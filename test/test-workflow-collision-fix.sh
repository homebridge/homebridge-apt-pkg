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

# Test 2: Check that the workflow uses the reusable action for collision fix
echo
echo "Test 2: Checking for workflow collision fix using reusable action..."

WORKFLOW_STEPS=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    steps = workflow['jobs']['update_dependencies']['steps']
    step_names = [step.get('name', '') for step in steps if 'name' in step]
    step_uses = [step.get('uses', '') for step in steps if 'uses' in step]
    print('|'.join(step_names))
    print('USES:' + '|'.join(step_uses))
")

# Check for the reusable action that replaces the monolithic trigger steps
if [[ "$WORKFLOW_STEPS" == *"Trigger and Wait for"*"Stage 2 Workflow"* && \
      "$WORKFLOW_STEPS" == *"USES:"*"./.github/actions/trigger-and-wait-workflow"* ]]; then
    echo "✅ Workflow collision fix using reusable action found"
else
    echo "❌ Missing workflow collision fix reusable action"
    echo "Found steps: $WORKFLOW_STEPS"
    exit 1
fi

# Test 3: Validate reusable action YAML syntax
echo
echo "Test 3: Validating reusable action YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('.github/actions/trigger-and-wait-workflow/action.yml'))" 2>/dev/null; then
    echo "✅ Reusable action YAML syntax is valid"
else
    echo "❌ Reusable action YAML syntax error"
    exit 1
fi

