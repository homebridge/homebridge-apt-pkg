# Race Condition Fix for Release Stage 1 Workflow

This document explains the fix implemented for the race condition in the Release Stage 1 workflow that was causing "GraphQL: Base branch was modified. Review and try the merge again" errors.

## Problem

The Release Stage 1 workflow was failing with race condition errors when multiple dependency update bots (alpha, beta, stable) tried to merge PRs simultaneously:

1. All three release types would run in parallel using the matrix strategy
2. Each would create PRs and attempt to auto-merge them at the same time
3. When one job merged its PR (modifying the base branch), other jobs would fail with "Base branch was modified"
4. This resulted in workflow failures like run #17525831245

## Solution

The fix was implemented by adding a simple `max-parallel: 1` constraint to the existing matrix strategy:

```yaml
strategy:
  max-parallel: 1
  matrix: ${{ fromJson(needs.determine-release-types.outputs.matrix) }}
```

## Benefits

This approach provides several advantages:

- **✅ Simple and minimal** - Only one line added to the existing workflow
- **✅ Preserves matrix structure** - Maintains the clean matrix approach instead of duplicating jobs
- **✅ Prevents race conditions** - Ensures only one bot operates at a time
- **✅ No code duplication** - Keeps the DRY principle intact
- **✅ Easy to understand** - Clear intent and implementation
- **✅ Maintains existing logic** - All conditional execution and matrix variables preserved

## How It Works

The `max-parallel: 1` constraint ensures that:

1. The matrix still defines all three jobs (alpha, beta, stable)
2. GitHub Actions will only run one matrix job at a time
3. Jobs execute sequentially, preventing simultaneous PR merge attempts
4. Race conditions are eliminated while preserving the clean matrix structure

## Testing

The fix includes a comprehensive test suite that validates:

- YAML syntax correctness
- Matrix strategy with max-parallel constraint
- Single job structure (not separate sequential jobs)
- Matrix variable usage preservation
- Proper race condition prevention

Run tests with:

```bash
./test/test-race-condition-fix.sh
```

This fix resolves the race condition without the complexity of separate sequential jobs, making it both effective and maintainable.