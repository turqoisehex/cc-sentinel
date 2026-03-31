#!/usr/bin/env bash
# Detects when code is replaced with comment placeholders
# Advisory only — never blocks, returns additionalContext warning
set -u

INPUT="$(cat)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // ""' | tr -d '\r')"

# Only check Edit and MultiEdit
[[ "$TOOL" != "Edit" && "$TOOL" != "MultiEdit" ]] && exit 0

# Extract file path
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' | tr -d '\r')"

# Skip markdown/docs
case "$FILE_PATH" in
  *.md|*.txt|*.rst) exit 0 ;;
esac

# Count comment lines in a string
count_comment_lines() {
  local text="$1"
  echo "$text" | grep -cE '^\s*(//|#|/\*|\*/|\*\s|<!--|-->|--\s)' 2>/dev/null || true
}

count_total_lines() {
  local text="$1"
  echo "$text" | grep -c '.' 2>/dev/null || true
}

check_replacement() {
  local old_str="$1" new_str="$2"
  [[ -z "$old_str" || -z "$new_str" ]] && return 1

  local old_total old_comments new_total new_comments
  old_total=$(count_total_lines "$old_str")
  old_comments=$(count_comment_lines "$old_str")
  new_total=$(count_total_lines "$new_str")
  new_comments=$(count_comment_lines "$new_str")

  # Skip if old was already primarily comments (>50%)
  [[ "$old_total" -gt 0 ]] && [[ $((old_comments * 100 / old_total)) -gt 50 ]] && return 1

  # Flag if old had code AND new is >50% comments
  [[ "$new_total" -gt 0 ]] && [[ $((new_comments * 100 / new_total)) -gt 50 ]] && return 0

  return 1
}

if [[ "$TOOL" == "Edit" ]]; then
  OLD=$(echo "$INPUT" | jq -r '.tool_input.old_string // ""' | tr -d '\r')
  NEW=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""' | tr -d '\r')
  if check_replacement "$OLD" "$NEW"; then
    MSG="You appear to have replaced code with a comment placeholder. This is almost never correct. Restore the original code and integrate your changes properly."
    MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.' | tr -d '\r')
    echo "{\"additionalContext\": ${MSG_ESCAPED}}"
    exit 0
  fi
elif [[ "$TOOL" == "MultiEdit" ]]; then
  EDIT_COUNT=$(echo "$INPUT" | jq '.tool_input.edits | length' 2>/dev/null || echo "0")
  for (( i=0; i<EDIT_COUNT; i++ )); do
    # Check per-edit file path for markdown/docs skip
    EDIT_PATH=$(echo "$INPUT" | jq -r ".tool_input.edits[$i].file_path // \"\"" | tr -d '\r')
    case "$EDIT_PATH" in
      *.md|*.txt|*.rst) continue ;;
    esac
    OLD=$(echo "$INPUT" | jq -r ".tool_input.edits[$i].old_string // \"\"" | tr -d '\r')
    NEW=$(echo "$INPUT" | jq -r ".tool_input.edits[$i].new_string // \"\"" | tr -d '\r')
    if check_replacement "$OLD" "$NEW"; then
      MSG="You appear to have replaced code with a comment placeholder in edit $((i+1)) of a MultiEdit. This is almost never correct. Restore the original code and integrate your changes properly."
      MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.' | tr -d '\r')
      echo "{\"additionalContext\": ${MSG_ESCAPED}}"
      # Only one warning per MultiEdit invocation (intentional — avoids flooding)
      exit 0
    fi
  done
fi

exit 0
