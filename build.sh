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

if [[ ! -z ${PKG_RELEASE_TYPE+z} ]] && [[ ! -z ${PKG_RELEASE_VERSION+z} ]]; then
  if [ "$PKG_RELEASE_TYPE" != "stable" ]; then
    PKG_RELEASE_TYPE="UNRELEASED"
  fi
  cd deb
    dch -b -v "$PKG_RELEASE_VERSION" --controlmaint "Automated Release" --distribution "$PKG_RELEASE_TYPE"
  cd ../
fi

rm -rf staging
cp -R deb staging

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

echo "Homebridge Apt Package Manifest" > homebridge_apt_pkg_$NODE_ARCH.manifest
echo >> homebridge_apt_pkg_$NODE_ARCH.manifest

# Add release version and type
echo "**Release Version**: ${PKG_RELEASE_VERSION:-unknown}" >> homebridge_apt_pkg_$NODE_ARCH.manifest
echo "**Release Type**: ${PKG_RELEASE_TYPE:-stable}" >> homebridge_apt_pkg_$NODE_ARCH.manifest
echo >> homebridge_apt_pkg_$NODE_ARCH.manifest
echo "| Package | Version |" >> homebridge_apt_pkg_$NODE_ARCH.manifest
echo "|:-------:|:-------:|" >> homebridge_apt_pkg_$NODE_ARCH.manifest
echo "|NodeJS| $NODE_VERSION |" >> homebridge_apt_pkg_$NODE_ARCH.manifest

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

npm install --location=global homebridge-config-ui-x@$HOMEBRIDGE_UIX_VERSION
echo "|Homebridge-Config-UI-X| $HOMEBRIDGE_UIX_VERSION |" >> homebridge_apt_pkg_$NODE_ARCH.manifest

npm install --prefix "$(pwd)/staging/var/lib/homebridge" homebridge@$HOMEBRIDGE_VERSION
echo "|Homebridge| $HOMEBRIDGE_VERSION |" >> homebridge_apt_pkg_$NODE_ARCH.manifest

cd staging
dpkg-buildpackage -us -uc
cd ..

MANIFEST=$(ls homebridge*.deb | sed -e 's/.deb/.manifest/g')
mv homebridge_apt_pkg_$NODE_ARCH.manifest "$MANIFEST"
