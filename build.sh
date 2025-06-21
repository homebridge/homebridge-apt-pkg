#!/bin/bash

set -e
set -x

# Determine if beta or stable config should be used
if [[ "$PKG_RELEASE_TYPE" == "beta" ]]; then
  PACKAGE_JSON_PATH="beta/package.json"
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

BUILD_ARCH=${QEMU_ARCH:-x86_64}
case "$BUILD_ARCH" in
  x86_64) NODE_ARCH='x64' ;;
  arm) NODE_ARCH='armv7l' ;;
  aarch64) NODE_ARCH='arm64' ;;
  i386) NODE_ARCH='x86' ;;
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
    curl -SLO "https://unofficial-builds.nodejs.org/download/release/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
  else
    curl -SLO "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
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
echo "|Homebridge-Config-UI-X| $HOMEBRIDGE_UIX_VERSION |" >> "$MANIFEST"

npm install --prefix "$(pwd)/staging/var/lib/homebridge" homebridge@$HOMEBRIDGE_VERSION
echo "|Homebridge| $HOMEBRIDGE_VERSION |" >> "$MANIFEST"

# Build .deb
cd staging
dpkg-buildpackage -us -uc
cd ..

# Finalize manifest name
FINAL_MANIFEST=$(ls homebridge*.deb | sed -e 's/.deb/.manifest/')
mv "$MANIFEST" "$FINAL_MANIFEST"
cp "$FINAL_MANIFEST" staging/opt/homebridge