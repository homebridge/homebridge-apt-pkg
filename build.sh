#!/bin/bash

# Homebridge APT Package Build Script
# 
# This script builds Debian packages for Homebridge across multiple architectures.
# 
# IMPORTANT: Node.js Version Constraints
# - Node.js 23+ dropped support for 32-bit architectures (ARM32, i386)
# - This script enforces Node.js ≤22 for 32-bit builds to prevent failures
# - 64-bit architectures (x86_64, aarch64) can use any Node.js version
#
# Package Configuration:
# - Alpha builds: Use alpha/64bit for x86_64/aarch64, alpha/32bit for arm/i386
# - Beta builds: Use beta/64bit for x86_64/aarch64, beta/32bit for arm/i386
# - Stable builds: Use stable/64bit for x86_64/aarch64, stable/32bit for arm/i386
#
# Run ./validate-config.sh to verify package configurations before building

set -e
set -x

#trap 'rm -rf staging *.tar.gz *.manifest /tmp/*' EXIT

# Determine if alpha, beta or stable config should be used
BUILD_ARCH=${QEMU_ARCH:-aarch64}
if [[ "$PKG_RELEASE_TYPE" == "beta" ]]; then
  case "$BUILD_ARCH" in
    x86_64|aarch64)
      PACKAGE_JSON_PATH="beta/64bit/package.json"
      ;;
    arm|i386)
      PACKAGE_JSON_PATH="beta/32bit/package.json"
      ;;
    *) echo "unsupported architecture"; exit 1 ;;
  esac
elif [[ "$PKG_RELEASE_TYPE" == "alpha" ]]; then
  case "$BUILD_ARCH" in
    x86_64|aarch64)
      PACKAGE_JSON_PATH="alpha/64bit/package.json"
      ;;
    arm|i386)
      PACKAGE_JSON_PATH="alpha/32bit/package.json"
      ;;
    *) echo "unsupported architecture"; exit 1 ;;
  esac
elif [[ "$PKG_RELEASE_TYPE" == "legacy" ]]; then
  case "$BUILD_ARCH" in
    x86_64|aarch64)
      PACKAGE_JSON_PATH="legacy/64bit/package.json"
      ;;
    arm|i386)
      PACKAGE_JSON_PATH="legacy/32bit/package.json"
      ;;
    *) echo "unsupported architecture"; exit 1 ;;
  esac
else
  # Stable builds also use architecture-specific configs
  case "$BUILD_ARCH" in
    x86_64|aarch64)
      PACKAGE_JSON_PATH="stable/64bit/package.json"
      ;;
    arm|i386)
      PACKAGE_JSON_PATH="stable/32bit/package.json"
      ;;
    *) echo "unsupported architecture"; exit 1 ;;
  esac
fi

echo "🔧 Using $PACKAGE_JSON_PATH for version resolution"

# Validate package.json configuration
if [[ ! -f "$PACKAGE_JSON_PATH" ]]; then
  echo "ERROR: Package configuration file not found: $PACKAGE_JSON_PATH"
  exit 1
fi

NODE_VERSION_RAW=$(jq -r '.dependencies.node' "$PACKAGE_JSON_PATH")
if [[ "$NODE_VERSION_RAW" == "null" ]]; then
  echo "ERROR: Node.js version not specified in $PACKAGE_JSON_PATH"
  exit 1
fi

echo "📦 Package configuration: $PACKAGE_JSON_PATH"
echo "🟢 Node.js version: $NODE_VERSION_RAW"
echo "🏗️  Target architecture: $BUILD_ARCH"

# Update changelog if version info is present
if [[ -n "${PKG_RELEASE_TYPE}" && -n "${PKG_RELEASE_VERSION}" ]]; then
  cd deb
  DISTRO="$PKG_RELEASE_TYPE"
  if [ "$PKG_RELEASE_TYPE" != "stable" ]; then
    DISTRO="UNRELEASED"
  fi
  dch -b -v "$PKG_RELEASE_VERSION" --controlmaint "Automated Release" --distribution "$DISTRO" "Automated release for $PKG_RELEASE_VERSION"
  cd ..
fi

rm -rf staging
cp -R deb staging

cp "$PACKAGE_JSON_PATH" staging/opt/homebridge/package.json

