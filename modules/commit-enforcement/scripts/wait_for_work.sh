#!/usr/bin/env bash
# Blocks INDEFINITELY until a .md file appears in _pending/ (or _pending/chN/).
# Returns the filename. No timeout — exits ONLY when work arrives.
# Usage: bash scripts/wait_for_work.sh [--channel N]
CHANNEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -n "$CHANNEL" ]]; then
  PENDING_DIR="verification_findings/_pending/ch${CHANNEL}"
else
  PENDING_DIR="verification_findings/_pending"
fi

mkdir -p "$PENDING_DIR"
HEARTBEAT_FILE="$PENDING_DIR/.heartbeat"

while true; do
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$HEARTBEAT_FILE" 2>/dev/null
  for f in "$PENDING_DIR"/*.md; do
    [[ -f "$f" ]] && echo "$f" && exit 0
  done
  sleep 3
done
