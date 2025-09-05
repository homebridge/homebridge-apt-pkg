#!/bin/bash
# Test script to verify Raspberry Pi 1 B (32-bit ARM) compatibility
# This validates that the build process will work correctly for 32-bit ARM devices

set -e

echo "🍓 Testing Raspberry Pi 1 B (32-bit ARM) Compatibility"
echo "====================================================="
echo

# Test 1: Verify 32-bit ARM package configurations are valid
echo "Test 1: Validating 32-bit ARM package configurations..."
for release in alpha beta stable; do
    config_file="$release/32bit/package.json"
    if [[ -f "$config_file" ]]; then
        node_version=$(jq -r '.dependencies.node' "$config_file")
        major_version=$(echo "$node_version" | sed 's/^\^//' | cut -d. -f1)
        
        if [[ "$major_version" -le 22 ]]; then
            echo "  ✅ $config_file: Node.js $node_version (compatible with 32-bit ARM)"
        else
            echo "  ❌ $config_file: Node.js $node_version (incompatible with 32-bit ARM)"
            exit 1
        fi
    else
        echo "  ⚠️  $config_file: Not found"
    fi
done
echo

# Test 2: Simulate 32-bit ARM build validation
echo "Test 2: Simulating 32-bit ARM build validation..."
for release in alpha beta stable; do
    echo "  Testing $release build for 32-bit ARM:"
    
    # Simulate the build script validation
    export PKG_RELEASE_TYPE="$release"
    export QEMU_ARCH="arm"
    
    # Get the package.json path that would be used
    case "$release" in
        alpha) PACKAGE_JSON_PATH="alpha/32bit/package.json" ;;
        beta) PACKAGE_JSON_PATH="beta/32bit/package.json" ;;
        *) PACKAGE_JSON_PATH="stable/32bit/package.json" ;;
    esac
    
    if [[ -f "$PACKAGE_JSON_PATH" ]]; then
        NODE_VERSION=$(jq -r '.dependencies.node | ltrimstr("^") | "v" + .' "$PACKAGE_JSON_PATH")
        MAJOR_NODE=$(jq -r '.dependencies.node | gsub("^\\^"; "")' "$PACKAGE_JSON_PATH" | cut -d. -f1)
        
        echo "    Package config: $PACKAGE_JSON_PATH"
        echo "    Node.js version: $NODE_VERSION"
        echo "    Major version: $MAJOR_NODE"
        
        if [[ "$MAJOR_NODE" -gt 22 ]]; then
            echo "    ❌ Would fail: Node.js $MAJOR_NODE not supported on 32-bit ARM"
            exit 1
        else
            echo "    ✅ Would succeed: Node.js $MAJOR_NODE supported on 32-bit ARM"
        fi
    else
        echo "    ⚠️  Package config not found: $PACKAGE_JSON_PATH"
    fi
    echo
done

# Test 3: Verify workflow permission fix
echo "Test 3: Verifying workflow permission fix..."
if grep -q "actions: write" .github/workflows/release-stage-1_update_dependencies.yml; then
    echo "  ✅ Stage 1 workflow has 'actions: write' permission"
else
    echo "  ❌ Stage 1 workflow missing 'actions: write' permission"
    exit 1
fi
echo

# Test 4: Validate build script error handling
echo "Test 4: Validating build script error handling for 32-bit ARM..."
echo "  Testing build script syntax validation..."
if bash -n build.sh; then
    echo "  ✅ build.sh syntax is valid"
else
    echo "  ❌ build.sh has syntax errors"
    exit 1
fi

# Check that the build script has the 32-bit ARM validation
if grep -q "Node.js.*not supported on 32-bit ARM" build.sh; then
    echo "  ✅ build.sh has 32-bit ARM Node.js validation"
else
    echo "  ❌ build.sh missing 32-bit ARM Node.js validation"
    exit 1
fi
echo

echo "🎉 All Raspberry Pi 1 B compatibility tests passed!"
echo
echo "Summary:"
echo "  ✅ 32-bit ARM package configurations use Node.js ≤22"
echo "  ✅ Build validation would work correctly for ARM32"
echo "  ✅ Workflow permissions fixed to prevent blocking"
echo "  ✅ Build script has proper error handling for ARM32"
echo
echo "💡 Raspberry Pi 1 B users should be able to install and update"
echo "   Homebridge packages without issues once this fix is deployed."