#!/usr/bin/env bash
# Test harness for wait_for_results.sh
# Run: bash modules/commit-enforcement/tests/test_wait_for_results.sh
#
# Tests file-waiting behavior, timeout, and argument parsing.
# Uses short timeouts and background file creation to avoid long waits.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WAIT_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/wait_for_results.sh"

if [[ ! -f "$WAIT_SCRIPT" ]]; then
  echo "ERROR: wait_for_results.sh not found at $WAIT_SCRIPT" >&2
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
}

teardown_temp() {
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
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

# ==================== TESTS ====================

echo "=== wait_for_results.sh Test Harness ==="
echo ""

# --- Test 1: No files specified -> error ---
echo "Test 1: No files specified -> error"
setup_temp
LAST_STDERR=$(bash "$WAIT_SCRIPT" 2>&1 >/dev/null)
LAST_EXIT=$?
LAST_STDOUT=""
assert_exit 1 "exit 1 (no files)"
assert_stderr_contains "No files specified" "reports no files"
teardown_temp

# --- Test 2: Files already present -> immediate success ---
echo ""
echo "Test 2: Files already present -> immediate success (exit 0)"
setup_temp
echo "result1" > "$TMPDIR_ROOT/file1.md"
echo "result2" > "$TMPDIR_ROOT/file2.md"
LAST_STDERR=$(bash "$WAIT_SCRIPT" --timeout 5 "$TMPDIR_ROOT/file1.md" "$TMPDIR_ROOT/file2.md" 2>&1 >/dev/null)
LAST_EXIT=$?
assert_exit 0 "exit 0 (files exist)"
teardown_temp

# --- Test 3: Single file already present -> success ---
echo ""
echo "Test 3: Single file present -> immediate success"
setup_temp
echo "data" > "$TMPDIR_ROOT/single.md"
LAST_STDERR=$(bash "$WAIT_SCRIPT" --timeout 5 "$TMPDIR_ROOT/single.md" 2>&1 >/dev/null)
LAST_EXIT=$?
assert_exit 0 "exit 0 (single file exists)"
teardown_temp

# --- Test 4: Timeout with missing files -> error ---
echo ""
echo "Test 4: Timeout with missing files -> error"
setup_temp
LAST_STDERR=$(bash "$WAIT_SCRIPT" --timeout 4 "$TMPDIR_ROOT/missing1.md" "$TMPDIR_ROOT/missing2.md" 2>&1 >/dev/null)
LAST_EXIT=$?
assert_exit 1 "exit 1 (timeout)"
assert_stderr_contains "TIMEOUT" "reports timeout"
assert_stderr_contains "missing1.md" "lists first missing file"
assert_stderr_contains "missing2.md" "lists second missing file"
teardown_temp

# --- Test 5: One file present, one missing -> timeout ---
echo ""
echo "Test 5: One present, one missing -> timeout"
setup_temp
echo "present" > "$TMPDIR_ROOT/present.md"
LAST_STDERR=$(bash "$WAIT_SCRIPT" --timeout 4 "$TMPDIR_ROOT/present.md" "$TMPDIR_ROOT/absent.md" 2>&1 >/dev/null)
LAST_EXIT=$?
assert_exit 1 "exit 1 (partial files)"
assert_stderr_contains "TIMEOUT" "reports timeout"
assert_stderr_contains "absent.md" "lists the missing file"
# Verify the present file is NOT listed as missing
TOTAL=$((TOTAL + 1))
if echo "$LAST_STDERR" | grep -q "present.md" 2>/dev/null; then
  echo -e "  ${RED}FAIL${NC}: present file incorrectly listed as missing"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}PASS${NC}: present file not listed as missing"
  PASS=$((PASS + 1))
fi
teardown_temp

# --- Test 6: File appears during wait -> success ---
echo ""
echo "Test 6: File appears during wait -> success before timeout"
setup_temp
# Create file after a short delay in background
(sleep 2 && echo "arrived" > "$TMPDIR_ROOT/delayed.md") &
BG_PID=$!
LAST_STDERR=$(bash "$WAIT_SCRIPT" --timeout 15 "$TMPDIR_ROOT/delayed.md" 2>&1 >/dev/null)
LAST_EXIT=$?
wait $BG_PID 2>/dev/null
assert_exit 0 "exit 0 (file appeared during wait)"
teardown_temp

# --- Test 7: Default timeout is 3600 (verify by checking timeout message) ---
echo ""
echo "Test 7: Timeout message includes wait duration"
setup_temp
LAST_STDERR=$(bash "$WAIT_SCRIPT" --timeout 4 "$TMPDIR_ROOT/nonexistent.md" 2>&1 >/dev/null)
LAST_EXIT=$?
assert_stderr_contains "Waited 4s" "timeout message shows correct duration"
teardown_temp

# --- Test 8: --timeout flag parsing ---
echo ""
echo "Test 8: Custom --timeout value is respected"
setup_temp
START=$(date +%s)
LAST_STDERR=$(bash "$WAIT_SCRIPT" --timeout 4 "$TMPDIR_ROOT/nope.md" 2>&1 >/dev/null)
LAST_EXIT=$?
END=$(date +%s)
ELAPSED=$((END - START))
assert_exit 1 "exit 1 (timed out)"
TOTAL=$((TOTAL + 1))
# Should have taken at least 3 seconds (timeout 4, poll every 3)
# and no more than 10 seconds
if [[ $ELAPSED -ge 3 ]] && [[ $ELAPSED -le 10 ]]; then
  echo -e "  ${GREEN}PASS${NC}: timeout respected (elapsed=${ELAPSED}s)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: unexpected elapsed time ${ELAPSED}s"
  FAIL=$((FAIL + 1))
fi
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
