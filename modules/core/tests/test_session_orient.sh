#!/usr/bin/env bash
# Test harness for session-orient.sh
# Run: bash modules/core/tests/test_session_orient.sh
#
# Creates temp directories with mock CURRENT_TASK files,
# pipes mock JSON stdin, asserts exit code and stdout content.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/session-orient.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: session-orient.sh not found at $HOOK_SCRIPT" >&2
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
}

teardown_temp() {
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

build_input() {
  local cwd="$1"
  cat << EOF
{
  "session_id": "test-session-$$",
  "cwd": "$cwd"
}
EOF
}

run_hook() {
  local input="$1"
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"
  echo "$input" | bash "$HOOK_SCRIPT" > "$stdout_file" 2> "$stderr_file"
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

create_ct() {
  local dir="$1" status="$2"
  cat > "$dir/CURRENT_TASK.md" << EOF
# CURRENT TASK
**Status:** $status
## Plan
- Step 1: Do something
EOF
}

create_channel_ct() {
  local dir="$1" channel="$2" status="$3"
  cat > "$dir/CURRENT_TASK_ch${channel}.md" << EOF
# CURRENT TASK — Channel $channel
**Channel:** $channel
**Status:** $status
## Plan
- Step 1: Channel $channel work
EOF
}

create_channel_ct_with_phase() {
  local dir="$1" channel="$2" phase="$3"
  cat > "$dir/CURRENT_TASK_ch${channel}.md" << EOF
# CURRENT TASK — Channel $channel
**Channel:** $channel
**Phase:** $phase
## Plan
- Step 1: Channel $channel work
EOF
}

# ==================== TESTS ====================

echo "=== session-orient.sh Test Harness ==="
echo ""

# --- Test 1: No CURRENT_TASK.md -> no output ---
echo "Test 1: No CURRENT_TASK.md -> silent exit"
setup_temp
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no CT file, no orientation"
teardown_temp

# --- Test 2: CT with IN PROGRESS -> orientation message ---
echo ""
echo "Test 2: CT with IN PROGRESS -> orientation message"
setup_temp
create_ct "$PROJECT" "IN PROGRESS"
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "SESSION START" "outputs session start message"
assert_stdout_contains "CURRENT_TASK.md" "mentions CT file"
teardown_temp

# --- Test 3: CT with COMPLETE -> no orientation ---
echo ""
echo "Test 3: CT with COMPLETE status -> no orientation"
setup_temp
create_ct "$PROJECT" "COMPLETE"
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "complete status produces no orientation"
teardown_temp

# --- Test 4: Active channel CT -> shows active channel ---
echo ""
echo "Test 4: Active channel CT -> shows channel in orientation"
setup_temp
create_ct "$PROJECT" "COMPLETE"
create_channel_ct "$PROJECT" "3" "IN PROGRESS"
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "SESSION START" "outputs orientation"
assert_stdout_contains "Channel 3" "mentions active channel 3"
teardown_temp

# --- Test 5: Multiple active channels -> shows all ---
echo ""
echo "Test 5: Multiple active channels -> shows all in orientation"
setup_temp
create_ct "$PROJECT" "COMPLETE"
create_channel_ct "$PROJECT" "1" "IN PROGRESS"
create_channel_ct "$PROJECT" "5" "IN PROGRESS"
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Channel 1" "mentions channel 1"
assert_stdout_contains "Channel 5" "mentions channel 5"
teardown_temp

# --- Test 6: Phase-based detection (active phase) ---
echo ""
echo "Test 6: Channel with active phase -> detects as active"
setup_temp
create_ct "$PROJECT" "COMPLETE"
create_channel_ct_with_phase "$PROJECT" "2" "/3 Implementation"
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Channel 2" "phase-based active detection works"
teardown_temp

# --- Test 7: Phase complete -> not active ---
echo ""
echo "Test 7: Channel with completed phase -> not active"
setup_temp
create_ct "$PROJECT" "COMPLETE"
create_channel_ct_with_phase "$PROJECT" "4" "/5 Complete"
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "completed phase not treated as active"
teardown_temp

# --- Test 8: Shared CT active + no channels -> orientation ---
echo ""
echo "Test 8: Shared CT active (unchanneled) -> orientation"
setup_temp
create_ct "$PROJECT" "IN PROGRESS"
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "unchanneled work" "mentions unchanneled active work"
teardown_temp

# --- Test 9: Output is valid JSON ---
echo ""
echo "Test 9: Output is valid JSON with additionalContext"
setup_temp
create_ct "$PROJECT" "IN PROGRESS"
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if echo "$LAST_STDOUT" | jq -e '.additionalContext' >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC}: output is valid JSON with additionalContext"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: output is not valid JSON or missing additionalContext"
  echo "    stdout: $LAST_STDOUT"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 10: Stale pending cleanup ---
echo ""
echo "Test 10: Stale pending files cleaned up"
setup_temp
create_ct "$PROJECT" "IN PROGRESS"
mkdir -p "$PROJECT/verification_findings/_pending_sonnet"
# Create a stale .md file (we'll age it)
STALE_FILE="$PROJECT/verification_findings/_pending_sonnet/stale_task.md"
echo "old work" > "$STALE_FILE"
# Use python with cygpath to set mtime to 2 hours ago (Git Bash on Windows)
STALE_WIN=$(cygpath -w "$STALE_FILE" 2>/dev/null || echo "$STALE_FILE")
python -c "import os, time; os.utime(r'$STALE_WIN', (time.time()-7200, time.time()-7200))" 2>/dev/null || \
  python3 -c "import os, time; os.utime(r'$STALE_WIN', (time.time()-7200, time.time()-7200))" 2>/dev/null || \
  touch -d "2 hours ago" "$STALE_FILE" 2>/dev/null
INPUT=$(build_input "$PROJECT")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if [[ ! -f "$STALE_FILE" ]]; then
  echo -e "  ${GREEN}PASS${NC}: stale pending file was cleaned up"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: stale pending file still exists"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 11: Empty input -> silent exit ---
echo ""
echo "Test 11: Empty/invalid input -> silent exit"
setup_temp
LAST_STDOUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>/dev/null)
LAST_EXIT=$?
assert_exit 0 "exit 0"
assert_stdout_empty "empty cwd causes silent exit"
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
