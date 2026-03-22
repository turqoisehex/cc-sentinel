#!/usr/bin/env bash
# safe-commit.sh — Internal enforcement layer for commits.
# DO NOT CALL DIRECTLY. Use channel_commit.sh instead:
#   bash scripts/channel_commit.sh --channel N --files "f1 f2" -m "msg"
# This script is called internally by channel_commit.sh with --internal flag.
set -u

# --- Direct invocation guard ---
if [[ "${1:-}" != "--internal" ]]; then
  echo "" >&2
  echo "================================================================" >&2
  echo "  BLOCKED: Do not call safe-commit.sh directly." >&2
  echo "" >&2
  echo "  Use channel_commit.sh instead:" >&2
  echo "    bash scripts/channel_commit.sh --channel N --files \"f1 f2\" -m \"msg\"" >&2
  echo "" >&2
  echo "  channel_commit.sh handles staging isolation, pre-dispatch" >&2
  echo "  cleanup, Sonnet verification, retry, and calls safe-commit.sh" >&2
  echo "  internally." >&2
  echo "================================================================" >&2
  exit 1
fi
shift  # remove --internal from args

# Usage (internal): bash safe-commit.sh --internal [-m "message"] [--skip-squad] [--local-verify] [--skip-tests]

# --- Parse flags ---
SKIP_SQUAD="false"
SONNET_VERIFY="true"
SKIP_TESTS="false"
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--skip-squad" ]]; then
    SKIP_SQUAD="true"
  elif [[ "$arg" == "--local-verify" ]]; then
    SONNET_VERIFY="false"
  elif [[ "$arg" == "--sonnet-verify" ]]; then
    SONNET_VERIFY="true"
  elif [[ "$arg" == "--skip-tests" ]]; then
    SKIP_TESTS="true"
  else
    ARGS+=("$arg")
  fi
done

# --- Channel detection ---
CH_SUFFIX=""
PENDING_SUBDIR=""
SQUAD_GLOB="verification_findings/squad_*/"
if [[ -n "${SENTINEL_CHANNEL:-}" ]]; then
  CH_SUFFIX="_ch${SENTINEL_CHANNEL}"
  PENDING_SUBDIR="/ch${SENTINEL_CHANNEL}"
  SQUAD_GLOB="verification_findings/squad_ch${SENTINEL_CHANNEL}_*/"
fi

