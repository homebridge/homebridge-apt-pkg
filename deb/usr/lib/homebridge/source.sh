#!/bin/sh

nodeBin="/usr/lib/homebridge/bin"
HB_SERVICE_STORAGE_PATH="/var/lib/homebridge"

export PATH="$nodeBin:$HB_SERVICE_STORAGE_PATH/node_modules/.bin:$PATH"
export PYTHON=/usr/bin/python3.8

export npm_config_global_style=true
export npm_config_audit=false
export npm_config_fund=false
export npm_config_store_dir=$HB_SERVICE_STORAGE_PATH/node_modules/.pnpm-store
export npm_config_prefix=/usr/lib/homebridge

export HOMEBRIDGE_APT_PACKAGE=1
export UIX_BASE_PATH_OVERRIDE=$HB_SERVICE_STORAGE_PATH/node_modules/homebridge-config-ui-x
export UIX_USE_PNPM=1
