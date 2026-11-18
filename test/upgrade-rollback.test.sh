#!/usr/bin/env bash
#
# A failed upgrade must leave the old install working.
# Order of the scripts, as dpkg runs them:
#   upgrade works:    preinst upgrade -> the new files are unpacked -> postinst configure
#   unpacking fails:  preinst upgrade -> dpkg puts the old files back -> postrm abort-upgrade

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake pstree chown adduser addgroup usermod ufw hostname npm getent
fake_systemctl
PREINST=$(sandbox_script deb/debian/preinst)
fake_runuser
POSTINST=$(sandbox_script deb/debian/postinst)
POSTRM=$(sandbox_script deb/debian/postrm)
STORAGE() { printf '%s\n' "$ROOT/var/lib/homebridge"; }
PTY_BUILD() { printf '%s\n' "$ROOT/opt/homebridge/lib/node_modules/homebridge-config-ui-x/node_modules/@homebridge/node-pty-prebuilt-multiarch/build"; }

# installed: an install where Homebridge was updated from the UI and node-pty was built locally
installed() {
  echo '{"dependencies":{"homebridge":"2.4.0","homebridge-foo":"^1.2.3"}}' > "$(STORAGE)/package.json"
  echo 'audit = false' > "$(STORAGE)/.npmrc"
  echo '{"name":"homebridge","version":"2.4.0"}' > "$(STORAGE)/node_modules/homebridge/package.json"
  echo 'updated from the UI' > "$(STORAGE)/node_modules/homebridge/file-dpkg-does-not-know"
  mkdir -p "$(PTY_BUILD)/Release"
  echo 'built here' > "$(PTY_BUILD)/Release/pty.node"
}

section "preinst upgrade deletes nothing"
sandbox_new keep
installed
run_in "$ROOT/cwd" "$BASH" "$PREINST" upgrade 2.0.25
assert_exists "$(STORAGE)/package.json" "package.json is still there (dpkg replaces it itself)"
assert_exists "$(STORAGE)/.npmrc" ".npmrc is still there"
assert_missing "$(STORAGE)/node_modules/homebridge" "the Homebridge folder is moved aside for the new files"
assert_exists "$(STORAGE)/node_modules/homebridge.apt-old/file-dpkg-does-not-know" "the old Homebridge folder is kept until the upgrade has worked"
assert_exists "$(PTY_BUILD).apt-old/Release/pty.node" "the old node-pty build is kept until the upgrade has worked"
assert_contains "$(stublog)" "[systemctl] stop homebridge.service" "the service is stopped"

section "unpacking fails: postrm abort-upgrade puts everything back and starts the service"
mkdir -p "$(STORAGE)/node_modules/homebridge" # what a half-finished unpack can leave behind
run_in "$ROOT/cwd" "$BASH" "$POSTRM" abort-upgrade 2.0.25
assert_eq '{"name":"homebridge","version":"2.4.0"}' "$(cat "$(STORAGE)/node_modules/homebridge/package.json")" "the old Homebridge is back"
assert_exists "$(STORAGE)/node_modules/homebridge/file-dpkg-does-not-know" "with all of its files"
assert_missing "$(STORAGE)/node_modules/homebridge.apt-old" "the moved-aside copy is gone"
assert_exists "$(PTY_BUILD)/Release/pty.node" "the node-pty build is back"
assert_json "$(STORAGE)/package.json" '.dependencies["homebridge-foo"] == "^1.2.3"' "the plugin list is the old one"
assert_eq "homebridge homebridge-bar homebridge-foo" "$(plugins)" "every plugin folder is still there"
assert_contains "$(stublog)" "[systemctl] start homebridge.service" "the service is started again"
assert_missing "$ROOT/var/lib/homebridge-apt-pkg/package.json.saved" "no saved copy is left for a later run to pick up"

section "unpacking fails, and the service was not running before"
sandbox_new stopped
installed
FAKE_ACTIVE=0 run_in "$ROOT/cwd" "$BASH" "$PREINST" upgrade 2.0.25
: > "$STUBLOG"
run_in "$ROOT/cwd" "$BASH" "$POSTRM" abort-upgrade 2.0.25
assert_exists "$(STORAGE)/node_modules/homebridge/file-dpkg-does-not-know" "the old Homebridge is back"
assert_not_contains "$(stublog)" "start homebridge.service" "the service is not started"

section "the upgrade works: postinst removes the old copies"
sandbox_new works
installed
run_in "$ROOT/cwd" "$BASH" "$PREINST" upgrade 2.0.25
mkdir -p "$(STORAGE)/node_modules/homebridge" # dpkg unpacks the new files
echo '{"name":"homebridge","version":"2.5.0"}' > "$(STORAGE)/node_modules/homebridge/package.json"
echo '{"dependencies":{"homebridge":"2.5.0"}}' > "$(STORAGE)/package.json"
touch "$(STORAGE)/package-lock.json" "$(STORAGE)/pnpm-lock.yaml"
run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_missing "$(STORAGE)/node_modules/homebridge.apt-old" "the old Homebridge folder is deleted"
assert_missing "$(PTY_BUILD).apt-old" "the old node-pty build is deleted"
assert_missing "$(PTY_BUILD)" "and it is not put back"
assert_missing "$(STORAGE)/package-lock.json" "package-lock.json is deleted"
assert_missing "$(STORAGE)/pnpm-lock.yaml" "pnpm-lock.yaml is deleted"
assert_json "$(STORAGE)/package.json" '.dependencies == {"homebridge":"2.5.0","homebridge-foo":"^1.2.3"}' "the plugin list is merged"
assert_missing "$(STORAGE)/node_modules/homebridge/file-dpkg-does-not-know" "no stale file is left in the new Homebridge folder"

finish
