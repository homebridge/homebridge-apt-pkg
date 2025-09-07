#!/bin/bash

# Test script to validate the release tag output fix
# This script validates that the create_prerelease job correctly outputs the release_tag

set -e

echo "🧪 Testing release tag output fix..."
echo

# Test 1: Validate YAML syntax of main workflow
echo "Test 1: Validating YAML syntax of main workflow..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax error"
    exit 1
fi

# Test 2: Check that create_prerelease job has the correct output reference
echo
echo "Test 2: Checking create_prerelease job output configuration..."
JOB_OUTPUT=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))
job = w['jobs']['create_prerelease']
if 'outputs' in job and 'release_tag' in job['outputs']:
    print(job['outputs']['release_tag'])
else:
    print('MISSING')
")

echo "create_prerelease job output: $JOB_OUTPUT"

if [[ "$JOB_OUTPUT" == "\${{ steps.set_output.outputs.release_tag }}" ]]; then
    echo "✅ Job output correctly references set_output step"
else
    echo "❌ Job output reference is incorrect"
    exit 1
fi

# Test 3: Check that the set_output step has an ID
echo
echo "Test 3: Checking set_output step configuration..."
STEP_EXISTS=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))
steps = w['jobs']['create_prerelease']['steps']
for step in steps:
    if step.get('id') == 'set_output' and 'Set release tag output' in step.get('name', ''):
        print('EXISTS')
        break
else:
    print('MISSING')
")

echo "set_output step exists: $STEP_EXISTS"

if [[ "$STEP_EXISTS" == "EXISTS" ]]; then
    echo "✅ set_output step has correct ID"
else
    echo "❌ set_output step is missing or incorrectly configured"
    exit 1
fi

# Test 4: Check that validate_prerelease job receives the output
echo
echo "Test 4: Checking validate_prerelease job input configuration..."
VALIDATION_INPUT=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))
job = w['jobs']['validate_prerelease']
if 'with' in job and 'release_tag' in job['with']:
    print(job['with']['release_tag'])
else:
    print('MISSING')
")

echo "validate_prerelease release_tag input: $VALIDATION_INPUT"

if [[ "$VALIDATION_INPUT" == "\${{ needs.create_prerelease.outputs.release_tag }}" ]]; then
    echo "✅ Validation job correctly receives release_tag from create_prerelease"
else
    echo "❌ Validation job input reference is incorrect"
    exit 1
fi

# Test 5: Check that the reusable workflow can handle the release_tag input
echo
echo "Test 5: Checking reusable workflow parameter handling..."

# Check if release_tag is defined in the reusable workflow inputs
if grep -A2 "release_tag:" .github/workflows/reusable-validate-homebridge.yml | grep -q "required: false"; then
    REUSABLE_PARAM="OPTIONAL"
elif grep -A2 "release_tag:" .github/workflows/reusable-validate-homebridge.yml | grep -q "required: true"; then
    REUSABLE_PARAM="REQUIRED"
else
    REUSABLE_PARAM="MISSING"
fi

echo "reusable workflow release_tag parameter: $REUSABLE_PARAM"

if [[ "$REUSABLE_PARAM" == "OPTIONAL" ]]; then
    echo "✅ Reusable workflow accepts release_tag as optional parameter"
else
    echo "❌ Reusable workflow parameter configuration is incorrect"
    exit 1
fi

echo
echo "🎉 All tests passed! The release tag output fix should resolve the issue."
echo
echo "Summary of the fix:"
echo "  - Added ID 'set_output' to the step that sets the release tag"
echo "  - Changed create_prerelease job output to reference the correct step"
echo "  - validate_prerelease job will now receive a proper release_tag value"
echo "  - This should resolve the 'Please input a valid tag or release ID' error"
echo "  - The robinraju/release-downloader action will get the correct tag parameter"