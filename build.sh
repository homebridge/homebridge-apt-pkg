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

NODE_VERSION="$(curl -s https://nodejs.org/dist/index.json | jq -r 'map(select(.lts))[0].version')"

BUILD_ARCH=${QEMU_ARCH:-x86_64}

case "$BUILD_ARCH" in \
  x86_64) NODE_ARCH='x64';; \
  arm) NODE_ARCH='armv6l';; \
  aarch64) NODE_ARCH='arm64';; \
  i386) NODE_ARCH='x86';; \
  *) echo "unsupported architecture"; exit 1 ;;
esac

if [ ! -f  "node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" ]; then
  [ "$NODE_ARCH" = "armv6l" -o "$NODE_ARCH" = "x86" ] && 
    curl -SLO "https://unofficial-builds.nodejs.org/download/release/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" || 
    curl -SLO "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
fi
tar xzf "node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" -C staging/opt/homebridge/ --strip-components=1 --no-same-owner

PATH="$(pwd)/staging/opt/homebridge/bin:$PATH"
export npm_config_prefix=$(pwd)/staging/opt/homebridge

npm install --location=global pnpm homebridge-config-ui-x@4.48.0-test.3

rm -rf /var/lib/homebridge/node_modules
rm -rf /var/lib/homebridge/package.json
rm -rf /var/lib/homebridge/pnpm-lock.yaml

mkdir -p /var/lib/homebridge

pnpm install -C /var/lib/homebridge homebridge@latest

mkdir -p $(pwd)/staging/var/lib/homebridge
cp -R /var/lib/homebridge/node_modules $(pwd)/staging/var/lib/homebridge/node_modules
cp /var/lib/homebridge/package.json $(pwd)/staging/var/lib/homebridge/package.json
cp /var/lib/homebridge/pnpm-lock.yaml $(pwd)/staging/var/lib/homebridge/pnpm-lock.yaml

cd staging
dpkg-buildpackage -us -uc
