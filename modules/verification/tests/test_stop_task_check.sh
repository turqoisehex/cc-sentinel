#!/usr/bin/env bash
# Test harness for stop-task-check.sh
# Run from repo root: bash modules/verification/tests/test_stop_task_check.sh
#
# Creates temp directories with mock CT files and squad dirs,
# pipes mock JSON stdin, asserts exit code and stdout content.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# cc-sentinel layout: tests/ and hooks/ are siblings under modules/verification/.
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/stop-task-check.sh"
# Deployed-companion layout (~/.claude/hooks/enforcement/): the test rides alongside the
# hook in the same dir, so fall back to a sibling if the cc-sentinel path is absent.
[[ -f "$HOOK_SCRIPT" ]] || HOOK_SCRIPT="$SCRIPT_DIR/stop-task-check.sh"

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

# Build JSON input with an explicit UUID session_id + transcript_path (resolver tests)
build_input_sid() {
  local cwd="$1" msg="$2" sid="$3" tpath="$4" stop_active="${5:-false}"
  local msg_json tpath_json
  msg_json=$(printf '%s' "$msg" | jq -Rs '.')
  tpath_json=$(printf '%s' "$tpath" | jq -Rs '.')
  cat << EOF
{
  "session_id": "$sid",
  "cwd": "$cwd",
  "transcript_path": $tpath_json,
  "stop_hook_active": $stop_active,
  "last_assistant_message": $msg_json,
  "hook_event_name": "Stop"
}
EOF
}

# Write a transcript file containing a genuine /opus N invocation line (CRLF-separated
# tags inside one JSON string, mirroring the wrapper CC emits — spec F3).
write_opus_transcript() {
  local file="$1" channel="$2"
  local content
  content=$(printf '<command-message>opus</command-message>\r\n<command-name>/opus</command-name>\r\n<command-args>%s</command-args>' "$channel")
  jq -nc --arg c "$content" '{type:"user", isSidechain:false, message:{role:"user", content:$c}}' > "$file"
}

# Transcript with a genuine /opus wrapper but NON-numeric/absent args (AMBIGUOUS case).
write_opus_transcript_bareargs() {
  local file="$1"
  local content
  content=$(printf '<command-message>opus</command-message>\r\n<command-name>/opus</command-name>\r\n<command-args>abc</command-args>')
  jq -nc --arg c "$content" '{type:"user", isSidechain:false, message:{role:"user", content:$c}}' > "$file"
}

# Transcript where /opus N appears ONLY inside array (tool_result) content (NOT a wrapper).
write_opus_transcript_toolresult() {
  local file="$1"
  jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:[{type:"tool_result", content:"the file says: claim via /opus 7"}]}}' > "$file"
}

# Transcript with <command-name>/opus</command-name> + <command-args>N</command-args> but NO
# <command-message>opus</command-message> wrapper — the echo/transcript-log shape the grep -a
# prefilter matches yet the F3 wrapper predicate MUST reject (spec F3). Not genuine, not PRESENCE.
write_opus_transcript_cmdname_only() {
  local file="$1" channel="$2"
  local content
  content=$(printf '<command-name>/opus</command-name>\r\n<command-args>%s</command-args>' "$channel")
  jq -nc --arg c "$content" '{type:"user", isSidechain:false, message:{role:"user", content:$c}}' > "$file"
}

# NOTE: uses a non-UUID session_id ('test-session-$$') intentionally — this trips the resolver's UUID guard so build_input-based tests exercise ONLY the pre-resolver paths. Use build_input_sid() for resolver tests.
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

# Touch a file and set its mtime to N seconds in the future (for clock-skew tests).
# Fail-loud: if all three fallback branches fail to set the mtime, exit nonzero
# so the test harness reports a real failure rather than running a recency test
# with a stale "now" mtime that silently masks a regression.
touch_future() {
  local file="$1" ahead="$2"
  touch "$file"
  local target_time
  # Branch 1: GNU date (-d relative)
  target_time=$(date -d "+${ahead} seconds" '+%Y%m%d%H%M.%S' 2>/dev/null)
  if [[ -n "$target_time" ]] && touch -t "$target_time" "$file" 2>/dev/null; then
    return 0
  fi
  # Branch 2: BSD/macOS date (-r epoch)
  local now epoch
  now=$(date +%s)
  epoch=$((now + ahead))
  target_time=$(date -r "$epoch" '+%Y%m%d%H%M.%S' 2>/dev/null) || true
  if [[ -n "$target_time" ]] && touch -t "$target_time" "$file" 2>/dev/null; then
    return 0
  fi
  # Branch 3: Python fallback (Windows Git Bash). Pass values via env so paths
  # with spaces or quotes don't break the string-interpolated Python literal.
  if FILE="$file" EPOCH="$epoch" python3 -c \
       'import os; t=int(os.environ["EPOCH"]); os.utime(os.environ["FILE"], (t, t))' \
       2>/dev/null; then
    return 0
  fi
  if FILE="$file" EPOCH="$epoch" python -c \
       'import os; t=int(os.environ["EPOCH"]); os.utime(os.environ["FILE"], (t, t))' \
       2>/dev/null; then
    return 0
  fi
  echo "    FATAL: touch_future could not set future mtime for $file (no working date or python)" >&2
  return 1
}

# Touch a file and set its mtime to N seconds ago.
# Fail-loud: if all three fallback branches fail, exit nonzero rather than
# leaving the file with current mtime (which would silently mask recency-test
# regressions).
touch_aged() {
  local file="$1" age="$2"
  touch "$file"
  local target_time
  # Branch 1: GNU date (-d relative)
  target_time=$(date -d "-${age} seconds" '+%Y%m%d%H%M.%S' 2>/dev/null)
  if [[ -n "$target_time" ]] && touch -t "$target_time" "$file" 2>/dev/null; then
    return 0
  fi
  # Branch 2: BSD/macOS date (-r epoch)
  local now epoch
  now=$(date +%s)
  epoch=$((now - age))
  target_time=$(date -r "$epoch" '+%Y%m%d%H%M.%S' 2>/dev/null) || true
  if [[ -n "$target_time" ]] && touch -t "$target_time" "$file" 2>/dev/null; then
    return 0
  fi
  # Branch 3: Python fallback. Pass values via env so paths with spaces or
  # quotes don't break the string-interpolated Python literal.
  if FILE="$file" EPOCH="$epoch" python3 -c \
       'import os; t=int(os.environ["EPOCH"]); os.utime(os.environ["FILE"], (t, t))' \
       2>/dev/null; then
    return 0
  fi
  if FILE="$file" EPOCH="$epoch" python -c \
       'import os; t=int(os.environ["EPOCH"]); os.utime(os.environ["FILE"], (t, t))' \
       2>/dev/null; then
    return 0
  fi
  echo "    FATAL: touch_aged could not set aged mtime for $file (no working date or python)" >&2
  return 1
}

