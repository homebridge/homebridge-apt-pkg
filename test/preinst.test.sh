#!/usr/bin/env bash
#
# Tests for deb/debian/preinst (the script apt runs before the new files are unpacked).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake systemctl pstree chown curl
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

finish
