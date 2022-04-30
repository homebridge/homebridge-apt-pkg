#!/bin/bash

# CLOUDFLARE_API_TOKEN=
# CLOUDFLARE_ZONE_ID=

if [ -z $CLOUDFLARE_API_TOKEN ]; then
  echo >&2 echo "CLOUDFLARE_API_TOKEN missing."
  exit 1
fi

if [ -z $CLOUDFLARE_ZONE_ID ]; then
  echo >&2 echo "CLOUDFLARE_ZONE_ID missing."
  exit 1
fi

# test the token is working still
curl -sSf -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type:application/json" > /dev/null

if [ "$?" != "0" ]; then
  >&2 echo "Failed to verify token."
  exit 1
fi

# get list of files to purge
PURGE_URLS_PAYLOAD=$(cat ./repo/cf-cache-purge-urls.json)

# purge cache
curl -sSf -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$PURGE_URLS_PAYLOAD"

if [ "$?" != "0" ]; then
  >&2 echo "Failed to purge cache."
  exit 1
fi
