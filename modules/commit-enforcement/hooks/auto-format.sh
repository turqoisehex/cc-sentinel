#!/usr/bin/env bash
# auto-format.sh — Detect project language and run appropriate formatter
# Hook event: PostToolUse (matched to Write/Edit/MultiEdit only via settings.json)
# Called after file edits to auto-format changed code.
# Never blocks — exits 0 even if formatter fails.
set -u

# Only act on file-writing tools
INPUT="$(cat)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null | tr -d '\r')"
[[ "$TOOL" != "Write" && "$TOOL" != "Edit" && "$TOOL" != "MultiEdit" ]] && exit 0

# Extract the file(s) that were just written
FILE_PATHS=()
if [[ "$TOOL" == "MultiEdit" ]]; then
  while IFS= read -r fp; do
    [[ -n "$fp" ]] && FILE_PATHS+=("$fp")
  done < <(echo "$INPUT" | jq -r '.tool_input.edits[]?.file_path // empty' 2>/dev/null | tr -d '\r')
else
  fp="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null | tr -d '\r')"
  [[ -n "$fp" ]] && FILE_PATHS+=("$fp")
fi
[[ ${#FILE_PATHS[@]} -eq 0 ]] && exit 0

# Format each changed file
format_file() {
  local f="$1"
  if [ -f "pubspec.yaml" ]; then
    dart format "$f" 2>/dev/null || true
  elif [ -f "package.json" ]; then
    npx prettier --write "$f" 2>/dev/null || true
  elif [ -f "Cargo.toml" ]; then
    cargo fmt -- "$f" 2>/dev/null || true
  elif [ -f "go.mod" ]; then
    gofmt -w "$f" 2>/dev/null || true
  elif [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
    black "$f" 2>/dev/null || ruff format "$f" 2>/dev/null || true
  fi
}

for FILE_PATH in "${FILE_PATHS[@]}"; do
  format_file "$FILE_PATH"
done

exit 0