NODE_VERSION=$(jq -r '.dependencies.node | ltrimstr("^") | "v" + .' "$PACKAGE_JSON_PATH")
HOMEBRIDGE_VERSION=$(jq -r '.dependencies["homebridge"]' "$PACKAGE_JSON_PATH")
HOMEBRIDGE_UIX_VERSION=$(jq -r '.dependencies["homebridge-config-ui-x"]' "$PACKAGE_JSON_PATH")
HOMEBRIDGE_PLUGIN_UPDATE_CHECK_VERSION=$(jq -r '.dependencies["@homebridge-plugins/homebridge-plugin-update-check"]' "$PACKAGE_JSON_PATH")

MAJOR_NODE=$(jq -r '.dependencies.node | gsub("^\\^"; "")' "$PACKAGE_JSON_PATH" | cut -d. -f1)

BUILD_ARCH=${QEMU_ARCH:-aarch64}
case "$BUILD_ARCH" in
  x86_64) NODE_ARCH='x64' ;;
  arm)
    if [ "$MAJOR_NODE" -gt 22 ]; then
      echo "ERROR: Node.js $MAJOR_NODE is not supported on 32-bit ARM (armv7l) architecture"
      echo "Node.js dropped 32-bit support starting with version 23"
      echo "Please use Node.js 22.x or earlier for ARM32 builds"
      echo "Current configuration uses Node.js $NODE_VERSION from $PACKAGE_JSON_PATH"
      exit 1
    fi
    NODE_ARCH='armv7l' ;;
  aarch64) NODE_ARCH='arm64' ;;
  i386)
    if [ "$MAJOR_NODE" -gt 22 ]; then
      echo "ERROR: Node.js $MAJOR_NODE is not supported on 32-bit x86 (i386) architecture"
      echo "Node.js dropped 32-bit support starting with version 23"
      echo "Please use Node.js 22.x or earlier for i386 builds"
      echo "Current configuration uses Node.js $NODE_VERSION from $PACKAGE_JSON_PATH"
      exit 1
    fi
    NODE_ARCH='x86' ;;
  *) echo "unsupported architecture"; exit 1 ;;
esac

MANIFEST="homebridge_apt_pkg_$NODE_ARCH.manifest"
echo "Homebridge Apt Package Manifest" > "$MANIFEST"
echo >> "$MANIFEST"
echo "**Release Version**: ${PKG_RELEASE_VERSION:-unknown}" >> "$MANIFEST"
echo "**Release Type**: ${PKG_RELEASE_TYPE:-stable}" >> "$MANIFEST"
echo >> "$MANIFEST"
echo "| Package | Version |" >> "$MANIFEST"
echo "|:-------:|:-------:|" >> "$MANIFEST"
echo "| NodeJS | $NODE_VERSION |" >> "$MANIFEST"

# Download and unpack NodeJS binary
if [ ! -f "node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" ]; then
  # Additional safety check: Ensure we're not trying to download Node.js >22 for 32-bit architectures
  if [[ ("$NODE_ARCH" == "armv7l" || "$NODE_ARCH" == "x86") && "$MAJOR_NODE" -gt 22 ]]; then
    echo "ERROR: Cannot download Node.js $NODE_VERSION for 32-bit architecture $NODE_ARCH"
    echo "Node.js versions greater than 22 do not support 32-bit architectures"
    echo "Please use Node.js 22.x or earlier for ARM32/i386 builds"
    exit 1
  fi
  
  if [[ "$NODE_ARCH" == "armv6l" || "$NODE_ARCH" == "x86" ]]; then
    echo "Downloading Node.js $NODE_VERSION for 32-bit architecture $NODE_ARCH from unofficial builds..."
    curl -fSLO "https://unofficial-builds.nodejs.org/download/release/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
  else
    echo "Downloading Node.js $NODE_VERSION for architecture $NODE_ARCH from official builds..."
    curl -fSLO "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
  fi
fi
tar xzf "node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" -C staging/opt/homebridge/ --strip-components=1 --no-same-owner

PATH="$(pwd)/staging/opt/homebridge/bin:$PATH"

export npm_config_prefix=$(pwd)/staging/opt/homebridge
export npm_config_global_style=true
export npm_config_package_lock=false
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export npm_config_auto_install_peers=true
export npm_config_loglevel=error

# Install packages
npm install --location=global homebridge-config-ui-x@$HOMEBRIDGE_UIX_VERSION
echo "| Homebridge UI | $HOMEBRIDGE_UIX_VERSION |" >> "$MANIFEST"

