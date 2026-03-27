#!/usr/bin/env bash
# Stop hook: blocks two specific mistakes at session stop time.
#
# Glossary: CC = Claude Code, CT = CURRENT_TASK (the .md state files).
#
# REQUIREMENTS:
#   R1. Completion gate — if assistant claims work is done (completion language
#       in last message), require verification evidence before allowing stop.
#       Evidence: squad dir with 5 PASS/WARN verdicts, or VERIFICATION_BLOCKED
#       marker in the active CT file. (WARN = issues found but non-blocking.)
#   R2. Staleness gate — if any active CT file is >2 min stale, block and
#       request progress update before stopping.
#   R3. Listener bypass — Sonnet/Opus listener sessions (stateless service
#       loops) must never be blocked. Detection: SENTINEL_LISTENER env var
#       (primary, set by spawn.py) or "Watching _pending_..." message pattern
#       (fallback for manual launches).
#   R4. Channel scoping — each session only checks its own CT files.
#       SENTINEL_CHANNEL=N or WAKEFUL_CHANNEL=N → shared CT + ch{N} CT.
#       Unset → shared CT only. Squad evidence scoped to active channels.
#   R5. Anti-loop — CC sets stop_hook_active=true after first block.
#       Second stop attempt always allowed.
#   R6. Fail-open — any parse/stat/jq error → exit 0, no output → allow stop.
#
# Checks CURRENT_TASK.md (shared index) + CURRENT_TASK_ch{N}.md (own channel).
# Agent names for squad validation: see modules/verification/reference/verification-squad.md.
set -u

LOGFILE="${SENTINEL_DEBUG_LOG:-/dev/null}"
[[ -n "${SENTINEL_DEBUG:-}" ]] && LOGFILE="/tmp/stop-hook-debug-$$.log"

# Read hook input from stdin
INPUT="$(cat)" || exit 0

# Log every invocation for diagnostics
{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "$INPUT" | jq '{session_id, cwd, stop_hook_active, hook_event_name, msg_len: (.last_assistant_message | length)}' 2>/dev/null
} >> "$LOGFILE" 2>/dev/null

# Prevent infinite loops: if we already blocked once, allow the stop
STOP_HOOK_ACTIVE="$(echo "$INPUT" | jq -r '.stop_hook_active // "false"' 2>/dev/null | tr -d '\r')" || exit 0
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  echo "  -> ALLOW (stop_hook_active)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# Guard: if no assistant message, this is startup/init — always allow
LAST_MSG_LEN="$(echo "$INPUT" | jq -r '.last_assistant_message | length' 2>/dev/null | tr -d '\r')" || exit 0
if [[ -z "$LAST_MSG_LEN" ]] || [[ "$LAST_MSG_LEN" -lt 1 ]]; then
  echo "  -> ALLOW (no assistant message / startup)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# --- BYPASS: Listener sessions (environment variable) ---
# Set by spawn.py for listener sessions at launch time. Unconditional bypass —
# listeners are stateless service loops that must not touch CT files.
# Accepts both SENTINEL_LISTENER (cc-sentinel) and WAKEFUL_LISTENER (Wakeful).
# The message pattern check below is a fallback for manual launches.
HOOK_LISTENER="${SENTINEL_LISTENER:-${WAKEFUL_LISTENER:-}}"
if [[ "$HOOK_LISTENER" == "true" ]]; then
  echo "  -> ALLOW (listener env var)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# Find project directory containing CURRENT_TASK.md
CWD="$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null | tr -d '\r')" || true
PROJECT_DIR=""
for dir in "$CWD" "$(pwd)" "$(git rev-parse --show-toplevel 2>/dev/null || true)"; do
  [[ -z "$dir" ]] && continue
  if [[ -f "$dir/CURRENT_TASK.md" ]]; then
    PROJECT_DIR="$dir"
    break
  fi
done

if [[ -z "$PROJECT_DIR" ]]; then
  echo "  -> ALLOW (no CURRENT_TASK.md)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# Collect CT files: scope to own channel only. Without a channel env var, only
