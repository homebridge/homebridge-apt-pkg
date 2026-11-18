#!/bin/bash
#
# Asks Cloudflare to drop its cached copies of the apt index files, so that users get the new
# index right after a release.
#
# Usage: ./purge-cf-cache.sh [file with the list of URLs]     (default: repo/cf-cache-purge-urls.json)
# Env:   CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, CLOUDFLARE_ACCOUNT_ID

for name in CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID CLOUDFLARE_ACCOUNT_ID; do
  if [ -z "${!name:-}" ]; then
    echo "$name missing." >&2
    exit 1
  fi
done

# test the token is working still
if ! curl -sSf -X GET "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/tokens/verify" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type:application/json" > /dev/null; then
  echo "Failed to verify token." >&2
  exit 1
fi

# get list of files to purge
# Optional first argument: a different URL list (used for the R2 hostname)
PURGE_URLS_PAYLOAD=$(cat "${1:-./repo/cf-cache-purge-urls.json}")

# purge cache
if ! curl -sSf -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$PURGE_URLS_PAYLOAD"; then
  echo "Failed to purge cache." >&2
  exit 1
fi
