#!/usr/bin/env bash
#
# Tests for deb/debian/postinst (the script apt runs after the files are unpacked).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake systemctl adduser addgroup usermod ufw chown hostname npm getent
POSTINST=$(sandbox_script deb/debian/postinst)
NEW='{"dependencies":{"homebridge":"2.5.0"}}' # the plugin list the new package ships

section "upgrade: the saved plugin list is merged into the new one"
sandbox_new merge
mkdir -p "$ROOT/tmp/homebridge-tmp"
echo '{"dependencies":{"homebridge":"2.4.0","homebridge-foo":"^1.2.3"}}' > "$ROOT/tmp/homebridge-tmp/package.json"
echo "$NEW" > "$ROOT/var/lib/homebridge/package.json"
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_json "$ROOT/var/lib/homebridge/package.json" '.dependencies == {"homebridge":"2.5.0","homebridge-foo":"^1.2.3"}' \
  "the user's plugin is kept and Homebridge is the new version"

finish
