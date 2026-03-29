#!/usr/bin/env bash
# Stop hook: three blocking checks (R1, R2, R7) with supporting behaviors (R3-R6).
#
# Glossary: CC = Claude Code, CT = CURRENT_TASK (the .md state files).
#
# REQUIREMENTS:
#   R1. Completion gate — if assistant claims work is done (completion language
#       in last message), require verification evidence before allowing stop.
#       Evidence: squad dir with all expected PASS/WARN verdicts, or VERIFICATION_BLOCKED
#       marker in the active CT file. (WARN = issues found but non-blocking.)
#   R2. Staleness gate — if any active CT file is >2 min stale, block and
#       request progress update before stopping.
#   R3. Listener bypass — Sonnet/Opus listener sessions (stateless service
#       loops) must never be blocked. Detection: SENTINEL_LISTENER or
#       WAKEFUL_LISTENER env var (primary, set by spawn.py) or "Watching _pending_(sonnet|opus)/"
#       / "Waiting for work on ch[0-9]+" message patterns (fallback).
#   R4. Channel scoping — each session only checks its own CT files.
#       SENTINEL_CHANNEL=N or WAKEFUL_CHANNEL=N → shared CT + ch{N} CT.
#       Unset → shared CT only. Squad evidence scoped to active channels.
#   R5. Anti-loop — CC sets stop_hook_active=true after first block.
#       Second stop attempt always allowed.
#   R6. Fail-open — any parse/stat/jq error → exit 0, no output → allow stop.
#   R7. Deferral gate — if assistant message contains deferral language
#       ("deferred items", "future sprint", etc.), block and require developer
#       permission. Complements PreToolUse anti-deferral hook (which only
#       sees file writes, not conversational output).
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

