#!/bin/bash

# Homebridge APT Package Build Script
# 
# This script builds Debian packages for Homebridge across multiple architectures.
# 
# IMPORTANT: Node.js Version Constraints
# - Node.js 23+ has no 32-bit builds
# - This script refuses Node.js above 22 for the 32-bit ARM build
# - 64-bit architectures (x86_64, aarch64) can use any Node.js version
#
# Package Configuration (PKG_RELEASE_TYPE is stable, beta, alpha or legacy):
# - <type>/64bit/package.json for x86_64 and aarch64
# - <type>/32bit/package.json for arm
#
# Run ./test/run.sh streams to verify the package configurations before building

set -e
set -x

#trap 'rm -rf staging *.tar.gz *.manifest /tmp/*' EXIT

# The architecture to build for: x86_64, aarch64 or arm
BUILD_ARCH=${QEMU_ARCH:-aarch64}

# Determine config directory based on release type (default to stable)
case "${PKG_RELEASE_TYPE}" in
  alpha|beta|legacy|stable) RELEASE_DIR="${PKG_RELEASE_TYPE}" ;;
  *) echo "unsupported release type: ${PKG_RELEASE_TYPE}"; exit 1 ;;
esac

# Map build architecture to 64bit/32bit subdir
case "${BUILD_ARCH}" in
  x86_64|aarch64) ARCH_DIR="64bit" ;;
  arm) ARCH_DIR="32bit" ;;
  *) echo "unsupported architecture: ${BUILD_ARCH}"; exit 1 ;;
esac

PACKAGE_JSON_PATH="${RELEASE_DIR}/${ARCH_DIR}/package.json"

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

# Work on a copy, so that a build never changes a file that git tracks
rm -rf staging
cp -R deb staging

# Write the version into the copy of debian/changelog
if [[ -n "${PKG_RELEASE_TYPE}" && -n "${PKG_RELEASE_VERSION}" ]]; then
  DISTRO="$PKG_RELEASE_TYPE"
  if [ "$PKG_RELEASE_TYPE" != "stable" ]; then
    DISTRO="UNRELEASED"
  fi
  (cd staging && dch -b -v "$PKG_RELEASE_VERSION" --controlmaint "Automated Release" --distribution "$DISTRO" "Automated release for $PKG_RELEASE_VERSION")
fi

cp "$PACKAGE_JSON_PATH" staging/opt/homebridge/package.json

NODE_VERSION=$(jq -r '.dependencies.node | ltrimstr("^") | "v" + .' "$PACKAGE_JSON_PATH")
HOMEBRIDGE_VERSION=$(jq -r '.dependencies["homebridge"]' "$PACKAGE_JSON_PATH")
HOMEBRIDGE_UIX_VERSION=$(jq -r '.dependencies["homebridge-config-ui-x"]' "$PACKAGE_JSON_PATH")
HOMEBRIDGE_UPDATER_VERSION=$(jq -r '.dependencies["@homebridge-plugins/homebridge-updater"]' "$PACKAGE_JSON_PATH")

MAJOR_NODE=$(jq -r '.dependencies.node | gsub("^\\^"; "")' "$PACKAGE_JSON_PATH" | cut -d. -f1)

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

# Download the NodeJS binary and check it against Node's published checksums, then unpack it
./scripts/fetch-node.sh "$NODE_VERSION" "$NODE_ARCH"
tar xzf "node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" -C staging/opt/homebridge/ --strip-components=1 --no-same-owner

PATH="$(pwd)/staging/opt/homebridge/bin:$PATH"

export npm_config_prefix=$(pwd)/staging/opt/homebridge
export npm_config_install_strategy=shallow
export npm_config_package_lock=false
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export npm_config_loglevel=error

# Every stream ships the npm that comes with its Node.js. (Alpha and beta used to get the
# newest npm, so they never tested the npm that stable users run.)
echo "Using npm $(npm -v)"

# Install packages
npm install --location=global homebridge-config-ui-x@$HOMEBRIDGE_UIX_VERSION
echo "| Homebridge UI | $HOMEBRIDGE_UIX_VERSION |" >> "$MANIFEST"

# Only install the Homebridge Updater plugin if the stream lists it (alpha and beta do)
if [ "$HOMEBRIDGE_UPDATER_VERSION" != "null" ]; then
  npm install --prefix "$(pwd)/staging/var/lib/homebridge" "@homebridge-plugins/homebridge-updater@$HOMEBRIDGE_UPDATER_VERSION"
  echo "| Homebridge Updater | $HOMEBRIDGE_UPDATER_VERSION |" >> "$MANIFEST"
fi

npm install --prefix "$(pwd)/staging/var/lib/homebridge" homebridge@$HOMEBRIDGE_VERSION
echo "| Homebridge | $HOMEBRIDGE_VERSION |" >> "$MANIFEST"

# The 64-bit and 32-bit packages can ship different Node.js versions (Node.js 23 and newer have
# no 32-bit build). The release notes are taken from a 64-bit build, so say it there.
if [ "$ARCH_DIR" = "64bit" ]; then
  NODE_VERSION_32BIT=$(jq -r '.dependencies.node // empty' "$RELEASE_DIR/32bit/package.json")
  if [ -n "$NODE_VERSION_32BIT" ] && [ "v$NODE_VERSION_32BIT" != "$NODE_VERSION" ]; then
    echo >> "$MANIFEST"
    echo "The 32-bit ARM (armhf) package ships NodeJS v$NODE_VERSION_32BIT." >> "$MANIFEST"
  fi
fi

# Add the "What's Changed" section to the manifest
./scripts/write-changelog.sh "$PKG_RELEASE_TYPE" "$ARCH_DIR" "$MANIFEST"

cp "$MANIFEST" staging/opt/homebridge
# Build the .deb only ("-b"). Without "-b" a source archive with Node.js and every module in it
# is built too, and nothing uses it.
cd staging
dpkg-buildpackage -us -uc -b
cd ..

# Finalize manifest name
FINAL_MANIFEST=$(ls homebridge*.deb | sed -e 's/.deb/.manifest/')
mv "$MANIFEST" "$FINAL_MANIFEST"