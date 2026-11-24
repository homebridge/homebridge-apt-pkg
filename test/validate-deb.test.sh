#!/usr/bin/env bash
#
# Tests for pieces of test/e2e/validate-deb.sh (the check a package must pass before it is published).
#
# The whole script needs root and a real install, so only its small helpers are run here: they are
# cut out of the script and run with a fake apt-get.

# SC2016: the text looked for holds "$..." that must not expand here.
# SC2317, SC2329: the fake apt-get is called by install_deb, which is cut out of the script at run
# time (shellcheck 0.11 reports an uncalled function as SC2329, older versions as SC2317).
# shellcheck disable=SC2016,SC2317,SC2329

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$REPO/test/e2e/validate-deb.sh"
LOG="$WORK/homebridge.log"
die() { echo "die: $*"; return 1; }

# log_lines, homebridge_started_after, LOG_MARK and install_deb, as the script defines them
eval "$(sed -n -e '/^log_lines() /p' -e '/^homebridge_started_after() /p' -e '/^LOG_MARK=/p' -e '/^install_deb() {$/,/^}$/p' "$SCRIPT")"

section "the package starts Homebridge during the install (systemd)"
printf 'a line from before the install\n' > "$LOG"
# With systemd, the service is started by the package scripts, so on a fast machine Homebridge has
# logged that it runs before apt-get returns.
apt-get() { printf 'Homebridge v2.5.1 (HAP v2.3.1) (Homebridge 1958) is running on port 51029.\n' >> "$LOG"; }
install_deb homebridge
assert_eq 1 "${LOG_MARK:-unset}" "the log is marked before the install, not after it"
if homebridge_started_after "$LOG_MARK"; then ok "the start is found from that mark"; else fail "the start is found from that mark"; fi
if homebridge_started_after "$(log_lines)"; then
  fail "a count taken after the install misses the start (this is why the mark is taken before)"
else
  ok "a count taken after the install misses the start (this is why the mark is taken before)"
fi

section "a start from before the install does not count"
printf 'Homebridge v2.5.0 (HAP v2.3.0) (Homebridge 1958) is running on port 51029.\n' > "$LOG"
apt-get() { printf 'the new package is unpacked\n' >> "$LOG"; }
install_deb homebridge
if homebridge_started_after "$LOG_MARK"; then
  fail "only a start after the mark counts"
else
  ok "only a start after the mark counts"
fi

section "the script never counts the log after an install"
assert_not_contains "$(cat "$SCRIPT")" 'before=$(log_lines)' "no count is taken after the install"
assert_contains "$(cat "$SCRIPT")" 'check_running "$LOG_MARK"' "the checks start from the mark"

finish
