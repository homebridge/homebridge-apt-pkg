#!/usr/bin/env bash
#
# Checks on the stream files (<stream>/<32bit|64bit>/package.json) and the bot configs.
# These files decide which Node.js, Homebridge and UI versions a release ships.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXACT='^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$'

# dep <stream>/<arch> <package>: the pinned version
dep() { jq -r --arg p "$2" '.dependencies[$p] // ""' "$REPO/$1/package.json"; }

# at_least <version> <floor>: true when version is the same as floor or newer
at_least() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$2" ]; }

section "every stream file is valid and pins exact versions"
for stream in stable beta alpha legacy; do
  for arch in 32bit 64bit; do
    file="$REPO/$stream/$arch/package.json"
    assert_json "$file" "[.dependencies.node, .dependencies.homebridge, .dependencies[\"homebridge-config-ui-x\"]] | all(type == \"string\" and test(\"$EXACT\"))" \
      "$stream/$arch pins Node.js, Homebridge and the UI"
  done
  node32=$(dep "$stream/32bit" node)
  if [ "${node32%%.*}" -le 22 ]; then
    ok "$stream/32bit uses Node.js 22 or older (newer Node.js has no 32-bit build)"
  else
    fail "$stream/32bit uses Node.js 22 or older (newer Node.js has no 32-bit build)" "found: $node32"
  fi
done

section "legacy stays on the newest Homebridge 1.x, and on a Node.js that Homebridge 1.x supports"
# Homebridge 1.11.4 is the last 1.x release. It supports Node.js 18, 20, 22 and 24.
for arch in 32bit 64bit; do
  hb=$(dep "legacy/$arch" homebridge)
  assert_eq "1" "${hb%%.*}" "legacy/$arch ships Homebridge 1.x"
  if at_least "$hb" 1.11.4; then
    ok "legacy/$arch Homebridge is 1.11.4 or newer"
  else
    fail "legacy/$arch Homebridge is 1.11.4 or newer" "found: $hb"
  fi
  node=$(dep "legacy/$arch" node)
  if [ "${node%%.*}" -le 24 ]; then
    ok "legacy/$arch uses Node.js 24 or older"
  else
    fail "legacy/$arch uses Node.js 24 or older" "found: $node"
  fi
done
assert_json "$REPO/.github/homebridge-legacy-bot.json" \
  '[.directories[].packages[] | select(.name == "node") | .tag] == ["^22.x.x", "^24.x.x"]' \
  "the legacy bot keeps Node.js on 22 (32-bit) and 24 (64-bit)"

finish
