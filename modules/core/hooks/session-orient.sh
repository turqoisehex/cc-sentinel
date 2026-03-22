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

# Clean stale prompt files from _pending/ (older than 1 hour)
if [[ -d "$PROJECT_DIR/verification_findings/_pending" ]]; then
  find "$PROJECT_DIR/verification_findings/_pending/" -name "*.md" -mmin +60 -delete 2>/dev/null
fi
# Also clean stale files from channeled _pending/ subdirectories
for chdir in "$PROJECT_DIR/verification_findings/_pending"/ch*/; do
  [[ -d "$chdir" ]] && find "$chdir" -name "*.md" -mmin +60 -delete 2>/dev/null
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
    ACTIVE_CHANNELS="${ACTIVE_CHANNELS}  - Channel ${CH_NUM}: ${BASENAME}\n"
  elif grep -qiE '\*\*Status:\*\*[[:space:]]*IN PROGRESS' "$CT_FILE" 2>/dev/null; then
    ACTIVE_CHANNELS="${ACTIVE_CHANNELS}  - Channel ${CH_NUM}: ${BASENAME}\n"
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
    MSG="${MSG} Active channel files:\n${ACTIVE_CHANNELS}"
  fi
  if [[ "$SHARED_ACTIVE" == "true" ]]; then
    MSG="${MSG} Shared CURRENT_TASK.md also has active unchanneled work."
  fi
  MSG="${MSG}Resume from where the previous session left off."
  # Escape for JSON
  MSG_ESCAPED=$(printf '%b' "$MSG" | jq -Rs '.' | tr -d '\r')
  echo "{\"additionalContext\": ${MSG_ESCAPED}}"
fi

exit 0
