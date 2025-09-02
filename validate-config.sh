#!/bin/bash

# Configuration validation script for homebridge-apt-pkg
# This script validates that the package.json configurations are compatible
# with the target architectures, particularly ensuring Node.js version constraints

set -e

echo "🔍 Validating package configurations..."

# Check main package.json
if [[ -f "package.json" ]]; then
    NODE_VERSION=$(jq -r '.dependencies.node | gsub("^\\^"; "")' package.json | cut -d. -f1)
    echo "✅ Main package.json: Node.js $NODE_VERSION"
    
    if [[ "$NODE_VERSION" -gt 22 ]]; then
        echo "⚠️  WARNING: Main package.json uses Node.js >22, which may cause issues for 32-bit builds"
    fi
else
    echo "❌ Main package.json not found"
    exit 1
fi

# Check beta configurations
for config_dir in beta/32bit beta/64bit; do
    if [[ -f "$config_dir/package.json" ]]; then
        NODE_VERSION=$(jq -r '.dependencies.node | gsub("^\\^"; "")' "$config_dir/package.json" | cut -d. -f1)
        echo "✅ $config_dir/package.json: Node.js $NODE_VERSION"
        
        if [[ "$config_dir" == "beta/32bit" && "$NODE_VERSION" -gt 22 ]]; then
            echo "❌ ERROR: $config_dir uses Node.js $NODE_VERSION which is not supported on 32-bit architectures"
            echo "   Node.js dropped 32-bit support starting with version 23"
            echo "   Please use Node.js 22.x or earlier for 32-bit configurations"
            exit 1
        fi
    else
        echo "❌ $config_dir/package.json not found"
        exit 1
    fi
done

echo "🎉 All package configurations are valid!"

# Provide architecture-specific build guidance
echo ""
echo "📋 Build Architecture Guide:"
echo "  • x86_64 (64-bit Intel/AMD): Can use any Node.js version"
echo "  • aarch64 (64-bit ARM): Can use any Node.js version"  
echo "  • arm (32-bit ARM): Must use Node.js ≤22"
echo "  • i386 (32-bit Intel): Must use Node.js ≤22"
echo ""
echo "💡 Current configurations:"
echo "  • Stable builds: Use main package.json for all architectures"
echo "  • Beta builds: Use beta/64bit for x86_64/aarch64, beta/32bit for arm/i386"