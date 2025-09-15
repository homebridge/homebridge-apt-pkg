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

# Test 2: Check that the workflow steps include the collision fix logic
echo
echo "Test 2: Checking for workflow collision fix steps..."

WORKFLOW_STEPS=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    steps = workflow['jobs']['update_dependencies']['steps']
    step_names = [step.get('name', '') for step in steps if 'name' in step]
    print('|'.join(step_names))
")

# Check for the 4 separate steps that replace the monolithic trigger step
if [[ "$WORKFLOW_STEPS" == *"Trigger"*"Stage 2 Workflow"* && \
      "$WORKFLOW_STEPS" == *"Find"*"Stage 2 Workflow Run"* && \
      "$WORKFLOW_STEPS" == *"Extract"*"Workflow Run ID"* && \
      "$WORKFLOW_STEPS" == *"Wait for"*"Stage 2 Completion"* ]]; then
    echo "✅ All four workflow collision fix steps found"
else
    echo "❌ Missing workflow collision fix steps"
    echo "Found steps: $WORKFLOW_STEPS"
    exit 1
fi

# Test 3: Check that trigger step is properly separated
echo
echo "Test 3: Checking trigger step separation..."
TRIGGER_STEP=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    jobs = workflow['jobs']['update_dependencies']['steps']
    for step in jobs:
        if 'name' in step and 'Trigger' in step['name'] and 'Stage 2 Workflow' in step['name']:
            print(step['run'])
            break
")

if [[ "$TRIGGER_STEP" == *"gh workflow run"* && "$TRIGGER_STEP" != *"gh run list"* ]]; then
    echo "✅ Trigger step properly isolated (contains gh workflow run but not polling logic)"
else
    echo "❌ Trigger step not properly separated"
    exit 1
fi

# Test 4: Check that find step uses gh run list
echo
echo "Test 4: Checking find workflow step..."
FIND_STEP=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    jobs = workflow['jobs']['update_dependencies']['steps']
    for step in jobs:
        if 'name' in step and 'Find' in step['name'] and 'Stage 2 Workflow Run' in step['name']:
            print(step['run'])
            break
")

if [[ "$FIND_STEP" == *"gh run list"* && "$FIND_STEP" == *"workflow_url"* ]]; then
    echo "✅ Find step properly uses gh run list and sets workflow_url output"
else
    echo "❌ Find step missing gh run list or output setting"
    exit 1
fi

# Test 5: Check that extract step uses BASH_REMATCH
echo
echo "Test 5: Checking run ID extraction step..."
EXTRACT_STEP=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    jobs = workflow['jobs']['update_dependencies']['steps']
    for step in jobs:
        if 'name' in step and 'Extract' in step['name'] and 'Workflow Run ID' in step['name']:
            print(step['run'])
            break
")

if [[ "$EXTRACT_STEP" == *"BASH_REMATCH"* && "$EXTRACT_STEP" == *"run_id"* ]]; then
    echo "✅ Extract step properly uses BASH_REMATCH and sets run_id output"
else
    echo "❌ Extract step missing BASH_REMATCH or output setting"
    exit 1
fi

# Test 6: Check that wait step uses gh run view and polling
echo
echo "Test 6: Checking wait for completion step..."
WAIT_STEP=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    jobs = workflow['jobs']['update_dependencies']['steps']
    for step in jobs:
        if 'name' in step and 'Wait for' in step['name'] and 'Stage 2 Completion' in step['name']:
            print(step['run'])
            break
")

if [[ "$WAIT_STEP" == *"gh run view"* && "$WAIT_STEP" == *"while true"* && "$WAIT_STEP" == *"conclusion"* ]]; then
    echo "✅ Wait step properly uses gh run view with polling and conclusion checking"
else
    echo "❌ Wait step missing gh run view, polling, or conclusion checking"
    exit 1
fi

# Test 7: Verify max-parallel constraint still exists
echo
echo "Test 7: Verifying max-parallel constraint is preserved..."
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

# Test 8: Check step dependencies and outputs
echo
echo "Test 8: Checking step dependencies and outputs..."

# Check that find step has an id and outputs workflow_url
FIND_STEP_ID=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    jobs = workflow['jobs']['update_dependencies']['steps']
    for step in jobs:
        if 'name' in step and 'Find' in step['name'] and 'Stage 2 Workflow Run' in step['name']:
            print(step.get('id', ''))
            break
")

# Check that extract step has an id and outputs run_id
EXTRACT_STEP_ID=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    jobs = workflow['jobs']['update_dependencies']['steps']
    for step in jobs:
        if 'name' in step and 'Extract' in step['name'] and 'Workflow Run ID' in step['name']:
            print(step.get('id', ''))
            break
")

if [[ "$FIND_STEP_ID" == "find-workflow" && "$EXTRACT_STEP_ID" == "extract-run-id" ]]; then
    echo "✅ Step IDs properly set for output passing"
else
    echo "❌ Missing step IDs for output passing"
    echo "Find step ID: $FIND_STEP_ID"
    echo "Extract step ID: $EXTRACT_STEP_ID"
    exit 1
fi

# Test 9: Check notification messages for clarity
echo
echo "Test 9: Checking notification messages..."
ALL_STEPS=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    jobs = workflow['jobs']['update_dependencies']['steps']
    all_run_content = ''
    for step in jobs:
        if 'name' in step and ('Trigger' in step['name'] or 'Find' in step['name'] or 'Extract' in step['name'] or 'Wait for' in step['name']):
            if step['name'].endswith('Package') or 'Stage 2' in step['name']:
                all_run_content += step.get('run', '') + ' '
    print(all_run_content)
")

if [[ "$ALL_STEPS" == *"Waiting for"* && "$ALL_STEPS" == *"to complete"* && "$ALL_STEPS" == *"workflow triggered successfully"* ]]; then
    echo "✅ Clear notification messages found across all steps"
else
    echo "❌ Missing clear notification messages"
    exit 1
fi

# Test 10: Check for proper conclusion handling
echo
echo "Test 10: Checking for conclusion handling..."
if [[ "$WAIT_STEP" == *"conclusion"* && "$WAIT_STEP" == *"success"* ]]; then
    echo "✅ Proper conclusion handling found"
else
    echo "❌ Missing proper conclusion handling"
    exit 1
fi

echo
echo "🎉 All tests passed! The workflow collision fix should resolve the issue."
echo
echo "Summary of the fix:"
echo "  - Split the monolithic trigger step into 4 separate, manageable steps:"
echo "    1. Trigger Stage 2 Workflow - triggers the workflow using gh workflow run"
echo "    2. Find Stage 2 Workflow Run - uses gh run list to find the triggered run"
echo "    3. Extract Workflow Run ID - extracts run ID from the workflow URL"
echo "    4. Wait for Stage 2 Completion - polls with gh run view until completion"
echo "  - Each step has a single responsibility for better maintainability"
echo "  - Uses step outputs to pass data between steps"
echo "  - Preserves existing max-parallel: 1 constraint for sequential processing"
echo "  - This prevents workflow collision by ensuring Stage 2 workflows complete sequentially"