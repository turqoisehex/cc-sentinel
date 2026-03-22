#!/usr/bin/env bash
set -u
# Blocks INDEFINITELY until a .md file appears in _pending/ (or _pending/chN/).
# Returns the filename on stdout. Heartbeat continues in background after work is
# found so channel_commit.sh never sees a stale heartbeat during Sonnet processing.
#
# The background heartbeat self-terminates when the parent shell (Sonnet listener
# session) exits, via PPID polling. Sonnet can also kill it explicitly via the
# .heartbeat_pid file.
#
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
HEARTBEAT_PID_FILE="$PENDING_DIR/.heartbeat_pid"
# PPID = the shell that invoked this script (Sonnet's bash session).
# When Sonnet exits, this PID dies, and the heartbeat self-terminates.
LISTENER_PID=$PPID

# Kill any prior stale heartbeat process
if [[ -f "$HEARTBEAT_PID_FILE" ]]; then
  OLD_PID=$(cat "$HEARTBEAT_PID_FILE" 2>/dev/null)
  kill "$OLD_PID" 2>/dev/null || true
  rm -f "$HEARTBEAT_PID_FILE"
fi

# Start background heartbeat — survives after this script exits.
# Self-terminates when parent shell (Sonnet session) is gone.
_heartbeat_loop() {
  while true; do
    # Check if parent process is still alive (Sonnet session)
    if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
      rm -f "$HEARTBEAT_FILE" "$HEARTBEAT_PID_FILE"
      exit 0
    fi
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$HEARTBEAT_FILE" 2>/dev/null
    sleep 3
  done
}
_heartbeat_loop &
echo $! > "$HEARTBEAT_PID_FILE"

# Poll for work
while true; do
  for f in "$PENDING_DIR"/*.md; do
    [[ -f "$f" ]] && echo "$f" && exit 0
  done
  sleep 3
done
