#!/usr/bin/env bash
# Test harness for agent-file-reminder.sh
# Run: bash modules/core/tests/test_agent_file_reminder.sh
#
# Pipes mock JSON stdin mimicking Agent tool calls and checks
# whether the hook correctly warns about file-writing obligations.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/agent-file-reminder.sh"

if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "ERROR: agent-file-reminder.sh not found at $HOOK_SCRIPT" >&2
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

build_agent_input() {
  local agent_type="$1" prompt="$2"
  local prompt_json
  prompt_json=$(printf '%s' "$prompt" | jq -Rs '.')
  cat << EOF
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "$agent_type",
    "prompt": $prompt_json
  }
}
EOF
}

build_non_agent_input() {
  cat << EOF
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "echo hello"
  }
}
EOF
}

run_hook() {
  local input="$1"
  LAST_STDOUT=$(echo "$input" | bash "$HOOK_SCRIPT" 2>/dev/null)
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
    echo -e "  ${GREEN}PASS${NC}: $label (stdout empty)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label — expected empty stdout, got:"
    echo "    stdout: $LAST_STDOUT"
    FAIL=$((FAIL + 1))
  fi
}

# ==================== TESTS ====================

echo "=== agent-file-reminder.sh Test Harness ==="
echo ""

# --- Test 1: Non-Agent tool -> silent ---
echo "Test 1: Non-Agent tool (Bash) -> silent pass-through"
INPUT=$(build_non_agent_input)
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "Bash tool ignored"

# --- Test 2: Explore agent -> warns about no file writing ---
echo ""
echo "Test 2: Explore agent -> warns about saving output"
INPUT=$(build_agent_input "Explore" "Find all test files in the project")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CANNOT write files" "warns Explore agent cannot write"
assert_stdout_contains "Explore" "names the agent type"

# --- Test 3: Plan agent -> warns about no file writing ---
echo ""
echo "Test 3: Plan agent -> warns about saving output"
INPUT=$(build_agent_input "Plan" "Create an implementation plan for the feature")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "CANNOT write files" "warns Plan agent cannot write"

# --- Test 4: General-purpose agent WITHOUT file instructions -> warns ---
echo ""
echo "Test 4: General-purpose agent without file instructions -> warns"
INPUT=$(build_agent_input "general-purpose" "Run all tests and report any failures")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "AGENTS WRITE TO FILES" "warns about missing file instructions"
assert_stdout_contains "does not appear to include" "explains the issue"

# --- Test 5: General-purpose agent WITH file-writing instructions -> silent ---
echo ""
echo "Test 5: General-purpose agent with file instructions -> silent"
INPUT=$(build_agent_input "general-purpose" "Verify the implementation and write results to verification_findings/agent_test.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "agent with file instructions not warned"

# --- Test 6: Agent prompt mentions 'save findings to file' -> silent ---
echo ""
echo "Test 6: Agent prompt with 'save...to file' pattern -> silent"
INPUT=$(build_agent_input "general-purpose" "Check for bugs and save your findings to a file named report.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "save-to-file pattern detected"

# --- Test 7: Agent prompt mentions 'output results to' -> silent ---
echo ""
echo "Test 7: Agent prompt with 'output results' pattern -> silent"
INPUT=$(build_agent_input "general-purpose" "Run the audit and output results to verification_findings/audit.md")
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_empty "'output results' pattern detected"

# --- Test 8: Output is valid JSON ---
echo ""
echo "Test 8: Warning output is valid JSON"
INPUT=$(build_agent_input "Explore" "Search for patterns")
run_hook "$INPUT"
assert_exit 0 "exit 0"
TOTAL=$((TOTAL + 1))
if echo "$LAST_STDOUT" | jq -e '.additionalContext' >/dev/null 2>&1; then
  echo -e "  ${GREEN}PASS${NC}: output is valid JSON with additionalContext"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: output is not valid JSON"
  echo "    stdout: $LAST_STDOUT"
  FAIL=$((FAIL + 1))
fi

# --- Test 9: Agent with no subagent_type -> defaults to general-purpose ---
echo ""
echo "Test 9: Missing subagent_type -> defaults behavior"
INPUT='{"tool_name": "Agent", "tool_input": {"prompt": "Do something without file output"}}'
run_hook "$INPUT"
assert_exit 0 "exit 0"
assert_stdout_contains "AGENTS WRITE TO FILES" "default type still gets file-writing check"

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
