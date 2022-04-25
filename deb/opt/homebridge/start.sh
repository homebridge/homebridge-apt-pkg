#!/bin/sh

HB_SERVICE_STORAGE_PATH="/var/lib/homebridge"
HB_SERVICE_NODE_EXEC_PATH="/opt/homebridge/bin/node"
HB_SERVICE_EXEC_PATH="$HB_SERVICE_STORAGE_PATH/node_modules/homebridge-config-ui-x/dist/bin/hb-service.js"

. "/opt/homebridge/source.sh"

# check for missing homebridge-config-ui-x
if [ ! -f "$HB_SERVICE_EXEC_PATH" ]; then
  cd $HB_SERVICE_STORAGE_PATH
  pnpm install homebridge-config-ui-x@latest
fi

# check for missing homebridge
if [ ! -f "$HB_SERVICE_STORAGE_PATH/node_modules/homebridge/package.json" ]; then
  cd $HB_SERVICE_STORAGE_PATH
  pnpm install homebridge@latest
fi

env > /tmp/env-dump

exec $HB_SERVICE_NODE_EXEC_PATH $HB_SERVICE_EXEC_PATH run -I -U $HB_SERVICE_STORAGE_PATH -P $HB_SERVICE_STORAGE_PATH/node_modules --strict-plugin-resolution
