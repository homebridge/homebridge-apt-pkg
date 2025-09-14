# Workflow Collision Fix

This document explains the workflow collision fix implemented to prevent Stage 2 workflow cancellations when multiple releases are targeted.

## Problem

When Stage 1 processes multiple release types (alpha, beta, stable), it triggers multiple Stage 2 workflows in rapid succession. Although Stage 2 has concurrency controls:

```yaml
concurrency:
  group: release-stage-2
  cancel-in-progress: false
```

This configuration queues multiple Stage 2 workflows, but can cause the last one to be cancelled due to workflow collision during the publishing phase.

The issue occurred in the following sequence:
1. Stage 1 processes alpha, beta, and stable sequentially (due to `max-parallel: 1`)
2. Each matrix job triggers Stage 2 using `gh workflow run`
3. Multiple Stage 2 workflows get queued rapidly
4. The last triggered workflow gets cancelled due to collision

## Solution

The fix implements the GitHub CLI pattern where Stage 1 waits for each triggered Stage 2 workflow to complete before proceeding to the next matrix job.

### Implementation

Modified the "Trigger Build and Release" step in Stage 1 to:

1. **Capture workflow run ID** from `gh workflow run` output
2. **Extract run ID** using regex pattern matching
3. **Wait for completion** using `gh run watch --exit-status`
4. **Handle errors** properly with exit status codes

```yaml
- name: Trigger Build and Release ${{ matrix.release_type }} Package
  if: steps.homebridge-bot.outputs.changes_detected == 'true' && steps.homebridge-bot.outputs.auto_merge == 'true'
  env:
    GH_TOKEN: ${{ secrets.GH_TOKEN }}
  run: |
    echo "::notice::Triggering ${{ matrix.release_type }} Stage 2 - Build and Release ${{ matrix.release_type }} Package"
    
    # Trigger the workflow and capture the run URL
    WORKFLOW_URL=$(gh workflow run release-stage-2_build_and_release.yml \
      --ref latest \
      --field release_type=${{ matrix.release_type }} \
      --field Scheduled=${{ github.event_name == 'workflow_dispatch' && 'Manual' || 'Scheduled' }} \
      2>&1) || { 
      echo "::error::Failed to trigger ${{ matrix.release_type }} Stage 2 workflow"; 
      exit 1; 
    }
    
    # Extract run ID from the URL (format: https://github.com/owner/repo/actions/runs/RUN_ID)
    if [[ "$WORKFLOW_URL" =~ actions/runs/([0-9]+) ]]; then
      RUN_ID="${BASH_REMATCH[1]}"
      echo "::notice::Triggered ${{ matrix.release_type }} workflow run ID: $RUN_ID"
      
      # Wait for the workflow to complete before proceeding
      echo "::notice::Waiting for ${{ matrix.release_type }} Stage 2 workflow (run $RUN_ID) to complete..."
      gh run watch "$RUN_ID" --exit-status || {
        echo "::error::${{ matrix.release_type }} Stage 2 workflow failed or was cancelled"
        exit 1
      }
      
      echo "::notice::${{ matrix.release_type }} Stage 2 workflow completed successfully"
    else
      echo "::error::Could not extract run ID from workflow trigger output: $WORKFLOW_URL"
      exit 1
    fi
```

## How It Works

1. **Sequential Processing**: Stage 1 processes alpha, beta, stable sequentially due to `max-parallel: 1`
2. **Workflow Triggering**: Each matrix job triggers Stage 2 and captures the workflow URL
3. **Run ID Extraction**: Extracts the run ID using regex pattern matching
4. **Wait for Completion**: Uses `gh run watch --exit-status` to wait for the workflow to complete
5. **Error Handling**: Fails the job if the triggered workflow fails or is cancelled
6. **Next Job**: Only proceeds to the next matrix job after the current Stage 2 workflow completes

## Benefits

- **Prevents Workflow Collision**: Ensures Stage 2 workflows complete sequentially
- **Maintains Data Integrity**: No more cancelled workflows during publishing
- **Better Error Handling**: Fails fast if any Stage 2 workflow fails
- **Clear Logging**: Provides detailed progress information
- **Preserves Existing Logic**: Maintains all existing conditional execution

## Testing

The fix includes a comprehensive test suite:

```bash
./test/test-workflow-collision-fix.sh
```

This validates:
- YAML syntax correctness
- Workflow wait logic presence (`gh run watch`)
- Run ID extraction logic
- Proper error handling with `--exit-status`
- Preservation of existing `max-parallel: 1` constraint
- Clear notification messages

## Impact

- **No Breaking Changes**: Existing functionality remains unchanged
- **Improved Reliability**: Eliminates workflow collision failures
- **Sequential Execution**: Ensures predictable release pipeline behavior
- **Better Resource Usage**: Prevents resource contention during Stage 2 execution

The workflow collision issue is now resolved, ensuring that when multiple releases are targeted, each Stage 2 workflow completes fully before the next one begins.