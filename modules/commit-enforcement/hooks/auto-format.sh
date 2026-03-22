#!/usr/bin/env bash
# auto-format.sh — Detect project language and run appropriate formatter
# Hook event: PostToolUse (matched to Write/Edit/MultiEdit only via settings.json)
# Called after file edits to auto-format changed code.
# Never blocks — exits 0 even if formatter fails.

# Only act on file-writing tools
INPUT="$(cat)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null | tr -d '\r')"
[[ "$TOOL" != "Write" && "$TOOL" != "Edit" && "$TOOL" != "MultiEdit" ]] && exit 0

# Extract the file that was just written
if [[ "$TOOL" == "MultiEdit" ]]; then
  FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.edits[0]?.file_path // empty' 2>/dev/null | tr -d '\r')"
else
  FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null | tr -d '\r')"
fi
[[ -z "$FILE_PATH" ]] && exit 0

# Format only the changed file, not the whole project
if [ -f "pubspec.yaml" ]; then
  dart format "$FILE_PATH" 2>/dev/null || true
elif [ -f "package.json" ]; then
  npx prettier --write "$FILE_PATH" 2>/dev/null || true
elif [ -f "Cargo.toml" ]; then
  cargo fmt -- "$FILE_PATH" 2>/dev/null || true
elif [ -f "go.mod" ]; then
  gofmt -w "$FILE_PATH" 2>/dev/null || true
elif [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
  black "$FILE_PATH" 2>/dev/null || ruff format "$FILE_PATH" 2>/dev/null || true
fi

exit 0
