#!/usr/bin/env bash
set -u
INPUT="$(cat)"
SOURCE="$(echo "$INPUT" | jq -r '.source // ""' | tr -d '\r')"

# Belt and suspenders: matcher filters for "compact", script also checks.
[[ "$SOURCE" != "compact" ]] && exit 0

# Resolve project directory. CLAUDE_PROJECT_DIR reflects CC's session CWD,
# which may differ from the actual project (e.g., CC launched from ~/).
# Try candidates in order; use the first that contains project files.
resolve_project_dir() {
  local candidates=("${CLAUDE_PROJECT_DIR:-}" "$(pwd)")
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)" && candidates+=("$git_root")
  for dir in "${candidates[@]}"; do
    [[ -z "$dir" ]] && continue
    if [[ -f "$dir/CURRENT_TASK.md" ]] || [[ -f "$dir/CLAUDE.md" ]]; then
      echo "$dir"
      return
    fi
  done
  echo "${CLAUDE_PROJECT_DIR:-$(pwd)}"
}
PROJECT_DIR="$(resolve_project_dir)"

# Read first 30 lines of CLAUDE.md (core rules)
CLAUDE_CONTENT=""
if [[ -f "${PROJECT_DIR}/CLAUDE.md" ]]; then
  CLAUDE_CONTENT=$(head -30 "${PROJECT_DIR}/CLAUDE.md" 2>/dev/null || echo "[could not read]")
fi

# Read shared CURRENT_TASK.md (sprint index) + all per-channel files
TASK_CONTENT=""
OLDEST_CT_FILE="${PROJECT_DIR}/CURRENT_TASK.md"
HAS_TASK="false"
if [[ -f "${PROJECT_DIR}/CURRENT_TASK.md" ]]; then
  HAS_TASK="true"
  TASK_CONTENT="--- CURRENT_TASK.md (shared index, full) ---"$'\n'
  TASK_CONTENT+=$(cat "${PROJECT_DIR}/CURRENT_TASK.md" 2>/dev/null || echo "[could not read]")
fi
# Read per-channel files
for CT_FILE in "${PROJECT_DIR}"/CURRENT_TASK_ch*.md; do
  [[ ! -f "$CT_FILE" ]] && continue
  HAS_TASK="true"
  BASENAME="$(basename "$CT_FILE")"
  TASK_CONTENT+=$'\n\n'"--- ${BASENAME} (full) ---"$'\n'
  TASK_CONTENT+=$(cat "$CT_FILE" 2>/dev/null || echo "[could not read]")
  # Track oldest CT file for agent output comparison
  if [[ -f "$CT_FILE" && ( ! -f "$OLDEST_CT_FILE" || "$CT_FILE" -ot "$OLDEST_CT_FILE" ) ]]; then
    OLDEST_CT_FILE="$CT_FILE"
  fi
done

# Build message with injected file contents
NL=$'\n'
if [[ "$HAS_TASK" == "true" ]]; then
  # Check for recently-modified agent output files (newer than oldest CT file)
  RECENT_AGENT_FILES=""
  if [[ -d "${PROJECT_DIR}/verification_findings" ]] && [[ -f "$OLDEST_CT_FILE" ]]; then
    RECENT_AGENT_FILES=$(find "${PROJECT_DIR}/verification_findings" -name "*.md" -newer "$OLDEST_CT_FILE" 2>/dev/null | head -10)
  fi
  AGENT_NOTE=""
  if [[ -n "$RECENT_AGENT_FILES" ]]; then
    AGENT_NOTE="${NL}${NL}--- AGENT OUTPUT FILES (newer than CT files — may be from pre-compaction agents) ---${NL}${RECENT_AGENT_FILES}${NL}Read these files — agent IDs do not survive compaction but their output files do."
  fi
  MSG="POST-COMPACTION RE-ORIENTATION. You have been compacted. Your channel CT file (CURRENT_TASK_ch[N].md, shown below) is your continuity — resume from where it indicates. The shared CURRENT_TASK.md has the Active Channels table. Do NOT proceed from memory. Check your channel CT file for any background agent output file paths listed before compaction.${NL}${NL}--- CLAUDE.md (first 30 lines) ---${NL}${CLAUDE_CONTENT}${NL}${NL}${TASK_CONTENT}${AGENT_NOTE}"
elif [[ -n "$CLAUDE_CONTENT" ]]; then
  MSG="POST-COMPACTION RE-ORIENTATION. You have been compacted. Read the project CLAUDE.md fully, then MEMORY.md if it exists. Look for state files (HANDOFF.md, STATE.md, CURRENT_TASK.md, CURRENT_TASK_ch[N].md) in the project root. Re-orient from files, not memory.${NL}${NL}--- CLAUDE.md (first 30 lines) ---${NL}${CLAUDE_CONTENT}"
else
  MSG="POST-COMPACTION RE-ORIENTATION. You have been compacted. Look for state files in the project root before continuing. Re-orient from files, not memory."
fi

# Escape for JSON using jq
MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.' | tr -d '\r')

echo "{\"additionalContext\": ${MSG_ESCAPED}}"
