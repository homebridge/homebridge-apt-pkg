#!/bin/bash

set -e
set -x

if [[ ! -z ${PKG_RELEASE_TYPE+z} ]] && [[ ! -z ${PKG_RELEASE_VERSION+z} ]]; then
  if [ "$PKG_RELEASE_TYPE" != "stable" ]; then
    PKG_RELEASE_TYPE="UNRELEASED"
  fi
  cd deb
    dch -b -v $PKG_RELEASE_VERSION --controlmaint "Automated Release" --distribution "$PKG_RELEASE_TYPE"
  cd ../
fi

rm -rf staging
cp -R deb staging

# Hold the NodeJS version to the 20.x LTS stream until 22 goes LTS
# deb/debian/control `libc6 (>= 2.31)` may need updating as well
# Supposedly they are using 2.28 - https://github.com/nodejs/node/blob/main/BUILDING.md

NODE_LTS_TAG="Iron"
# NODE_VERSION="$(curl -s https://nodejs.org/dist/index.json | jq -r --arg NODE_LTS_TAG "${NODE_LTS_TAG}" 'map(select(.lts==$NODE_LTS_TAG))[0].version')"
NODE_VERSION=$(cat package.json | jq -r '.dependencies.node | gsub("^\\^"; "v")')

BUILD_ARCH=${QEMU_ARCH:-x86_64}

case "$BUILD_ARCH" in \
  x86_64) NODE_ARCH='x64';; \
  arm) NODE_ARCH='armv7l';; \
  aarch64) NODE_ARCH='arm64';; \
  i386) NODE_ARCH='x86';; \
  *) echo "unsupported architecture"; exit 1 ;;
esac

echo "Homebridge Apt Package Manifest" > homebridge_apt_pkg_$NODE_ARCH.manifest
echo >> homebridge_apt_pkg_$NODE_ARCH.manifest
echo "| Package | Version |" >> homebridge_apt_pkg_$NODE_ARCH.manifest
echo "|:-------:|:-------:|" >> homebridge_apt_pkg_$NODE_ARCH.manifest
echo "|NodeJS| "$NODE_VERSION "|" >> homebridge_apt_pkg_$NODE_ARCH.manifest

# https://nodejs.org/dist/v22.12.0/node-v22.12.0-linux-armv7l.tar.gz

if [ ! -f  "node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" ]; then
  [ "$NODE_ARCH" = "armv6l" -o "$NODE_ARCH" = "x86" ] && 
    curl -SLO "https://unofficial-builds.nodejs.org/download/release/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" || 
    curl -SLO "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
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

npm install --location=global homebridge-config-ui-x

HOMBRIDGE_CONFIG_VERSION="$(npm list -g --json=true | jq --raw-output '{version: .dependencies."homebridge-config-ui-x".version}.version')"
echo "|Homebridge-Config-UI-X|" $HOMBRIDGE_CONFIG_VERSION "|" >> homebridge_apt_pkg_$NODE_ARCH.manifest

npm install --prefix $(pwd)/staging/var/lib/homebridge homebridge

CWD=`pwd`
cd staging/var/lib/homebridge
HOMBRIDGE_VERSION="$(npm list --json=true | jq --raw-output '{version: .dependencies."homebridge".version}.version')"
echo "|Homebridge|" $HOMBRIDGE_VERSION "|" >> ${CWD}/homebridge_apt_pkg_$NODE_ARCH.manifest

cd ${CWD}/staging
dpkg-buildpackage -us -uc

cd ${CWD}
MANIFEST=$(ls homebridge*.deb | sed -e 's/.deb/.manifest/g')
mv ${CWD}/homebridge_apt_pkg_$NODE_ARCH.manifest ${CWD}/$MANIFEST
