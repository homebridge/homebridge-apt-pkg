#!/bin/bash
#
# Picks the old releases of one stream that can be deleted from GitHub.
#
# Usage: select-old-releases.sh <beta|alpha|legacy> <number to keep>  < list of tags
#   Standard input: every release tag of the repo, one per line.
#   Output: the tags of that stream that are older than the newest <number to keep>.
#
# Only tags of exactly this stream's form are looked at (v2.0.27-beta.20261118). A stable tag,
# a tag of another stream, or any other tag is never printed. Stable releases are never deleted.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib/versions.sh
. scripts/lib/versions.sh

STREAM="${1:?usage: select-old-releases.sh <beta|alpha|legacy> <number to keep>}"
KEEP="${2:?usage: select-old-releases.sh <beta|alpha|legacy> <number to keep>}"

case "$STREAM" in
  beta | alpha | legacy) ;;
  *)
    echo "Releases of '$STREAM' are never deleted. Use beta, alpha or legacy." >&2
    exit 2
    ;;
esac
if [[ ! "$KEEP" =~ ^[1-9][0-9]*$ ]]; then
  echo "The number to keep must be 1 or more (got: $KEEP)" >&2
  exit 2
fi

{ grep -E -- "$(stream_tag_pattern "$STREAM")" || true; } | sort -V -r | tail -n "+$((KEEP + 1))"
