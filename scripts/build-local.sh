#!/bin/bash

# Unified local build script for all release streams (stable, beta, alpha)
# This script reuses the existing build components and Dockerfile to create test builds

set -e

# Ensure we're running from the repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to repo root if we're not already there
if [[ "$(pwd)" != "$REPO_ROOT" ]]; then
    echo "📂 Changing to repository root: $REPO_ROOT"
    cd "$REPO_ROOT"
fi

# Show usage function
show_usage() {
    echo "🏗️  Homebridge APT Package Local Build Script"
    echo
    echo "Usage: $0 <release_type> [architecture] [version]"
    echo
    echo "Release Types:"
    echo "  stable  - Build stable release (uses package.json)"
    echo "  beta    - Build beta release (uses beta/*/package.json)"
    echo "  alpha   - Build alpha release (uses alpha/*/package.json)"
    echo
    echo "Architectures:"
    echo "  x86_64   - Intel/AMD 64-bit (default on Intel Macs and non-macOS)"
    echo "  aarch64  - ARM 64-bit (default on Apple Silicon Macs, alias: arm64)"
    echo "  arm      - ARM 32-bit (alias: armhf)"
    echo
    echo "Examples:"
    echo "  $0 stable"
    echo "  $0 beta aarch64"
    echo "  $0 alpha x86_64 1.0.0~alpha.1"
    echo "  $0 stable arm my-stable-build"
    echo
    echo "Individual scripts are also available:"
    echo "  ./scripts/build-stable.sh [arch] [version]"
    echo "  ./scripts/build-beta.sh [arch] [version]"
    echo "  ./scripts/build-alpha.sh [arch] [version]"
}

# Parse arguments
RELEASE_TYPE="${1}"

# Default architecture: aarch64 on Apple Silicon Macs, x86_64 otherwise
DEFAULT_ARCH="x86_64"
if [[ "$OSTYPE" == "darwin"* && "$(uname -m)" == "arm64" ]]; then
    DEFAULT_ARCH="aarch64"
fi

ARCH="${2:-$DEFAULT_ARCH}"
VERSION="${3}"

# Validate release type
if [[ -z "$RELEASE_TYPE" ]]; then
    echo "❌ Error: Release type is required"
    echo
    show_usage
    exit 1
fi

case "$RELEASE_TYPE" in
  stable|beta|alpha)
    # Valid release type
    ;;
  help|--help|-h)
    show_usage
    exit 0
    ;;
  *)
    echo "❌ Error: Invalid release type '$RELEASE_TYPE'"
    echo
    show_usage
    exit 1
    ;;
esac

# Set default version based on release type if not provided
if [[ -z "$VERSION" ]]; then
    case "$RELEASE_TYPE" in
        stable)
            VERSION="1.0.0~test"
            ;;
        beta)
            VERSION="1.0.0~beta.test"
            ;;
        alpha)
            VERSION="1.0.0~alpha.test"
            ;;
    esac
fi

# Normalize architecture names
case "$ARCH" in
  arm64)
    ARCH="aarch64"
    ;;
  armhf)
    ARCH="arm"
    ;;
esac

BUILD_NAME="homebridge-$RELEASE_TYPE-build"

echo "🏗️  Building $RELEASE_TYPE release package..."
echo "📦 Architecture: $ARCH"
echo "🏷️  Version: $VERSION"
echo "🔧 Release Type: $RELEASE_TYPE"
echo

# Validate architecture and set Docker parameters
case "$ARCH" in
  x86_64)
    BASE_IMAGE="library/debian:bullseye"
    QEMU_ARCH="x86_64"
    ;;
  aarch64)
    BASE_IMAGE="arm64v8/debian:bullseye"
    QEMU_ARCH="aarch64"
    ;;
  arm)
    BASE_IMAGE="balenalib/raspberrypi3-debian:bullseye"
    QEMU_ARCH="arm"
    ;;
  *)
    echo "❌ Unsupported architecture: $ARCH"
    echo "   Supported: x86_64, aarch64, arm"
    exit 1
    ;;
esac

# Check if package.json exists for the release type
case "$RELEASE_TYPE" in
  stable)
    if [[ ! -f "package.json" ]]; then
        echo "❌ Error: package.json not found for stable release"
        exit 1
    fi
    echo "📋 Using: package.json"
    ;;
  beta)
    case "$ARCH" in
      x86_64|aarch64)
        PACKAGE_JSON_PATH="beta/64bit/package.json"
        ;;
      arm)
        PACKAGE_JSON_PATH="beta/32bit/package.json"
        ;;
    esac
    if [[ ! -f "$PACKAGE_JSON_PATH" ]]; then
        echo "❌ Error: $PACKAGE_JSON_PATH not found for beta release"
        exit 1
    fi
    echo "📋 Using: $PACKAGE_JSON_PATH"
    ;;
  alpha)
    case "$ARCH" in
      x86_64|aarch64)
        PACKAGE_JSON_PATH="alpha/64bit/package.json"
        ;;
      arm)
        PACKAGE_JSON_PATH="alpha/32bit/package.json"
        ;;
    esac
    if [[ ! -f "$PACKAGE_JSON_PATH" ]]; then
        echo "❌ Error: $PACKAGE_JSON_PATH not found for alpha release"
        exit 1
    fi
    echo "📋 Using: $PACKAGE_JSON_PATH"
    ;;
esac

echo
echo "🔧 Building Docker image for $ARCH..."

# Detect macOS and add platform flag to avoid Rosetta/QEMU conflicts
DOCKER_PLATFORM=""
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "🍎 macOS detected - using platform-specific build to avoid Rosetta conflicts..."
  case "$QEMU_ARCH" in
    x86_64) DOCKER_PLATFORM="--platform linux/amd64" ;;
    aarch64) DOCKER_PLATFORM="--platform linux/arm64" ;;
    arm) DOCKER_PLATFORM="--platform linux/arm/v7" ;;
  esac
fi

docker build -f build/Dockerfile \
  $DOCKER_PLATFORM \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg QEMU_ARCH="$QEMU_ARCH" \
  -t "$BUILD_NAME" \
  .

echo
echo "📦 Building $RELEASE_TYPE package..."
docker run --rm \
  -v "$(pwd):/repo" \
  -e PKG_RELEASE_TYPE="$RELEASE_TYPE" \
  -e PKG_RELEASE_VERSION="$VERSION" \
  -e QEMU_ARCH="$QEMU_ARCH" \
  "$BUILD_NAME"

echo
echo "✅ $RELEASE_TYPE build completed!"
echo "📂 Package files:"
ls -la homebridge_*.deb homebridge_*.manifest 2>/dev/null || echo "   No package files found - check build output above"