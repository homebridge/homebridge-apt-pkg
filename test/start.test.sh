#!/usr/bin/env bash
#
# Tests for deb/opt/homebridge/start.sh (runs at every start of the service, as the service user).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake npm
START=$(sandbox_script deb/opt/homebridge/start.sh)
LIST() { printf '%s\n' "$ROOT/var/lib/homebridge/package.json"; }

section "a normal start changes nothing"
sandbox_new normal
echo '{"dependencies":{"homebridge":"2.5.0","homebridge-foo":"^1.2.3"}}' > "$(LIST)"
run_in "$ROOT/cwd" sh "$START"
assert_json "$(LIST)" '.dependencies == {"homebridge":"2.5.0","homebridge-foo":"^1.2.3"}' "the plugin list is untouched"
assert_contains "$(stublog)" "[node] /opt/homebridge/lib/node_modules/homebridge-config-ui-x/dist/bin/hb-service.js run" "the service is started"
assert_not_contains "$(stublog)" "[npm]" "npm is not called"

section "the plugin list is cut short (power loss): plugins are kept"
sandbox_new cut
mkdir -p "$ROOT/var/lib/homebridge/node_modules/@scope/homebridge-scoped" "$ROOT/dev/homebridge-linked"
echo '{"name":"@scope/homebridge-scoped","version":"7.8.9"}' > "$ROOT/var/lib/homebridge/node_modules/@scope/homebridge-scoped/package.json"
echo '{"name":"homebridge-linked","version":"0.0.1"}' > "$ROOT/dev/homebridge-linked/package.json"
ln -s "$ROOT/dev/homebridge-linked" "$ROOT/var/lib/homebridge/node_modules/homebridge-linked"
printf '{"dependencies":{"homebridge":"2.5.0","homebridge-foo":"1.0' > "$(LIST)"
run_in "$ROOT/cwd" sh "$START"
assert_eq "@scope homebridge homebridge-bar homebridge-foo homebridge-linked" "$(plugins)" "every plugin folder is still there"
assert_json "$(LIST)" \
  '.dependencies == {"@scope/homebridge-scoped":"7.8.9","homebridge":"2.5.0","homebridge-bar":"4.5.6","homebridge-foo":"1.2.3"}' \
  "the new list holds what is installed (a linked plugin is left out)"
broken=/dev/null
for f in "$ROOT/var/lib/homebridge"/package.json.broken-*; do [ -e "$f" ] && broken="$f"; done
assert_eq '{"dependencies":{"homebridge":"2.5.0","homebridge-foo":"1.0' "$(cat "$broken")" "the bad file is kept under another name"
assert_contains "$OUT" "No plugin is removed" "the log says what happened"
assert_not_contains "$(stublog)" "[npm]" "nothing is installed again"

section "the plugin list is an empty file"
sandbox_new empty
: > "$(LIST)"
run_in "$ROOT/cwd" sh "$START"
assert_eq "homebridge homebridge-bar homebridge-foo" "$(plugins)" "every plugin folder is still there"
assert_json "$(LIST)" '.dependencies | keys == ["homebridge","homebridge-bar","homebridge-foo"]' "a new list is written"

section "the plugin list is valid JSON but not an object"
sandbox_new array
echo '[]' > "$(LIST)"
run_in "$ROOT/cwd" sh "$START"
assert_json "$(LIST)" '.dependencies | keys == ["homebridge","homebridge-bar","homebridge-foo"]' "a new list is written"

finish
