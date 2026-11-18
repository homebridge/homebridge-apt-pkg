#!/usr/bin/env bash
#
# Checks on the GitHub workflow files. They can not be run here, so these tests read them as data.
# Needs python3 with PyYAML (Debian and Ubuntu: apt-get install python3-yaml).

# shellcheck source=test/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKFLOWS="$REPO/.github/workflows"
STAGE2="$WORK/stage2.json"
if ! yaml_json "$WORKFLOWS/release-stage-2_build_and_release.yml" > "$STAGE2"; then
  fail "the workflow files can be read" "python3 with PyYAML is needed (apt-get install python3-yaml)"
  finish
  exit 1
fi

# stage2 <jq filter>: the filter's output for the Stage 2 workflow
stage2() { jq -r "$1" "$STAGE2"; }

section "Stage 2: a job that waits for other jobs must say always()"
# One of the two "version" jobs is skipped on every run. GitHub skips every later job in the
# chain too, unless its "if" starts from always().
while read -r job; do
  condition=$(stage2 ".jobs[\"$job\"].if // \"\"")
  assert_contains "$condition" "always()" "job $job"
done < <(stage2 '.jobs | to_entries[] | select(.value.needs != null) | .key')

section "Stage 2: a stable release is marked as latest, after it can be installed from the APT repo"
latest_job=$(stage2 '.jobs | to_entries[] | select([(.value.steps // [])[] | .run // ""] | any(test("gh release edit .*--latest( |$)"))) | .key')
assert_eq "mark_latest" "$latest_job" "one job marks the release as latest"
assert_contains "$(stage2 '.jobs.mark_latest.if')" "inputs.release_type == 'stable'" "only for stable"
assert_contains "$(stage2 '.jobs.mark_latest.needs | join(" ")')" "validate_apt" "it waits for the check of the APT repository"
assert_contains "$(stage2 '.jobs.mark_latest.if')" "needs.validate_apt.result == 'success'" "and only runs when that check passed"

section "before publishing: the package is installed and started on every CPU type"
VALIDATE="$WORK/validate.json"
yaml_json "$WORKFLOWS/reusable-validate-homebridge.yml" > "$VALIDATE"
validate() { jq -r "$1" "$VALIDATE"; }
assert_eq '["amd64","arm64"]' "$(validate '.jobs.validate_prerelease_homebridge.strategy.matrix.include | map(.arch) | tojson')" \
  "the prerelease check runs on Intel and on 64-bit ARM runners"
# shellcheck disable=SC2016 # the text is a line of the workflow, not a variable to expand here
assert_contains "$(validate '.jobs.validate_prerelease_homebridge.steps | map(.run // "") | join("\n")')" \
  'validate-deb.sh --upgrade-from-apt "$CHANNEL" --lifecycle' "it upgrades from the published package, then removes, installs again and purges"
assert_contains "$(validate '.jobs.validate_prerelease_armhf.steps | map(.run // "") | join("\n")')" \
  "--platform linux/arm/v7" "the 32-bit ARM package is installed and started in a 32-bit container"
assert_eq "validate_prerelease" "$(stage2 '.jobs.promote_to_release.needs | map(select(. == "validate_prerelease")) | .[0]')" \
  "Stage 2 only promotes and publishes after that check"
assert_contains "$(stage2 '.jobs.promote_to_release.if')" "needs.validate_prerelease.result == 'success'" "and only when it passed"
assert_eq "null" "$(validate '.true.workflow_call.secrets | tojson')" "the check needs no secret"

finish
