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

The fix implements the GitHub CLI pattern recommended in [cli/cli#4001](https://github.com/cli/cli/issues/4001#issuecomment-2742170405) where Stage 1 waits for each triggered Stage 2 workflow to complete before proceeding to the next matrix job.

### Implementation

Modified the workflow triggering process in Stage 1 by splitting the complex monolithic step into four separate, manageable steps:

#### 1. Trigger Stage 2 Workflow
Triggers the Stage 2 workflow using `gh workflow run`:

```yaml
- name: Trigger ${{ matrix.release_type }} Stage 2 Workflow
  if: steps.homebridge-bot.outputs.changes_detected == 'true' && steps.homebridge-bot.outputs.auto_merge == 'true'
  env:
    GH_TOKEN: ${{ secrets.GH_TOKEN }}
  run: |
    echo "::notice::Triggering ${{ matrix.release_type }} Stage 2 - Build and Release ${{ matrix.release_type }} Package"
    
    gh workflow run release-stage-2_build_and_release.yml \
      --ref latest \
      --field release_type=${{ matrix.release_type }} \
      --field Scheduled=${{ github.event_name == 'workflow_dispatch' && 'Manual' || 'Scheduled' }} || { 
      echo "::error::Failed to trigger ${{ matrix.release_type }} Stage 2 workflow"; 
      exit 1; 
    }
    
    echo "::notice::${{ matrix.release_type }} Stage 2 workflow triggered successfully"
```

#### 2. Find Stage 2 Workflow Run
Uses `gh run list` to locate the most recently triggered workflow:

```yaml
- name: Find ${{ matrix.release_type }} Stage 2 Workflow Run
  if: steps.homebridge-bot.outputs.changes_detected == 'true' && steps.homebridge-bot.outputs.auto_merge == 'true'
  id: find-workflow
  env:
    GH_TOKEN: ${{ secrets.GH_TOKEN }}
  run: |
    echo "::notice::Waiting for ${{ matrix.release_type }} Stage 2 workflow to appear in run list..."
    
    # Wait for the workflow to appear in the list
    sleep 5
    
    # Get the URL of the most recent workflow run
    WORKFLOW_URL=$(gh run list --workflow release-stage-2_build_and_release.yml \
      --event workflow_dispatch \
      --branch latest \
      --limit 1 \
      --json url \
      | jq -r '.[].url')
    
    if [[ -z "$WORKFLOW_URL" || "$WORKFLOW_URL" == "null" ]]; then
      echo "::error::Could not find triggered ${{ matrix.release_type }} Stage 2 workflow run"
      exit 1
    fi
    
    echo "::notice::Found ${{ matrix.release_type }} workflow run: $WORKFLOW_URL"
    echo "workflow_url=$WORKFLOW_URL" >> $GITHUB_OUTPUT
```

#### 3. Extract Workflow Run ID
Extracts the run ID from the workflow URL using regex:

```yaml
- name: Extract ${{ matrix.release_type }} Workflow Run ID
  if: steps.homebridge-bot.outputs.changes_detected == 'true' && steps.homebridge-bot.outputs.auto_merge == 'true'
  id: extract-run-id
  run: |
    WORKFLOW_URL="${{ steps.find-workflow.outputs.workflow_url }}"
    
    # Extract run ID from the URL
    if [[ "$WORKFLOW_URL" =~ actions/runs/([0-9]+) ]]; then
      RUN_ID="${BASH_REMATCH[1]}"
      echo "::notice::Extracted run ID: $RUN_ID"
      echo "run_id=$RUN_ID" >> $GITHUB_OUTPUT
    else
      echo "::error::Could not extract run ID from workflow URL: $WORKFLOW_URL"
      exit 1
    fi
```

#### 4. Wait for Stage 2 Completion
Polls the workflow status using `gh run view` until completion:

```yaml
- name: Wait for ${{ matrix.release_type }} Stage 2 Completion
  if: steps.homebridge-bot.outputs.changes_detected == 'true' && steps.homebridge-bot.outputs.auto_merge == 'true'
  env:
    GH_TOKEN: ${{ secrets.GH_TOKEN }}
  run: |
    RUN_ID="${{ steps.extract-run-id.outputs.run_id }}"
    echo "::notice::Waiting for ${{ matrix.release_type }} Stage 2 workflow (run $RUN_ID) to complete..."
    
    # Poll the workflow status until it completes
    while true; do
      STATUS=$(gh run view "$RUN_ID" --json status -q '.status')
      
      case "$STATUS" in
        "completed")
          CONCLUSION=$(gh run view "$RUN_ID" --json conclusion -q '.conclusion')
          if [[ "$CONCLUSION" == "success" ]]; then
            echo "::notice::${{ matrix.release_type }} Stage 2 workflow completed successfully"
            break
          else
            echo "::error::${{ matrix.release_type }} Stage 2 workflow failed with conclusion: $CONCLUSION"
            exit 1
          fi
          ;;
        "in_progress"|"queued"|"requested"|"waiting")
          echo "::notice::${{ matrix.release_type }} workflow status: $STATUS - continuing to wait..."
          sleep 30
          ;;
        *)
          echo "::error::${{ matrix.release_type }} Stage 2 workflow has unexpected status: $STATUS"
          exit 1
          ;;
      esac
    done
```

## How It Works

1. **Sequential Processing**: Stage 1 processes alpha, beta, stable sequentially due to `max-parallel: 1`
2. **Step 1 - Workflow Triggering**: Each matrix job triggers Stage 2 using `gh workflow run`
3. **Step 2 - Find Latest Run**: Uses `gh run list` to find the most recently triggered workflow run
4. **Step 3 - Run ID Extraction**: Extracts the run ID using regex pattern matching from workflow URL
5. **Step 4 - Status Polling**: Uses `gh run view` in a loop to monitor workflow status
6. **Completion Check**: Waits until status is "completed" and checks conclusion
7. **Next Job**: Only proceeds to the next matrix job after the current Stage 2 workflow completes

## Benefits

- **Better Maintainability**: Each step has a single, clear responsibility
- **Easier Debugging**: Failures can be isolated to specific steps
- **Step Output Passing**: Uses GitHub Actions step outputs for clean data flow
- **Prevents Workflow Collision**: Ensures Stage 2 workflows complete sequentially
- **Maintains Data Integrity**: No more cancelled workflows during publishing
- **Better Error Handling**: Handles all workflow states (success, failure, cancellation)
- **Clear Logging**: Provides detailed progress information with status updates
- **Preserves Existing Logic**: Maintains all existing conditional execution
- **Uses Standard GitHub CLI**: Based on proven patterns from the GitHub CLI team

## Testing

The fix includes a comprehensive test suite:

```bash
./test/test-workflow-collision-fix.sh
```

This validates:
- YAML syntax correctness
- Presence of all four workflow collision fix steps
- Proper separation of trigger logic from polling logic
- Use of `gh run list` in the find step
- Run ID extraction logic using BASH_REMATCH
- Proper status and conclusion handling with `gh run view`
- Step output dependencies and data flow
- Preservation of existing `max-parallel: 1` constraint
- Clear notification messages across all steps

## Impact

- **No Breaking Changes**: Existing functionality remains unchanged
- **Improved Maintainability**: Each step has a single responsibility for easier support and debugging
- **Better Error Isolation**: Failures can be traced to specific workflow collision fix steps
- **Improved Reliability**: Eliminates workflow collision failures
- **Sequential Execution**: Ensures predictable release pipeline behavior
- **Better Resource Usage**: Prevents resource contention during Stage 2 execution
- **Standard Implementation**: Uses documented GitHub CLI patterns
- **Clean Data Flow**: Uses GitHub Actions step outputs for passing data between steps

The workflow collision issue is now resolved with a well-structured, maintainable implementation. When multiple releases are targeted, each Stage 2 workflow completes fully before the next one begins, with clear separation of concerns across four dedicated steps.