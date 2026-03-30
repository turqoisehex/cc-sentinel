#!/usr/bin/env bash
# Test harness for safe-commit.sh
# Run: bash modules/commit-enforcement/tests/test_safe_commit.sh
#
# Creates temp git repos per test and exercises safe-commit.sh behaviors:
# direct invocation guard, flag parsing, channel routing, per-commit agent
# checks, squad verification, test framework detection, commit passthrough,
# and post-commit cleanup.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/safe-commit.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: safe-commit.sh not found at $HOOK_SCRIPT" >&2
  exit 1
fi

# Counters
PASS=0
FAIL=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
if [[ ! -t 1 ]]; then RED=""; GREEN=""; YELLOW=""; NC=""; fi

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

  # Copy the real hook into the repo
  cp "$HOOK_SCRIPT" "$REPO/safe-commit.sh"
  chmod +x "$REPO/safe-commit.sh"

  # Create a mock wait_for_results.sh that always succeeds (the per-commit
  # agent files are pre-created by tests that need them)
  mkdir -p "$REPO/scripts"
  cat > "$REPO/scripts/wait_for_results.sh" << 'MOCK_EOF'
#!/usr/bin/env bash
# Mock wait: just exit 0 (real files are pre-created by the test)
exit 0
MOCK_EOF
  chmod +x "$REPO/scripts/wait_for_results.sh"

  # Create verification_findings dir
  mkdir -p verification_findings
}

