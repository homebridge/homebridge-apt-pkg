#!/usr/bin/env bash
#
# Shared helpers for the tests in this folder. Each "*.test.sh" file sources this file.
#
# How the sandbox works:
# - A script from the package is copied and its absolute paths are rewritten, so that
#   /var/lib/homebridge becomes $ROOT/var/lib/homebridge and so on. Nothing on the real
#   machine is touched, and no root rights are needed.
# - Fake commands (systemctl, npm, adduser ...) are put first on the PATH. They only write
#   the arguments they were given to $STUBLOG.
#
# Needs: bash 4 or newer, jq, git. Run everything with: test/run.sh

# SC2016: the fake commands and the path rewrite hold "$..." text that must not expand here.
# SC2034: OUT and STATUS are read by the test files.
# shellcheck disable=SC2016,SC2034

set -u

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$TEST_DIR/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/hb-apt-test.XXXXXX")
FAKEBIN="$WORK/bin"
REAL_PATH="$PATH"
FAILS=0
CHECKS=0
OUT=""
STATUS=0

mkdir -p "$FAKEBIN" "$WORK/scripts"
trap 'rm -rf "$WORK"' EXIT

# ---- results -----------------------------------------------------------------------------

section() { printf '\n== %s\n' "$*"; }

ok() {
  CHECKS=$((CHECKS + 1))
  printf '  ok    %s\n' "$1"
}

fail() {
  CHECKS=$((CHECKS + 1))
  FAILS=$((FAILS + 1))
  printf '  FAIL  %s\n' "$1"
  shift
  [ "$#" -gt 0 ] && printf '        %s\n' "$@"
  return 0
}

# assert_eq <expected> <actual> <what>
assert_eq() {
  if [ "$1" = "$2" ]; then ok "$3"; else fail "$3" "expected: $1" "actual:   $2"; fi
}

# assert_contains <text> <needle> <what>
assert_contains() {
  case "$1" in
    *"$2"*) ok "$3" ;;
    *) fail "$3" "did not find: $2" "in: $1" ;;
  esac
}

# assert_not_contains <text> <needle> <what>
assert_not_contains() {
  case "$1" in
    *"$2"*) fail "$3" "found: $2" "in: $1" ;;
    *) ok "$3" ;;
  esac
}

# assert_exists <path> <what> / assert_missing <path> <what>
assert_exists() { if [ -e "$1" ] || [ -L "$1" ]; then ok "$2"; else fail "$2" "missing: $1"; fi; }
assert_missing() { if [ -e "$1" ] || [ -L "$1" ]; then fail "$2" "still there: $1"; else ok "$2"; fi; }

# assert_json <file> <jq filter that must be true> <what>
assert_json() {
  if jq -e "$2" "$1" > /dev/null 2>&1; then
    ok "$3"
  else
    fail "$3" "jq filter not true: $2" "file: $(head -c 400 "$1" 2> /dev/null)"
  fi
}

# yaml_json <file>: print a YAML file as JSON, for jq. Needs python3 with PyYAML.
# (The YAML key "on" comes out as "true". That is how YAML 1.1 reads it.)
yaml_json() {
  python3 -c 'import sys, json, yaml; json.dump(yaml.safe_load(open(sys.argv[1])), sys.stdout)' "$1"
}

finish() {
  printf '\n%s: %d checks, %d failed\n' "$(basename "$0")" "$CHECKS" "$FAILS"
  [ "$FAILS" -eq 0 ]
}

# ---- fake commands -----------------------------------------------------------------------

# fake <name>...: a command that writes "[name] args" to $STUBLOG and exits 0
fake() {
  local c
  for c in "$@"; do
    printf '#!/bin/sh\necho "[%s] $*" >> "$STUBLOG"\nexit 0\n' "$c" > "$FAKEBIN/$c"
    chmod +x "$FAKEBIN/$c"
  done
}

# fake_script <name>: a fake command with its own body, read from standard input
fake_script() {
  cat > "$FAKEBIN/$1"
  chmod +x "$FAKEBIN/$1"
}

# fake_systemctl: logs like the others, and answers the questions the scripts ask.
#   FAKE_ACTIVE=0   "is-active" says the service is not running   (default: running)
#   FAKE_ENABLED=0  "is-enabled" says no                           (default: yes)
fake_systemctl() {
  fake_script systemctl << 'EOF'
#!/bin/sh
echo "[systemctl] $*" >> "$STUBLOG"
case "$1" in
  is-active) [ "${FAKE_ACTIVE:-1}" = "1" ] ;;
  is-enabled) [ "${FAKE_ENABLED:-1}" = "1" ] ;;
  *) exit 0 ;;
esac
EOF
}

