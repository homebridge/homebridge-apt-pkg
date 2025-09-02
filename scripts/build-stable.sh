#!/bin/bash

# Local build script for stable release stream
# This script reuses the existing build components and Dockerfile to create test builds

set -e

# Default values
ARCH="${1:-x86_64}"
VERSION="${2:-test-stable-1.0.0}"
BUILD_NAME="homebridge-stable-build"

echo "🏗️  Building stable release package..."
echo "📦 Architecture: $ARCH"
echo "🏷️  Version: $VERSION"
echo

# Show usage for help requests
if [[ "$ARCH" == "help" || "$ARCH" == "--help" || "$ARCH" == "-h" ]]; then
    echo "📖 Stable Release Build Script"
    echo
    echo "Usage: $0 [architecture] [version]"
    echo
    echo "Arguments:"
    echo "  architecture  - Target architecture (default: x86_64)"
    echo "  version      - Package version (default: test-stable-1.0.0)"
    echo
    echo "Supported architectures: x86_64, aarch64, arm64, arm, armhf"
    echo
    echo "Examples:"
    echo "  $0                     # Build for x86_64 with default version"
    echo "  $0 aarch64             # Build for ARM64"
    echo "  $0 x86_64 my-test-1.0 # Build with custom version"
    echo
    echo "💡 For unified script with all release types: ./scripts/build-local.sh help"
    exit 0
fi

# Validate architecture
case "$ARCH" in
  x86_64)
    BASE_IMAGE="library/debian:bullseye"
    QEMU_ARCH="x86_64"
    ;;
  aarch64|arm64)
    BASE_IMAGE="arm64v8/debian:bullseye"
    QEMU_ARCH="aarch64"
    ;;
  arm|armhf)
    BASE_IMAGE="balenalib/raspberrypi3-debian:bullseye"
    QEMU_ARCH="arm"
    ;;
  *)
    echo "❌ Unsupported architecture: $ARCH"
    echo "   Supported: x86_64, aarch64, arm64, arm, armhf"
    echo "   Use '$0 help' for more information"
    exit 1
    ;;
esac

echo "🔧 Building Docker image for $ARCH..."
docker build -f build/Dockerfile \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg QEMU_ARCH="$QEMU_ARCH" \
  -t "$BUILD_NAME" \
  .

echo "📦 Building stable package..."
docker run --rm \
  -v "$(pwd):/repo" \
  -e PKG_RELEASE_TYPE="stable" \
  -e PKG_RELEASE_VERSION="$VERSION" \
  -e QEMU_ARCH="$QEMU_ARCH" \
  "$BUILD_NAME"

echo
echo "✅ Stable build completed!"
echo "📂 Package files:"
ls -la homebridge_*.deb homebridge_*.manifest 2>/dev/null || echo "   No package files found - check build output above"
echo
echo "💡 Usage examples:"
echo "   # Build for x86_64 (default):"
echo "   ./scripts/build-stable.sh"
echo "   # Build for ARM64:"
echo "   ./scripts/build-stable.sh aarch64"
echo "   # Build with custom version:"
echo "   ./scripts/build-stable.sh x86_64 my-test-1.2.3"