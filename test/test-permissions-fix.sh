#!/bin/bash

# Test script to validate the permissions fix for Release Stage 2 workflow
# This script checks that the workflow has the required 'workflows' permission

set -e

echo "🧪 Testing permissions fix for Release Stage 2 workflow..."
echo

# Test 1: Validate YAML syntax
echo "Test 1: Validating YAML syntax..."
if python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))" 2>/dev/null; then
    echo "✅ YAML syntax is valid"
else
    echo "❌ YAML syntax error"
    exit 1
fi

# Test 2: Check that workflows permission is present
echo
echo "Test 2: Checking workflow permissions..."
WORKFLOWS_PERMISSION=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))
perms = w.get('permissions', {})
print(perms.get('workflows', 'MISSING'))
")

echo "Workflows permission: $WORKFLOWS_PERMISSION"

if [[ "$WORKFLOWS_PERMISSION" == "write" ]]; then
    echo "✅ Workflows permission is correctly set to 'write'"
else
    echo "❌ Workflows permission is missing or incorrect"
    exit 1
fi

# Test 3: Check other required permissions are still present
echo
echo "Test 3: Checking other required permissions..."
CONTENTS_PERMISSION=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))
perms = w.get('permissions', {})
print(perms.get('contents', 'MISSING'))
")

ACTIONS_PERMISSION=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))
perms = w.get('permissions', {})
print(perms.get('actions', 'MISSING'))
")

ID_TOKEN_PERMISSION=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))
perms = w.get('permissions', {})
print(perms.get('id-token', 'MISSING'))
")

echo "Contents permission: $CONTENTS_PERMISSION"
echo "Actions permission: $ACTIONS_PERMISSION"
echo "ID token permission: $ID_TOKEN_PERMISSION"

if [[ "$CONTENTS_PERMISSION" == "write" && "$ACTIONS_PERMISSION" == "write" && "$ID_TOKEN_PERMISSION" == "write" ]]; then
    echo "✅ All other required permissions are present"
else
    echo "❌ One or more required permissions are missing"
    exit 1
fi

# Test 4: Validate that the create-github-release action is still used
echo
echo "Test 4: Checking create-github-release action usage..."
CREATE_RELEASE_ACTION=$(python3 -c "
import yaml
w = yaml.safe_load(open('.github/workflows/release-stage-2_build_and_release.yml'))
jobs = w.get('jobs', {})
create_prerelease = jobs.get('create_prerelease', {})
steps = create_prerelease.get('steps', [])
for step in steps:
    uses = step.get('uses', '')
    if 'mini-bomba/create-github-release' in uses:
        print(uses)
        break
else:
    print('NOT_FOUND')
")

echo "Create release action: $CREATE_RELEASE_ACTION"

if [[ "$CREATE_RELEASE_ACTION" == "docker://ghcr.io/mini-bomba/create-github-release:v1.2.0" ]]; then
    echo "✅ Create release action is correctly configured"
else
    echo "❌ Create release action not found or misconfigured"
    exit 1
fi

echo
echo "🎉 All tests passed! The permissions fix should resolve the Release Stage 2 failure."
echo
echo "Summary of the fix:"
echo "  - Added 'workflows: write' permission to allow tag creation that may trigger workflows"
echo "  - Maintains all existing permissions (contents, actions, id-token)"
echo "  - Should resolve the tag creation rejection by GitHub"
echo "  - GitHub App tokens can now create tags that reference workflow files"