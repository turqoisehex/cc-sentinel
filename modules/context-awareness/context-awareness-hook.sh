#!/usr/bin/env bash
# cc-context-awareness — Hook actuator (optimized)
# Reads trigger flag file and outputs additionalContext for Claude Code.
# Designed to be fast in the common case (no trigger file present).

set -u

# Save full stdin for session_id and tool_name access
SAVED_INPUT="$(cat)"
SESSION_ID="$(echo "$SAVED_INPUT" | jq -r '.session_id // ""' | tr -d '\r')" || true

[[ -z "$SESSION_ID" ]] && exit 0

# Determine config file location (local takes precedence over global)
if [[ -f "./.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="./.claude/cc-context-awareness/config.json"
elif [[ -f "$HOME/.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"
else
  CONFIG_FILE=""
fi

# Load config values
if [[ -n "$CONFIG_FILE" ]]; then
  read -r FLAG_DIR HOOK_EVENT <<< "$(jq -r '[.flag_dir // "/tmp", .hook_event // "PreToolUse"] | @tsv' "$CONFIG_FILE" | tr -d '\r')"
else
  FLAG_DIR="/tmp"
  HOOK_EVENT="PreToolUse"
fi

TRIGGER_FILE="${FLAG_DIR}/.cc-ctx-trigger-${SESSION_ID}"

# Fast path: no trigger file, exit immediately
[[ ! -f "$TRIGGER_FILE" ]] && exit 0

# Trigger file exists — read message and level
MESSAGE="$(jq -r '.message // empty' "$TRIGGER_FILE" | tr -d '\r')"
LEVEL="$(jq -r '.level // ""' "$TRIGGER_FILE" | tr -d '\r')"

if [[ -z "$MESSAGE" ]]; then
  rm -f "$TRIGGER_FILE"
  exit 0
fi

# --- All levels: inject message as additionalContext ---
jq -n --arg msg "$MESSAGE" --arg evt "$HOOK_EVENT" '{
  "hookSpecificOutput": {
    "hookEventName": $evt,
    "additionalContext": $msg
  }
}'

# Remove trigger flag so it doesn't fire again
rm -f "$TRIGGER_FILE"
