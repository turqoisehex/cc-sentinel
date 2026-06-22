#!/usr/bin/env bash
# Test harness for context-awareness-statusline.sh
# Run: bash modules/context-awareness/tests/test_context_awareness_statusline.sh
#
# Pipes mock Claude Code statusline JSON on stdin and asserts the rendered
# percentage. Focus: the percentage is derived from REAL token counts (not the
# payload's clamped used_percentage), and a provably-impossible window report
# (used_tokens > context_window_size) self-corrects to the 1M tier.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE="$(cd "$SCRIPT_DIR/.." && pwd)/context-awareness-statusline.sh"

if [[ ! -f "$STATUSLINE" ]]; then
  echo "ERROR: context-awareness-statusline.sh not found at $STATUSLINE" >&2
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
if [[ ! -t 1 ]]; then RED=""; GREEN=""; NC=""; fi

# Temp config with a sandboxed flag dir so we never touch real /tmp session flags.
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT
CONFIG_FILE="$TMPDIR_ROOT/config.json"
cat > "$CONFIG_FILE" <<EOF
{ "flag_dir": "$TMPDIR_ROOT/flags", "statusline": { "enabled": true } }
EOF
mkdir -p "$TMPDIR_ROOT/flags"
export CC_CTX_CONFIG="$CONFIG_FILE"

# render <session_id> <json> -> echoes the statusline output with ANSI stripped
render() {
  printf '%s' "$2" | bash "$STATUSLINE" | sed 's/\x1b\[[0-9;]*m//g'
}

# assert_pct <name> <json> <expected_pct_substring e.g. "50%">
assert_pct() {
  local name="$1" json="$2" want="$3"
  TOTAL=$((TOTAL+1))
  local out; out="$(render "s$TOTAL" "$json")"
  if [[ "$out" == *"$want"* ]]; then
    PASS=$((PASS+1)); printf "${GREEN}PASS${NC}: %s -> %s\n" "$name" "$want"
  else
    FAIL=$((FAIL+1)); printf "${RED}FAIL${NC}: %s — wanted '%s', got: %s\n" "$name" "$want" "$out"
  fi
}

# refute_pct <name> <json> <unwanted e.g. "100%">
refute_pct() {
  local name="$1" json="$2" bad="$3"
  TOTAL=$((TOTAL+1))
  local out; out="$(render "s$TOTAL" "$json")"
  if [[ "$out" != *"$bad"* ]]; then
    PASS=$((PASS+1)); printf "${GREEN}PASS${NC}: %s — correctly not '%s'\n" "$name" "$bad"
  else
    FAIL=$((FAIL+1)); printf "${RED}FAIL${NC}: %s — should NOT contain '%s', got: %s\n" "$name" "$bad" "$out"
  fi
}

echo "=== context-awareness-statusline.sh ==="

# 1. Normal, correctly-reported 200k window: parity with stock used_percentage.
assert_pct "200k window, 100k tokens" \
  '{"session_id":"x","context_window":{"total_input_tokens":100000,"context_window_size":200000}}' "50%"

# 2. Correctly-reported 1M window.
assert_pct "1M window, 850k tokens" \
  '{"session_id":"x","context_window":{"total_input_tokens":850000,"context_window_size":1000000}}' "85%"

# 3. THE FIX: mislabeled window (1M build reporting 200000). used_tokens exceeds
#    the reported window, so the report is provably wrong -> correct to 1M tier.
assert_pct "mislabeled 1M (879k tok, reports 200k)" \
  '{"session_id":"x","context_window":{"total_input_tokens":878889,"context_window_size":200000,"used_percentage":100}}' "87%"
refute_pct "mislabeled 1M does not pin at 100%" \
  '{"session_id":"x","context_window":{"total_input_tokens":878889,"context_window_size":200000,"used_percentage":100}}' "100%"

# 4. Fallback: older CC payloads with only used_percentage (no token fields).
assert_pct "fallback to used_percentage=42" \
  '{"session_id":"x","context_window":{"used_percentage":42,"context_window_size":200000}}' "42%"

# 5. Fallback: current_usage sum when total_input_tokens is absent (2+10000+40000=50002).
assert_pct "current_usage sum (no total_input_tokens)" \
  '{"session_id":"x","context_window":{"current_usage":{"input_tokens":2,"cache_creation_input_tokens":10000,"cache_read_input_tokens":40000},"context_window_size":200000}}' "25%"

# 6. Degenerate: empty context_window must not crash and reads 0%.
assert_pct "empty context_window -> 0%" \
  '{"session_id":"x","context_window":{}}' "0%"

echo "========================================="
echo "  RESULTS: $PASS passed, $FAIL failed ($TOTAL total)"
echo "========================================="
[[ "$FAIL" -eq 0 ]] && { echo "All tests passed."; exit 0; } || { echo "FAILURES present."; exit 1; }
