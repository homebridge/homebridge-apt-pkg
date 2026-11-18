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

finish
