#!/usr/bin/env bash
# Test harness for anti-deferral.sh
# Run: bash modules/core/tests/test_anti_deferral.sh
#
# Pipes mock JSON stdin (mimicking CC PreToolUse hook protocol) and
# asserts exit code + stdout content.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/anti-deferral.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: anti-deferral.sh not found at $HOOK_SCRIPT" >&2
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

# Build JSON input for Write tool
build_write_input() {
  local content="$1"
  local content_json
  content_json=$(printf '%s' "$content" | jq -Rs '.')
  cat << EOF
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/tmp/test_file.md",
    "content": $content_json
  }
}
EOF
}

# Build JSON input for Edit tool
build_edit_input() {
  local new_string="$1"
  local ns_json
  ns_json=$(printf '%s' "$new_string" | jq -Rs '.')
  cat << EOF
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/tmp/test_file.md",
    "old_string": "old text",
    "new_string": $ns_json
  }
}
EOF
}

# Build JSON input for non-file tools (e.g., Bash)
build_non_file_input() {
  cat << EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "echo hello"
  }
}
EOF
}

# Build JSON input for MultiEdit tool
build_multiedit_input() {
  local new_string="$1"
  local ns_json
  ns_json=$(printf '%s' "$new_string" | jq -Rs '.')
  cat << EOF
{
  "tool_name": "MultiEdit",
  "tool_input": {
    "edits": [
      {"file_path": "/tmp/f1.md", "old_string": "a", "new_string": $ns_json},
      {"file_path": "/tmp/f2.md", "old_string": "b", "new_string": "clean text"}
    ]
  }
}
EOF
}

run_hook() {
  local input="$1"
  LAST_STDOUT=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null)
  LAST_EXIT=$?
}

