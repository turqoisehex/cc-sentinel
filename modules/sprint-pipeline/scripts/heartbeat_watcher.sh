#!/usr/bin/env bash
# Duo mode only. Not used in default (native subagent) mode.
# heartbeat_watcher.sh — Watch for Sonnet listener heartbeat on a channel.
# Usage: bash heartbeat_watcher.sh --channel N [--timeout SECONDS]
# Checks every 5 seconds for _pending_sonnet/chN/.heartbeat.
# Exits 0 if found, warns on timeout. Designed to run in background.
set -u

CHANNEL=""
TIMEOUT=300  # 5 minutes default

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$CHANNEL" ]] && { echo "Usage: heartbeat_watcher.sh --channel N" >&2; exit 1; }

HB="verification_findings/_pending_sonnet/ch${CHANNEL}/.heartbeat"
INTERVAL=5
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  if [[ -f "$HB" ]]; then
    echo "Sonnet listener detected on ch${CHANNEL}"
    exit 0
  fi
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "WARNING: No Sonnet listener after $((TIMEOUT / 60)) minutes on ch${CHANNEL}"
exit 0
