#!/usr/bin/env bash
# Test harness for pre-compact-state-save.sh
# Run: bash modules/core/tests/test_pre_compact.sh
#
# Creates temp directories with mock CURRENT_TASK files,
# pipes mock JSON stdin (PreCompact protocol), asserts exit code
# and stdout content.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/pre-compact-state-save.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: pre-compact-state-save.sh not found at $HOOK_SCRIPT" >&2
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
  # Create minimal CLAUDE.md so resolve_project_dir picks this dir over CWD
  touch "$PROJECT/CLAUDE.md"
}

teardown_temp() {
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

build_precompact_input() {
  local trigger="${1:-auto}"
  cat << EOF
{"trigger": "$trigger"}
EOF
}

run_hook() {
  local input="$1"
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"
  echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK_SCRIPT" > "$stdout_file" 2> "$stderr_file"
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
    echo "    stdout: ${LAST_STDOUT:0:300}"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_not_contains() {
  local pattern="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | grep -qiE "$pattern" 2>/dev/null; then
    echo -e "  ${RED}FAIL${NC}: $label — stdout unexpectedly matches '$pattern'"
    echo "    stdout: ${LAST_STDOUT:0:300}"
    FAIL=$((FAIL + 1))
  else
    echo -e "  ${GREEN}PASS${NC}: $label (pattern absent)"
    PASS=$((PASS + 1))
  fi
}

assert_json_valid() {
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | jq -e '.' >/dev/null 2>&1; then
    echo -e "  ${GREEN}PASS${NC}: $label (valid JSON)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — output is not valid JSON"
    echo "    stdout: ${LAST_STDOUT:0:300}"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_has_key() {
  local key="$1" label="$2"
  TOTAL=$((TOTAL + 1))
  if echo "$LAST_STDOUT" | jq -e ".$key" >/dev/null 2>&1; then
    echo -e "  ${GREEN}PASS${NC}: $label (key '$key' present)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — JSON missing key '$key'"
    echo "    stdout: ${LAST_STDOUT:0:300}"
    FAIL=$((FAIL + 1))
  fi
}

create_ct() {
  local dir="$1" content="$2"
  printf '%s' "$content" > "$dir/CURRENT_TASK.md"
}

create_channel_ct() {
  local dir="$1" channel="$2" content="$3"
  printf '%s' "$content" > "$dir/CURRENT_TASK_ch${channel}.md"
}

# ==================== TESTS ====================

echo "=== pre-compact-state-save.sh Test Harness ==="
echo ""

# --- Test 1: No state files -> generic message, exit 0 ---
echo "Test 1: No state files -> generic compaction message"
setup_temp
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "COMPACTION IMMINENT" "outputs compaction warning"
assert_stdout_contains "Write current work state" "generic message (no state files)"
assert_stdout_not_contains "state files for reference" "no reference header when no files exist"
teardown_temp

# --- Test 2: CURRENT_TASK.md exists -> includes file content ---
echo ""
echo "Test 2: CURRENT_TASK.md exists -> includes state file content"
setup_temp
create_ct "$PROJECT" "# CURRENT TASK
**Status:** IN PROGRESS
## Plan
- Step 1: Implement feature X"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "state files for reference" "reference header present"
assert_stdout_contains "CURRENT_TASK.md" "mentions shared CT filename"
assert_stdout_contains "Implement feature X" "includes file content"
teardown_temp

# --- Test 3: CURRENT_TASK_ch1.md exists -> picked up by glob ---
echo ""
echo "Test 3: Channel CT (ch1) -> picked up by glob"
setup_temp
create_channel_ct "$PROJECT" "1" "# Channel 1 Task
**Status:** IN PROGRESS
- Working on audio system"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "state files for reference" "reference header present"
assert_stdout_contains "CURRENT_TASK_ch1.md" "mentions channel 1 filename"
assert_stdout_contains "audio system" "includes channel file content"
teardown_temp

# --- Test 4: Both shared + channel files -> both included ---
echo ""
echo "Test 4: Shared CT + channel CT -> both included"
setup_temp
create_ct "$PROJECT" "# Shared task
Phase: /3 Implementation"
create_channel_ct "$PROJECT" "5" "# Channel 5
Working on meditation engine"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CURRENT_TASK.md" "shared CT mentioned"
assert_stdout_contains "CURRENT_TASK_ch5.md" "channel 5 CT mentioned"
assert_stdout_contains "Implementation" "shared content present"
assert_stdout_contains "meditation engine" "channel content present"
teardown_temp

# --- Test 5: CLAUDE_PROJECT_DIR env var -> resolves correctly ---
echo ""
echo "Test 5: CLAUDE_PROJECT_DIR resolves project dir"
setup_temp
create_ct "$PROJECT" "# Task from env var project
Status: active"
# Run from a different directory to prove CLAUDE_PROJECT_DIR is used
INPUT=$(build_precompact_input "auto")
# Explicitly cd to /tmp so pwd != PROJECT, but CLAUDE_PROJECT_DIR points correctly
local_stdout_file="$TMPDIR_ROOT/stdout5"
local_stderr_file="$TMPDIR_ROOT/stderr5"
echo "$INPUT" | (cd /tmp && CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK_SCRIPT") > "$local_stdout_file" 2> "$local_stderr_file"
LAST_EXIT=$?
LAST_STDOUT=$(cat "$local_stdout_file")
LAST_STDERR=$(cat "$local_stderr_file")
assert_exit 0 "exit 0"
assert_stdout_contains "env var project" "resolved via CLAUDE_PROJECT_DIR"
teardown_temp

# --- Test 6: Trigger field propagated into message ---
echo ""
echo "Test 6: Trigger field propagated into output message"
setup_temp
INPUT=$(build_precompact_input "PreCompact")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "PreCompact" "trigger value appears in message"
teardown_temp

# --- Test 7: Custom trigger value ---
echo ""
echo "Test 7: Custom trigger value propagated"
setup_temp
create_ct "$PROJECT" "# Some task"
INPUT=$(build_precompact_input "manual_95pct")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "manual_95pct" "custom trigger value in message"
teardown_temp

# --- Test 8: Output is valid JSON ---
echo ""
echo "Test 8: Output is valid JSON (no state files)"
setup_temp
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_json_valid "generic output parses as JSON"
teardown_temp

# --- Test 9: Output is valid JSON (with state files) ---
echo ""
echo "Test 9: Output is valid JSON (with state files)"
setup_temp
create_ct "$PROJECT" "# Task with special chars: \"quotes\" and \backslashes"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_json_valid "output with special chars parses as JSON"
teardown_temp

# --- Test 10: Output contains additionalContext key ---
echo ""
echo "Test 10: Output JSON has additionalContext key"
setup_temp
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_json_has_key "additionalContext" "additionalContext key present"
teardown_temp

# --- Test 11: additionalContext key present when state files exist ---
echo ""
echo "Test 11: additionalContext key present with state files"
setup_temp
create_ct "$PROJECT" "# Active task"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_json_has_key "additionalContext" "additionalContext key present with CT"
teardown_temp

# --- Test 12: Empty CURRENT_TASK.md -> still HAS_TASK=true ---
echo ""
echo "Test 12: Empty CURRENT_TASK.md -> still treated as state file"
setup_temp
create_ct "$PROJECT" ""
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "state files for reference" "empty file still triggers reference header"
assert_stdout_contains "CURRENT_TASK.md" "empty file still mentioned by name"
teardown_temp

# --- Test 13: Large CURRENT_TASK.md -> only first 50 lines ---
echo ""
echo "Test 13: Large CURRENT_TASK.md -> truncated to first 50 lines"
setup_temp
# Generate 100 lines, each uniquely identifiable
LARGE_CONTENT=""
for i in $(seq 1 100); do
  LARGE_CONTENT+="LINE_NUMBER_${i}_MARKER"$'\n'
done
create_ct "$PROJECT" "$LARGE_CONTENT"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "LINE_NUMBER_1_MARKER" "first line included"
assert_stdout_contains "LINE_NUMBER_50_MARKER" "line 50 included"
assert_stdout_not_contains "LINE_NUMBER_51_MARKER" "line 51 excluded (head -50)"
assert_stdout_not_contains "LINE_NUMBER_100_MARKER" "line 100 excluded"
teardown_temp

# --- Test 14: Multiple channel files -> all included ---
echo ""
echo "Test 14: Multiple channel CTs -> all included"
setup_temp
create_channel_ct "$PROJECT" "1" "Channel one content alpha"
create_channel_ct "$PROJECT" "3" "Channel three content beta"
create_channel_ct "$PROJECT" "7" "Channel seven content gamma"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CURRENT_TASK_ch1.md" "channel 1 filename"
assert_stdout_contains "CURRENT_TASK_ch3.md" "channel 3 filename"
assert_stdout_contains "CURRENT_TASK_ch7.md" "channel 7 filename"
assert_stdout_contains "alpha" "channel 1 content"
assert_stdout_contains "beta" "channel 3 content"
assert_stdout_contains "gamma" "channel 7 content"
teardown_temp

# --- Test 15: Generic message mentions ZERO context ---
echo ""
echo "Test 15: Generic message warns about zero context in next session"
setup_temp
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "ZERO context" "warns about context loss"
teardown_temp

# --- Test 16: State-file message includes mandatory update instructions ---
echo ""
echo "Test 16: State-file message includes update instructions"
setup_temp
create_ct "$PROJECT" "# Some task in progress"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "MANDATORY" "mandatory update instruction"
assert_stdout_contains "uncommitted changes" "mentions uncommitted changes"
assert_stdout_contains "AGENT IDS" "mentions agent ID persistence warning"
teardown_temp

# --- Test 17: Output has exactly one JSON object (single line) ---
echo ""
echo "Test 17: Output is a single JSON object"
setup_temp
create_ct "$PROJECT" "# Task"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
JSON_COUNT=$(echo "$LAST_STDOUT" | jq -c '.' 2>/dev/null | wc -l)
if [[ "$JSON_COUNT" -eq 1 ]]; then
  echo -e "  ${GREEN}PASS${NC}: exactly one JSON object in output"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: expected 1 JSON object, got $JSON_COUNT"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 18: Trigger defaults to 'unknown' when missing ---
echo ""
echo "Test 18: Missing trigger field -> defaults to 'unknown'"
setup_temp
INPUT='{}'
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "unknown" "trigger defaults to unknown"
teardown_temp

# --- Test 19: Newlines in CT content -> valid JSON ---
echo ""
echo "Test 19: CT with newlines and special chars -> valid JSON"
setup_temp
create_ct "$PROJECT" '# Task
Line with "double quotes"
Line with $dollar and `backticks`
Line with tab	here
End of file'
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_json_valid "special characters produce valid JSON"
assert_json_has_key "additionalContext" "additionalContext survives special chars"
teardown_temp

# --- Test 20: Channel file also truncated to 50 lines ---
echo ""
echo "Test 20: Large channel CT -> also truncated to 50 lines"
setup_temp
CH_CONTENT=""
for i in $(seq 1 80); do
  CH_CONTENT+="CH_LINE_${i}_TAG"$'\n'
done
create_channel_ct "$PROJECT" "2" "$CH_CONTENT"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CH_LINE_1_TAG" "channel line 1 included"
assert_stdout_contains "CH_LINE_50_TAG" "channel line 50 included"
assert_stdout_not_contains "CH_LINE_51_TAG" "channel line 51 excluded"
teardown_temp

# --- Test 21: Message includes 'first 50 lines' label ---
echo ""
echo "Test 21: Output labels content as 'first 50 lines'"
setup_temp
create_ct "$PROJECT" "# Some task"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "first 50 lines" "truncation label present"
teardown_temp

# --- Test 22: CLAUDE.md in project dir -> resolves even without CT ---
echo ""
echo "Test 22: CLAUDE.md present (no CT) -> still resolves project dir correctly"
setup_temp
# No CURRENT_TASK.md, but CLAUDE.md exists (project root marker)
echo "# CLAUDE.md" > "$PROJECT/CLAUDE.md"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
# Without CT files, we get the generic message — but it should still resolve and run
assert_stdout_contains "COMPACTION IMMINENT" "hook runs with CLAUDE.md as marker"
assert_stdout_contains "Write current work state" "generic message when only CLAUDE.md"
teardown_temp

# --- Test 23: additionalContext value is a string, not nested JSON ---
echo ""
echo "Test 23: additionalContext value is a string type"
setup_temp
create_ct "$PROJECT" "# Task"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
AC_TYPE=$(echo "$LAST_STDOUT" | jq -r '.additionalContext | type' 2>/dev/null)
if [[ "$AC_TYPE" == "string" ]]; then
  echo -e "  ${GREEN}PASS${NC}: additionalContext is a string"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: additionalContext type is '$AC_TYPE', expected 'string'"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 24: HAS_TASK=true path includes YAML FRONTMATTER instructions ---
echo ""
echo "Test 24: CT exists -> YAML FRONTMATTER instructions in output"
setup_temp
create_ct "$PROJECT" "# Active task"
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "YAML FRONTMATTER" "YAML FRONTMATTER instruction present"
assert_stdout_contains "goal:" "frontmatter field 'goal' mentioned"
assert_stdout_contains "now:" "frontmatter field 'now' mentioned"
assert_stdout_contains "next:" "frontmatter field 'next' mentioned"
teardown_temp

# --- Test 25: HAS_TASK=false path includes YAML FRONTMATTER instructions ---
echo ""
echo "Test 25: No CT -> YAML FRONTMATTER instructions still in output"
setup_temp
INPUT=$(build_precompact_input "auto")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "YAML FRONTMATTER" "YAML FRONTMATTER instruction in generic path"
assert_stdout_contains "goal:" "frontmatter field 'goal' in generic path"
assert_stdout_contains "now:" "frontmatter field 'now' in generic path"
assert_stdout_contains "next:" "frontmatter field 'next' in generic path"
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
