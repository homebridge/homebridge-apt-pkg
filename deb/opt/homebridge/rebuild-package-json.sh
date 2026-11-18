#!/bin/sh
#
# Prints a new plugin list (the content for package.json), built from what is installed in
# node_modules. Used when the real package.json is missing or damaged, so that no plugin has to
# be removed or installed again.
#
# Usage: rebuild-package-json.sh [storage path]      (default: /var/lib/homebridge)

STORAGE_PATH="${1:-/var/lib/homebridge}"

for manifest in "$STORAGE_PATH"/node_modules/*/package.json "$STORAGE_PATH"/node_modules/@*/*/package.json; do
  [ -f "$manifest" ] || continue
  # a plugin added with "hb-service link" is a link to a source folder, not an npm install
  [ -L "$(dirname "$manifest")" ] && continue
  jq -c 'select((.name | type) == "string" and (.version | type) == "string") | {(.name): .version}' "$manifest" 2> /dev/null
done | jq -s '{dependencies: ((add // {}) | del(.["homebridge-config-ui-x"]))}'
