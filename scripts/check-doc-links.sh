#!/usr/bin/env bash
# Verify every relative markdown link in docs/ and plans/ points at a file that exists.
# Cross-references between plan phases and safety docs are load-bearing here: a broken
# link means an engineer follows a safety reference into nothing.
set -uo pipefail

fail=0

while IFS= read -r src; do
  dir=$(dirname "$src")
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    case "$link" in
      http://* | https://* | mailto:* | \#*) continue ;;
    esac
    target="${link%%#*}"
    [ -z "$target" ] && continue
    if [ ! -e "$dir/$target" ]; then
      echo "BROKEN: $src -> $link"
      fail=1
    fi
  done < <(grep -oE '\]\([^)]+\)' "$src" | sed -E 's/^\]\((.*)\)$/\1/')
done < <(find docs plans -name '*.md' 2>/dev/null)

if [ "$fail" -eq 0 ]; then
  echo "All relative doc links resolve."
fi

exit "$fail"
