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

section "Stage 2: alpha, beta and legacy releases can never become the latest release"
promote=$(stage2 '.jobs.promote_to_release.steps | map(.run // "") | join("\n")')
assert_contains "$promote" "--prerelease=false --latest=false" "the promote step says 'not latest' in so many words"
assert_eq "mark_latest" "$latest_job" "and only the mark_latest job (stable only) sets latest"

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

section "the deb-s3 tool is installed in one place, with a checksum"
users=$(grep -l "deb-s3 " "$WORKFLOWS"/*.yml | wc -l)
shared=$(grep -l "uses: ./.github/actions/install-deb-s3" "$WORKFLOWS"/*.yml | wc -l)
assert_eq "$users" "$shared" "every workflow that runs deb-s3 uses the shared install step"
assert_eq "" "$(grep -l "gem install" "$WORKFLOWS"/*.yml)" "no workflow installs a gem by itself"
assert_contains "$(cat "$REPO/.github/actions/install-deb-s3/action.yml")" "sha256sum --check" "the shared step checks the SHA-256 of the file"

section "erasing a channel: verify first, purge the cache after"
CLEAN="$WORK/clean.json"
yaml_json "$WORKFLOWS/display_or_clean_apt.yml" > "$CLEAN"
clean() { jq -r "$1" "$CLEAN"; }
assert_eq "verify_apt" "$(clean '.jobs.display_or_clean_apt.needs')" "the delete job waits for the verify job"
assert_eq "display_or_clean_apt" "$(clean '.jobs.purge_cloudflare_cache.needs')" "the cache purge runs after the delete"
assert_contains "$(clean '.jobs.purge_cloudflare_cache.if')" "inputs.cleanup == true" "the cache is only purged when something was deleted"
assert_contains "$(clean '.jobs.display_or_clean_apt_r2.steps | map(.run // "") | join("\n")')" "purge-cf-cache.sh" "the R2 host is purged too"
assert_eq '["beta","alpha","legacy"]' "$(clean '.true.workflow_dispatch.inputs.stream.options | tojson')" "legacy can be chosen; stable can not be erased here"
assert_not_contains "$(cat "$WORKFLOWS/display_or_clean_apt.yml")" "::Group::" "log groups use the right spelling"

section "nothing runs with a stranger's pull request in a trusted context, except the labeler"
assert_eq "pr-labeler.yml" "$(grep -l 'pull_request_target' "$WORKFLOWS"/*.yml | xargs -n 1 basename | tr '\n' ' ' | sed 's/ $//')" \
  "only the labeler uses pull_request_target (the debug logger that printed every event is gone)"
assert_eq "" "$(grep -l 'toJson(github)' "$WORKFLOWS"/*.yml)" "no workflow prints the whole event to the log"

section "no value is pasted into a shell line (it goes through env)"
for file in "$WORKFLOWS"/*.yml "$REPO"/.github/actions/*/action.yml; do
  name=${file#"$REPO/.github/"}
  count=$(yaml_json "$file" | jq '[(.jobs // {action: {steps: .runs.steps}})[] | (.steps // [])[] | .run // "" | select(contains("${{"))] | length')
  assert_eq 0 "$count" "$name: no \${{ ... }} inside a run step"
done

section "rights and secrets: every job gets only what it needs"
for file in "$WORKFLOWS"/*.yml; do
  name=$(basename "$file")
  json="$WORK/$name.json"
  yaml_json "$file" > "$json"
  assert_eq "{}" "$(jq -c '.permissions // "missing"' "$json")" "$name: no rights by default (permissions: {})"
  assert_eq "" "$(jq -r '.jobs | to_entries[] | select(.value.permissions == null) | .key' "$json" | tr '\n' ' ')" \
    "$name: every job names its own rights"
  assert_eq "" "$(jq -r '.jobs | to_entries[] | select(.value.secrets == "inherit") | .key' "$json")" \
    "$name: no job is given every secret (secrets: inherit)"
  assert_eq "" "$(jq -r '[.jobs[] | (.steps // [])[] | .run // "" | select(test("\\$\\{\\{ *secrets\\."))] | length | select(. > 0)' "$json")" \
    "$name: no secret is written into a shell line (they go through env)"
done
assert_eq "publish_to_npm" "$(stage2 '.jobs | to_entries[] | select(.value.permissions["id-token"] == "write") | .key')" \
  "Stage 2: only the npm job may publish to npm (id-token: write)"
assert_eq "" "$(stage2 '.jobs | to_entries[] | select(.value.permissions.contents == "write" or .value.permissions.actions == "write") | .key')" \
  "Stage 2: no job gets write rights from the workflow's own token (releases use the GitHub App token)"
assert_not_contains "$(cat "$WORKFLOWS/release-stage-1_update_dependencies.yml")" "secrets.GH_TOKEN" \
  "Stage 1: the personal access token (GH_TOKEN) is not used any more"

finish
