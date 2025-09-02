#!/bin/bash

# Test script for changelog generation functionality
# This script allows testing the changelog feature outside of the full release process

set -e

# Default values
PKG_RELEASE_TYPE="${PKG_RELEASE_TYPE:-stable}"
PKG_RELEASE_VERSION="${PKG_RELEASE_VERSION:-test-1.0.0}"
OUTPUT_FILE="${OUTPUT_FILE:-changelog-test.md}"

echo "🧪 Testing changelog generation..."
echo "📋 Release Type: $PKG_RELEASE_TYPE"
echo "📋 Release Version: $PKG_RELEASE_VERSION"
echo "📋 Output File: $OUTPUT_FILE"
echo

# Create test manifest header (similar to build.sh)
cat > "$OUTPUT_FILE" << EOF
# Homebridge Apt Package Manifest (TEST)

**Release Version**: $PKG_RELEASE_VERSION
**Release Type**: $PKG_RELEASE_TYPE

| Package | Version |
|:-------:|:-------:|
|NodeJS| test-node-version |
|Homebridge UI| test-ui-version |
|Homebridge| test-homebridge-version |

## What's Changed

EOF

# Get the latest tag to compare against, filtered by release type
# This is the same logic as in build.sh lines 118-124
if [[ "${PKG_RELEASE_TYPE}" == "beta" ]]; then
  # For beta releases, only look at beta tags
  LATEST_TAG=$(git tag -l | grep -E "beta\." | sort -V | tail -1 2>/dev/null || echo "")
  echo "🔍 Looking for latest beta tag..."
else
  # For stable releases, only look at stable tags (no beta in name)
  LATEST_TAG=$(git tag -l | grep -v -E "beta\." | sort -V | tail -1 2>/dev/null || echo "")
  echo "🔍 Looking for latest stable tag..."
fi

if [ -n "$LATEST_TAG" ]; then
  echo "📌 Found latest $PKG_RELEASE_TYPE tag: $LATEST_TAG"
  
  # Get commits since the latest tag of the same type
  CHANGELOG_COMMITS=$(git log --oneline --no-merges "$LATEST_TAG"..HEAD 2>/dev/null)
  
  if [ -n "$CHANGELOG_COMMITS" ]; then
    echo "📝 Found $(echo "$CHANGELOG_COMMITS" | wc -l) commits since $LATEST_TAG"
    echo
    
    # Format commits as changelog entries
    while IFS= read -r commit; do
      if [ -n "$commit" ]; then
        # Extract commit hash and message
        COMMIT_HASH=$(echo "$commit" | cut -d' ' -f1)
        COMMIT_MSG=$(echo "$commit" | cut -d' ' -f2-)
        echo "* $COMMIT_MSG (\`$COMMIT_HASH\`)" >> "$OUTPUT_FILE"
        echo "  * $COMMIT_MSG (\`$COMMIT_HASH\`)"
      fi
    done <<< "$CHANGELOG_COMMITS"
  else
    echo "ℹ️  No new commits since last $PKG_RELEASE_TYPE release"
    echo "* No new commits since last $PKG_RELEASE_TYPE release" >> "$OUTPUT_FILE"
  fi
else
  echo "⚠️  No $PKG_RELEASE_TYPE tags found, showing recent commits"
  
  # If no tags of this type exist, show recent commits
  RECENT_COMMITS=$(git log --oneline --no-merges -5 2>/dev/null)
  if [ -n "$RECENT_COMMITS" ]; then
    echo "### Recent Changes" >> "$OUTPUT_FILE"
    while IFS= read -r commit; do
      if [ -n "$commit" ]; then
        COMMIT_HASH=$(echo "$commit" | cut -d' ' -f1)
        COMMIT_MSG=$(echo "$commit" | cut -d' ' -f2-)
        echo "* $COMMIT_MSG (\`$COMMIT_HASH\`)" >> "$OUTPUT_FILE"
        echo "  * $COMMIT_MSG (\`$COMMIT_HASH\`)"
      fi
    done <<< "$RECENT_COMMITS"
  else
    echo "* No commit history available" >> "$OUTPUT_FILE"
    echo "⚠️  No commit history available"
  fi
fi

echo >> "$OUTPUT_FILE"

echo
echo "✅ Test completed! Output written to: $OUTPUT_FILE"
echo
echo "📖 To test different scenarios:"
echo "   # Test beta changelog:"
echo "   PKG_RELEASE_TYPE=beta ./test-changelog.sh"
echo
echo "   # Test stable changelog:"
echo "   PKG_RELEASE_TYPE=stable ./test-changelog.sh"
echo
echo "   # Test with custom version and output file:"
echo "   PKG_RELEASE_TYPE=beta PKG_RELEASE_VERSION=1.2.3-beta.1 OUTPUT_FILE=my-test.md ./test-changelog.sh"
echo
echo "📋 Available tags in repository:"
echo "   Stable tags:"
git tag -l | grep -v -E "beta\." | sort -V | tail -5 | sed 's/^/     /'
echo "   Beta tags:"
git tag -l | grep -E "beta\." | sort -V | tail -5 | sed 's/^/     /'