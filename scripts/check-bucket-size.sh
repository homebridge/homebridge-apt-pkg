#!/bin/bash
#
# Reads the size of the R2 bucket and stops when it is close to the free limit (10 GB).
#
# Env: R2_BUCKET, R2_ENDPOINT, and the aws command's own credentials.
#      GITHUB_ENV (optional): gets "R2_SIZE_GB=<size>" for the job summary.
#
# Exit code 1 when the bucket is over 9.5 GB, AND when the size can not be read. (The old
# workflow step went on with an empty size and reported "0.00 GB".)

set -euo pipefail

: "${R2_BUCKET:?R2_BUCKET is required}"
: "${R2_ENDPOINT:?R2_ENDPOINT is required}"

if ! listing=$(aws s3 ls "s3://$R2_BUCKET" --recursive --summarize --endpoint-url "$R2_ENDPOINT"); then
  echo "::error::Could not list the R2 bucket, so its size is unknown."
  exit 1
fi
total=$(awk '/Total Size/ {print $3}' <<< "$listing")
if [[ ! "$total" =~ ^[0-9]+$ ]]; then
  echo "::error::Could not read the size of the R2 bucket from the listing."
  exit 1
fi

gb=$(awk -v b="$total" 'BEGIN {printf "%.2f", b / 1024^3}')
echo "R2 bucket size: ${gb} GB"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "R2_SIZE_GB=$gb" >> "$GITHUB_ENV"
fi

if [ "$total" -gt 10200547328 ]; then # 9.5 GB
  echo "::error::R2 bucket is ${gb} GB, close to the 10 GB free tier. Lower KEEP_VERSIONS."
  exit 1
elif [ "$total" -gt 8589934592 ]; then # 8 GB
  echo "::warning::R2 bucket is ${gb} GB (free tier is 10 GB)."
fi
