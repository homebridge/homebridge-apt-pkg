#!/usr/bin/env bash
#
# Tests for the pre-release branches of the beta and alpha streams:
# - scripts/check-release-branch.sh (which stream may build from which branch)
# - scripts/prerelease-branch-notes.sh (the "Pre-release Changes" part of the release text)
# - the branch Release Stage 1 picks

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check() {
  OUT=$("$BASH" "$REPO/scripts/check-release-branch.sh" "$@" 2>&1)
  STATUS=$?
}

section "every stream may build from latest"
for stream in stable beta alpha legacy; do
  check "$stream" latest
  assert_eq 0 "$STATUS" "$stream from latest"
done

section "only beta and alpha may build from their own dated branch"
check beta beta-2026.11.18
assert_eq 0 "$STATUS" "beta from beta-2026.11.18"
check alpha alpha-2026.1.5
assert_eq 0 "$STATUS" "alpha from alpha-2026.1.5"
check stable beta-2026.11.18
assert_eq 1 "$STATUS" "stable from a beta branch is refused"
assert_contains "$OUT" "stable releases must be built from the latest branch" "stable: the reason is printed"
check legacy beta-2026.11.18
assert_eq 1 "$STATUS" "legacy from a beta branch is refused"

section "any other branch is refused"
for branch in alpha-2026.11.18 feat/x beta-2026-11-18 beta-2026.11.18-x archive/beta-2026.11.18 beta-UI-Update bp-audit; do
  check beta "$branch"
  assert_eq 1 "$STATUS" "beta from $branch is refused"
done
check beta feat/x
assert_contains "$OUT" "latest or a beta-YYYY.M.D branch" "beta: the reason is printed"

section "wrong arguments"
check beta
assert_eq 2 "$STATUS" "one argument is refused"
check nightly latest
assert_eq 2 "$STATUS" "an unknown release type is refused"

# ---- the release text ----------------------------------------------------------------------

G="$WORK/notes-origin"
W="$WORK/notes-work"
git init -q -b latest "$G"
git -C "$G" -c user.email=test@example.com -c user.name=test commit -q --allow-empty -m base
git clone -q "$G" "$W"
git -C "$W" config user.email test@example.com
git -C "$W" config user.name test

notes() {
  OUT=$(cd "$W" && "$BASH" "$REPO/scripts/prerelease-branch-notes.sh" "$@" 2>&1)
  STATUS=$?
}

section "a build from latest adds nothing to the release text"
notes latest
assert_eq 0 "$STATUS" "exit status"
assert_eq "" "$OUT" "no text"

section "a build from a branch lists what the branch adds"
git -C "$W" switch -q -c feat
git -C "$W" commit -q --allow-empty -m "feat: run as a non-root user"
git -C "$W" switch -q -c beta-2026.11.18 origin/latest
git -C "$W" merge -q --no-ff feat -m "Merge pull request #12 from someone/feat"
git -C "$W" commit -q --allow-empty -m "BETA: Update beta dependencies in beta/32bit,beta/64bit"
git -C "$W" commit -q --allow-empty -m "fix: a direct commit on the branch"
notes beta-2026.11.18
assert_eq 0 "$STATUS" "exit status"
assert_contains "$OUT" "## Pre-release Changes (not yet in stable)" "the heading"
assert_contains "$OUT" "/tree/beta-2026.11.18" "a link to the branch"
assert_contains "$OUT" "* Pull request #12" "the merged pull request"
assert_contains "$OUT" "* feat: run as a non-root user" "the commit the pull request brought in"
assert_contains "$OUT" "* fix: a direct commit on the branch" "a commit made on the branch"
assert_not_contains "$OUT" "Update beta dependencies" "the dependency bot's commits are left out"

section "a branch with nothing new says so"
git -C "$W" switch -q -c beta-2026.11.20 origin/latest
notes beta-2026.11.20
assert_contains "$OUT" "* No changes beyond latest" "the empty branch line"

# ---- the branch Release Stage 1 picks --------------------------------------------------------

# The same filter and sort as the "Resolve ... Branch" step of release-stage-1_update_dependencies.yml
pick() {
  local stream="$1"
  shift
  printf '%s\n' "$@" | grep -E "^${stream}-[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}$" | sort -V | tail -n 1 || true
}

section "Release Stage 1 picks the newest dated branch"
assert_eq "beta-2026.11.18" "$(pick beta beta-2026.2.3 beta-2026.11.18 beta-2026.11.2 beta-test beta-2026-11-30 alpha-2027.1.1)" "the newest beta branch, by date and not by text"
assert_eq "" "$(pick alpha beta-2026.2.3 alpha-UI-Update)" "no dated alpha branch: none is picked, so latest is used"
STAGE1="$REPO/.github/workflows/release-stage-1_update_dependencies.yml"
# SC2016: the text looked for holds "$..." and "${{ ... }}" that must not expand here.
# shellcheck disable=SC2016
{
assert_contains "$(cat "$STAGE1")" 'grep -E "^${STREAM}-[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}$"' "the workflow uses this filter"
assert_contains "$(cat "$STAGE1")" 'base_branch: ${{ steps.resolve-branch.outputs.branch }}' "the dependency bot works on the picked branch"
assert_contains "$(cat "$STAGE1")" 'ref: ${{ steps.resolve-branch.outputs.branch }}' "Stage 2 runs on the picked branch"
}

finish
