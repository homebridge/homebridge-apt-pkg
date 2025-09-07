#!/bin/bash

# Test script to validate the race condition fix for Release Stage 1
# This script validates that the workflow uses max-parallel: 1 to prevent race conditions

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

# Test 2: Check that matrix strategy still exists but with max-parallel constraint
echo
echo "Test 2: Checking matrix strategy with max-parallel constraint..."
WORKFLOW_FILE=".github/workflows/release-stage-1_update_dependencies.yml"

# Check that matrix strategy is present
if grep -q "strategy:" "$WORKFLOW_FILE"; then
    echo "✅ Matrix strategy found"
else
    echo "❌ Matrix strategy missing"
    exit 1
fi

# Check that matrix configuration is present
if grep -q "matrix:" "$WORKFLOW_FILE"; then
    echo "✅ Matrix configuration found"
else
    echo "❌ Matrix configuration missing"
    exit 1
fi

# Test 3: Check that max-parallel: 1 constraint is present
echo
echo "Test 3: Checking max-parallel constraint..."

if grep -q "max-parallel: 1" "$WORKFLOW_FILE"; then
    echo "✅ max-parallel: 1 constraint found"
else
    echo "❌ max-parallel: 1 constraint missing"
    exit 1
fi

# Test 4: Check that single update_dependencies job exists (not separate jobs)
echo
echo "Test 4: Checking single matrix job structure..."

if grep -q "update_dependencies:" "$WORKFLOW_FILE"; then
    echo "✅ Single update_dependencies job found"
else
    echo "❌ update_dependencies job missing"
    exit 1
fi

# Ensure separate alpha/beta/stable jobs don't exist (those were from the old approach)
if grep -q "update_alpha_dependencies:" "$WORKFLOW_FILE"; then
    echo "❌ Separate alpha job found (should use matrix instead)"
    exit 1
else
    echo "✅ No separate alpha job (using matrix approach correctly)"
fi

# Ensure separate beta/stable jobs don't exist (those were from the old approach)
if grep -q "update_beta_dependencies:" "$WORKFLOW_FILE"; then
    echo "❌ Separate beta job found (should use matrix instead)"
    exit 1
else
    echo "✅ No separate beta job (using matrix approach correctly)"
fi

if grep -q "update_stable_dependencies:" "$WORKFLOW_FILE"; then
    echo "❌ Separate stable job found (should use matrix instead)"
    exit 1
else
    echo "✅ No separate stable job (using matrix approach correctly)"
fi

# Test 5: Check that the job still uses matrix variables properly
echo
echo "Test 5: Checking matrix variable usage..."

if grep -q "\${{ matrix.release_type }}" "$WORKFLOW_FILE"; then
    echo "✅ Matrix release_type variable found"
else
    echo "❌ Matrix release_type variable missing"
    exit 1
fi

if grep -q "\${{ matrix.config_file }}" "$WORKFLOW_FILE"; then
    echo "✅ Matrix config_file variable found"
else
    echo "❌ Matrix config_file variable missing"
    exit 1
fi

# Test 6: Check that the job name uses matrix variable
echo
echo "Test 6: Checking matrix job name..."

if grep -q "Update \${{ matrix.release_type }} Dependencies" "$WORKFLOW_FILE"; then
    echo "✅ Job name uses matrix variable correctly"
else
    echo "❌ Job name does not use matrix variable"
    exit 1
fi

# Test 7: Verify that race condition is prevented
echo
echo "Test 7: Verifying race condition prevention..."

# Check that max-parallel and matrix are in the same strategy block
STRATEGY_SECTION=$(python3 -c "
import yaml
with open('$WORKFLOW_FILE') as f:
    w = yaml.safe_load(f)
    strategy = w['jobs']['update_dependencies']['strategy']
    print('max-parallel' in strategy and 'matrix' in strategy)
" 2>/dev/null)

if [[ "$STRATEGY_SECTION" == "True" ]]; then
    echo "✅ max-parallel and matrix are properly configured in strategy"
else
    echo "❌ max-parallel and matrix not properly configured"
    exit 1
fi

echo
echo "🎉 All tests passed! The race condition fix is properly implemented."
echo
echo "Summary of changes:"
echo "  - ✅ Kept the clean matrix strategy structure"
echo "  - ✅ Added max-parallel: 1 constraint to prevent race conditions"
echo "  - ✅ Maintained all existing matrix variable usage"
echo "  - ✅ Preserved conditional execution logic"
echo "  - ✅ Much simpler solution than sequential jobs"
echo
echo "This should resolve the race condition that caused:"
echo "  - 'Base branch was modified. Review and try the merge again' errors"
echo "  - Failed PR merges when multiple bots run simultaneously"
echo "  - Release Stage 1 workflow failures"
echo
echo "The max-parallel: 1 constraint ensures that even though the matrix"
echo "defines multiple jobs (alpha, beta, stable), only one will run at a time,"
echo "preventing the race condition while maintaining the clean matrix structure."