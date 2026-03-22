#!/usr/bin/env bash
# auto-format.sh — Detect project language and run appropriate formatter
# Hook event: PostToolUse
# Called after file edits to auto-format changed code.
# Never blocks — exits 0 even if formatter fails.

if [ -f "pubspec.yaml" ]; then
  dart format . 2>/dev/null
elif [ -f "package.json" ]; then
  npx prettier --write . 2>/dev/null || true
elif [ -f "Cargo.toml" ]; then
  cargo fmt 2>/dev/null || true
elif [ -f "go.mod" ]; then
  gofmt -w . 2>/dev/null || true
elif [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
  black . 2>/dev/null || ruff format . 2>/dev/null || true
fi

exit 0