# Only install homebridge-plugin-update-check if it exists in package.json
if [ "$HOMEBRIDGE_PLUGIN_UPDATE_CHECK_VERSION" != "null" ]; then
  npm install --prefix "$(pwd)/staging/var/lib/homebridge" @homebridge-plugins/homebridge-plugin-update-check@$HOMEBRIDGE_PLUGIN_UPDATE_CHECK_VERSION
  echo "| Plugin Update Check | $HOMEBRIDGE_PLUGIN_UPDATE_CHECK_VERSION |" >> "$MANIFEST"
fi

npm install --prefix "$(pwd)/staging/var/lib/homebridge" homebridge@$HOMEBRIDGE_VERSION
echo "| Homebridge | $HOMEBRIDGE_VERSION |" >> "$MANIFEST"

# Add changelog section to manifest
echo >> "$MANIFEST"
echo "## What's Changed" >> "$MANIFEST"
echo >> "$MANIFEST"

# Configure git for Docker containers to avoid "dubious ownership" errors
git config --global --add safe.directory /repo 2>/dev/null || true

# Get the latest tag to compare against, filtered by release type
if [[ "${PKG_RELEASE_TYPE:-stable}" == "beta" ]]; then
  # For beta releases, only look at beta tags
  LATEST_TAG=$(git tag -l | grep -E "beta\." | sort -V | tail -1 2>/dev/null || echo "")
elif [[ "${PKG_RELEASE_TYPE:-stable}" == "alpha" ]]; then
  # For alpha releases, only look at alpha tags
  LATEST_TAG=$(git tag -l | grep -E "alpha\." | sort -V | tail -1 2>/dev/null || echo "")
else
  # For stable releases, only look at stable tags (no beta or alpha in name)
  LATEST_TAG=$(git tag -l | grep -v -E "(beta|alpha)\." | sort -V | tail -1 2>/dev/null || echo "")
fi

# Check for package manifest changes if we have a previous tag
HAS_PACKAGE_CHANGES=false
if [ -n "$LATEST_TAG" ]; then
  # Get the previous package.json for comparison
  PREV_PACKAGE_JSON=""
  case "${PKG_RELEASE_TYPE:-stable}" in
    beta)
      if [[ "$BUILD_ARCH" == "aarch64" || "$BUILD_ARCH" == "x86_64" ]]; then
        PREV_PACKAGE_JSON="beta/64bit/package.json"
      else
        PREV_PACKAGE_JSON="beta/32bit/package.json"
      fi
      ;;
    alpha)
      if [[ "$BUILD_ARCH" == "aarch64" || "$BUILD_ARCH" == "x86_64" ]]; then
        PREV_PACKAGE_JSON="alpha/64bit/package.json"
      else
        PREV_PACKAGE_JSON="alpha/32bit/package.json"
      fi
      ;;
    *)
      if [[ "$BUILD_ARCH" == "aarch64" || "$BUILD_ARCH" == "x86_64" ]]; then
        PREV_PACKAGE_JSON="stable/64bit/package.json"
      else
        PREV_PACKAGE_JSON="stable/32bit/package.json"
      fi
      ;;
  esac
  
  # Compare package versions with previous tag
  if [ -n "$PREV_PACKAGE_JSON" ] && git show "$LATEST_TAG:$PREV_PACKAGE_JSON" >/dev/null 2>&1; then
    PREV_NODE=$(git show "$LATEST_TAG:$PREV_PACKAGE_JSON" 2>/dev/null | jq -r '.dependencies.node // "unknown"')
    PREV_HOMEBRIDGE=$(git show "$LATEST_TAG:$PREV_PACKAGE_JSON" 2>/dev/null | jq -r '.dependencies.homebridge // "unknown"')
    PREV_HOMEBRIDGE_UI=$(git show "$LATEST_TAG:$PREV_PACKAGE_JSON" 2>/dev/null | jq -r '.dependencies["homebridge-config-ui-x"] // "unknown"')
    
    CURR_NODE=$(jq -r '.dependencies.node // "unknown"' "$PACKAGE_JSON_PATH")
    CURR_HOMEBRIDGE=$(jq -r '.dependencies.homebridge // "unknown"' "$PACKAGE_JSON_PATH")
    CURR_HOMEBRIDGE_UI=$(jq -r '.dependencies["homebridge-config-ui-x"] // "unknown"' "$PACKAGE_JSON_PATH")
    
    # Check for version changes and add them to changelog
    if [[ "$PREV_NODE" != "$CURR_NODE" && "$CURR_NODE" != "unknown" ]]; then
      echo "### Package Manifest Changes" >> "$MANIFEST"
      echo >> "$MANIFEST"
      HAS_PACKAGE_CHANGES=true
    fi
    
    if [[ "$PREV_NODE" != "$CURR_NODE" && "$CURR_NODE" != "unknown" ]]; then
      echo "* **Node.js**: Updated from $PREV_NODE to $CURR_NODE" >> "$MANIFEST"
    fi
    if [[ "$PREV_HOMEBRIDGE" != "$CURR_HOMEBRIDGE" && "$CURR_HOMEBRIDGE" != "unknown" ]]; then
      if [ "$HAS_PACKAGE_CHANGES" = false ]; then
        echo "### Package Manifest Changes" >> "$MANIFEST"
        echo >> "$MANIFEST"
        HAS_PACKAGE_CHANGES=true
      fi
      echo "* **Homebridge**: Updated from $PREV_HOMEBRIDGE to $CURR_HOMEBRIDGE" >> "$MANIFEST"
    fi
    if [[ "$PREV_HOMEBRIDGE_UI" != "$CURR_HOMEBRIDGE_UI" && "$CURR_HOMEBRIDGE_UI" != "unknown" ]]; then
      if [ "$HAS_PACKAGE_CHANGES" = false ]; then
        echo "### Package Manifest Changes" >> "$MANIFEST"
        echo >> "$MANIFEST"
        HAS_PACKAGE_CHANGES=true
      fi
      echo "* **Homebridge Config UI X**: Updated from $PREV_HOMEBRIDGE_UI to $CURR_HOMEBRIDGE_UI" >> "$MANIFEST"
    fi
    
    if [ "$HAS_PACKAGE_CHANGES" = true ]; then
      echo >> "$MANIFEST"
    fi
  fi