# check shared CT — channel CTs belong to other sessions and checking them
# causes cross-channel noise (stale alerts for files this session doesn't own,
# which can lead to models deleting or overwriting other sessions' state).
# Accepts both SENTINEL_CHANNEL (cc-sentinel) and WAKEFUL_CHANNEL (Wakeful).
HOOK_CHANNEL="${SENTINEL_CHANNEL:-${WAKEFUL_CHANNEL:-}}"
TASK_FILES=()
if [[ -n "$HOOK_CHANNEL" ]]; then
  # Channeled session: own channel + shared index
  [[ -f "${PROJECT_DIR}/CURRENT_TASK.md" ]] && TASK_FILES+=("${PROJECT_DIR}/CURRENT_TASK.md")
  [[ -f "${PROJECT_DIR}/CURRENT_TASK_ch${HOOK_CHANNEL}.md" ]] && TASK_FILES+=("${PROJECT_DIR}/CURRENT_TASK_ch${HOOK_CHANNEL}.md")
else
  # Unchanneled: shared CT only
  TASK_FILES=("${PROJECT_DIR}/CURRENT_TASK.md")
fi

# Helper: extract channel number from a CT file (empty = unchanneled/shared)
get_channel() {
  local f="$1"
  grep -oE '\*\*Channel:\*\*[[:space:]]*[0-9]+' "$f" 2>/dev/null | grep -oE '[0-9]+' | head -1
}

# Determine aggregate task status across all CT files
# "active" if ANY file has active work; "complete" if any claims complete; "none" otherwise
TASK_STATUS="none"
ACTIVE_FILES=()
for tf in "${TASK_FILES[@]}"; do
  if grep -qiE '\*\*Status:\*\*[[:space:]]*IN PROGRESS' "$tf" 2>/dev/null; then
    TASK_STATUS="active"
    ACTIVE_FILES+=("$tf")
  elif grep -iE '\*\*Phase:\*\*[[:space:]]*/[0-9]' "$tf" 2>/dev/null | grep -qivE '(complete|done|finished)'; then
    TASK_STATUS="active"
    ACTIVE_FILES+=("$tf")
  elif grep -qiE '\*\*Status:\*\*[[:space:]]*(COMPLETE|ALL DONE)' "$tf" 2>/dev/null; then
    [[ "$TASK_STATUS" == "none" ]] && TASK_STATUS="complete"
  fi
done

if [[ "$TASK_STATUS" == "none" ]]; then
  echo "  -> ALLOW (no active task in any CT file)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# --- CHECK 1: Completion claim without verification ---
# Extract last assistant message
LAST_MSG="$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null | tr -d '\r')" || true

# --- BYPASS: Waiting for agents ---
if echo "$LAST_MSG" | grep -qiE "(agent|agents).*(still running|running|pending|remaining|waiting)|(waiting for).*(agent|results|report)" 2>/dev/null; then
  echo "  -> ALLOW (waiting for agents)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# --- BYPASS: Listener sessions (message pattern — fallback for manual launches) ---
# Matches the idle announce line. Once the listener picks up work, the last
# message changes and normal CT enforcement applies. (See R3 in header.)
if echo "$LAST_MSG" | grep -qiE "Watching _pending_(sonnet|opus)/" 2>/dev/null; then
  echo "  -> ALLOW (listener session — announce pattern)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# Completion language patterns
COMPLETION_PATTERNS="(all (items |steps |tasks |work )?(are |is )?(done|complete)|work is (complete|done|finished)|sprint is (complete|done)|task is (complete|done)|everything.s (done|complete)|implementation.* complete|ship.ready|what.s next|what should we|shall we move on|ready to move)"

# Completion signal: completion language in assistant message (REQUIRED).
# COMPLETE status in CURRENT_TASK.md alone is NOT sufficient — it may be stale
# from a previous task. The commit hook is the hard gate at commit time.
COMPLETION_CLAIMED="false"
if echo "$LAST_MSG" | grep -qiE "$COMPLETION_PATTERNS" 2>/dev/null; then
  COMPLETION_CLAIMED="true"
fi

# --- BYPASS: Question-ending messages WITHOUT completion language ---
# "Which spec?" → bypass. "Work is done, what next?" → still blocked.
LAST_MSG_TRIMMED="$(echo "$LAST_MSG" | sed 's/[[:space:]]*$//')"
if [[ "$COMPLETION_CLAIMED" == "false" ]] && [[ "$LAST_MSG_TRIMMED" == *"?" ]]; then
  echo "  -> ALLOW (question, no completion language)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

