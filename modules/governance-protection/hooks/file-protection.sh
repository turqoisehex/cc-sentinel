#!/usr/bin/env bash
set -u
INPUT="$(cat)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // ""' | tr -d '\r')"

# Only check file-writing tools: Write, Edit, MultiEdit
[[ "$TOOL" != "Write" && "$TOOL" != "Edit" && "$TOOL" != "MultiEdit" ]] && exit 0

# Extract file path(s) — MultiEdit may have an array of edits
if [[ "$TOOL" == "MultiEdit" ]]; then
  FILE_PATHS="$(echo "$INPUT" | jq -r '.tool_input.edits[]?.file_path // empty' | tr -d '\r')"
else
  FILE_PATHS="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' | tr -d '\r')"
fi
[[ -z "$FILE_PATHS" ]] && exit 0

# Load protected files list — check project-local first, then global
# Project-local: <project_root>/protected-files.txt or <project_root>/.claude/protected-files.txt
# Global fallback: ~/.claude/protected-files.txt
PROTECTED_FILES_LIST=""

# Derive project directory from the file being edited.
find_project_dir() {
  local file_path="$1"
  local dir
  dir="$(dirname "$file_path")"
  local prev=""
  while [[ "$dir" != "$prev" ]]; do
    if [[ -d "$dir/.git" ]] || [[ -f "$dir/CURRENT_TASK.md" ]]; then
      echo "$dir"
      return
    fi
    prev="$dir"
    dir="$(dirname "$dir")"
  done
  echo "${CLAUDE_PROJECT_DIR:-$(pwd)}"
}

# Get first file path for project dir derivation
FIRST_FILE="$(echo "$FILE_PATHS" | head -1)"
PROJECT_DIR="$(find_project_dir "$FIRST_FILE")"

# Search for protected-files.txt
for candidate in \
  "${PROJECT_DIR}/protected-files.txt" \
  "${PROJECT_DIR}/.claude/protected-files.txt" \
  "${HOME}/.claude/protected-files.txt"; do
  if [[ -f "$candidate" ]]; then
    PROTECTED_FILES_LIST="$candidate"
    break
  fi
done

# Check if current task authorizes governance edits
GOVERNANCE_AUTHORIZED="false"
for CHECK_DIR in "$PROJECT_DIR" "${CLAUDE_PROJECT_DIR:-}"; do
  [[ -z "$CHECK_DIR" ]] && continue
  # Check shared index
  if [[ -f "${CHECK_DIR}/CURRENT_TASK.md" ]]; then
    if tr -d '\r' < "${CHECK_DIR}/CURRENT_TASK.md" | grep -qx "GOVERNANCE-EDIT-AUTHORIZED" 2>/dev/null; then
      GOVERNANCE_AUTHORIZED="true"
      break
    fi
  fi
  # Check per-channel files
  for CT_FILE in "${CHECK_DIR}"/CURRENT_TASK_ch*.md; do
    [[ ! -f "$CT_FILE" ]] && continue
    if tr -d '\r' < "$CT_FILE" | grep -qx "GOVERNANCE-EDIT-AUTHORIZED" 2>/dev/null; then
      GOVERNANCE_AUTHORIZED="true"
      break 2
    fi
  done
done

[[ "$GOVERNANCE_AUTHORIZED" == "true" ]] && exit 0

# Check each file path against the protected list (if protected-files.txt exists)
# Pre-load into array to avoid re-reading file per FILE_PATH
if [[ -n "$PROTECTED_FILES_LIST" ]]; then
PROTECTED_ENTRIES=()
while IFS= read -r LINE || [[ -n "$LINE" ]]; do
  LINE=$(echo "$LINE" | tr -d '\r' | xargs)
  [[ -z "$LINE" || "$LINE" == \#* ]] && continue
  PROTECTED_ENTRIES+=("$LINE")
done < "$PROTECTED_FILES_LIST"

PROTECTED_DENY=$(echo "$FILE_PATHS" | while IFS= read -r FILE_PATH; do
  [[ -z "$FILE_PATH" ]] && continue
  FILENAME="$(basename "$FILE_PATH")"

  for PROTECTED in "${PROTECTED_ENTRIES[@]}"; do
    if [[ "$FILENAME" == "$PROTECTED" ]]; then
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","reason":"PROTECTED: '"$FILENAME"' is a governance file. To edit: add GOVERNANCE-EDIT-AUTHORIZED as its own standalone line in your channel CT file (CURRENT_TASK_chN.md) or CURRENT_TASK.md if unchanneled. It must be the entire line by itself. Then retry the edit."}}'
      exit 0
    fi
  done
done)
if [[ -n "$PROTECTED_DENY" ]]; then
  echo "$PROTECTED_DENY"
  exit 0
fi
fi

# --- Second pass: sensitive file patterns ---
SENSITIVE_LIST=""
for candidate in \
  "${PROJECT_DIR}/sensitive-patterns.txt" \
  "${PROJECT_DIR}/.claude/sensitive-patterns.txt" \
  "${HOME}/.claude/sensitive-patterns.txt"; do
  if [[ -f "$candidate" ]]; then
    SENSITIVE_LIST="$candidate"
    break
  fi
done

if [[ -n "$SENSITIVE_LIST" ]]; then
  # Pre-load into deny and negation arrays to avoid re-reading file per FILE_PATH
  DENY_PATTERNS=()
  NEGATION_PATTERNS=()
  while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    LINE=$(echo "$LINE" | tr -d '\r' | xargs)
    [[ -z "$LINE" || "$LINE" == \#* ]] && continue
    if [[ "$LINE" == !* ]]; then
      NEGATION_PATTERNS+=("${LINE#!}")
    else
      DENY_PATTERNS+=("$LINE")
    fi
  done < "$SENSITIVE_LIST"

  echo "$FILE_PATHS" | while IFS= read -r FILE_PATH; do
    [[ -z "$FILE_PATH" ]] && continue

    DENIED="false"
    for PATTERN in "${DENY_PATTERNS[@]}"; do
      # shellcheck disable=SC2053
      if [[ "$FILE_PATH" == $PATTERN ]]; then
        DENIED="true"
        break
      fi
    done

    if [[ "$DENIED" == "true" ]]; then
      for NEG_PATTERN in "${NEGATION_PATTERNS[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$FILE_PATH" == $NEG_PATTERN ]]; then
          DENIED="false"
          break
        fi
      done
    fi

    if [[ "$DENIED" == "true" ]]; then
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","reason":"SENSITIVE: This file matches a credential/secret pattern and should not be read or modified by Claude."}}'
      exit 0
    fi
  done
fi
