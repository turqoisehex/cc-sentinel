#!/usr/bin/env bash
# Test harness for channel_commit.sh
# Run: bash modules/commit-enforcement/tests/test_channel_commit.sh
#
# Creates a temp git repo with mock safe-commit.sh and wait_for_results.sh,
# then exercises channel_commit.sh argument parsing, locking, staging,
# hash validation, and error paths.
#
# Strategy: For tests that need successful commits, we create a .heartbeat
# file so the script dispatches to our mock wait_for_results.sh (which
# creates result files with the correct hash). For tests that specifically
# test local-verify or error paths, we omit the heartbeat.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMIT_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/channel_commit.sh"

if [[ ! -f "$COMMIT_SCRIPT" ]]; then
  echo "ERROR: channel_commit.sh not found at $COMMIT_SCRIPT" >&2
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

setup_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  REPO="$TMPDIR_ROOT/repo"
  mkdir -p "$REPO"
  cd "$REPO"

  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"

  # Initial commit so HEAD exists
  echo "init" > init.txt
  git add init.txt
  git commit --quiet -m "initial"

  # Create verification_findings dir structure
  mkdir -p verification_findings/_pending_sonnet

  # Create a mock safe-commit.sh that just does git commit
  mkdir -p .claude/hooks
  cat > .claude/hooks/safe-commit.sh << 'MOCK_EOF'
#!/usr/bin/env bash
# Mock safe-commit.sh: just commit whatever is staged
shift  # consume --internal
MSG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) MSG="$2"; shift 2 ;;
    --local-verify|--skip-squad) shift ;;
    *) shift ;;
  esac
done
git commit --quiet -m "$MSG" --allow-empty-message 2>/dev/null
MOCK_EOF
  chmod +x .claude/hooks/safe-commit.sh

  # Create a mock wait_for_results.sh that creates fake result files
  # with the correct hash extracted from the dispatch file
  cat > "$TMPDIR_ROOT/mock_wait.sh" << 'MOCK_EOF'
#!/usr/bin/env bash
# Mock wait_for_results.sh: create result files immediately with matching hash
# Skip --timeout and its value if present
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) shift 2 ;;
    *) break ;;
  esac
done
# Read the dispatch file to get the hash
DISPATCH=$(find verification_findings/_pending_sonnet -name 'verify_*.md' -print -quit 2>/dev/null)
HASH=""
if [[ -n "$DISPATCH" ]] && [[ -f "$DISPATCH" ]]; then
  HASH=$(grep '^Hash: ' "$DISPATCH" 2>/dev/null | awk '{print $2}')
fi
for f in "$@"; do
  mkdir -p "$(dirname "$f")"
  printf 'Hash: %s\nVERDICT: PASS\n' "${HASH}" > "$f"
done
MOCK_EOF
  chmod +x "$TMPDIR_ROOT/mock_wait.sh"

  # Prepare scripts_mock directory with our mocked versions
  mkdir -p "$REPO/scripts_mock"
  cp "$COMMIT_SCRIPT" "$REPO/scripts_mock/channel_commit.sh"
  cp "$TMPDIR_ROOT/mock_wait.sh" "$REPO/scripts_mock/wait_for_results.sh"
  chmod +x "$REPO/scripts_mock/channel_commit.sh" "$REPO/scripts_mock/wait_for_results.sh"
}

# Create a fresh heartbeat so the script uses normal dispatch (not local-verify fallback)
create_heartbeat() {
  local pending="${1:-verification_findings/_pending_sonnet}"
  mkdir -p "$pending"
  touch "$pending/.heartbeat"
}

# Create a heartbeat with a specific age in seconds (for liveness-state tests)
create_aged_heartbeat() {
  local pending="${1:-verification_findings/_pending_sonnet}" age_seconds="${2:-400}"
  mkdir -p "$pending"
  touch "$pending/.heartbeat"
  local hb_win
  hb_win=$(cygpath -w "$pending/.heartbeat" 2>/dev/null || echo "$pending/.heartbeat")
  python -c "import os, time; os.utime(r'$hb_win', (time.time()-$age_seconds, time.time()-$age_seconds))" 2>/dev/null || \
    python3 -c "import os, time; os.utime(r'$hb_win', (time.time()-$age_seconds, time.time()-$age_seconds))" 2>/dev/null || \
    touch -d "${age_seconds} seconds ago" "$pending/.heartbeat" 2>/dev/null
}

