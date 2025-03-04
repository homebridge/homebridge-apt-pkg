#!/bin/sh

HB_SERVICE_STORAGE_PATH="/var/lib/homebridge"
HB_SERVICE_NODE_EXEC_PATH="/opt/homebridge/bin/node"
HB_SERVICE_EXEC_PATH="/opt/homebridge/lib/node_modules/homebridge-config-ui-x/dist/bin/hb-service.js"

. "/opt/homebridge/source.sh"

cd $HB_SERVICE_STORAGE_PATH

# check for invalid package.json file
if [ -e $HB_SERVICE_STORAGE_PATH/package.json ]; then
  jq empty $HB_SERVICE_STORAGE_PATH/package.json 2>/dev/null
  if [ "$?" != 0 ]; then
    echo "ERROR: $HB_SERVICE_STORAGE_PATH/package.json is not a valid JSON file; deleting..."
    rm -rf $HB_SERVICE_STORAGE_PATH/package.json
    rm -rf $HB_SERVICE_STORAGE_PATH/package-lock.json
    rm -rf $HB_SERVICE_STORAGE_PATH/pnpm-lock.yaml
    rm -rf $HB_SERVICE_STORAGE_PATH/node_modules
  fi
fi

# remove the package-lock.json
if [ -e /var/lib/homebridge/package-lock.json ]; then
  rm -rf /var/lib/homebridge/package-lock.json
fi

# remove homebridge-config-ui-x package from the plugins store
if [ -e "/var/lib/homebridge/node_modules/homebridge-config-ui-x" ]; then
  rm -rf $HB_SERVICE_STORAGE_PATH/node_modules/homebridge-config-ui-x
fi

# remove homebridge package from the plugins store
if [ -e "/var/lib/homebridge/node_modules/homebridge" ]; then
  rm -rf $HB_SERVICE_STORAGE_PATH/node_modules/homebridge
fi

# homebridge is removed from the package.json only in postinst
# so this needs to be here on the first run to ensure the exidsting version is not reinstalled

# remove homebridge from the package.json
if [ -e /var/lib/homebridge/package.json ]; then
  if [ "$(cat /var/lib/homebridge/package.json | jq -r '.dependencies."homebridge"')" != "null" ]; then
    packageJson="$(cat /var/lib/homebridge/package.json | jq -rM 'del(."dependencies"."homebridge")')"
    if [ "$?" = "0" ]; then
      printf "$packageJson" > /var/lib/homebridge/package.json
      echo "Removed homebridge from package.json"
    fi
  fi
fi

exec $HB_SERVICE_NODE_EXEC_PATH $HB_SERVICE_EXEC_PATH run -I -U $HB_SERVICE_STORAGE_PATH -P $HB_SERVICE_STORAGE_PATH/node_modules --strict-plugin-resolution "$@"
