#!/bin/bash
#
# Removes old package versions from the S3 apt repository.
# Every package file with a version LOWER than MIN_VERSION is deleted from the pool of one channel.
#
# Env (all required):
#   MIN_VERSION    the oldest version to keep, for example 2.0.20
#   RELEASE_TYPE   the channel: stable, beta, alpha, legacy or test
#   S3_BUCKET      for example repo.homebridge.io
#   S3_REGION      for example us-west-2
# Env (optional):
#   DRY_RUN=1      only print what would be deleted
#
# After a real run the apt index must be rebuilt ("deb-s3 verify --fix-manifests", see purge.yml).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=scripts/lib/versions.sh
. scripts/lib/versions.sh

: "${MIN_VERSION:?MIN_VERSION is required, for example 2.0.20}"
: "${RELEASE_TYPE:?RELEASE_TYPE is required: stable, beta, alpha, legacy or test}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${S3_REGION:?S3_REGION is required}"
DRY_RUN="${DRY_RUN:-0}"

if [[ ! "$MIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "MIN_VERSION must look like 2.0.20 (got: $MIN_VERSION)" >&2
  exit 2
fi
case "$RELEASE_TYPE" in
  stable | beta | alpha | legacy | test) ;;
  *)
    echo "Unknown RELEASE_TYPE: $RELEASE_TYPE" >&2
    exit 2
    ;;
esac

# file names look like homebridge_v2.0.26_amd64.deb (older ones have no "v")
keys=$(aws s3api list-objects --region "$S3_REGION" --bucket "$S3_BUCKET" --prefix "pool/$RELEASE_TYPE/h/ho/" --output json \
  | jq -r '.Contents // [] | .[].Key')

to_delete=()
kept=0
while IFS= read -r key; do
  [ -n "$key" ] || continue
  file="${key##*/}"
  version="${file#*_}"
  version="${version%_*}"
  version="${version#v}"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "Skipping $key (no version found in the name)"
    continue
  fi
  # compare the x.y.z part only: 2.0.27.beta.20261118 counts as 2.0.27
  if version_lt "${BASH_REMATCH[0]}" "$MIN_VERSION"; then
    to_delete+=("$key")
  else
    kept=$((kept + 1))
  fi
done <<< "$keys"

if [ "${#to_delete[@]}" -eq 0 ]; then
  echo "Nothing in pool/$RELEASE_TYPE is older than $MIN_VERSION."
  exit 0
fi
if [ "$kept" -eq 0 ]; then
  echo "Stopped: every package in pool/$RELEASE_TYPE is older than $MIN_VERSION, so this would delete all of them." >&2
  exit 1
fi

for key in "${to_delete[@]}"; do
  if [ "$DRY_RUN" = "1" ]; then
    echo "Would remove s3://$S3_BUCKET/$key"
  else
    echo "Removing s3://$S3_BUCKET/$key"
    aws s3api delete-object --region "$S3_REGION" --bucket "$S3_BUCKET" --key "$key" --output json
  fi
done
echo "${#to_delete[@]} file(s) $([ "$DRY_RUN" = "1" ] && echo "would be removed" || echo "removed"), $kept kept."
