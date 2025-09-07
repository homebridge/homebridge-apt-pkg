#!/bin/bash

# Test script to validate the race condition fix for Release Stage 1
# This script validates that the workflow no longer uses parallel matrix jobs

set -e

echo "🧪 Testing Race Condition Fix for Release Stage 1..."
echo

# Test 1: Validate YAML syntax
echo "Test 1: Validating YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-stage-1_update_dependencies.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax error"
    exit 1
fi

# Test 2: Check that matrix strategy is removed
echo
echo "Test 2: Checking matrix strategy removal..."
WORKFLOW_FILE=".github/workflows/release-stage-1_update_dependencies.yml"

# Check that there's no matrix strategy in the workflow
if grep -q "strategy:" "$WORKFLOW_FILE"; then
    echo "❌ Matrix strategy still present in workflow"
    exit 1
else
    echo "✅ Matrix strategy successfully removed"
fi

# Test 3: Check that separate jobs exist for each release type
echo
echo "Test 3: Checking separate jobs exist..."

# Check for alpha job
if grep -q "update_alpha_dependencies:" "$WORKFLOW_FILE"; then
    echo "✅ Alpha dependencies job found"
else
    echo "❌ Alpha dependencies job missing"
    exit 1
fi

# Check for beta job
if grep -q "update_beta_dependencies:" "$WORKFLOW_FILE"; then
    echo "✅ Beta dependencies job found"
else
    echo "❌ Beta dependencies job missing"
    exit 1
fi

# Check for stable job
if grep -q "update_stable_dependencies:" "$WORKFLOW_FILE"; then
    echo "✅ Stable dependencies job found"
else
    echo "❌ Stable dependencies job missing"
    exit 1
fi

# Test 4: Check job dependencies for sequential execution
echo
echo "Test 4: Checking job dependencies..."

# Extract job dependencies using Python
ALPHA_NEEDS=$(python3 -c "
import yaml
with open('$WORKFLOW_FILE') as f:
    w = yaml.safe_load(f)
    needs = w['jobs']['update_alpha_dependencies'].get('needs', [])
    if isinstance(needs, list):
        print(','.join(needs))
    else:
        print(needs)
" 2>/dev/null || echo "")

BETA_NEEDS=$(python3 -c "
import yaml
with open('$WORKFLOW_FILE') as f:
    w = yaml.safe_load(f)
    needs = w['jobs']['update_beta_dependencies'].get('needs', [])
    if isinstance(needs, list):
        print(','.join(needs))
    else:
        print(needs)
" 2>/dev/null || echo "")

STABLE_NEEDS=$(python3 -c "
import yaml
with open('$WORKFLOW_FILE') as f:
    w = yaml.safe_load(f)
    needs = w['jobs']['update_stable_dependencies'].get('needs', [])
    if isinstance(needs, list):
        print(','.join(needs))
    else:
        print(needs)
" 2>/dev/null || echo "")

echo "Alpha job needs: $ALPHA_NEEDS"
echo "Beta job needs: $BETA_NEEDS" 
echo "Stable job needs: $STABLE_NEEDS"

# Alpha should only depend on determine-release-types
if [[ "$ALPHA_NEEDS" == "determine-release-types" ]]; then
    echo "✅ Alpha job has correct dependencies"
else
    echo "❌ Alpha job dependencies incorrect"
    exit 1
fi

# Beta should depend on determine-release-types and update_alpha_dependencies
if [[ "$BETA_NEEDS" == *"determine-release-types"* && "$BETA_NEEDS" == *"update_alpha_dependencies"* ]]; then
    echo "✅ Beta job has correct dependencies"
else
    echo "❌ Beta job dependencies incorrect"
    exit 1
fi

# Stable should depend on determine-release-types and update_beta_dependencies
if [[ "$STABLE_NEEDS" == *"determine-release-types"* && "$STABLE_NEEDS" == *"update_beta_dependencies"* ]]; then
    echo "✅ Stable job has correct dependencies"
else
    echo "❌ Stable job dependencies incorrect"
    exit 1
fi

# Test 5: Check that always() conditions are used for proper error handling
echo
echo "Test 5: Checking always() conditions..."

# Beta and stable jobs should use always() to continue even if previous jobs fail
if grep -A5 "update_beta_dependencies:" "$WORKFLOW_FILE" | grep -q "always()"; then
    echo "✅ Beta job uses always() condition"
else
    echo "❌ Beta job missing always() condition"
    exit 1
fi

if grep -A5 "update_stable_dependencies:" "$WORKFLOW_FILE" | grep -q "always()"; then
    echo "✅ Stable job uses always() condition"
else
    echo "❌ Stable job missing always() condition"
    exit 1
fi

# Test 6: Check that conditional execution based on matrix still works
echo
echo "Test 6: Checking conditional execution..."

# All jobs should have conditions to check if they should run based on the determined matrix
for job in "alpha" "beta" "stable"; do
    if grep -A5 "update_${job}_dependencies:" "$WORKFLOW_FILE" | grep -q "contains.*release_type.*${job}"; then
        echo "✅ ${job^} job has proper conditional execution"
    else
        echo "❌ ${job^} job missing conditional execution"
        exit 1
    fi
done

# Test 7: Check that hardcoded config files are correct
echo
echo "Test 7: Checking config file references..."

if grep -q ".github/homebridge-alpha-bot.json" "$WORKFLOW_FILE"; then
    echo "✅ Alpha config file correctly referenced"
else
    echo "❌ Alpha config file reference incorrect"
    exit 1
fi

if grep -q ".github/homebridge-beta-bot.json" "$WORKFLOW_FILE"; then
    echo "✅ Beta config file correctly referenced"
else
    echo "❌ Beta config file reference incorrect"
    exit 1
fi

if grep -q ".github/homebridge-stable-bot.json" "$WORKFLOW_FILE"; then
    echo "✅ Stable config file correctly referenced"
else
    echo "❌ Stable config file reference incorrect"
    exit 1
fi

echo
echo "🎉 All tests passed! The race condition fix is properly implemented."
echo
echo "Summary of changes:"
echo "  - ✅ Removed parallel matrix strategy"
echo "  - ✅ Created separate sequential jobs for alpha, beta, stable"
echo "  - ✅ Added proper job dependencies to ensure sequential execution"
echo "  - ✅ Used always() conditions for error resilience"
echo "  - ✅ Maintained conditional execution based on release types"
echo "  - ✅ Fixed hardcoded config file references"
echo
echo "This should resolve the race condition that caused:"
echo "  - 'Base branch was modified. Review and try the merge again' errors"
echo "  - Failed PR merges when multiple bots run simultaneously"
echo "  - Release Stage 1 workflow failures"