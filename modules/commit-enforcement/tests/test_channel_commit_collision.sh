#!/usr/bin/env bash
# Test harness for channel_commit.sh lock-serialization (two-channel collision test)
#
# SEQUENTIAL REGRESSION GUARD, NOT A CONCURRENCY TEST
# -------------------------------------------------------
# True concurrency (two real channel_commit.sh processes racing) cannot be driven
# reliably in this harness: channel_commit.sh runs UNLOCKED during the dispatch
# window (the long wait_for_results.sh call), so two concurrent invocations would
# not deterministically contend on the lock at all — they might both succeed with
# no collision observed, giving a vacuous green that proves nothing.
#
# Instead, the test drives the REAL lock mechanism deterministically:
#   1. The test manually pre-creates .git/commit.lock with FRESH holder files
#      (time/pid/channel) to simulate a held lock, defeating stale-detection.
#   2. channel 7 is launched in background — it loops on mkdir(.git/commit.lock)
#      and WAITS (real lock contention path exercised).
#   3. Contention is asserted: PID7 still alive + no new commit yet.
#   4. Lock released with rm -rf (matching channel_commit.sh's own release_lock).
#   5. ch7 then acquires, stages, and commits.
#
# This is a sequential regression guard that locks the exact wait-loop behavior,
# per-channel file isolation, and lock-release contract. Label preserved per plan.
#
# Run: bash modules/commit-enforcement/tests/test_channel_commit_collision.sh

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

# --- Test helpers (mirror test_channel_commit.sh) ---

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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) shift 2 ;;
    *) break ;;
  esac
done
# Look in all pending dirs for the dispatch file
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

