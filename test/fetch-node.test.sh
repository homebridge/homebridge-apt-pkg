#!/usr/bin/env bash
#
# Tests for scripts/fetch-node.sh (downloads the Node.js archive and checks its SHA-256).
# A fake "curl" writes the files, so nothing is downloaded.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STUBLOG="$WORK/stub.log"
export STUBLOG FAKE_SUMS="$WORK/sums.txt" FAKE_ARCHIVE="$WORK/served-archive"
# the fake curl: "curl ... -o <file> <url>" saves the checksum list or the archive
fake_script curl << 'EOF'
#!/bin/sh
echo "[curl] $*" >> "$STUBLOG"
while [ "$#" -gt 1 ]; do
  [ "$1" = "-o" ] && out="$2"
  shift
done
case "$1" in
  */SHASUMS256.txt) cat "$FAKE_SUMS" > "$out" ;;
  *) cat "$FAKE_ARCHIVE" > "$out" ;;
esac
EOF

NAME=node-v24.22.3-linux-arm64.tar.gz
echo "the real archive" > "$WORK/real-archive"
REAL_SUM=$(sha256sum "$WORK/real-archive" | cut -d' ' -f1)
printf '%s  %s\n%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "node-v24.22.3-linux-x64.tar.gz" "$REAL_SUM" "$NAME" > "$FAKE_SUMS"

# fetch <folder>: run the script in that folder
fetch() {
  mkdir -p "$1"
  : > "$STUBLOG"
  OUT=$(cd "$1" && PATH="$FAKEBIN:$REAL_PATH" "$BASH" "$REPO/scripts/fetch-node.sh" v24.22.3 arm64 2>&1)
  STATUS=$?
}

section "the archive matches the published checksum"
cp "$WORK/real-archive" "$FAKE_ARCHIVE"
fetch "$WORK/good"
assert_eq 0 "$STATUS" "exit code 0"
assert_eq "the real archive" "$(cat "$WORK/good/$NAME")" "the archive is saved"

section "the archive was changed on the way"
echo "something else" > "$FAKE_ARCHIVE"
fetch "$WORK/changed"
assert_eq 1 "$STATUS" "exit code 1: the build stops"
assert_missing "$WORK/changed/$NAME" "the bad archive is not left behind"
assert_contains "$OUT" "the checksum of $NAME is wrong" "it says why"

section "the checksum list has no line for this archive"
cp "$WORK/real-archive" "$FAKE_ARCHIVE"
cp "$FAKE_SUMS" "$WORK/sums-backup"
echo "$REAL_SUM  node-v24.22.3-linux-x64.tar.gz" > "$FAKE_SUMS"
fetch "$WORK/no-line"
assert_eq 1 "$STATUS" "exit code 1"
assert_missing "$WORK/no-line/$NAME" "nothing is downloaded"
cp "$WORK/sums-backup" "$FAKE_SUMS"

section "an archive from an earlier build is already in the folder"
mkdir -p "$WORK/cached"
echo "a damaged old download" > "$WORK/cached/$NAME"
fetch "$WORK/cached"
assert_eq 0 "$STATUS" "exit code 0"
assert_eq "the real archive" "$(cat "$WORK/cached/$NAME")" "a wrong local copy is downloaded again"
fetch "$WORK/cached"
assert_eq 1 "$(grep -c . "$STUBLOG")" "a right local copy is not downloaded again (only the checksum list is fetched)"

finish
