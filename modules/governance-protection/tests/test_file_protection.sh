#!/usr/bin/env bash
# Test harness for file-protection.sh
# Run: bash modules/governance-protection/tests/test_file_protection.sh
#
# Creates temp directories with mock CT files and protected-files.txt,
# pipes mock JSON stdin, asserts exit code and stdout content.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/file-protection.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: file-protection.sh not found at $HOOK_SCRIPT" >&2
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
  mkdir -p "$PROJECT/.git"  # fake git repo so find_project_dir works
  mkdir -p "$PROJECT/.claude"
}

teardown_temp() {
  rm -rf "$TMPDIR_ROOT" 2>/dev/null
}

# Create protected-files.txt in project root
create_protected_list() {
  local dir="$1"
  shift
  {
    echo "# Protected files for testing"
    for f in "$@"; do
      echo "$f"
    done
  } > "$dir/protected-files.txt"
}

# Build JSON for Write tool editing a file
build_write_input() {
  local file_path="$1"
  cat << EOF
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "$file_path",
    "content": "new content"
  }
}
EOF
}

# Build JSON for Edit tool
build_edit_input() {
  local file_path="$1"
  cat << EOF
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "$file_path",
    "old_string": "old",
    "new_string": "new"
  }
}
EOF
}

# Build JSON for MultiEdit tool
build_multiedit_input() {
  local file_path1="$1" file_path2="$2"
  cat << EOF
{
  "tool_name": "MultiEdit",
  "tool_input": {
    "edits": [
      {"file_path": "$file_path1", "old_string": "a", "new_string": "b"},
      {"file_path": "$file_path2", "old_string": "c", "new_string": "d"}
    ]
  }
}
EOF
}

# Build JSON for Bash tool (should be ignored)
build_bash_input() {
  cat << EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "echo hello"
  }
}
EOF
}

# Create CT file with optional GOVERNANCE-EDIT-AUTHORIZED marker
create_ct() {
  local dir="$1" authorized="$2"
  if [[ "$authorized" == "true" ]]; then
    cat > "$dir/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Status:** IN PROGRESS
GOVERNANCE-EDIT-AUTHORIZED
## Plan
- Edit governance files
EOF
  else
    cat > "$dir/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Status:** IN PROGRESS
## Plan
- Regular work
EOF
  fi
}

create_channel_ct() {
  local dir="$1" channel="$2" authorized="$3"
  if [[ "$authorized" == "true" ]]; then
    cat > "$dir/CURRENT_TASK_ch${channel}.md" << EOF
# CURRENT TASK — Channel $channel
**Channel:** $channel
**Status:** IN PROGRESS
GOVERNANCE-EDIT-AUTHORIZED
## Plan
- Edit governance files
EOF
  else
    cat > "$dir/CURRENT_TASK_ch${channel}.md" << EOF
# CURRENT TASK — Channel $channel
**Channel:** $channel
**Status:** IN PROGRESS
## Plan
- Regular work
EOF
  fi
}

run_hook() {
  local input="$1"
  local stdout_file="$TMPDIR_ROOT/stdout"
  local stderr_file="$TMPDIR_ROOT/stderr"
  echo "$input" | bash "$HOOK_SCRIPT" > "$stdout_file" 2> "$stderr_file"
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
  if echo "$LAST_STDOUT" | grep -qiE "$pattern" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}: $label (stdout matches)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — stdout does not match '$pattern'"
    echo "    stdout: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

