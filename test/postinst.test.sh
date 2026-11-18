#!/usr/bin/env bash
#
# Tests for deb/debian/postinst (the script apt runs after the files are unpacked).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake systemctl adduser addgroup usermod ufw chown hostname npm getent
POSTINST=$(sandbox_script deb/debian/postinst)
NEW='{"dependencies":{"homebridge":"2.5.0"}}' # the plugin list the new package ships
STATE() { printf '%s\n' "$ROOT/var/lib/homebridge-apt-pkg"; }
LIST() { printf '%s\n' "$ROOT/var/lib/homebridge/package.json"; }

# upgrade_from <saved plugin list>: the state after the new files were unpacked
upgrade_from() {
  mkdir -p "$(STATE)"
  printf '%s\n' "$1" > "$(STATE)/package.json.saved"
  echo "$NEW" > "$(LIST)"
}

section "upgrade: the saved plugin list is merged into the new one"
sandbox_new merge
upgrade_from '{"dependencies":{"homebridge":"2.4.0","homebridge-foo":"^1.2.3"}}'
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_json "$(LIST)" '.dependencies == {"homebridge":"2.5.0","homebridge-foo":"^1.2.3"}' \
  "the user's plugin is kept and Homebridge is the new version"
assert_missing "$(STATE)/package.json.saved" "the saved copy is removed after use"

section "upgrade: a file planted in /tmp/homebridge-tmp is not used"
sandbox_new planted
mkdir -p "$ROOT/tmp/homebridge-tmp"
echo '{"dependencies":{"evil-package":"1.0.0"}}' > "$ROOT/tmp/homebridge-tmp/package.json"
echo "$NEW" > "$(LIST)"
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_json "$(LIST)" '.dependencies == {"homebridge":"2.5.0"}' "the plugin list is what the package shipped"
assert_not_contains "$(stublog)" "[npm]" "npm is not run"

finish
