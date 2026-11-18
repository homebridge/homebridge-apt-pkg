#!/usr/bin/env bash
#
# Tests for the pre-start script deb/etc/hb-service/homebridge/prestart.d/10-fix-permissions.
# It runs as root before every start, and decides who owns what.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fake chown chmod
fake_script id << 'EOF'
#!/bin/sh
if [ "$1" = "-gn" ]; then echo svcgroup; exit 0; fi
PATH="$REAL_PATH" exec id "$@"
EOF
FIX=$(sandbox_script deb/etc/hb-service/homebridge/prestart.d/10-fix-permissions)

section "the service user gets the storage folder and the Node.js runtime, not the scripts"
sandbox_new owner
mkdir -p "$ROOT/opt/homebridge/lib" "$ROOT/opt/homebridge/include" "$ROOT/opt/homebridge/share"
touch "$ROOT/opt/homebridge/CHANGELOG.md" "$ROOT/opt/homebridge/LICENSE" "$ROOT/opt/homebridge/README.md" \
  "$ROOT/opt/homebridge/source-vm.sh" "$ROOT/opt/homebridge/.hidden"
USER=svc run_in "$ROOT/cwd" sh "$FIX"
log=$(stublog)
assert_contains "$log" "[chown] -R svc: /var/lib/homebridge" "storage folder: service user"
for entry in bin lib include share CHANGELOG.md LICENSE README.md; do
  assert_contains "$log" "[chown] -R svc: /opt/homebridge/$entry" "$entry: service user"
done
for entry in hb-service-shim hb-shell source.sh start.sh bashrc bashrc-hb-shell rebuild-package-json.sh package.json source-vm.sh .hidden; do
  assert_contains "$log" "[chown] -h root:root /opt/homebridge/$entry" "$entry: root"
done
assert_contains "$log" "[chown] root:svcgroup /opt/homebridge" "the folder itself: root, with the service user's group"
assert_contains "$log" "[chmod] 1775 /opt/homebridge" "the folder is sticky: the service user can add files, not replace root's"
assert_not_contains "$log" "svc: /opt/homebridge/hb-service-shim" "the hb-service script is never given to the service user"
assert_not_contains "$log" "/var/lib/homebridge /opt/homebridge" "the whole of /opt/homebridge is never handed over"

section "when the service runs as root, nothing is changed"
sandbox_new root
USER=root run_in "$ROOT/cwd" sh "$FIX"
assert_eq "" "$(stublog)" "no chown and no chmod"

finish