teardown_repo() {
  cd /
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

# Stage a non-exempt file (triggers per-commit + squad checks)
stage_code_file() {
  local name="${1:-code.sh}" content="${2:-echo hello}"
  mkdir -p "$(dirname "$name")" 2>/dev/null
  echo "$content" > "$name"
  git add "$name"
}

# Stage an exempt-only file (no per-commit or squad checks)
stage_exempt_file() {
  local name="${1:-README.md}" content="${2:-# Readme}"
  echo "$content" > "$name"
  git add "$name"
}

# Compute CURRENT_HASH for whatever is currently staged
get_staged_hash() {
  git diff --cached | git hash-object --stdin
}

# Create valid per-commit agent files with matching hash
create_agent_evidence() {
  local hash="$1" suffix="${2:-}"
  mkdir -p verification_findings
  printf 'CURRENT_HASH: %s\nVERDICT: PASS\n' "$hash" > "verification_findings/commit_check${suffix}.md"
  printf 'CURRENT_HASH: %s\nVERDICT: PASS\n' "$hash" > "verification_findings/commit_cold_read${suffix}.md"
}

# Create valid squad evidence directory
create_squad_evidence() {
  local prefix="${1:-squad_run1}"
  local dir="verification_findings/${prefix}"
  mkdir -p "$dir"
  for agent in mechanical.md adversarial.md completeness.md dependency.md cold_reader.md; do
    printf 'VERDICT: PASS\n' > "$dir/$agent"
  done
}

# Run safe-commit.sh and capture outputs
run_hook() {
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"

  bash "$REPO/safe-commit.sh" "$@" > "$stdout_file" 2> "$stderr_file"
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
    echo -e "  ${RED}FAIL${NC}: $label -- expected exit=$expected, got exit=$LAST_EXIT"
    echo "    stdout: $LAST_STDOUT"
    echo "    stderr: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDERR" | grep -qiE "$pattern" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label -- stderr does not match '$pattern'"
    echo "    stderr: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_not_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDERR" | grep -qiE "$pattern" 2>/dev/null; then
    echo -e "  ${RED}FAIL${NC}: $label -- stderr unexpectedly matches '$pattern'"
    echo "    stderr: $LAST_STDERR"
    FAIL=$((FAIL + 1))
  else
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  fi
}

assert_file_exists() {
  local path="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -e "$path" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label -- '$path' does not exist"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local path="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -e "$path" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label -- '$path' still exists"
    FAIL=$((FAIL + 1))
  fi
}

assert_last_commit_message() {
  local expected="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(git log -1 --format=%s 2>/dev/null)
  if [[ "$actual" == "$expected" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label -- expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# ==================== TESTS ====================

echo "=== safe-commit.sh Test Harness ==="
echo ""

# --- Test 1: Direct invocation (no --internal) -> exit 1, BLOCKED ---
echo "Test 1: Direct invocation without --internal -> BLOCKED"
setup_repo
stage_exempt_file
run_hook -m "direct call"
assert_exit 1 "exits 1 without --internal"
assert_stderr_contains "BLOCKED" "BLOCKED message in stderr"
assert_stderr_contains "Do not call safe-commit.sh directly" "usage guidance in stderr"
teardown_repo

# --- Test 2: --internal flag -> passes guard ---
echo ""
echo "Test 2: --internal flag passes the guard"
setup_repo
stage_exempt_file
# With --internal, exempt-only files, --skip-tests, --skip-squad -> should commit
run_hook --internal --skip-tests --skip-squad -m "internal call"
assert_exit 0 "exits 0 with --internal"
assert_last_commit_message "internal call" "commit actually created"
teardown_repo

# --- Test 3: --skip-tests -> skips test detection ---
echo ""
echo "Test 3: --skip-tests skips test framework detection"
setup_repo
stage_exempt_file
# Create pubspec.yaml which would trigger flutter test (which would fail)
echo "name: fake_project" > pubspec.yaml
run_hook --internal --skip-tests --skip-squad -m "skip tests"
assert_exit 0 "exits 0 with --skip-tests"
assert_stderr_contains "Tests skipped" "reports tests skipped"
assert_stderr_not_contains "Running Flutter" "does not attempt Flutter tests"
teardown_repo

# --- Test 4: --skip-squad -> bypasses squad evidence check ---
echo ""
echo "Test 4: --skip-squad bypasses squad evidence"
setup_repo
stage_code_file "deploy.sh" "echo deploy"
HASH=$(get_staged_hash)
# Create _pending so SONNET_VERIFY doesn't warn (but set --local-verify to skip wait)
mkdir -p verification_findings/_pending_sonnet
create_agent_evidence "$HASH"
# No squad evidence at all -> should still pass because --skip-squad
run_hook --internal --skip-tests --skip-squad --local-verify -m "skip squad"
assert_exit 0 "exits 0 with --skip-squad"
assert_stderr_contains "SQUAD BYPASSED" "reports squad bypassed"
teardown_repo

# --- Test 5: --local-verify sets SONNET_VERIFY=false ---
echo ""
echo "Test 5: --local-verify sets SONNET_VERIFY=false"
setup_repo
stage_code_file "run.sh" "echo run"
HASH=$(get_staged_hash)
# No _pending dir -> would normally warn. With --local-verify, per-commit checks
# should skip if no result files exist (single-terminal mode).
create_agent_evidence "$HASH"
create_squad_evidence
run_hook --internal --skip-tests --local-verify -m "local verify"
assert_exit 0 "exits 0 with --local-verify"
assert_stderr_not_contains "Waiting for Sonnet" "does not wait for Sonnet"
teardown_repo

# --- Test 6: Exempt files only -> no squad check needed ---
echo ""
echo "Test 6: Exempt-only files skip squad check"
setup_repo
stage_exempt_file "README.md" "# Project readme"
stage_exempt_file "CHANGELOG.md" "## Changes"
stage_exempt_file "notes.txt" "some notes"
# No squad evidence, no agent evidence -> should still pass
run_hook --internal --skip-tests -m "exempt only"
assert_exit 0 "exits 0 with exempt-only files"
assert_stderr_not_contains "BLOCKED" "no BLOCKED message"
assert_stderr_not_contains "Squad verification" "no squad check"
teardown_repo

# --- Test 7: Non-exempt files without squad evidence -> BLOCKED ---
echo ""
echo "Test 7: Non-exempt files without squad evidence -> BLOCKED"
setup_repo
stage_code_file "main.dart" "void main() {}"
HASH=$(get_staged_hash)
# Provide per-commit agent evidence (so that check passes) but no squad evidence
create_agent_evidence "$HASH"
# No squad dirs at all
run_hook --internal --skip-tests --local-verify -m "no squad"
assert_exit 1 "exits 1 without squad evidence"
assert_stderr_contains "COMMIT BLOCKED" "BLOCKED message"
assert_stderr_contains "Squad verification required" "squad required message"
teardown_repo

# --- Test 8: Non-exempt files with valid squad evidence -> passes ---
echo ""
echo "Test 8: Non-exempt files with valid squad evidence -> passes"
setup_repo
stage_code_file "lib/app.dart" "void main() {}"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
create_squad_evidence "squad_run42"
run_hook --internal --skip-tests --local-verify -m "valid squad"
assert_exit 0 "exits 0 with valid squad evidence"
assert_last_commit_message "valid squad" "commit message correct"
teardown_repo

# --- Test 9: Squad evidence with VERDICT: FAIL -> BLOCKED ---
echo ""
echo "Test 9: Squad evidence with VERDICT: FAIL -> BLOCKED"
setup_repo
stage_code_file "src/index.ts" "console.log('hi')"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
# Create squad dir with one FAIL verdict (all 5 agents present, one fails)
mkdir -p "verification_findings/squad_fail1"
for agent in mechanical.md adversarial.md completeness.md dependency.md; do
  printf 'VERDICT: PASS\n' > "verification_findings/squad_fail1/$agent"
done
printf 'VERDICT: FAIL\n' > "verification_findings/squad_fail1/cold_reader.md"
run_hook --internal --skip-tests --local-verify -m "squad fail"
assert_exit 1 "exits 1 with squad FAIL"
assert_stderr_contains "COMMIT BLOCKED" "BLOCKED message"
assert_stderr_contains "Squad verification required" "squad required (evidence incomplete)"
teardown_repo

# --- Test 10: Squad evidence with VERDICT: PASS -> passes ---
echo ""
echo "Test 10: Squad evidence with all VERDICT: PASS -> passes"
setup_repo
stage_code_file "scripts/build.sh" "make build"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
# All PASS
create_squad_evidence "squad_allpass"
run_hook --internal --skip-tests --local-verify -m "squad pass"
assert_exit 0 "exits 0 with all PASS"
teardown_repo

# --- Test 11: Squad evidence with VERDICT: WARN -> passes ---
echo ""
echo "Test 11: Squad evidence with VERDICT: WARN -> passes"
setup_repo
stage_code_file "test/unit_test.dart" "test('x', () {})"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
# Mix of PASS and WARN
mkdir -p "verification_findings/squad_warnmix"
printf 'VERDICT: PASS\n' > "verification_findings/squad_warnmix/mechanical.md"
printf 'VERDICT: WARN\n' > "verification_findings/squad_warnmix/adversarial.md"
printf 'VERDICT: PASS\n' > "verification_findings/squad_warnmix/completeness.md"
printf 'VERDICT: WARN\n' > "verification_findings/squad_warnmix/dependency.md"
printf 'VERDICT: PASS\n' > "verification_findings/squad_warnmix/cold_reader.md"
run_hook --internal --skip-tests --local-verify -m "squad warn"
assert_exit 0 "exits 0 with WARN verdicts"
teardown_repo

# --- Test 12: VERIFICATION_BLOCKED in CURRENT_TASK.md -> overrides squad ---
echo ""
echo "Test 12: VERIFICATION_BLOCKED overrides squad requirement"
setup_repo
stage_code_file "core.py" "print('core')"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
# No squad evidence, but VERIFICATION_BLOCKED in CURRENT_TASK.md
echo "Status: VERIFICATION_BLOCKED - max rounds exhausted" > CURRENT_TASK.md
run_hook --internal --skip-tests --local-verify -m "blocked override"
assert_exit 0 "exits 0 with VERIFICATION_BLOCKED override"
assert_last_commit_message "blocked override" "commit created despite no squad"
teardown_repo

# --- Test 13: SENTINEL_CHANNEL -> channel suffix in paths ---
echo ""
echo "Test 13: SENTINEL_CHANNEL sets channel suffix"
setup_repo
stage_code_file "config.yaml" "key: value"
HASH=$(get_staged_hash)
# Create channel-specific agent evidence
create_agent_evidence "$HASH" "_ch5"
# Create channel-specific squad evidence
create_squad_evidence "squad_ch5_run1"
# Create _pending_sonnet/ch5 dir so Sonnet verify path exists
mkdir -p "verification_findings/_pending_sonnet/ch5"
export SENTINEL_CHANNEL=5
run_hook --internal --skip-tests --local-verify -m "channel 5 commit"
assert_exit 0 "exits 0 with channel evidence"
assert_last_commit_message "channel 5 commit" "commit message correct"
unset SENTINEL_CHANNEL
teardown_repo

# --- Test 14: SENTINEL_CHANNEL with wrong channel evidence -> BLOCKED ---
echo ""
echo "Test 14: SENTINEL_CHANNEL with non-channel evidence -> BLOCKED"
setup_repo
stage_code_file "handler.go" "package main"
HASH=$(get_staged_hash)
# Create evidence WITHOUT channel suffix (wrong for ch3)
create_agent_evidence "$HASH"
create_squad_evidence "squad_run1"
export SENTINEL_CHANNEL=3
run_hook --internal --skip-tests --local-verify -m "wrong channel"
RESULT_EXIT=$LAST_EXIT
unset SENTINEL_CHANNEL
# The hook looks for commit_check_ch3.md, not commit_check.md
# Without _pending_sonnet/ch3 dir, SONNET_VERIFY becomes false and it checks for
# verification_findings/commit_check_ch3.md which doesn't exist -> skips in local mode
# But squad_run1 doesn't match squad_ch3_* glob -> BLOCKED
assert_exit 1 "exits 1 with non-channel squad evidence"
assert_stderr_contains "BLOCKED" "BLOCKED for wrong channel squad"
teardown_repo

# --- Test 15: Test framework detection with --skip-tests -> skipped ---
echo ""
echo "Test 15: pubspec.yaml present but --skip-tests -> skipped"
setup_repo
# Create pubspec.yaml (would trigger flutter test)
echo "name: fake" > pubspec.yaml
git add pubspec.yaml
git commit --quiet -m "add pubspec"
stage_exempt_file "docs.md" "# Docs"
run_hook --internal --skip-tests -m "skip despite pubspec"
assert_exit 0 "exits 0 with --skip-tests"
assert_stderr_contains "Tests skipped" "reports tests skipped"
assert_stderr_not_contains "Running Flutter" "flutter test not invoked"
teardown_repo

# --- Test 16: Commit succeeds -> squad dirs cleaned up ---
echo ""
echo "Test 16: Successful commit cleans up squad dirs"
setup_repo
stage_code_file "cleanup.sh" "echo cleanup"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
create_squad_evidence "squad_cleanup1"
# Also create a second squad dir that is incomplete (should NOT be cleaned)
mkdir -p "verification_findings/squad_incomplete"
printf 'VERDICT: PASS\n' > "verification_findings/squad_incomplete/mechanical.md"
# (missing other agents)
run_hook --internal --skip-tests --local-verify -m "cleanup test"
assert_exit 0 "exits 0, commit succeeds"
assert_file_not_exists "verification_findings/squad_cleanup1" "complete squad dir removed"
assert_file_exists "verification_findings/squad_incomplete" "incomplete squad dir preserved"
# Per-commit agent files should also be cleaned
assert_file_not_exists "verification_findings/commit_check.md" "commit_check.md removed"
assert_file_not_exists "verification_findings/commit_cold_read.md" "commit_cold_read.md removed"
teardown_repo

# --- Test 17: Commit message passed through correctly ---
echo ""
echo "Test 17: Commit message passed through to git commit"
setup_repo
stage_exempt_file "LICENSE" "MIT"
run_hook --internal --skip-tests -m "fix: precise message with special chars & symbols"
assert_exit 0 "exits 0"
assert_last_commit_message "fix: precise message with special chars & symbols" "message preserved exactly"
teardown_repo

# --- Test 18: Per-commit agent check - missing commit_check.md -> BLOCKED ---
echo ""
echo "Test 18: Missing commit_check.md -> BLOCKED"
setup_repo
stage_code_file "server.rs" "fn main() {}"
HASH=$(get_staged_hash)
# Only create cold_read, not commit_check
mkdir -p verification_findings/_pending_sonnet
mkdir -p verification_findings
printf 'CURRENT_HASH: %s\nVERDICT: PASS\n' "$HASH" > "verification_findings/commit_cold_read.md"
# Don't create commit_check.md
run_hook --internal --skip-tests --skip-squad
assert_exit 1 "exits 1 missing commit_check.md"
assert_stderr_contains "COMMIT BLOCKED" "BLOCKED message"
assert_stderr_contains "Adversarial" "names missing agent"
teardown_repo

# --- Test 19: Per-commit agent check - stale hash -> BLOCKED ---
echo ""
echo "Test 19: Per-commit agent files with stale hash -> BLOCKED"
setup_repo
stage_code_file "logic.dart" "void logic() {}"
HASH=$(get_staged_hash)
# Create agent files with wrong hash
create_agent_evidence "0000000000000000000000000000000000000000"
mkdir -p verification_findings/_pending_sonnet
run_hook --internal --skip-tests --skip-squad
assert_exit 1 "exits 1 with stale hash"
assert_stderr_contains "COMMIT BLOCKED" "BLOCKED message"
assert_stderr_contains "stale" "stale hash detected"
teardown_repo

# --- Test 20: Per-commit agent check - VERDICT: FAIL in commit_check -> BLOCKED ---
echo ""
echo "Test 20: Per-commit VERDICT: FAIL -> BLOCKED"
setup_repo
stage_code_file "broken.py" "import os"
HASH=$(get_staged_hash)
mkdir -p verification_findings/_pending_sonnet
mkdir -p verification_findings
printf '%s\nVERDICT: FAIL\n' "$HASH" > "verification_findings/commit_check.md"
printf '%s\nVERDICT: PASS\n' "$HASH" > "verification_findings/commit_cold_read.md"
run_hook --internal --skip-tests --skip-squad
assert_exit 1 "exits 1 with agent FAIL"
assert_stderr_contains "COMMIT BLOCKED" "BLOCKED message"
assert_stderr_contains "FAILED" "FAILED verdict reported"
teardown_repo

# --- Test 21: Per-commit VERDICT: WARN -> passes ---
echo ""
echo "Test 21: Per-commit VERDICT: WARN -> passes"
setup_repo
stage_code_file "util.sh" "echo util"
HASH=$(get_staged_hash)
mkdir -p verification_findings/_pending_sonnet
mkdir -p verification_findings
printf '%s\nVERDICT: WARN\n' "$HASH" > "verification_findings/commit_check.md"
printf '%s\nVERDICT: WARN\n' "$HASH" > "verification_findings/commit_cold_read.md"
create_squad_evidence
run_hook --internal --skip-tests --local-verify -m "warn verdicts"
assert_exit 0 "exits 0 with WARN verdicts"
teardown_repo

# --- Test 22: --sonnet-verify flag keeps SONNET_VERIFY=true ---
echo ""
echo "Test 22: --sonnet-verify flag"
setup_repo
stage_code_file "api.ts" "export default {}"
HASH=$(get_staged_hash)
# Create _pending dir so the hook doesn't warn about missing listener
mkdir -p verification_findings/_pending_sonnet
# The mock wait_for_results.sh will succeed, but we need agent files
# pre-created because the mock doesn't create them for this path
create_agent_evidence "$HASH"
create_squad_evidence
run_hook --internal --skip-tests --sonnet-verify -m "sonnet verify"
assert_exit 0 "exits 0 with --sonnet-verify"
assert_stderr_contains "Waiting for Sonnet" "attempts to wait for Sonnet results"
teardown_repo

# --- Test 23: VERIFICATION_BLOCKED in channel-specific CT file ---
echo ""
echo "Test 23: VERIFICATION_BLOCKED in CURRENT_TASK_chN.md with channel"
setup_repo
stage_code_file "worker.py" "import sys"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH" "_ch7"
# No squad evidence, but channel CT has VERIFICATION_BLOCKED
echo "VERIFICATION_BLOCKED: round 3 failed" > CURRENT_TASK_ch7.md
export SENTINEL_CHANNEL=7
run_hook --internal --skip-tests --local-verify -m "channel blocked"
assert_exit 0 "exits 0 with channel VERIFICATION_BLOCKED"
assert_last_commit_message "channel blocked" "commit message correct"
unset SENTINEL_CHANNEL
teardown_repo

# --- Test 24: Multiple flags combined ---
echo ""
echo "Test 24: Multiple flags (--skip-tests --skip-squad --local-verify)"
setup_repo
stage_code_file "multi.dart" "void multi() {}"
# No agent evidence, no squad evidence -> would normally fail both checks
# But --skip-squad skips squad, and --local-verify with no result files skips per-commit
run_hook --internal --skip-tests --skip-squad --local-verify -m "multi flags"
assert_exit 0 "exits 0 with all flags combined"
assert_stderr_contains "Tests skipped" "tests skipped"
assert_stderr_contains "SQUAD BYPASSED" "squad bypassed"
teardown_repo

# --- Test 25: Remaining args forwarded to git commit ---
echo ""
echo "Test 25: Extra git args forwarded to commit"
setup_repo
stage_exempt_file "NOTICE" "notice text"
# The -m flag and message should pass through; verify with the commit
run_hook --internal --skip-tests -m "forwarded message"
assert_exit 0 "exits 0"
assert_last_commit_message "forwarded message" "message forwarded to git commit"
teardown_repo

# --- Test 26: No staged files -> git commit fails (nothing to commit) ---
echo ""
echo "Test 26: No staged files -> commit fails"
setup_repo
# Don't stage anything
run_hook --internal --skip-tests -m "empty commit"
# git commit should fail because nothing is staged
assert_exit 1 "exits 1 with nothing staged"
teardown_repo

# --- Test 27: Channel cleanup targets channel-specific squad dirs ---
echo ""
echo "Test 27: Channel cleanup targets only channel-specific dirs"
setup_repo
stage_code_file "ch_clean.yaml" "clean: true"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH" "_ch2"
# Create channel-2 squad dir (should be cleaned) and non-channel dir (should survive)
create_squad_evidence "squad_ch2_run1"
create_squad_evidence "squad_run_other"
export SENTINEL_CHANNEL=2
run_hook --internal --skip-tests --local-verify -m "channel cleanup"
assert_exit 0 "exits 0"
assert_file_not_exists "verification_findings/squad_ch2_run1" "channel squad dir cleaned"
assert_file_exists "verification_findings/squad_run_other" "non-channel squad dir preserved"
# Channel-specific agent files cleaned
assert_file_not_exists "verification_findings/commit_check_ch2.md" "channel commit_check removed"
assert_file_not_exists "verification_findings/commit_cold_read_ch2.md" "channel cold_read removed"
unset SENTINEL_CHANNEL
teardown_repo

# --- Test 28: Missing one of five squad agents -> BLOCKED ---
echo ""
echo "Test 28: Incomplete squad (missing dependency.md) -> BLOCKED"
setup_repo
stage_code_file "partial.sh" "echo partial"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
# Create squad dir with only 4 of 5 agents (missing dependency.md)
mkdir -p "verification_findings/squad_partial"
for agent in mechanical.md adversarial.md completeness.md cold_reader.md; do
  printf 'VERDICT: PASS\n' > "verification_findings/squad_partial/$agent"
done
# dependency.md missing
run_hook --internal --skip-tests --local-verify -m "partial squad"
assert_exit 1 "exits 1 with incomplete squad"
assert_stderr_contains "COMMIT BLOCKED" "BLOCKED for incomplete squad"
teardown_repo

# --- Test 29: Per-commit local-verify with no result files and no _pending -> skips ---
echo ""
echo "Test 29: Local-verify, no _pending dir, no results -> per-commit skipped"
setup_repo
stage_code_file "solo.sh" "echo solo"
# No _pending dir, no result files -> local-verify mode with HAVE_RESULTS=false
# Per-commit checks skip, but squad still required
create_squad_evidence
run_hook --internal --skip-tests --local-verify -m "solo mode"
# SONNET_VERIFY starts true, but no _pending dir -> sets false + warns
# Then no result files -> HAVE_RESULTS=false -> skip per-commit
# Squad check should still pass
assert_exit 0 "exits 0 (per-commit skipped, squad passes)"
assert_stderr_contains "No Sonnet listener" "warns about missing listener"
assert_stderr_contains "Per-commit agent checks skipped" "skips per-commit checks"
teardown_repo

# --- Test 30: manifest.json with valid launched list -> uses filtered agents ---
echo ""
echo "Test 30: manifest.json valid -> uses 2 listed agents only"
setup_repo
stage_code_file "doc.md" "# docs"
# Stage an exempt-only file to avoid per-commit checks but still need squad
# Actually need a non-exempt file - but that triggers per-commit checks too.
# Use a code file and skip per-commit via --local-verify (no result files = skipped).
stage_code_file "src/filter.sh" "echo filter"
# Create manifest-filtered squad: only 2 agents listed
mkdir -p "verification_findings/squad_manifest1"
printf 'VERDICT: PASS\n' > "verification_findings/squad_manifest1/mechanical.md"
printf 'VERDICT: PASS\n' > "verification_findings/squad_manifest1/cold_reader.md"
printf '{"launched":["mechanical.md","cold_reader.md"],"reason":"docs only"}\n' > "verification_findings/squad_manifest1/manifest.json"
run_hook --internal --skip-tests --local-verify -m "manifest filtered"
assert_exit 0 "exits 0 with manifest-filtered 2-agent squad"
teardown_repo

# --- Test 31: manifest.json with invalid JSON -> falls through to default (all 5) ---
echo ""
echo "Test 31: manifest.json invalid JSON -> falls through to default"
setup_repo
stage_code_file "src/broken.sh" "echo broken"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
# Create squad with all 5 agents (default)
create_squad_evidence "squad_manifest_bad"
# Add an invalid manifest.json
printf '{invalid\n' > "verification_findings/squad_manifest_bad/manifest.json"
run_hook --internal --skip-tests --local-verify -m "bad manifest"
assert_exit 0 "exits 0 (invalid manifest falls back to default 5)"
teardown_repo

# --- Test 32: manifest.json with empty launched -> falls through to default ---
echo ""
echo "Test 32: manifest.json empty launched -> falls through to default"
setup_repo
stage_code_file "src/empty.sh" "echo empty"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
create_squad_evidence "squad_manifest_empty"
printf '{"launched":[]}\n' > "verification_findings/squad_manifest_empty/manifest.json"
run_hook --internal --skip-tests --local-verify -m "empty manifest"
assert_exit 0 "exits 0 (empty launched array falls back to default 5)"
teardown_repo

# --- Test 33: no manifest.json -> uses default 5 agents ---
echo ""
echo "Test 33: no manifest.json -> uses default 5 agents"
setup_repo
stage_code_file "src/default.sh" "echo default"
HASH=$(get_staged_hash)
create_agent_evidence "$HASH"
create_squad_evidence "squad_no_manifest"
# No manifest.json in squad dir
run_hook --internal --skip-tests --local-verify -m "no manifest"
assert_exit 0 "exits 0 (no manifest uses default 5)"
teardown_repo

# --- Test 34: cleanup respects manifest — only removes listed agents, squad dir cleaned ---
echo ""
echo "Test 34: Cleanup loop respects manifest.json -> cleans up 2-agent squad dir"
setup_repo
stage_code_file "src/cleanup.sh" "echo cleanup"
# Create manifest-filtered squad: only 2 agents (mechanical + cold_reader)
mkdir -p "verification_findings/squad_manifest_cleanup"
printf 'VERDICT: PASS\n' > "verification_findings/squad_manifest_cleanup/mechanical.md"
printf 'VERDICT: PASS\n' > "verification_findings/squad_manifest_cleanup/cold_reader.md"
printf '{"launched":["mechanical.md","cold_reader.md"],"reason":"test cleanup"}\n' > "verification_findings/squad_manifest_cleanup/manifest.json"
run_hook --internal --skip-tests --local-verify -m "manifest cleanup"
assert_exit 0 "exits 0 with manifest-filtered squad"
assert_file_not_exists "verification_findings/squad_manifest_cleanup" "manifest-filtered squad dir removed after commit"
teardown_repo

# ==================== SUMMARY ====================

echo ""
echo "========================================="
if [[ $FAIL -gt 0 ]]; then
  echo -e "  RESULTS: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} ($TOTAL total)"
else
  echo -e "  RESULTS: ${GREEN}$PASS passed${NC}, $FAIL failed ($TOTAL total)"
fi
echo "========================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  echo "All tests passed."
  exit 0
fi