# 1. Per-commit agent checks (adversarial + cold reader)
STAGED_FOR_CHECKS="$(git diff --cached --name-only 2>/dev/null)" || true
if [[ -n "$STAGED_FOR_CHECKS" ]]; then
  # Non-exempt file patterns (code, config, governance)
  CHECK_PATTERNS='\.dart$|\.sh$|\.py$|\.js$|\.ts$|\.go$|\.rs$|\.yaml$|\.yml$|\.toml$|^\.claude/|^scripts/|^src/|^lib/|^test/|^tests/|^CLAUDE\.md$'
  if echo "$STAGED_FOR_CHECKS" | grep -qE "$CHECK_PATTERNS" 2>/dev/null; then
    CURRENT_HASH="$(git diff --cached | git hash-object --stdin)"

    # Wait for Sonnet verification results if listener is active
    if [[ "$SONNET_VERIFY" == "true" ]]; then
      if [[ ! -d "verification_findings/_pending${PENDING_SUBDIR}" ]]; then
        echo "WARNING: No Sonnet listener detected. Checking for pre-existing results." >&2
        SONNET_VERIFY="false"
      else
        echo "Waiting for Sonnet verification results..." >&2
        bash scripts/wait_for_results.sh --timeout 300 \
          "verification_findings/commit_check${CH_SUFFIX}.md" \
          "verification_findings/commit_cold_read${CH_SUFFIX}.md"
        WAIT_EXIT=$?
        if [[ $WAIT_EXIT -ne 0 ]]; then
          exit 1
        fi
      fi
    fi

    # Both agents must pass
    COMMIT_AGENTS=("commit_check${CH_SUFFIX}.md:commit-adversarial:Adversarial" "commit_cold_read${CH_SUFFIX}.md:commit-cold-reader:Cold Reader")
    for agent_entry in "${COMMIT_AGENTS[@]}"; do
      IFS=':' read -r CHECK_FILE AGENT_NAME DISPLAY_NAME <<< "$agent_entry"
      CHECK_PATH="verification_findings/$CHECK_FILE"

      if [[ ! -f "$CHECK_PATH" ]]; then
        echo "" >&2
        echo "================================================================" >&2
        echo "  COMMIT BLOCKED: Per-commit ${DISPLAY_NAME} check required." >&2
        echo "  Run the ${AGENT_NAME} agent first, then retry." >&2
        echo "================================================================" >&2
        exit 1
      fi

      if ! grep -q "$CURRENT_HASH" "$CHECK_PATH" 2>/dev/null; then
        echo "" >&2
        echo "================================================================" >&2
        echo "  COMMIT BLOCKED: ${DISPLAY_NAME} check is stale." >&2
        echo "  Re-run the ${AGENT_NAME} agent with current diff." >&2
        echo "================================================================" >&2
        exit 1
      fi

      if ! grep -qE "VERDICT: (PASS|WARN)" "$CHECK_PATH" 2>/dev/null; then
        echo "" >&2
        echo "================================================================" >&2
        echo "  COMMIT BLOCKED: ${DISPLAY_NAME} check FAILED." >&2
        echo "  Fix the issues, then re-run the agent." >&2
        echo "================================================================" >&2
        exit 1
      fi
    done
  fi
fi

# 2. Run tests — auto-detect project type
if [[ "$SKIP_TESTS" == "true" ]]; then
  echo "Tests skipped (--skip-tests flag)." >&2
