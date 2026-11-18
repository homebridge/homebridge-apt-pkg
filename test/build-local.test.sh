#!/usr/bin/env bash
#
# Tests for scripts/build-local.sh. Only its arguments are tested ("--dry-run"): no Docker is used.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# plan <arguments...>: what the script would build
plan() {
  OUT=$("$BASH" "$REPO/scripts/build-local.sh" "$@" 2>&1)
  STATUS=$?
}

section "every stream and every architecture"
for stream in stable beta alpha legacy; do
  plan "$stream" x86_64 1.2.3 --dry-run
  assert_eq 0 "$STATUS" "$stream is a known release type"
  assert_contains "$OUT" "Versions in:  $stream/64bit/package.json" "$stream x86_64 uses the 64-bit file"
done
plan legacy arm 1.2.3 --dry-run
assert_contains "$OUT" "Versions in:  legacy/32bit/package.json" "32-bit ARM uses the 32-bit file"
assert_contains "$OUT" "arm (linux/arm/v7, image arm32v7/debian:bookworm)" "32-bit ARM builds in the official Debian image"
plan stable aarch64 1.2.3 --dry-run
assert_contains "$OUT" "aarch64 (linux/arm64, image arm64v8/debian:bookworm)" "64-bit ARM"
plan stable x86_64 1.2.3 --dry-run
assert_contains "$OUT" "x86_64 (linux/amd64, image library/debian:bookworm)" "Intel"

section "other names for the same architecture"
plan stable arm64 1.2.3 --dry-run
assert_contains "$OUT" "Architecture: aarch64 " "arm64 means aarch64"
plan stable armhf 1.2.3 --dry-run
assert_contains "$OUT" "Architecture: arm " "armhf means arm"
plan stable amd64 1.2.3 --dry-run
assert_contains "$OUT" "Architecture: x86_64 " "amd64 means x86_64"

section "wrong input"
plan
assert_eq 2 "$STATUS" "no release type: exit code 2"
plan nightly
assert_eq 2 "$STATUS" "an unknown release type: exit code 2"
plan stable mips 1.2.3 --dry-run
assert_eq 2 "$STATUS" "an unknown architecture: exit code 2"
plan --help
assert_eq 0 "$STATUS" "--help: exit code 0"
assert_contains "$OUT" "stable | beta | alpha | legacy" "--help lists the release types"

section "the workflows build with this script, so there is one list of build images"
assert_eq "" "$(grep -l 'docker build' "$REPO"/.github/workflows/*.yml)" "no workflow has its own docker build line"
assert_eq "" "$(grep -rl 'bullseye\|balenalib' "$REPO/scripts" "$REPO/.github/workflows" "$REPO/build")" "no old image name is left in the scripts or workflows"

finish
