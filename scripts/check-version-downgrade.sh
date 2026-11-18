#!/bin/bash
#
# Stops a release when a bundled version (Node.js, Homebridge, the UI ...) is LOWER than in the
# last release of the same stream.
#
# Why: on 2 Nov 2026 the dependency bot moved the legacy stream from Homebridge 1.11.4 down to
# 1.6.1, and nothing noticed. Users who upgraded went back three years.
#
# Usage: scripts/check-version-downgrade.sh <stable|beta|alpha|legacy> [base-tag]
#   base-tag: the release to compare with. Default: the newest tag of that stream.
# Env:   ALLOW_VERSION_DOWNGRADE=1   only warn. For the rare case where a step back is wanted.
#
# Needs git (with tags fetched) and jq. Exit code 1 when a version went down.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib/versions.sh
. scripts/lib/versions.sh

STREAM="${1:?usage: check-version-downgrade.sh <stable|beta|alpha|legacy> [base-tag]}"
case "$STREAM" in
  stable | beta | alpha | legacy) ;;
  *)
    echo "Unknown stream: $STREAM" >&2
    exit 2
    ;;
esac

BASE="${2:-$(latest_stream_tag "$STREAM")}"
if [ -z "$BASE" ]; then
  echo "No earlier $STREAM release tag found. Nothing to compare."
  exit 0
fi
echo "Comparing the $STREAM stream with release $BASE"

EXACT='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'
went_down=0

for arch in 32bit 64bit; do
  file="$STREAM/$arch/package.json"
  if ! old=$(git show "$BASE:$file" 2> /dev/null); then
    echo "  $file is not in $BASE. Skipped."
    continue
  fi
  while IFS=$'\t' read -r name was now; do
    [[ "$was" =~ $EXACT && "$now" =~ $EXACT ]] || continue
    if version_lt "$now" "$was"; then
      echo "::error file=$file::$name goes DOWN from $was to $now (compared with $BASE)"
      went_down=1
    else
      echo "  $file: $name $was -> $now"
    fi
  done < <(jq -rn --argjson old "$old" --slurpfile new "$file" '
    ($old.dependencies // {}) as $o | ($new[0].dependencies // {}) as $n
    | $o | keys[] | select($n[.] != null and $n[.] != $o[.]) | [., $o[.], $n[.]] | @tsv')
done

if [ "$went_down" -eq 1 ]; then
  if [ "${ALLOW_VERSION_DOWNGRADE:-}" = "1" ]; then
    echo "::warning::A version goes down, and ALLOW_VERSION_DOWNGRADE=1 is set. Carrying on."
    exit 0
  fi
  echo "Stopped: a version goes down. If this is wanted, run again with the 'allow downgrade' option." >&2
  exit 1
fi
echo "No version goes down."
