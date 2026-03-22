#!/usr/bin/env bash
# Test harness for context-awareness-hook.sh
# Run: bash modules/context-awareness/tests/test_context_awareness_hook.sh
#
# Creates temp trigger files, pipes mock JSON stdin,
# asserts exit code and stdout content.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/context-awareness-hook.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: context-awareness-hook.sh not found at $HOOK_SCRIPT" >&2
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

# --- Test helpers ---

setup_temp() {
  TMPDIR_ROOT=$(mktemp -d)
  FLAG_DIR="$TMPDIR_ROOT/flags"
  mkdir -p "$FLAG_DIR"
  CONFIG_DIR="$TMPDIR_ROOT/project/.claude/cc-context-awareness"
  mkdir -p "$CONFIG_DIR"
  # Write config pointing to our temp flag dir
  cat > "$CONFIG_DIR/config.json" << EOF
{
  "flag_dir": "$FLAG_DIR",
  "hook_event": "PreToolUse"
}
EOF
}

teardown_temp() {
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

build_input() {
  local session_id="$1"
  cat << EOF
{
  "session_id": "$session_id",
  "tool_name": "Bash"
}
EOF
}

create_trigger() {
  local session_id="$1" message="$2" level="${3:-info}"
  local msg_json
  msg_json=$(printf '%s' "$message" | jq -Rs '.')
  cat > "$FLAG_DIR/.cc-ctx-trigger-${session_id}" << EOF
{
  "message": $msg_json,
  "level": "$level"
}
EOF
}

run_hook() {
  local input="$1" workdir="${2:-$TMPDIR_ROOT/project}"
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"
  cd "$workdir"
  echo "$input" | bash "$HOOK_SCRIPT" > "$stdout_file" 2> "$stderr_file"
  LAST_EXIT=$?
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
  cd - >/dev/null
}

assert_exit() {
  local expected=$1 label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ $LAST_EXIT -eq $expected ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (exit=$LAST_EXIT)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected exit=$expected, got exit=$LAST_EXIT"
    echo "    stderr: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | grep -qiE "$pattern" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label (stdout matches)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — stdout does not match '$pattern'"
    echo "    stdout: $LAST_STDOUT"
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
    echo -e "  ${RED}FAIL${NC}: $label — expected empty stdout, got:"
    echo "    stdout: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

# ==================== TESTS ====================

echo "=== context-awareness-hook.sh Test Harness ==="
echo ""

# --- Test 1: No trigger file -> silent exit ---
echo "Test 1: No trigger file -> silent exit"
setup_temp
INPUT=$(build_input "sess-001")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no trigger file = no output"
teardown_temp

# --- Test 2: Trigger file present -> outputs message ---
echo ""
echo "Test 2: Trigger file with message -> injects context"
setup_temp
INPUT=$(build_input "sess-002")
create_trigger "sess-002" "Context window at 75%. Wrap up current unit."
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "75%" "outputs trigger message"
assert_stdout_contains "additionalContext" "uses additionalContext field"
teardown_temp

# --- Test 3: Trigger file consumed after read ---
echo ""
echo "Test 3: Trigger file is removed after being read"
setup_temp
INPUT=$(build_input "sess-003")
create_trigger "sess-003" "Reminder: document progress."
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if [[ ! -f "$FLAG_DIR/.cc-ctx-trigger-sess-003" ]]; then
  echo -e "  ${GREEN}PASS${NC}: trigger file removed after read"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: trigger file still exists"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 4: Empty session_id -> silent exit ---
echo ""
echo "Test 4: Empty session_id -> silent exit"
setup_temp
INPUT='{"session_id": "", "tool_name": "Bash"}'
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "empty session_id produces no output"
teardown_temp

# --- Test 5: Trigger with empty message -> cleaned up, no output ---
echo ""
echo "Test 5: Trigger with empty message -> cleanup, no output"
setup_temp
INPUT=$(build_input "sess-005")
cat > "$FLAG_DIR/.cc-ctx-trigger-sess-005" << 'EOF'
{
  "message": "",
  "level": "info"
}
EOF
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "empty message produces no output"
TOTAL=$((TOTAL + 1))
if [[ ! -f "$FLAG_DIR/.cc-ctx-trigger-sess-005" ]]; then
  echo -e "  ${GREEN}PASS${NC}: empty-message trigger file cleaned up"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: empty-message trigger file not cleaned up"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 6: Different session IDs don't interfere ---
echo ""
echo "Test 6: Trigger for different session -> not read"
setup_temp
INPUT=$(build_input "sess-006")
create_trigger "sess-OTHER" "This is for a different session"
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "trigger for different session not read"
# Verify the other session's trigger is untouched
TOTAL=$((TOTAL + 1))
if [[ -f "$FLAG_DIR/.cc-ctx-trigger-sess-OTHER" ]]; then
  echo -e "  ${GREEN}PASS${NC}: other session's trigger file untouched"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: other session's trigger file was incorrectly removed"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 7: Output is valid JSON ---
echo ""
echo "Test 7: Output is well-formed JSON"
setup_temp
INPUT=$(build_input "sess-007")
create_trigger "sess-007" "Context at 85%. State files must be current."
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if echo "$LAST_STDOUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC}: output has hookSpecificOutput.additionalContext"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: output not valid JSON or missing expected structure"
  echo "    stdout: $LAST_STDOUT"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 8: Warning level trigger ---
echo ""
echo "Test 8: Warning level trigger works"
setup_temp
INPUT=$(build_input "sess-008")
create_trigger "sess-008" "URGENT: Auto-compaction imminent." "warning"
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "URGENT" "warning level message delivered"
teardown_temp

# --- Test 9: No config file -> defaults to /tmp ---
echo ""
echo "Test 9: No config file -> uses /tmp defaults"
setup_temp
# Remove the config
rm -rf "$CONFIG_DIR"
# Create trigger in /tmp instead
create_trigger_in_tmp() {
  local session_id="$1" message="$2"
  local msg_json
  msg_json=$(printf '%s' "$message" | jq -Rs '.')
  cat > "/tmp/.cc-ctx-trigger-${session_id}" << EOF
{
  "message": $msg_json,
  "level": "info"
}
EOF
}
create_trigger_in_tmp "sess-009" "Fallback to /tmp works"
INPUT=$(build_input "sess-009")
# Need to run from a dir without .claude/cc-context-awareness/config.json
# and without global config
run_hook "$INPUT" "$TMPDIR_ROOT"
assert_exit 0 "exit 0"
assert_stdout_contains "Fallback" "/tmp trigger picked up without config"
# Cleanup
rm -f "/tmp/.cc-ctx-trigger-sess-009"
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
