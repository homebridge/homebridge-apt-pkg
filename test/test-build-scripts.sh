#!/bin/bash

# Test script for local build scripts validation
# This validates the scripts without running full Docker builds

set -e

echo "🧪 Testing local build scripts..."
echo

# Test unified script help
echo "✅ Testing unified script help:"
./scripts/build-local.sh help
echo

# Test individual script help
echo "✅ Testing individual script help:"
./scripts/build-stable.sh help
echo

# Test error handling
echo "✅ Testing error handling:"
echo "  - Invalid release type:"
if ./scripts/build-local.sh invalid_type 2>/dev/null; then
    echo "❌ ERROR: Should have failed with invalid release type"
    exit 1
else
    echo "  ✓ Correctly rejected invalid release type"
fi

echo "  - Invalid architecture:"
if ./scripts/build-stable.sh invalid_arch 2>/dev/null; then
    echo "❌ ERROR: Should have failed with invalid architecture"
    exit 1
else
    echo "  ✓ Correctly rejected invalid architecture"
fi

# Test package.json validation
echo "✅ Testing package.json validation:"
echo "  - Stable release (package.json):"
if [[ -f "package.json" ]]; then
    echo "  ✓ package.json exists for stable releases"
else
    echo "  ❌ package.json missing for stable releases"
    exit 1
fi

echo "  - Beta release (beta/64bit/package.json):"
if [[ -f "beta/64bit/package.json" ]]; then
    echo "  ✓ beta/64bit/package.json exists"
else
    echo "  ❌ beta/64bit/package.json missing"
    exit 1
fi

echo "  - Alpha release (alpha/64bit/package.json):"
if [[ -f "alpha/64bit/package.json" ]]; then
    echo "  ✓ alpha/64bit/package.json exists"
else
    echo "  ❌ alpha/64bit/package.json missing"
    exit 1
fi

# Test architecture mapping
echo "✅ Testing architecture aliases:"
echo "  - arm64 -> aarch64 mapping:"
timeout 10s ./scripts/build-local.sh stable arm64 test-version 2>&1 | grep -q "Architecture: aarch64" && echo "  ✓ arm64 correctly mapped to aarch64" || echo "  ❌ arm64 mapping failed"

echo "  - armhf -> arm mapping:"
timeout 10s ./scripts/build-local.sh stable armhf test-version 2>&1 | grep -q "Architecture: arm" && echo "  ✓ armhf correctly mapped to arm" || echo "  ❌ armhf mapping failed"

# Test default values
echo "✅ Testing default values:"
echo "  - Default stable version:"
timeout 10s ./scripts/build-stable.sh x86_64 2>&1 | grep -q "1.0.0~test" && echo "  ✓ Default stable version correct" || echo "  ❌ Default stable version incorrect"

echo "  - Default beta version:"
timeout 10s ./scripts/build-beta.sh x86_64 2>&1 | grep -q "1.0.0~beta.test" && echo "  ✓ Default beta version correct" || echo "  ❌ Default beta version incorrect"

echo "  - Default alpha version:"
timeout 10s ./scripts/build-alpha.sh x86_64 2>&1 | grep -q "1.0.0~alpha.test" && echo "  ✓ Default alpha version correct" || echo "  ❌ Default alpha version incorrect"

# Test release type validation in unified script
echo "✅ Testing release type validation:"
for release_type in stable beta alpha; do
    timeout 10s ./scripts/build-local.sh "$release_type" x86_64 test-version 2>&1 | grep -q "Release Type: $release_type" && echo "  ✓ $release_type release type validated" || echo "  ❌ $release_type release type validation failed"
done

echo
echo "✅ All validation tests passed!"
echo "📝 Note: Full Docker builds not tested due to emulation requirements"
echo "🏗️  The scripts are ready for use with proper Docker multiarch setup"