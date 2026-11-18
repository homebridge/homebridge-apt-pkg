#!/usr/bin/env bash
#
# Tests for the two scripts of .github/actions/trigger-and-wait-workflow.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ACTION="$REPO/.github/actions/trigger-and-wait-workflow"
STUBLOG="$WORK/stub.log"
export STUBLOG
: > "$STUBLOG"

# ---- select-new-run.sh -----------------------------------------------------------------------

# The run list on 18 Nov 2026: the beta run of the day before is still the newest "Scheduled" run.
cat > "$WORK/before.json" << 'EOF'
[
  {"databaseId": 100, "displayTitle": "Release Stage 2 - Scheduled - beta Run", "createdAt": "2026-11-17T08:09:33Z"},
  {"databaseId": 99, "displayTitle": "Release Stage 2 - Scheduled - alpha Run", "createdAt": "2026-11-17T08:10:54Z"}
]
EOF
select_run() { "$BASH" "$ACTION/select-new-run.sh" "$WORK/before.json" "$1" "$2"; }

section "the new run is not listed yet"
assert_eq "" "$(select_run "$WORK/before.json" "- Scheduled - beta Run")" "nothing is picked (the old code picked run 100, which had already finished)"

section "the new run is listed"
cat > "$WORK/after.json" << 'EOF'
[
  {"databaseId": 103, "displayTitle": "Release Stage 2 - Manual - beta Run", "createdAt": "2026-11-18T08:09:40Z"},
  {"databaseId": 102, "displayTitle": "Release Stage 2 - Scheduled - beta Run", "createdAt": "2026-11-18T08:09:35Z"},
  {"databaseId": 101, "displayTitle": "Release Stage 2 - Scheduled - alpha Run", "createdAt": "2026-11-18T08:09:34Z"},
  {"databaseId": 100, "displayTitle": "Release Stage 2 - Scheduled - beta Run", "createdAt": "2026-11-17T08:09:33Z"},
  {"databaseId": 99, "displayTitle": "Release Stage 2 - Scheduled - alpha Run", "createdAt": "2026-11-17T08:10:54Z"}
]
EOF
assert_eq "102" "$(select_run "$WORK/after.json" "- Scheduled - beta Run")" "the new beta run is picked, not the old one, not another stream, not a manual run"
assert_eq "101" "$(select_run "$WORK/after.json" "- Scheduled - alpha Run")" "the same list gives the new alpha run for alpha"
assert_eq "" "$(select_run "$WORK/after.json" "- Scheduled - legacy Run")" "no legacy run was started, so nothing is picked"

# ---- wait-for-run.sh -------------------------------------------------------------------------

# a fake "gh": each call prints the next line of $GH_ANSWERS ("FAIL" means the command fails)
fake_script gh << 'EOF'
#!/bin/sh
echo "[gh] $*" >> "$STUBLOG"
count=$(cat "$GH_COUNT" 2> /dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$GH_COUNT"
answer=$(sed -n "${count}p" "$GH_ANSWERS")
[ -n "$answer" ] || answer=$(tail -n 1 "$GH_ANSWERS")
[ "$answer" = "FAIL" ] && exit 1
echo "$answer"
EOF
export GH_ANSWERS="$WORK/gh-answers" GH_COUNT="$WORK/gh-count"

# wait_run <timeout minutes> <answer>...
wait_run() {
  local timeout="$1"
  shift
  printf '%s\n' "$@" > "$GH_ANSWERS"
  rm -f "$GH_COUNT"
  OUT=$(PATH="$FAKEBIN:$REAL_PATH" POLL_SECONDS=0 GITHUB_OUTPUT="$WORK/github-output" "$BASH" "$ACTION/wait-for-run.sh" 102 "$timeout" 2>&1)
  STATUS=$?
}

section "the run succeeds after a while"
: > "$WORK/github-output"
wait_run 5 "queued " "in_progress " "completed success"
assert_eq 0 "$STATUS" "exit code 0"
assert_eq "conclusion=success" "$(cat "$WORK/github-output")" "the conclusion is written as an output"

section "the run fails"
wait_run 5 "in_progress " "completed failure"
assert_eq 1 "$STATUS" "exit code 1 (the old code ended with 0, so Stage 1 was always green)"
assert_contains "$OUT" "ended with: failure" "it says how the run ended"

section "the run is cancelled"
wait_run 5 "completed cancelled"
assert_eq 1 "$STATUS" "exit code 1"

section "the run does not finish in time"
wait_run 0 "in_progress "
assert_eq 1 "$STATUS" "exit code 1 (the old code ended with 0)"
assert_contains "$OUT" "did not finish within 0 minutes" "it says that the time is up"

section "one failed status request is not a failed release"
wait_run 5 "in_progress " "FAIL" "completed success"
assert_eq 0 "$STATUS" "exit code 0 when the next request works"
wait_run 5 "FAIL"
assert_eq 1 "$STATUS" "exit code 1 when the status can not be read 5 times in a row"

finish