# Wrapper: abort harness if mtime helpers fail (callers don't check returns
# because set -e is intentionally off — this provides the fail-loud guarantee).
must_touch_aged()   { touch_aged   "$@" || { echo "ABORT: touch_aged failed — cannot run mtime-dependent tests" >&2; exit 1; }; }
must_touch_future() { touch_future "$@" || { echo "ABORT: touch_future failed — cannot run mtime-dependent tests" >&2; exit 1; }; }

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
SENTINEL_CHANNEL=2 run_hook "$INPUT"
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
must_touch_aged "$PROJECT/CURRENT_TASK.md" 1000  # over the 900s threshold
INPUT=$(build_input "$PROJECT" "Let me check that file for you.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocks (stale CT)"
assert_stdout_contains "not updated recently" "mentions staleness"
teardown_temp

# --- Test 7: stop_hook_active=true -> ALLOW (anti-loop) ---
echo ""
echo "Test 7: stop_hook_active=true -> ALLOW (anti-loop)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 600  # very stale
INPUT=$(build_input "$PROJECT" "All work is done!" "true")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (anti-loop bypass)"
teardown_temp

# --- Test 7b: Listener env var -> unconditional ALLOW ---
echo ""
echo "Test 7b: SENTINEL_LISTENER=true -> ALLOW (env var bypass)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
INPUT=$(build_input "$PROJECT" "All work is complete. What's next?")
# Even with completion language and stale CT, listener env var bypasses everything
SENTINEL_LISTENER=true run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (listener env var bypass)"
teardown_temp

# --- Test 8: Sonnet listener bypass ---
echo ""
echo "Test 8: Sonnet listener session -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
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
must_touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
INPUT=$(build_input "$PROJECT" "Opus listener active. Watching _pending_opus/ch1/ for new work...")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (Opus listener message pattern bypass)"
teardown_temp

# --- Test 8b2: "Waiting for work on chN" listener pattern -> ALLOW ---
echo ""
echo "Test 8b2: 'Waiting for work on ch10' listener pattern -> ALLOW (multi-digit)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
# Use ch10 (multi-digit) to prove the regex handles [0-9]+, not just [0-9]
INPUT=$(build_input "$PROJECT" "Waiting for work on ch10.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (listener 'Waiting for work' pattern bypass, multi-digit)"
teardown_temp

# --- Test 8c: Heartbeat files do NOT bypass (regression guard) ---
echo ""
echo "Test 8c: Sonnet heartbeat does NOT bypass stale CT"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 1000  # over the 900s threshold
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
must_touch_aged "$PROJECT/CURRENT_TASK.md" 1000  # over the 900s threshold
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
SENTINEL_CHANNEL=10 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocks (ch1 squad doesn't satisfy ch10)"
teardown_temp

# --- Test 12: Waiting for agents -> ALLOW ---
echo ""
echo "Test 12: Waiting for agents -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale
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

# --- Test 14: Unchanneled STALENESS check skips channel CTs (only shared CT can be reported) ---
# NOTE: TASK_FILES still globs ALL channel CTs for an unchanneled session (so Check 1 sees every
# VERIFICATION_BLOCKED); it is specifically the CHECK 2 *staleness* guard that skips channel CTs.
echo ""
echo "Test 14: Unchanneled staleness -> channel CTs skipped, only shared CT reported (CHECK 2 guard)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
create_channel_ct "$PROJECT" "1" "IN PROGRESS"
create_channel_ct "$PROJECT" "2" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 1000   # shared CT stale (over 900s)
must_touch_aged "$PROJECT/CURRENT_TASK_ch1.md" 1000
touch_now "$PROJECT/CURRENT_TASK_ch2.md"
INPUT=$(build_input "$PROJECT" "Continuing work.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
# Staleness reports ONLY the shared CT: the CHECK 2 guard skips ch1/ch2 for an unchanneled
# session (even though ch1 is also aged). Contrast Test 14b (channeled = own channel only).
assert_stdout_contains "CURRENT_TASK.md" "unchanneled staleness reports shared CT; channel CTs skipped by the CHECK 2 guard"
teardown_temp

# --- Test 14b: Channeled session checks own channel + shared ---
echo ""
echo "Test 14b: SENTINEL_CHANNEL=2 -> checks ch2 + shared, ignores ch1"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"  # shared not active
create_channel_ct "$PROJECT" "1" "IN PROGRESS"
create_channel_ct "$PROJECT" "2" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK_ch1.md" 1000  # stale but not our channel
must_touch_aged "$PROJECT/CURRENT_TASK_ch2.md" 1000  # stale and IS our channel (over 900s)
INPUT=$(build_input "$PROJECT" "Continuing work on channel 2.")
SENTINEL_CHANNEL=2 run_hook "$INPUT"
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
must_touch_aged "$PROJECT/CURRENT_TASK.md" 1000
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
must_touch_aged "$PROJECT/CURRENT_TASK.md" 300
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
must_touch_aged "$PROJECT/CURRENT_TASK.md" 600  # stale but COMPLETE
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
SENTINEL_CHANNEL=3 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "VERIFICATION_BLOCKED in channel CT counts as evidence"
teardown_temp

# --- Test 19: Channeled session skips shared CT staleness (owns channel CT only) ---
echo ""
echo "Test 19: Channeled session, shared stale + own channel fresh -> allows (shared skipped)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
create_channel_ct "$PROJECT" "5" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 300   # shared stale
touch_now "$PROJECT/CURRENT_TASK_ch5.md"    # own channel fresh
INPUT=$(build_input "$PROJECT" "Continuing work.")
SENTINEL_CHANNEL=5 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "channeled session skips shared CT staleness"
teardown_temp

# --- Test 20: CWD fallback — empty CWD, pwd finds project ---
echo ""
echo "Test 20: Empty CWD in JSON -> falls through to pwd-based discovery"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK.md" 300
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

# --- Test 21: COMPLETE status + completion language -> BLOCK (no active files for verification) ---
echo ""
echo "Test 21: COMPLETE + completion language -> BLOCK (anti-loop allows 2nd stop)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"
touch_now "$PROJECT/CURRENT_TASK.md"
create_passing_squad "$PROJECT"
INPUT=$(build_input "$PROJECT" "All work is complete. What's next?")
run_hook "$INPUT"
assert_exit 0 "exit 0"
# COMPLETE = not active, so ACTIVE_FILES is empty, no squad can match
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "blocks (COMPLETE has no active files for verification)"
teardown_temp

# --- Test 22: VERIFICATION_PASSED is NOT accepted (self-attestation rejection) ---
echo ""
echo "Test 22: VERIFICATION_PASSED in CT does NOT satisfy verification gate"
setup_temp
mkdir -p "$PROJECT"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Status:** IN PROGRESS
## Notes
VERIFICATION_PASSED — all agents passed.
EOF
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint is done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "VERIFICATION_PASSED is not accepted as evidence"
teardown_temp

# --- Test 23: Malformed CT (no Status or Phase line) -> ALLOW (fail-open) ---
echo ""
echo "Test 23: Malformed CT (no Status/Phase) -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
Some notes here but no Status or Phase header.
## Plan
- Step 1: Do something
EOF
must_touch_aged "$PROJECT/CURRENT_TASK.md" 300
INPUT=$(build_input "$PROJECT" "All work is done. Sprint is complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "malformed CT = no active task detected = allow"
teardown_temp

# --- Test 24: Two squad dirs — first incomplete blocks even if second passes ---
echo ""
echo "Test 24: Two squad dirs — first incomplete blocks despite second passing"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# First squad dir (alphabetically): incomplete
create_failing_squad "$PROJECT" "squad_a_old" 3  # 2 pass, 3 fail
# Second squad dir (alphabetically): all pass
create_passing_squad "$PROJECT" "squad_b_new"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint is complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "first incomplete squad blocks"
assert_stdout_contains "squad_a_old" "identifies the blocking squad dir"
teardown_temp

# --- Test 25: Squad with missing agent files vs failed verdicts -> distinct error messages ---
echo ""
echo "Test 25a: Squad with missing agent files -> reports 'Missing'"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# Create squad with only 3 of 5 agents (2 missing: dependency, cold_reader)
PARTIAL_SQUAD="$PROJECT/verification_findings/squad_sonnet"
mkdir -p "$PARTIAL_SQUAD"
echo "VERDICT: PASS" > "$PARTIAL_SQUAD/mechanical.md"
echo "VERDICT: PASS" > "$PARTIAL_SQUAD/adversarial.md"
echo "VERDICT: PASS" > "$PARTIAL_SQUAD/completeness.md"
# dependency.md and cold_reader.md missing
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Missing:" "reports missing agents"
assert_stdout_contains "3/5" "shows 3 of 5 passed"
teardown_temp

echo ""
echo "Test 25b: Squad with failed verdicts -> reports 'Failed'"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# Create squad with all 5 present but 2 have FAIL verdicts
FAIL_SQUAD="$PROJECT/verification_findings/squad_sonnet"
mkdir -p "$FAIL_SQUAD"
echo "VERDICT: PASS" > "$FAIL_SQUAD/mechanical.md"
echo "VERDICT: PASS" > "$FAIL_SQUAD/adversarial.md"
echo "VERDICT: PASS" > "$FAIL_SQUAD/completeness.md"
echo "VERDICT: FAIL (3 issues)" > "$FAIL_SQUAD/dependency.md"
echo "VERDICT: FAIL (1 issue)" > "$FAIL_SQUAD/cold_reader.md"
INPUT=$(build_input "$PROJECT" "Everything is done. Implementation complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "Failed" "reports failed agents"
assert_stdout_contains "3/5" "shows 3 of 5 passed"
teardown_temp

# Note: the original Tests 28-29 (manifest-related) were renamed to the T_manifest_* series
# below; Tests 28-29 are now repurposed as R7 deferral sub-pattern tests (further below).

# --- Test T_all_done: "ALL DONE" status treated as complete ---
echo ""
echo "Test T_all_done: ALL DONE status -> complete (not active)"
setup_temp
mkdir -p "$PROJECT"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Status:** ALL DONE — sprint finalized.
**Phase:** /5 complete
EOF
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Session cleanup finished.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "ALL DONE = complete, no block"
teardown_temp

# --- Test T_manifest_valid: manifest.json with 2 listed agents -> uses 2-agent squad ---
echo ""
echo "Test T_manifest_valid: manifest.json valid -> 2-agent squad satisfies gate"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# Create manifest-filtered squad: only mechanical + cold_reader
MANI_SQUAD="$PROJECT/verification_findings/squad_sonnet"
mkdir -p "$MANI_SQUAD"
echo "VERDICT: PASS" > "$MANI_SQUAD/mechanical.md"
echo "VERDICT: PASS" > "$MANI_SQUAD/cold_reader.md"
printf '{"launched":["mechanical.md","cold_reader.md"],"reason":"docs only","timestamp":"2026-01-01T00:00:00Z"}' > "$MANI_SQUAD/manifest.json"
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (manifest 2-agent squad satisfies gate)"
teardown_temp

# --- Test T_manifest_invalid_json: invalid JSON in manifest.json -> falls through to default ---
echo ""
echo "Test T_manifest_invalid_json: invalid manifest.json -> falls through to default (all 5)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# Create squad with all 5 agents (default), plus bad manifest
create_passing_squad "$PROJECT" "squad_sonnet"
printf '{invalid' > "$PROJECT/verification_findings/squad_sonnet/manifest.json"
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (invalid manifest falls back to default 5)"
teardown_temp

# --- Test T_manifest_empty: empty launched array -> falls through to default ---
echo ""
echo "Test T_manifest_empty: empty launched[] -> falls through to default (all 5)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# Create squad with all 5 agents, plus empty manifest
create_passing_squad "$PROJECT" "squad_sonnet"
printf '{"launched":[]}' > "$PROJECT/verification_findings/squad_sonnet/manifest.json"
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (empty launched falls back to default 5)"
teardown_temp

# --- Test T_manifest_absent: no manifest.json -> uses default 5 agents ---
echo ""
echo "Test T_manifest_absent: no manifest.json -> uses default 5 agents"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
create_passing_squad "$PROJECT" "squad_sonnet"
# No manifest.json — just the 5 agent files
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (no manifest uses default 5)"
teardown_temp

# --- Test T_manifest_sonnet_prefixed_allow: sonnet_-prefixed manifest entries + matching files -> ALLOW ---
# Characterizes the hook's exact-string match: manifest says "sonnet_mechanical.md" and the
# file IS "sonnet_mechanical.md" -> the entry is satisfied and the gate passes.
echo ""
echo "Test T_manifest_sonnet_prefixed_allow: sonnet_-prefixed launched[] with matching sonnet_*.md files -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
MANI_SQUAD="$PROJECT/verification_findings/squad_sonnet"
mkdir -p "$MANI_SQUAD"
# Write sonnet_-prefixed squad files INLINE (do NOT use create_passing_squad — it writes unprefixed names)
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_mechanical.md"
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_adversarial.md"
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_completeness.md"
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_dependency.md"
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_cold_reader.md"
printf '{"launched":["sonnet_mechanical.md","sonnet_adversarial.md","sonnet_completeness.md","sonnet_dependency.md","sonnet_cold_reader.md"],"reason":"sonnet prefix","timestamp":"2026-01-01T00:00:00Z"}' > "$MANI_SQUAD/manifest.json"
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no block (sonnet_-prefixed manifest + matching files satisfies gate)"
teardown_temp

# --- Test T_manifest_sonnet_prefixed_block_when_missing: manifest says sonnet_*.md but only unprefixed files exist -> BLOCK ---
# Exact-string match means "sonnet_mechanical.md" in launched[] is NOT satisfied by "mechanical.md" on disk.
echo ""
echo "Test T_manifest_sonnet_prefixed_block_when_missing: manifest launched sonnet_*.md but only unprefixed mechanical.md exists -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
MANI_SQUAD="$PROJECT/verification_findings/squad_sonnet"
mkdir -p "$MANI_SQUAD"
# Manifest declares sonnet_-prefixed names; only the UNprefixed file is present
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/mechanical.md"
printf '{"launched":["sonnet_mechanical.md","sonnet_adversarial.md","sonnet_completeness.md","sonnet_dependency.md","sonnet_cold_reader.md"],"reason":"sonnet prefix","timestamp":"2026-01-01T00:00:00Z"}' > "$MANI_SQUAD/manifest.json"
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocked (sonnet_mechanical.md not satisfied by mechanical.md)"
teardown_temp

# --- Test T_manifest_unprefixed_block_when_only_sonnet: manifest says unprefixed names but only sonnet_*.md files exist -> BLOCK ---
# Mirror case: manifest says "mechanical.md" but file is "sonnet_mechanical.md" -> not satisfied.
echo ""
echo "Test T_manifest_unprefixed_block_when_only_sonnet: manifest launched unprefixed names but only sonnet_*.md files exist -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
MANI_SQUAD="$PROJECT/verification_findings/squad_sonnet"
mkdir -p "$MANI_SQUAD"
# Only sonnet_-prefixed files exist; manifest declares unprefixed names
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_mechanical.md"
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_adversarial.md"
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_completeness.md"
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_dependency.md"
printf 'VERDICT: PASS\n' > "$MANI_SQUAD/sonnet_cold_reader.md"
printf '{"launched":["mechanical.md","adversarial.md","completeness.md","dependency.md","cold_reader.md"],"reason":"unprefixed","timestamp":"2026-01-01T00:00:00Z"}' > "$MANI_SQUAD/manifest.json"
INPUT=$(build_input "$PROJECT" "All work is complete. Sprint done.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "blocked (mechanical.md not satisfied by sonnet_mechanical.md)"
teardown_temp

# --- Test 26: AWAITING is parked (not active) — no staleness block ---
# AWAITING USER APPROVAL means the assistant has done its part and is waiting
# on a human; forcing a staleness block would create false alarms when the
# user takes hours/days to review. Hook intentionally treats AWAITING as
# complete-equivalent (see hook line ~130).
echo ""
echo "Test 26: AWAITING USER APPROVAL status -> parked, not stale-blocked"
setup_temp
mkdir -p "$PROJECT"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Status:** AWAITING USER APPROVAL — Design spec + implementation plan complete.
**Phase:** /2 complete → /3 pending approval
EOF
must_touch_aged "$PROJECT/CURRENT_TASK.md" 300
INPUT=$(build_input "$PROJECT" "Continuing work on the design.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "AWAITING is parked — staleness does not block"
teardown_temp

# --- Test 27: Deferral language in assistant message -> BLOCK ---
echo ""
echo "Test 27: Deferral language -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# Fresh CT, no completion language, but deferred items in message
INPUT=$(build_input "$PROJECT" "Done with the build. Deferred deployment items: 1. Run installer 2. Update config")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains '"decision".*"block"' "deferral language blocked"
assert_stdout_contains "DEFERRAL" "reason identifies deferral"
teardown_temp

# --- Test 28: Deferral with "future sprint" (IN PROGRESS, no completion language) -> R7 BLOCK ---
# Uses IN PROGRESS status and NO completion language so R1 is not reached — pure R7 test.
echo ""
echo "Test 28: 'future sprint' deferral (R7 path) -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Finished reviewing. Some items can wait for a future sprint.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "future sprint triggers R7 deferral gate"
teardown_temp

# --- Test 29: No deferral language -> ALLOW ---
echo ""
echo "Test 29: No deferral language -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Updated the config file. Looks good.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no deferral = no block"
teardown_temp

# --- Test 30: Positive channel path (SENTINEL_CHANNEL + matching squad_chN_) ---
echo ""
echo "Test 30: SENTINEL_CHANNEL=2 + squad_ch2_sonnet (all PASS) -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
echo '**Channel:** 2' >> "$PROJECT/CURRENT_TASK_ch2.md"
echo '**Status:** IN PROGRESS' >> "$PROJECT/CURRENT_TASK_ch2.md"
touch_now "$PROJECT/CURRENT_TASK.md"
touch_now "$PROJECT/CURRENT_TASK_ch2.md"
create_passing_squad "$PROJECT" "squad_ch2_sonnet"
INPUT=$(build_input "$PROJECT" "All done. Sprint complete.")
SENTINEL_CHANNEL=2 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "channel-scoped squad satisfies gate"
teardown_temp

# --- Test 31: Cross-channel VERIFICATION_BLOCKED isolation ---
echo ""
echo "Test 31: VERIFICATION_BLOCKED in ch3 CT does not satisfy ch2 gate"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
echo '**Channel:** 2' >> "$PROJECT/CURRENT_TASK_ch2.md"
echo '**Status:** IN PROGRESS' >> "$PROJECT/CURRENT_TASK_ch2.md"
touch_now "$PROJECT/CURRENT_TASK.md"
touch_now "$PROJECT/CURRENT_TASK_ch2.md"
# VERIFICATION_BLOCKED in ch3 (not our channel)
cat > "$PROJECT/CURRENT_TASK_ch3.md" << 'EOF'
**Channel:** 3
**Status:** IN PROGRESS
VERIFICATION_BLOCKED — issues remain
EOF
INPUT=$(build_input "$PROJECT" "Sprint is complete and verified.")
SENTINEL_CHANNEL=2 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "ch3 BLOCKED doesn't help ch2"
teardown_temp

# --- Test 32: Invalid JSON stdin -> fail-open ---
echo ""
echo "Test 32: Invalid JSON input -> exit 0 (fail-open)"
setup_temp
mkdir -p "$PROJECT"
INPUT="this is not json at all {{{}"
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "invalid JSON = fail-open allow"
teardown_temp

# --- R7 deferral sub-pattern coverage ---
echo ""
echo "Test 33: 'later sprint' -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "We can handle that in a later sprint.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "later sprint triggers R7"
teardown_temp

echo ""
echo "Test 34: 'next sprint' -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Moving this to the next sprint.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "next sprint triggers R7"
teardown_temp

echo ""
echo "Test 35: 'handle this later' -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Let's handle this later when we have more context.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "handle this later triggers R7"
teardown_temp

echo ""
echo "Test 40: 'address this later' -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "We should address this later in a focused session.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "address this later triggers R7"
teardown_temp

echo ""
echo "Test 41: 'out of scope for now' -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "That feature is out of scope for now.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "out of scope for now triggers R7"
teardown_temp

echo ""
echo "Test 42: 'separate session needed' -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "A separate session needed for the deployment steps.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "separate session needed triggers R7"
teardown_temp

echo ""
echo "Test 43: 'deferred to next week' -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Deferred to next week when the API is ready.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "deferred to triggers R7"
teardown_temp

echo ""
echo "Test 44: 'deferred as low priority' -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Deferred as low priority for this sprint.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "deferred as triggers R7"
teardown_temp

# --- Tests 45-48: Responsibility deflection patterns (mirrors DEFLECT cluster) ---
echo ""
echo "Test 45: 'pre-existing failure' -> BLOCK (DEFLECT)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Test 26 is a pre-existing failure, not introduced by my changes.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "pre-existing triggers R7 deflection"
teardown_temp

echo ""
echo "Test 46: 'preexisting' (no hyphen) -> BLOCK (DEFLECT)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "That's a preexisting issue I won't touch.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "preexisting variant triggers R7"
teardown_temp

echo ""
echo "Test 47: 'known issue' -> BLOCK (DEFLECT)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "That's a known issue from before this sprint.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "known issue triggers R7"
teardown_temp

echo ""
echo "Test 48: 'outside current scope' -> BLOCK (DEFLECT)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "That bug is outside current scope.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "outside current scope triggers R7"
teardown_temp

# ==================== COMMIT-PAIR R1 EVIDENCE (Check 1.5) ====================
# Pair = commit-adversarial + commit-cold-reader output, written by
# channel_commit.sh --local-verify before a commit lands. If their verdicts are
# recent (default 900s), they satisfy R1 as alternative evidence to the full
# 5-agent squad. Channel-scoped via filename suffix.
#
# ENV-VAR COVERAGE NOTE:
# Canonical cc-sentinel hook reads SENTINEL_CHANNEL only. Deployed Wakeful mirror
# resolves HOOK_CHANNEL="${SENTINEL_CHANNEL:-${WAKEFUL_CHANNEL:-}}", adding
# WAKEFUL_CHANNEL as a project-aware fallback. The Wakeful-specific fallback is
# NOT exercised by this canonical test suite by design — both env vars feed the
# same HOOK_CHANNEL value via mechanically equivalent bash parameter expansion,
# and the env-precedence tests (T-resolve-2 env>transcript, AC-7 env>registry)
# cover the env-wins behavior using SENTINEL_CHANNEL. WAKEFUL_CHANNEL is
# intentionally out-of-scope for cc-sentinel canonical tests.

# --- Test T-pair-1: Channeled session + fresh passing pair -> ALLOW ---
echo ""
echo "Test T-pair-1: Channeled passing pair -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"  # shared not active
create_channel_ct "$PROJECT" "2" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK_ch2.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch2.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch2.md"
touch_now "$PROJECT/verification_findings/commit_check_ch2.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch2.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
SENTINEL_CHANNEL=2 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "channeled pair satisfies R1"
teardown_temp

# --- Test T-pair-2: Unchanneled session + fresh passing pair -> ALLOW ---
echo ""
echo "Test T-pair-2: Unchanneled passing pair -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: WARN (1 minor)" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "unchanneled pair satisfies R1 (PASS+WARN)"
teardown_temp

# --- Test T-pair-3: Stale pair (>900s) -> BLOCK ---
echo ""
echo "Test T-pair-3: Stale pair (aged 1200s, window 900s) -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
must_touch_aged "$PROJECT/verification_findings/commit_check.md" 1200
must_touch_aged "$PROJECT/verification_findings/commit_cold_read.md" 1200
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "stale pair does not satisfy R1"
teardown_temp

# --- Test T-pair-4: FAIL verdict in pair -> BLOCK ---
echo ""
echo "Test T-pair-4: Pair with FAIL verdict -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: FAIL (3 issues)" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "FAIL verdict does not satisfy R1"
assert_stdout_contains "commit_check.md" "A4: block reason names the failing pair file"
teardown_temp

# --- Test T-pair-5: Half-pair (only commit_check) -> BLOCK ---
echo ""
echo "Test T-pair-5: Only commit_check.md present, no commit_cold_read.md -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
# commit_cold_read.md deliberately absent
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "half-pair does not satisfy R1"
teardown_temp

# --- Test T-pair-6: Cross-channel isolation — ch3 pair does not satisfy ch2 gate ---
echo ""
echo "Test T-pair-6: ch3 pair files do not satisfy ch2 session -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"
create_channel_ct "$PROJECT" "2" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK_ch2.md"
# Pair at ch3, not ch2
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch3.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch3.md"
touch_now "$PROJECT/verification_findings/commit_check_ch3.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch3.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
SENTINEL_CHANNEL=2 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "ch3 pair does not leak to ch2"
teardown_temp

# --- Test T-pair-7: Pair + passing squad both present -> ALLOW ---
echo ""
echo "Test T-pair-7: Valid pair + valid squad both present -> ALLOW (either suffices)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
create_passing_squad "$PROJECT" "squad_sonnet"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "either evidence path satisfies R1"
teardown_temp

# --- Test T-pair-8: SENTINEL_COMMIT_RECENCY_SEC=30 override -> BLOCK on 60s pair ---
echo ""
echo "Test T-pair-8: Recency override (30s window) + 60s-aged pair -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
must_touch_aged "$PROJECT/verification_findings/commit_check.md" 60
must_touch_aged "$PROJECT/verification_findings/commit_cold_read.md" 60
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
SENTINEL_COMMIT_RECENCY_SEC=30 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "override tightens window"
teardown_temp

# --- Test T-pair-9: Boundary — age near window -> ALLOW ---
# Tests the -le inclusivity of the pair recency check. Setting age = window - 2
# (198s set, 200s window) exercises near-boundary; the 2s buffer absorbs test
# execution latency (touch_aged → hook run). A regression from -le to -lt
# would only matter at exact equality, which is not reliably testable without
# freezing time, but this still proves the pair path accepts ages within window.
echo ""
echo "Test T-pair-9: Custom window 200s + 198s-aged pair -> ALLOW (near-boundary -le)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
must_touch_aged "$PROJECT/verification_findings/commit_check.md" 198
must_touch_aged "$PROJECT/verification_findings/commit_cold_read.md" 198
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
SENTINEL_COMMIT_RECENCY_SEC=200 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "age within configured window satisfies R1 (-le boundary)"
teardown_temp

# --- Test T-pair-10: Stat failure (fail-closed via H1 guard) -> BLOCK ---
# Override `stat` in PATH so mtime reads fail (echo 0 fallback fires).
# H1 guard requires NOW>0 && CHECK_MTIME>0 && COLD_MTIME>0 — any zero
# short-circuits the recency comparison and leaves VERIFICATION_FOUND false.
echo ""
echo "Test T-pair-10: Pair stat failure (H1 fail-closed guard) -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "COMPLETE"  # COMPLETE so staleness check skipped (uses stat too)
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
# Install stat shim that always fails — exercises echo-0 fallback + H1 guard
mkdir -p "$TMPDIR_ROOT/stub_bin"
cat > "$TMPDIR_ROOT/stub_bin/stat" << 'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$TMPDIR_ROOT/stub_bin/stat"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
PATH="$TMPDIR_ROOT/stub_bin:$PATH" run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "broken stat = fail-closed (H1 guard) = no ALLOW"
teardown_temp

# --- Test T-pair-11: Empty pair files (no VERDICT line) -> BLOCK ---
echo ""
echo "Test T-pair-11: Pair files exist but contain no VERDICT line -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
> "$PROJECT/verification_findings/commit_check.md"
> "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "empty pair files do not satisfy R1"
teardown_temp

# --- Test T-pair-12: VERIFICATION_BLOCKED + pair both present -> ALLOW (Check 1 wins) ---
echo ""
echo "Test T-pair-12: VERIFICATION_BLOCKED in CT + valid pair -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Status:** IN PROGRESS
## Notes
VERIFICATION_BLOCKED — max rounds reached.
EOF
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "VERIFICATION_BLOCKED satisfies R1 ahead of pair check"
teardown_temp

# --- Test T-pair-13: H3 fix — partial squad + valid pair -> ALLOW ---
echo ""
echo "Test T-pair-13: Partial (incomplete) squad + valid pair -> ALLOW (H3 fix)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
# Stale partial squad — 2 of 5 agents pass
create_failing_squad "$PROJECT" "squad_sonnet" 3
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "H3: pair preempts partial-squad block"
teardown_temp

# --- Test T-pair-14: Unchanneled session ignores channeled pair -> BLOCK ---
echo ""
echo "Test T-pair-14: Unchanneled session + ch2-suffixed pair only -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch2.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch2.md"
touch_now "$PROJECT/verification_findings/commit_check_ch2.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch2.md"
# No unchanneled commit_check.md / commit_cold_read.md
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "channeled pair does not satisfy unchanneled session"
teardown_temp

# --- Test T-pair-21: Future-dated pair files (negative age, clock skew) -> BLOCK ---
# Exercises the negative-age fail-closed guard on the commit-pair files themselves.
# Bash -le treats negative ages as "within window"; without the -ge 0 guard
# on CHECK_AGE/COLD_AGE a future-dated pair would silently satisfy R1.
echo ""
echo "Test T-pair-21: Channel env=2 + future-dated ch2 pair PASS -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch2.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch2.md"
must_touch_future "$PROJECT/verification_findings/commit_check_ch2.md" 120
must_touch_future "$PROJECT/verification_findings/commit_cold_read_ch2.md" 120
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
SENTINEL_CHANNEL=2 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "future-dated pair files rejected (negative age)"
teardown_temp

# --- Test T-parsed-1: multiline completion message still triggers R1 (sed-index regression) ---
echo ""
echo "Test T-parsed-1: multiline message with completion phrase on a later line -> BLOCK (R1)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "Here is a summary of the changes.
I touched three files and updated the docs.
All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "multiline completion (line 3) still triggers R1 after sed-index move"
teardown_temp

# --- Test T-parsed-2: multiline deferral message still triggers R7 (sed-index regression) ---
echo ""
echo "Test T-parsed-2: multiline message with deferral phrase on a later line -> BLOCK (R7)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
INPUT=$(build_input "$PROJECT" "I made the requested edits.
The build is green.
I am leaving the flaky test for a future sprint.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "DEFERRAL" "multiline deferral (line 3) still triggers R7 after sed-index move"
teardown_temp

# --- Test T-resolve-1: transcript /opus 3 resolves channel (no env) -> ALLOW via ch3 pair ---
echo ""
echo "Test T-resolve-1: no env + transcript /opus 3 + ch3 pair PASS -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch3.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch3.md"
touch_now "$PROJECT/verification_findings/commit_check_ch3.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch3.md"
SID="11111111-1111-1111-1111-111111111111"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" 3
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "transcript resolves ch3; ch3 pair satisfies R1"
teardown_temp

# --- Test T-resolve-2: env precedence wins + logs disagreement ---
echo ""
echo "Test T-resolve-2: SENTINEL_CHANNEL=5 + transcript /opus 3 + ch5 pair PASS -> ALLOW (env wins)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch5.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch5.md"
touch_now "$PROJECT/verification_findings/commit_check_ch5.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch5.md"
SID="22222222-2222-2222-2222-222222222222"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" 3
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
SENTINEL_CHANNEL=5 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "env ch5 wins over transcript ch3; ch5 pair satisfies"
teardown_temp

# --- Test T-resolve-3: CRLF-embedded /opus 4 line -> resolves bare 4 ---
echo ""
echo "Test T-resolve-3: transcript /opus 4 with CRLF in args -> resolves bare 4"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch4.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch4.md"
touch_now "$PROJECT/verification_findings/commit_check_ch4.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch4.md"
SID="33333333-3333-3333-3333-333333333333"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" 4
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "CRLF /opus 4 resolves to bare 4 (ch4 pair satisfies)"
teardown_temp

# --- Test T-resolve-4: registry fallback when transcript has no /opus ---
echo ""
echo "Test T-resolve-4: no env + transcript without /opus + registry=6 + ch6 pair PASS -> ALLOW"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch6.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch6.md"
touch_now "$PROJECT/verification_findings/commit_check_ch6.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch6.md"
SID="44444444-4444-4444-4444-444444444444"
jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:"just a normal prompt"}}' > "$TMPDIR_ROOT/$SID.jsonl"
mkdir -p "$PROJECT/verification_findings/.session_channel"
printf '6' > "$PROJECT/verification_findings/.session_channel/$SID"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "registry=6 resolves when transcript yields no /opus; ch6 pair satisfies"
teardown_temp

# --- Test T-resolve-5: garbage SID -> skip registry/transcript entirely ---
echo ""
echo "Test T-resolve-5: garbage (non-UUID) session_id + transcript /opus 3 -> NOT channeled (skipped)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch3.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch3.md"
touch_now "$PROJECT/verification_findings/commit_check_ch3.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch3.md"
write_opus_transcript "$TMPDIR_ROOT/not-a-uuid.jsonl" 3
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "not-a-uuid" "$TMPDIR_ROOT/not-a-uuid.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "garbage SID skips transcript/registry; ch3 pair NOT credited"
teardown_temp

# --- Test AC-8: PRESENCE witnessed (bare-args wrapper) + completion -> FAIL CLOSED ---
echo ""
echo "Test AC-8: genuine /opus wrapper with non-numeric args + completion -> BLOCK (fail closed)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
SID="55555555-5555-5555-5555-555555555555"
write_opus_transcript_bareargs "$TMPDIR_ROOT/$SID.jsonl"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT RESOLVED CHANNEL" "AC-8: PRESENCE + no valid N + completion -> deliberate fail closed"
teardown_temp

# --- Test N1/N2: /opus 7 only in tool_result array content + completion -> NOT fail-closed ---
echo ""
echo "Test N1/N2: /opus 7 quoted in tool_result (array content), not a wrapper + completion -> ordinary R1 block (not fail-closed)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
SID="66666666-6666-6666-6666-666666666666"
write_opus_transcript_toolresult "$TMPDIR_ROOT/$SID.jsonl"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "N1/N2: array-content /opus is NOT PRESENCE; parent glob-all, ordinary R1 block"
teardown_temp

# --- Test T-conservative-1: garbage registry + top-level pair PASS + completion -> fail-closed, NOT top-level-pair ALLOW ---
echo ""
echo "Test T-conservative-1: registry='xyz' (PRESENCE) + top-level pair PASS + completion -> BLOCK (does not read top-level pair)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
SID="77777777-7777-7777-7777-777777777777"
jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:"normal prompt, no opus"}}' > "$TMPDIR_ROOT/$SID.jsonl"
mkdir -p "$PROJECT/verification_findings/.session_channel"
printf 'xyz' > "$PROJECT/verification_findings/.session_channel/$SID"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT RESOLVED CHANNEL" "garbage registry = PRESENCE; fail-closed, does NOT read top-level pair"
teardown_temp

# --- Test T-stale-1: channeled own CT aged 200s -> ALLOW under 900s threshold ---
# NOTE: message must NOT match COMPLETION_PATTERNS (else Check 1 blocks before staleness).
echo ""
echo "Test T-stale-1: SENTINEL_CHANNEL=4 + own CURRENT_TASK_ch4.md aged 200s -> ALLOW (under 900s)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "DONE"
create_channel_ct "$PROJECT" 4 "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK_ch4.md" 200
INPUT=$(build_input "$PROJECT" "Inspecting the current state of the files.")
SENTINEL_CHANNEL=4 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "own CT aged 200s is fresh under the 900s threshold"
teardown_temp

# --- Test T-stale-2: channeled own CT aged 1000s -> BLOCK (over 900s) ---
echo ""
echo "Test T-stale-2: SENTINEL_CHANNEL=4 + own CURRENT_TASK_ch4.md aged 1000s -> BLOCK (over 900s)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "DONE"
create_channel_ct "$PROJECT" 4 "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK_ch4.md" 1000
INPUT=$(build_input "$PROJECT" "Inspecting the current state of the files.")
SENTINEL_CHANNEL=4 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "not updated recently" "own CT aged 1000s is stale over the 900s threshold"
teardown_temp

# --- Test T-prewarm-1: SessionStart source=resume re-derives + writes cache ---
echo ""
echo "Test T-prewarm-1: SessionStart(resume) + transcript /opus 3 -> cache .session_channel/<sid> == 3"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
SID="88888888-8888-8888-8888-888888888888"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" 3
ORIENT_SCRIPT="$(cd "$SCRIPT_DIR/../../.." && pwd)/modules/core/hooks/session-orient.sh"
[[ -f "$ORIENT_SCRIPT" ]] || ORIENT_SCRIPT="$SCRIPT_DIR/session-orient.sh"  # deployed-companion layout
ORIENT_INPUT=$(cat << EOF
{"session_id":"$SID","cwd":"$PROJECT","source":"resume","transcript_path":"$TMPDIR_ROOT/$SID.jsonl","hook_event_name":"SessionStart"}
EOF
)
echo "$ORIENT_INPUT" | (cd "$TMPDIR_ROOT" && bash "$ORIENT_SCRIPT") > /dev/null 2>&1
TOTAL=$((TOTAL + 1))
if [[ -f "$PROJECT/verification_findings/.session_channel/$SID" ]] \
   && [[ "$(cat "$PROJECT/verification_findings/.session_channel/$SID")" == "3" ]]; then
  echo -e "  ${GREEN}PASS${NC}: prewarm wrote cache=3 on resume"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: prewarm did not write cache=3"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test AC-7: env channel wins over registry, disagreement logged ---
echo ""
echo "Test AC-7: SENTINEL_CHANNEL=5 + registry=3 + ch5 pair PASS -> ALLOW (env wins over registry)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch5.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch5.md"
touch_now "$PROJECT/verification_findings/commit_check_ch5.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch5.md"
SID="99999999-9999-9999-9999-999999999999"
jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:"normal prompt"}}' > "$TMPDIR_ROOT/$SID.jsonl"
mkdir -p "$PROJECT/verification_findings/.session_channel"
printf '3' > "$PROJECT/verification_findings/.session_channel/$SID"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
SENTINEL_CHANNEL=5 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "env ch5 wins over registry ch3; ch5 pair satisfies R1"
teardown_temp

# --- Test T-resolve-6: <command-name>-only echo (no <command-message> wrapper) -> filter rejects, NOT channeled ---
# Proves the F3 <command-message>opus</command-message> wrapper predicate is load-bearing: without it,
# a transcript-log echo of "<command-name>/opus</command-name>" would falsely resolve the channel.
echo ""
echo "Test T-resolve-6: <command-name>/opus 3</command-name> WITHOUT <command-message> wrapper + ch3 pair + completion -> BLOCK (echo rejected, ch3 pair NOT credited)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch3.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch3.md"
touch_now "$PROJECT/verification_findings/commit_check_ch3.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch3.md"
SID="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
write_opus_transcript_cmdname_only "$TMPDIR_ROOT/$SID.jsonl" 3
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "cmdname-only echo is NOT a genuine wrapper; filter + presence both reject; ch3 pair NOT credited; not fail-closed"
teardown_temp

# --- Test T-resolve-7: leading zero normalised (04 -> 4) + ch4 pair -> ALLOW ---
echo ""
echo "Test T-resolve-7: /opus 04 (leading zero) + ch4 pair PASS -> ALLOW (normalised to 4)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch4.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch4.md"
touch_now "$PROJECT/verification_findings/commit_check_ch4.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch4.md"
SID="cccccccc-cccc-cccc-cccc-cccccccccccc"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" "04"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "04 normalises to 4; ch4 pair satisfies R1"
teardown_temp

# --- Test T-resolve-8: last-adoption-wins (/opus 3 then /opus 5 -> resolves 5) + ch5 pair -> ALLOW ---
echo ""
echo "Test T-resolve-8: /opus 3 then /opus 5 (tail-1) + ch5 pair PASS -> ALLOW (last-adoption-wins)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch5.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch5.md"
touch_now "$PROJECT/verification_findings/commit_check_ch5.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch5.md"
SID="dddddddd-dddd-dddd-dddd-dddddddddddd"
TR="$TMPDIR_ROOT/$SID.jsonl"
write_opus_transcript "$TR" 3
content=$(printf '<command-message>opus</command-message>\r\n<command-name>/opus</command-name>\r\n<command-args>5</command-args>')
jq -nc --arg c "$content" '{type:"user", isSidechain:false, message:{role:"user", content:$c}}' >> "$TR"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TR")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "tail-1 picks /opus 5; ch5 pair satisfies R1"
teardown_temp

# --- Test AC-7-log: SENTINEL_CHANNEL=5 + transcript /opus 3 -> env wins, disagreement logged ---
echo ""
echo "Test AC-7-log: SENTINEL_CHANNEL=5 + transcript /opus 3 + ch5 pair -> ALLOW + disagreement in debug log"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch5.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch5.md"
touch_now "$PROJECT/verification_findings/commit_check_ch5.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch5.md"
SID="eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" 3
LOG="$TMPDIR_ROOT/dbg.log"; : > "$LOG"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
SENTINEL_CHANNEL=5 SENTINEL_DEBUG_LOG="$LOG" run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "env ch5 wins; ch5 pair satisfies R1"
TOTAL=$((TOTAL + 1))
if grep -q "wins; transcript disagrees" "$LOG"; then
  echo -e "  ${GREEN}PASS${NC}: debug log captured disagreement (env wins; transcript disagrees)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: debug log missing disagreement text"
  echo "    log contents: $(cat "$LOG" 2>/dev/null || echo '(empty)')"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test T-prewarm-2: startup source does NOT pre-warm cache ---
echo ""
echo "Test T-prewarm-2: SessionStart(startup) + transcript /opus 3 -> cache NOT written"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
SID="ffffffff-ffff-ffff-ffff-ffffffffffff"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" 3
ORIENT_SCRIPT="$(cd "$SCRIPT_DIR/../../.." && pwd)/modules/core/hooks/session-orient.sh"
[[ -f "$ORIENT_SCRIPT" ]] || ORIENT_SCRIPT="$SCRIPT_DIR/session-orient.sh"  # deployed-companion layout
ORIENT_INPUT=$(cat << EOF
{"session_id":"$SID","cwd":"$PROJECT","source":"startup","transcript_path":"$TMPDIR_ROOT/$SID.jsonl","hook_event_name":"SessionStart"}
EOF
)
echo "$ORIENT_INPUT" | (cd "$TMPDIR_ROOT" && bash "$ORIENT_SCRIPT") > /dev/null 2>&1
TOTAL=$((TOTAL + 1))
if [[ ! -f "$PROJECT/verification_findings/.session_channel/$SID" ]]; then
  echo -e "  ${GREEN}PASS${NC}: startup did NOT write cache (prewarm skipped for startup source)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: startup incorrectly wrote cache file"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test T-resolve-malformed: corrupt transcript (invalid JSON) -> jq fails, UNCHANNELED, ch4 pair NOT credited ---
# (Ordinary R1 no-evidence block, NOT the RESOLVE_STATE=ambiguous-presence fail-closed gate: corrupt
#  JSON fails jq for BOTH channel resolution AND presence detection, so PRESENCE=false -> unchanneled.)
echo ""
echo "Test T-resolve-malformed: invalid JSON transcript + ch4 pair + completion -> BLOCK (jq fails, unchanneled, ch4 pair not credited)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch4.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch4.md"
touch_now "$PROJECT/verification_findings/commit_check_ch4.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch4.md"
SID="00000000-1111-2222-3333-444444444444"
TR="$TMPDIR_ROOT/$SID.jsonl"
printf '{"type":"user","message":{"content":"<command-message>opus</command-message> <command-name>/opus</command-name> <command-args>4</command-args>" BROKEN_JSON\n' > "$TR"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TR")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "malformed transcript: jq fails, no resolution, ch4 pair not credited"
teardown_temp

# --- Test T-env-leading-zero: SENTINEL_CHANNEL=04 normalizes to 4 (env-path leading zero) ---
# Regression guard for the env-path 10# normalization (the transcript path is covered by T-resolve-7).
echo ""
echo "Test T-env-leading-zero: SENTINEL_CHANNEL=04 + ch4 pair PASS + completion -> ALLOW (env 04 -> 4)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch4.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch4.md"
touch_now "$PROJECT/verification_findings/commit_check_ch4.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch4.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
SENTINEL_CHANNEL=04 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "env SENTINEL_CHANNEL=04 normalizes to 4; ch4 pair satisfies R1 (would BLOCK on a missing ch04 pair without the fix)"
teardown_temp

# ==================== CHANNEL-DETECTION COVERAGE TESTS ====================

# --- Test T-sidechain-rejected: isSidechain:true /opus wrapper NOT a genuine witness ---
# The F3 filter (select(.isSidechain!=true)) strips sidechain lines from both
# _rhc_transcript_channel AND _rhc_transcript_presence. A transcript whose ONLY
# /opus wrapper line has isSidechain:true yields: no channel resolved + no PRESENCE
# -> truly unchanneled (not ambiguous-presence). With a ch3 pair + completion, the
# unchanneled session looks for unsuffixed commit_check.md / commit_cold_read.md (which
# don't exist) -> BLOCK "COMPLETION WITHOUT VERIFICATION".
echo ""
echo "Test T-sidechain-rejected: isSidechain:true /opus 3 + ch3 pair + completion -> BLOCK (sidechain filter; not fail-closed)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch3.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch3.md"
touch_now "$PROJECT/verification_findings/commit_check_ch3.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch3.md"
SID="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
TR="$TMPDIR_ROOT/$SID.jsonl"
# Build a transcript with ONLY a sidechain /opus wrapper (isSidechain:true)
jq -nc --arg c "$(printf '<command-message>opus</command-message>\r\n<command-name>/opus</command-name>\r\n<command-args>3</command-args>')" \
  '{type:"user", isSidechain:true, message:{role:"user", content:$c}}' > "$TR"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TR")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "sidechain /opus rejected by F3 filter; session unchanneled; ch3 pair NOT credited; ordinary R1 block (not fail-closed)"
teardown_temp

# --- Test T-conservative-allow: PRESENCE + non-completion message -> conservative -> ALLOW ---
# registry entry='xyz' (unresolvable) -> RESOLVE_STATE="ambiguous-presence".
# Non-completion last message -> fail-closed gate does NOT fire -> RESOLVE_STATE flips to
# "conservative". Check 1 is skipped (no COMPLETION_CLAIMED). Check 1.5 is skipped
# (RESOLVE_STATE==conservative guard). Fresh CT avoids staleness. No deferral patterns.
# -> ALLOW (empty stdout).
echo ""
echo "Test T-conservative-allow: registry=xyz (PRESENCE) + no-opus transcript + non-completion + fresh CT -> ALLOW (conservative path, no false-block)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
SID="11223344-5566-7788-99aa-bbccddeeff00"
jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:"just a normal prompt"}}' > "$TMPDIR_ROOT/$SID.jsonl"
mkdir -p "$PROJECT/verification_findings/.session_channel"
printf 'xyz' > "$PROJECT/verification_findings/.session_channel/$SID"
INPUT=$(build_input_sid "$PROJECT" "Still reviewing the files." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "conservative path (PRESENCE + no completion) does NOT false-block"
teardown_temp

# --- Test T-cache-write-transcript: Stop with transcript /opus 3 -> registry written ---
# After resolve_hook_channel with a genuine /opus 3 transcript, _rhc_cache_write is called
# with '3'. Assert .session_channel/<sid> exists and contains '3'.
echo ""
echo "Test T-cache-write-transcript: Stop with transcript /opus 3 -> .session_channel/<sid> written with '3'"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
# Provide ch3 pair so the stop is ALLOW (cache write happens regardless of R1 outcome,
# but an ALLOW outcome proves the channel resolved correctly end-to-end).
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch3.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch3.md"
touch_now "$PROJECT/verification_findings/commit_check_ch3.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch3.md"
SID="aaaabbbb-cccc-dddd-eeee-ffff00001111"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" 3
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
# Check that the registry file was written with value '3'
TOTAL=$((TOTAL + 1))
CACHE_FILE="$PROJECT/verification_findings/.session_channel/$SID"
if [[ -f "$CACHE_FILE" ]] && [[ "$(cat "$CACHE_FILE")" == "3" ]]; then
  echo -e "  ${GREEN}PASS${NC}: cache written: .session_channel/$SID == '3'"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: cache not written or wrong value (expected '3', got '$(cat "$CACHE_FILE" 2>/dev/null || echo MISSING)')"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test T-cache-write-env: Stop with SENTINEL_CHANNEL=5 + UUID sid -> registry written with '5' ---
# When HOOK_CHANNEL is set via env AND sid_ok=true, _rhc_cache_write seeds the registry
# from the env channel value. Assert .session_channel/<sid> contains '5'.
echo ""
echo "Test T-cache-write-env: SENTINEL_CHANNEL=5 + UUID sid -> .session_channel/<sid> written with '5'"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
# Provide ch5 pair so the stop is ALLOW.
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch5.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch5.md"
touch_now "$PROJECT/verification_findings/commit_check_ch5.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch5.md"
SID="12345678-abcd-ef01-2345-6789abcdef01"
# Transcript with no /opus (env path, not transcript path)
jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:"normal prompt"}}' > "$TMPDIR_ROOT/$SID.jsonl"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
SENTINEL_CHANNEL=5 run_hook "$INPUT"
TOTAL=$((TOTAL + 1))
CACHE_FILE="$PROJECT/verification_findings/.session_channel/$SID"
if [[ -f "$CACHE_FILE" ]] && [[ "$(cat "$CACHE_FILE")" == "5" ]]; then
  echo -e "  ${GREEN}PASS${NC}: env-path cache written: .session_channel/$SID == '5'"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: env-path cache not written or wrong value (expected '5', got '$(cat "$CACHE_FILE" 2>/dev/null || echo MISSING)')"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test T-prewarm-compact: SessionStart source=compact -> cache IS written ---
