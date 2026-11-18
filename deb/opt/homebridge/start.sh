#!/bin/sh

HB_SERVICE_STORAGE_PATH="/var/lib/homebridge"
HB_SERVICE_NODE_EXEC_PATH="/opt/homebridge/bin/node"
HB_SERVICE_EXEC_PATH="/opt/homebridge/lib/node_modules/homebridge-config-ui-x/dist/bin/hb-service.js"

. "/opt/homebridge/source.sh"

cd $HB_SERVICE_STORAGE_PATH

# The plugin list (package.json) must be a JSON object. A power loss while npm writes the file can
# leave it empty or cut short. NEVER delete the plugins when that happens: keep the bad file under
# another name, and write a new list from what is installed in node_modules.
PACKAGE_JSON="$HB_SERVICE_STORAGE_PATH/package.json"

rebuild_package_json() {
  for manifest in "$HB_SERVICE_STORAGE_PATH"/node_modules/*/package.json "$HB_SERVICE_STORAGE_PATH"/node_modules/@*/*/package.json; do
    [ -f "$manifest" ] || continue
    # a plugin added with "hb-service link" is a link to a source folder, not an npm install
    [ -L "$(dirname "$manifest")" ] && continue
    jq -c 'select((.name | type) == "string" and (.version | type) == "string") | {(.name): .version}' "$manifest" 2> /dev/null
  done | jq -s '{dependencies: ((add // {}) | del(.["homebridge-config-ui-x"]))}' > "$PACKAGE_JSON.new" \
    && mv -f "$PACKAGE_JSON.new" "$PACKAGE_JSON"
}

if [ -e "$PACKAGE_JSON" ] && ! jq -e 'type == "object"' "$PACKAGE_JSON" > /dev/null 2>&1; then
  BROKEN_COPY="$PACKAGE_JSON.broken-$(date +%Y%m%d-%H%M%S)"
  echo "ERROR: $PACKAGE_JSON is not a valid JSON file. It is kept as $BROKEN_COPY."
  echo "Writing a new plugin list from the plugins found in node_modules. No plugin is removed."
  mv -f "$PACKAGE_JSON" "$BROKEN_COPY"
  rebuild_package_json || echo "ERROR: could not write a new $PACKAGE_JSON."
fi

# remove the package-lock.json
if [ -e /var/lib/homebridge/package-lock.json ]; then
  rm -rf /var/lib/homebridge/package-lock.json
fi

# check for missing homebridge
if [ ! -f "$HB_SERVICE_STORAGE_PATH/node_modules/homebridge/package.json" ]; then
  cd $HB_SERVICE_STORAGE_PATH
  echo "Re-installing homebridge..."
  npm --prefix $HB_SERVICE_STORAGE_PATH install --save homebridge@latest
fi

# remove homebridge-config-ui-x package from the plugins store
if [ -e "/var/lib/homebridge/node_modules/homebridge-config-ui-x" ]; then
  rm -rf $HB_SERVICE_STORAGE_PATH/node_modules/homebridge-config-ui-x
fi

exec $HB_SERVICE_NODE_EXEC_PATH $HB_SERVICE_EXEC_PATH run -I -U $HB_SERVICE_STORAGE_PATH -P $HB_SERVICE_STORAGE_PATH/node_modules --strict-plugin-resolution "$@"
