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

section "the stream files hold nothing that is never used"
for stream in stable beta alpha legacy; do
  for arch in 32bit 64bit; do
    assert_json "$REPO/$stream/$arch/package.json" '.name == "@homebridge/homebridge-apt-pkg" and (has("scripts") | not)' \
      "$stream/$arch: the published name, and no scripts (the publish job sets its own)"
  done
done
for unused in .github/release-drafter.yml .github/release.yml .npmignore; do
  assert_missing "$REPO/$unused" "$unused (no workflow used it) is gone"
done
assert_contains "$(cat "$REPO/.github/workflows/pr-labeler.yml")" "workflows/labeler.yml@latest" "the labeler workflow is the one that reads .github/labeler.yml"

section "the package details"
control=$(cat "$REPO/deb/debian/control")
assert_contains "$control" "Section: net" "the section is a real Debian section"
assert_contains "$control" "Homepage: https://homebridge.io" "the homepage uses https"
assert_eq "3" "$(grep -c '^ [A-Za-z]' "$REPO/deb/debian/control")" "the description has a few lines of text under its first line"

section "the cache purge list names every index file of every channel that is built, and nothing else"
expected=$(
  echo "https://repo.homebridge.io/KEY.gpg"
  for channel in stable beta alpha legacy; do
    for file in InRelease Release Release.gpg; do echo "https://repo.homebridge.io/dists/$channel/$file"; done
    for arch in amd64 arm64 armhf; do
      echo "https://repo.homebridge.io/dists/$channel/main/binary-$arch/Packages"
      echo "https://repo.homebridge.io/dists/$channel/main/binary-$arch/Packages.gz"
    done
  done
)
assert_eq "$(printf '%s\n' "$expected" | sort)" "$(jq -r '.files[]' "$REPO/repo/cf-cache-purge-urls.json" | sort)" \
  "stable, beta, alpha and legacy; amd64, arm64 and armhf (no 'test' channel, no i386)"

section "what the stream files list, the bots track, and build.sh installs is the same set"
for stream in stable beta alpha legacy; do
  for arch in 32bit 64bit; do
    listed=$(jq -c '.dependencies | keys' "$REPO/$stream/$arch/package.json")
    tracked=$(jq -c --arg d "$stream/$arch" '[.directories[] | select(.directory == $d) | .packages[].name] | sort' "$REPO/.github/homebridge-$stream-bot.json")
    assert_eq "$listed" "$tracked" "$stream/$arch: the bot tracks every listed package, and nothing else"
    for name in $(jq -r '.dependencies | keys[]' "$REPO/$stream/$arch/package.json"); do
      if grep -q -F -- ".dependencies[\"$name\"]" "$REPO/build.sh" || grep -q -F -- ".dependencies.$name" "$REPO/build.sh"; then
        ok "$stream/$arch: build.sh reads the version of $name"
      else
        fail "$stream/$arch: build.sh reads the version of $name" "build.sh never uses this package, so it is tracked for nothing"
      fi
    done
  done
done
assert_eq "" "$(grep -rl 'homebridge-plugin-update-check' "$REPO/alpha" "$REPO/beta" "$REPO/stable" "$REPO/legacy" "$REPO/.github"/homebridge-*-bot.json "$REPO/build.sh")" \
  "the old update-check plugin is not named in the stream files, bot configs or build.sh"

section "npm settings: nothing that npm warns about, and the same npm in every stream"
for file in deb/var/lib/homebridge/.npmrc deb/opt/homebridge/source.sh build.sh; do
  text=$(cat "$REPO/$file")
  assert_not_contains "$text" "auto-install-peers" "$file: no auto-install-peers (a pnpm setting; npm 11 warns about it)"
  assert_not_contains "$text" "auto_install_peers" "$file: no auto_install_peers"
  assert_not_contains "$text" "global-style" "$file: no global-style (deprecated)"
  assert_not_contains "$text" "global_style" "$file: no global_style (deprecated)"
done
assert_contains "$(cat "$REPO/deb/var/lib/homebridge/.npmrc")" 'install-strategy = "shallow"' ".npmrc uses install-strategy (the new name of global-style)"
assert_contains "$(cat "$REPO/deb/opt/homebridge/source.sh")" "npm_config_install_strategy=shallow" "source.sh uses install-strategy"
assert_not_contains "$(cat "$REPO/build.sh")" "npm@latest" "build.sh does not replace npm in some streams only"

section "build.sh works on a copy and builds the package only"
build=$(cat "$REPO/build.sh")
copy_line=$(grep -n '^cp -R deb staging' "$REPO/build.sh" | cut -d: -f1)
dch_line=$(grep -n 'dch -b -v' "$REPO/build.sh" | cut -d: -f1)
if [ -n "$copy_line" ] && [ -n "$dch_line" ] && [ "$copy_line" -lt "$dch_line" ]; then
  ok "the version is written after the copy is made"
else
  fail "the version is written after the copy is made" "copy at line ${copy_line:-none}, dch at line ${dch_line:-none}"
fi
assert_contains "$build" "(cd staging && dch " "dch runs inside the copy, not in deb/"
assert_contains "$build" "dpkg-buildpackage -us -uc -b" "no source archive is built"
assert_not_contains "$build" "git config --global" "the global git config is not changed"

finish