teardown_repo() {
  # Kill any background processes that may still be running
  if [[ -n "${BG_PID7:-}" ]]; then
    kill "$BG_PID7" 2>/dev/null || true
    wait "$BG_PID7" 2>/dev/null || true
    BG_PID7=""
  fi
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

assert_true() {
  local condition="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$condition" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — condition not met: $condition"
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

echo "=== channel_commit.sh Collision / Lock Serialization Test Harness ==="
echo ""

# --- Test C1: Lock contention — ch7 waits while lock is manually held ---
#
# SEQUENTIAL REGRESSION GUARD: drives the real acquire_lock wait-loop by manually
# pre-creating the lock dir with FRESH holder files (defeating stale-detection),
# launching ch7 in background, asserting it is blocked, then releasing and
# asserting ch7 commits successfully.
echo "Test C1: Lock contention — ch7 waits on manually-held lock, commits after release"
BG_PID7=""
setup_repo
create_test_file "file_ch7.txt" "channel 7 content"
mkdir -p "verification_findings/_pending_sonnet/ch7"
create_heartbeat "verification_findings/_pending_sonnet/ch7"

# Capture the git log count BEFORE the lock-hold test
COMMITS_BEFORE=$(git log --oneline | wc -l | tr -d ' ')

# Step 1: Manually create the lock dir with FRESH holder files (defeating stale-detection).
# REQUIRED: without a fresh time, stale-detection (~120s threshold) would rm -rf the dir
# and ch7 would acquire immediately — no contention.
LOCK_DIR=".git/commit.lock"
mkdir -p "$LOCK_DIR"
date +%s > "$LOCK_DIR/time"          # FRESH timestamp (0s old — well below 120s threshold)
echo "99999" > "$LOCK_DIR/pid"       # fake holder PID (not a real process)
echo "simulated-holder" > "$LOCK_DIR/channel"

# Step 2: Launch ch7 in the background. It will loop on mkdir .git/commit.lock (fails —
# dir exists) + sleep 1, i.e. it WAITS. --skip-squad avoids the squad step.
{
  bash "$REPO/scripts_mock/channel_commit.sh" \
    --channel 7 \
    --files "file_ch7.txt" \
    -m "test: ch7 collision" \
    --skip-squad \
    > "$TMPDIR_ROOT/ch7_stdout" 2> "$TMPDIR_ROOT/ch7_stderr"
  echo $? > "$TMPDIR_ROOT/ch7_exit"
} &
BG_PID7=$!

# Step 3: Assert contention — after ~1.5s, ch7 PID is alive AND no new commit yet.
sleep 2

# (a) PID7 still alive (ch7 is waiting on the lock)
TOTAL=$((TOTAL + 1))
if kill -0 "$BG_PID7" 2>/dev/null; then
  echo -e "  ${GREEN}PASS${NC}: ch7 PID still alive (blocked on lock)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: ch7 process already exited (expected to be waiting on lock)"
  echo "    ch7 stderr: $(cat "$TMPDIR_ROOT/ch7_stderr" 2>/dev/null)"
  FAIL=$((FAIL + 1))
fi

# (b) No new commit while lock is held
COMMITS_DURING=$(git log --oneline | wc -l | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [[ "$COMMITS_DURING" -le "$COMMITS_BEFORE" ]]; then
  echo -e "  ${GREEN}PASS${NC}: no new commit while lock is held (before=$COMMITS_BEFORE, during=$COMMITS_DURING)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: unexpected commit while lock held (before=$COMMITS_BEFORE, during=$COMMITS_DURING)"
  FAIL=$((FAIL + 1))
fi

# Step 4: Release the lock with rm -rf (matching channel_commit.sh's release_lock function).
# NOT rmdir — the dir contains holder files (time/pid/channel).
rm -rf "$LOCK_DIR"

# Step 5: Wait for ch7 to complete (it acquires lock, stages, and commits).
wait "$BG_PID7" 2>/dev/null || true
BG_PID7=""

CH7_EXIT=$(cat "$TMPDIR_ROOT/ch7_exit" 2>/dev/null || echo "unknown")
CH7_STDERR=$(cat "$TMPDIR_ROOT/ch7_stderr" 2>/dev/null || echo "")

# (c) ch7 exited successfully after lock released
TOTAL=$((TOTAL + 1))
if [[ "$CH7_EXIT" == "0" ]]; then
  echo -e "  ${GREEN}PASS${NC}: ch7 committed successfully after lock released (exit=0)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: ch7 exited with code $CH7_EXIT (expected 0)"
  echo "    ch7 stderr: $CH7_STDERR"
  FAIL=$((FAIL + 1))
fi

# (d) ch7 commit is now in git log
TOTAL=$((TOTAL + 1))
if git log --oneline | grep -q "ch7 collision"; then
  echo -e "  ${GREEN}PASS${NC}: ch7 commit landed in git log"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: ch7 commit not found in git log"
  echo "    git log: $(git log --oneline)"
  FAIL=$((FAIL + 1))
fi

# (e) git fsck clean (--quiet not supported on all git versions, so omit it)
TOTAL=$((TOTAL + 1))
FSCK_OUT=$(git fsck --full 2>&1)
FSCK_EXIT=$?
if [[ $FSCK_EXIT -eq 0 ]]; then
  echo -e "  ${GREEN}PASS${NC}: git fsck clean after collision test"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: git fsck reported errors (exit=$FSCK_EXIT)"
  echo "    fsck: $FSCK_OUT"
  FAIL=$((FAIL + 1))
fi

# (f) lock dir absent after completion
assert_no_lock "lock dir absent after ch7 completion"

teardown_repo

# --- Test C2: Per-channel file isolation — ch2 and ch7 write to distinct paths ---
#
# Verifies that each channel writes to its own verification_findings paths (commit_check_ch2.md
# vs commit_check_ch7.md) and that each commit includes only its own channel's files.
# Uses sequential commits (ch2 then ch7) to avoid the HEAD-advanced conflict between
# Phase 1 and Phase 2 that a concurrent race would trigger.
# Note: staged_diff_chN.diff files are cleaned up by channel_commit.sh after each commit
# (rm -f on line ~429) — assert on commit_check_chN.md files which persist.
echo ""
echo "Test C2: Per-channel file isolation — ch2 and ch7 use distinct verification paths"
setup_repo
create_test_file "file_ch2.txt" "channel 2 content"
create_test_file "file_ch7.txt" "channel 7 content"
create_heartbeat "verification_findings/_pending_sonnet/ch2"
create_heartbeat "verification_findings/_pending_sonnet/ch7"

# Commit ch2 first
bash "$REPO/scripts_mock/channel_commit.sh" \
  --channel 2 \
  --files "file_ch2.txt" \
  -m "test: ch2 isolation" \
  --skip-squad \
  > "$TMPDIR_ROOT/c2_stdout" 2> "$TMPDIR_ROOT/c2_stderr"
C2_EXIT=$?

# Commit ch7 second (sequential — avoids HEAD conflict without complex hash pre-seeding)
bash "$REPO/scripts_mock/channel_commit.sh" \
  --channel 7 \
  --files "file_ch7.txt" \
  -m "test: ch7 isolation" \
  --skip-squad \
  > "$TMPDIR_ROOT/c7_stdout" 2> "$TMPDIR_ROOT/c7_stderr"
C7_EXIT=$?

TOTAL=$((TOTAL + 1))
if [[ $C2_EXIT -eq 0 && $C7_EXIT -eq 0 ]]; then
  echo -e "  ${GREEN}PASS${NC}: both ch2 and ch7 committed successfully (exit 0)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: ch2 exit=$C2_EXIT, ch7 exit=$C7_EXIT (expected both 0)"
  echo "    ch2 stderr: $(cat "$TMPDIR_ROOT/c2_stderr")"
  echo "    ch7 stderr: $(cat "$TMPDIR_ROOT/c7_stderr")"
  FAIL=$((FAIL + 1))
fi

# Two channel commits in log (plus initial + create_test_file commits)
TOTAL=$((TOTAL + 1))
CH2_MATCH=$(git log --oneline | grep -c "ch2 isolation" || true)
CH7_MATCH=$(git log --oneline | grep -c "ch7 isolation" || true)
if [[ $CH2_MATCH -ge 1 && $CH7_MATCH -ge 1 ]]; then
  echo -e "  ${GREEN}PASS${NC}: both ch2 and ch7 commits present in git log"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: expected both ch2+ch7 in git log (ch2=$CH2_MATCH, ch7=$CH7_MATCH)"
  echo "    git log: $(git log --oneline)"
  FAIL=$((FAIL + 1))
fi

# Per-channel verification result files exist (commit_check_chN.md persists after commit)
TOTAL=$((TOTAL + 1))
if [[ -f "verification_findings/commit_check_ch2.md" && -f "verification_findings/commit_check_ch7.md" ]]; then
  echo -e "  ${GREEN}PASS${NC}: per-channel commit_check files exist (ch2 + ch7 are distinct)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: missing per-channel commit_check files"
  echo "    ch2: $(ls verification_findings/commit_check_ch2.md 2>/dev/null || echo 'MISSING')"
  echo "    ch7: $(ls verification_findings/commit_check_ch7.md 2>/dev/null || echo 'MISSING')"
  FAIL=$((FAIL + 1))
fi

# ch2's commit_check does not contain ch7's file path (no cross-channel bleed)
TOTAL=$((TOTAL + 1))
if [[ -f "verification_findings/commit_check_ch2.md" ]]; then
  if ! grep -q "file_ch7.txt" "verification_findings/commit_check_ch2.md" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: ch2 commit_check contains no ch7 files (no cross-channel bleed)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: ch2 commit_check CONTAINS ch7 file (cross-channel bleed!)"
    FAIL=$((FAIL + 1))
  fi
else
  echo -e "  ${RED}FAIL${NC}: ch2 commit_check missing — cannot verify isolation"
  FAIL=$((FAIL + 1))
fi

# ch7's commit_check does not contain ch2's file path
TOTAL=$((TOTAL + 1))
if [[ -f "verification_findings/commit_check_ch7.md" ]]; then
  if ! grep -q "file_ch2.txt" "verification_findings/commit_check_ch7.md" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: ch7 commit_check contains no ch2 files (no cross-channel bleed)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: ch7 commit_check CONTAINS ch2 file (cross-channel bleed!)"
    FAIL=$((FAIL + 1))
  fi
else
  echo -e "  ${RED}FAIL${NC}: ch7 commit_check missing — cannot verify isolation"
  FAIL=$((FAIL + 1))
fi

# Each commit in git log includes only its own channel's file (no cross-channel staging leak)
TOTAL=$((TOTAL + 1))
CH2_COMMIT=$(git log --oneline | grep "ch2 isolation" | awk '{print $1}')
CH7_COMMIT=$(git log --oneline | grep "ch7 isolation" | awk '{print $1}')
CH2_OK="true"
CH7_OK="true"
if [[ -n "$CH2_COMMIT" ]]; then
  if git show --stat "$CH2_COMMIT" 2>/dev/null | grep -q "file_ch7.txt"; then
    CH2_OK="false"
  fi
fi
if [[ -n "$CH7_COMMIT" ]]; then
  if git show --stat "$CH7_COMMIT" 2>/dev/null | grep -q "file_ch2.txt"; then
    CH7_OK="false"
  fi
fi
if [[ "$CH2_OK" == "true" && "$CH7_OK" == "true" ]]; then
  echo -e "  ${GREEN}PASS${NC}: each commit includes only its own channel's files (no staging leak)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: cross-channel file leaked into commit (ch2_ok=$CH2_OK, ch7_ok=$CH7_OK)"
  FAIL=$((FAIL + 1))
fi

# git fsck clean
TOTAL=$((TOTAL + 1))
FSCK_OUT2=$(git fsck --full 2>&1)
FSCK_EXIT2=$?
if [[ $FSCK_EXIT2 -eq 0 ]]; then
  echo -e "  ${GREEN}PASS${NC}: git fsck clean after isolation test"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: git fsck reported errors (exit=$FSCK_EXIT2)"
  echo "    fsck: $FSCK_OUT2"
  FAIL=$((FAIL + 1))
fi

assert_no_lock "lock dir absent after both channel commits"
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
