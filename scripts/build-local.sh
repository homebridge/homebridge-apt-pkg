#!/bin/bash
#
# Builds one Homebridge .deb package in Docker.
# The release workflow and the CI workflow use this same script, so a local build is made the
# same way as a released one.
#
# Usage: scripts/build-local.sh <release type> [architecture] [version]
# Run it with --help for the details.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

show_usage() {
  cat << 'EOF'
Usage: scripts/build-local.sh <release type> [architecture] [version]

Release types (each has its own <type>/32bit and <type>/64bit package.json):
  stable | beta | alpha | legacy

Architectures:
  x86_64   Intel/AMD 64-bit (alias: amd64)
  aarch64  ARM 64-bit (alias: arm64)
  arm      ARM 32-bit (alias: armhf). Needs a machine that can run 32-bit ARM programs.
  Default: the architecture of this machine.

Version:
  The package version. Default: 0.0.0~<release type>.local

Examples:
  scripts/build-local.sh stable
  scripts/build-local.sh beta aarch64
  scripts/build-local.sh legacy x86_64 2.0.27~legacy.20261118

The package (homebridge_<version>_<arch>.deb) and its manifest are written to the repo folder.
Needs Docker and a network connection. A build takes a few minutes.
EOF
}

RELEASE_TYPE="${1:-}"
case "$RELEASE_TYPE" in
  stable | beta | alpha | legacy) ;;
  help | --help | -h)
    show_usage
    exit 0
    ;;
  "")
    echo "Error: a release type is required." >&2
    echo >&2
    show_usage >&2
    exit 2
    ;;
  *)
    echo "Error: unknown release type '$RELEASE_TYPE'." >&2
    echo >&2
    show_usage >&2
    exit 2
    ;;
esac

case "$(uname -m)" in
  arm64 | aarch64) DEFAULT_ARCH=aarch64 ;;
  *) DEFAULT_ARCH=x86_64 ;;
esac
ARCH="${2:-$DEFAULT_ARCH}"
VERSION="${3:-0.0.0~$RELEASE_TYPE.local}"

# The one table of build images. Every architecture builds in the official Debian image.
#   BASE_IMAGE: the image the build container is made from
#   PLATFORM:   what Docker calls this architecture
#   QEMU_ARCH:  what build.sh calls it
case "$ARCH" in
  x86_64 | amd64)
    QEMU_ARCH=x86_64
    BASE_IMAGE=library/debian:bookworm
    PLATFORM=linux/amd64
    ARCH_DIR=64bit
    ;;
  aarch64 | arm64)
    QEMU_ARCH=aarch64
    BASE_IMAGE=arm64v8/debian:bookworm
    PLATFORM=linux/arm64
    ARCH_DIR=64bit
    ;;
  arm | armhf)
    QEMU_ARCH=arm
    BASE_IMAGE=arm32v7/debian:bookworm
    PLATFORM=linux/arm/v7
    ARCH_DIR=32bit
    ;;
  *)
    echo "Error: unknown architecture '$ARCH'. Use x86_64, aarch64 or arm." >&2
    exit 2
    ;;
esac

PACKAGE_JSON="$RELEASE_TYPE/$ARCH_DIR/package.json"
if [ ! -f "$PACKAGE_JSON" ]; then
  echo "Error: $PACKAGE_JSON not found." >&2
  exit 1
fi

IMAGE="homebridge-$RELEASE_TYPE-$QEMU_ARCH-build"
echo "Release type: $RELEASE_TYPE"
echo "Architecture: $QEMU_ARCH ($PLATFORM, image $BASE_IMAGE)"
echo "Version:      $VERSION"
echo "Versions in:  $PACKAGE_JSON"
echo

# --dry-run as a 4th argument: only show what would be built (used by the tests)
if [ "${4:-}" = "--dry-run" ]; then
  exit 0
fi

docker build -f build/Dockerfile \
  --platform "$PLATFORM" \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg QEMU_ARCH="$QEMU_ARCH" \
  -t "$IMAGE" \
  .

docker run --rm \
  --platform "$PLATFORM" \
  -v "$(pwd):/repo" \
  -e PKG_RELEASE_TYPE="$RELEASE_TYPE" \
  -e PKG_RELEASE_VERSION="$VERSION" \
  -e QEMU_ARCH="$QEMU_ARCH" \
  "$IMAGE"

echo
echo "Build finished:"
ls -l homebridge_*.deb homebridge_*.manifest
