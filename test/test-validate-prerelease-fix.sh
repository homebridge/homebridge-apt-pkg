#!/bin/bash

# Test script to validate the validate_prerelease job condition fix
# This script validates that the validate_prerelease job has the correct if condition

set -e

echo "🧪 Testing validate_prerelease job condition fix..."
echo

# Test 1: Validate YAML syntax of main workflow
echo "Test 1: Validating YAML syntax of main workflow..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax error"
    exit 1
fi

# Test 2: Check that validate_prerelease job has an explicit if condition
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

# Test 3: Verify consistency with other validation jobs
echo
echo "Test 3: Checking consistency with validate_apt job..."
VALIDATE_APT_CONDITION=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml')); print(w['jobs']['validate_apt'].get('if', 'MISSING'))")

echo "validate_apt condition: $VALIDATE_APT_CONDITION"

if [[ "$VALIDATE_APT_CONDITION" == "needs.publish_apt.result == 'success'" ]]; then
    echo "✅ Both validation jobs follow the same pattern"
else
    echo "❌ Validation jobs have inconsistent patterns"
    exit 1
fi

# Test 4: Check dependencies are correct
echo
echo "Test 4: Checking job dependencies..."
VALIDATE_PRERELEASE_NEEDS=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml')); print(w['jobs']['validate_prerelease']['needs'])")

echo "validate_prerelease needs: $VALIDATE_PRERELEASE_NEEDS"

if [[ "$VALIDATE_PRERELEASE_NEEDS" == "['create_prerelease']" ]]; then
    echo "✅ validate_prerelease job has correct dependencies"
else
    echo "❌ validate_prerelease job dependencies are incorrect"
    exit 1
fi

echo
echo "🎉 All tests passed! The validate_prerelease job should now run correctly."
echo
echo "Summary of the fix:"
echo "  - Added explicit if condition to validate_prerelease job"
echo "  - Condition: needs.create_prerelease.result == 'success'"
echo "  - This ensures the job runs when create_prerelease completes successfully"
echo "  - Pattern matches other validation jobs in the workflow"
echo "  - Should resolve the job skipping issue reported in #215"