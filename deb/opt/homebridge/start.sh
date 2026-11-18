#!/bin/sh

HB_SERVICE_STORAGE_PATH="/var/lib/homebridge"
HB_SERVICE_NODE_EXEC_PATH="/opt/homebridge/bin/node"
HB_SERVICE_EXEC_PATH="/opt/homebridge/lib/node_modules/homebridge-config-ui-x/dist/bin/hb-service.js"

# shellcheck source=deb/opt/homebridge/source.sh
. "/opt/homebridge/source.sh"

cd "$HB_SERVICE_STORAGE_PATH" || exit 1

# The plugin list (package.json) must be a JSON object. A power loss while npm writes the file can
# leave it empty or cut short. NEVER delete the plugins when that happens: keep the bad file under
# another name, and write a new list from what is installed in node_modules.
PACKAGE_JSON="$HB_SERVICE_STORAGE_PATH/package.json"

if [ -e "$PACKAGE_JSON" ] && ! jq -e 'type == "object"' "$PACKAGE_JSON" > /dev/null 2>&1; then
  BROKEN_COPY="$PACKAGE_JSON.broken-$(date +%Y%m%d-%H%M%S)"
  echo "ERROR: $PACKAGE_JSON is not a valid JSON file. It is kept as $BROKEN_COPY."
  echo "Writing a new plugin list from the plugins found in node_modules. No plugin is removed."
  mv -f "$PACKAGE_JSON" "$BROKEN_COPY"
  if /opt/homebridge/rebuild-package-json.sh "$HB_SERVICE_STORAGE_PATH" > "$PACKAGE_JSON.new"; then
    mv -f "$PACKAGE_JSON.new" "$PACKAGE_JSON"
  else
    echo "ERROR: could not write a new $PACKAGE_JSON."
  fi
fi

# remove the package-lock.json
if [ -e /var/lib/homebridge/package-lock.json ]; then
  rm -rf /var/lib/homebridge/package-lock.json
fi

# check for missing homebridge
if [ ! -f "$HB_SERVICE_STORAGE_PATH/node_modules/homebridge/package.json" ]; then
  # Install the version this package was built with, not "latest". "latest" would move a legacy
  # (Homebridge 1.x) install to Homebridge 2, and a beta install off the beta line.
  HOMEBRIDGE_VERSION=$(jq -er '.dependencies.homebridge | strings' /opt/homebridge/package.json 2> /dev/null)
  if [ -z "$HOMEBRIDGE_VERSION" ]; then
    echo "WARNING: could not read the packaged Homebridge version from /opt/homebridge/package.json, using 'latest'."
    HOMEBRIDGE_VERSION=latest
  fi
  echo "Re-installing homebridge@$HOMEBRIDGE_VERSION..."
  if ! npm --prefix "$HB_SERVICE_STORAGE_PATH" install --save "homebridge@$HOMEBRIDGE_VERSION"; then
    # the service manager starts this script again at once: wait, so a machine with no network
    # does not try every few seconds
    echo "ERROR: could not install homebridge@$HOMEBRIDGE_VERSION. Is the network up? Trying again in 30 seconds."
    sleep 30
    exit 1
  fi
fi

# remove homebridge-config-ui-x package from the plugins store
if [ -e "/var/lib/homebridge/node_modules/homebridge-config-ui-x" ]; then
  rm -rf "$HB_SERVICE_STORAGE_PATH/node_modules/homebridge-config-ui-x"
fi

exec "$HB_SERVICE_NODE_EXEC_PATH" "$HB_SERVICE_EXEC_PATH" run -I -U "$HB_SERVICE_STORAGE_PATH" -P "$HB_SERVICE_STORAGE_PATH/node_modules" --strict-plugin-resolution "$@"
