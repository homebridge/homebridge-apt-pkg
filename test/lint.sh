#!/usr/bin/env bash
#
# Runs shellcheck on every shell script in the repo. Exits 1 when it finds something.
# Usage: test/lint.sh        Needs: shellcheck, git.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "This script needs bash 4 or newer (this is $BASH_VERSION)." >&2
  exit 1
fi

# every tracked or new file that is a shell script: by its name, or by its first line
mapfile -t files < <(
  git ls-files --cached --others --exclude-standard | while IFS= read -r file; do
    [ -f "$file" ] || continue
    case "$file" in
      *.sh)
        echo "$file"
        ;;
      *.md | *.json | *.yml | *.gpg | *.pkla | *.rules | LICENSE) ;;
      *)
        if head -n 1 "$file" | grep -qE '^#!.*\b(ba)?sh\b'; then echo "$file"; fi
        ;;
    esac
  done
)

echo "shellcheck: ${#files[@]} files"
shellcheck -x "${files[@]}"
