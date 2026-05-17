#!/usr/bin/env bash
# setup-codex.sh — Probe, install, and verify Codex CLI
# Called by cc-sentinel installer after user opts into dual-architecture verification.
#
# Usage: bash setup-codex.sh [--probe-only | --install | --verify-auth]
#
# Modes:
#   --probe-only    Check if codex is on PATH and report version (default)
#   --install       Attempt npm install if codex not found
#   --verify-auth   Run smoke test to confirm auth works
#
# Output: machine-readable STATUS lines for the installer conversation to parse.
#   STATUS: FOUND <version>
#   STATUS: NOT_FOUND
#   STATUS: INSTALLED <version>
#   STATUS: INSTALL_NEED_SUDO
#   STATUS: INSTALL_NO_NODE
#   STATUS: INSTALL_FAILED
#   STATUS: AUTH_OK
#   STATUS: AUTH_FAILED
#   CMD: <command the user must run>

set -euo pipefail

MODE="${1:---probe-only}"

find_codex() {
  if command -v codex &>/dev/null; then
    echo "codex"
  elif command -v codex.cmd &>/dev/null; then
    echo "codex.cmd"
  else
    echo ""
  fi
}

probe() {
  local bin
  bin=$(find_codex)
  if [[ -n "$bin" ]]; then
    local ver
    ver=$("$bin" --version 2>/dev/null | head -1 || echo "unknown")
    echo "STATUS: FOUND $ver"
    exit 0
  else
    echo "STATUS: NOT_FOUND"
    exit 0
  fi
}

install_codex() {
  local bin
  bin=$(find_codex)
  if [[ -n "$bin" ]]; then
    local ver
    ver=$("$bin" --version 2>/dev/null | head -1 || echo "unknown")
    echo "STATUS: FOUND $ver"
    exit 0
  fi

  if ! command -v npm &>/dev/null; then
    echo "STATUS: INSTALL_NO_NODE"
    # Detect OS for install suggestion
    case "$(uname -s)" in
      Darwin)  echo "CMD: brew install node && npm install -g @openai/codex" ;;
      Linux)   echo "CMD: curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash - && sudo apt-get install -y nodejs && npm install -g @openai/codex" ;;
      MINGW*|MSYS*|CYGWIN*) echo "CMD: winget install OpenJS.NodeJS.LTS" ;;
      *)       echo "CMD: npm install -g @openai/codex" ;;
    esac
    exit 0
  fi

  # npm available — check if global dir is writable
  local npm_prefix
  npm_prefix="$(npm config get prefix 2>/dev/null | grep -v '^npm ' | tail -1)"
  if [[ -z "$npm_prefix" ]]; then
    echo "STATUS: INSTALL_NEED_SUDO"
    echo "CMD: sudo npm install -g @openai/codex"
    exit 0
  fi

  if [[ -w "$npm_prefix" ]] || [[ -w "$npm_prefix/lib" ]]; then
    # Can install without sudo — capture exit to avoid set -e abort
    local npm_exit=0
    npm install -g @openai/codex >/dev/null 2>&1 || npm_exit=$?
    if [[ $npm_exit -ne 0 ]]; then
      echo "STATUS: INSTALL_FAILED"
      echo "CMD: npm install -g @openai/codex"
      exit 0
    fi
    hash -r 2>/dev/null
    bin=$(find_codex)
    if [[ -n "$bin" ]]; then
      local ver
      ver=$("$bin" --version 2>/dev/null | head -1 || echo "unknown")
      echo "STATUS: INSTALLED $ver"
    else
      echo "STATUS: INSTALL_FAILED"
      echo "CMD: npm install -g @openai/codex"
    fi
  else
    echo "STATUS: INSTALL_NEED_SUDO"
    echo "CMD: sudo npm install -g @openai/codex"
  fi
  exit 0
}

portable_timeout() {
  local secs=$1; shift
  if command -v timeout &>/dev/null; then
    timeout "$secs" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$secs" "$@"
  else
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill "$pid" 2>/dev/null ) &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    local ret=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    # bash 3.2: wait returns 127 if PID already reaped — treat as success
    if [[ $ret -eq 127 ]]; then ret=0; fi
    return $ret
  fi
}

verify_auth() {
  local bin
  bin=$(find_codex)
  if [[ -z "$bin" ]]; then
    echo "STATUS: NOT_FOUND"
    exit 0
  fi

  local output stderr_tmp
  stderr_tmp=$(mktemp)
  trap 'rm -f "$stderr_tmp"' EXIT
  local exit_code=0
  output=$(echo "Reply with exactly one word: SENTINEL" | portable_timeout 30 "$bin" exec -m gpt-4.1-mini --sandbox read-only --skip-git-repo-check --ephemeral 2>"$stderr_tmp") || exit_code=$?

  if [[ $exit_code -eq 124 ]] || [[ $exit_code -eq 137 ]] || [[ $exit_code -eq 143 ]]; then
    rm -f "$stderr_tmp"
    echo "STATUS: AUTH_FAILED"
    echo "CMD: codex login"
    exit 0
  fi

  if [[ $exit_code -eq 0 ]] && echo "$output" | grep -q "SENTINEL"; then
    rm -f "$stderr_tmp"
    echo "STATUS: AUTH_OK"
  else
    local stderr_content
    stderr_content=$(cat "$stderr_tmp" 2>/dev/null || echo "")
    rm -f "$stderr_tmp"
    if echo "$stderr_content" | grep -qiE "auth|login|key|credential|unauthorized|not configured|forbidden|403"; then
      echo "STATUS: AUTH_FAILED"
      echo "CMD: codex login"
    elif echo "$stderr_content" | grep -qiE "rate.limit|quota"; then
      # Rate limit = auth is valid (authenticated enough to hit limits)
      echo "STATUS: AUTH_OK"
    elif echo "$stderr_content" | grep -qiE "model_not_found|invalid_model|no such model|not supported"; then
      # Model issue = auth is valid (wrong model, not wrong credentials)
      echo "STATUS: AUTH_OK"
    else
      echo "STATUS: AUTH_FAILED"
      echo "CMD: codex login"
    fi
  fi
  exit 0
}

case "$MODE" in
  --probe-only)   probe ;;
  --install)      install_codex ;;
  --verify-auth)  verify_auth ;;
  *)
    echo "ERROR: Unknown mode: $MODE" >&2
    echo "Usage: bash setup-codex.sh [--probe-only | --install | --verify-auth]" >&2
    exit 1
    ;;
esac
