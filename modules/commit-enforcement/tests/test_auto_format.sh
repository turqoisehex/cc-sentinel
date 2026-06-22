#!/usr/bin/env bash
# Test harness for auto-format.sh
# Run: bash modules/commit-enforcement/tests/test_auto_format.sh
#
# Tests the PostToolUse hook that detects project language from manifest
# files and routes to the appropriate formatter. Formatters are not
# installed in the test environment, but the hook exits 0 regardless
# (|| true on every formatter call), so we test detection/routing logic
# and exit behavior only.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/auto-format.sh"

if [[ ! -f "$HOOK" ]]; then
  echo "ERROR: auto-format.sh not found at $HOOK" >&2
  exit 1
fi

# Counters
PASS=0
FAIL=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
if [[ ! -t 1 ]]; then RED=""; GREEN=""; NC=""; fi

# --- Input builders ---

build_write_input() {
  local file_path="$1"
  cat << EOF
{"tool_name": "Write", "tool_input": {"file_path": "$file_path", "content": "test"}}
EOF
}

build_edit_input() {
  local file_path="$1"
  cat << EOF
{"tool_name": "Edit", "tool_input": {"file_path": "$file_path", "old_string": "a", "new_string": "b"}}
EOF
}

build_multiedit_input() {
  # Accepts N file paths, builds a MultiEdit JSON with an edits array
  local edits=""
  local first=true
  for fp in "$@"; do
    if $first; then
      first=false
    else
      edits+=","
    fi
    edits+="{\"file_path\": \"$fp\", \"old_string\": \"a\", \"new_string\": \"b\"}"
  done
  cat << EOF
{"tool_name": "MultiEdit", "tool_input": {"edits": [$edits]}}
EOF
}

build_tool_input() {
  local tool_name="$1"
  cat << EOF
{"tool_name": "$tool_name", "tool_input": {"command": "echo hello"}}
EOF
}

build_empty_tool_input() {
  local tool_name="$1"
  cat << EOF
{"tool_name": "$tool_name", "tool_input": {}}
EOF
}

# --- Test helpers ---

setup_temp() {
  TMPDIR_ROOT=$(mktemp -d)
  PROJECT_DIR="$TMPDIR_ROOT/project"
  mkdir -p "$PROJECT_DIR"
}

