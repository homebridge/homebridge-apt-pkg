#!/bin/bash
#
# Keep the R2 APT repository small (the R2 free tier is 10 GB).
# For one codename, keeps the newest KEEP versions of each package per architecture,
# removes older versions from the signed indexes, then deletes pool files that are
# no longer referenced.
#
# Usage: ./r2-apt-retention.sh <codename> <keep>
# Env:   R2_BUCKET, R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, GPG_KEY_ID
#
set -euo pipefail

CODENAME="${1:?codename required}"
KEEP="${2:?number of versions to keep required}"

DEB_S3_ARGS=(
  --bucket="$R2_BUCKET"
  --endpoint="$R2_ENDPOINT"
  --s3-region=auto
  --force-path-style
  --visibility=private
  --access-key-id="$R2_ACCESS_KEY_ID"
  --secret-access-key="$R2_SECRET_ACCESS_KEY"
  --codename="$CODENAME"
)

LIST=$(deb-s3 list "${DEB_S3_ARGS[@]}")
echo "Packages in $CODENAME:"
echo "$LIST"

# Rows are: <name> <version> <arch>
for key in $(echo "$LIST" | awk 'NF==3 {print $1 "|" $3}' | sort -u); do
  pkg="${key%|*}"
  arch="${key#*|}"
  old=$(echo "$LIST" | awk -v p="$pkg" -v a="$arch" '$1==p && $3==a {print $2}' | sort -V \
    | awk -v k="$KEEP" '{v[NR]=$0} END {for (i = 1; i <= NR - k; i++) print v[i]}')
  # Never call delete with an empty list: deb-s3 would delete ALL versions.
  if [ -n "$old" ]; then
    echo "Removing $pkg ($arch): $(echo $old)"
    # shellcheck disable=SC2086 # versions are passed as separate arguments
    deb-s3 delete "$pkg" "${DEB_S3_ARGS[@]}" --arch="$arch" --sign="$GPG_KEY_ID" --versions $old
  fi
done

deb-s3 clean "${DEB_S3_ARGS[@]}"
