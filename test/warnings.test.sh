#!/usr/bin/env bash
#
# The package scripts always end with exit code 0, so apt never stops half-way.
# These tests check that a step that fails is at least reported with a clear WARNING line.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake pstree chown addgroup usermod ufw hostname npm
fake_systemctl
fake_runuser
POSTINST=$(sandbox_script deb/debian/postinst)
unpacked() { echo '{"dependencies":{"homebridge":"2.5.0"}}' > "$ROOT/var/lib/homebridge/package.json"; }

section "everything works: no warning"
fake adduser getent
sandbox_new fine
mkdir -p "$ROOT/run/systemd/system"
unpacked
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure
assert_eq 0 "$STATUS" "exit code 0"
assert_not_contains "$OUT" "WARNING" "no warning is printed"

section "the service user can not be created"
fake_failing adduser getent
sandbox_new no-user
unpacked
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure
assert_eq 0 "$STATUS" "exit code 0 (apt carries on)"
assert_contains "$OUT" "WARNING: could not create the 'homebridge' user" "a warning says so"
fake adduser getent

section "the service does not start"
sandbox_new no-start
mkdir -p "$ROOT/run/systemd/system"
unpacked
FAKE_SYSTEMCTL_FAILS="restart enable" run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure
assert_eq 0 "$STATUS" "exit code 0"
assert_contains "$OUT" "WARNING: the Homebridge service did not start. To see why: journalctl -u homebridge" "a warning says so, and where to look"
assert_contains "$OUT" "WARNING: could not enable the Homebridge service" "a failed enable is reported too"

section "npm fails while the plugins are refreshed (no network)"
sandbox_new npm-fails
mkdir -p "$ROOT/var/lib/homebridge-apt-pkg"
echo '{"dependencies":{"homebridge":"2.4.0","homebridge-foo":"^1.2.3"}}' > "$ROOT/var/lib/homebridge-apt-pkg/package.json.saved"
unpacked
# shellcheck disable=SC2016 # the text is the content of the fake npm
printf '#!/bin/sh\necho "[npm] $*" >> "$STUBLOG"\nexit 1\n' > "$ROOT/opt/homebridge/bin/npm"
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_eq 0 "$STATUS" "exit code 0"
assert_contains "$OUT" "WARNING: npm could not refresh the plugins" "a warning says so"
assert_json "$ROOT/var/lib/homebridge/package.json" '.dependencies["homebridge-foo"] == "^1.2.3"' "the plugin list is still merged"

finish
