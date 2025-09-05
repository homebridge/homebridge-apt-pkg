# Fix for Issue #211: "Run is blocked"

## Problem Summary
The issue "Run is blocked" was caused by the Stage 1 workflow failing to trigger the Stage 2 workflow due to insufficient permissions. The error message was:

```
could not create workflow dispatch event: HTTP 403: Resource not accessible by personal access token
```

## Root Cause
The `release-stage-1_update_dependencies.yml` workflow was missing the `actions: write` permission needed to trigger other workflows via `gh workflow run`.

## Solution
Added the missing permission to the workflow:

```yaml
permissions:
  contents: write
  pull-requests: write
  actions: write  # <- Added this line
```

## Impact on Raspberry Pi 1 B Users
This fix is particularly important for Raspberry Pi 1 B users (32-bit ARM) because:

1. **Prevents Update Blocking**: When workflows fail to chain properly, new package releases don't get published, blocking users from receiving updates.

2. **Maintains 32-bit ARM Compatibility**: The repository correctly uses Node.js ≤22 for 32-bit ARM configurations, which is compatible with Raspberry Pi 1 B.

3. **Ensures Continuous Updates**: With the workflow fix, automated dependency updates can now properly trigger package builds and releases.

## Verification
All tests pass:
- ✅ Node.js version validation for 32-bit ARM
- ✅ Build script validation  
- ✅ Raspberry Pi 1 B compatibility test
- ✅ Workflow YAML syntax validation

## Test Results
```bash
$ ./test/test-raspberry-pi-1b-compatibility.sh
🍓 Testing Raspberry Pi 1 B (32-bit ARM) Compatibility
=====================================================

✅ All Raspberry Pi 1 B compatibility tests passed!

Summary:
  ✅ 32-bit ARM package configurations use Node.js ≤22
  ✅ Build validation would work correctly for ARM32
  ✅ Workflow permissions fixed to prevent blocking
  ✅ Build script has proper error handling for ARM32

💡 Raspberry Pi 1 B users should be able to install and update
   Homebridge packages without issues once this fix is deployed.
```

## Files Changed
- `.github/workflows/release-stage-1_update_dependencies.yml` - Added `actions: write` permission
- `test/test-raspberry-pi-1b-compatibility.sh` - Added validation test

The fix is minimal, surgical, and addresses the core issue preventing package releases from reaching users.