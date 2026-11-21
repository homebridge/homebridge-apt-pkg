#!/usr/bin/env bash
#
# Says whether a release stream may be built from a branch.
#
# - Every stream may build from `latest`.
# - Only beta and alpha may also build from their own pre-release branch, named
#   `<stream>-YYYY.M.D` (the date it was made, with dots and no zero padding: beta-2026.11.18).
# - Stable and legacy must come from `latest`, so a branch can never publish to the stable or
#   legacy apt channel.
#
# Usage: scripts/check-release-branch.sh <release type> <branch>
# Exit: 0 = allowed, 1 = refused (the reason is printed), 2 = wrong arguments.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <release type> <branch>" >&2
  exit 2
fi

RELEASE_TYPE="$1"
BRANCH="$2"

case "$RELEASE_TYPE" in
  stable | beta | alpha | legacy) ;;
  *)
    echo "Unknown release type: $RELEASE_TYPE" >&2
    exit 2
    ;;
esac

if [ "$BRANCH" = "latest" ]; then
  exit 0
fi

if [ "$RELEASE_TYPE" != "beta" ] && [ "$RELEASE_TYPE" != "alpha" ]; then
  echo "::error::${RELEASE_TYPE} releases must be built from the latest branch, not ${BRANCH}"
  exit 1
fi

if [[ ! "$BRANCH" =~ ^${RELEASE_TYPE}-[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
  echo "::error::${RELEASE_TYPE} releases must be built from latest or a ${RELEASE_TYPE}-YYYY.M.D branch, not ${BRANCH}"
  exit 1
fi