else
  TEST_LOG=$(mktemp)
  TEST_RAN="false"

  if [[ -f "pubspec.yaml" ]]; then
    echo "Running Flutter tests..." >&2
    TEST_RAN="true"
    flutter test --exclude-tags property,pairwise,slow > "$TEST_LOG" 2>&1 || { echo "TESTS FAILED:" >&2; tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
  elif [[ -f "package.json" ]]; then
    echo "Running npm tests..." >&2
    TEST_RAN="true"
    npm test > "$TEST_LOG" 2>&1 || { echo "TESTS FAILED:" >&2; tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
  elif [[ -f "Cargo.toml" ]]; then
    echo "Running cargo tests..." >&2
    TEST_RAN="true"
    cargo test > "$TEST_LOG" 2>&1 || { echo "TESTS FAILED:" >&2; tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
  elif [[ -f "go.mod" ]]; then
    echo "Running Go tests..." >&2
    TEST_RAN="true"
    go test ./... > "$TEST_LOG" 2>&1 || { echo "TESTS FAILED:" >&2; tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
  elif [[ -f "pytest.ini" ]] || [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]]; then
    echo "Running pytest..." >&2
    TEST_RAN="true"
    pytest > "$TEST_LOG" 2>&1 || python -m pytest > "$TEST_LOG" 2>&1 || { echo "TESTS FAILED:" >&2; tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
  elif [[ -f "Makefile" ]] && grep -q "^test:" "Makefile" 2>/dev/null; then
    echo "Running make test..." >&2
    TEST_RAN="true"
    make test > "$TEST_LOG" 2>&1 || { echo "TESTS FAILED:" >&2; tail -20 "$TEST_LOG" >&2; rm -f "$TEST_LOG"; exit 1; }
  fi

  if [[ "$TEST_RAN" == "true" ]]; then
    echo "Tests passed." >&2
  fi
  rm -f "$TEST_LOG"
fi

# 3. Squad verification — HARD BLOCK for non-exempt staged files
STAGED_FILES="$(git diff --cached --name-only 2>/dev/null)" || true
if [[ -n "$STAGED_FILES" ]]; then
  NON_EXEMPT="false"
  NON_EXEMPT_PATTERNS='\.dart$|\.sh$|\.py$|\.js$|\.ts$|\.go$|\.rs$|\.yaml$|\.yml$|\.toml$|^\.claude/|^scripts/|^src/|^lib/|^test/|^tests/|^CLAUDE\.md$'
  if echo "$STAGED_FILES" | grep -qE "$NON_EXEMPT_PATTERNS" 2>/dev/null; then
    NON_EXEMPT="true"
  fi

  if [[ "$NON_EXEMPT" == "true" ]]; then
    if [[ "$SKIP_SQUAD" == "true" ]]; then
      echo "" >&2
      echo "  SQUAD BYPASSED (--skip-squad flag)" >&2
    else
      SQUAD_EVIDENCE="false"
      SQUAD_EXPECTED=("mechanical.md" "adversarial.md" "completeness.md" "dependency.md" "cold_reader.md")
      for sd in $SQUAD_GLOB; do
        [[ ! -d "$sd" ]] && continue
        ALL_PASS="true"
        for ef in "${SQUAD_EXPECTED[@]}"; do
          if [[ ! -f "$sd/$ef" ]] || ! grep -qE "VERDICT: (PASS|WARN)" "$sd/$ef" 2>/dev/null; then
            ALL_PASS="false"
            break
          fi
        done
        if [[ "$ALL_PASS" == "true" ]]; then
          SQUAD_EVIDENCE="true"
          break
        fi
      done

      # Check VERIFICATION_BLOCKED (max rounds exhausted)
      BLOCKED_FILE=""
      if [[ -n "${SENTINEL_CHANNEL:-}" ]] && [[ -f "CURRENT_TASK_ch${SENTINEL_CHANNEL}.md" ]]; then
        BLOCKED_FILE="CURRENT_TASK_ch${SENTINEL_CHANNEL}.md"
      elif [[ -f "CURRENT_TASK.md" ]]; then
        BLOCKED_FILE="CURRENT_TASK.md"
      fi
      if [[ -n "$BLOCKED_FILE" ]] && grep -qE "VERIFICATION_BLOCKED" "$BLOCKED_FILE" 2>/dev/null; then
        SQUAD_EVIDENCE="true"
      fi

      if [[ "$SQUAD_EVIDENCE" == "false" ]]; then
        echo "" >&2
        echo "================================================================" >&2
        echo "  COMMIT BLOCKED: Squad verification required." >&2
        echo "  Run /squad first, or use --skip-squad for WIP commits." >&2
        echo "================================================================" >&2
        exit 1
      fi
    fi
  fi
fi

# 4. Execute commit
git commit "${ARGS[@]}"
COMMIT_EXIT=$?

# 5. Clean up after successful commit
if [[ "$COMMIT_EXIT" -eq 0 ]]; then
  SQUAD_EXPECTED_CLEAN=("mechanical.md" "adversarial.md" "completeness.md" "dependency.md" "cold_reader.md")
  for sd in $SQUAD_GLOB; do
    [[ ! -d "$sd" ]] && continue
    ALL_DONE="true"
    for ef in "${SQUAD_EXPECTED_CLEAN[@]}"; do
      if [[ ! -f "$sd/$ef" ]] || ! grep -qE "VERDICT: (PASS|WARN)" "$sd/$ef" 2>/dev/null; then
        ALL_DONE="false"
        break
      fi
    done
    if [[ "$ALL_DONE" == "true" ]]; then
      rm -f "$sd"/*.md 2>/dev/null
      rmdir "$sd" 2>/dev/null
    fi
  done
  rm -f "verification_findings/commit_check${CH_SUFFIX}.md" "verification_findings/commit_cold_read${CH_SUFFIX}.md" 2>/dev/null
fi

exit $COMMIT_EXIT
