#!/bin/bash
#
# Finds the workflow run that our trigger just created.
#
# Usage: select-new-run.sh <before.json> <after.json> <title text>
#   before.json / after.json: output of
#     gh run list --workflow <file> --event workflow_dispatch --json databaseId,displayTitle,createdAt
#   taken before and after the trigger.
#
# Prints the id of the run that is in the second list, is NOT in the first, and has the text in
# its title. Prints nothing when there is no such run yet.
# (The old code took "the newest run with the right word in its name". The new run is often not
# listed yet, so it picked the previous run, saw "completed, success", and did not wait at all.)

set -euo pipefail

jq -r --slurpfile before "$1" --arg title "$3" '
  ($before[0] | map(.databaseId)) as $known
  | map(select((.databaseId as $id | $known | index($id) | not) and (.displayTitle | contains($title))))
  | sort_by(.createdAt)
  | .[0].databaseId // empty' "$2"
