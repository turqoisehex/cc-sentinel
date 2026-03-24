#!/usr/bin/env bash
set -u
# Blocks INDEFINITELY until a .md file appears in the model-specific pending dir.
# Returns the filename on stdout (oldest-first by mtime). Writes .active signal
# before returning so observers know what's being processed.
#
# Heartbeat continues in background after work is found so channel_commit.sh
# never sees a stale heartbeat during processing.
#
# The background heartbeat self-terminates when the parent shell exits via
# PPID polling.
#
# Usage: bash scripts/wait_for_work.sh --model opus|sonnet [--channel N]
CHANNEL=""
MODEL="sonnet"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --model)   MODEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Validate model
case "$MODEL" in
  opus|sonnet) ;;
  *) echo "ERROR: --model must be 'opus' or 'sonnet', got '$MODEL'" >&2; exit 1 ;;
esac

if [[ -n "$CHANNEL" ]]; then
  PENDING_DIR="verification_findings/_pending_${MODEL}/ch${CHANNEL}"
else
  PENDING_DIR="verification_findings/_pending_${MODEL}"
fi

mkdir -p "$PENDING_DIR"
HEARTBEAT_FILE="$PENDING_DIR/.heartbeat"
HEARTBEAT_PID_FILE="$PENDING_DIR/.heartbeat_pid"
# PPID = the shell that invoked this script (listener session).
# When the session exits, this PID dies, and the heartbeat self-terminates.
LISTENER_PID=$PPID

# Kill any prior stale heartbeat process
if [[ -f "$HEARTBEAT_PID_FILE" ]]; then
  OLD_PID=$(cat "$HEARTBEAT_PID_FILE" 2>/dev/null)
  kill "$OLD_PID" 2>/dev/null || true
  rm -f "$HEARTBEAT_PID_FILE"
fi

# Start background heartbeat — survives after this script exits.
# Self-terminates when parent shell is gone.
_heartbeat_loop() {
  while true; do
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

# Poll for work — oldest-first by mtime
while true; do
  OLDEST=$(ls -tr "$PENDING_DIR"/*.md 2>/dev/null | head -1)
  if [[ -n "$OLDEST" ]] && [[ -f "$OLDEST" ]]; then
    # Write .active signal before returning
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") processing $(basename "$OLDEST")" > "$PENDING_DIR/.active"
    echo "$OLDEST"
    exit 0
  fi
  sleep 3
done
