#!/usr/bin/env bash
#
# Tests for deb/opt/homebridge/hb-service-shim (the "hb-service" command, run with sudo).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake systemctl sudo runuser chown tail getent
fake_root_id
SHIM=$(sandbox_script deb/opt/homebridge/hb-service-shim)
MODULES() { printf '%s\n' "$ROOT/var/lib/homebridge/node_modules"; }

# dev_folder <name in package.json>: a plugin source folder; $DEV is its path
dev_folder() {
  DEV="$ROOT/dev/plugin"
  mkdir -p "$DEV"
  printf '%s\n' "$1" > "$DEV/package.json"
}

section "unlink: package.json in the current folder is not valid JSON"
sandbox_new unlink-bad-json
dev_folder '{"name":"homebridge-foo",}'
run_in "$DEV" "$BASH" "$SHIM" unlink
assert_eq "homebridge homebridge-bar homebridge-foo" "$(plugins)" "no plugin is deleted"
assert_contains "$OUT" "Could not read plugin name" "it prints an error"
assert_eq 1 "$STATUS" "exit code 1"

section "unlink: no name in package.json"
sandbox_new unlink-no-name
dev_folder '{"version":"1.0.0"}'
run_in "$DEV" "$BASH" "$SHIM" unlink
assert_eq "homebridge homebridge-bar homebridge-foo" "$(plugins)" "no plugin is deleted"
assert_eq 1 "$STATUS" "exit code 1"

section "unlink: the plugin is installed normally and was never linked"
sandbox_new unlink-not-linked
dev_folder '{"name":"homebridge-foo"}'
run_in "$DEV" "$BASH" "$SHIM" unlink
assert_exists "$(MODULES)/homebridge-foo/package.json" "the installed plugin is kept"
assert_contains "$OUT" "it is not linked. Nothing was removed." "it says why"
assert_eq 1 "$STATUS" "exit code 1"

section "unlink: a name with ../ in it"
sandbox_new unlink-dotdot
mkdir -p "$ROOT/etc-important"
dev_folder '{"name":"../../../../etc-important"}'
run_in "$DEV" "$BASH" "$SHIM" unlink
assert_exists "$ROOT/etc-important" "the folder outside node_modules is kept"
assert_contains "$OUT" "is not a valid plugin name" "it says why"
assert_eq 1 "$STATUS" "exit code 1"

section "unlink: the link points at another folder"
sandbox_new unlink-other
dev_folder '{"name":"homebridge-dev"}'
mkdir -p "$ROOT/dev/other"
ln -s "$ROOT/dev/other" "$(MODULES)/homebridge-dev"
run_in "$DEV" "$BASH" "$SHIM" unlink
assert_exists "$(MODULES)/homebridge-dev" "the link is kept"
assert_eq 1 "$STATUS" "exit code 1"

section "link then unlink: the normal case still works"
sandbox_new link-unlink
dev_folder '{"name":"@scope/homebridge-dev"}'
run_in "$DEV" "$BASH" "$SHIM" link
assert_contains "$OUT" "Success: @scope/homebridge-dev linked" "link reports success"
assert_eq "$(realpath "$DEV")" "$(realpath "$(MODULES)/@scope/homebridge-dev")" "the link points at the source folder"
run_in "$DEV" "$BASH" "$SHIM" unlink
assert_contains "$OUT" "Success: @scope/homebridge-dev unlinked" "unlink reports success"
assert_missing "$(MODULES)/@scope/homebridge-dev" "the link is gone"
assert_exists "$DEV/package.json" "the source folder is untouched"

section "link: the plugin is already installed as a normal plugin"
sandbox_new link-installed
dev_folder '{"name":"homebridge-foo"}'
run_in "$DEV" "$BASH" "$SHIM" link
assert_eq 1 "$STATUS" "exit code 1 (the old code said Success and linked nothing)"
assert_contains "$OUT" "Remove the installed plugin first: hb-service remove homebridge-foo" "it says what to do"
assert_missing "$(MODULES)/homebridge-foo/plugin" "no link is put inside the installed folder"
assert_exists "$(MODULES)/homebridge-foo/package.json" "the installed plugin is untouched"

section "link: the plugin is linked to another folder"
sandbox_new link-replace
dev_folder '{"name":"homebridge-dev"}'
mkdir -p "$ROOT/dev/old-copy"
ln -s "$ROOT/dev/old-copy" "$(MODULES)/homebridge-dev"
run_in "$DEV" "$BASH" "$SHIM" link
assert_eq "$(realpath "$DEV")" "$(realpath "$(MODULES)/homebridge-dev")" "the link now points at the current folder"
assert_missing "$ROOT/dev/old-copy/plugin" "no link is put inside the old folder"
run_in "$DEV" "$BASH" "$SHIM" link
assert_contains "$OUT" "is already linked" "linking the same folder twice is reported"

section "link: a name with ../ in it"
sandbox_new link-dotdot
dev_folder '{"name":"../../escape"}'
run_in "$DEV" "$BASH" "$SHIM" link
assert_missing "$ROOT/var/lib/escape" "nothing is created outside node_modules"
assert_eq 1 "$STATUS" "exit code 1"

