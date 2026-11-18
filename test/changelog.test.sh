#!/usr/bin/env bash
#
# Tests for scripts/write-changelog.sh (the "What's Changed" part of the release notes).
# It runs in a small throw-away git repo with known tags and commits.

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

G="$WORK/changelog-repo"
mkdir -p "$G/scripts/lib" "$G/deb"
cp "$REPO/scripts/write-changelog.sh" "$G/scripts/"
cp "$REPO/scripts/lib/versions.sh" "$G/scripts/lib/"
git -C "$G" init -q
git -C "$G" config user.email test@example.com
git -C "$G" config user.name test

# stream_file <stream> <homebridge> <node 64-bit>
stream_file() {
  mkdir -p "$G/$1/64bit" "$G/$1/32bit"
  printf '{"dependencies":{"homebridge":"%s","homebridge-config-ui-x":"5.30.1","node":"%s"}}\n' "$2" "$3" > "$G/$1/64bit/package.json"
  printf '{"dependencies":{"homebridge":"%s","homebridge-config-ui-x":"5.30.1","node":"22.23.5"}}\n' "$2" > "$G/$1/32bit/package.json"
}
commit() {
  git -C "$G" add -A
  git -C "$G" commit -q -m "$1"
}
# notes <stream> <arch>: the text the script writes
notes() {
  rm -f "$WORK/manifest"
  (cd "$G" && "$BASH" scripts/write-changelog.sh "$1" "$2" "$WORK/manifest") > "$WORK/changelog.out" 2>&1
  STATUS=$?
  OUT=$(cat "$WORK/manifest" 2> /dev/null)
}

# history: a stable release, then legacy and beta releases, then more commits
stream_file stable 2.4.0 26.13.0
stream_file legacy 1.11.4 24.22.2
stream_file beta 2.5.0-beta.1 26.13.0
commit "first"
git -C "$G" tag v2.0.26
stream_file legacy 1.11.4 24.22.3
commit "LEGACY: Update legacy dependencies in legacy/64bit"
git -C "$G" tag v2.0.27-legacy.20261115
stream_file beta 2.5.1-beta.5 26.13.1
commit "BETA: Update beta dependencies in beta/32bit,beta/64bit"
git -C "$G" tag v2.0.27-beta.20261118
echo "fix" > "$G/deb/postinst"
commit "fix(postinst): a shared fix"
stream_file stable 2.5.0 26.13.1
commit "STABLE: Update stable dependencies in stable/32bit,stable/64bit"
stream_file beta 2.5.1-beta.6 26.13.1
commit "BETA: Update beta dependencies in beta/64bit"

section "a stable release is compared with the last stable release"
notes stable 64bit
assert_eq 0 "$STATUS" "exit code 0"
assert_contains "$OUT" "* **Homebridge**: Updated from 2.4.0 to 2.5.0" "Homebridge: from the last stable version (the base is v2.0.26, not a legacy or beta tag)"
assert_contains "$OUT" "* **Node.js**: Updated from 26.13.0 to 26.13.1" "Node.js: from the last stable version"
assert_contains "$OUT" "fix(postinst): a shared fix" "a commit to shared files is listed"
assert_contains "$OUT" "STABLE: Update stable dependencies" "the stream's own bot commit is listed"
assert_not_contains "$OUT" "BETA: Update beta" "bot commits of the beta stream are left out"
assert_not_contains "$OUT" "LEGACY: Update legacy" "bot commits of the legacy stream are left out"

section "a legacy release is compared with the last legacy release, and with the legacy files"
notes legacy 64bit
assert_not_contains "$OUT" "Homebridge**: Updated" "Homebridge did not change in legacy, so it is not listed (the old code said 'from 2.5.0 to 1.6.1')"
assert_not_contains "$OUT" "Package Manifest Changes" "no package change section"
assert_contains "$OUT" "fix(postinst): a shared fix" "the shared commit since the last legacy release is listed"
assert_not_contains "$OUT" "STABLE: Update stable" "bot commits of the stable stream are left out"

section "a beta release"
notes beta 64bit
assert_contains "$OUT" "* **Homebridge**: Updated from 2.5.1-beta.5 to 2.5.1-beta.6" "compared with the last beta release"
assert_contains "$OUT" "BETA: Update beta dependencies in beta/64bit" "the newest beta commit is listed"
assert_not_contains "$OUT" "beta/32bit,beta/64bit" "the beta commit that is already in the last beta release is not listed again"
notes beta 32bit
assert_not_contains "$OUT" "Node.js" "32-bit: Node.js stayed on 22, so it is not listed"

section "nothing changed since the last release of the stream"
git -C "$G" tag v2.0.27-beta.20261119
notes beta 64bit
assert_contains "$OUT" "* No new commits since last beta release" "it says so"

section "a stream with no release yet"
git -C "$G" tag -d v2.0.27-legacy.20261115 > /dev/null
notes legacy 64bit
assert_contains "$OUT" "### Recent Changes" "the newest commits are shown"

section "build.sh uses the script"
# shellcheck disable=SC2016 # the text is a line of build.sh
assert_contains "$(cat "$REPO/build.sh")" './scripts/write-changelog.sh "$PKG_RELEASE_TYPE" "$ARCH_DIR" "$MANIFEST"' "build.sh calls write-changelog.sh"

finish