# fake_runuser: logs, then runs the command that follows "--" (as the current user).
# INSIDE_RUNUSER=1 is set for that command, so a test can tell what ran "as the service user".
fake_runuser() {
  fake_script runuser << 'EOF'
#!/bin/sh
echo "[runuser] $*" >> "$STUBLOG"
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
shift
INSIDE_RUNUSER=1 exec "$@"
EOF
}

# the package scripts refuse to run unless "id -u" prints 0
fake_root_id() {
  fake_script id << 'EOF'
#!/bin/sh
if [ "$1" = "-u" ] && [ "$#" -eq 1 ]; then echo 0; exit 0; fi
PATH="$REAL_PATH" exec id "$@"
EOF
}

# ---- sandbox -----------------------------------------------------------------------------

# rewrite <file>: print the file with its absolute paths moved under $ROOT
rewrite() {
  sed -E \
    -e 's#(^|[^A-Za-z0-9_./$}-])/(var|opt|etc|tmp|home|run)/#\1$ROOT/\2/#g' \
    -e 's#(^|[^A-Za-z0-9_./$}-])/usr/(local|bin|sbin|lib|share)/#\1$ROOT/usr/\2/#g' \
    "$1"
}

# sandbox_script <path in repo>: make the rewritten copy, print where it is
sandbox_script() {
  local dest
  dest="$WORK/scripts/$(basename "$1")"
  rewrite "$REPO/$1" > "$dest"
  chmod +x "$dest"
  printf '%s\n' "$dest"
}

# sandbox_new <name>: a fresh fake system under $ROOT, with three "plugins" installed
sandbox_new() {
  ROOT="$WORK/root-$1"
  STUBLOG="$ROOT/stub.log"
  export ROOT STUBLOG REAL_PATH
  rm -rf "$ROOT"
  mkdir -p \
    "$ROOT/var/lib/homebridge/node_modules/homebridge" \
    "$ROOT/var/lib/homebridge/node_modules/homebridge-foo" \
    "$ROOT/var/lib/homebridge/node_modules/homebridge-bar" \
    "$ROOT/etc" "$ROOT/tmp" "$ROOT/run" \
    "$ROOT/usr/local/bin" "$ROOT/usr/bin" "$ROOT/usr/sbin" "$ROOT/home/homebridge" "$ROOT/cwd"
  : > "$STUBLOG"
  echo '{"name":"homebridge","version":"2.5.0"}' > "$ROOT/var/lib/homebridge/node_modules/homebridge/package.json"
  echo '{"name":"homebridge-foo","version":"1.2.3"}' > "$ROOT/var/lib/homebridge/node_modules/homebridge-foo/package.json"
  echo '{"name":"homebridge-bar","version":"4.5.6"}' > "$ROOT/var/lib/homebridge/node_modules/homebridge-bar/package.json"
  sandbox_unpack_opt
}

# sandbox_unpack_opt: put the files the package ships into $ROOT/opt/homebridge
sandbox_unpack_opt() {
  local shipped
  mkdir -p "$ROOT/opt/homebridge/bin"
  for shipped in "$REPO"/deb/opt/homebridge/*; do
    rewrite "$shipped" > "$ROOT/opt/homebridge/$(basename "$shipped")"
    chmod +x "$ROOT/opt/homebridge/$(basename "$shipped")"
  done
  echo '{"dependencies":{"homebridge":"2.5.0","homebridge-config-ui-x":"5.30.1","node":"26.13.1"}}' > "$ROOT/opt/homebridge/package.json"
  printf '#!/bin/sh\necho "[node] $*" >> "$STUBLOG"\n' > "$ROOT/opt/homebridge/bin/node"
  printf '#!/bin/sh\necho "[npm] $*" >> "$STUBLOG"\n' > "$ROOT/opt/homebridge/bin/npm"
  chmod +x "$ROOT/opt/homebridge/bin/node" "$ROOT/opt/homebridge/bin/npm"
}

# plugins: the names in the sandbox plugin folder, on one line
plugins() {
  local names
  names=$(cd "$ROOT/var/lib/homebridge/node_modules" 2> /dev/null && ls)
  printf '%s' "${names//$'\n'/ }"
}

# stublog: what the fake commands were called with, with the sandbox path removed
stublog() { sed "s#$ROOT##g" "$STUBLOG"; }

# run_in <folder> <interpreter> <script> [args]: run with the fake commands first on the PATH.
# Sets $OUT (standard output and errors together, sandbox path removed) and $STATUS.
run_in() {
  local dir="$1" shell="$2" script="$3"
  shift 3
  OUT=$(cd "$dir" && PATH="$FAKEBIN:$REAL_PATH" "$shell" "$script" "$@" 2>&1)
  STATUS=$?
  OUT=${OUT//"$ROOT"/}
}
