#!/usr/bin/env bash
#
# Tests for scripts/check-version-downgrade.sh and scripts/lib/versions.sh.
# The guard runs in a small throw-away git repo, never in this one.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=scripts/lib/versions.sh
. "$REPO/scripts/lib/versions.sh"

section "version_lt orders versions the way npm and apt do"
lt() { if version_lt "$1" "$2"; then echo yes; else echo no; fi; }
assert_eq yes "$(lt 1.6.1 1.11.4)" "1.6.1 is lower than 1.11.4"
assert_eq no "$(lt 1.11.4 1.6.1)" "1.11.4 is not lower than 1.6.1"
assert_eq no "$(lt 2.5.0 2.5.0)" "a version is not lower than itself"
assert_eq yes "$(lt 2.5.1-beta.5 2.5.1)" "a beta is lower than its release"
assert_eq no "$(lt 2.5.1-beta.5 2.5.0)" "the next beta is not lower than the last release"
assert_eq yes "$(lt 2.5.1-beta.9 2.5.1-beta.10)" "beta.9 is lower than beta.10"
assert_eq yes "$(lt 6.0.1-alpha.25 6.0.1-beta.1)" "an alpha is lower than a beta"

# a throw-away repo with one release of each stream
G="$WORK/guard-repo"
mkdir -p "$G/scripts/lib"
cp "$REPO/scripts/check-version-downgrade.sh" "$G/scripts/"
cp "$REPO/scripts/lib/versions.sh" "$G/scripts/lib/"
git -C "$G" init -q
git -C "$G" config user.email test@example.com
git -C "$G" config user.name test

# stream_file <stream> <arch> <homebridge> <node>
stream_file() {
  mkdir -p "$G/$1/$2"
  printf '{"dependencies":{"homebridge":"%s","homebridge-config-ui-x":"5.30.1","node":"%s"}}\n' "$3" "$4" > "$G/$1/$2/package.json"
}
release() {
  git -C "$G" add -A
  git -C "$G" commit -q -m "release $1"
  git -C "$G" tag "$1"
}
guard() {
  OUT=$(cd "$G" && "$BASH" scripts/check-version-downgrade.sh "$@" 2>&1)
  STATUS=$?
}

stream_file legacy 32bit 1.11.4 22.23.5
stream_file legacy 64bit 1.11.4 24.22.3
stream_file stable 32bit 2.5.0 22.23.5
stream_file stable 64bit 2.5.0 26.13.1
stream_file beta 32bit 2.5.1-beta.5 22.23.5
stream_file beta 64bit 2.5.1-beta.5 26.13.1
release v2.0.26
git -C "$G" tag v2.0.27-legacy.20261101
git -C "$G" tag v2.0.27-beta.20261101

section "nothing changed: the guard passes"
guard legacy
assert_eq 0 "$STATUS" "exit code 0"

section "the real case: legacy Homebridge goes from 1.11.4 to 1.6.1"
stream_file legacy 32bit 1.6.1 22.23.5
stream_file legacy 64bit 1.6.1 24.22.3
guard legacy
assert_eq 1 "$STATUS" "exit code 1"
assert_contains "$OUT" "homebridge goes DOWN from 1.11.4 to 1.6.1" "the message names the package and both versions"
guard stable
assert_eq 0 "$STATUS" "the stable stream is not affected by the legacy files"

section "a wanted step back can be allowed"
OUT=$(cd "$G" && ALLOW_VERSION_DOWNGRADE=1 "$BASH" scripts/check-version-downgrade.sh legacy 2>&1)
assert_eq 0 "$?" "exit code 0 with ALLOW_VERSION_DOWNGRADE=1"
assert_contains "$OUT" "::warning::" "it still prints a warning"

section "only one of the two files goes down"
stream_file legacy 32bit 1.11.4 22.23.5
stream_file legacy 64bit 1.11.4 22.23.5
guard legacy
assert_eq 1 "$STATUS" "exit code 1 when only 64-bit Node.js goes down"
assert_contains "$OUT" "node goes DOWN from 24.22.3 to 22.23.5" "the message names Node.js"

section "upgrades and pre-releases"
stream_file legacy 64bit 1.11.4 24.22.4
guard legacy
assert_eq 0 "$STATUS" "a newer Node.js passes"
stream_file beta 32bit 2.5.1 22.23.5
stream_file beta 64bit 2.5.1 26.13.1
guard beta
assert_eq 0 "$STATUS" "beta moving from 2.5.1-beta.5 to the release 2.5.1 passes"
stream_file beta 64bit 2.5.0 26.13.1
guard beta
assert_eq 1 "$STATUS" "beta moving from 2.5.1-beta.5 back to 2.5.0 is stopped"

section "it compares with the newest tag of the same stream only"
stream_file stable 64bit 2.4.0 26.13.1
guard stable
assert_eq 1 "$STATUS" "stable is compared with v2.0.26, not with a legacy or beta tag"
assert_contains "$OUT" "release v2.0.26" "the base tag is v2.0.26"
guard nightly
assert_eq 2 "$STATUS" "an unknown stream is refused"

finish
