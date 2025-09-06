#!/bin/bash

# Test script to validate the workflow condition fix
# This script validates that the reusable workflow conditions are correct

set -e

echo "🧪 Testing workflow condition fix..."
echo

# Test 1: Validate YAML syntax of reusable workflow
echo "Test 1: Validating YAML syntax of reusable workflow..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/reusable-validate-homebridge.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax error"
    exit 1
fi

# Test 2: Check condition syntax is correct
echo
echo "Test 2: Checking condition syntax..."
PRERELEASE_CONDITION=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/reusable-validate-homebridge.yml')); print(w['jobs']['validate_github_release'].get('if', ''))")
APT_CONDITION=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/reusable-validate-homebridge.yml')); print(w['jobs']['validate_apt_installation'].get('if', ''))")

echo "Prerelease condition: $PRERELEASE_CONDITION"
echo "APT condition: $APT_CONDITION"

if [[ "$PRERELEASE_CONDITION" == "inputs.validation_type == 'prerelease'" ]]; then
    echo "✅ Prerelease condition syntax is correct"
else
    echo "❌ Prerelease condition syntax is incorrect"
    exit 1
fi

if [[ "$APT_CONDITION" == "inputs.validation_type == 'apt'" ]]; then
    echo "✅ APT condition syntax is correct"
else
    echo "❌ APT condition syntax is incorrect"
    exit 1
fi

# Test 3: Validate parameter matching
echo
echo "Test 3: Validating parameter matching with calling workflow..."
VALIDATION_TYPE=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml')); print(w['jobs']['validate_prerelease']['with']['validation_type'])")

echo "Calling workflow passes validation_type: $VALIDATION_TYPE"

if [[ "$VALIDATION_TYPE" == "prerelease" ]]; then
    echo "✅ Parameter matching is correct"
else
    echo "❌ Parameter matching is incorrect"
    exit 1
fi

echo
echo "🎉 All tests passed! The workflow condition fix should resolve the issue."
echo
echo "Summary of the fix:"
echo "  - Fixed condition syntax from \${{ inputs.validation_type == 'prerelease' }} to inputs.validation_type == 'prerelease'"
echo "  - Fixed condition syntax from \${{ inputs.validation_type == 'apt' }} to inputs.validation_type == 'apt'"
echo "  - This should allow the validate_prerelease job to run instead of being skipped"
echo "  - All subsequent jobs should then run as expected"