# session-orient.sh re-derives on any source that is NOT "startup" or "clear".
# "compact" is a re-warm source (same as "resume") -> pre-warm writes the registry.
echo ""
echo "Test T-prewarm-compact: SessionStart(compact) + transcript /opus 3 -> cache .session_channel/<sid> == 3"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
SID="cafe0000-0000-0000-0000-000000000001"
write_opus_transcript "$TMPDIR_ROOT/$SID.jsonl" 3
ORIENT_SCRIPT="$(cd "$SCRIPT_DIR/../../.." && pwd)/modules/core/hooks/session-orient.sh"
[[ -f "$ORIENT_SCRIPT" ]] || ORIENT_SCRIPT="$SCRIPT_DIR/session-orient.sh"  # deployed-companion layout
ORIENT_INPUT=$(cat << EOF
{"session_id":"$SID","cwd":"$PROJECT","source":"compact","transcript_path":"$TMPDIR_ROOT/$SID.jsonl","hook_event_name":"SessionStart"}
EOF
)
echo "$ORIENT_INPUT" | (cd "$TMPDIR_ROOT" && bash "$ORIENT_SCRIPT") > /dev/null 2>&1
TOTAL=$((TOTAL + 1))
CACHE_FILE="$PROJECT/verification_findings/.session_channel/$SID"
if [[ -f "$CACHE_FILE" ]] && [[ "$(cat "$CACHE_FILE")" == "3" ]]; then
  echo -e "  ${GREEN}PASS${NC}: compact source wrote cache=3 (same as resume)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: compact source did NOT write cache (expected '3', got '$(cat "$CACHE_FILE" 2>/dev/null || echo MISSING)')"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test T-stale-override: SENTINEL_STALE_SEC=120 makes 200s CT stale -> BLOCK ---
