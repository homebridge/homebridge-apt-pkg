#!/bin/bash

set -e
set -x

#trap 'rm -rf staging *.tar.gz *.manifest /tmp/*' EXIT

# Determine if beta or stable config should be used
if [[ "$PKG_RELEASE_TYPE" == "beta" ]]; then
  BUILD_ARCH=${QEMU_ARCH:-aarch64}
  case "$BUILD_ARCH" in
    x86_64|aarch64)
      PACKAGE_JSON_PATH="beta/64bit/package.json"
      ;;
    arm|i386)
      PACKAGE_JSON_PATH="beta/32bit/package.json"
      ;;
    *) echo "unsupported architecture"; exit 1 ;;
  esac
else
  PACKAGE_JSON_PATH="package.json"
fi

echo "🔧 Using $PACKAGE_JSON_PATH for version resolution"

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

NODE_VERSION=$(jq -r '.dependencies.node | gsub("^\\^"; "v")' "$PACKAGE_JSON_PATH")
HOMEBRIDGE_VERSION=$(jq -r '.dependencies["homebridge"]' "$PACKAGE_JSON_PATH")
HOMEBRIDGE_UIX_VERSION=$(jq -r '.dependencies["homebridge-config-ui-x"]' "$PACKAGE_JSON_PATH")

MAJOR_NODE=$(jq -r '.dependencies.node | gsub("^\\^"; "")' "$PACKAGE_JSON_PATH" | cut -d. -f1)

BUILD_ARCH=${QEMU_ARCH:-aarch64}
case "$BUILD_ARCH" in
  x86_64) NODE_ARCH='x64' ;;
  arm)
    if [ "$MAJOR_NODE" -gt 22 ]; then
      echo "Skipping arm build as NodeJS > 22 on 32 Bit OS's is no longer supported"
      exit 1
    fi
    NODE_ARCH='armv7l' ;;
  aarch64) NODE_ARCH='arm64' ;;
  i386)
    if [ "$MAJOR_NODE" -gt 22 ]; then
      echo "Skipping i386 build as NodeJS > 22 on 32 Bit OS's is no longer supported"
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
echo "|NodeJS| $NODE_VERSION |" >> "$MANIFEST"

# Download and unpack NodeJS binary
if [ ! -f "node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" ]; then
  if [[ "$NODE_ARCH" == "armv6l" || "$NODE_ARCH" == "x86" ]]; then
    curl -fSLO "https://unofficial-builds.nodejs.org/download/release/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
  else
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
echo "|Homebridge UI| $HOMEBRIDGE_UIX_VERSION |" >> "$MANIFEST"

npm install --prefix "$(pwd)/staging/var/lib/homebridge" homebridge@$HOMEBRIDGE_VERSION
echo "|Homebridge| $HOMEBRIDGE_VERSION |" >> "$MANIFEST"

# Add changelog section to manifest
echo >> "$MANIFEST"
echo "## What's Changed" >> "$MANIFEST"
echo >> "$MANIFEST"

# Get the latest tag to compare against, filtered by release type
if [[ "${PKG_RELEASE_TYPE:-stable}" == "beta" ]]; then
  # For beta releases, only look at beta tags
  LATEST_TAG=$(git tag -l | grep -E "beta\." | sort -V | tail -1 2>/dev/null || echo "")
else
  # For stable releases, only look at stable tags (no beta in name)
  LATEST_TAG=$(git tag -l | grep -v -E "beta\." | sort -V | tail -1 2>/dev/null || echo "")
fi

if [ -n "$LATEST_TAG" ]; then
  # Get commits since the latest tag of the same type
  CHANGELOG_COMMITS=$(git log --oneline --no-merges "$LATEST_TAG"..HEAD 2>/dev/null)
  
  if [ -n "$CHANGELOG_COMMITS" ]; then
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
    echo "* No new commits since last ${PKG_RELEASE_TYPE:-stable} release" >> "$MANIFEST"
  fi
else
  # If no tags of this type exist, show recent commits
  RECENT_COMMITS=$(git log --oneline --no-merges -5 2>/dev/null)
  if [ -n "$RECENT_COMMITS" ]; then
    echo "### Recent Changes" >> "$MANIFEST"
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