#!/usr/bin/env bash
# SessionStart hook (all sessions, not just post-compact):
# If CURRENT_TASK.md or any CURRENT_TASK_chN.md exists with active work,
# inject orientation reminder showing all active channels.
# Ensures every fresh session reads the task state before proceeding.
set -u

INPUT="$(cat)" || exit 0

# Find project directory
PROJECT_DIR=""
CWD="$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null | tr -d '\r')" || true
for dir in "$CWD" "$(pwd)" "$(git rev-parse --show-toplevel 2>/dev/null || true)"; do
  [[ -z "$dir" ]] && continue
  if [[ -f "$dir/CURRENT_TASK.md" ]]; then
    PROJECT_DIR="$dir"
    break
  fi
done

[[ -z "$PROJECT_DIR" ]] && exit 0

# --- Channel-registry pre-warm (optional; the Stop hook re-derives anyway) ---
# Listener guard: never pre-warm for listener sessions (canonical: SENTINEL_LISTENER only).
if [[ "${SENTINEL_LISTENER:-}" != "true" ]]; then
  PW_SID="$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null | tr -d '\r')"
  PW_SOURCE="$(echo "$INPUT" | jq -r '.source // ""' 2>/dev/null | tr -d '\r')"
  PW_TPATH="$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null | tr -d '\r')"
  PW_TPATH="${PW_TPATH/#\~/$HOME}"
  # Re-derive on resume/compact, or on an absent/unrecognized source (safe = resume).
  if [[ "$PW_SOURCE" != "startup" ]] && [[ "$PW_SOURCE" != "clear" ]] \
     && [[ "$PW_SID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    PW_FILE=""
    if [[ -n "$PW_TPATH" ]] && [[ -f "$PW_TPATH" ]]; then
      PW_FILE="$PW_TPATH"
    else
      shopt -s nullglob
      for g in "$HOME"/.claude/projects/*/"$PW_SID".jsonl; do PW_FILE="$g"; break; done
      shopt -u nullglob
    fi
    if [[ -n "$PW_FILE" ]] && [[ -f "$PW_FILE" ]]; then
      PW_N="$(grep -a '<command-name>/opus</command-name>' "$PW_FILE" 2>/dev/null \
        | jq -r 'select(.type=="user")
            | select((.message.content|type)=="string")
            | select(.isSidechain!=true)
            | select(.message.content|test("<command-message>opus</command-message>"))
            | (.message.content|capture("<command-args>(?<n>[0-9]+)")|.n)' 2>/dev/null \
        | tr -d '\r' | grep -E '^[0-9]+$' | tail -1)"
      if [[ -n "$PW_N" ]]; then
        PW_DIR="${PROJECT_DIR}/verification_findings/.session_channel"
        PW_TMP="${PW_DIR}/.${PW_SID}.tmp.$$"
        { mkdir -p "$PW_DIR" && printf '%s' "$PW_N" > "$PW_TMP" && mv -f "$PW_TMP" "$PW_DIR/$PW_SID"; } 2>/dev/null || true
      fi
    fi
  fi
fi

# Clean stale .active files from both pending dirs (>30 min = crashed session).
# Clean stale .md prompt files from _pending_sonnet/ only (>1 hour = listener crashed).
# NEVER clean .md files from _pending_opus/ — those are cross-session dispatches
# that persist until the target Opus session consumes them. Manual cleanup via /cleanup.
for pending_base in "_pending_sonnet" "_pending_opus"; do
  PENDING_PATH="$PROJECT_DIR/verification_findings/$pending_base"
  if [[ -d "$PENDING_PATH" ]]; then
    [[ "$pending_base" == "_pending_sonnet" ]] && find "$PENDING_PATH/" -name "*.md" -mmin +60 -delete 2>/dev/null
    find "$PENDING_PATH/" -name ".active" -mmin +30 -delete 2>/dev/null
  fi
  for chdir in "$PENDING_PATH"/ch*/; do
    if [[ -d "$chdir" ]]; then
      [[ "$pending_base" == "_pending_sonnet" ]] && find "$chdir" -name "*.md" -mmin +60 -delete 2>/dev/null
      find "$chdir" -name ".active" -mmin +30 -delete 2>/dev/null
    fi
  done
done

# Collect active channels from per-channel files
ACTIVE_CHANNELS=""
for CT_FILE in "$PROJECT_DIR"/CURRENT_TASK_ch*.md; do
  [[ ! -f "$CT_FILE" ]] && continue
  BASENAME="$(basename "$CT_FILE")"
  # Extract channel number
  CH_NUM=$(echo "$BASENAME" | grep -oE 'ch[0-9]+' | grep -oE '[0-9]+')
  # Check for active status (Phase line without complete/done/finished)
  if grep -iE '\*\*Phase:\*\*[[:space:]]*/[0-9]' "$CT_FILE" 2>/dev/null | grep -qivE '(complete|done|finished)'; then
    ACTIVE_CHANNELS="${ACTIVE_CHANNELS}  - Channel ${CH_NUM}: ${BASENAME}"$'\n'
  elif grep -qiE '\*\*Status:\*\*[[:space:]]*IN PROGRESS' "$CT_FILE" 2>/dev/null; then
    ACTIVE_CHANNELS="${ACTIVE_CHANNELS}  - Channel ${CH_NUM}: ${BASENAME}"$'\n'
  fi
done

# Check shared CT for unchanneled active work
SHARED_ACTIVE="false"
if grep -qiE '\*\*Status:\*\*[[:space:]]*IN PROGRESS' "$PROJECT_DIR/CURRENT_TASK.md" 2>/dev/null; then
  SHARED_ACTIVE="true"
fi

# Build orientation message
if [[ -n "$ACTIVE_CHANNELS" ]] || [[ "$SHARED_ACTIVE" == "true" ]]; then
  MSG="SESSION START: Active work detected. Read CURRENT_TASK.md first."
  if [[ -n "$ACTIVE_CHANNELS" ]]; then
    MSG="${MSG} Active channel files:"$'\n'"${ACTIVE_CHANNELS}"
  fi
  if [[ "$SHARED_ACTIVE" == "true" ]]; then
    MSG="${MSG} Shared CURRENT_TASK.md also has active unchanneled work."
  fi
  MSG="${MSG}Resume from where the previous session left off."
  # Escape for JSON
  MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.' | tr -d '\r')
  echo "{\"additionalContext\": ${MSG_ESCAPED}}"
fi

exit 0