# With SENTINEL_STALE_SEC=120, a CT aged ~200s (> 120) triggers the staleness block.
# Without the override (default 900), the same 200s age is fresh (< 900 -> ALLOW).
# One test only: override=120 + 200s age -> BLOCK.
echo ""
echo "Test T-stale-override: SENTINEL_CHANNEL=4 + own CT aged ~200s + SENTINEL_STALE_SEC=120 -> BLOCK (200 >= 120)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "DONE"
create_channel_ct "$PROJECT" 4 "IN PROGRESS"
must_touch_aged "$PROJECT/CURRENT_TASK_ch4.md" 200
INPUT=$(build_input "$PROJECT" "Inspecting the current state of the files.")
SENTINEL_CHANNEL=4 SENTINEL_STALE_SEC=120 run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "not updated recently" "SENTINEL_STALE_SEC=120 makes 200s stale -> block"
teardown_temp

# --- Test T-registry-leading-zero: registry='04' -> normalized to 4 -> ch4 pair satisfies ---
# The registry read normalizes with 10# (HOOK_CHANNEL="$((10#$cval))"). '04' -> 4.
# ch4 pair + completion -> ALLOW. If this BLOCKS, 10# normalization is missing -> real bug.
echo ""
echo "Test T-registry-leading-zero: registry='04' + no-opus transcript + ch4 pair + completion -> ALLOW (10# normalization)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch4.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch4.md"
touch_now "$PROJECT/verification_findings/commit_check_ch4.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch4.md"
SID="deadbeef-dead-beef-dead-beefdeadbeef"
jq -nc '{type:"user", isSidechain:false, message:{role:"user", content:"normal prompt, no opus"}}' > "$TMPDIR_ROOT/$SID.jsonl"
mkdir -p "$PROJECT/verification_findings/.session_channel"
printf '04' > "$PROJECT/verification_findings/.session_channel/$SID"
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "$SID" "$TMPDIR_ROOT/$SID.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "registry '04' normalizes to 4 via 10#; ch4 pair satisfies R1 -> ALLOW (bug if BLOCKS)"
teardown_temp

