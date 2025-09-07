# Concurrency Controls Fix

This document explains the concurrency controls added to the Release Stage 2 workflow to prevent race conditions.

## Problem

The Release Stage 2 workflow (`release-stage-2_build_and_release.yml`) could potentially be triggered multiple times simultaneously, either through:
- Multiple manual `workflow_dispatch` triggers
- Scheduled runs overlapping with manual runs  
- Rapid successive commits triggering the workflow

This could lead to:
- Race conditions in package building and publishing
- Conflicting GitHub releases being created
- APT repository corruption from simultaneous uploads
- NPM publishing conflicts

## Solution

Added workflow-level concurrency controls:

```yaml
concurrency:
  group: release-stage-2
  cancel-in-progress: false
```

### Configuration Details

- **`group: release-stage-2`**: Creates a concurrency group that ensures only one instance of this workflow can run at a time across the entire repository, regardless of trigger type or parameters.

- **`cancel-in-progress: false`**: Prevents cancellation of already-running workflow instances. This is crucial for release workflows because:
  - Partial builds should not be interrupted  
  - Package publishing operations need to complete atomically
  - GitHub releases should not be left in an inconsistent state

## How It Works

1. When a workflow run starts, GitHub checks if any other runs in the same concurrency group are active
2. If another run is active, the new run waits in a queue
3. Only one run executes at a time within the concurrency group
4. Queued runs execute in order when the active run completes

## Benefits

- **Prevents Race Conditions**: No more simultaneous builds that could conflict
- **Ensures Data Integrity**: APT repository and NPM registry remain consistent
- **Resource Efficiency**: Prevents unnecessary parallel builds
- **Predictable Behavior**: Release operations complete in a deterministic order

## Alternative Approaches Considered

1. **Per-release-type concurrency**: Using `group: release-stage-2-${{ inputs.release_type }}` would allow concurrent alpha/beta/stable builds but risk resource conflicts
2. **Job-level concurrency**: Would still allow workflow-level conflicts in GitHub release creation
3. **Cancel-in-progress: true**: Would risk incomplete releases and corrupt states

The chosen approach prioritizes data integrity and consistency over parallelism.

## Testing

The concurrency configuration can be tested using:

```bash
./test/test-concurrency-fix.sh
```

This validates:
- Concurrency section exists and is properly formatted
- YAML syntax remains valid
- Configuration follows GitHub Actions best practices

## Impact

- **No Breaking Changes**: Existing functionality remains unchanged
- **Improved Reliability**: Eliminates race condition failures
- **Better Resource Usage**: Prevents resource contention during builds
- **Enhanced Stability**: Ensures predictable release pipeline behavior

The workflow will now queue multiple concurrent requests instead of running them simultaneously, ensuring each release process completes fully before the next one begins.