fi

if [ -n "$LATEST_TAG" ]; then
  # Get commits since the latest tag of the same type
  CHANGELOG_COMMITS=$(git log --oneline --no-merges "$LATEST_TAG"..HEAD 2>/dev/null)
  
  if [ -n "$CHANGELOG_COMMITS" ]; then
    # Add code changes section header
    if [ "$HAS_PACKAGE_CHANGES" = true ]; then
      echo "### Code Changes" >> "$MANIFEST"
      echo >> "$MANIFEST"
    fi
    # Format commits as changelog entries
    while IFS= read -r commit; do
      if [ -n "$commit" ]; then
        # Extract commit hash and message
        COMMIT_HASH=$(echo "$commit" | cut -d' ' -f1)
        COMMIT_MSG=$(echo "$commit" | cut -d' ' -f2-)
        echo "* $COMMIT_MSG (\`$COMMIT_HASH\`)" >> "$MANIFEST"
      fi
    done <<< "$CHANGELOG_COMMITS"
  else
    if [ "$HAS_PACKAGE_CHANGES" = false ]; then
      echo "* No new commits since last ${PKG_RELEASE_TYPE:-stable} release" >> "$MANIFEST"
    fi
  fi
else
  # If no tags of this type exist, show recent commits
  RECENT_COMMITS=$(git log --oneline --no-merges -5 2>/dev/null)
  if [ -n "$RECENT_COMMITS" ]; then
    echo "### Recent Changes" >> "$MANIFEST"
    echo >> "$MANIFEST"
    while IFS= read -r commit; do
      if [ -n "$commit" ]; then
        COMMIT_HASH=$(echo "$commit" | cut -d' ' -f1)
        COMMIT_MSG=$(echo "$commit" | cut -d' ' -f2-)
        echo "* $COMMIT_MSG (\`$COMMIT_HASH\`)" >> "$MANIFEST"
      fi
    done <<< "$RECENT_COMMITS"
  else
    echo "* No commit history available" >> "$MANIFEST"
  fi
fi

echo >> "$MANIFEST"

cp "$MANIFEST" staging/opt/homebridge
# Build .deb
cd staging
dpkg-buildpackage -us -uc
cd ..

# Finalize manifest name
FINAL_MANIFEST=$(ls homebridge*.deb | sed -e 's/.deb/.manifest/')
mv "$MANIFEST" "$FINAL_MANIFEST"