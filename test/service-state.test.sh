#!/usr/bin/env bash
#
# What postinst does with the systemd service on a first install, an upgrade and a re-install.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake pstree chown adduser addgroup usermod ufw hostname npm getent
fake_systemctl
fake_runuser
POSTINST=$(sandbox_script deb/debian/postinst)
PRERM=$(sandbox_script deb/debian/prerm)
STATE() { printf '%s\n' "$ROOT/var/lib/homebridge-apt-pkg"; }

# systemd_is_running: what a booted system looks like to the script
systemd_is_running() { mkdir -p "$ROOT/run/systemd/system"; }
unpacked() { echo '{"dependencies":{"homebridge":"2.5.0"}}' > "$ROOT/var/lib/homebridge/package.json"; }

section "first install: the service is turned on and started"
sandbox_new first
systemd_is_running
unpacked
FAKE_ACTIVE=0 run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure
log=$(stublog)
assert_contains "$log" "[systemctl] enable homebridge.service" "enable"
assert_contains "$log" "[systemctl] restart homebridge.service" "start"
assert_not_contains "$log" "unmask" "a mask is never removed"
assert_contains "$OUT" "Homebridge Installation Complete!" "the welcome text is shown"

section "first install with a config.json whose UI block has no port"
sandbox_new first-no-port
systemd_is_running
unpacked
echo '{"platforms":[{"platform":"config"}]}' > "$ROOT/var/lib/homebridge/config.json"
mkdir -p "$ROOT/usr/sbin"
touch "$ROOT/usr/sbin/ufw"
fake_script ufw << 'EOF'
#!/bin/sh
echo "[ufw] $*" >> "$STUBLOG"
[ "$1" = "status" ] && echo "Status: active"
exit 0
EOF
fake_script hostname << 'EOF'
#!/bin/sh
echo "192.0.2.10"
EOF
FAKE_ACTIVE=0 run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure
assert_contains "$(stublog)" "[ufw] allow 8581/tcp" "the firewall rule is for port 8581 (the old code tried 'null/tcp')"
assert_contains "$OUT" "* http://192.0.2.10:8581" "the printed address uses port 8581"
assert_not_contains "$OUT" "null" "the word null is not printed"
fake ufw hostname

section "upgrade, the service was running: it is started again, nothing else changes"
sandbox_new upgrade-running
systemd_is_running
unpacked
mkdir -p "$(STATE)"
touch "$(STATE)/was-running" # left by "preinst upgrade" when it stopped the service
FAKE_ACTIVE=0 run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
log=$(stublog)
assert_contains "$log" "[systemctl] restart homebridge.service" "start"
assert_contains "$log" "[systemctl] daemon-reload" "systemd reads the new unit file"
assert_not_contains "$log" "enable homebridge.service" "enable is not run again"
assert_not_contains "$log" "unmask" "a mask is never removed"
assert_missing "$(STATE)/was-running" "the note is removed"
assert_not_contains "$OUT" "Homebridge Installation Complete!" "no welcome text on an upgrade"

section "upgrade, the admin had stopped or disabled the service: it stays off"
sandbox_new upgrade-stopped
systemd_is_running
unpacked
FAKE_ACTIVE=0 run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
log=$(stublog)
assert_not_contains "$log" "restart homebridge.service" "not started"
assert_not_contains "$log" "enable homebridge.service" "not enabled"
assert_not_contains "$log" "unmask" "not unmasked"
assert_contains "$OUT" "was not running before the upgrade, so it is not started" "the output says so"

section "install again after a remove: like a first install"
sandbox_new reinstall
systemd_is_running
echo '{"dependencies":{"homebridge":"2.5.0"}}' > "$ROOT/var/lib/homebridge/package.json"
run_in "$ROOT/cwd" "$BASH" "$PRERM" remove
assert_exists "$(STATE)/removed" "prerm remove leaves a note"
unpacked
: > "$STUBLOG"
FAKE_ACTIVE=0 run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
log=$(stublog)
assert_contains "$log" "[systemctl] enable homebridge.service" "enable"
assert_contains "$log" "[systemctl] restart homebridge.service" "start"
assert_missing "$(STATE)/removed" "the note is removed"

section "no running systemd (a system image is being built): enable only"
sandbox_new chroot
unpacked
FAKE_ACTIVE=0 run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure
log=$(stublog)
assert_contains "$log" "[systemctl] enable homebridge.service" "enable (works without a running systemd)"
assert_not_contains "$log" "restart homebridge.service" "nothing is started"
assert_not_contains "$log" "daemon-reload" "no daemon-reload"

section "the service runs as another user (a systemd override): that user joins the homebridge group"
# a fake "id" that knows the user "pi" (uid 1000)
fake_script id << 'EOF'
#!/bin/sh
if [ "$1" = "-nu" ]; then
  case "$2" in pi | 1000) echo pi; exit 0 ;; homebridge) echo homebridge; exit 0 ;; *) exit 1 ;; esac
fi
PATH="$REAL_PATH" exec id "$@"
EOF
sandbox_new other-user
systemd_is_running
unpacked
FAKE_ACTIVE=0 FAKE_SERVICE_USER=1000 run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_contains "$(stublog)" "[usermod] -a -G homebridge pi" "the user is added to the group (so the polkit rule for mDNS applies to it)"

section "the service runs as homebridge: no group change"
sandbox_new default-user
systemd_is_running
unpacked
FAKE_ACTIVE=0 run_in "$ROOT/cwd" "$BASH" "$POSTINST" configure 2.0.25
assert_not_contains "$(stublog)" "[usermod] -a -G homebridge" "usermod is not called"
rm -f "$FAKEBIN/id"

finish
