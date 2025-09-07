#!/bin/bash

# Test script to validate concurrency configuration in workflows
# This ensures the concurrency controls are properly configured

set -e

echo "🧪 Testing concurrency configuration in Release Stage 2 workflow..."

WORKFLOW_FILE=".github/workflows/release-stage-2_build_and_release.yml"

if [[ ! -f "$WORKFLOW_FILE" ]]; then
    echo "❌ ERROR: Workflow file not found: $WORKFLOW_FILE"
    exit 1
fi

echo "✅ Workflow file exists: $WORKFLOW_FILE"

# Check if concurrency section exists
if grep -q "^concurrency:" "$WORKFLOW_FILE"; then
    echo "✅ Concurrency section found"
else
    echo "❌ ERROR: Concurrency section not found in workflow"
    exit 1
fi

# Check for required concurrency fields
if grep -A2 "^concurrency:" "$WORKFLOW_FILE" | grep -q "group:"; then
    echo "✅ Concurrency group configured"
else
    echo "❌ ERROR: Concurrency group not configured"
    exit 1
fi

if grep -A2 "^concurrency:" "$WORKFLOW_FILE" | grep -q "cancel-in-progress:"; then
    echo "✅ Cancel-in-progress setting configured"
else
    echo "❌ ERROR: Cancel-in-progress setting not configured"  
    exit 1
fi

# Validate YAML syntax using Python
echo "🔍 Validating YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW_FILE', 'r'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ ERROR: Invalid YAML syntax in workflow file"
    exit 1
fi

# Check that concurrency is properly placed (should be after permissions)
PERMISSIONS_LINE=$(grep -n "^permissions:" "$WORKFLOW_FILE" | cut -d: -f1)
CONCURRENCY_LINE=$(grep -n "^concurrency:" "$WORKFLOW_FILE" | cut -d: -f1)

if [[ $CONCURRENCY_LINE -gt $PERMISSIONS_LINE ]]; then
    echo "✅ Concurrency section is properly placed after permissions"
else
    echo "⚠️  WARNING: Concurrency section should be placed after permissions section"
fi

# Extract and display the concurrency configuration
echo ""
echo "📋 Current concurrency configuration:"
echo "---"
grep -A5 "^concurrency:" "$WORKFLOW_FILE" | head -n 3
echo "---"

echo ""
echo "🎉 Concurrency configuration validation completed successfully!"
echo "This workflow will now prevent multiple instances from running simultaneously."