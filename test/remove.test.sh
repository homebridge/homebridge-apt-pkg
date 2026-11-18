#!/usr/bin/env bash
#
# "apt remove" followed by "apt install" must bring the plugins back.
# Order of the scripts, as dpkg runs them:
#   remove:   prerm remove -> the package's files are deleted -> postrm remove
#   install:  preinst install -> the new files are unpacked -> postinst configure

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake pstree chown adduser addgroup usermod ufw hostname npm getent
fake_systemctl
PRERM=$(sandbox_script deb/debian/prerm)
POSTRM=$(sandbox_script deb/debian/postrm)
fake_runuser
POSTINST=$(sandbox_script deb/debian/postinst)
STORAGE() { printf '%s\n' "$ROOT/var/lib/homebridge"; }
STATE() { printf '%s\n' "$ROOT/var/lib/homebridge-apt-pkg"; }

section "remove: the plugin list is saved before dpkg deletes package.json"
sandbox_new remove
echo '{"dependencies":{"homebridge":"2.5.0","homebridge-foo":"^1.2.3","homebridge-bar":"4.5.6"}}' > "$(STORAGE)/package.json"
echo '{"bridge":{}}' > "$(STORAGE)/config.json"
run_in "$ROOT/cwd" "$BASH" "$PRERM" remove
assert_json "$(STATE)/package.json.saved" '.dependencies | keys == ["homebridge","homebridge-bar","homebridge-foo"]' "a copy of the list is kept"
rm -f "$(STORAGE)/package.json" # dpkg deletes the package's files
run_in "$ROOT/cwd" "$BASH" "$POSTRM" remove
assert_exists "$(STORAGE)/config.json" "config.json is kept"
assert_exists "$(STATE)/package.json.saved" "the saved list is still there after the remove"

section "install again: the saved list is merged back and the plugins are installed"
assert_missing "$ROOT/opt/homebridge" "/opt/homebridge is removed"
sandbox_unpack_opt # dpkg unpacks the new files
echo '{"dependencies":{"homebridge":"2.5.1"}}' > "$(STORAGE)/package.json"
: > "$STUBLOG"
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.26
assert_json "$(STORAGE)/package.json" '.dependencies == {"homebridge":"2.5.1","homebridge-foo":"^1.2.3","homebridge-bar":"4.5.6"}' \
  "the plugins are in the list again, with the new Homebridge version"
assert_contains "$(stublog)" "[npm] --prefix /var/lib/homebridge install" "npm installs them"

section "an upgrade does not go through the remove steps"
sandbox_new upgrade
echo '{"dependencies":{"homebridge":"2.5.0"}}' > "$(STORAGE)/package.json"
run_in "$ROOT/cwd" "$BASH" "$PRERM" upgrade 2.0.27
assert_missing "$(STATE)/package.json.saved" "prerm upgrade saves nothing (preinst does that)"

section "purge: the saved list is deleted too"
sandbox_new purge
mkdir -p "$(STATE)"
echo '{}' > "$(STATE)/package.json.saved"
run_in "$ROOT/cwd" "$BASH" "$POSTRM" purge
assert_missing "$(STATE)" "/var/lib/homebridge-apt-pkg is gone"
assert_missing "$(STORAGE)" "/var/lib/homebridge is gone"

finish