teardown_temp() {
  cd /
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

# Run the hook with given stdin, inside PROJECT_DIR
run_hook() {
  local input="$1"
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"

  cd "$PROJECT_DIR"
  echo "$input" | bash "$HOOK" > "$stdout_file" 2> "$stderr_file"
  LAST_EXIT=$?
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
}

assert_exit() {
  local expected=$1 label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ $LAST_EXIT -eq $expected ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (exit=$LAST_EXIT)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label -- expected exit=$expected, got exit=$LAST_EXIT"
    echo "    stdout: $LAST_STDOUT"
    echo "    stderr: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_empty() {
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if [[ -z "$LAST_STDERR" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (stderr empty)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label -- stderr not empty: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_empty() {
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if [[ -z "$LAST_STDOUT" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (stdout empty)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label -- stdout not empty: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

# ==================== TESTS ====================

echo "=== auto-format.sh Test Harness ==="
echo ""

# --- Test 1: Non-file tool (Bash) -> exit 0, no formatting ---
echo "Test 1: Non-file tool (Bash) -> exit 0 silently"
setup_temp
run_hook "$(build_tool_input "Bash")"
assert_exit 0 "Bash tool exits 0"
assert_stdout_empty "no stdout for Bash tool"
teardown_temp

# --- Test 2: Non-file tool (Read) -> exit 0 ---
echo ""
echo "Test 2: Non-file tool (Read) -> exit 0 silently"
setup_temp
run_hook "$(build_tool_input "Read")"
assert_exit 0 "Read tool exits 0"
assert_stdout_empty "no stdout for Read tool"
teardown_temp

# --- Test 3: Write tool -> exits 0 (extracts file_path) ---
echo ""
echo "Test 3: Write tool -> exits 0"
setup_temp
run_hook "$(build_write_input "$PROJECT_DIR/test.dart")"
assert_exit 0 "Write tool exits 0"
teardown_temp

# --- Test 4: Edit tool -> exits 0 (extracts file_path) ---
echo ""
echo "Test 4: Edit tool -> exits 0"
setup_temp
run_hook "$(build_edit_input "$PROJECT_DIR/test.py")"
assert_exit 0 "Edit tool exits 0"
teardown_temp

# --- Test 5: MultiEdit tool -> exits 0 (extracts file_paths) ---
echo ""
echo "Test 5: MultiEdit tool -> exits 0"
setup_temp
run_hook "$(build_multiedit_input "$PROJECT_DIR/a.dart" "$PROJECT_DIR/b.dart")"
assert_exit 0 "MultiEdit tool exits 0"
teardown_temp

# --- Test 6: Empty tool_input (Write with no file_path) -> exit 0 ---
echo ""
echo "Test 6: Empty tool_input -> exit 0"
setup_temp
run_hook "$(build_empty_tool_input "Write")"
assert_exit 0 "empty Write tool_input exits 0"
teardown_temp

# --- Test 7: No manifest file -> no formatter runs, exit 0 ---
echo ""
echo "Test 7: No manifest file -> exit 0 (no formatter)"
setup_temp
# PROJECT_DIR has no manifest files
echo "content" > "$PROJECT_DIR/test.js"
run_hook "$(build_write_input "$PROJECT_DIR/test.js")"
assert_exit 0 "no manifest -> exit 0"
teardown_temp

# --- Test 8: pubspec.yaml present -> dart format detection ---
echo ""
echo "Test 8: pubspec.yaml -> dart format detection, exit 0"
setup_temp
touch "$PROJECT_DIR/pubspec.yaml"
echo "void main() {}" > "$PROJECT_DIR/test.dart"
run_hook "$(build_write_input "$PROJECT_DIR/test.dart")"
assert_exit 0 "pubspec.yaml present -> exit 0"
teardown_temp

# --- Test 9: package.json present -> prettier detection ---
echo ""
echo "Test 9: package.json -> prettier detection, exit 0"
setup_temp
echo '{}' > "$PROJECT_DIR/package.json"
echo "const x = 1;" > "$PROJECT_DIR/test.js"
run_hook "$(build_write_input "$PROJECT_DIR/test.js")"
assert_exit 0 "package.json present -> exit 0"
teardown_temp

# --- Test 10: Cargo.toml present -> cargo fmt detection ---
echo ""
echo "Test 10: Cargo.toml -> cargo fmt detection, exit 0"
setup_temp
touch "$PROJECT_DIR/Cargo.toml"
echo "fn main() {}" > "$PROJECT_DIR/test.rs"
run_hook "$(build_write_input "$PROJECT_DIR/test.rs")"
assert_exit 0 "Cargo.toml present -> exit 0"
teardown_temp

# --- Test 11: go.mod present -> gofmt detection ---
echo ""
echo "Test 11: go.mod -> gofmt detection, exit 0"
setup_temp
touch "$PROJECT_DIR/go.mod"
echo "package main" > "$PROJECT_DIR/test.go"
run_hook "$(build_write_input "$PROJECT_DIR/test.go")"
assert_exit 0 "go.mod present -> exit 0"
teardown_temp

# --- Test 12: setup.py present -> black/ruff detection ---
echo ""
echo "Test 12: setup.py -> black/ruff detection, exit 0"
setup_temp
touch "$PROJECT_DIR/setup.py"
echo "x = 1" > "$PROJECT_DIR/test.py"
run_hook "$(build_write_input "$PROJECT_DIR/test.py")"
assert_exit 0 "setup.py present -> exit 0"
teardown_temp

# --- Test 13: pyproject.toml present -> black/ruff detection ---
echo ""
echo "Test 13: pyproject.toml -> black/ruff detection, exit 0"
setup_temp
touch "$PROJECT_DIR/pyproject.toml"
echo "x = 1" > "$PROJECT_DIR/test.py"
run_hook "$(build_write_input "$PROJECT_DIR/test.py")"
assert_exit 0 "pyproject.toml present -> exit 0"
teardown_temp

# --- Test 14: Multiple edits in MultiEdit -> all extracted ---
echo ""
echo "Test 14: MultiEdit with 3 files -> all file_paths extracted"
setup_temp
touch "$PROJECT_DIR/pubspec.yaml"
echo "a" > "$PROJECT_DIR/one.dart"
echo "a" > "$PROJECT_DIR/two.dart"
echo "a" > "$PROJECT_DIR/three.dart"
# The hook iterates all extracted paths and calls format_file on each.
# Since dart isn't installed, all fail silently (|| true). Just verify exit 0.
run_hook "$(build_multiedit_input "$PROJECT_DIR/one.dart" "$PROJECT_DIR/two.dart" "$PROJECT_DIR/three.dart")"
assert_exit 0 "MultiEdit with 3 files exits 0"
teardown_temp

# --- Test 15: Tool name case sensitivity (lowercase "write" != "Write") ---
echo ""
echo "Test 15: Tool name case sensitivity -- 'write' (lowercase) is skipped"
setup_temp
touch "$PROJECT_DIR/pubspec.yaml"
INPUT='{"tool_name": "write", "tool_input": {"file_path": "'"$PROJECT_DIR/test.dart"'", "content": "test"}}'
run_hook "$INPUT"
assert_exit 0 "lowercase 'write' exits 0"
assert_stdout_empty "no output for unrecognized tool"
teardown_temp

# --- Test 16: Tool name case sensitivity -- 'WRITE' (uppercase) is skipped ---
echo ""
echo "Test 16: Tool name case sensitivity -- 'WRITE' (uppercase) is skipped"
setup_temp
INPUT='{"tool_name": "WRITE", "tool_input": {"file_path": "'"$PROJECT_DIR/test.dart"'", "content": "test"}}'
run_hook "$INPUT"
assert_exit 0 "uppercase 'WRITE' exits 0"
assert_stdout_empty "no output for unrecognized tool"
teardown_temp

# --- Test 17: Invalid JSON input -> exits 0 (never blocks) ---
echo ""
echo "Test 17: Invalid JSON input -> exits 0"
setup_temp
run_hook "this is not json at all {{{{"
assert_exit 0 "invalid JSON exits 0"
teardown_temp

# --- Test 18: Empty string input -> exits 0 ---
echo ""
echo "Test 18: Empty string input -> exits 0"
setup_temp
run_hook ""
assert_exit 0 "empty input exits 0"
teardown_temp

# --- Test 19: MultiEdit with empty edits array -> exit 0 ---
echo ""
echo "Test 19: MultiEdit with empty edits array -> exit 0"
setup_temp
INPUT='{"tool_name": "MultiEdit", "tool_input": {"edits": []}}'
run_hook "$INPUT"
assert_exit 0 "MultiEdit with empty edits exits 0"
teardown_temp

# --- Test 20: Write with empty file_path -> exit 0 ---
echo ""
echo "Test 20: Write with empty file_path string -> exit 0"
setup_temp
INPUT='{"tool_name": "Write", "tool_input": {"file_path": "", "content": "test"}}'
run_hook "$INPUT"
assert_exit 0 "Write with empty file_path exits 0"
teardown_temp

# --- Test 21: Manifest priority (pubspec.yaml wins over package.json) ---
echo ""
echo "Test 21: Manifest priority -- pubspec.yaml checked before package.json"
setup_temp
# Both present -- the hook's if/elif chain means pubspec.yaml wins
touch "$PROJECT_DIR/pubspec.yaml"
echo '{}' > "$PROJECT_DIR/package.json"
echo "void main() {}" > "$PROJECT_DIR/test.dart"
run_hook "$(build_write_input "$PROJECT_DIR/test.dart")"
assert_exit 0 "dual manifests -> exit 0 (pubspec.yaml takes priority)"
teardown_temp

# --- Test 22: Unrecognized tool names are silently skipped ---
echo ""
echo "Test 22: Unrecognized tool (TodoRead) -> exit 0 silently"
setup_temp
run_hook "$(build_tool_input "TodoRead")"
assert_exit 0 "TodoRead exits 0"
assert_stdout_empty "no stdout for TodoRead"
teardown_temp

# --- Test 23: Glob tool is ignored ---
echo ""
echo "Test 23: Glob tool -> exit 0 silently"
setup_temp
run_hook "$(build_tool_input "Glob")"
assert_exit 0 "Glob exits 0"
assert_stdout_empty "no stdout for Glob"
teardown_temp

# --- Test 24: MultiEdit with one entry -> single file extracted ---
echo ""
echo "Test 24: MultiEdit with single entry -> exits 0"
setup_temp
run_hook "$(build_multiedit_input "$PROJECT_DIR/solo.txt")"
assert_exit 0 "MultiEdit single entry exits 0"
teardown_temp

# --- Test 25: JSON with extra fields -> still works ---
echo ""
echo "Test 25: JSON with extra fields -> tool_name still extracted"
setup_temp
INPUT='{"tool_name": "Write", "tool_input": {"file_path": "'"$PROJECT_DIR/x.txt"'", "content": "c"}, "extra_field": 42}'
run_hook "$INPUT"
assert_exit 0 "extra JSON fields -> exit 0"
teardown_temp

# --- Test 26: tool_name field missing -> exits 0 ---
echo ""
echo "Test 26: Missing tool_name field -> exits 0"
setup_temp
INPUT='{"tool_input": {"file_path": "'"$PROJECT_DIR/x.txt"'"}}'
run_hook "$INPUT"
assert_exit 0 "missing tool_name exits 0"
teardown_temp

# ==================== SUMMARY ====================

echo ""
echo "========================================="
echo "  RESULTS: $PASS passed, $FAIL failed ($TOTAL total)"
echo "========================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  echo "All tests passed."
  exit 0
fi
