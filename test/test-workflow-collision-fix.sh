#!/bin/bash

# Test script to validate the workflow collision fix
# This script validates that Stage 1 properly waits for Stage 2 workflows to complete

set -e

echo "🧪 Testing workflow collision fix..."
echo

# Test 1: Validate YAML syntax of Stage 1 workflow
echo "Test 1: Validating YAML syntax of Stage 1 workflow..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-stage-1_update_dependencies.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax error"
    exit 1
fi

# Test 2: Check that the trigger step includes workflow wait logic
echo
echo "Test 2: Checking for workflow wait logic in trigger step..."
TRIGGER_STEP=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    jobs = workflow['jobs']['update_dependencies']['steps']
    for step in jobs:
        if 'name' in step and 'Trigger Build and Release' in step['name']:
            print(step['run'])
            break
")

if [[ "$TRIGGER_STEP" == *"gh run watch"* ]]; then
    echo "✅ Workflow wait logic (gh run watch) found in trigger step"
else
    echo "❌ Missing workflow wait logic in trigger step"
    exit 1
fi

# Test 3: Check for run ID extraction logic
echo
echo "Test 3: Checking for run ID extraction logic..."
if [[ "$TRIGGER_STEP" == *"BASH_REMATCH"* ]]; then
    echo "✅ Run ID extraction logic found"
else
    echo "❌ Missing run ID extraction logic"
    exit 1
fi

# Test 4: Check for proper error handling
echo
echo "Test 4: Checking for proper error handling..."
if [[ "$TRIGGER_STEP" == *"--exit-status"* ]]; then
    echo "✅ Exit status handling for gh run watch found"
else
    echo "❌ Missing exit status handling"
    exit 1
fi

# Test 5: Verify max-parallel constraint still exists
echo
echo "Test 5: Verifying max-parallel constraint is preserved..."
MAX_PARALLEL=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    strategy = workflow['jobs']['update_dependencies']['strategy']
    print(strategy.get('max-parallel', 'missing'))
")

if [[ "$MAX_PARALLEL" == "1" ]]; then
    echo "✅ max-parallel: 1 constraint preserved"
else
    echo "❌ max-parallel constraint missing or incorrect: $MAX_PARALLEL"
    exit 1
fi

# Test 6: Check notification messages for clarity
echo
echo "Test 6: Checking notification messages..."
if [[ "$TRIGGER_STEP" == *"Waiting for"* && "$TRIGGER_STEP" == *"to complete"* ]]; then
    echo "✅ Clear notification messages found"
else
    echo "❌ Missing clear notification messages"
    exit 1
fi

echo
echo "🎉 All tests passed! The workflow collision fix should resolve the issue."
echo
echo "Summary of the fix:"
echo "  - Stage 1 now captures workflow run ID when triggering Stage 2"
echo "  - Uses 'gh run watch --exit-status' to wait for each Stage 2 workflow to complete"
echo "  - Includes proper error handling and logging"
echo "  - Preserves existing max-parallel: 1 constraint for sequential processing"
echo "  - This prevents workflow collision by ensuring Stage 2 workflows complete sequentially"