# --- Test T-empty-sid: empty session_id -> UUID guard fails -> unchanneled -> ch3 pair NOT credited ---
# build_input_sid with sid="" produces "session_id":"" in JSON. The hook's sid_ok check
# (UUID regex) fails -> resolve_hook_channel returns immediately with HOOK_CHANNEL="" ->
# truly unchanneled. Unchanneled session looks for unsuffixed commit_check.md which is
# absent -> BLOCK "COMPLETION WITHOUT VERIFICATION".
echo ""
echo "Test T-empty-sid: empty session_id + transcript /opus 3 + ch3 pair + completion -> BLOCK (empty sid fails UUID guard; unchanneled)"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
mkdir -p "$PROJECT/verification_findings"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check_ch3.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read_ch3.md"
touch_now "$PROJECT/verification_findings/commit_check_ch3.md"
touch_now "$PROJECT/verification_findings/commit_cold_read_ch3.md"
write_opus_transcript "$TMPDIR_ROOT/empty-sid.jsonl" 3
INPUT=$(build_input_sid "$PROJECT" "All work is done. Sprint complete." "" "$TMPDIR_ROOT/empty-sid.jsonl")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "empty sid -> UUID guard fails -> unchanneled -> ch3 pair NOT credited -> R1 block"
teardown_temp

