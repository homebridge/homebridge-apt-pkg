#!/bin/bash
#
# Waits until a workflow run has finished.
#
# Usage: wait-for-run.sh <run id> <timeout in minutes>
# Env:   GH_TOKEN (for the gh command), POLL_SECONDS (default 30)
#
# Exit code 0 only when the run ended with "success".
# Exit code 1 when it failed, was cancelled, could not be read, or did not finish in time.
# With $GITHUB_OUTPUT set, writes "conclusion=<value>" to it.

set -uo pipefail

RUN_ID="${1:?run id required}"
TIMEOUT_MINUTES="${2:?timeout in minutes required}"
POLL_SECONDS="${POLL_SECONDS:-30}"
deadline=$(($(date +%s) + TIMEOUT_MINUTES * 60))
read_errors=0

while true; do
  if state=$(gh run view "$RUN_ID" --json status,conclusion --jq '.status + " " + (.conclusion // "")'); then
    read_errors=0
  else
    # one failed request is not a failed release: try a few times before giving up
    read_errors=$((read_errors + 1))
    if [ "$read_errors" -ge 5 ]; then
      echo "::error::Could not read the status of run $RUN_ID (5 tries)"
      exit 1
    fi
    state="unknown"
  fi
  status="${state%% *}"
  conclusion="${state#* }"

  if [ "$status" = "completed" ]; then
    [ -n "${GITHUB_OUTPUT:-}" ] && echo "conclusion=$conclusion" >> "$GITHUB_OUTPUT"
    if [ "$conclusion" = "success" ]; then
      echo "::notice::Run $RUN_ID completed successfully"
      exit 0
    fi
    echo "::error::Run $RUN_ID ended with: $conclusion"
    exit 1
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "::error::Run $RUN_ID did not finish within $TIMEOUT_MINUTES minutes (status: $status)"
    exit 1
  fi

  echo "Run $RUN_ID status: $status. Waiting..."
  sleep "$POLL_SECONDS"
done
