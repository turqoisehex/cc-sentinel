#!/usr/bin/env bash
# Test harness for notification scripts (flash-linux.sh, flash-macos.sh, flash.ps1)
# Run: bash modules/notification/tests/test_notification.sh
#
# Since desktop notifications and terminal bells can't be verified in CI,
# we test: exit codes, stdin draining (no hang), shebang/flags, file existence,
# and PowerShell content patterns.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LINUX_SCRIPT="$MODULE_DIR/flash-linux.sh"
MACOS_SCRIPT="$MODULE_DIR/flash-macos.sh"
PS1_SCRIPT="$MODULE_DIR/flash.ps1"

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

LAST_STDOUT=""
LAST_EXIT=0

# Run a shell script with optional stdin, using timeout to guarantee no hang.
# Redirects stderr to /dev/null since bell/notify-send/osascript noise is expected.
# Uses gtimeout (macOS via coreutils) or timeout (Linux), falls back to plain bash.
if command -v timeout &>/dev/null; then
  _TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
  _TIMEOUT_CMD="gtimeout"
else
  _TIMEOUT_CMD=""
fi

run_with_timeout() {
  local script="$1" input="$2"
  if [[ -n "$_TIMEOUT_CMD" ]]; then
    LAST_STDOUT=$(echo "$input" | $_TIMEOUT_CMD 5 bash "$script" 2>/dev/null)
  else
    LAST_STDOUT=$(echo "$input" | bash "$script" 2>/dev/null)
  fi
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

assert_file_readable() {
  local path="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -r "$path" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — file not readable: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local path="$1" pattern="$2" label="$3"
  TOTAL=$((TOTAL + 1))
  if grep -qE "$pattern" "$path" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — pattern '$pattern' not found in $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_first_line() {
  local path="$1" expected="$2" label="$3"
  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(head -1 "$path")
  if [[ "$actual" == "$expected" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# ==================== TESTS ====================

echo "=== Notification Scripts Test Harness ==="
echo ""

# ---------- General: All files exist ----------

echo "Test 1: All three notification scripts exist"
assert_file_exists "$LINUX_SCRIPT" "flash-linux.sh exists"
assert_file_exists "$MACOS_SCRIPT" "flash-macos.sh exists"
assert_file_exists "$PS1_SCRIPT" "flash.ps1 exists"

# ---------- General: Shell scripts are readable ----------

echo ""
echo "Test 2: Shell scripts are readable"
assert_file_readable "$LINUX_SCRIPT" "flash-linux.sh is readable"
assert_file_readable "$MACOS_SCRIPT" "flash-macos.sh is readable"

# ---------- flash-linux.sh ----------

echo ""
echo "Test 3: flash-linux.sh has correct shebang"
assert_first_line "$LINUX_SCRIPT" "#!/usr/bin/env bash" "shebang is #!/usr/bin/env bash"

echo ""
echo "Test 4: flash-linux.sh has set -u"
assert_file_contains "$LINUX_SCRIPT" "^set -u" "set -u present"

echo ""
echo "Test 5: flash-linux.sh exits 0 with empty stdin"
run_with_timeout "$LINUX_SCRIPT" ""
assert_exit 0 "exit 0 with empty stdin"

echo ""
echo "Test 6: flash-linux.sh exits 0 with JSON stdin (drains it)"
run_with_timeout "$LINUX_SCRIPT" '{"event":"Stop","session_id":"abc-123","tool_name":null}'
assert_exit 0 "exit 0 with JSON stdin"

echo ""
echo "Test 7: flash-linux.sh exits 0 without notify-send (guards with command -v)"
# Even if notify-send is not on PATH, the script must not fail.
# We already tested it exits 0 above; additionally verify the guard exists.
assert_file_contains "$LINUX_SCRIPT" "command -v notify-send" "guards notify-send with command -v"

echo ""
echo "Test 8: flash-linux.sh drains stdin (cat > /dev/null)"
assert_file_contains "$LINUX_SCRIPT" "cat > /dev/null" "drains stdin via cat > /dev/null"

# ---------- flash-macos.sh ----------

echo ""
echo "Test 9: flash-macos.sh has correct shebang"
assert_first_line "$MACOS_SCRIPT" "#!/usr/bin/env bash" "shebang is #!/usr/bin/env bash"

echo ""
echo "Test 10: flash-macos.sh has set -u"
assert_file_contains "$MACOS_SCRIPT" "^set -u" "set -u present"

echo ""
echo "Test 11: flash-macos.sh exits 0 with empty stdin"
run_with_timeout "$MACOS_SCRIPT" ""
assert_exit 0 "exit 0 with empty stdin"

echo ""
echo "Test 12: flash-macos.sh exits 0 with JSON stdin (drains it)"
run_with_timeout "$MACOS_SCRIPT" '{"event":"Notification","session_id":"xyz-789","message":"done"}'
assert_exit 0 "exit 0 with JSON stdin"

echo ""
echo "Test 13: flash-macos.sh exits 0 even without osascript (uses || true)"
# On non-macOS systems osascript won't exist; the script must still exit 0.
# The previous exit-code tests already prove this. Verify the guard pattern too.
assert_file_contains "$MACOS_SCRIPT" '\|\| true' "osascript guarded with || true"

echo ""
echo "Test 14: flash-macos.sh drains stdin (cat > /dev/null)"
assert_file_contains "$MACOS_SCRIPT" "cat > /dev/null" "drains stdin via cat > /dev/null"

# ---------- flash.ps1 ----------

echo ""
echo "Test 15: flash.ps1 contains FlashWindowEx (core mechanism)"
assert_file_contains "$PS1_SCRIPT" "FlashWindowEx" "FlashWindowEx present"

echo ""
echo "Test 16: flash.ps1 contains console::beep"
assert_file_contains "$PS1_SCRIPT" '\[console\]::beep' "console::beep present"

echo ""
echo "Test 17: flash.ps1 drains stdin"
assert_file_contains "$PS1_SCRIPT" 'ReadToEnd' "drains stdin via ReadToEnd"

# ---------- Resilience: large stdin does not hang ----------

echo ""
echo "Test 18: flash-linux.sh handles large stdin without hanging"
LARGE_INPUT=$(python3 -c "import json; print(json.dumps({'data': 'x'*10000}))" 2>/dev/null || printf '{"data":"%s"}' "$(head -c 10000 /dev/zero | tr '\0' 'x')")
run_with_timeout "$LINUX_SCRIPT" "$LARGE_INPUT"
assert_exit 0 "exit 0 with large stdin (no hang)"

echo ""
echo "Test 19: flash-macos.sh handles large stdin without hanging"
run_with_timeout "$MACOS_SCRIPT" "$LARGE_INPUT"
assert_exit 0 "exit 0 with large stdin (no hang)"

# ---------- Content: bell character ----------

echo ""
echo "Test 20: flash-linux.sh emits terminal bell"
assert_file_contains "$LINUX_SCRIPT" "printf.*\\\\a" "contains printf bell"

echo ""
echo "Test 21: flash-macos.sh emits terminal bell"
assert_file_contains "$MACOS_SCRIPT" "printf.*\\\\a" "contains printf bell"

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
