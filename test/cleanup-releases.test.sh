#!/usr/bin/env bash
#
# Tests for scripts/select-old-releases.sh (which old GitHub releases of a stream may be deleted).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TAGS="v2.0.26
v2.0.25
v1.7.12
v2.0.27-beta.20261114
v2.0.27-beta.20261115
v2.0.27-beta.20261116
v2.0.27-beta.20261117
v2.0.27-beta.20261118
v2.0.27-beta.20261118.1
v2.0.26-beta.20261101
v2.0.27-alpha.20261117
v2.0.27-alpha.20261118
v2.0.27-legacy.20261115
v2.0.27-legacy.20261102
beta-test
v2.0.27-betamax.1"

# old <stream> <keep>: what the script would delete, on one line
old() {
  OUT=$(printf '%s\n' "$TAGS" | "$BASH" "$REPO/scripts/select-old-releases.sh" "$@" 2>&1)
  STATUS=$?
  printf '%s' "${OUT//$'\n'/ }"
}

section "beta: keep the newest 3"
assert_eq "v2.0.27-beta.20261116 v2.0.27-beta.20261115 v2.0.27-beta.20261114 v2.0.26-beta.20261101" "$(old beta 3)" \
  "the newest 3 stay (20261118.1, 20261118 and 20261117); only beta tags are picked"

section "other streams"
assert_eq "v2.0.27-alpha.20261117" "$(old alpha 1)" "alpha: keep 1"
assert_eq "" "$(old legacy 5)" "legacy: fewer than 5 releases, so nothing is deleted"
assert_eq "v2.0.27-legacy.20261102" "$(old legacy 1)" "legacy: keep 1"

section "what is never deleted"
all=$(old beta 1; echo " "; old alpha 1; echo " "; old legacy 1)
assert_not_contains "$all" "v2.0.26 " "a stable release"
assert_not_contains "$all" "v1.7.12" "an old stable release"
assert_not_contains "$all" "beta-test" "a tag that only has the word beta in it"
assert_not_contains "$all" "betamax" "a tag of another form"
old stable 5 > /dev/null
assert_eq 2 "$STATUS" "asking for stable is refused"
old beta 0 > /dev/null
assert_eq 2 "$STATUS" "keeping 0 is refused"

section "the workflow keeps enough releases for Docker builds"
keep=$(yaml_json "$REPO/.github/workflows/release-stage-1_update_dependencies.yml" \
  | jq -r '.jobs.update_dependencies.steps[] | select(.uses == "./.github/actions/cleanup-old-releases-and-tags") | .with["releases-to-keep"]')
if [ "$keep" -ge 14 ]; then ok "Stage 1 keeps $keep releases (at least two weeks of daily builds)"; else fail "Stage 1 keeps at least 14 releases" "found: $keep"; fi

finish
