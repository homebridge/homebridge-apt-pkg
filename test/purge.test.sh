#!/usr/bin/env bash
#
# Tests for purge.sh (removes old package versions from the S3 apt repository).
# A fake "aws" command prints a saved file list and logs every delete. Nothing real is touched.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STUBLOG="$WORK/stub.log"
export STUBLOG FAKE_LIST="$WORK/list.json"
fake_script aws << 'EOF'
#!/bin/sh
case "$*" in
  *list-objects*) cat "$FAKE_LIST" ;;
  *delete-object*) echo "[aws] $*" >> "$STUBLOG" ;;
esac
EOF

# pool <file name>...: the fake content of the pool
pool() {
  jq -n --args '{Contents: [$ARGS.positional[] | {Key: ("pool/stable/h/ho/" + .)}]}' "$@" > "$FAKE_LIST"
}
# purge <MIN_VERSION> [VAR=value ...]
purge() {
  local min="$1"
  shift
  : > "$STUBLOG"
  OUT=$(env PATH="$FAKEBIN:$REAL_PATH" MIN_VERSION="$min" RELEASE_TYPE=stable S3_BUCKET=fake-bucket S3_REGION=fake-region "$@" "$BASH" "$REPO/purge.sh" 2>&1)
  STATUS=$?
}
deleted() { sed -n 's/.*--key \([^ ]*\).*/\1/p' "$STUBLOG" | sed 's#.*/##' | tr '\n' ' '; }

pool homebridge_1.0.33_amd64.deb homebridge_v1.7.12_amd64.deb homebridge_v1.7.12_arm64.deb \
  homebridge_v2.0.9_amd64.deb homebridge_v2.0.26_amd64.deb homebridge_v2.0.26_armhf.deb

section "keep everything from 1.8.0: the current 2.x packages must stay"
purge 1.8.0
assert_eq 0 "$STATUS" "exit code 0"
assert_eq "homebridge_1.0.33_amd64.deb homebridge_v1.7.12_amd64.deb homebridge_v1.7.12_arm64.deb " "$(deleted)" \
  "only the 1.0.33 and 1.7.12 files are removed (the old script removed v2.0.26)"

section "keep everything from 2.0.20: older 1.x and 2.x packages go"
purge 2.0.20
assert_eq "homebridge_1.0.33_amd64.deb homebridge_v1.7.12_amd64.deb homebridge_v1.7.12_arm64.deb homebridge_v2.0.9_amd64.deb " "$(deleted)" \
  "1.0.33, 1.7.12 and 2.0.9 are removed (the old script removed nothing); 2.0.9 is lower than 2.0.20"

section "dry run"
purge 2.0.20 DRY_RUN=1
assert_eq "" "$(deleted)" "nothing is deleted"
assert_contains "$OUT" "Would remove s3://fake-bucket/pool/stable/h/ho/homebridge_v2.0.9_amd64.deb" "it prints what would be removed"

section "safety stops"
purge 3.0.0
assert_eq 1 "$STATUS" "a minimum above every version is refused"
assert_eq "" "$(deleted)" "and nothing is deleted"
purge 2.x
assert_eq 2 "$STATUS" "a minimum that is not a version is refused"
purge 1.0.0
assert_eq 0 "$STATUS" "a minimum below every version is fine"
assert_eq "" "$(deleted)" "and removes nothing"
echo 'not json' > "$FAKE_LIST"
purge 2.0.20
assert_eq "" "$(deleted)" "a broken file list deletes nothing"
if [ "$STATUS" -ne 0 ]; then ok "and the script fails"; else fail "and the script fails"; fi

finish
