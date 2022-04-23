#!/bin/bash

set -e
set -x

rm -rf staging
cp -R deb staging

NODE_VERSION="$(curl -s https://nodejs.org/dist/index.json | jq -r 'map(select(.lts))[0].version')"

case $(uname -m) in \
  x86_64) NODE_ARCH='x64';; \
  armv6l) NODE_ARCH='armv6l';; \
  armv7l) NODE_ARCH='armv6l';; \
  aarch64) NODE_ARCH='arm64';; \
  i386) NODE_ARCH='x86';; \
  *) echo "unsupported architecture"; exit 1 ;;
esac

[ "$NODE_ARCH" = "armv6l" -o "$NODE_ARCH" = "x86" ] && 
  curl -SLO "https://unofficial-builds.nodejs.org/download/release/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" || 
  curl -SLO "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
tar xzf "node-$NODE_VERSION-linux-$NODE_ARCH.tar.gz" -C staging/usr/lib/homebridge/ --strip-components=1 --no-same-owner

PATH="$(pwd)/staging/usr/lib/homebridge/bin:$PATH"
export npm_config_prefix=$(pwd)/staging/usr/lib/homebridge
export npm_config_store_dir=/var/lib/homebridge/node_modules/.pnpm-store

npm install -g pnpm

rm -rf /var/lib/homebridge/node_modules
rm -rf /var/lib/homebridge/package.json
rm -rf /var/lib/homebridge/pnpm-lock.yaml

mkdir -p /var/lib/homebridge

pnpm install -C /var/lib/homebridge homebridge@1.4.1-beta.1 homebridge-config-ui-x@4.43.2-test.2

mkdir -p $(pwd)/staging/var/lib/homebridge
cp -R /var/lib/homebridge/node_modules $(pwd)/staging/var/lib/homebridge/node_modules
cp /var/lib/homebridge/package.json $(pwd)/staging/var/lib/homebridge/package.json
cp /var/lib/homebridge/pnpm-lock.yaml $(pwd)/staging/var/lib/homebridge/pnpm-lock.yaml

cd staging
dpkg-buildpackage -us -uc
