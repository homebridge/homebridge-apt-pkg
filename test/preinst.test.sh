#!/usr/bin/env bash
#
# Tests for deb/debian/preinst (the script apt runs before the new files are unpacked).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake pstree chown curl
fake_systemctl
PREINST=$(sandbox_script deb/debian/preinst)
STATE() { printf '%s\n' "$ROOT/var/lib/homebridge-apt-pkg"; }
LIST() { printf '%s\n' "$ROOT/var/lib/homebridge/package.json"; }

section "upgrade: the plugin list is saved in a folder only root can write to"
sandbox_new save
echo '{"dependencies":{"homebridge":"2.4.0","homebridge-foo":"^1.2.3"}}' > "$(LIST)"
run_in "$ROOT/cwd" "$BASH" "$PREINST" upgrade 2.0.25
assert_json "$(STATE)/package.json.saved" '.dependencies["homebridge-foo"] == "^1.2.3"' "the copy is in /var/lib/homebridge-apt-pkg"
assert_eq "700" "$(stat -c %a "$(STATE)" 2> /dev/null || stat -f %Lp "$(STATE)")" "the folder has mode 700"
assert_contains "$(stublog)" "[chown] root:root /var/lib/homebridge-apt-pkg" "the folder is given to root"
assert_missing "$ROOT/tmp/homebridge-tmp" "nothing is written to /tmp"

section "upgrade: the state folder is a link to somewhere else"
sandbox_new state-link
mkdir -p "$ROOT/somewhere-else"
ln -s "$ROOT/somewhere-else" "$(STATE)"
echo '{"dependencies":{"homebridge":"2.4.0"}}' > "$(LIST)"
run_in "$ROOT/cwd" "$BASH" "$PREINST" upgrade 2.0.25
assert_missing "$ROOT/somewhere-else/package.json.saved" "nothing is written through the link"
assert_contains "$OUT" "is not a normal folder" "it prints a warning"
assert_eq 0 "$STATUS" "the upgrade itself carries on"

section "upgrade: package.json in the storage folder is a link"
sandbox_new list-link
echo 'secret' > "$ROOT/etc/secret"
ln -s "$ROOT/etc/secret" "$(LIST)"
run_in "$ROOT/cwd" "$BASH" "$PREINST" upgrade 2.0.25
assert_missing "$(STATE)/package.json.saved" "the target of the link is not copied"

section "install over an old 'hb-service install' set-up: the plugins are brought over"
sandbox_new migrate
GLOBAL="$ROOT/opt/custom/lib/node_modules" # where the old unit runs the UI from
mkdir -p "$ROOT/etc/systemd/system" "$GLOBAL/homebridge-config-ui-x" "$GLOBAL/homebridge" "$GLOBAL/homebridge-hue" \
  "$GLOBAL/@scope/homebridge-scoped" "$GLOBAL/npm" "$ROOT/usr/lib/node_modules/homebridge-other"
printf '[Service]\nExecStart=%s/homebridge-config-ui-x/dist/bin/hb-service.js run -U /var/lib/homebridge\n' "$GLOBAL" > "$ROOT/etc/systemd/system/homebridge.service"
echo '{"name":"homebridge-config-ui-x","version":"4.50.0"}' > "$GLOBAL/homebridge-config-ui-x/package.json"
echo '{"name":"homebridge","version":"1.6.0"}' > "$GLOBAL/homebridge/package.json"
echo '{"name":"homebridge-hue","version":"0.13.1"}' > "$GLOBAL/homebridge-hue/package.json"
echo '{"name":"@scope/homebridge-scoped","version":"2.0.0"}' > "$GLOBAL/@scope/homebridge-scoped/package.json"
echo '{"name":"npm","version":"9.0.0"}' > "$GLOBAL/npm/package.json"
echo '{"name":"homebridge-other","version":"3.2.1"}' > "$ROOT/usr/lib/node_modules/homebridge-other/package.json"
rm -rf "$ROOT/var/lib/homebridge/node_modules"
echo '{"bridge":{}}' > "$ROOT/var/lib/homebridge/config.json"
run_in "$ROOT/cwd" "$BASH" "$PREINST" install
assert_json "$(STATE)/package.json.saved" \
  '.dependencies == {"homebridge-hue":"0.13.1","@scope/homebridge-scoped":"2.0.0","homebridge-other":"3.2.1"}' \
  "the old plugins and their versions are saved for postinst (not Homebridge, the UI or npm)"
assert_not_contains "$(stublog)" "[curl]" "the running UI is not asked (that needs a login token it refuses)"
assert_missing "$ROOT/etc/systemd/system/homebridge.service" "the old unit file is removed"

section "install over an old set-up that has no plugins"
sandbox_new migrate-none
mkdir -p "$ROOT/etc/systemd/system"
echo '[Service]' > "$ROOT/etc/systemd/system/homebridge.service"
rm -rf "$ROOT/var/lib/homebridge/node_modules"
echo '{"bridge":{}}' > "$ROOT/var/lib/homebridge/config.json"
run_in "$ROOT/cwd" "$BASH" "$PREINST" install
assert_missing "$(STATE)/package.json.saved" "no plugin list is saved"
assert_eq 0 "$STATUS" "exit code 0"

finish
