#!/bin/bash

# Test script to validate the reusable workflow restructuring fix
# This script validates that the workflow now uses conditional steps instead of conditional jobs

set -e

echo "🧪 Testing reusable workflow restructuring fix..."
echo

# Test 1: Validate YAML syntax of reusable workflow
echo "Test 1: Validating YAML syntax of reusable workflow..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/reusable-validate-homebridge.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax error"
    exit 1
fi

# Test 2: Check that jobs always run (no conditions on job level)
echo
echo "Test 2: Checking job-level conditions..."
MAIN_JOB_CONDITION=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/reusable-validate-homebridge.yml')); print(w['jobs']['validate_homebridge'].get('if', 'NO_CONDITION'))" 2>/dev/null || echo "NO_CONDITION")
ARM_JOB_CONDITION=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/reusable-validate-homebridge.yml')); print(w['jobs']['validate_apt_on_arm'].get('if', 'NO_CONDITION'))" 2>/dev/null || echo "NO_CONDITION")

echo "Main job condition: $MAIN_JOB_CONDITION"
echo "ARM job condition: $ARM_JOB_CONDITION"

if [[ "$MAIN_JOB_CONDITION" == "NO_CONDITION" ]]; then
    echo "✅ Main job has no condition - will always run"
else
    echo "❌ Main job has unexpected condition"
    exit 1
fi

if [[ "$ARM_JOB_CONDITION" == "inputs.validation_type == 'apt'" ]]; then
    echo "✅ ARM job has correct condition for APT validation only"
else
    echo "❌ ARM job condition is incorrect"
    exit 1
fi

# Test 3: Check that steps have appropriate conditions
echo
echo "Test 3: Checking step-level conditions..."

# Count steps with prerelease conditions
PRERELEASE_STEPS=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/reusable-validate-homebridge.yml'))
steps = w['jobs']['validate_homebridge']['steps']
count = sum(1 for step in steps if step.get('if', '') == \"inputs.validation_type == 'prerelease'\")
print(count)
")

# Count steps with APT conditions
APT_STEPS=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/reusable-validate-homebridge.yml'))
steps = w['jobs']['validate_homebridge']['steps']
count = sum(1 for step in steps if step.get('if', '') == \"inputs.validation_type == 'apt'\")
print(count)
")

echo "Steps with prerelease conditions: $PRERELEASE_STEPS"
echo "Steps with APT conditions: $APT_STEPS"

if [[ "$PRERELEASE_STEPS" -gt 0 && "$APT_STEPS" -gt 0 ]]; then
    echo "✅ Both validation types have conditional steps"
else
    echo "❌ Missing conditional steps for one or both validation types"
    exit 1
fi

# Test 4: Validate parameter matching with calling workflow
echo
echo "Test 4: Validating parameter matching with calling workflow..."
VALIDATION_TYPE=$(python3 -c "import yaml; w=yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml')); print(w['jobs']['validate_prerelease']['with']['validation_type'])")

echo "Calling workflow passes validation_type: $VALIDATION_TYPE"

if [[ "$VALIDATION_TYPE" == "prerelease" ]]; then
    echo "✅ Parameter matching is correct"
else
    echo "❌ Parameter matching is incorrect"
    exit 1
fi

echo
echo "🎉 All tests passed! The reusable workflow restructuring should resolve the issue."
echo
echo "Summary of the fix:"
echo "  - Restructured reusable workflow from conditional jobs to conditional steps"
echo "  - Main job (validate_homebridge) always runs, ensuring workflow completion"
echo "  - Steps within the main job are conditional based on validation_type"
echo "  - ARM validation job only runs for APT validation type"
echo "  - This ensures the overall workflow call reports success when appropriate"
echo "  - Should resolve the job skipping issue where validation jobs were not running"