# ==================== SYMMETRIC COMMIT-PAIR (Check 1.5) A4/A5 ====================
# These four cases prove that a partial or failing pair does NOT satisfy R1.
# They are the symmetric counterparts to T-pair-4 (check FAIL/cold PASS) and
# T-pair-5 (cold absent/check present). All four must block.

# --- Test T-pair-A4a: commit_check.md VERDICT FAIL, commit_cold_read.md PASS -> BLOCK ---
echo ""
echo "Test T-pair-A4a: commit_check.md FAIL + commit_cold_read.md PASS -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: FAIL (issues found)" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "commit_check FAIL does not satisfy R1"
assert_stdout_contains "commit_check.md" "block reason names the failing pair file"
teardown_temp

# --- Test T-pair-A4b: commit_cold_read.md VERDICT FAIL, commit_check.md PASS -> BLOCK ---
echo ""
echo "Test T-pair-A4b: commit_cold_read.md FAIL + commit_check.md PASS -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
echo "VERDICT: FAIL (issues found)" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "commit_cold_read FAIL does not satisfy R1"
assert_stdout_contains "commit_cold_read.md" "block reason names the failing pair file"
teardown_temp

# --- Test T-pair-A4c: commit_check.md missing, commit_cold_read.md present+PASS -> BLOCK ---
echo ""
echo "Test T-pair-A4c: commit_check.md absent + commit_cold_read.md PASS -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# commit_check.md deliberately absent; only cold_read present
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_cold_read.md"
touch_now "$PROJECT/verification_findings/commit_cold_read.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "missing commit_check.md does not satisfy R1"
teardown_temp

# --- Test T-pair-A4d: commit_cold_read.md missing, commit_check.md present+PASS -> BLOCK ---
echo ""
echo "Test T-pair-A4d: commit_cold_read.md absent + commit_check.md PASS -> BLOCK"
setup_temp
mkdir -p "$PROJECT"
create_ct "$PROJECT" "IN PROGRESS"
touch_now "$PROJECT/CURRENT_TASK.md"
# commit_cold_read.md deliberately absent; only check present
echo "VERDICT: PASS" > "$PROJECT/verification_findings/commit_check.md"
touch_now "$PROJECT/verification_findings/commit_check.md"
INPUT=$(build_input "$PROJECT" "All work is done. Sprint complete.")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPLETION WITHOUT VERIFICATION" "missing commit_cold_read.md does not satisfy R1"
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
