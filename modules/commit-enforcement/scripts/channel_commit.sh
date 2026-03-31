#!/usr/bin/env bash
# channel_commit.sh — Atomic multi-channel commit with locking and verification dispatch
#
# Usage:
#   bash scripts/channel_commit.sh [--channel N] --files "f1 f2" -m "msg" [--skip-squad] [--local-verify]
#
# Output:
#   stdout: commit SHA on success
#   stderr: status messages, errors
#   exit 0: success, exit 1: failure

set -euo pipefail

# --- Parse arguments ---
CHANNEL=""
FILE_ARRAY=()
MESSAGE=""
SKIP_SQUAD="false"
LOCAL_VERIFY="false"
MAX_RETRIES=3

# Trailing `true` required: under set -e, [[ ]] returning false would exit.
_require_value() { [[ $# -lt 2 ]] && echo "ERROR: $1 requires a value" >&2 && exit 1; true; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) _require_value "$@"; CHANNEL="$2"; shift 2 ;;
    --files)   _require_value "$@"; IFS=' ' read -ra FILE_ARRAY <<< "$2"; shift 2 ;;
    -m)        _require_value "$@"; MESSAGE="$2"; shift 2 ;;
    --skip-squad)   SKIP_SQUAD="true"; shift ;;
    --local-verify) LOCAL_VERIFY="true"; shift ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ ${#FILE_ARRAY[@]} -eq 0 ]] && echo "ERROR: --files \"f1 f2\" required" >&2 && exit 1
[[ -z "$MESSAGE" ]] && echo "ERROR: -m \"message\" required" >&2 && exit 1

# --- Derived paths ---
if [[ -n "$CHANNEL" ]]; then
  CH_SUFFIX="_ch${CHANNEL}"
  PENDING_DIR="verification_findings/_pending_sonnet/ch${CHANNEL}"
else
  CH_SUFFIX=""
  PENDING_DIR="verification_findings/_pending_sonnet"
fi
CHECK_FILE="verification_findings/commit_check${CH_SUFFIX}.md"
COLD_READ_FILE="verification_findings/commit_cold_read${CH_SUFFIX}.md"
DIFF_FILE="verification_findings/staged_diff${CH_SUFFIX}.diff"
LOCK_DIR=".git/commit.lock"
COMMIT_ACTIVE_FILE="${PENDING_DIR}/.commit_active"

# Resolve scripts directory: project-local first, then global
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

_cleanup_exit() {
  rm -f "$COMMIT_ACTIVE_FILE" 2>/dev/null
  rm -rf "$LOCK_DIR" 2>/dev/null
}
trap _cleanup_exit EXIT

# --- Lock functions ---
acquire_lock() {
  local max_wait=180 stale_threshold=120 waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    local lock_time now
    lock_time=$(cat "$LOCK_DIR/time" 2>/dev/null || echo 0)
    now=$(date +%s)
    if (( lock_time > 0 && now - lock_time > stale_threshold )); then
      echo "Removing stale commit lock (age: $((now - lock_time))s)" >&2
      rm -rf "$LOCK_DIR"
      continue
    fi
    sleep 1
    waited=$((waited + 1))
    if (( waited >= max_wait )); then
      echo "ERROR: LOCK_TIMEOUT — waited ${max_wait}s for commit lock" >&2
      exit 1
    fi
  done
  date +%s > "$LOCK_DIR/time"
  echo "$$" > "$LOCK_DIR/pid"
  echo "${CHANNEL:-unchanneled}" > "$LOCK_DIR/channel"
}

release_lock() { rm -rf "$LOCK_DIR" 2>/dev/null; }

# --- Phase 1: Stage + Hash + Dispatch ---
phase1_stage_and_dispatch() {
  local attempt=$1
  acquire_lock

  local currently_staged
  currently_staged=$(git diff --cached --name-only 2>/dev/null || true)
  if [[ -n "$currently_staged" ]]; then
    local unrelated=""
    for staged_file in $currently_staged; do
      local is_ours="false"
      for f in "${FILE_ARRAY[@]}"; do
        [[ "$staged_file" == "$f" ]] && is_ours="true" && break
      done
      [[ "$is_ours" == "false" ]] && unrelated="$unrelated $staged_file"
    done
    [[ -n "$unrelated" ]] && echo "WARNING: Clearing unrelated staged files:$unrelated" >&2
  fi

  git reset --quiet 2>/dev/null || true
  for f in "${FILE_ARRAY[@]}"; do
    if ! git add "$f" 2>/dev/null; then
      echo "ERROR: Failed to stage: $f" >&2
      release_lock
      return 1
    fi
  done

  git diff --cached > "$DIFF_FILE"
  HASH=$(git hash-object --stdin < "$DIFF_FILE")

  if [[ "$LOCAL_VERIFY" != "true" ]]; then
    rm -f "$CHECK_FILE" "$COLD_READ_FILE"
  fi

  release_lock
  echo "Phase 1 complete (attempt $attempt/$MAX_RETRIES) — hash: $HASH" >&2
}

# --- Dispatch + Wait ---
dispatch_and_wait() {
  if [[ "$LOCAL_VERIFY" == "true" ]]; then
    if [[ ! -f "$CHECK_FILE" ]] || [[ ! -f "$COLD_READ_FILE" ]]; then
      echo "LOCAL VERIFY: Result files missing." >&2
      exit 1
    fi
    return 0
  fi

  mkdir -p "$PENDING_DIR"
  rm -f "${PENDING_DIR}"/verify_*.md 2>/dev/null || true

  local dispatch_file="${PENDING_DIR}/verify_${HASH}.md"
  cat > "$dispatch_file" << YAML_EOF
---
type: commit-verification
diff_path: ${DIFF_FILE}
agents:
  - name: commit-adversarial
    output_path: ${CHECK_FILE}
  - name: commit-cold-reader
    output_path: ${COLD_READ_FILE}
---
## Commit Verification
Hash: ${HASH}
Message: ${MESSAGE}
Files: ${FILE_ARRAY[*]}
YAML_EOF

  echo "Dispatched to ${dispatch_file} — waiting for results" >&2
  bash "$SCRIPT_DIR/wait_for_results.sh" --timeout 300 "$CHECK_FILE" "$COLD_READ_FILE"
  return $?
}

# --- Validate Results ---
validate_results() {
  for f in "$CHECK_FILE" "$COLD_READ_FILE"; do
    [[ ! -f "$f" ]] && echo "ERROR: Missing $f" >&2 && return 1
  done

  if ! grep -q "$HASH" "$CHECK_FILE" 2>/dev/null; then
    echo "Hash mismatch in adversarial check — cleaning stale result" >&2
    rm -f "$CHECK_FILE" "$COLD_READ_FILE"
    return 1
  fi
  if ! grep -q "$HASH" "$COLD_READ_FILE" 2>/dev/null; then
    echo "Hash mismatch in cold-reader check — cleaning stale result" >&2
    rm -f "$CHECK_FILE" "$COLD_READ_FILE"
    return 1
  fi

  if ! grep -qE "VERDICT: (PASS|WARN)" "$CHECK_FILE" 2>/dev/null; then
    echo "ADVERSARIAL CHECK FAILED — see: $CHECK_FILE" >&2
    return 2
  fi
  if ! grep -qE "VERDICT: (PASS|WARN)" "$COLD_READ_FILE" 2>/dev/null; then
    echo "COLD-READER CHECK FAILED — see: $COLD_READ_FILE" >&2
    return 2
  fi

  echo "Verification passed (hash: $HASH)" >&2
  return 0
}

# --- Heartbeat + Liveness Check ---
# Returns 0 = dispatch normally, 1 = switch to local (or optimistic dispatch if OPTIMISTIC_DISPATCH set).
# Sets OPTIMISTIC_DISPATCH="true" when listener may recover (stale + .active).
# Matches 7-state Liveness States table in opus-listener spec (docs/specs/2026-03-23-opus-listener-design.md).
OPTIMISTIC_DISPATCH="false"

check_heartbeat() {
  local hb_file="${PENDING_DIR}/.heartbeat"
  local active_file="${PENDING_DIR}/.active"

  # State: Missing heartbeat (any .active state) → not started or crashed
  if [[ ! -f "$hb_file" ]]; then
    echo "WARNING: No listener heartbeat detected — switching to local verification." >&2
    echo "  Start /sonnet in a second terminal for full per-commit verification." >&2
    return 1
  fi

  local now hb_time age active_info=""
  now=$(date +%s)
  hb_time=$(stat -c %Y "$hb_file" 2>/dev/null || stat -f %m "$hb_file" 2>/dev/null || echo 0)
  age=$((now - hb_time))
  [[ -f "$active_file" ]] && active_info=$(cat "$active_file" 2>/dev/null)

  if (( age > 900 )); then
    # Stale heartbeat (>15 min)
    if [[ -n "$active_info" ]]; then
      echo "WARNING: Listener may be stuck (heartbeat ${age}s, active: $active_info) — dispatching + local fallback." >&2
      OPTIMISTIC_DISPATCH="true"
      return 1
    else
      echo "WARNING: Listener likely down (heartbeat ${age}s) — switching to local verification." >&2
      return 1
    fi
  elif (( age > 300 )); then
    # Warn-stale heartbeat (5–15 min)
    if [[ -n "$active_info" ]]; then
      echo "Listener busy on long task (heartbeat ${age}s, active: $active_info)." >&2
    else
      echo "WARNING: Listener slow or briefly stalled (heartbeat ${age}s)." >&2
    fi
    return 0
  else
    # Fresh heartbeat (<5 min)
    if [[ -n "$active_info" ]]; then
      echo "Listener alive, processing: $active_info" >&2
    fi
    return 0
  fi
}

# --- Main Flow ---
HASH=""
mkdir -p "$PENDING_DIR"
printf '%s\n' "${FILE_ARRAY[@]}" > "$COMMIT_ACTIVE_FILE"

ATTEMPT=0
while (( ATTEMPT < MAX_RETRIES )); do
  ATTEMPT=$((ATTEMPT + 1))
  OPTIMISTIC_DISPATCH="false"
  phase1_stage_and_dispatch "$ATTEMPT" || exit 1

  if [[ "$LOCAL_VERIFY" != "true" ]]; then
    if ! check_heartbeat; then
      if [[ "$OPTIMISTIC_DISPATCH" == "true" ]]; then
        # Listener may recover — write dispatch file optimistically
        mkdir -p "$PENDING_DIR"
        rm -f "${PENDING_DIR}"/verify_*.md 2>/dev/null || true
        cat > "${PENDING_DIR}/verify_${HASH}.md" << OPT_EOF
---
type: commit-verification
diff_path: ${DIFF_FILE}
agents:
  - name: commit-adversarial
    output_path: ${CHECK_FILE}
  - name: commit-cold-reader
    output_path: ${COLD_READ_FILE}
---
## Commit Verification (optimistic — listener may be stuck)
Hash: ${HASH}
Message: ${MESSAGE}
Files: ${FILE_ARRAY[*]}
OPT_EOF
        echo "Optimistic dispatch written — proceeding with local verification" >&2
      fi
      LOCAL_VERIFY="true"
    fi
  fi

  WAIT_EXIT=0
  dispatch_and_wait || WAIT_EXIT=$?
  if [[ $WAIT_EXIT -ne 0 ]]; then
    echo "Sonnet wait failed (attempt $ATTEMPT/$MAX_RETRIES)" >&2
    (( ATTEMPT >= MAX_RETRIES )) && exit 1
    rm -f "$CHECK_FILE" "$COLD_READ_FILE"
    continue
  fi

  VAL_EXIT=0
  validate_results || VAL_EXIT=$?
  if [[ $VAL_EXIT -eq 0 ]]; then
    break
  elif [[ $VAL_EXIT -eq 2 ]]; then
    exit 1
  else
    (( ATTEMPT >= MAX_RETRIES )) && exit 1
    rm -f "$CHECK_FILE" "$COLD_READ_FILE"
  fi
done

# --- Phase 2: Commit ---
# Tests are owned by safe-commit.sh (single source of truth).
acquire_lock
git reset --quiet 2>/dev/null || true
for f in "${FILE_ARRAY[@]}"; do
  git add "$f" 2>/dev/null || { echo "ERROR: Phase 2 staging failed: $f" >&2; release_lock; exit 1; }
done

COMMIT_HASH=$(git diff --cached | git hash-object --stdin)
if [[ "$COMMIT_HASH" != "$HASH" ]]; then
  echo "CONFLICT: HEAD advanced and diff changed." >&2
  release_lock
  exit 1
fi

COMMIT_ARGS=(-m "$MESSAGE" --local-verify)
[[ "$SKIP_SQUAD" == "true" ]] && COMMIT_ARGS+=(--skip-squad)

[[ -n "$CHANNEL" ]] && export SENTINEL_CHANNEL="$CHANNEL"
COMMIT_EXIT=0
# Resolve safe-commit.sh: project-local first, then global
SAFE_COMMIT=""
for candidate in ".claude/hooks/safe-commit.sh" "${HOME}/.claude/hooks/safe-commit.sh"; do
  if [[ -f "$candidate" ]]; then
    SAFE_COMMIT="$candidate"
    break
  fi
done
if [[ -z "$SAFE_COMMIT" ]]; then
  echo "ERROR: safe-commit.sh not found in .claude/hooks/ or ~/.claude/hooks/" >&2
  exit 1
fi
bash "$SAFE_COMMIT" --internal "${COMMIT_ARGS[@]}" || COMMIT_EXIT=$?

rm -f "$DIFF_FILE" "$COMMIT_ACTIVE_FILE"
release_lock

if [[ $COMMIT_EXIT -eq 0 ]]; then
  COMMIT_SHA=$(git rev-parse HEAD)
  echo "SUCCESS: committed $COMMIT_SHA" >&2
  echo "$COMMIT_SHA"
else
  exit $COMMIT_EXIT
fi
