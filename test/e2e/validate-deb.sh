#!/bin/bash
#
# Installs a homebridge .deb on THIS machine and checks that it really works:
# it installs, the service starts, the UI answers, Homebridge itself is running, and the
# Node.js, Homebridge and UI versions are the ones the package says it ships.
#
# ONLY for throw-away machines: a CI runner, a VM or a container. It installs, removes and
# purges the homebridge package. It needs root. No token or secret is used.
#
# Usage: validate-deb.sh [options] <new.deb>
#        validate-deb.sh [options] --from-apt <channel>
#   --from-apt <channel>          check the package that https://repo.homebridge.io serves for
#                                 this channel, in place of a file
#   --expect-version <version>    with --from-apt: the version that must get installed
#   --upgrade-from <old.deb>      install this package first, add a plugin, then upgrade to <new.deb>
#   --upgrade-from-apt <channel>  the same, but the old package comes from https://repo.homebridge.io
#                                 (channel: stable, beta, alpha or legacy)
#   --lifecycle                   after the checks: remove, install again, then purge
#   --plugin <name>               plugin for the upgrade and lifecycle checks (default: homebridge-dummy)
#
# With systemd running, the real service is used. Without systemd (a plain container), the
# script starts /opt/homebridge/start.sh itself, as the service user.

set -uo pipefail

OLD_DEB=""
OLD_CHANNEL=""
LIFECYCLE=0
PLUGIN="homebridge-dummy"
NEW_DEB=""
NEW_CHANNEL=""
EXPECT_VERSION=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --upgrade-from)
      OLD_DEB="$2"
      shift 2
      ;;
    --upgrade-from-apt)
      OLD_CHANNEL="$2"
      shift 2
      ;;
    --from-apt)
      NEW_CHANNEL="$2"
      shift 2
      ;;
    --expect-version)
      EXPECT_VERSION="$2"
      shift 2
      ;;
    --lifecycle)
      LIFECYCLE=1
      shift
      ;;
    --plugin)
      PLUGIN="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      NEW_DEB="$1"
      shift
      ;;
  esac
done

if [ -z "$NEW_CHANNEL" ] && { [ -z "$NEW_DEB" ] || [ ! -f "$NEW_DEB" ]; }; then
  echo "usage: validate-deb.sh [--upgrade-from <old.deb> | --upgrade-from-apt <channel>] [--lifecycle] <new.deb>" >&2
  echo "       validate-deb.sh [--expect-version <version>] [--lifecycle] --from-apt <channel>" >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must run as root (it installs a package)." >&2
  exit 2
fi

[ -n "$NEW_DEB" ] && NEW_DEB=$(realpath "$NEW_DEB")
[ -n "$OLD_DEB" ] && OLD_DEB=$(realpath "$OLD_DEB")
STORAGE=/var/lib/homebridge
LOG="$STORAGE/homebridge.log"
START_LOG=/tmp/homebridge-start.log
START_PID=""
export DEBIAN_FRONTEND=noninteractive

step() { printf '\n=== %s\n' "$*"; }
pass() { printf '  ok    %s\n' "$*"; }

die() {
  printf '  FAIL  %s\n' "$*"
  echo
  echo "---- diagnostics ----"
  if have_systemd; then
    systemctl status homebridge.service --no-pager 2>&1 | head -n 20
    journalctl -u homebridge.service --no-pager -n 40 2>&1
  else
    tail -n 40 "$START_LOG" 2>&1
  fi
  tail -n 40 "$LOG" 2>&1
  ls -la /opt/homebridge "$STORAGE" 2>&1
  stop_service
  exit 1
}

have_systemd() { [ -d /run/systemd/system ]; }

# ---- starting and stopping -------------------------------------------------------------------

start_service() {
  if have_systemd; then
    systemctl start homebridge.service
  else
    # what the systemd unit does: the pre-start scripts as root, then start.sh as the service user
    USER=homebridge run-parts /etc/hb-service/homebridge/prestart.d
    (cd "$STORAGE" && exec runuser -u homebridge -- env HOME=/home/homebridge USER=homebridge /opt/homebridge/start.sh) > "$START_LOG" 2>&1 &
    START_PID=$!
  fi
}