if [[ "$COMPLETION_CLAIMED" == "true" ]]; then
  # Claimed completion — check for verification evidence
  VERIFICATION_FOUND="false"

  # Check 1: VERIFICATION_BLOCKED marker in ACTIVE CT files only (not all files)
  # BLOCKED means max-rounds exhausted and issues presented to user — still counts as verification done
  # NOTE: VERIFICATION_PASSED is NOT accepted here — it's self-attestation (model writes it without
  # proof that Squad actually ran). Only actual squad files or VERIFICATION_BLOCKED satisfy this gate.
  # Scoped to ACTIVE_FILES to prevent cross-channel leak (ch1 BLOCKED satisfying ch2 gate).
  for tf in "${ACTIVE_FILES[@]}"; do
    if grep -qE "VERIFICATION_BLOCKED" "$tf" 2>/dev/null; then
      VERIFICATION_FOUND="true"
      break
    fi
  done

  # Check 2: Squad validation — scoped to active channels to prevent cross-channel leak
  # Build allowed squad dir patterns from ACTIVE_FILES
  SQUAD_PATTERNS=()
  HAS_UNCHANNELED_ACTIVE="false"
  for tf in "${ACTIVE_FILES[@]}"; do
    ACH=$(get_channel "$tf")
    if [[ -n "$ACH" ]]; then
      SQUAD_PATTERNS+=("squad_ch${ACH}_")
    else
      HAS_UNCHANNELED_ACTIVE="true"
    fi
  done

  for SQUAD_DIR in "${PROJECT_DIR}/verification_findings/squad_"*/; do
    [[ ! -d "$SQUAD_DIR" ]] && continue
    SQUAD_TAG="$(basename "$SQUAD_DIR")"

    # Scope check: only examine squad dirs belonging to active channels
    SQUAD_ALLOWED="false"
    if [[ ${#SQUAD_PATTERNS[@]} -gt 0 ]]; then
      for sp in "${SQUAD_PATTERNS[@]}"; do
        if [[ "$SQUAD_TAG" == ${sp}* ]]; then
          SQUAD_ALLOWED="true"
          break
        fi
      done
    fi
    # Unchanneled active: allow squad dirs that don't match any channel pattern
    if [[ "$HAS_UNCHANNELED_ACTIVE" == "true" ]] && [[ "$SQUAD_TAG" != squad_ch[0-9]* ]]; then
      SQUAD_ALLOWED="true"
    fi
    [[ "$SQUAD_ALLOWED" == "false" ]] && continue
    # Source of truth for agent names: modules/verification/reference/verification-squad.md
    SQUAD_EXPECTED=("mechanical.md" "adversarial.md" "completeness.md" "dependency.md" "cold_reader.md")
    SQUAD_EXISTS=0
    SQUAD_PASS=0
    SQUAD_MISSING=""
    SQUAD_FAILED=""
    for tf in "${SQUAD_EXPECTED[@]}"; do
      if [[ -f "$SQUAD_DIR/$tf" ]]; then
        SQUAD_EXISTS=$((SQUAD_EXISTS + 1))
        if grep -qE "VERDICT: (PASS|WARN)" "$SQUAD_DIR/$tf" 2>/dev/null; then
          SQUAD_PASS=$((SQUAD_PASS + 1))
        else
          SQUAD_FAILED="${SQUAD_FAILED} ${tf}"
        fi
      else
        SQUAD_MISSING="${SQUAD_MISSING} ${tf}"
      fi
    done

    # NOTE: Blocks immediately on first incomplete squad dir found. If a newer
    # passing squad also exists, the old one still blocks — clean up old squad
    # dirs before claiming completion. This is the safe direction (false block,
    # not false allow). The anti-loop (R5) limits this to one extra stop.
    if [[ "$SQUAD_EXISTS" -gt 0 ]] && [[ "$SQUAD_PASS" -lt 5 ]]; then
      REASON="INCOMPLETE VERIFICATION SQUAD (${SQUAD_TAG}): Squad directory exists but not all 5 agents passed (${SQUAD_PASS}/5)."
      if [[ -n "$SQUAD_MISSING" ]]; then
        REASON="${REASON} Missing:${SQUAD_MISSING}."
      fi
      if [[ -n "$SQUAD_FAILED" ]]; then
        REASON="${REASON} Failed (no VERDICT: PASS or WARN):${SQUAD_FAILED}."
      fi
      REASON="${REASON} Fix failing agents and re-run. All 5 must PASS or WARN before completion."
      REASON_JSON=$(printf '%s' "$REASON" | jq -Rs '.' | tr -d '\r') || exit 0
      echo "  -> BLOCK (${SQUAD_TAG} incomplete: ${SQUAD_PASS}/5 pass)" >> "$LOGFILE" 2>/dev/null
      echo "{\"decision\": \"block\", \"reason\": ${REASON_JSON}}"
      exit 0
    fi

    # All 5 exist and pass — this squad counts as verification evidence
    if [[ "$SQUAD_PASS" -eq 5 ]]; then
      VERIFICATION_FOUND="true"
    fi
  done

  if [[ "$VERIFICATION_FOUND" == "false" ]]; then
    REASON="COMPLETION WITHOUT VERIFICATION: No verification evidence found. Run the Verification Squad — it is required by default for all non-exempt work. The feeling of completion is a trigger to BEGIN verification, not end work. If this is not a task completion, ignore this and stop again."
    REASON_JSON=$(printf '%s' "$REASON" | jq -Rs '.' | tr -d '\r') || exit 0
    echo "  -> BLOCK (completion without verification)" >> "$LOGFILE" 2>/dev/null
    echo "{\"decision\": \"block\", \"reason\": ${REASON_JSON}}"
    exit 0
  fi
fi

# --- CHECK 2: Stale CT files (only for active/in-progress tasks) ---
if [[ "$TASK_STATUS" == "active" ]] && [[ ${#ACTIVE_FILES[@]} -gt 0 ]]; then
  NOW=$(date +%s) || exit 0
  STALE_FILES=""
  for tf in "${ACTIVE_FILES[@]}"; do
    FILE_MTIME=$(stat -c %Y "$tf" 2>/dev/null || stat -f %m "$tf" 2>/dev/null) || continue
    FILE_MTIME=$(echo "$FILE_MTIME" | tr -d '\r')
    DIFF=$((NOW - FILE_MTIME)) || continue
    if [[ "$DIFF" -ge 120 ]]; then
      CH=$(get_channel "$tf")
      FNAME="$(basename "$tf")"
      if [[ -n "$CH" ]]; then
        STALE_FILES="${STALE_FILES} ${FNAME} (ch${CH}, ${DIFF}s)"
      else
        STALE_FILES="${STALE_FILES} ${FNAME} (${DIFF}s)"
      fi
    fi
  done

  # NOTE: A previous ANY_FRESH shortcut allowed stop if ANY active CT was fresh,
  # even when other channels' CTs were stale. This was removed because in multi-
  # channel setups, one channel's activity would exempt all others — allowing
  # sessions to stop without updating their own CT. Now each stale file is
  # reported individually. The stop_hook_active anti-loop (R5) ensures a
  # session can always stop on its second attempt.

  if [[ -n "$STALE_FILES" ]]; then
    REASON="Active CT file(s) not updated in the last 2 minutes:${STALE_FILES}. Before stopping: update each active channel's Completed Steps with what you did, and update Status if the task is done. Do NOT clear or rewrite — only add progress. Then stop again."
    REASON_JSON=$(printf '%s' "$REASON" | jq -Rs '.' | tr -d '\r') || exit 0
    echo "  -> BLOCK (stale:${STALE_FILES})" >> "$LOGFILE" 2>/dev/null
    echo "{\"decision\": \"block\", \"reason\": ${REASON_JSON}}"
    exit 0
  fi
fi

# COMPLETE status with no completion language — allow stop (R1 only triggers
# when assistant claims completion in its message; stale check only for active tasks)
echo "  -> ALLOW (no completion claim, no stale active files)" >> "$LOGFILE" 2>/dev/null
exit 0
