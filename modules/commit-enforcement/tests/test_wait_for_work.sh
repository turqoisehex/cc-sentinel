#!/usr/bin/env bash
# Test harness for wait_for_work.sh
# Run: bash modules/commit-enforcement/tests/test_wait_for_work.sh
#
# NOTE: wait_for_work.sh spawns a background heartbeat that inherits open file
# descriptors. Using $() command substitution would keep the pipe open until the
# heartbeat exits, blocking the test. All invocations therefore redirect output to
# a temp file and read it back afterward.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAIT_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/wait_for_work.sh"

if [[ ! -f "$WAIT_SCRIPT" ]]; then
  echo "ERROR: wait_for_work.sh not found at $WAIT_SCRIPT" >&2
  exit 1
fi

# Temp file for capturing script output within tests
OUT_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT

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

# Run wait_for_work.sh, redirect to files (avoids $() pipe blocking on heartbeat).
# Sets LAST_STDOUT, LAST_STDERR, LAST_EXIT.
run_script() {
  : > "$OUT_FILE"
  : > "$ERR_FILE"
  bash "$WAIT_SCRIPT" "$@" >"$OUT_FILE" 2>"$ERR_FILE"
  LAST_EXIT=$?
  LAST_STDOUT=$(cat "$OUT_FILE")
  LAST_STDERR=$(cat "$ERR_FILE")
}

assert_exit() {
  local expected=$1 label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ $LAST_EXIT -eq $expected ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (exit=$LAST_EXIT)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected exit=$expected, got exit=$LAST_EXIT"
    echo "    stdout: ${LAST_STDOUT:-}"
    echo "    stderr: ${LAST_STDERR:-}"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | grep -q "$pattern" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label (stdout matches)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — stdout does not match '$pattern'"
    echo "    stdout: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDERR" | grep -qiE "$pattern" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label (stderr matches)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — stderr does not match '$pattern'"
    echo "    stderr: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local path="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$path" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — file not found: $path"
    FAIL=$((FAIL + 1))
  fi
}

kill_heartbeat() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    kill "$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
  fi
}

ORIG_DIR="$(pwd)"

# ==================== TESTS ====================

echo "=== wait_for_work.sh Test Harness ==="
echo ""

# --- Test 1: --model opus selects _pending_opus dir ---
echo "Test 1: --model opus selects _pending_opus dir"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p verification_findings/_pending_opus/ch1
echo "work" > verification_findings/_pending_opus/ch1/task.md
run_script --model opus --channel 1
kill_heartbeat "verification_findings/_pending_opus/ch1/.heartbeat_pid"
assert_exit 0 "exit 0 (opus, channel 1)"
assert_stdout_contains "_pending_opus/ch1/task.md" "stdout contains _pending_opus/ch1/task.md"
assert_file_exists "verification_findings/_pending_opus/ch1/.active" ".active written"
cd "$ORIG_DIR"
rm -rf "$TMPDIR"

# --- Test 2: --model sonnet selects _pending_sonnet dir ---
echo ""
echo "Test 2: --model sonnet selects _pending_sonnet dir"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p verification_findings/_pending_sonnet/ch1
echo "work" > verification_findings/_pending_sonnet/ch1/task.md
run_script --model sonnet --channel 1
kill_heartbeat "verification_findings/_pending_sonnet/ch1/.heartbeat_pid"
assert_exit 0 "exit 0 (sonnet, channel 1)"
assert_stdout_contains "_pending_sonnet/ch1/task.md" "stdout contains _pending_sonnet/ch1/task.md"
assert_file_exists "verification_findings/_pending_sonnet/ch1/.active" ".active written"
cd "$ORIG_DIR"
rm -rf "$TMPDIR"

# --- Test 3: Invalid model -> exit 1 with error ---
echo ""
echo "Test 3: Invalid model -> exit 1 with error"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
run_script --model invalid
assert_exit 1 "exit 1 (invalid model)"
assert_stderr_contains "opus.*sonnet|sonnet.*opus|must be" "stderr mentions valid model names"
cd "$ORIG_DIR"
rm -rf "$TMPDIR"

# --- Test 4: Oldest-first ordering ---
echo ""
echo "Test 4: Oldest-first ordering"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p verification_findings/_pending_sonnet/ch1
echo "c" > verification_findings/_pending_sonnet/ch1/task_c.md
echo "b" > verification_findings/_pending_sonnet/ch1/task_b.md
echo "a" > verification_findings/_pending_sonnet/ch1/task_a.md
# Age task_b to be oldest (100s in the past)
python -c "import os,time; os.utime('verification_findings/_pending_sonnet/ch1/task_b.md', (time.time()-100, time.time()-100))"
run_script --model sonnet --channel 1
kill_heartbeat "verification_findings/_pending_sonnet/ch1/.heartbeat_pid"
assert_exit 0 "exit 0 (oldest-first)"
assert_stdout_contains "task_b.md" "stdout returns oldest file (task_b.md)"
cd "$ORIG_DIR"
rm -rf "$TMPDIR"

# --- Test 5: .active file written with correct format ---
echo ""
echo "Test 5: .active file written with correct format"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p verification_findings/_pending_sonnet/ch2
echo "work" > verification_findings/_pending_sonnet/ch2/task.md
run_script --model sonnet --channel 2
kill_heartbeat "verification_findings/_pending_sonnet/ch2/.heartbeat_pid"
assert_exit 0 "exit 0 (.active format)"
assert_file_exists "verification_findings/_pending_sonnet/ch2/.active" ".active file exists"
TOTAL=$((TOTAL + 1))
ACTIVE_CONTENT=$(cat "verification_findings/_pending_sonnet/ch2/.active" 2>/dev/null || echo "")
if echo "$ACTIVE_CONTENT" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z processing task\.md$"; then
  echo -e "  ${GREEN}PASS${NC}: .active content matches ISO-8601 processing <basename>"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: .active content format unexpected: '$ACTIVE_CONTENT'"
  FAIL=$((FAIL + 1))
fi
cd "$ORIG_DIR"
rm -rf "$TMPDIR"

# --- Test 6: Unchanneled (no --channel) uses top-level pending dir ---
echo ""
echo "Test 6: Unchanneled uses top-level _pending_sonnet dir"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
mkdir -p verification_findings/_pending_sonnet
echo "work" > verification_findings/_pending_sonnet/task.md
run_script --model sonnet
kill_heartbeat "verification_findings/_pending_sonnet/.heartbeat_pid"
assert_exit 0 "exit 0 (unchanneled)"
assert_stdout_contains "_pending_sonnet/task.md" "stdout contains _pending_sonnet/task.md (no ch subdir)"
assert_file_exists "verification_findings/_pending_sonnet/.active" ".active written at top-level"
cd "$ORIG_DIR"
rm -rf "$TMPDIR"

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
