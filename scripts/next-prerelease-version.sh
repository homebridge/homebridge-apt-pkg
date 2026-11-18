#!/bin/bash
#
# Prints the version for the next alpha, beta or legacy build.
#
# Usage: scripts/next-prerelease-version.sh <base version> <alpha|beta|legacy> [date as YYYYMMDD]
#   base version: for example 2.0.28 (anything after a "-" is dropped)
#   date: default is today (UTC)
#
# Output (in the form GitHub Actions reads from $GITHUB_OUTPUT):
#   version=2.0.28~beta.20261118          the apt version
#   npm_version=2.0.28-beta.20261118      the npm version and, with a "v" in front, the git tag
#
# The first build of a day ends in the date. If the tag for that version exists already, the
# next free number is added: 2.0.28~beta.20261118.1, then .2 and so on. apt and npm both sort
# these after the first build. Without this, a second build on the same day had the same
# version: apt users never got it, and the file in the apt repo was replaced under their feet.
#
# Needs git, with the tags fetched.

set -euo pipefail

BASE="${1:?usage: next-prerelease-version.sh <base version> <alpha|beta|legacy> [YYYYMMDD]}"
STREAM="${2:?usage: next-prerelease-version.sh <base version> <alpha|beta|legacy> [YYYYMMDD]}"
DATE="${3:-$(date -u +%Y%m%d)}"

BASE="${BASE%%-*}"
if [[ ! "$BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Not a version: $BASE" >&2
  exit 2
fi
case "$STREAM" in
  alpha | beta | legacy) ;;
  *)
    echo "Unknown stream: $STREAM" >&2
    exit 2
    ;;
esac
if [[ ! "$DATE" =~ ^[0-9]{8}$ ]]; then
  echo "Not a date (YYYYMMDD): $DATE" >&2
  exit 2
fi

npm_version="$BASE-$STREAM.$DATE"
build=0
while git rev-parse --quiet --verify "refs/tags/v$npm_version" > /dev/null; do
  build=$((build + 1))
  npm_version="$BASE-$STREAM.$DATE.$build"
done

echo "version=${npm_version/-/\~}"
echo "npm_version=$npm_version"
