#!/usr/bin/env bash
#
# Tests for the pre-start script deb/etc/hb-service/homebridge/prestart.d/10-fix-permissions.
# It runs as root before every start, and decides who owns what.
#
# "chown" and "chmod" are fakes that only log. "find" is the real one, so the sandbox files
# need a real owner:
# - run as a normal user: that user plays the service user (the files are theirs already);
# - run as root (a container): "nobody" plays the service user, and the files are given to it.
# To see files handed over, the fake "id" names a group that the files are NOT in.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake chown chmod
if [ "$(id -u)" -eq 0 ]; then
  ME=nobody
  MY_GROUP=$(id -gn nobody)
  own_sandbox() { chown -R "$ME:$MY_GROUP" "$ROOT/var/lib/homebridge" "$ROOT/opt/homebridge"; }
else
  ME=$(id -un)
  MY_GROUP=$(id -gn)
  own_sandbox() { :; }
fi
OTHER_GROUP=$(awk -F: -v mine="$MY_GROUP" '$1 != mine {print $1; exit}' /etc/group)
export FAKE_GROUP
fake_script id << 'EOF'
#!/bin/sh
if [ "$1" = "-gn" ]; then echo "$FAKE_GROUP"; exit 0; fi
PATH="$REAL_PATH" exec id "$@"
EOF
FIX=$(sandbox_script deb/etc/hb-service/homebridge/prestart.d/10-fix-permissions)

# new_install <name>: a sandbox with the Node.js runtime, the scripts and two extra files
new_install() {
  sandbox_new "$1"
  mkdir -p "$ROOT/opt/homebridge/lib/node_modules" "$ROOT/opt/homebridge/include" "$ROOT/opt/homebridge/share"
  touch "$ROOT/opt/homebridge/CHANGELOG.md" "$ROOT/opt/homebridge/LICENSE" "$ROOT/opt/homebridge/README.md" \
    "$ROOT/opt/homebridge/source-vm.sh" "$ROOT/opt/homebridge/.hidden"
  own_sandbox
}

section "files with the wrong owner or group: the service user gets the storage folder and the Node.js runtime, not the scripts"
new_install owner
FAKE_GROUP="$OTHER_GROUP" USER="$ME" run_in "$ROOT/cwd" sh "$FIX"
log=$(stublog)
given=$(printf '%s\n' "$log" | grep -F "[chown] -h $ME:$OTHER_GROUP ")
assert_contains "$given" " /var/lib/homebridge/node_modules/homebridge-foo/package.json" "storage folder: every file goes to the service user"
for entry in bin/npm lib/node_modules include share CHANGELOG.md LICENSE README.md; do
  assert_contains "$given" " /opt/homebridge/$entry" "$entry: service user"
done
for entry in hb-service-shim hb-shell source.sh start.sh bashrc bashrc-hb-shell rebuild-package-json.sh package.json source-vm.sh .hidden; do
  assert_contains "$log" "[chown] -h root:root /opt/homebridge/$entry" "$entry: root"
  assert_not_contains "$given" "/opt/homebridge/$entry" "$entry: never given to the service user"
done
assert_contains "$log" "[chown] root:$OTHER_GROUP /opt/homebridge" "the folder itself: root, with the service user's group"
assert_contains "$log" "[chmod] 1775 /opt/homebridge" "the folder is sticky: the service user can add files, not replace root's"
assert_not_contains "$log" "[chown] -R" "no blind recursive chown"

section "files that are right already are not written to again"
new_install unchanged
FAKE_GROUP="$MY_GROUP" USER="$ME" run_in "$ROOT/cwd" sh "$FIX"
assert_not_contains "$(stublog)" "[chown] -h $ME:" "no chown for the storage folder or the runtime (the old script ran chown -R over all of it on every start)"

section "when the service runs as root, nothing is changed"
new_install root
USER=root run_in "$ROOT/cwd" sh "$FIX"
assert_eq "" "$(stublog)" "no chown and no chmod"

section "the unit file"
unit=$(cat "$REPO/deb/debian/homebridge.service")
assert_not_contains "$unit" "syslog.target" "syslog.target (it does nothing on current systems) is not named"
assert_contains "$unit" "ExecStartPre=-/bin/run-parts /etc/hb-service/homebridge/prestart.d" "the pre-start scripts still run"
assert_contains "$unit" "PermissionsStartOnly=true" "and still run as root"

finish
