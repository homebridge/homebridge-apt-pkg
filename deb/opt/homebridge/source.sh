#!/bin/sh

NODE_BIN_PATH="/opt/homebridge/bin"
HB_SERVICE_STORAGE_PATH="/var/lib/homebridge"

export PATH="$NODE_BIN_PATH:$HB_SERVICE_STORAGE_PATH/node_modules/.bin:$PATH"

export npm_config_global_style=true
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export npm_config_store_dir=$HB_SERVICE_STORAGE_PATH/node_modules/.pnpm-store
export npm_config_prefix=/opt/homebridge
export npm_config_global_pnpmfile=/opt/homebridge/global_pnpmfile.cjs

export HOMEBRIDGE_APT_PACKAGE=1
export UIX_CUSTOM_PLUGIN_PATH=$HB_SERVICE_STORAGE_PATH/node_modules
export UIX_BASE_PATH_OVERRIDE=$HB_SERVICE_STORAGE_PATH/node_modules/homebridge-config-ui-x
export UIX_USE_PNPM=1
