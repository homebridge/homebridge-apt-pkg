#!/bin/bash
#
# Downloads the Node.js archive for a build and checks it against Node's published SHA-256 list.
# This archive becomes the Node.js runtime of every user, so a damaged or changed file must stop
# the build.
#
# Usage: scripts/fetch-node.sh <version, for example v24.22.3> <arch: x64 | arm64 | armv7l>
# The archive is saved in the current folder as node-<version>-linux-<arch>.tar.gz.
# An archive that is already there is checked the same way, and downloaded again if it is wrong.

set -euo pipefail

NODE_VERSION="${1:?usage: fetch-node.sh <version> <arch>}"
NODE_ARCH="${2:?usage: fetch-node.sh <version> <arch>}"
BASE_URL="https://nodejs.org/dist/$NODE_VERSION"
ARCHIVE="node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
SUMS="SHASUMS256-$NODE_VERSION.txt"

curl -fsSL -o "$SUMS" "$BASE_URL/SHASUMS256.txt"
expected=$(awk -v file="$ARCHIVE" '$2 == file {print $1}' "$SUMS")
rm -f "$SUMS"
if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERROR: $BASE_URL/SHASUMS256.txt has no checksum for $ARCHIVE" >&2
  exit 1
fi

matches() { [ -f "$ARCHIVE" ] && echo "$expected  $ARCHIVE" | sha256sum --check --status; }

if matches; then
  echo "Node.js $NODE_VERSION ($NODE_ARCH) is already downloaded, and its checksum is right."
  exit 0
fi

echo "Downloading Node.js $NODE_VERSION for $NODE_ARCH..."
rm -f "$ARCHIVE"
curl -fSL -o "$ARCHIVE" "$BASE_URL/$ARCHIVE"
if ! matches; then
  echo "ERROR: the checksum of $ARCHIVE is wrong." >&2
  echo "  expected: $expected" >&2
  echo "  got:      $(sha256sum "$ARCHIVE" | cut -d' ' -f1)" >&2
  rm -f "$ARCHIVE"
  exit 1
fi
echo "Checksum of $ARCHIVE is right."