teardown_repo() {
  cd /
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

# Create a tracked file then modify it (so there's a diff to commit)
create_test_file() {
  local name="$1" content="${2:-test content}"
  echo "$content" > "$name"
  git add "$name"
  git commit --quiet -m "add $name"
  # Now modify it so there's something to commit
  echo "${content} modified" > "$name"
}

# Run channel_commit.sh with given args, using mocked scripts
run_commit() {
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"

  bash "$REPO/scripts_mock/channel_commit.sh" "$@" > "$stdout_file" 2> "$stderr_file"
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
    echo "    stdout: $LAST_STDOUT"
    echo "    stderr: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | grep -qE "$pattern" 2>/dev/null; then
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

assert_file_committed() {
  local file="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if git log --oneline -1 --name-only | grep -q "$file" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label ($file in last commit)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — $file not in last commit"
    echo "    last commit: $(git log --oneline -1 --name-only)"
    FAIL=$((FAIL + 1))
  fi
}

assert_no_lock() {
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if [[ ! -d ".git/commit.lock" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (no stale lock)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — commit.lock still exists"
    FAIL=$((FAIL + 1))
  fi
}

# ==================== TESTS ====================

echo "=== channel_commit.sh Test Harness ==="
echo ""

# --- Test 1: Basic commit with 2 files -> success ---
echo "Test 1: Basic commit with 2 files"
setup_repo
create_test_file "file_a.txt" "content A"
create_test_file "file_b.txt" "content B"
create_heartbeat
run_commit --files "file_a.txt file_b.txt" -m "test: commit two files"
assert_exit 0 "exits successfully"
assert_stdout_contains "[0-9a-f]{7,}" "outputs commit SHA"
assert_stderr_contains "SUCCESS" "reports success"
assert_file_committed "file_a.txt" "file_a committed"
assert_file_committed "file_b.txt" "file_b committed"
assert_no_lock "lock cleaned up"
teardown_repo

# --- Test 2: Missing --files -> error ---
echo ""
echo "Test 2: Missing --files -> error"
setup_repo
run_commit -m "test: no files"
assert_exit 1 "exits with error"
assert_stderr_contains "(required|unbound)" "reports missing --files"
teardown_repo

# --- Test 3: Missing -m -> error ---
echo ""
echo "Test 3: Missing -m message -> error"
setup_repo
create_test_file "file_c.txt" "content C"
run_commit --files "file_c.txt"
assert_exit 1 "exits with error"
assert_stderr_contains "required" "mentions -m required"
teardown_repo

# --- Test 4: --skip-squad flag accepted ---
echo ""
echo "Test 4: --skip-squad flag accepted"
setup_repo
create_test_file "file_d.txt" "content D"
create_heartbeat
run_commit --files "file_d.txt" -m "test: skip squad" --skip-squad
assert_exit 0 "exits successfully with --skip-squad"
assert_stdout_contains "[0-9a-f]{7,}" "outputs commit SHA"
assert_no_lock "lock cleaned up"
teardown_repo

# --- Test 5: --local-verify with valid pre-existing results ---
echo ""
echo "Test 5: --local-verify with correct pre-existing results"
setup_repo
create_test_file "file_e.txt" "content E"
# Stage + compute hash to pre-populate result files correctly
git add file_e.txt
EXPECTED_HASH=$(git diff --cached | git hash-object --stdin)
git reset --quiet
mkdir -p verification_findings
printf 'Hash: %s\nVERDICT: PASS\n' "$EXPECTED_HASH" > verification_findings/commit_check.md
printf 'Hash: %s\nVERDICT: PASS\n' "$EXPECTED_HASH" > verification_findings/commit_cold_read.md
run_commit --files "file_e.txt" -m "test: local verify" --local-verify
assert_exit 0 "exits successfully with --local-verify"
assert_stdout_contains "[0-9a-f]{7,}" "outputs commit SHA"
assert_stderr_contains "Verification passed" "reports verification passed"
teardown_repo

# --- Test 6: Lock acquisition and release ---
echo ""
echo "Test 6: Lock acquisition and cleanup"
setup_repo
create_test_file "file_f.txt" "content F"
create_heartbeat
# Verify no lock exists before
TOTAL=$((TOTAL + 1))
if [[ ! -d ".git/commit.lock" ]]; then
  echo -e "  ${GREEN}PASS${NC}: no lock before commit"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: lock exists before commit"
  FAIL=$((FAIL + 1))
fi
run_commit --files "file_f.txt" -m "test: lock test"
assert_exit 0 "commits successfully"
assert_no_lock "lock released after commit"
teardown_repo

# --- Test 7: Stale lock detection ---
echo ""
echo "Test 7: Stale lock detection and removal"
setup_repo
create_test_file "file_g.txt" "content G"
create_heartbeat
# Create a stale lock (timestamp from 200s ago, threshold is 120s)
mkdir -p .git/commit.lock
local_now=$(date +%s)
echo "$((local_now - 200))" > .git/commit.lock/time
echo "99999" > .git/commit.lock/pid
echo "test" > .git/commit.lock/channel
run_commit --files "file_g.txt" -m "test: stale lock"
assert_exit 0 "exits successfully (stale lock removed)"
assert_stderr_contains "[Ss]tale" "reports stale lock removal"
assert_no_lock "stale lock cleaned up"
teardown_repo

# --- Test 8: Unknown argument -> error ---
echo ""
echo "Test 8: Unknown argument -> error"
setup_repo
run_commit --files "x.txt" -m "test" --bogus-flag
assert_exit 1 "exits with error"
assert_stderr_contains "Unknown argument" "reports unknown argument"
teardown_repo

# --- Test 9: Channel flag sets correct paths ---
echo ""
echo "Test 9: --channel flag sets channel-specific paths"
setup_repo
create_test_file "file_h.txt" "content H"
create_heartbeat "verification_findings/_pending_sonnet/ch3"
run_commit --channel 3 --files "file_h.txt" -m "test: channel 3"
assert_exit 0 "commits successfully with --channel"
assert_stderr_contains "Phase 1" "executes Phase 1"
assert_stdout_contains "[0-9a-f]{7,}" "outputs commit SHA"
teardown_repo

# --- Test 10: No heartbeat -> auto-fallback to local-verify ---
echo ""
echo "Test 10: No heartbeat -> auto-fallback to local-verify"
setup_repo
create_test_file "file_i.txt" "content I"
# No heartbeat file, no --local-verify flag
# Script should detect missing heartbeat and auto-set LOCAL_VERIFY=true
# Then local-verify fails because no pre-existing result files
run_commit --files "file_i.txt" -m "test: heartbeat"
assert_exit 1 "exits with error (no results for local-verify)"
assert_stderr_contains "(heartbeat|No Sonnet)" "heartbeat check fires"
assert_stderr_contains "LOCAL VERIFY" "falls back to local-verify mode"
assert_no_lock "lock cleaned up on failure"
teardown_repo

# --- Test 10b: Fresh heartbeat + .active present -> dispatch normally, log processing ---
echo ""
echo "Test 10b: Fresh heartbeat + .active present -> commits successfully, logs processing"
setup_repo
create_test_file "file_10b.txt" "content 10b"
create_heartbeat
echo "2026-03-23T20:15:00Z processing test_task.md" > "verification_findings/_pending_sonnet/.active"
run_commit --files "file_10b.txt" -m "test: fresh hb with active"
assert_exit 0 "exits successfully (fresh hb + .active)"
assert_stderr_contains "processing" "logs listener is processing"
assert_no_lock "lock cleaned up"
teardown_repo

# --- Test 10c: Warn-stale heartbeat (~400s) + no .active -> commits, warns slow listener ---
echo ""
echo "Test 10c: Warn-stale heartbeat (~400s) + no .active -> commits successfully, warns about slow listener"
setup_repo
create_test_file "file_10c.txt" "content 10c"
create_aged_heartbeat "verification_findings/_pending_sonnet" 400
run_commit --files "file_10c.txt" -m "test: warn-stale hb no active"
assert_exit 0 "exits successfully (warn-stale hb, no .active)"
assert_stderr_contains "(slow|stalled|Listener)" "warns about stale heartbeat"
assert_no_lock "lock cleaned up"
teardown_repo

# --- Test 10d: Warn-stale heartbeat (~400s) + .active present -> commits, logs busy ---
echo ""
echo "Test 10d: Warn-stale heartbeat (~400s) + .active present -> commits successfully, logs busy"
setup_repo
create_test_file "file_10d.txt" "content 10d"
create_aged_heartbeat "verification_findings/_pending_sonnet" 400
echo "2026-03-23T20:15:00Z processing test_task.md" > "verification_findings/_pending_sonnet/.active"
run_commit --files "file_10d.txt" -m "test: warn-stale hb with active"
assert_exit 0 "exits successfully (warn-stale hb + .active)"
assert_stderr_contains "(busy|long task)" "logs listener busy"
assert_no_lock "lock cleaned up"
teardown_repo

# --- Test 10e: Stale heartbeat (~1000s) + no .active -> falls back to local-verify (exit 1) ---
echo ""
echo "Test 10e: Stale heartbeat (~1000s) + no .active -> falls back to local-verify, exits 1"
setup_repo
create_test_file "file_10e.txt" "content 10e"
create_aged_heartbeat "verification_findings/_pending_sonnet" 1000
# No pre-existing result files, so local-verify also fails -> exit 1
run_commit --files "file_10e.txt" -m "test: stale hb no active"
assert_exit 1 "exits 1 (stale hb, no .active, no result files)"
assert_stderr_contains "(down|stale|local)" "warns about stale heartbeat"
assert_no_lock "lock cleaned up on failure"
teardown_repo

# --- Test 11: Commit active file lifecycle ---
echo ""
echo "Test 11: .commit_active signal file lifecycle"
setup_repo
create_test_file "file_j.txt" "content J"
create_heartbeat
run_commit --files "file_j.txt" -m "test: commit active"
assert_exit 0 "commits successfully"
# After completion, .commit_active should be cleaned by trap
TOTAL=$((TOTAL + 1))
if [[ ! -f "verification_findings/_pending_sonnet/.commit_active" ]]; then
  echo -e "  ${GREEN}PASS${NC}: .commit_active cleaned up after commit"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: .commit_active still exists after commit"
  FAIL=$((FAIL + 1))
fi
assert_no_lock "lock cleaned up"
teardown_repo

# --- Test 12: Hash conflict detection (concurrent modification of same file) ---
echo ""
echo "Test 12: Hash conflict detection"
setup_repo
create_test_file "file_k.txt" "content K"
# Stage and compute the expected hash (file_k has "content K modified")
git add file_k.txt
EXPECTED_HASH=$(git diff --cached | git hash-object --stdin)
git reset --quiet
# Pre-populate result files with Phase 1's hash for local-verify
mkdir -p verification_findings
printf 'Hash: %s\nVERDICT: PASS\n' "$EXPECTED_HASH" > verification_findings/commit_check.md
printf 'Hash: %s\nVERDICT: PASS\n' "$EXPECTED_HASH" > verification_findings/commit_cold_read.md
# Simulate concurrent commit that modifies the SAME file (changes its base in HEAD)
# This changes what git diff --cached produces for file_k.txt in Phase 2
echo "content K concurrent change" > file_k.txt
git add file_k.txt
git commit --quiet -m "concurrent: modify file_k.txt"
# Restore our intended modification (different from what concurrent committed)
echo "content K modified" > file_k.txt
# Phase 2 will re-stage file_k.txt, but the diff is now against the new base
# ("concurrent change" -> "modified") instead of ("content K" -> "modified")
# This produces a different hash -> CONFLICT
run_commit --files "file_k.txt" -m "test: conflict" --local-verify
assert_exit 1 "exits with error (hash conflict)"
assert_stderr_contains "(CONFLICT|Hash mismatch)" "detects hash change"
assert_no_lock "lock cleaned up on conflict"
teardown_repo

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