stop_service() {
  if have_systemd; then
    systemctl stop homebridge.service 2> /dev/null
  elif [ -n "$START_PID" ]; then
    pkill -TERM -u homebridge 2> /dev/null
    wait "$START_PID" 2> /dev/null
    START_PID=""
  fi
  return 0
}

# ui_port: the port of the UI (8581 unless config.json says something else)
ui_port() {
  local port=""
  [ -f "$STORAGE/config.json" ] && port=$(jq -r '.platforms[]? | select(.platform == "config") | .port // empty' "$STORAGE/config.json" 2> /dev/null | head -n 1)
  echo "${port:-8581}"
}

# wait_until <seconds> <command...>: run the command once a second until it works
wait_until() {
  local seconds="$1" i
  shift
  for ((i = 0; i < seconds; i++)); do
    "$@" > /dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

port_open() { (exec 3<> "/dev/tcp/127.0.0.1/$1") 2> /dev/null; }
log_lines() { if [ -f "$LOG" ]; then wc -l < "$LOG"; else echo 0; fi; }
homebridge_started_after() { tail -n "+$(($1 + 1))" "$LOG" 2> /dev/null | grep -q "is running on port"; }

# check_running <log lines before the start>: the service, the UI and Homebridge itself
check_running() {
  local before="$1" port
  if have_systemd; then
    wait_until 60 systemctl is-active --quiet homebridge.service || die "the service did not become active"
    pass "the service is active"
  fi
  port=$(ui_port)
  wait_until 120 port_open "$port" || die "nothing listens on the UI port $port"
  hb-service status > /dev/null 2>&1 || die "'hb-service status' says the UI is not running"
  pass "the UI answers on port $port"
  wait_until 180 homebridge_started_after "$before" || die "Homebridge itself did not start (no 'is running on port' line in $LOG)"
  pass "Homebridge is running: $(tail -n "+$((before + 1))" "$LOG" | grep -m 1 -o 'Homebridge v[^ ]* .*is running on port [0-9]*')"
}

# ---- what must be true after an install ------------------------------------------------------

# packaged <name>: the version of a package that this .deb says it ships
packaged() { jq -r --arg name "$1" '.dependencies[$name] // empty' /opt/homebridge/package.json; }

check_versions() {
  local want have name
  want="v$(packaged node)"
  have=$(/opt/homebridge/bin/node -v 2>&1)
  [ "$have" = "$want" ] || die "Node.js is $have, the package says $want"
  pass "Node.js $have"

  /opt/homebridge/bin/node /opt/homebridge/bin/npm -v > /dev/null 2>&1 || die "npm does not run"
  pass "npm $(/opt/homebridge/bin/node /opt/homebridge/bin/npm -v)"

  want=$(packaged homebridge)
  have=$(jq -r .version "$STORAGE/node_modules/homebridge/package.json" 2>&1)
  [ "$have" = "$want" ] || die "Homebridge is $have, the package says $want"
  pass "Homebridge $have"

  want=$(packaged homebridge-config-ui-x)
  have=$(jq -r .version /opt/homebridge/lib/node_modules/homebridge-config-ui-x/package.json 2>&1)
  [ "$have" = "$want" ] || die "the UI is $have, the package says $want"
  pass "Homebridge UI $have"

  # anything else the package ships (alpha and beta: the updater plugin)
  for name in $(jq -r '.dependencies | keys[] | select(. != "node" and . != "homebridge" and . != "homebridge-config-ui-x")' /opt/homebridge/package.json); do
    want=$(packaged "$name")
    have=$(jq -r .version "$STORAGE/node_modules/$name/package.json" 2>&1)
    [ "$have" = "$want" ] || die "$name is $have, the package says $want"
    pass "$name $have"
  done

  # the shipped npm settings must not use options that npm warns about (they stop working later)
  local npm_warnings
  npm_warnings=$(
    cd "$STORAGE" || exit
    runuser -u homebridge -- env HOME=/home/homebridge sh -c '. /opt/homebridge/source.sh && npm config ls --loglevel=warn' 2>&1 | grep -i "^npm warn"
  ) || true
  [ -z "$npm_warnings" ] || die "npm warns about its settings: $npm_warnings"
  pass "npm has no complaint about the shipped settings"

  # the terminal in the UI needs this native module: it must load on this CPU type
  (cd /opt/homebridge/lib/node_modules/homebridge-config-ui-x && /opt/homebridge/bin/node -e 'require("@homebridge/node-pty-prebuilt-multiarch")') \
    || die "the node-pty module does not load on this machine"
  pass "the node-pty module loads"
}

check_owners() {
  local file
  for file in hb-service-shim hb-shell source.sh start.sh; do
    [ "$(stat -c %U "/opt/homebridge/$file")" = "root" ] || die "/opt/homebridge/$file does not belong to root"
    if runuser -u homebridge -- test -w "/opt/homebridge/$file"; then
      die "the service user can write to /opt/homebridge/$file"
    fi
  done
  pass "the scripts that root runs belong to root, and the service user can not change them"
  runuser -u homebridge -- test -w "$STORAGE" || die "the service user can not write to $STORAGE"
  runuser -u homebridge -- test -w /opt/homebridge/lib/node_modules || die "the service user can not update the UI in /opt/homebridge/lib"
  pass "the service user owns the storage folder and the Node.js runtime"
}

check_plugin_present() {
  [ -f "$STORAGE/node_modules/$PLUGIN/package.json" ] || die "the plugin $PLUGIN is not installed any more"
  jq -e --arg name "$PLUGIN" '.dependencies[$name] != null' "$STORAGE/package.json" > /dev/null || die "the plugin $PLUGIN is missing from package.json"
  pass "the plugin $PLUGIN is installed and in the plugin list"
}

install_deb() {
  apt-get install -y "$1" > /tmp/apt-install.log 2>&1 || {
    tail -n 40 /tmp/apt-install.log
    die "apt-get install $1 failed"
  }
  # warnings from the package scripts are worth seeing in the log of the check
  grep -E "WARNING|ERROR" /tmp/apt-install.log || true
}

# install_from_apt <channel>: install the package that repo.homebridge.io serves for a channel
install_from_apt() {
  if ! command -v curl > /dev/null || ! command -v gpg > /dev/null; then
    apt-get install -y curl gpg > /dev/null 2>&1 || die "could not install curl and gpg"
  fi
  curl -sSfL https://repo.homebridge.io/KEY.gpg | gpg --dearmor --yes -o /usr/share/keyrings/homebridge-validate.gpg || die "could not fetch the repository key"
  echo "deb [signed-by=/usr/share/keyrings/homebridge-validate.gpg] https://repo.homebridge.io $1 main" > /etc/apt/sources.list.d/homebridge-validate.list
  apt-get update > /dev/null 2>&1 || die "apt-get update with the homebridge repository failed"
  install_deb homebridge
  rm -f /etc/apt/sources.list.d/homebridge-validate.list /usr/share/keyrings/homebridge-validate.gpg
}

# install_new: the package under test, from a file or from the apt repository
install_new() {
  if [ -n "$NEW_CHANNEL" ]; then
    install_from_apt "$NEW_CHANNEL"
  else
    install_deb "$NEW_DEB"
  fi
}

# full_check <text>: everything that must hold after an install or an upgrade
full_check() {
  local before
  before=$(log_lines)
  if ! have_systemd; then
    start_service
  fi
  check_running "$before"
  check_versions
  check_owners
}

# ---- the run ---------------------------------------------------------------------------------

if [ -n "$NEW_CHANNEL" ]; then
  NEW_NAME="the $NEW_CHANNEL package from repo.homebridge.io"
else
  NEW_NAME=$(basename "$NEW_DEB")
fi

# The checks look at a first start, so the machine must not have the package yet.
if dpkg-query -W -f '${db:Status-Abbrev}' homebridge 2> /dev/null | grep -q '^.i'; then
  echo "The homebridge package is already installed on this machine. Use a fresh machine or container." >&2
  exit 2
fi

step "Preparing"
apt-get update > /dev/null 2>&1 || die "apt-get update failed"
pass "apt-get update"
# pkill is used to stop start.sh when there is no systemd
command -v pkill > /dev/null || apt-get install -y procps > /dev/null 2>&1 || die "could not install procps"
if have_systemd; then pass "systemd is running: the real service is used"; else pass "no systemd: start.sh is started by this script"; fi

if [ -n "$OLD_CHANNEL" ]; then
  step "Installing the published $OLD_CHANNEL package from repo.homebridge.io"
  install_from_apt "$OLD_CHANNEL"
  pass "installed homebridge $(dpkg-query -W -f '${Version}' homebridge)"
elif [ -n "$OLD_DEB" ]; then
  step "Installing the old package $(basename "$OLD_DEB")"
  install_deb "$OLD_DEB"
  pass "installed homebridge $(dpkg-query -W -f '${Version}' homebridge)"
fi

if [ -n "$OLD_CHANNEL$OLD_DEB" ]; then
  before=$(log_lines)
  have_systemd || start_service
  check_running "$before"
  step "Adding the plugin $PLUGIN to the old install"
  hb-service add "$PLUGIN" > /tmp/plugin-add.log 2>&1 || {
    tail -n 20 /tmp/plugin-add.log
    die "could not install the plugin $PLUGIN"
  }
  check_plugin_present
  have_systemd || stop_service
  step "Upgrading to $NEW_NAME"
else
  step "Installing $NEW_NAME"
fi

install_new
INSTALLED_VERSION=$(dpkg-query -W -f '${Version}' homebridge)
pass "installed homebridge $INSTALLED_VERSION"
if [ -n "$EXPECT_VERSION" ]; then
  [ "$INSTALLED_VERSION" = "$EXPECT_VERSION" ] || die "expected version $EXPECT_VERSION, but apt installed $INSTALLED_VERSION"
  pass "that is the expected version"
fi
full_check
if [ -n "$OLD_CHANNEL$OLD_DEB" ]; then
  check_plugin_present
  [ -f "$STORAGE/config.json" ] || die "config.json is gone after the upgrade"
  pass "config.json is still there"
fi

if [ "$LIFECYCLE" = "1" ]; then
  if [ -z "$OLD_CHANNEL$OLD_DEB" ]; then
    step "Adding the plugin $PLUGIN"
    hb-service add "$PLUGIN" > /tmp/plugin-add.log 2>&1 || {
      tail -n 20 /tmp/plugin-add.log
      die "could not install the plugin $PLUGIN"
    }
    check_plugin_present
  fi

  step "Removing the package (apt-get remove)"
  have_systemd || stop_service
  apt-get remove -y homebridge > /tmp/apt-remove.log 2>&1 || {
    tail -n 20 /tmp/apt-remove.log
    die "apt-get remove failed"
  }
  [ -f "$STORAGE/config.json" ] || die "config.json was deleted by a remove"
  pass "config.json is kept"
  [ ! -e /opt/homebridge/bin/node ] || die "/opt/homebridge still holds Node.js after a remove"
  [ ! -e /usr/local/bin/hb-service ] || die "the hb-service command is still there after a remove"
  pass "the program files are gone"
  if have_systemd && systemctl is-active --quiet homebridge.service; then
    die "the service still runs after a remove"
  fi

  step "Installing again"
  install_new
  full_check
  check_plugin_present

  step "Purging the package (apt-get purge)"
  have_systemd || stop_service
  apt-get purge -y homebridge > /tmp/apt-purge.log 2>&1 || {
    tail -n 20 /tmp/apt-purge.log
    die "apt-get purge failed"
  }
  [ ! -e "$STORAGE" ] || die "$STORAGE is still there after a purge"
  [ ! -e /var/lib/homebridge-apt-pkg ] || die "/var/lib/homebridge-apt-pkg is still there after a purge"
  [ ! -e /opt/homebridge ] || die "/opt/homebridge is still there after a purge"
  pass "the storage folder and the program files are gone"
else
  have_systemd || stop_service
fi

echo
echo "All checks passed."
