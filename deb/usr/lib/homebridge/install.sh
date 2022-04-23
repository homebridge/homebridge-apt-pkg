#!/bin/sh

HB_SERVICE_STORAGE_PATH="/var/lib/homebridge"

source "/usr/lib/homebridge/source.sh"

# install homebridge / homebridge ui
cd $HB_SERVICE_STORAGE_PATH
pnpm install --unsafe-perm homebridge@v1.4.1-beta.1 homebridge-config-ui-x@4.43.1-test.11
