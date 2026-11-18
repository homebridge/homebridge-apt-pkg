#!/usr/bin/env bash
#
# Tests for r2-apt-retention.sh (keeps the newest versions in the R2 apt repository, removes the rest).
# A fake "deb-s3" command prints a saved package list and logs every call. Nothing real is touched.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STUBLOG="$WORK/stub.log"
export STUBLOG FAKE_LIST="$WORK/list.txt"
fake_script deb-s3 << 'EOF'
#!/bin/sh
case "$1" in
  list) cat "$FAKE_LIST" ;;
  *) echo "[deb-s3] $*" >> "$STUBLOG" ;;
esac
EOF

# retention <codename> <keep>
retention() {
  : > "$STUBLOG"
  rm -f "$WORK/report.txt"
  OUT=$(PATH="$FAKEBIN:$REAL_PATH" R2_BUCKET=fake R2_ENDPOINT=https://fake R2_ACCESS_KEY_ID=fake R2_SECRET_ACCESS_KEY=fake \
    GPG_KEY_ID=FAKEKEY RETENTION_REPORT="$WORK/report.txt" "$BASH" "$REPO/r2-apt-retention.sh" "$@" 2>&1)
  STATUS=$?
}
deletes() { grep '^\[deb-s3\] delete' "$STUBLOG" | sed 's/--access-key-id=[^ ]* --secret-access-key=[^ ]* //'; }

section "stable: keep the newest 3 versions of each architecture"
cat > "$FAKE_LIST" << 'EOF'
homebridge 2.0.9 amd64
homebridge 2.0.24 amd64
homebridge 2.0.25 amd64
homebridge 2.0.26 amd64
homebridge 2.0.25 arm64
homebridge 2.0.26 arm64
homebridge 2.0.10 armhf
homebridge 2.0.23 armhf
homebridge 2.0.24 armhf
homebridge 2.0.25 armhf
homebridge 2.0.26 armhf
EOF
retention stable 3
assert_eq 0 "$STATUS" "exit code 0"
all=$(deletes)
assert_contains "$all" "--arch=amd64 --sign=FAKEKEY --versions 2.0.9" "amd64: only 2.0.9 is removed (2.0.9 is older than 2.0.24)"
assert_contains "$all" "--arch=armhf --sign=FAKEKEY --versions 2.0.10 2.0.23" "armhf: the two oldest are removed"
assert_not_contains "$all" "--arch=arm64" "arm64: has only 2 versions, so nothing is removed"
assert_not_contains "$all" "2.0.26" "the newest version is never removed"
assert_contains "$(cat "$STUBLOG")" "[deb-s3] clean" "files that are no longer listed are cleaned up"

section "beta: versions with a date, and a second build on the same day"
cat > "$FAKE_LIST" << 'EOF'
homebridge 2.0.27~beta.20261117 amd64
homebridge 2.0.27~beta.20261118 amd64
homebridge 2.0.27~beta.20261118.1 amd64
homebridge 2.0.26~beta.20261101 amd64
EOF
retention beta 2
assert_contains "$(deletes)" "--versions 2.0.26~beta.20261101 2.0.27~beta.20261117" "the two oldest builds are removed; the two builds of the last day stay"

section "nothing to remove: delete is never called without a version"
cat > "$FAKE_LIST" << 'EOF'
homebridge 2.0.26 amd64
EOF
retention stable 3
assert_eq "" "$(deletes)" "no delete call (deb-s3 would remove ALL versions if called without one)"

section "missing arguments"
retention stable
if [ "$STATUS" -ne 0 ]; then ok "the number to keep is required"; else fail "the number to keep is required"; fi
assert_eq "" "$(deletes)" "and nothing is deleted"

finish
