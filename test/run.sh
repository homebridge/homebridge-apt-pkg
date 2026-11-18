#!/usr/bin/env bash
#
# Runs every "*.test.sh" file in this folder. Exits 1 if any check failed.
# Needs: bash 4 or newer, jq, git. No root rights, no network.
#
# Usage: test/run.sh [name ...]      for example: test/run.sh postinst start

set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "These tests need bash 4 or newer (this is $BASH_VERSION)." >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  files=()
  for name in "$@"; do files+=("$name.test.sh"); done
else
  files=(*.test.sh)
fi

failed=()
for file in "${files[@]}"; do
  printf '\n######## %s\n' "$file"
  "$BASH" "$file" || failed+=("$file")
done

echo
if [ "${#failed[@]}" -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "All test files passed."
