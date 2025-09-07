# Fix for Release Stage 2 Failure - Permissions Issue

## Problem
The Release Stage 2 workflow was failing when trying to create GitHub releases with the error:
```
! [remote rejected] v1.7.8 -> v1.7.8 (refusing to allow a GitHub App to create or update workflow `.github/workflows/release-stage-2_build_and_release.yml` without `workflows` permission)
error: failed to push some refs to 'https://github.com/homebridge/homebridge-apt-pkg'
```

## Root Cause
The `mini-bomba/create-github-release:v1.2.0` Docker action was attempting to create Git tags, but the workflow's GitHub token lacked the `workflows` permission required to create tags that could potentially trigger other workflows.

## Solution
Added the `workflows: write` permission to the Release Stage 2 workflow permissions:

**Before:**
```yaml
permissions:
  contents: write
  actions: write
  id-token: write
```

**After:**
```yaml
permissions:
  contents: write
  actions: write
  id-token: write
  workflows: write
```

## Why This Fixes It
- GitHub Apps and tokens require the `workflows` permission to create Git tags that reference workflow files
- The `workflows: write` permission allows the action to create tags even if they might trigger other workflows
- This is a security feature to prevent unauthorized workflow triggers via tag creation

## Files Changed
- `.github/workflows/release-stage-2_build_and_release.yml`: Added `workflows: write` permission
- `test/test-permissions-fix.sh`: Created comprehensive test to validate the fix

## Validation
The fix has been validated with:
- YAML syntax validation for all modified workflows
- Permission verification tests
- Existing workflow functionality tests
- No breaking changes to other workflows

## Impact
This change should resolve the Release Stage 2 failures and allow successful creation of stable, beta, and alpha releases through the GitHub release process.