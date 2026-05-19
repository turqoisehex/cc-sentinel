#!/usr/bin/env bash
# cc-context-awareness — Compaction reset handler
# Clears stale flag files after /compact or auto-compaction.
# Registered as a SessionStart hook (matcher: "compact").

set -u

# Read JSON from stdin and extract session_id
SESSION_ID="$(cat | jq -r '.session_id // empty' | tr -d '\r')"

[[ -z "$SESSION_ID" ]] && exit 0

# Determine config file location (env override, then script-relative, then local CWD, then global)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${CC_CTX_CONFIG:-}" && -f "$CC_CTX_CONFIG" ]]; then
  CONFIG_FILE="$CC_CTX_CONFIG"
elif [[ -f "$_SCRIPT_DIR/config.json" ]]; then
  CONFIG_FILE="$_SCRIPT_DIR/config.json"
elif [[ -f "./.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="./.claude/cc-context-awareness/config.json"
elif [[ -f "$HOME/.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"
else
  CONFIG_FILE=""
fi

# Load flag_dir from config (2>/dev/null: malformed JSON falls through to default)
FLAG_DIR=""
if [[ -n "$CONFIG_FILE" ]]; then
  FLAG_DIR="$(jq -r '.flag_dir // "/tmp"' "$CONFIG_FILE" 2>/dev/null | tr -d '\r')" || true
fi
[[ -z "$FLAG_DIR" ]] && FLAG_DIR="/tmp"

# Remove stale flag files for this session
rm -f "${FLAG_DIR}/.cc-ctx-trigger-${SESSION_ID}"
rm -f "${FLAG_DIR}/.cc-ctx-fired-${SESSION_ID}"
