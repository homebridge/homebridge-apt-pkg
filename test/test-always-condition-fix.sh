#!/bin/bash

# Test script to validate the "always() &&" condition fix for job skipping
# This validates that the fix follows the established pattern in the workflow

set -e

echo "🔍 Testing the 'always() &&' condition fix for job skipping..."

# Test 1: Validate that the conditions were added
echo "Test 1: Checking that always() conditions were added to validation jobs..."

if grep -q "if: always() && needs.create_prerelease.result == 'success'" .github/workflows/release-stage-2_build_and_release.yml; then
    echo "✅ Prerelease validation job has always() condition"
else
    echo "❌ Prerelease validation job missing always() condition"
    exit 1
fi

if grep -q "if: always() && needs.publish_apt.result == 'success'" .github/workflows/release-stage-2_build_and_release.yml; then
    echo "✅ APT validation job has always() condition"
else
    echo "❌ APT validation job missing always() condition"
    exit 1
fi

# Test 2: Validate that this follows the existing pattern
echo
echo "Test 2: Verifying consistency with existing always() pattern..."

ALWAYS_COUNT=$(grep -c "if: always()" .github/workflows/release-stage-2_build_and_release.yml)
echo "Found $ALWAYS_COUNT jobs using 'if: always()' pattern"

if [[ $ALWAYS_COUNT -ge 4 ]]; then
    echo "✅ Pattern is consistent with other jobs in the workflow"
else
    echo "❌ Pattern inconsistency detected"
    exit 1
fi

# Test 3: Validate YAML syntax
echo
echo "Test 3: Validating YAML syntax..."

if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax is invalid"
    exit 1
fi

# Test 4: Check that dependency chains are intact
echo
echo "Test 4: Verifying job dependency chains..."

# validate_prerelease should depend on create_prerelease
if grep -A2 "validate_prerelease:" .github/workflows/release-stage-2_build_and_release.yml | grep -q "needs: \[create_prerelease\]"; then
    echo "✅ validate_prerelease job dependencies are correct"
else
    echo "❌ validate_prerelease job dependencies are incorrect"
    exit 1
fi

# validate_apt should depend on publish_apt and determine-release-type
if grep -A2 "validate_apt:" .github/workflows/release-stage-2_build_and_release.yml | grep -q "needs: \[publish_apt, determine-release-type\]"; then
    echo "✅ validate_apt job dependencies are correct"
else
    echo "❌ validate_apt job dependencies are incorrect"
    exit 1
fi

echo
echo "🎉 All tests passed! The always() condition fix should resolve the job skipping issue."
echo
echo "Summary of the fix:"
echo "  - Added 'if: always() && needs.create_prerelease.result == \"success\"' to validate_prerelease job"
echo "  - Added 'if: always() && needs.publish_apt.result == \"success\"' to validate_apt job"
echo "  - This follows the same pattern used by build_packages and create_prerelease jobs"
echo "  - The always() function ensures jobs run even when dependencies complete, then success is checked"
echo "  - This should prevent GitHub Actions from skipping the validation jobs"