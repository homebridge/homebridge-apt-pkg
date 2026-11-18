#!/usr/bin/env bash
#
# Tests for deb/debian/postinst (the script apt runs after the files are unpacked).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake systemctl adduser addgroup usermod ufw chown hostname npm getent
fake_runuser
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

section "upgrade: the saved plugin list is not valid JSON"
sandbox_new bad-saved
upgrade_from '{"dependencies":{"homebridge-foo":"^1.2.3",}}'
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_json "$(LIST)" '.dependencies == {"homebridge":"2.5.0","homebridge-bar":"4.5.6","homebridge-foo":"1.2.3"}' \
  "the list is rebuilt from the installed plugins, and is never left empty"
assert_exists "$(STATE)/package.json.not-merged" "the bad copy is kept for the user"
assert_contains "$OUT" "WARNING: the saved plugin list is not valid JSON" "it prints a warning"

section "upgrade: the saved plugin list is JSON, but not a plugin list"
sandbox_new array-saved
upgrade_from '[1,2,3]'
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_json "$(LIST)" '.dependencies | keys == ["homebridge","homebridge-bar","homebridge-foo"]' "the list is rebuilt from the installed plugins"

section "upgrade: an old install that lists the UI, and a % inside a value"
sandbox_new percent
upgrade_from '{"dependencies":{"homebridge-config-ui-x":"^4.50.0","homebridge-foo":"https://example.com/my%20plugin.tgz","homebridge-bar":"1.0.0\\n"}}'
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_json "$(LIST)" '.dependencies == {"homebridge":"2.5.0","homebridge-foo":"https://example.com/my%20plugin.tgz","homebridge-bar":"1.0.0\\n"}' \
  "the UI is taken out, and every other value is unchanged"

section "upgrade: a * and several spaces inside a value"
sandbox_new star
touch "$ROOT/cwd/FILE_ONE" "$ROOT/cwd/FILE_TWO"
upgrade_from '{"dependencies":{"homebridge-foo":"1.0.0"},"description":"a * b   c"}'
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_json "$(LIST)" '.description == "a * b   c"' "the text is unchanged"
assert_contains "$(stublog)" "[npm] --prefix /var/lib/homebridge install" "the plugins are refreshed"

section "upgrade: npm runs as the service user, and root never loads files from /opt/homebridge"
sandbox_new as-user
# a hook file that a plugin could have planted; it notes who loads it
# shellcheck disable=SC2016 # the text is the content of the hook file
echo 'echo "hook loaded, as the service user: ${INSIDE_RUNUSER:-0}" >> "$ROOT/hook.log"' > "$ROOT/opt/homebridge/source-vm.sh"
upgrade_from '{"dependencies":{"homebridge":"2.4.0","homebridge-foo":"^1.2.3"}}'
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_contains "$(stublog)" "[runuser] -u homebridge -- env HOME=" "npm is started through runuser, as the service user"
assert_contains "$(stublog)" "[npm] --prefix /var/lib/homebridge install" "npm install runs"
assert_contains "$(stublog)" "[npm] --prefix /var/lib/homebridge rebuild" "npm rebuild runs"
assert_contains "$(stublog)" "[chown] -R homebridge: /var/lib/homebridge" "the storage folder is given to the service user first"
assert_eq "hook loaded, as the service user: 1" "$(sort -u "$ROOT/hook.log")" "the hook file is only ever loaded as the service user"

finish
