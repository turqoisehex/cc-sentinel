#!/usr/bin/env bash
# Test harness for comment-replacement.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/hooks/comment-replacement.sh"

[[ ! -f "$HOOK_SCRIPT" ]] && echo "ERROR: comment-replacement.sh not found" >&2 && exit 1

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
[[ ! -t 1 ]] && RED="" && GREEN="" && NC=""

assert_eq() {
  TOTAL=$((TOTAL + 1))
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf "${GREEN}PASS${NC} %s\n" "$label"; PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC} %s\n  expected: %s\n  actual:   %s\n" "$label" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    printf "${GREEN}PASS${NC} %s\n" "$label"; PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC} %s\n  expected to contain: %s\n" "$label" "$needle"; FAIL=$((FAIL + 1))
  fi
}

# T1: Code replaced with comments → warning
echo "--- T1: Code replaced with comments ---"
INPUT='{"tool_name":"Edit","tool_input":{"file_path":"src/main.py","old_string":"def process():\n    data = fetch()\n    return transform(data)","new_string":"# TODO: implement process function\n# This was removed for now"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_contains "T1: warns about replacement" "additionalContext" "$OUTPUT"

# T2: Normal code edit → no warning
echo "--- T2: Normal code edit ---"
INPUT='{"tool_name":"Edit","tool_input":{"file_path":"src/main.py","old_string":"x = 1","new_string":"x = 2"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T2: no warning" "" "$OUTPUT"

# T3: Markdown file → skip
echo "--- T3: Markdown file ---"
INPUT='{"tool_name":"Edit","tool_input":{"file_path":"docs/README.md","old_string":"old text","new_string":"# new heading"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T3: skip markdown" "" "$OUTPUT"

# T4: Non-Edit tool → skip
echo "--- T4: Write tool ---"
INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/new.py","content":"# all comments"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T4: skip Write" "" "$OUTPUT"

# T5: Old content was already comments → skip
echo "--- T5: Comment-to-comment ---"
INPUT='{"tool_name":"Edit","tool_input":{"file_path":"src/main.py","old_string":"# old comment\n# another comment","new_string":"# new comment\n# different comment"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T5: skip comment-to-comment" "" "$OUTPUT"

# T6: MultiEdit code→comment → warning
echo "--- T6: MultiEdit code→comment ---"
INPUT='{"tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":"src/main.py","old_string":"def run():\n    process()","new_string":"# TODO: implement\n# removed"}]}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_contains "T6: MultiEdit warns" "additionalContext" "$OUTPUT"

# T7: MultiEdit on markdown file → skip (per-edit file path check)
echo "--- T7: MultiEdit markdown skip ---"
INPUT='{"tool_name":"MultiEdit","tool_input":{"edits":[{"file_path":"docs/README.md","old_string":"old text","new_string":"# New Section\n## Overview"}]}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK_SCRIPT" 2>/dev/null)
assert_eq "T7: MultiEdit skip markdown" "" "$OUTPUT"

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
