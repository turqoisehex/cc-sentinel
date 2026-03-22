#!/usr/bin/env bash
# Blocks until ALL specified files exist. Used by Opus to wait for Sonnet results.
# Usage: bash scripts/wait_for_results.sh [--timeout N] file1.md [file2.md ...]
TIMEOUT=3600
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

[[ ${#FILES[@]} -eq 0 ]] && echo "No files specified" >&2 && exit 1

ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  ALL_PRESENT=true
  for f in "${FILES[@]}"; do
    [[ ! -f "$f" ]] && ALL_PRESENT=false && break
  done
  $ALL_PRESENT && exit 0
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

echo "" >&2
echo "================================================================" >&2
echo "  TIMEOUT: Waited ${TIMEOUT}s for Sonnet verification results." >&2
echo "  Missing files:" >&2
for f in "${FILES[@]}"; do
  [[ ! -f "$f" ]] && echo "    - $f" >&2
done
echo "================================================================" >&2
exit 1