# Extract all needed fields from JSON in one jq call (avoids 4-5 subprocess forks)
PARSED="$(echo "$INPUT" | jq -r '[
  (.stop_hook_active // "false"),
  (.last_assistant_message | length | tostring),
  (.cwd // ""),
  (.last_assistant_message // "")
] | join("\n")' 2>/dev/null | tr -d '\r')" || exit 0

# Split into variables by line number (last field captures lines 4+ for multiline messages)
STOP_HOOK_ACTIVE="$(echo "$PARSED" | sed -n '1p')"
LAST_MSG_LEN="$(echo "$PARSED" | sed -n '2p')"
CWD="$(echo "$PARSED" | sed -n '3p')"
LAST_MSG="$(echo "$PARSED" | sed -n '4,$p')"

# Prevent infinite loops: if we already blocked once, allow the stop
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  echo "  -> ALLOW (stop_hook_active)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# Guard: if no assistant message, this is startup/init — always allow
if [[ -z "$LAST_MSG_LEN" ]] || [[ "$LAST_MSG_LEN" -lt 1 ]]; then
  echo "  -> ALLOW (no assistant message / startup)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# --- BYPASS: Listener sessions (environment variable) ---
# Set by spawn.py for listener sessions at launch time. Unconditional bypass —
# listeners are stateless service loops that must not touch CT files.
# Accepts both SENTINEL_LISTENER (cc-sentinel) and WAKEFUL_LISTENER (Wakeful).
# Value must be the string literal "true" (set by spawn.py at launch time).
# The message pattern check below is a fallback for manual launches.
HOOK_LISTENER="${SENTINEL_LISTENER:-${WAKEFUL_LISTENER:-}}"
if [[ "$HOOK_LISTENER" == "true" ]]; then
  echo "  -> ALLOW (listener env var)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# Find project directory containing CURRENT_TASK.md
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
  if grep -qiE '\*\*Status:\*\*[[:space:]]*(COMPLETE|ALL DONE)' "$tf" 2>/dev/null; then
    [[ "$TASK_STATUS" == "none" ]] && TASK_STATUS="complete"
  elif grep -qiE '\*\*Status:\*\*' "$tf" 2>/dev/null; then
    # Any non-COMPLETE status with a Status header = active
    TASK_STATUS="active"
    ACTIVE_FILES+=("$tf")
  elif grep -iE '\*\*Phase:\*\*[[:space:]]*/[0-9]' "$tf" 2>/dev/null | grep -qivE '(complete|done|finished)'; then
    TASK_STATUS="active"
    ACTIVE_FILES+=("$tf")
  fi
done

if [[ "$TASK_STATUS" == "none" ]]; then
  echo "  -> ALLOW (no active task in any CT file)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# --- CHECK 1: Completion claim without verification ---
# LAST_MSG already extracted in consolidated jq call above

# --- BYPASS: Waiting for agents (fires before R1 — agents need time, not verification) ---
if echo "$LAST_MSG" | grep -qiE "(agent|agents).*(still running|running|pending|remaining|waiting)|(waiting for).*(agent|results|report)" 2>/dev/null; then
  echo "  -> ALLOW (waiting for agents)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# --- BYPASS: Listener sessions (message pattern — fallback for manual launches) ---
# Fires before R1 — listeners are stateless and never claim completion.
# Matches the idle announce line. Once the listener picks up work, the last
# message changes and normal CT enforcement applies. (See R3 in header.)
if echo "$LAST_MSG" | grep -qiE "Watching _pending_(sonnet|opus)/|Waiting for work on ch[0-9]+" 2>/dev/null; then
  echo "  -> ALLOW (listener session — announce pattern)" >> "$LOGFILE" 2>/dev/null
  exit 0
fi

# Completion language patterns
COMPLETION_PATTERNS="(all (items |steps |tasks |work )?(are |is )?(done|complete)|work is (complete|done|finished)|sprint is (complete|done)|task is (complete|done)|everything.s (done|complete)|implementation.* complete|ship.ready|what.s next|what should we|shall we move on|ready to move)"

# Completion signal: completion language in assistant message (REQUIRED).
# COMPLETE status in CURRENT_TASK.md alone is NOT sufficient — it may be stale
# from a previous task. The commit hook (safe-commit.sh) is the hard gate at commit time.
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
    SQUAD_EXPECTED=("mechanical.md" "adversarial.md" "completeness.md" "dependency.md" "cold_reader.md" "performance.md")

    # Check for manifest.json (smart filtering) — overrides default SQUAD_EXPECTED
    if [[ -f "$SQUAD_DIR/manifest.json" ]]; then
      if ! jq -e '.launched' "$SQUAD_DIR/manifest.json" >/dev/null 2>&1; then
        echo "WARNING: manifest.json exists but contains invalid JSON — using default agents" >&2
      else
        MANIFEST_AGENTS=$(jq -r '.launched[]? // empty' "$SQUAD_DIR/manifest.json" 2>/dev/null | tr -d '\r')
        if [[ -n "$MANIFEST_AGENTS" ]]; then
          SQUAD_EXPECTED=()
          while IFS= read -r agent; do
            agent="${agent//$'\r'/}"
            [[ -n "$agent" ]] && SQUAD_EXPECTED+=("${agent}")
          done <<< "$MANIFEST_AGENTS"
          # If we ended up with empty array, restore default
          if [[ ${#SQUAD_EXPECTED[@]} -eq 0 ]]; then
            SQUAD_EXPECTED=("mechanical.md" "adversarial.md" "completeness.md" "dependency.md" "cold_reader.md" "performance.md")
          fi
        fi
      fi
    fi

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

    # NOTE: Blocks on first incomplete squad dir where at least one expected
    # agent file exists. Empty/irrelevant dirs are skipped (the no-evidence
    # block fires instead). If a newer passing squad also exists, the old one
    # still blocks — clean up old dirs before claiming completion. Safe direction
    # (false block, not false allow). The anti-loop (R5) limits to one extra stop.
    if [[ "$SQUAD_EXISTS" -gt 0 ]] && [[ "$SQUAD_PASS" -lt ${#SQUAD_EXPECTED[@]} ]]; then
      REASON="INCOMPLETE VERIFICATION SQUAD (${SQUAD_TAG}): Squad directory exists but not all ${#SQUAD_EXPECTED[@]} agents passed (${SQUAD_PASS}/${#SQUAD_EXPECTED[@]})."
      if [[ -n "$SQUAD_MISSING" ]]; then
        REASON="${REASON} Missing:${SQUAD_MISSING}."
      fi
      if [[ -n "$SQUAD_FAILED" ]]; then
        REASON="${REASON} Failed (no VERDICT: PASS or WARN):${SQUAD_FAILED}."
      fi
      REASON="${REASON} Fix failing agents and re-run. All ${#SQUAD_EXPECTED[@]} must PASS or WARN before completion."
      REASON_JSON=$(printf '%s' "$REASON" | jq -Rs '.' | tr -d '\r') || exit 0
      echo "  -> BLOCK (${SQUAD_TAG} incomplete: ${SQUAD_PASS}/${#SQUAD_EXPECTED[@]} pass)" >> "$LOGFILE" 2>/dev/null
      echo "{\"decision\": \"block\", \"reason\": ${REASON_JSON}}"
      exit 0
    fi

    # All agents exist and pass — this squad counts as verification evidence
    if [[ "$SQUAD_PASS" -eq ${#SQUAD_EXPECTED[@]} ]]; then
      VERIFICATION_FOUND="true"
    fi
  done

  if [[ "$VERIFICATION_FOUND" == "false" ]]; then
    REASON="COMPLETION WITHOUT VERIFICATION: No verification evidence found. Run the Verification Squad — it is required by default for all non-exempt work. The feeling of completion is a trigger to BEGIN verification, not end work. If the completion language in your message was incidental (not a real claim), you may stop again — the anti-loop (R5) always allows the second stop."
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
    REASON="Active CT file(s) not updated in the last 2 minutes:${STALE_FILES}. Before stopping: update your Completed Steps with what you did, and update Status if the task is done. Do NOT clear or rewrite — only add progress. Then stop again."
    REASON_JSON=$(printf '%s' "$REASON" | jq -Rs '.' | tr -d '\r') || exit 0
    echo "  -> BLOCK (stale:${STALE_FILES})" >> "$LOGFILE" 2>/dev/null
    echo "{\"decision\": \"block\", \"reason\": ${REASON_JSON}}"
    exit 0
  fi
fi

# --- CHECK 3: Deferral language in assistant message ---
# Catches "Deferred items:", "future sprint", etc. in conversational output
# where the PreToolUse anti-deferral hook cannot see it (not a file write).
DEFERRAL_PATTERNS="deferred (items|deployment|to |as )|future sprint|later sprint|next sprint|handle this later|address this later|out of scope for now|separate (pass|effort|session) needed"
if echo "$LAST_MSG" | grep -qiE "$DEFERRAL_PATTERNS" 2>/dev/null; then
  REASON="DEFERRAL IN CONVERSATION: Your last message contains deferral language. Rule 0: Fix it now. Never defer without explicit developer permission. If the developer already approved these deferrals, ignore this and stop again."
  REASON_JSON=$(printf '%s' "$REASON" | jq -Rs '.' | tr -d '\r') || exit 0
  echo "  -> BLOCK (deferral language)" >> "$LOGFILE" 2>/dev/null
  echo "{\"decision\": \"block\", \"reason\": ${REASON_JSON}}"
  exit 0
fi

# All three checks passed (completion, staleness, deferral) — allow stop
echo "  -> ALLOW (all checks passed)" >> "$LOGFILE" 2>/dev/null
exit 0
