#!/usr/bin/env bash
#
# Tests for scripts/check-bucket-size.sh (the size check of the R2 bucket), with a fake "aws".

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# the fake aws prints $FAKE_AWS_OUTPUT and ends with $FAKE_AWS_EXIT
fake_script aws << 'EOF'
#!/bin/sh
printf '%s\n' "$FAKE_AWS_OUTPUT"
exit "${FAKE_AWS_EXIT:-0}"
EOF

# size_check <aws output> [aws exit code]
size_check() {
  : > "$WORK/github-env"
  OUT=$(PATH="$FAKEBIN:$REAL_PATH" R2_BUCKET=fake R2_ENDPOINT=https://fake GITHUB_ENV="$WORK/github-env" \
    FAKE_AWS_OUTPUT="$1" FAKE_AWS_EXIT="${2:-0}" "$BASH" "$REPO/scripts/check-bucket-size.sh" 2>&1)
  STATUS=$?
}
listing() { printf '2026-11-18 10:00:00  58343432 pool/stable/h/ho/homebridge_v2.0.26_amd64.deb\n\nTotal Objects: 42\n   Total Size: %s\n' "$1"; }

section "a normal bucket"
size_check "$(listing 5368709120)"
assert_eq 0 "$STATUS" "exit code 0"
assert_eq "R2_SIZE_GB=5.00" "$(cat "$WORK/github-env")" "the size is passed on for the summary"

section "the bucket is getting full"
size_check "$(listing 9000000000)"
assert_eq 0 "$STATUS" "over 8 GB: exit code 0"
assert_contains "$OUT" "::warning::" "over 8 GB: a warning"
size_check "$(listing 10300000000)"
assert_eq 1 "$STATUS" "over 9.5 GB: exit code 1"

section "the size can not be read"
size_check "An error occurred (AccessDenied)" 255
assert_eq 1 "$STATUS" "aws fails: exit code 1 (the old step passed with '0.00 GB')"
assert_eq "" "$(cat "$WORK/github-env")" "no size is reported"
size_check ""
assert_eq 1 "$STATUS" "aws prints nothing: exit code 1"
size_check "$(listing "")"
assert_eq 1 "$STATUS" "the listing has no size in it: exit code 1"

finish