# Test 4: Check that action has the 4 steps internally
echo
echo "Test 4: Checking reusable action contains the collision fix logic..."
ACTION_STEPS=$(python3 -c "
import yaml
with open('.github/actions/trigger-and-wait-workflow/action.yml') as f:
    action = yaml.safe_load(f)
    steps = action['runs']['steps']
    step_names = [step.get('name', '') for step in steps if 'name' in step]
    print('|'.join(step_names))
")

if [[ "$ACTION_STEPS" == *"Trigger"*"Workflow"* && \
      "$ACTION_STEPS" == *"Find"*"Workflow Run"* && \
      "$ACTION_STEPS" == *"Extract"*"Workflow Run ID"* && \
      "$ACTION_STEPS" == *"Wait for"*"Workflow Completion"* ]]; then
    echo "✅ All four workflow collision fix steps found in reusable action"
else
    echo "❌ Missing workflow collision fix steps in reusable action"
    echo "Found steps: $ACTION_STEPS"
    exit 1
fi

# Test 5: Check that action trigger step uses gh workflow run
echo
echo "Test 5: Checking action trigger step..."
ACTION_TRIGGER_STEP=$(python3 -c "
import yaml
with open('.github/actions/trigger-and-wait-workflow/action.yml') as f:
    action = yaml.safe_load(f)
    steps = action['runs']['steps']
    for step in steps:
        if 'name' in step and 'Trigger' in step['name'] and 'Workflow' in step['name']:
            print(step['run'])
            break
")

if [[ "$ACTION_TRIGGER_STEP" == *"gh workflow run"* && "$ACTION_TRIGGER_STEP" != *"gh run list"* ]]; then
    echo "✅ Action trigger step properly isolated (contains gh workflow run but not polling logic)"
else
    echo "❌ Action trigger step not properly separated"
    exit 1
fi

# Test 6: Check that action find step uses gh run list
echo
echo "Test 6: Checking action find workflow step..."
ACTION_FIND_STEP=$(python3 -c "
import yaml
with open('.github/actions/trigger-and-wait-workflow/action.yml') as f:
    action = yaml.safe_load(f)
    steps = action['runs']['steps']
    for step in steps:
        if 'name' in step and 'Find' in step['name'] and 'Workflow Run' in step['name']:
            print(step['run'])
            break
")

if [[ "$ACTION_FIND_STEP" == *"gh run list"* && "$ACTION_FIND_STEP" == *"workflow_url"* ]]; then
    echo "✅ Action find step properly uses gh run list and sets workflow_url output"
else
    echo "❌ Action find step missing gh run list or output setting"
    exit 1
fi

# Test 7: Check that action extract step uses BASH_REMATCH
echo
echo "Test 7: Checking action run ID extraction step..."
ACTION_EXTRACT_STEP=$(python3 -c "
import yaml
with open('.github/actions/trigger-and-wait-workflow/action.yml') as f:
    action = yaml.safe_load(f)
    steps = action['runs']['steps']
    for step in steps:
        if 'name' in step and 'Extract' in step['name'] and 'Workflow Run ID' in step['name']:
            print(step['run'])
            break
")

if [[ "$ACTION_EXTRACT_STEP" == *"BASH_REMATCH"* && "$ACTION_EXTRACT_STEP" == *"run_id"* ]]; then
    echo "✅ Action extract step properly uses BASH_REMATCH and sets run_id output"
else
    echo "❌ Action extract step missing BASH_REMATCH or output setting"
    exit 1
fi

# Test 8: Check that action wait step uses gh run view and polling
echo
echo "Test 8: Checking action wait for completion step..."
ACTION_WAIT_STEP=$(python3 -c "
import yaml
with open('.github/actions/trigger-and-wait-workflow/action.yml') as f:
    action = yaml.safe_load(f)
    steps = action['runs']['steps']
    for step in steps:
        if 'name' in step and 'Wait for' in step['name'] and 'Workflow Completion' in step['name']:
            print(step['run'])
            break
")

if [[ "$ACTION_WAIT_STEP" == *"gh run view"* && "$ACTION_WAIT_STEP" == *"while true"* && "$ACTION_WAIT_STEP" == *"conclusion"* ]]; then
    echo "✅ Action wait step properly uses gh run view with polling and conclusion checking"
else
    echo "❌ Action wait step missing gh run view, polling, or conclusion checking"
    exit 1
fi

# Test 9: Check timeout implementation in action
echo
echo "Test 9: Checking timeout implementation..."
if [[ "$ACTION_WAIT_STEP" == *"MAX_WAIT_SECONDS"* && "$ACTION_WAIT_STEP" == *"timeout-minutes"* && "$ACTION_WAIT_STEP" == *"exit 0"* ]]; then
    echo "✅ Timeout implementation found with exit 0 behavior"
else
    echo "❌ Missing timeout implementation or incorrect behavior"
    exit 1
fi

# Test 10: Verify max-parallel constraint still exists
echo
echo "Test 10: Verifying max-parallel constraint is preserved..."
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

# Test 11: Check workflow uses action with proper inputs
echo
echo "Test 11: Checking reusable action inputs..."
ACTION_USAGE=$(python3 -c "
import yaml
with open('.github/workflows/release-stage-1_update_dependencies.yml') as f:
    workflow = yaml.safe_load(f)
    steps = workflow['jobs']['update_dependencies']['steps']
    for step in steps:
        if 'uses' in step and 'trigger-and-wait-workflow' in step['uses']:
            inputs = step.get('with', {})
            print('|'.join([f'{k}:{v}' for k, v in inputs.items()]))
            break
")

if [[ "$ACTION_USAGE" == *"workflow-file:release-stage-2_build_and_release.yml"* && \
      "$ACTION_USAGE" == *"timeout-minutes:30"* && \
      "$ACTION_USAGE" == *"github-token:"* ]]; then
    echo "✅ Reusable action properly configured with required inputs"
else
    echo "❌ Reusable action missing required inputs"
    echo "Found inputs: $ACTION_USAGE"
    exit 1
fi

echo
echo "🎉 All tests passed! The workflow collision fix should resolve the issue."
echo
echo "Summary of the fix:"
echo "  - Created a reusable action (./.github/actions/trigger-and-wait-workflow) that:"
echo "    1. Trigger Workflow - triggers the workflow using gh workflow run"
echo "    2. Find Workflow Run - uses gh run list to find the triggered run"
echo "    3. Extract Workflow Run ID - extracts run ID from the workflow URL"
echo "    4. Wait for Workflow Completion - polls with gh run view until completion"
echo "  - Replaced 4 individual workflow steps with 1 reusable action call"
echo "  - Action is configurable and reusable across other workflows"
echo "  - Includes timeout protection (30 minutes default) with exit 0 behavior"
echo "  - Preserves existing max-parallel: 1 constraint for sequential processing"
echo "  - This prevents workflow collision by ensuring Stage 2 workflows complete sequentially"