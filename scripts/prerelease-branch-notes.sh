#!/bin/bash
#
# Prints the "Pre-release Changes" section for the release notes of a build that came
# from a pre-release branch (e.g. beta-2026.11.18): the branch it was built from, and
# what that branch adds on top of latest. Prints nothing for a build from latest.
#
# Usage: scripts/prerelease-branch-notes.sh <branch>
# Needs the full git history (actions/checkout with fetch-depth: 0).

set -e

BUILD_BRANCH="${1:-latest}"

if [[ "$BUILD_BRANCH" == "latest" ]]; then
  exit 0
fi

REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-homebridge/homebridge-apt-pkg}"

echo
echo "## Pre-release Changes (not yet in stable)"
echo
echo "Built from branch [\`${BUILD_BRANCH}\`](${REPO_URL}/tree/${BUILD_BRANCH})."
echo

if ! git rev-parse --verify --quiet origin/latest >/dev/null; then
  echo "::warning::origin/latest not available; cannot list pre-release changes." >&2
  exit 0
fi

# Pull requests merged into the branch, then the individual commits they brought in
BRANCH_PRS=$(git log --merges --format='%s' origin/latest..HEAD | grep -oE 'pull request #[0-9]+' | grep -oE '#[0-9]+' | sort -u || true)
for PR in $BRANCH_PRS; do
  echo "* Pull request ${PR}"
done

# Skip the dependency bot's daily package.json bumps; the manifest already covers those
BRANCH_COMMITS=$(git log --no-merges --format='%h %s' origin/latest..HEAD | grep -vE '^[0-9a-f]+ [A-Z]+: Update [a-z]+ dependencies' || true)
if [ -n "$BRANCH_COMMITS" ]; then
  while IFS= read -r commit; do
    echo "* ${commit#* } (\`${commit%% *}\`)"
  done <<< "$BRANCH_COMMITS"
elif [ -z "$BRANCH_PRS" ]; then
  echo "* No changes beyond latest"
fi
