#!/usr/bin/env bash
# Test harness for post-compact-reorient.sh
# Run: bash modules/core/tests/test_post_compact.sh
#
# Creates temp directories with mock project files (CLAUDE.md, CURRENT_TASK*.md),
# pipes mock SessionStart JSON on stdin, asserts exit code and stdout content.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/post-compact-reorient.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: post-compact-reorient.sh not found at $HOOK_SCRIPT" >&2
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
  PROJECT="$TMPDIR_ROOT/project"
  mkdir -p "$PROJECT"
  # Create minimal CLAUDE.md so resolve_project_dir picks this dir over CWD
  touch "$PROJECT/CLAUDE.md"
}

teardown_temp() {
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

build_session_input() {
  local source="${1:-}"
  cat << EOF
{"source": "$source"}
EOF
}

run_hook() {
  local input="$1"
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"
  echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK_SCRIPT" > "$stdout_file" 2> "$stderr_file"
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
    echo -e "  ${RED}FAIL${NC}: $label — expected exit=$expected, got exit=$LAST_EXIT"
    echo "    stderr: $LAST_STDERR"
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
    echo "    stdout (first 200 chars): ${LAST_STDOUT:0:200}"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_not_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | grep -qiE "$pattern" 2>/dev/null; then
    echo -e "  ${RED}FAIL${NC}: $label — stdout unexpectedly matches '$pattern'"
    echo "    stdout (first 200 chars): ${LAST_STDOUT:0:200}"
    FAIL=$((FAIL + 1))
  else
    echo -e "  ${GREEN}PASS${NC}: $label (stdout does NOT match '$pattern')"
    PASS=$((PASS + 1))
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
    echo "    stdout (first 200 chars): ${LAST_STDOUT:0:200}"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_valid() {
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | jq -e '.' >/dev/null 2>&1; then
    echo -e "  ${GREEN}PASS${NC}: $label (valid JSON)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — output is not valid JSON"
    echo "    stdout (first 200 chars): ${LAST_STDOUT:0:200}"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_has_key() {
  local key="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | jq -e ".$key" >/dev/null 2>&1; then
    echo -e "  ${GREEN}PASS${NC}: $label (JSON has key '$key')"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — JSON missing key '$key'"
    echo "    stdout (first 200 chars): ${LAST_STDOUT:0:200}"
    FAIL=$((FAIL + 1))
  fi
}

create_claude_md() {
  local dir="$1" lines="${2:-10}"
  {
    for i in $(seq 1 "$lines"); do
      echo "Line $i of CLAUDE.md — project rules here"
    done
  } > "$dir/CLAUDE.md"
}

create_ct() {
  local dir="$1"
  cat > "$dir/CURRENT_TASK.md" << 'CTEOF'
# CURRENT TASK
**Status:** IN PROGRESS
**Channel:** shared

## Active Channels
| Channel | Owner | Phase |
|---------|-------|-------|
| ch1     | Opus  | /3    |

## Plan
- Step 1: Do something important
CTEOF
}

create_channel_ct() {
  local dir="$1" channel="$2"
  cat > "$dir/CURRENT_TASK_ch${channel}.md" << CHEOF
# CURRENT TASK — Channel $channel
**Channel:** $channel
**Phase:** /3 Implementation
## Plan
- Step 1: Channel $channel work item
- Step 2: More channel $channel work
CHEOF
}

# ==================== TESTS ====================

echo "=== post-compact-reorient.sh Test Harness ==="
echo ""

# --- Test 1: source != "compact" -> exit 0, no output ---
echo "Test 1: source = 'user' -> silent exit"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
INPUT=$(build_session_input "user")
run_hook "$INPUT"
assert_exit 0 "exit 0 for non-compact source"
assert_stdout_empty "no output for source=user"
teardown_temp

# --- Test 2: source = "compact", no files -> generic message, valid JSON ---
echo ""
echo "Test 2: source = 'compact', no files -> generic message"
setup_temp
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "POST-COMPACTION" "outputs re-orientation header"
assert_stdout_contains "Look for state files" "generic fallback message"
assert_json_valid "output is valid JSON"
teardown_temp

# --- Test 3: source = "compact", CLAUDE.md only -> includes CLAUDE.md header ---
echo ""
echo "Test 3: source = 'compact', CLAUDE.md only -> CLAUDE.md path"
setup_temp
create_claude_md "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CLAUDE\\.md.*first 30 lines" "mentions CLAUDE.md truncation"
assert_stdout_contains "Line 1 of CLAUDE" "includes actual CLAUDE.md content"
teardown_temp

# --- Test 4: source = "compact", CURRENT_TASK.md present -> includes full CT content ---
echo ""
echo "Test 4: source = 'compact', CURRENT_TASK.md -> includes CT content"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CURRENT_TASK\\.md.*shared index" "CT section header present"
assert_stdout_contains "Do something important" "CT body content included"
teardown_temp

# --- Test 5: source = "compact", CURRENT_TASK_ch1.md only -> picked up by glob ---
echo ""
echo "Test 5: Channel CT (ch1) only -> picked up by glob"
setup_temp
create_claude_md "$PROJECT"
create_channel_ct "$PROJECT" "1"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CURRENT_TASK_ch1\\.md" "channel file name appears in output"
assert_stdout_contains "Channel 1 work item" "channel CT content included"
teardown_temp

# --- Test 6: Both shared + channel CT -> both included ---
echo ""
echo "Test 6: Shared CT + channel CT -> both in output"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
create_channel_ct "$PROJECT" "3"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CURRENT_TASK\\.md.*shared index" "shared CT section present"
assert_stdout_contains "CURRENT_TASK_ch3\\.md" "channel 3 section present"
assert_stdout_contains "Do something important" "shared CT body included"
assert_stdout_contains "Channel 3 work item" "channel 3 body included"
teardown_temp

# --- Test 7: CLAUDE.md truncated to 30 lines ---
echo ""
echo "Test 7: CLAUDE.md with 50 lines -> only first 30 included"
setup_temp
create_claude_md "$PROJECT" 50
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
# Extract the additionalContext string and check for line 30 and absence of line 31
CONTEXT_STR=$(echo "$LAST_STDOUT" | jq -r '.additionalContext // ""' 2>/dev/null)
TOTAL=$((TOTAL + 1))
if echo "$CONTEXT_STR" | grep -q "Line 30 of CLAUDE" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC}: line 30 is present"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: line 30 not found in CLAUDE.md content"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if echo "$CONTEXT_STR" | grep -q "Line 31 of CLAUDE" 2>/dev/null; then
  echo -e "  ${RED}FAIL${NC}: line 31 should NOT be present (truncation failed)"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}PASS${NC}: line 31 is absent (truncation works)"
  PASS=$((PASS + 1))
fi
teardown_temp

# --- Test 8: Recent agent files in verification_findings/ -> noted in output ---
echo ""
echo "Test 8: Recent verification_findings files -> agent note"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
mkdir -p "$PROJECT/verification_findings"
# Create a CT file first, then create a newer agent file
# Touch the CT to set a baseline time
sleep 1
echo "# Agent output" > "$PROJECT/verification_findings/agent_test_result.md"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "AGENT OUTPUT FILES" "agent output section present"
assert_stdout_contains "agent_test_result\\.md" "specific agent file named"
teardown_temp

# --- Test 9: Output is valid JSON ---
echo ""
echo "Test 9: All output paths produce valid JSON"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_json_valid "full path output is valid JSON"
teardown_temp

# --- Test 10: Output contains additionalContext key ---
echo ""
echo "Test 10: JSON output has additionalContext key"
setup_temp
create_claude_md "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_json_has_key "additionalContext" "additionalContext key present"
teardown_temp

# --- Test 11: Empty source field -> treated as non-compact, exits silently ---
echo ""
echo "Test 11: Empty source field -> silent exit"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
INPUT=$(build_session_input "")
run_hook "$INPUT"
assert_exit 0 "exit 0 for empty source"
assert_stdout_empty "empty source treated as non-compact"
teardown_temp

# --- Test 12: CLAUDE_PROJECT_DIR resolution ---
echo ""
echo "Test 12: CLAUDE_PROJECT_DIR resolution finds project files"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
INPUT=$(build_session_input "compact")
# run_hook already sets CLAUDE_PROJECT_DIR=$PROJECT
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "POST-COMPACTION" "CLAUDE_PROJECT_DIR used to find files"
assert_stdout_contains "Do something important" "CT content from resolved dir"
teardown_temp

# --- Test 13: source = "api" -> silent exit ---
echo ""
echo "Test 13: source = 'api' -> silent exit (only 'compact' triggers)"
setup_temp
create_claude_md "$PROJECT"
INPUT=$(build_session_input "api")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "source=api produces no output"
teardown_temp

# --- Test 14: Multiple channel CTs -> all picked up ---
echo ""
echo "Test 14: Multiple channel CTs (ch1, ch5, ch7) -> all included"
setup_temp
create_claude_md "$PROJECT"
create_channel_ct "$PROJECT" "1"
create_channel_ct "$PROJECT" "5"
create_channel_ct "$PROJECT" "7"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CURRENT_TASK_ch1\\.md" "ch1 picked up"
assert_stdout_contains "CURRENT_TASK_ch5\\.md" "ch5 picked up"
assert_stdout_contains "CURRENT_TASK_ch7\\.md" "ch7 picked up"
teardown_temp

# --- Test 15: No verification_findings dir -> no agent note ---
echo ""
echo "Test 15: No verification_findings/ -> no agent output section"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
# Deliberately do NOT create verification_findings/
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_not_contains "AGENT OUTPUT FILES" "no agent section without directory"
teardown_temp

# --- Test 16: CT-only path (no CLAUDE.md) still includes CT ---
echo ""
echo "Test 16: CT exists but no CLAUDE.md -> still picks up CT"
setup_temp
create_ct "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
# The hook resolves project dir by looking for CURRENT_TASK.md OR CLAUDE.md
assert_stdout_contains "CURRENT_TASK\\.md" "CT found without CLAUDE.md"
assert_stdout_contains "Do something important" "CT content present"
teardown_temp

# --- Test 17: Full CT path has resume instruction ---
echo ""
echo "Test 17: Full CT output includes resume instruction"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "resume from where it indicates" "resume instruction present"
assert_stdout_contains "Do NOT proceed from memory" "anti-memory instruction present"
teardown_temp

# --- Test 18: CLAUDE.md-only path includes re-orient message ---
echo ""
echo "Test 18: CLAUDE.md only -> re-orient from files message"
setup_temp
create_claude_md "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Re-orient from files, not memory" "re-orient instruction"
assert_stdout_contains "CLAUDE\\.md.*first 30 lines" "CLAUDE.md header"
teardown_temp

# --- Test 19: Generic path (no files) -> correct fallback ---
echo ""
echo "Test 19: No project files -> generic fallback"
setup_temp
rm -f "$PROJECT/CLAUDE.md"  # Remove marker so resolve_project_dir finds nothing
INPUT=$(build_session_input "compact")
# Override pwd and git root so resolve_project_dir can't find real project files
SAVED_DIR="$(pwd)"
cd "$TMPDIR_ROOT" 2>/dev/null
(echo "$INPUT" | CLAUDE_PROJECT_DIR="$PROJECT" GIT_CEILING_DIRECTORIES="$TMPDIR_ROOT" bash "$HOOK_SCRIPT" > "$TMPDIR_ROOT/stdout" 2> "$TMPDIR_ROOT/stderr")
LAST_EXIT=$?; LAST_STDOUT=$(cat "$TMPDIR_ROOT/stdout"); LAST_STDERR=$(cat "$TMPDIR_ROOT/stderr")
cd "$SAVED_DIR" 2>/dev/null
assert_exit 0 "exit 0"
assert_stdout_not_contains "CLAUDE\\.md.*first 30 lines" "no CLAUDE.md section"
assert_stdout_not_contains "CURRENT_TASK" "no CT section"
assert_stdout_contains "Look for state files" "generic fallback instruction"
assert_json_has_key "additionalContext" "JSON structure correct for fallback"
teardown_temp

# --- Test 20: Missing .source key in JSON -> silent exit ---
echo ""
echo "Test 20: JSON with no .source key -> silent exit"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
LAST_STDOUT=""
LAST_STDERR=""
echo '{"other_key": "value"}' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK_SCRIPT" > "$TMPDIR_ROOT/stdout" 2> "$TMPDIR_ROOT/stderr"
LAST_EXIT=$?
LAST_STDOUT=$(cat "$TMPDIR_ROOT/stdout")
LAST_STDERR=$(cat "$TMPDIR_ROOT/stderr")
assert_exit 0 "exit 0 for missing .source"
assert_stdout_empty "missing .source treated as non-compact"
teardown_temp

# --- Test 21: Verification findings with no recent files -> no agent note ---
echo ""
echo "Test 21: verification_findings/ exists but no files newer than CT -> no agent note"
setup_temp
create_claude_md "$PROJECT"
mkdir -p "$PROJECT/verification_findings"
# Create an agent file FIRST, then create CT after (so CT is newer)
echo "# Old agent output" > "$PROJECT/verification_findings/old_result.md"
sleep 1
create_ct "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_not_contains "AGENT OUTPUT FILES" "old agent file not flagged as recent"
teardown_temp

# --- Test 22: Agent file note includes read instruction ---
echo ""
echo "Test 22: Agent output note includes read-these-files instruction"
setup_temp
create_claude_md "$PROJECT"
create_ct "$PROJECT"
mkdir -p "$PROJECT/verification_findings"
sleep 1
echo "# Fresh result" > "$PROJECT/verification_findings/fresh_result.md"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Read these files" "read instruction for agent files"
assert_stdout_contains "agent IDs do not survive compaction" "explains why files matter"
teardown_temp

# --- Test 23: CLAUDE.md-only path JSON has additionalContext ---
echo ""
echo "Test 23: CLAUDE.md-only path -> valid JSON with additionalContext"
setup_temp
create_claude_md "$PROJECT"
INPUT=$(build_session_input "compact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_json_valid "CLAUDE-only path produces valid JSON"
assert_json_has_key "additionalContext" "additionalContext in CLAUDE-only path"
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
