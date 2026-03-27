#!/usr/bin/env bash
# Test harness for auto-checkpoint.sh
# Run: bash modules/core/tests/test_auto_checkpoint.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/auto-checkpoint.sh"

[[ ! -f "$HOOK_SCRIPT" ]] && echo "ERROR: auto-checkpoint.sh not found at $HOOK_SCRIPT" >&2 && exit 1

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
[[ ! -t 1 ]] && RED="" && GREEN="" && NC=""

setup_repo() {
  TMPDIR_ROOT=$(mktemp -d)
  REPO="$TMPDIR_ROOT/repo"
  mkdir -p "$REPO" && cd "$REPO"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt && git commit -m "initial" --quiet
}

teardown() { rm -rf "$TMPDIR_ROOT" 2>/dev/null; }

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf "${GREEN}PASS${NC} %s\n" "$label"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC} %s\n  expected: %s\n  actual:   %s\n" "$label" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    printf "${GREEN}PASS${NC} %s\n" "$label"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC} %s\n  expected to contain: %s\n  actual: %s\n" "$label" "$needle" "$haystack"
    FAIL=$((FAIL + 1))
  fi
}

# --- Tests ---

# T1: Creates stash when changes exist
echo "--- T1: Creates checkpoint stash ---"
setup_repo
echo "modified" >> file.txt
OUTPUT=$(echo '{"trigger":"Stop"}' | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T1: exit code" "0" "$?"
STASH_COUNT=$(git stash list | grep -c "sentinel-checkpoint:" || true)
assert_eq "T1: sentinel stash created" "1" "$STASH_COUNT"
# Working dir unchanged
assert_eq "T1: file still modified" "modified" "$(tail -1 file.txt)"
# Nothing staged after hook
STAGED=$(git diff --cached --name-only)
assert_eq "T1: nothing staged after" "" "$STAGED"
teardown

# T2: No stash when no changes
echo "--- T2: No stash when clean ---"
setup_repo
OUTPUT=$(echo '{"trigger":"Stop"}' | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T2: exit code" "0" "$?"
STASH_COUNT=$(git stash list | grep -c "sentinel-checkpoint:" || true)
assert_eq "T2: no stash created" "0" "$STASH_COUNT"
teardown

# T3: Silent output (no stdout)
echo "--- T3: Silent output ---"
setup_repo
echo "change" >> file.txt
OUTPUT=$(echo '{"trigger":"PreCompact"}' | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T3: no stdout" "" "$OUTPUT"
teardown

# T4: Prune respects MAX_CHECKPOINTS and only prunes sentinel stashes
echo "--- T4: Prune only sentinel stashes ---"
setup_repo
# Create 5 user stashes
for i in $(seq 1 5); do
  echo "user-$i" >> file.txt
  git stash push -m "user stash $i" --quiet 2>/dev/null
  echo "initial" > file.txt  # restore
done
# Create 11 sentinel stashes (exceeds MAX_CHECKPOINTS=10)
for i in $(seq 1 11); do
  echo "sentinel-$i" >> file.txt
  SHA=$(git stash create "sentinel-checkpoint: test-$i")
  git stash store -m "sentinel-checkpoint: test-$i" "$SHA"
  git checkout -- file.txt
done
# Run hook to trigger pruning
echo "final" >> file.txt
OUTPUT=$(echo '{"trigger":"Stop"}' | bash "$HOOK_SCRIPT" 2>/dev/null)
# Should have 10 sentinel stashes (pruned oldest) + 5 user stashes
SENTINEL_COUNT=$(git stash list | grep -c "sentinel-checkpoint:" || true)
USER_COUNT=$(git stash list | grep -c "user stash" || true)
assert_eq "T4: sentinel stashes pruned to 10" "10" "$SENTINEL_COUNT"
assert_eq "T4: user stashes untouched" "5" "$USER_COUNT"
teardown

# T5: Not in git repo — graceful exit
echo "--- T5: Not in git repo ---"
TMPDIR_ROOT=$(mktemp -d)
cd "$TMPDIR_ROOT"
OUTPUT=$(echo '{"trigger":"Stop"}' | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T5: exit code" "0" "$?"
rm -rf "$TMPDIR_ROOT"

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
