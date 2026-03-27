#!/usr/bin/env bash
# Test harness for stop-task-check.sh
# Run: bash modules/verification/tests/test_stop_task_check.sh
#
# Creates temp directories with mock CT files and squad dirs,
# pipes mock JSON stdin, asserts exit code and stdout content.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/stop-task-check.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: stop-task-check.sh not found at $HOOK_SCRIPT" >&2
  exit 1
fi

# Counters
PASS=0
FAIL=0
TOTAL=0

# Colors (if terminal supports them)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
if [[ ! -t 1 ]]; then RED=""; GREEN=""; NC=""; fi

# --- Test helpers ---

setup_temp() {
  TMPDIR_ROOT=$(mktemp -d)
  PROJECT="$TMPDIR_ROOT/project"
  mkdir -p "$PROJECT/verification_findings"
}

teardown_temp() {
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

# Create a minimal CURRENT_TASK.md with given status
create_ct() {
  local dir="$1" status="$2" file="${3:-CURRENT_TASK.md}"
  cat > "$dir/$file" << EOF
# CURRENT TASK
**Status:** $status
## Plan
- Step 1: Do something
EOF
}

# Create a channel CT with channel number in it
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

# Build JSON input mimicking CC hook protocol
build_input() {
  local cwd="$1" msg="${2:-}" stop_active="${3:-false}"
  local msg_json
  msg_json=$(printf '%s' "$msg" | jq -Rs '.')
  cat << EOF
{
  "session_id": "test-session-$$",
  "cwd": "$cwd",
  "stop_hook_active": $stop_active,
  "last_assistant_message": $msg_json,
  "hook_event_name": "Stop"
}
EOF
}

# Run the hook and capture results
run_hook() {
  local input="$1"
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"
  local exit_code

  # Run in temp dir to prevent $(pwd) / git-rev-parse fallback from finding
  # real project files outside the test fixture.
  echo "$input" | (cd "$TMPDIR_ROOT" && bash "$HOOK_SCRIPT") > "$stdout_file" 2> "$stderr_file"
  exit_code=$?

  LAST_EXIT=$exit_code
  LAST_STDOUT=$(cat "$stdout_file")
  LAST_STDERR=$(cat "$stderr_file")
}

# Assert exit code
assert_exit() {
  local expected=$1 label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ $LAST_EXIT -eq $expected ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (exit=$LAST_EXIT)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected exit=$expected, got exit=$LAST_EXIT"
    echo "    stdout: $LAST_STDOUT"
    echo "    stderr: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  fi
}

# Assert stdout contains a pattern
assert_stdout_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | grep -qE "$pattern" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label (stdout matches '$pattern')"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — stdout does not match '$pattern'"
    echo "    stdout: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

# Assert stdout is empty (ALLOW = no output)
assert_stdout_empty() {
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if [[ -z "$LAST_STDOUT" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (stdout empty = ALLOW)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected empty stdout (ALLOW), got:"
    echo "    stdout: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

# Create a valid squad dir with all 5 agents passing
create_passing_squad() {
  local dir="$1" squad_name="${2:-squad_sonnet}"
  local squad_dir="$dir/verification_findings/$squad_name"
  mkdir -p "$squad_dir"
  for agent in mechanical adversarial completeness dependency cold_reader; do
    echo "VERDICT: PASS" > "$squad_dir/$agent.md"
  done
}

# Create a squad dir with some agents failing
create_failing_squad() {
  local dir="$1" squad_name="${2:-squad_sonnet}" fail_count="${3:-2}"
  local squad_dir="$dir/verification_findings/$squad_name"
  mkdir -p "$squad_dir"
  local i=0
  for agent in mechanical adversarial completeness dependency cold_reader; do
    if (( i < fail_count )); then
      echo "VERDICT: FAIL" > "$squad_dir/$agent.md"
    else
      echo "VERDICT: PASS" > "$squad_dir/$agent.md"
    fi
    i=$((i + 1))
  done
}

# Touch a file to set its mtime to now
touch_now() {
  touch "$1"
}

# Touch a file and set its mtime to N seconds ago
touch_aged() {
  local file="$1" age="$2"
  touch "$file"
  # Use touch -d for GNU or python fallback
  local target_time
  target_time=$(date -d "-${age} seconds" '+%Y%m%d%H%M.%S' 2>/dev/null)
  if [[ -n "$target_time" ]]; then
    touch -t "$target_time" "$file"
  else
    # macOS/BSD fallback
    local epoch now
    now=$(date +%s)
    epoch=$((now - age))
    target_time=$(date -r "$epoch" '+%Y%m%d%H%M.%S' 2>/dev/null) || true
    if [[ -n "$target_time" ]]; then
      touch -t "$target_time" "$file"
    else
      # Python fallback for Windows Git Bash
      python3 -c "import os; os.utime('$file', ($(date +%s)-$age, $(date +%s)-$age))" 2>/dev/null || \
      python -c "import os; os.utime('$file', ($(date +%s)-$age, $(date +%s)-$age))" 2>/dev/null || \
      echo "    WARNING: Could not set mtime for $file" >&2
    fi
  fi
}

# ==================== TESTS ====================

echo "=== stop-task-check.sh Test Harness ==="
echo ""

# --- Test 1: No CURRENT_TASK.md -> ALLOW ---
echo "Test 1: No CURRENT_TASK.md -> ALLOW"
setup_temp
# Project dir exists but no CT file
mkdir -p "$PROJECT"
INPUT=$(build_input "$PROJECT" "All work is done and complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0 (allow)"
assert_stdout_empty "no block output"
teardown_temp

# --- Test 2: Active task + completion language + no squad -> BLOCK ---
echo ""
echo "Test 2: Active task + completion language + no squad -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "All tasks are done and the work is complete. What should we do next?")
run_hook "$INPUT"
assert_exit 0 "exit 0 (hook always exits 0)"
assert_stdout_contains '"decision".*"block"' "outputs block decision"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "mentions verification"
teardown_temp

# --- Test 3: Active task + completion language + valid squad (5 PASS) -> ALLOW ---
echo ""
echo "Test 3: Active task + completion language + valid squad -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
create_passing_squad "$PROJECT"
INPUT=$(build_input "$PROJECT" "All work is complete and ready to ship.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (verification found)"
teardown_temp

# --- Test 3b: VERDICT: WARN counts as passing (not just PASS) ---
echo ""
echo "Test 3b: Squad with WARN verdicts -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# Create squad with mix of PASS and WARN
WARN_SQUAD="$PROJECT/verification_findings/squad_sonnet"
mkdir -p "$WARN_SQUAD"
echo "VERDICT: PASS" > "$WARN_SQUAD/mechanical.md"
echo "VERDICT: WARN (2 minor)" > "$WARN_SQUAD/adversarial.md"
echo "VERDICT: PASS" > "$WARN_SQUAD/completeness.md"
echo "VERDICT: WARN (1 minor)" > "$WARN_SQUAD/dependency.md"
echo "VERDICT: PASS" > "$WARN_SQUAD/cold_reader.md"
INPUT=$(build_input "$PROJECT" "All work is complete and ready to ship.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (WARN counts as passing)"
teardown_temp

# --- Test 4: Active task + completion + squad from wrong channel -> BLOCK ---
echo ""
echo "Test 4: Channeled task + completion + wrong-channel squad -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"  # shared CT shows complete (not active)
create_channel_ct "$PROJECT" "2" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK_ch2.md"
# Squad exists but for channel 1, not channel 2
create_passing_squad "$PROJECT" "squad_ch1_sonnet"
INPUT=$(build_input "$PROJECT" "All tasks are done. The implementation is complete.")
WAKEFUL_CHANNEL=2 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocks (wrong channel squad)"
teardown_temp

# --- Test 5: Question without completion language -> ALLOW ---
echo ""
echo "Test 5: Question ending, no completion language -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Which spec file should I read next?")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (question bypass)"
teardown_temp

# --- Test 5b: Question WITH completion language -> still BLOCK ---
echo ""
echo "Test 5b: Question + completion language -> still BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "All work is done. What should we do next?")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocks (completion language present despite question)"
teardown_temp

# --- Test 6: Active task + stale CT (>2 min) -> BLOCK ---
echo ""
echo "Test 6: Active task + stale CT -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 300  # 5 minutes old
INPUT=$(build_input "$PROJECT" "Let me check that file for you.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocks (stale CT)"
assert_stdout_contains "not updated in the last 2 minutes" "mentions staleness"
teardown_temp

# --- Test 7: stop_hook_active=true -> ALLOW (anti-loop) ---
echo ""
echo "Test 7: stop_hook_active=true -> ALLOW (anti-loop)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # very stale
INPUT=$(build_input "$PROJECT" "All work is done!" "true")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (anti-loop bypass)"
teardown_temp

# --- Test 7b: WAKEFUL_LISTENER env var -> unconditional ALLOW ---
echo ""
echo "Test 7b: WAKEFUL_LISTENER=true -> ALLOW (env var bypass)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
INPUT=$(build_input "$PROJECT" "All work is complete. What's next?")
# Even with completion language and stale CT, WAKEFUL_LISTENER bypasses everything
WAKEFUL_LISTENER=true run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (WAKEFUL_LISTENER env var bypass)"
teardown_temp

# --- Test 8: Sonnet listener bypass ---
echo ""
echo "Test 8: Sonnet listener session -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
INPUT=$(build_input "$PROJECT" "Watching _pending_sonnet/ for new work...")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (Sonnet listener bypass)"
teardown_temp

# --- Test 8b: Opus listener bypass (message pattern) ---
echo ""
echo "Test 8b: Opus listener session -> ALLOW (message pattern)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
INPUT=$(build_input "$PROJECT" "Opus listener active. Watching _pending_opus/ch1/ for new work...")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (Opus listener message pattern bypass)"
teardown_temp

# --- Test 8c: Heartbeat files do NOT bypass (regression guard) ---
echo ""
echo "Test 8c: Sonnet heartbeat does NOT bypass stale CT"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
mkdir -p "$PROJECT/verification_findings/_pending_sonnet/ch1"
touch "$PROJECT/verification_findings/_pending_sonnet/ch1/.heartbeat"
INPUT=$(build_input "$PROJECT" "Processing the prompt file...")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Active CT file" "blocks (sonnet heartbeat no longer bypasses)"
teardown_temp

# --- Test 8d: Opus heartbeat does NOT bypass (regression guard) ---
echo ""
echo "Test 8d: Opus heartbeat does NOT bypass stale CT"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
mkdir -p "$PROJECT/verification_findings/_pending_opus/ch2"
touch "$PROJECT/verification_findings/_pending_opus/ch2/.heartbeat"
INPUT=$(build_input "$PROJECT" "Running verification agents...")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Active CT file" "blocks (opus heartbeat no longer bypasses)"
teardown_temp

# --- Test 9: VERIFICATION_BLOCKED in CT -> ALLOW ---
echo ""
echo "Test 9: VERIFICATION_BLOCKED in active CT -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Status:** IN PROGRESS
## Notes
VERIFICATION_BLOCKED — max rounds reached, presented to user.
EOF
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "All work is complete. The sprint is done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (VERIFICATION_BLOCKED counts as evidence)"
teardown_temp

# --- Test 10: Incomplete squad (3/5 pass) -> BLOCK with details ---
echo ""
echo "Test 10: Incomplete squad (3/5 pass) -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
create_failing_squad "$PROJECT" "squad_sonnet" 2  # 2 fail, 3 pass
INPUT=$(build_input "$PROJECT" "Everything is done. Implementation complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocks (incomplete squad)"
assert_stdout_contains "INCOMPLETE VERIFICATION SQUAD" "mentions incomplete squad"
assert_stdout_contains "3/5" "shows pass count"
teardown_temp

# --- Test 11: Channel scoping — ch1 squad doesn't satisfy ch10 ---
echo ""
echo "Test 11: Channel scoping — ch1 squad does NOT satisfy ch10"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"  # shared not active
create_channel_ct "$PROJECT" "10" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK_ch10.md"
# Squad for ch1 should NOT match ch10
create_passing_squad "$PROJECT" "squad_ch1_sonnet"
INPUT=$(build_input "$PROJECT" "All tasks are done. Ready to ship.")
WAKEFUL_CHANNEL=10 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocks (ch1 squad doesn't satisfy ch10)"
teardown_temp

# --- Test 12: Waiting for agents -> ALLOW ---
echo ""
echo "Test 12: Waiting for agents -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
INPUT=$(build_input "$PROJECT" "Both agents are still running in the background. Waiting for results.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (waiting for agents bypass)"
teardown_temp

# --- Test 13: No assistant message (startup) -> ALLOW ---
echo ""
echo "Test 13: No assistant message (startup) -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
INPUT=$(build_input "$PROJECT" "")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (no message = startup)"
teardown_temp

# --- Test 14: Unchanneled session only checks shared CT, not channel CTs ---
echo ""
echo "Test 14: Unchanneled session ignores channel CTs -> only shared CT checked"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
create_channel_ct "$PROJECT" "1" "IN PROGRESS"
create_channel_ct "$PROJECT" "2" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 300   # shared CT stale
touch_aged "$PROJECT/CURRENT_TASK_ch1.md" 300
touch_now "$PROJECT/CURRENT_TASK_ch2.md"
INPUT=$(build_input "$PROJECT" "Continuing work.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
# Only shared CT reported, not ch1 or ch2
assert_stdout_contains "CURRENT_TASK.md" "blocks for stale shared CT"
teardown_temp

# --- Test 14b: Channeled session checks own channel + shared ---
echo ""
echo "Test 14b: WAKEFUL_CHANNEL=2 -> checks ch2 + shared, ignores ch1"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"  # shared not active
create_channel_ct "$PROJECT" "1" "IN PROGRESS"
create_channel_ct "$PROJECT" "2" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK_ch1.md" 300  # stale but not our channel
touch_aged "$PROJECT/CURRENT_TASK_ch2.md" 300  # stale and IS our channel
INPUT=$(build_input "$PROJECT" "Continuing work on channel 2.")
WAKEFUL_CHANNEL=2 run_hook "$INPUT"
assert_exit 0 "exit 0"
# Should only report ch2, not ch1
assert_stdout_contains "ch2" "reports own channel as stale"
teardown_temp

# --- Test 15: Phase-based activity detection -> active ---
echo ""
echo "Test 15: Phase line without 'complete' -> active -> stale CT blocks"
setup_temp
mkdir -p "$PROJECT"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Phase:** /3 Build
## Plan
- Step 1: Implement feature
EOF
touch_aged "$PROJECT/CURRENT_TASK.md" 300
INPUT=$(build_input "$PROJECT" "Continuing implementation.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Active CT file" "Phase /3 detected as active"
teardown_temp

# --- Test 15b: Phase line WITH complete -> not active -> ALLOW ---
echo ""
echo "Test 15b: Phase line with 'complete' -> not active -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Phase:** /4 Quality — complete
## Plan
- Done
EOF
touch_aged "$PROJECT/CURRENT_TASK.md" 300
INPUT=$(build_input "$PROJECT" "Reviewing results.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "Phase complete not treated as active"
teardown_temp

# --- Test 16: COMPLETE status without completion language -> ALLOW ---
echo ""
echo "Test 16: COMPLETE status + no completion language -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"
touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale but COMPLETE
INPUT=$(build_input "$PROJECT" "Reading the spec file now.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "COMPLETE status allows stop without completion language"
teardown_temp

# --- Test 17: Unchanneled squad matching (no channel prefix) -> ALLOW ---
echo ""
echo "Test 17: Unchanneled active + unchanneled squad -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
create_passing_squad "$PROJECT" "squad_sonnet"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint is complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "unchanneled squad matches unchanneled active"
teardown_temp

# --- Test 18: VERIFICATION_BLOCKED in channel CT -> ALLOW ---
echo ""
echo "Test 18: VERIFICATION_BLOCKED in channel CT -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"  # shared not active
cat > "$PROJECT/CURRENT_TASK_ch3.md" << 'EOF'
# CURRENT TASK — Channel 3
**Channel:** 3
**Status:** IN PROGRESS
## Notes
VERIFICATION_BLOCKED — max rounds reached, issues presented to user.
EOF
touch_now "$PROJECT/CURRENT_TASK_ch3.md"
INPUT=$(build_input "$PROJECT" "All tasks are done. Work is complete.")
WAKEFUL_CHANNEL=3 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "VERIFICATION_BLOCKED in channel CT counts as evidence"
teardown_temp

# --- Test 19: Multi-channel — one stale, one fresh -> reports stale only ---
echo ""
echo "Test 19: Channeled session, shared stale + own channel fresh -> blocks for shared"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
create_channel_ct "$PROJECT" "5" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 300   # shared stale
touch_now "$PROJECT/CURRENT_TASK_ch5.md"    # own channel fresh
INPUT=$(build_input "$PROJECT" "Continuing work.")
WAKEFUL_CHANNEL=5 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CURRENT_TASK.md" "reports stale shared CT"
teardown_temp

# --- Test 20: CWD fallback — empty CWD, pwd finds project ---
echo ""
echo "Test 20: Empty CWD in JSON -> falls through to pwd-based discovery"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_aged "$PROJECT/CURRENT_TASK.md" 300
# Build input with empty CWD; the hook's cd to TMPDIR_ROOT won't find CT
# but if we pass a valid CWD in JSON it should work
INPUT=$(build_input "" "Continuing work.")
# Hook runs cd'd to TMPDIR_ROOT which has no CT; empty CWD in JSON;
# only git rev-parse fallback might find something, but we're in temp dir.
# So this should ALLOW (no CT found).
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no CT found via any fallback = allow"
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
