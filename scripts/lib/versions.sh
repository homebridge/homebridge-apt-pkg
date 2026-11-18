#!/bin/bash
#
# Small version helpers, shared by build.sh and the scripts in this folder.
# Source this file; it runs nothing by itself.

# version_lt <a> <b>: true when version a is lower than version b.
# A pre-release is lower than its release: 2.5.1-beta.5 is lower than 2.5.1.
# ("~" sorts before everything in "sort -V", the same way Debian orders versions.)
version_lt() {
  local a="${1/-/\~}" b="${2/-/\~}"
  [ "$a" != "$b" ] && [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n 1)" = "$a" ]
}

# stream_tag_pattern <stream>: a regular expression that matches the release tags of one stream.
#   stable -> v2.0.26          the others -> v2.0.27-beta.20261118
stream_tag_pattern() {
  case "$1" in
    stable) printf '%s\n' '^v[0-9]+\.[0-9]+\.[0-9]+$' ;;
    beta | alpha | legacy) printf '^v[0-9]+\\.[0-9]+\\.[0-9]+-%s\\.[0-9.]+$\n' "$1" ;;
    *) return 1 ;;
  esac
}

# latest_stream_tag <stream>: the newest release tag of that stream in this git repo, or nothing.
latest_stream_tag() {
  local pattern
  pattern=$(stream_tag_pattern "$1") || return 1
  git tag -l | grep -E -- "$pattern" | sort -V | tail -n 1
}
