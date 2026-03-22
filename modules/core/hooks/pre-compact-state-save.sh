#!/usr/bin/env bash
set -u

INPUT="$(cat)"
TRIGGER="$(echo "$INPUT" | jq -r '.trigger // "unknown"' | tr -d '\r')"

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

# Read shared CURRENT_TASK.md + all per-channel files
HAS_TASK="false"
TASK_CONTENT=""
if [[ -f "${PROJECT_DIR}/CURRENT_TASK.md" ]]; then
  HAS_TASK="true"
  TASK_CONTENT="--- CURRENT_TASK.md (shared index, first 50 lines) ---"$'\n'
  TASK_CONTENT+=$(head -50 "${PROJECT_DIR}/CURRENT_TASK.md" 2>/dev/null || echo "[could not read]")
fi
# Read per-channel files
for CT_FILE in "${PROJECT_DIR}"/CURRENT_TASK_ch*.md; do
  [[ ! -f "$CT_FILE" ]] && continue
  HAS_TASK="true"
  BASENAME="$(basename "$CT_FILE")"
  TASK_CONTENT+=$'\n\n'"--- ${BASENAME} (first 50 lines) ---"$'\n'
  TASK_CONTENT+=$(head -50 "$CT_FILE" 2>/dev/null || echo "[could not read]")
done

NL=$'\n'
if [[ "$HAS_TASK" == "true" ]]; then
  MSG="COMPACTION IMMINENT (trigger: ${TRIGGER}). MANDATORY: Update your state file (CURRENT_TASK_chN.md if channeled, or CURRENT_TASK.md if unchanneled) NOW with: (1) Which plan step you just completed, (2) Which step is next, (3) Any uncommitted changes — describe them precisely, (4) Key decisions made this session, (5) Anything a fresh session needs that is not already in the file, (6) AGENT IDS AND OUTPUT FILES — list every background agent still running, its purpose, and the file path it is writing to (agent IDs do NOT survive compaction — the output file paths are the only way the next session can find results). Then commit via channel_commit.sh (or git commit if commit-enforcement is not installed). A fresh session will read ONLY CLAUDE.md and the state files below — everything else is lost.${NL}${NL}Current state files for reference (update yours, do not start from scratch):${NL}${TASK_CONTENT}"
else
  MSG="COMPACTION IMMINENT (trigger: ${TRIGGER}). Write current work state to CURRENT_TASK.md (create it from the template if it does not exist). Include: what was done, what remains, decisions made, current approach, uncommitted changes. A fresh session will have ZERO context from this session."
fi

# Escape for JSON using jq
MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.' | tr -d '\r')

echo "{\"additionalContext\": ${MSG_ESCAPED}}"