assert_stdout_empty() {
  local label="$1"
  TOTAL=$((TOTAL + 1))
  if [[ -z "$LAST_STDOUT" ]]; then
    echo -e "  ${GREEN}PASS${NC}: $label (stdout empty = allow)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected empty stdout, got:"
    echo "    stdout: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

# ==================== TESTS ====================

echo "=== file-protection.sh Test Harness ==="
echo ""

# --- Test 1: Non-file tool -> allow ---
echo "Test 1: Non-file tool (Bash) -> silent allow"
setup_temp
create_protected_list "$PROJECT" "CLAUDE.md" "settings.json"
create_ct "$PROJECT" "false"
INPUT=$(build_bash_input)
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "Bash tool not checked"
teardown_temp

# --- Test 2: Editing unprotected file -> allow ---
echo ""
echo "Test 2: Editing unprotected file -> allow"
setup_temp
create_protected_list "$PROJECT" "CLAUDE.md" "settings.json"
create_ct "$PROJECT" "false"
INPUT=$(build_write_input "$PROJECT/lib/main.dart")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "unprotected file is allowed"
teardown_temp

# --- Test 3: Editing protected file without authorization -> deny ---
echo ""
echo "Test 3: Editing protected file without auth -> deny"
setup_temp
create_protected_list "$PROJECT" "CLAUDE.md" "settings.json"
create_ct "$PROJECT" "false"
INPUT=$(build_write_input "$PROJECT/CLAUDE.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "PROTECTED" "blocks protected file"
assert_stdout_contains "CLAUDE.md" "names the blocked file"
assert_stdout_contains "GOVERNANCE-EDIT-AUTHORIZED" "tells how to authorize"
teardown_temp

# --- Test 4: Editing protected file WITH authorization -> allow ---
echo ""
echo "Test 4: Editing protected file with GOVERNANCE-EDIT-AUTHORIZED -> allow"
setup_temp
create_protected_list "$PROJECT" "CLAUDE.md" "settings.json"
create_ct "$PROJECT" "true"
INPUT=$(build_write_input "$PROJECT/CLAUDE.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "authorized edit is allowed"
teardown_temp

# --- Test 5: Channel CT authorization -> allow ---
echo ""
echo "Test 5: Channel CT has GOVERNANCE-EDIT-AUTHORIZED -> allow"
setup_temp
create_protected_list "$PROJECT" "CLAUDE.md"
create_ct "$PROJECT" "false"
create_channel_ct "$PROJECT" "2" "true"
INPUT=$(build_write_input "$PROJECT/CLAUDE.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "channel CT authorization accepted"
teardown_temp

# --- Test 6: Edit tool on protected file -> deny ---
echo ""
echo "Test 6: Edit tool on protected file -> deny"
setup_temp
create_protected_list "$PROJECT" "settings.json"
create_ct "$PROJECT" "false"
INPUT=$(build_edit_input "$PROJECT/.claude/settings.json")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "PROTECTED" "Edit tool blocked on protected file"
assert_stdout_contains "settings.json" "names the file"
teardown_temp

# --- Test 7: No protected-files.txt -> allow everything ---
echo ""
echo "Test 7: No protected-files.txt -> allow all edits"
setup_temp
# Don't create any protected-files.txt
# Override HOME so global ~/.claude/protected-files.txt isn't found
create_ct "$PROJECT" "false"
INPUT=$(build_write_input "$PROJECT/CLAUDE.md")
HOME="$TMPDIR_ROOT" run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "no protected-files.txt means no protection"
teardown_temp

# --- Test 8: Comment in protected-files.txt -> ignored ---
echo ""
echo "Test 8: Commented-out entry in protected list -> not protected"
setup_temp
cat > "$PROJECT/protected-files.txt" << 'EOF'
# Protected files
CLAUDE.md
# settings.json
EOF
create_ct "$PROJECT" "false"
# settings.json is commented out, should be allowed
INPUT=$(build_write_input "$PROJECT/.claude/settings.json")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "commented-out file is not protected"
teardown_temp

# --- Test 9: Protected file in subdirectory -> matches by basename ---
echo ""
echo "Test 9: Protected file matched by basename regardless of path"
setup_temp
create_protected_list "$PROJECT" "CLAUDE.md"
create_ct "$PROJECT" "false"
INPUT=$(build_write_input "$PROJECT/some/nested/dir/CLAUDE.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "PROTECTED" "basename match works for nested paths"
teardown_temp

# --- Test 10: Output is valid JSON with deny decision ---
echo ""
echo "Test 10: Deny output is valid JSON with correct structure"
setup_temp
create_protected_list "$PROJECT" "CLAUDE.md"
create_ct "$PROJECT" "false"
INPUT=$(build_write_input "$PROJECT/CLAUDE.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if echo "$LAST_STDOUT" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC}: output has hookSpecificOutput.permissionDecision"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: output missing expected JSON structure"
  echo "    stdout: $LAST_STDOUT"
  FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
DECISION=$(echo "$LAST_STDOUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
if [[ "$DECISION" == "deny" ]]; then
  echo -e "  ${GREEN}PASS${NC}: permissionDecision is 'deny'"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: expected permissionDecision='deny', got '$DECISION'"
  FAIL=$((FAIL + 1))
fi
teardown_temp

# --- Test 11: protected-files.txt in .claude/ subdirectory ---
echo ""
echo "Test 11: protected-files.txt in .claude/ subdirectory works"
setup_temp
mkdir -p "$PROJECT/.claude"
cat > "$PROJECT/.claude/protected-files.txt" << 'EOF'
CLAUDE.md
EOF
create_ct "$PROJECT" "false"
INPUT=$(build_write_input "$PROJECT/CLAUDE.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "PROTECTED" ".claude/protected-files.txt is found"
teardown_temp

# --- Test 12: GOVERNANCE-EDIT-AUTHORIZED must be standalone line ---
echo ""
echo "Test 12: GOVERNANCE-EDIT-AUTHORIZED embedded in text -> not authorized"
setup_temp
create_protected_list "$PROJECT" "CLAUDE.md"
cat > "$PROJECT/CURRENT_TASK.md" << 'EOF'
# CURRENT TASK
**Status:** IN PROGRESS
Need to add GOVERNANCE-EDIT-AUTHORIZED to proceed.
## Plan
- Edit governance files
EOF
INPUT=$(build_write_input "$PROJECT/CLAUDE.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "PROTECTED" "embedded marker not accepted as authorization"
teardown_temp

# --- Test 13: .env file -> deny (sensitive pattern) ---
echo ""
echo "Test 13: .env file -> deny (sensitive pattern)"
setup_temp
# No protected-files.txt needed — sensitive-patterns.txt triggers
cp "$(cd "$SCRIPT_DIR/.." && pwd)/sensitive-patterns.txt" "$PROJECT/sensitive-patterns.txt"
create_ct "$PROJECT" "false"
INPUT=$(build_edit_input "$PROJECT/.env")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "SENSITIVE" ".env denied by sensitive patterns"
teardown_temp

# --- Test 14: .env.example -> allow (negation exemption) ---
echo ""
echo "Test 14: .env.example -> allow (negation exemption)"
setup_temp
cp "$(cd "$SCRIPT_DIR/.." && pwd)/sensitive-patterns.txt" "$PROJECT/sensitive-patterns.txt"
create_ct "$PROJECT" "false"
INPUT=$(build_edit_input "$PROJECT/.env.example")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty ".env.example allowed by negation"
teardown_temp

# --- Test 15: .ssh/id_rsa -> deny (SSH key) ---
echo ""
echo "Test 15: .ssh/id_rsa -> deny (SSH key)"
setup_temp
cp "$(cd "$SCRIPT_DIR/.." && pwd)/sensitive-patterns.txt" "$PROJECT/sensitive-patterns.txt"
create_ct "$PROJECT" "false"
INPUT=$(build_edit_input "$PROJECT/.ssh/id_rsa")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "SENSITIVE" "id_rsa denied by sensitive patterns"
teardown_temp

# --- Test 16: src/main.py -> allow (normal file) ---
echo ""
echo "Test 16: src/main.py -> allow (normal file)"
setup_temp
cp "$(cd "$SCRIPT_DIR/.." && pwd)/sensitive-patterns.txt" "$PROJECT/sensitive-patterns.txt"
create_ct "$PROJECT" "false"
INPUT=$(build_edit_input "$PROJECT/src/main.py")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "normal source file allowed"
teardown_temp

# --- Test 17: .aws/credentials -> deny (cloud) ---
echo ""
echo "Test 17: .aws/credentials -> deny (cloud)"
setup_temp
cp "$(cd "$SCRIPT_DIR/.." && pwd)/sensitive-patterns.txt" "$PROJECT/sensitive-patterns.txt"
create_ct "$PROJECT" "false"
INPUT=$(build_edit_input "$PROJECT/.aws/credentials")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "SENSITIVE" ".aws/credentials denied by sensitive patterns"
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
