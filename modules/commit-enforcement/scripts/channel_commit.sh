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
FILES=""
MESSAGE=""
SKIP_SQUAD="false"
LOCAL_VERIFY="false"
MAX_RETRIES=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel|--files|-m)
      [[ $# -lt 2 ]] && echo "ERROR: $1 requires a value" >&2 && exit 1
      ;;&
    --channel) CHANNEL="$2"; shift 2 ;;
    --files)   FILES="$2"; shift 2 ;;
    -m)        MESSAGE="$2"; shift 2 ;;
    --skip-squad)   SKIP_SQUAD="true"; shift ;;
    --local-verify) LOCAL_VERIFY="true"; shift ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$FILES" ]]   && echo "ERROR: --files \"f1 f2\" required" >&2 && exit 1
[[ -z "$MESSAGE" ]] && echo "ERROR: -m \"message\" required" >&2 && exit 1

# --- Derived paths ---
if [[ -n "$CHANNEL" ]]; then
  CH_SUFFIX="_ch${CHANNEL}"
  PENDING_DIR="verification_findings/_pending/ch${CHANNEL}"
else
  CH_SUFFIX=""
  PENDING_DIR="verification_findings/_pending"
fi
CHECK_FILE="verification_findings/commit_check${CH_SUFFIX}.md"
COLD_READ_FILE="verification_findings/commit_cold_read${CH_SUFFIX}.md"
DIFF_FILE="verification_findings/staged_diff${CH_SUFFIX}.diff"
LOCK_DIR=".git/commit.lock"
COMMIT_ACTIVE_FILE="${PENDING_DIR}/.commit_active"

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
      for f in $FILES; do
        [[ "$staged_file" == "$f" ]] && is_ours="true" && break
      done
      [[ "$is_ours" == "false" ]] && unrelated="$unrelated $staged_file"
    done
    [[ -n "$unrelated" ]] && echo "WARNING: Clearing unrelated staged files:$unrelated" >&2
  fi

  git reset HEAD --quiet 2>/dev/null || true
  for f in $FILES; do
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
Files: ${FILES}
YAML_EOF

  echo "Dispatched to ${dispatch_file} — waiting for results" >&2
  bash scripts/wait_for_results.sh --timeout 300 "$CHECK_FILE" "$COLD_READ_FILE"
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

# --- Heartbeat Check ---
check_heartbeat() {
  local hb_file="${PENDING_DIR}/.heartbeat"
  [[ ! -f "$hb_file" ]] && echo "WARNING: No Sonnet heartbeat. Use --local-verify or start /sonnet." >&2 && return
  local now hb_time age
  now=$(date +%s)
  hb_time=$(stat -c %Y "$hb_file" 2>/dev/null || stat -f %m "$hb_file" 2>/dev/null || echo 0)
  age=$((now - hb_time))
  (( age > 30 )) && echo "WARNING: Sonnet heartbeat stale (${age}s)." >&2
}

# --- Main Flow ---
HASH=""
mkdir -p "$PENDING_DIR"
printf '%s\n' $FILES > "$COMMIT_ACTIVE_FILE"

ATTEMPT=0
while (( ATTEMPT < MAX_RETRIES )); do
  ATTEMPT=$((ATTEMPT + 1))
  phase1_stage_and_dispatch "$ATTEMPT" || exit 1

  [[ "$LOCAL_VERIFY" != "true" ]] && check_heartbeat

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

# --- Auto-detect and run tests ---
TEST_LOG=$(mktemp)
TEST_RAN="false"
if [[ -f "pubspec.yaml" ]]; then
  echo "Running Flutter tests..." >&2; TEST_RAN="true"
  flutter test --exclude-tags property,pairwise,slow > "$TEST_LOG" 2>&1 || { tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
elif [[ -f "package.json" ]]; then
  echo "Running npm tests..." >&2; TEST_RAN="true"
  npm test > "$TEST_LOG" 2>&1 || { tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
elif [[ -f "Cargo.toml" ]]; then
  echo "Running cargo tests..." >&2; TEST_RAN="true"
  cargo test > "$TEST_LOG" 2>&1 || { tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
elif [[ -f "go.mod" ]]; then
  echo "Running Go tests..." >&2; TEST_RAN="true"
  go test ./... > "$TEST_LOG" 2>&1 || { tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
elif [[ -f "pytest.ini" ]] || [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]]; then
  echo "Running pytest..." >&2; TEST_RAN="true"
  pytest > "$TEST_LOG" 2>&1 || { tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
elif [[ -f "Makefile" ]] && grep -q "^test:" "Makefile" 2>/dev/null; then
  echo "Running make test..." >&2; TEST_RAN="true"
  make test > "$TEST_LOG" 2>&1 || { tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
fi
[[ "$TEST_RAN" == "true" ]] && echo "Tests passed." >&2
rm -f "$TEST_LOG"

# --- Phase 2: Commit ---
acquire_lock
git reset HEAD --quiet 2>/dev/null || true
for f in $FILES; do
  git add "$f" 2>/dev/null || { echo "ERROR: Phase 2 staging failed: $f" >&2; release_lock; exit 1; }
done

COMMIT_HASH=$(git diff --cached | git hash-object --stdin)
if [[ "$COMMIT_HASH" != "$HASH" ]]; then
  echo "CONFLICT: HEAD advanced and diff changed." >&2
  release_lock
  exit 1
fi

COMMIT_ARGS=(-m "$MESSAGE" --local-verify --skip-tests)
[[ "$SKIP_SQUAD" == "true" ]] && COMMIT_ARGS+=(--skip-squad)

[[ -n "$CHANNEL" ]] && export SENTINEL_CHANNEL="$CHANNEL"
COMMIT_EXIT=0
bash "$(dirname "$0")/../hooks/safe-commit.sh" --internal "${COMMIT_ARGS[@]}" || COMMIT_EXIT=$?

rm -f "$DIFF_FILE" "$COMMIT_ACTIVE_FILE"
release_lock

if [[ $COMMIT_EXIT -eq 0 ]]; then
  COMMIT_SHA=$(git rev-parse HEAD)
  echo "SUCCESS: committed $COMMIT_SHA" >&2
  echo "$COMMIT_SHA"
else
  exit $COMMIT_EXIT
fi