assert_exit() {
  local expected=$1 label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ $LAST_EXIT -eq $expected ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (exit=$LAST_EXIT)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected exit=$expected, got exit=$LAST_EXIT"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | grep -qiE "$pattern" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label (stdout matches '$pattern')"
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
    echo -e "  ${GREEN}PASS${NC}: $label (stdout empty = no warning)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected empty stdout, got:"
    echo "    stdout: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

# ==================== TESTS ====================

echo "=== anti-deferral.sh Test Harness ==="
echo ""

# --- Test 1: Non-file tool -> no output (exit 0) ---
echo "Test 1: Non-file tool (Bash) -> silent pass-through"
INPUT=$(build_non_file_input)
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no warning for Bash tool"

# --- Test 2: Clean Write content -> no warning ---
echo ""
echo "Test 2: Write with clean content -> no warning"
INPUT=$(build_write_input "This is a normal task description. All work is complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no deferral language detected"

# --- Test 3: Write with 'future sprint' -> warning ---
echo ""
echo "Test 3: Write with 'future sprint' -> triggers warning"
INPUT=$(build_write_input "We can address this in a future sprint when we have bandwidth.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'future sprint'"
assert_stdout_contains "FIX IT NOW" "includes fix-it-now directive"

# --- Test 4: Write with 'not urgent' -> warning ---
echo ""
echo "Test 4: Write with 'not urgent' -> triggers warning"
INPUT=$(build_write_input "This is not urgent, we can come back to it later.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'not urgent'"

# --- Test 5: Write with 'defer to sprint' -> warning ---
echo ""
echo "Test 5: Write with 'defer to sprint N' -> triggers warning"
INPUT=$(build_write_input "Let's defer to sprint 15 for this feature.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'defer to sprint'"

# --- Test 6: Write with 'low priority' -> warning ---
echo ""
echo "Test 6: Write with 'low priority' -> triggers warning"
INPUT=$(build_write_input "This is a low priority item that can wait.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'low priority'"

# --- Test 7: Write with 'handle this later' -> warning ---
echo ""
echo "Test 7: Write with 'handle this later' -> triggers warning"
INPUT=$(build_write_input "We should handle this later after the refactor.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'handle this later'"

# --- Test 8: Write with 'TODO: fix later' -> warning ---
echo ""
echo "Test 8: Write with 'TODO: fix later' -> triggers warning"
INPUT=$(build_write_input "TODO: fix this later when we have time")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'TODO.*later'"

# --- Test 9: Edit tool with deferral language -> warning ---
echo ""
echo "Test 9: Edit tool with deferral language -> triggers warning"
INPUT=$(build_edit_input "This is acceptable as-is for now, we can revisit later.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects deferral in Edit tool"

# --- Test 10: MultiEdit tool with deferral in one edit -> warning ---
echo ""
echo "Test 10: MultiEdit with deferral in one edit -> triggers warning"
INPUT=$(build_multiedit_input "We can tackle later when bandwidth allows.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects deferral in MultiEdit"

# --- Test 11: Write with 'good enough for now' -> warning ---
echo ""
echo "Test 11: Write with 'good enough for now' -> triggers warning"
INPUT=$(build_write_input "The current implementation is good enough for now.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'good enough for now'"

# --- Test 12: Write with past-tense 'deferred' -> NO warning ---
echo ""
echo "Test 12: Past-tense 'deferred' -> no warning (documenting user decision)"
INPUT=$(build_write_input "The user deferred this feature to a later release.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "past-tense 'deferred' not flagged"

# --- Test 13: Write with 'out of scope for now' -> warning ---
echo ""
echo "Test 13: Write with 'out of scope for now' -> triggers warning"
INPUT=$(build_write_input "This feature is out of scope for now.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'out of scope for now'"

# --- Test 14: Empty content -> no warning ---
echo ""
echo "Test 14: Write with empty content -> no warning"
INPUT='{"tool_name": "Write", "tool_input": {"file_path": "/tmp/x.md", "content": ""}}'
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "empty content produces no warning"

# --- Test 15: Write with 'next sprint' (case insensitive) -> warning ---
echo ""
echo "Test 15: Case insensitive match for 'Next Sprint'"
INPUT=$(build_write_input "We should address this in the Next Sprint.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "case insensitive match works"

# --- Test 16: additionalContext format is valid JSON ---
echo ""
echo "Test 16: Output is valid JSON"
INPUT=$(build_write_input "This can wait for a future sprint.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if echo "$LAST_STDOUT" | jq -e '.additionalContext' >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC}: output is valid JSON with additionalContext key"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: output is not valid JSON"
  echo "    stdout: $LAST_STDOUT"
  FAIL=$((FAIL + 1))
fi

# --- Test 17: Write with 'future pass' -> warning (new tier 1) ---
echo ""
echo "Test 17: Write with 'future pass' -> triggers warning"
INPUT=$(build_write_input "Command/skill content drift. Separate synchronization future pass needed.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'future pass'"

# --- Test 18: Write with 'separate pass needed' -> warning (new tier 1) ---
echo ""
echo "Test 18: Write with 'separate pass needed' -> triggers warning"
INPUT=$(build_write_input "This requires a separate pass needed to complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'separate pass needed'"

# --- Test 19: Write with 'deferred —' -> warning (new tier 1) ---
echo ""
echo "Test 19: Write with 'deferred —' (em dash) -> triggers warning"
INPUT=$(build_write_input "Status: deferred — known debt from skills migration.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'deferred —'"

# --- Test 20: Write with 'deferred (known)' -> warning (new tier 1) ---
echo ""
echo "Test 20: Write with 'deferred (parenthetical)' -> triggers warning"
INPUT=$(build_write_input "Arrow style inconsistency deferred (cosmetic only).")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'deferred ('"

# --- Test 21: Write with 'future work' -> warning (new tier 1) ---
echo ""
echo "Test 21: Write with 'future work' -> triggers warning"
INPUT=$(build_write_input "Backport items identified as future work.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'future work'"

# --- Test 22: Write with 'previously deferred' -> NO warning (safe) ---
echo ""
echo "Test 22: 'previously deferred' -> no warning (historical documentation)"
INPUT=$(build_write_input "This was previously deferred by the team in Q2.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "'previously deferred' not flagged"

# --- Test 23: Write with 'anti-deferral' -> NO warning (the hook's own name) ---
echo ""
echo "Test 23: 'anti-deferral' -> no warning (hook self-reference)"
INPUT=$(build_write_input "Updated the anti-deferral hook with new patterns.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "'anti-deferral' not flagged"

# --- Test 24: Write with 'deferred loading' -> NO warning (technical term) ---
echo ""
echo "Test 24: 'deferred loading pattern' -> no warning (technical term)"
INPUT=$(build_write_input "Uses a deferred loading pattern for performance.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "'deferred loading' not flagged"

# --- Test 25: Write with 'next session' -> warning ---
echo ""
echo "Test 25: Write with 'in the next session' -> triggers warning"
INPUT=$(build_write_input "Do you want to dispatch R2-R3 in the next session?")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'next session'"

# --- Test 26: Write with 'separate session' -> warning ---
echo ""
echo "Test 26: Write with 'separate session' -> triggers warning"
INPUT=$(build_write_input "We could handle that in a separate session.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'separate session'"

# --- Test 27: Write with 'next conversation' -> warning ---
echo ""
echo "Test 27: Write with 'next conversation' -> triggers warning"
INPUT=$(build_write_input "Pick this up in the next conversation.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "RULE VIOLATION" "detects 'next conversation'"

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
