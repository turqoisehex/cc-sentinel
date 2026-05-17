#!/usr/bin/env bash
set -euo pipefail

# codex-verify-agent.sh — dispatch one Codex verification agent
# Usage: codex-verify-agent.sh -m MODEL -r ROLE -w WORK_PRODUCT -s SOURCE_SPEC -S "SCOPE" -o OUTPUT_PATH [--project-root DIR] [--reasoning LEVEL]

usage() {
  echo "Usage: $0 -m MODEL -r ROLE -w WORK_PRODUCT -s SOURCE_SPEC -S SCOPE -o OUTPUT_PATH [--project-root DIR] [--reasoning LEVEL]" >&2
  exit 1
}

MODEL="" ROLE="" WORK_PRODUCT="" SOURCE_SPEC="" SCOPE_SUMMARY="" OUTPUT_PATH="" PROJECT_ROOT="$PWD" REASONING=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) MODEL="$2"; shift 2 ;;
    -r) ROLE="$2"; shift 2 ;;
    -w) WORK_PRODUCT="$2"; shift 2 ;;
    -s) SOURCE_SPEC="$2"; shift 2 ;;
    -S) SCOPE_SUMMARY="$2"; shift 2 ;;
    -o) OUTPUT_PATH="$2"; shift 2 ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --reasoning) REASONING="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$MODEL" || -z "$ROLE" || -z "$WORK_PRODUCT" || -z "$SOURCE_SPEC" || -z "$SCOPE_SUMMARY" || -z "$OUTPUT_PATH" ]] && usage

# Validate ROLE
case "$ROLE" in
  mechanical|adversarial|completeness|dependency|cold_reader) ;;
  *) echo "ERROR: Invalid role '$ROLE'" >&2; exit 1 ;;
esac

TMP_FILE="${OUTPUT_PATH}.tmp"
RAW_FILE="${OUTPUT_PATH}.raw.md"
STDERR_TMP="${OUTPUT_PATH}.stderr.tmp"

# Step 1: Auth pre-flight
AUTH_FILE="$HOME/.codex/auth.json"
if [[ ! -f "$AUTH_FILE" ]]; then
  echo "VERDICT: TRANSIENT — auth not configured" > "$TMP_FILE"
  mv -f "$TMP_FILE" "$OUTPUT_PATH"
  exit 0
fi
if ! grep -q '"auth_mode"' "$AUTH_FILE" 2>/dev/null; then
  echo "VERDICT: TRANSIENT — auth not configured" > "$TMP_FILE"
  mv -f "$TMP_FILE" "$OUTPUT_PATH"
  exit 0
fi

# Step 2: Build prompt from template
PROMPTS_FILE="$HOME/.claude/reference/codex-verification-prompts.md"
if [[ ! -f "$PROMPTS_FILE" ]]; then
  echo "VERDICT: TRANSIENT — prompts file missing ($PROMPTS_FILE)" > "$TMP_FILE"
  mv -f "$TMP_FILE" "$OUTPUT_PATH"
  exit 0
fi

# Extract role section: between "## ROLE_UPPER" and the next "---" separator
# Role headings are ALL-CAPS H2 (## MECHANICAL, ## ADVERSARIAL, etc.)
# Prompt bodies contain mixed-case H2 (## Summary, ## Detail, ## UX Journey Trace)
# so we use "---" as the inter-role delimiter instead of matching on H2 headings.
ROLE_UPPER=$(echo "$ROLE" | tr '[:lower:]' '[:upper:]' | tr '_' ' ')
PROMPT_BODY=$(awk "/^## ${ROLE_UPPER}/{found=1; next} /^---$/{if(found) exit} found{print}" "$PROMPTS_FILE")

# Splice placeholders
PROMPT_BODY=$(echo "$PROMPT_BODY" | sed \
  -e "s|{{WORK_PRODUCT}}|${WORK_PRODUCT}|g" \
  -e "s|{{SOURCE_SPEC}}|${SOURCE_SPEC}|g" \
  -e "s|{{SCOPE_SUMMARY}}|${SCOPE_SUMMARY}|g")

# Step 3: Invoke codex exec (with reasoning-flag fallback per design-spec section 4.2)
CODEX_ARGS=(-m "$MODEL" -s read-only --skip-git-repo-check --ephemeral)
USED_REASONING=""
if [[ -n "$REASONING" ]]; then
  CODEX_ARGS+=(-c "model_reasoning_effort=\"$REASONING\"")
  USED_REASONING="$REASONING"
fi

cd "$PROJECT_ROOT"

CODEX_EXIT=0
echo "$PROMPT_BODY" | codex exec "${CODEX_ARGS[@]}" > "${RAW_FILE}" 2>"$STDERR_TMP" || CODEX_EXIT=$?

# Reasoning-flag fallback: if non-zero exit AND reasoning was set, retry without it
if [[ $CODEX_EXIT -ne 0 && -n "$USED_REASONING" ]]; then
  if grep -qiE 'invalid.*option|unknown.*flag|unrecognized|model_reasoning' "$STDERR_TMP" 2>/dev/null; then
    echo "WARN: reasoning flag '$USED_REASONING' rejected by codex exec; retrying without it" >&2
    CODEX_ARGS=(-m "$MODEL" -s read-only --skip-git-repo-check --ephemeral)
    CODEX_EXIT=0
    echo "$PROMPT_BODY" | codex exec "${CODEX_ARGS[@]}" > "${RAW_FILE}" 2>"$STDERR_TMP" || CODEX_EXIT=$?
  fi
fi

# Non-zero exit handler
if [[ $CODEX_EXIT -ne 0 ]]; then
  STDERR_FIRST=$(head -1 "$STDERR_TMP" 2>/dev/null || echo "unknown error")
  if grep -qiE 'usage.limit|rate.limit|429|too many requests|quota' "$STDERR_TMP" 2>/dev/null; then
    echo "VERDICT: TRANSIENT — rate limit" > "$TMP_FILE"
  else
    echo "VERDICT: TRANSIENT — exit $CODEX_EXIT $STDERR_FIRST" > "$TMP_FILE"
  fi
  mv -f "$TMP_FILE" "$OUTPUT_PATH"
  rm -f "$STDERR_TMP"
  exit 0
fi

# Step 4: Extract structured output (last valid VERDICT to EOF)
LAST_VERDICT_LINE=$(grep -n '^VERDICT: \(PASS\|WARN\|FAIL\)' "$RAW_FILE" | tail -1 | cut -d: -f1)

if [[ -n "$LAST_VERDICT_LINE" ]]; then
  # Extract from last VERDICT line to end of file
  tail -n +"$LAST_VERDICT_LINE" "$RAW_FILE" > "$TMP_FILE"
else
  # Step 7: No valid VERDICT found
  echo "VERDICT: TRANSIENT — malformed output (exit 0, no VERDICT line)" > "$TMP_FILE"
  # RAW_FILE already preserved from step 3
  mv -f "$TMP_FILE" "$OUTPUT_PATH"
  rm -f "$STDERR_TMP"
  exit 0
fi

# Step 5: Validate extraction
if ! grep -q '^VERDICT: \(PASS\|WARN\|FAIL\)' "$TMP_FILE"; then
  echo "VERDICT: TRANSIENT — malformed output (exit 0, no VERDICT line)" > "$TMP_FILE"
fi

# Step 8: Atomic write
mv -f "$TMP_FILE" "$OUTPUT_PATH"
rm -f "$STDERR_TMP"
exit 0