section "commands that run as the service user do not need sudo"
sandbox_new no-sudo
run_in "$ROOT/cwd" "$BASH" "$SHIM" status
assert_contains "$(stublog)" "[runuser] -u homebridge -- env -i HOME=" "status: runuser starts the command as the service user"
assert_contains "$(stublog)" " USER=homebridge LOGNAME=homebridge SHELL=/bin/bash PATH=" "status: with a clean environment"
for command in add remove update-node rebuild; do
  : > "$STUBLOG"
  run_in "$ROOT/cwd" "$BASH" "$SHIM" "$command" something
  assert_contains "$(stublog)" "[runuser] -u homebridge --" "$command: uses runuser"
done
assert_not_contains "$(cat "$REPO/deb/opt/homebridge/hb-service-shim" "$REPO/deb/opt/homebridge/hb-shell")" "exec sudo" "sudo is not used by hb-service or hb-shell"

section "hb-shell does not need sudo"
sandbox_new shell-no-sudo
HB_SHELL=$(sandbox_script deb/opt/homebridge/hb-shell)
run_in "$ROOT/cwd" sh "$HB_SHELL"
assert_contains "$(stublog)" "[runuser] -u homebridge -- env -i HOME=" "runuser starts the shell as the service user"
assert_contains "$(stublog)" "bash --rcfile /opt/homebridge/bashrc-hb-shell" "with the Homebridge shell settings"

section "the package declares what its scripts need"
control="$REPO/deb/debian/control"
depends=$(grep '^Depends:' "$control")
pre_depends=$(grep '^Pre-Depends:' "$control")
assert_contains "$depends" "adduser" "adduser (used by postinst) is a dependency"
for tool in jq psmisc; do
  assert_contains "$pre_depends" "$tool" "$tool (used by preinst) must be set up before unpacking"
done
for tool in gcc g++ make python3-dev; do
  assert_contains "$depends" "$tool" "$tool is a normal dependency"
  assert_not_contains "$pre_depends" "$tool" "$tool does not have to be set up before unpacking"
done

section "arguments keep their quoting"
sandbox_new quoting
# a runuser that writes every argument it gets on its own line
fake_script runuser << 'EOF'
#!/bin/sh
for argument in "$@"; do echo "[argument] $argument" >> "$STUBLOG"; done
EOF
run_in "$ROOT/cwd" "$BASH" "$SHIM" add 'homebridge-foo@>=2.0.0' 'two words'
log=$(stublog)
# shellcheck disable=SC2016 # the text is the command line that bash gets
assert_contains "$log" '/var/lib/homebridge "$@"' "add: the command is fixed text, with no user input in it"
assert_contains "$log" "
[argument] add
[argument] homebridge-foo@>=2.0.0
[argument] two words" "add: each argument arrives as one argument"
: > "$STUBLOG"
run_in "$ROOT/cwd" "$BASH" "$SHIM" update-node '24.22.3; touch /tmp/oops'
assert_contains "$(stublog)" "
[argument] update-node
[argument] 24.22.3; touch /tmp/oops" "update-node: shell characters stay inside the argument"
fake runuser

section "status: the port of the UI"
# a runuser that writes every argument it gets on its own line
fake_script runuser << 'EOF'
#!/bin/sh
for argument in "$@"; do echo "[argument] $argument" >> "$STUBLOG"; done
EOF
# status_port <config.json content>: the port that "hb-service status" checks
status_port() {
  sandbox_new "port-$RANDOM"
  [ -n "$1" ] && printf '%s\n' "$1" > "$ROOT/var/lib/homebridge/config.json"
  run_in "$ROOT/cwd" "$BASH" "$SHIM" status
  tail -n 1 "$STUBLOG" | sed 's/^\[argument\] //'
}
assert_eq "8581" "$(status_port '')" "no config.json: 8581"
assert_eq "8080" "$(status_port '{"platforms":[{"platform":"config","port":8080}]}')" "a port in the UI block is used"
assert_eq "8581" "$(status_port '{"platforms":[{"platform":"config"}]}')" "a UI block without a port: 8581 (the old code used the word null)"
assert_eq "8581" "$(status_port '{"platforms":[{"platform":"config","port":"80; reboot"}]}')" "a port that is not a number: 8581"
assert_eq "8581" "$(status_port '{"bridge":{}}')" "a config without platforms: 8581"
assert_eq "8581" "$(status_port 'not json')" "a config.json that is not valid JSON: 8581"
fake runuser

section "-V prints the Homebridge version, for Homebridge 1 and 2"
sandbox_new version
run_in "$ROOT/cwd" "$BASH" "$SHIM" -V
assert_eq "2.5.0" "$OUT" "the version comes from the installed files"
assert_eq 0 "$STATUS" "exit code 0"
rm -rf "$(MODULES)/homebridge"
run_in "$ROOT/cwd" "$BASH" "$SHIM" -V
assert_eq 1 "$STATUS" "exit code 1 when Homebridge is not installed"

section "-D starts nothing"
sandbox_new debug
run_in "$ROOT/cwd" "$BASH" "$SHIM" -D
assert_eq 1 "$STATUS" "exit code 1"
assert_contains "$OUT" "Homebridge Debug Mode" "it says where the debug switch is"
assert_eq "" "$(stublog)" "no second Homebridge is started as root"

finish
