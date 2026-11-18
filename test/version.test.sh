#!/usr/bin/env bash
#
# Tests for scripts/next-prerelease-version.sh (the version of an alpha, beta or legacy build).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=scripts/lib/versions.sh
. "$REPO/scripts/lib/versions.sh"

G="$WORK/version-repo"
mkdir -p "$G"
git -C "$G" init -q
git -C "$G" -c user.email=test@example.com -c user.name=test commit -q --allow-empty -m first

next() {
  OUT=$(cd "$G" && "$BASH" "$REPO/scripts/next-prerelease-version.sh" "$@" 2>&1)
  STATUS=$?
}
# value <name>: one value from the script's output
value() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }

section "the first build of a day"
next 2.0.28 beta 20261118
assert_eq "2.0.28~beta.20261118" "$(value version)" "apt version"
assert_eq "2.0.28-beta.20261118" "$(value npm_version)" "npm version"

section "a second and third build on the same day get their own version"
git -C "$G" tag v2.0.28-beta.20261118
next 2.0.28 beta 20261118
second=$(value npm_version)
assert_eq "2.0.28-beta.20261118.1" "$second" "second build: npm version"
assert_eq "2.0.28~beta.20261118.1" "$(value version)" "second build: apt version"
git -C "$G" tag "v$second"
next 2.0.28 beta 20261118
assert_eq "2.0.28-beta.20261118.2" "$(value npm_version)" "third build: npm version"

section "the versions sort in the order they were built"
if version_lt 2.0.28-beta.20261118 2.0.28-beta.20261118.1; then ok "the first build is lower than the second"; else fail "the first build is lower than the second"; fi
if version_lt 2.0.28-beta.20261118.2 2.0.28-beta.20261119; then ok "the last build of a day is lower than the next day"; else fail "the last build of a day is lower than the next day"; fi
if version_lt 2.0.28-beta.20261119 2.0.28; then ok "every beta is lower than the release"; else fail "every beta is lower than the release"; fi

section "other streams and other days are not affected"
next 2.0.28 alpha 20261118
assert_eq "2.0.28-alpha.20261118" "$(value npm_version)" "alpha on the same day starts without a number"
next 2.0.28 beta 20261119
assert_eq "2.0.28-beta.20261119" "$(value npm_version)" "the next day starts without a number"

section "input"
next 2.0.28-beta.20261101 legacy 20261118
assert_eq "2.0.28-legacy.20261118" "$(value npm_version)" "a suffix on the base version is dropped"
next 2.0.28 stable 20261118
assert_eq 2 "$STATUS" "stable is refused (stable versions have no date)"
next abc beta 20261118
assert_eq 2 "$STATUS" "a base that is not a version is refused"

finish
