#!/bin/bash
#
# Appends the "What's Changed" section to a release manifest (the text of the GitHub release).
#
# Usage: scripts/write-changelog.sh <stable|beta|alpha|legacy> <32bit|64bit> <manifest file>
#
# - The base is the newest release tag of the SAME stream (a stable release is compared with
#   the last stable release, never with a legacy or beta tag).
# - "Package Manifest Changes" compares the stream's own package.json with the one in that tag.
# - "Code Changes" lists the commits since that tag, without the commits that only touch the
#   files of another stream (the daily "BETA: Update beta dependencies ..." commits and so on).
#
# Needs git (with tags) and jq. Only reads from git.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib/versions.sh
. scripts/lib/versions.sh

STREAM="${1:?usage: write-changelog.sh <stream> <32bit|64bit> <manifest file>}"
ARCH_DIR="${2:?usage: write-changelog.sh <stream> <32bit|64bit> <manifest file>}"
MANIFEST="${3:?usage: write-changelog.sh <stream> <32bit|64bit> <manifest file>}"
PACKAGE_JSON="$STREAM/$ARCH_DIR/package.json"

# Inside the build container the repo belongs to another user. Tell git that this is fine, for
# the commands of this script only (nothing is written to a git config file).
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'

# label <package name>: the name used in the notes
label() {
  case "$1" in
    node) echo "Node.js" ;;
    homebridge) echo "Homebridge" ;;
    homebridge-config-ui-x) echo "Homebridge Config UI X" ;;
    @homebridge-plugins/homebridge-updater) echo "Homebridge Updater" ;;
    *) echo "$1" ;;
  esac
}

# list_commits <git log arguments...>: commits as "* subject (`hash`)" lines
list_commits() {
  # shellcheck disable=SC2016 # the backticks are part of the output format
  git log --no-merges --format='* %s (`%h`)' "$@"
}

LATEST_TAG=$(latest_stream_tag "$STREAM" || true)

{
  echo
  echo "## What's Changed"
  echo

  if [ -z "$LATEST_TAG" ]; then
    # no earlier release of this stream: show the newest commits
    recent=$(list_commits -5 2> /dev/null || true)
    if [ -n "$recent" ]; then
      echo "### Recent Changes"
      echo
      echo "$recent"
    else
      echo "* No commit history available"
    fi
    echo
    exit 0
  fi

  package_changes=""
  if old=$(git show "$LATEST_TAG:$PACKAGE_JSON" 2> /dev/null); then
    while IFS=$'\t' read -r name was now; do
      if [ -z "$was" ]; then
        package_changes+="* **$(label "$name")**: Added $now"$'\n'
      elif [ -z "$now" ]; then
        package_changes+="* **$(label "$name")**: Removed (was $was)"$'\n'
      else
        package_changes+="* **$(label "$name")**: Updated from $was to $now"$'\n'
      fi
    done < <(jq -rn --argjson old "$old" --slurpfile new "$PACKAGE_JSON" '
      ($old.dependencies // {}) as $o | ($new[0].dependencies // {}) as $n
      | ([$o, $n] | map(keys) | add | unique)[]
      | select($o[.] != $n[.]) | [., ($o[.] // ""), ($n[.] // "")] | @tsv')
  fi

  # commits since the last release of this stream, without the ones that only touch another stream
  exclude=()
  for other in stable beta alpha legacy; do
    [ "$other" = "$STREAM" ] && continue
    exclude+=(":(exclude)$other" ":(exclude).github/homebridge-$other-bot.json")
  done
  commits=$(list_commits "$LATEST_TAG..HEAD" -- . "${exclude[@]}" 2> /dev/null || true)

  if [ -n "$package_changes" ]; then
    echo "### Package Manifest Changes"
    echo
    printf '%s\n' "$package_changes"
  fi
  if [ -n "$commits" ]; then
    if [ -n "$package_changes" ]; then
      echo "### Code Changes"
      echo
    fi
    echo "$commits"
  elif [ -z "$package_changes" ]; then
    echo "* No new commits since last $STREAM release"
  fi
  echo
} >> "$MANIFEST"
