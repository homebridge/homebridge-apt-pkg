# Trigger and Wait for Workflow Action

Starts a workflow, finds the run that the trigger created, and waits until that run has finished.

Stage 1 uses it to start Stage 2 for one stream at a time, so two releases never run together.

## Usage

```yaml
- name: Trigger and Wait for Stage 2 Workflow
  uses: ./.github/actions/trigger-and-wait-workflow
  with:
    workflow-file: 'release-stage-2_build_and_release.yml'
    ref: 'latest'
    release-type: ${{ matrix.release_type }}
    scheduled: ${{ github.event_name == 'workflow_dispatch' && 'Manual' || 'Scheduled' }}
    github-token: ${{ secrets.GH_TOKEN }}
    timeout-minutes: '150'
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `workflow-file` | Yes | - | The workflow file to trigger |
| `ref` | Yes | `latest` | The git ref to run the workflow on |
| `release-type` | Yes | - | Passed to the workflow as `release_type` |
| `scheduled` | No | `Manual` | Passed to the workflow as `Scheduled` (`Scheduled` or `Manual`) |
| `github-token` | Yes | - | A token that may start workflows and read runs |
| `timeout-minutes` | No | `150` | How long to wait for the run to finish |

## Outputs

| Output | Description |
|--------|-------------|
| `workflow-conclusion` | How the run ended (`success`, `failure`, `cancelled` ...) |
| `run-id` | The id of the run that was started |

## How It Works

1. It saves the list of runs that exist **before** the trigger.
2. It starts the workflow with `gh workflow run`.
3. It asks for the list again every 5 seconds (for up to 2 minutes). The new run is the one that is
   not in the first list and has `- <scheduled> - <release-type> Run` in its title
   (`select-new-run.sh`).
4. It asks for the status of that run every 30 seconds until it has finished (`wait-for-run.sh`).

## When it fails

The step fails (exit code 1) when:

- the workflow could not be started;
- the new run did not show up within 2 minutes;
- the run ended with anything other than `success`;
- the run did not finish within `timeout-minutes`.

A failed step stops the steps after it, so old releases are not cleaned up after a failed release.

## Tests

`test/trigger-and-wait.test.sh` tests both scripts with saved run lists and a fake `gh` command.
