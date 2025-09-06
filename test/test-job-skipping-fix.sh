#!/bin/bash

# Test script to validate the job skipping fix
# This script validates that the validate_prerelease and validate_apt jobs have the correct if conditions

set -e

echo "🧪 Testing job skipping fix..."
echo

# Test 1: Validate YAML syntax
echo "Test 1: Validating YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax error"
    exit 1
fi

# Test 2: Check validate_prerelease job has correct if condition
echo
echo "Test 2: Checking validate_prerelease job condition..."
VALIDATE_PRERELEASE_CONDITION=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml')); print(w['jobs']['validate_prerelease'].get('if', 'MISSING'))")

echo "validate_prerelease condition: $VALIDATE_PRERELEASE_CONDITION"

if [[ "$VALIDATE_PRERELEASE_CONDITION" == "needs.create_prerelease.result == 'success'" ]]; then
    echo "✅ validate_prerelease job has correct if condition"
else
    echo "❌ validate_prerelease job condition is incorrect or missing"
    echo "   Expected: needs.create_prerelease.result == 'success'"
    echo "   Found: $VALIDATE_PRERELEASE_CONDITION"
    exit 1
fi

# Test 3: Check validate_apt job has correct if condition  
echo
echo "Test 3: Checking validate_apt job condition..."
VALIDATE_APT_CONDITION=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml')); print(w['jobs']['validate_apt'].get('if', 'MISSING'))")

echo "validate_apt condition: $VALIDATE_APT_CONDITION"

if [[ "$VALIDATE_APT_CONDITION" == "needs.publish_apt.result == 'success'" ]]; then
    echo "✅ validate_apt job has correct if condition"
else
    echo "❌ validate_apt job condition is incorrect or missing"
    echo "   Expected: needs.publish_apt.result == 'success'"  
    echo "   Found: $VALIDATE_APT_CONDITION"
    exit 1
fi

# Test 4: Check job dependencies are correct
echo
echo "Test 4: Checking job dependencies..."
VALIDATE_PRERELEASE_NEEDS=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml')); print(w['jobs']['validate_prerelease']['needs'])")
VALIDATE_APT_NEEDS=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml')); print(w['jobs']['validate_apt']['needs'])")

echo "validate_prerelease needs: $VALIDATE_PRERELEASE_NEEDS"
echo "validate_apt needs: $VALIDATE_APT_NEEDS"

if [[ "$VALIDATE_PRERELEASE_NEEDS" == "['create_prerelease']" ]]; then
    echo "✅ validate_prerelease job has correct dependencies"
else
    echo "❌ validate_prerelease job dependencies are incorrect"
    exit 1
fi

if [[ "$VALIDATE_APT_NEEDS" == "['publish_apt', 'determine-release-type']" ]]; then
    echo "✅ validate_apt job has correct dependencies"
else
    echo "❌ validate_apt job dependencies are incorrect"
    exit 1
fi

echo
echo "🎉 All tests passed! The job skipping fix should resolve the issue."
echo
echo "Summary of the fix:"
echo "  - Added explicit if condition to validate_prerelease job"
echo "  - Condition: needs.create_prerelease.result == 'success'"
echo "  - Added explicit if condition to validate_apt job"
echo "  - Condition: needs.publish_apt.result == 'success'"
echo "  - This ensures jobs run when their dependencies complete successfully"
echo "  - Should resolve the job skipping issue where subsequent jobs were not running"