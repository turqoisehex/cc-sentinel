#!/usr/bin/env bash
# codex-postfix-scan.sh — Codex-driven integrity scan of a spec after fix application.
# Detects fix-application artifacts (duplicate paragraphs, append-instead-of-edit, stale refs).
#
# Usage: codex-postfix-scan.sh [--no-streak] [--] <spec_path> <output_findings_path>
#
# Exit code semantics (caller MUST distinguish):
#   0 = CLEAN — proceed to next round.
#   1 = ARTIFACTS_FOUND — actionable; fix and re-run.
#   2 = TRANSIENT scan failure (timeout, rate-limit, malformed Codex output, missing
#       VERDICT line, ARTIFACTS_FOUND verdict with no `### A1:` (or `### Artifact N:`)
#       body) — the scan could not produce a usable verdict THIS run. Operator MAY
#       proceed without the scan (safety net, not a hard gate); a logged warning is
#       required.
#   3 = FATAL misconfiguration (wrong arg count, spec/prompt-template not found,
#       codex CLI absent) — wiring bug. Operator MUST fix and re-invoke; do NOT
#       silently proceed.
#   4 = STOP. Two consecutive exit-2 results on the same spec. Do NOT auto-retry;
#       surface to operator.

set -euo pipefail

# Post-/3 maintenance: any edit MUST also update the in-tree draft copy in the
# same commit (verify with `diff -q`). The draft lives alongside the implementation
# plan so a future operator can see the wrapper source without leaving the repo.
# The actual executable lives at ~/.claude/scripts/codex-postfix-scan.sh; the draft
# must be byte-equal to it. If the two diverge, operators reading the plan will
# reason about a wrapper
# that does not match the one the /verify skill actually invokes.

# Defense-in-depth: an attacker controlling the parent environment (or a
# poorly-scoped CI export) could set BASH_ENV / ENV to a script that runs
# before the wrapper's own logic and silently flips CODEX_POSTFIX_NO_STREAK=1
# (or other behavior-modifying state). Strip both at start. Note: this does
# NOT defeat shell-profile-level exports of CODEX_POSTFIX_NO_STREAK itself
# (which the wrapper already WARNs about); this just blocks the indirect
# pre-script-execution vector.
unset BASH_ENV ENV
#
# Explicit extglob support probe via subshell-attempt-enable. The wrapper relies on
# `+([0-9])` in the squad-variant case statement below the EXTGLOB_PREV save/restore
# block. Prior `shopt -p extglob >/dev/null` was inverted: `shopt -p` returns rc=0
# when extglob is currently SET and rc=1 when UNSET, regardless of bash support — so
# on any non-interactive shell (extglob defaults OFF) the wrapper fatal-exited on
# every invocation. Correct probe: attempt-enable in a subshell. The save/restore
# dance below the case statement already handles the supported-but-OFF case via
# `|| true`, so this probe only catches the truly-unsupported case (bash without
# extglob feature).
if ! (shopt -s extglob 2>/dev/null); then
  echo "FATAL: bash extglob unsupported (bash version: $BASH_VERSION) — install bash >= 4.0" >&2
  exit 3
fi

# --no-streak flag: skip the per-spec streak update + STOP guardrail. Required
# during /3 calibration (Task 5a 3-attempt retry budget, Task 5b 3-shot
# idempotency probe) — those protocols deliberately run multiple back-to-back
# invocations on the unchanged spec. If two of those invocations happen to
# exit 2 (rate-limit, timeout, ...), the wrapper's two-consecutive-exit-2 STOP
# guardrail fires BEFORE the calibration's majority-voting / retry logic can
# disposition the run, killing the calibration on a transient blip the
# protocol explicitly authorizes proceeding past. The streak guardrail is
# correct for STEADY-STATE /verify usage (one scan per round) but wrong for
# CALIBRATION usage (multiple scans per round).
#
# Steady-state: do NOT pass --no-streak. Calibration (Task 5a/5b only):
# pass --no-streak on every invocation in the calibration block. Same applies
# to env var CODEX_POSTFIX_NO_STREAK=1 (set by the test harness). The flag is
# documented in Task 6a/6b governance text alongside the streak rule itself.
NO_STREAK=0
_NO_STREAK_FROM_FLAG=0
LOCKDIR=""
# Robust flag parser. Supports flags in any order before positional args
# and detects unknown flags rather than silently treating them as the spec path.
# Loop terminates as soon as a non-flag arg appears or `--` is seen.
while [ $# -gt 0 ]; do
  case "$1" in
    --no-streak)
      NO_STREAK=1
      _NO_STREAK_FROM_FLAG=1
      shift
      ;;
    --)
      shift
      break
      ;;
    --*)
      echo "FATAL: Unknown flag: $1" >&2
      echo "Usage: $0 [--no-streak] [--] <spec_path> <output_findings_path>" >&2
      exit 3
      ;;
    *)
      break
      ;;
  esac
done
[ "${CODEX_POSTFIX_NO_STREAK:-0}" = "1" ] && NO_STREAK=1
if [ "$NO_STREAK" = "1" ] && [ "${_NO_STREAK_FROM_FLAG:-0}" = "0" ]; then
  echo "WARN: streak tracking disabled via CODEX_POSTFIX_NO_STREAK env var (no --no-streak flag passed) — confirm intentional, not a leftover shell-profile export." >&2
fi

if [ $# -ne 2 ]; then
  echo "Usage: $0 [--no-streak] [--] <spec_path> <output_findings_path>" >&2
  exit 3
fi

SPEC_PATH="$1"
OUTPUT_PATH="$2"

# Reject leading-dash paths early — `mktemp "${OUTPUT_PATH}.writing.XXX"` and
# `realpath "$SPEC_PATH"` would parse a leading dash as a flag, surfacing either a
# confusing "unknown option" error or a silent canonicalisation failure.
case "$SPEC_PATH" in
  -*) echo "FATAL: spec path begins with '-'; use './$SPEC_PATH' or an absolute path." >&2; exit 3 ;;
esac
case "$OUTPUT_PATH" in
  -*) echo "FATAL: output path begins with '-'; use './$OUTPUT_PATH' or an absolute path." >&2; exit 3 ;;
esac

# Reject trailing-slash OUTPUT_PATH — directory-shaped paths cause `mv` to use the
# basename of OUTPUT_TMP (a hidden `.writing.XXX` file), so the operator sees an
# empty squad dir and an exit-0 success despite no findings file ever appearing.
case "$OUTPUT_PATH" in
  */) echo "FATAL: output path ends with '/' — supply the filename, e.g., 'integrity_scan.md'." >&2; exit 3 ;;
esac

# Reject OUTPUT_PATH that already exists as a directory. The trailing-slash check
# above rejects directory-shaped path SYNTAX; this rejects an existing directory
# at a non-slash-suffixed path. Without this, `mv "$OUTPUT_TMP" "$OUTPUT_PATH"`
# would silently move OUTPUT_TMP INSIDE the directory (`<dir>/<basename>`), and
# the cold-reader path that opens OUTPUT_PATH as a file would fail with
# `Is a directory` rather than a clear pre-flight error.
if [ -d "$OUTPUT_PATH" ]; then
  echo "FATAL: output path is an existing directory: $OUTPUT_PATH" >&2
  echo "Supply a file path, not a directory (e.g., '<dir>/integrity_scan.md')." >&2
  exit 3
fi

# Same-path operator typo: SPEC_PATH and OUTPUT_PATH must not resolve to the same
# file. The wrapper writes the verdict to OUTPUT_PATH; if it matches SPEC_PATH the
# spec is silently destroyed. Fast-path string equality + canonicalized check below
# (after SPEC_PATH_CANON is computed). Catches the common case immediately; the
# canonicalized check catches the symlinked / different-form aliases.
if [ "$SPEC_PATH" = "$OUTPUT_PATH" ]; then
  echo "FATAL: spec_path and output_findings_path are identical — running the scan would overwrite the spec." >&2
  exit 3
fi

# Symmetric placeholder-character rejection on SPEC_PATH. The
# OUTPUT_PATH guard further down rejects '[', ']', '*' for unsubstituted
# channel-template characters; SPEC_PATH should reject the same set for the same
# reason — an operator who pastes a placeholder spec path needs to see the
# rejection up front, before any state-dir side effects.
case "$SPEC_PATH" in
  *'['*|*']'*|*'*'*)
    echo "Spec path contains literal '[', ']', or '*' character: $SPEC_PATH" >&2
    echo "These are placeholder characters from the channel-routing template (e.g., [chN_])." >&2
    echo "Substitute the actual spec path before invoking the wrapper." >&2
    exit 3
    ;;
esac

# Reject newline / carriage return in spec or output paths. The downstream
# canonicalization strips \n\r from realpath output as a defensive measure;
# without this guard, two distinct files (`/tmp/foo.md` and the literal
# `/tmp/foo\nbar.md`) would canonicalize to the same hash and share a streak
# counter, defeating per-spec keying. Genuine multi-line paths in the wild are
# vanishingly rare; rejecting outright is safer than silent aliasing.
case "$SPEC_PATH" in
  *$'\n'*|*$'\r'*) echo "FATAL: spec path contains newline or carriage return — refusing to proceed (would alias to other paths in streak hashing)." >&2; exit 3 ;;
esac
case "$OUTPUT_PATH" in
  *$'\n'*|*$'\r'*) echo "FATAL: output path contains newline or carriage return — refusing to proceed." >&2; exit 3 ;;
esac

# Codex CLI absence check — run BEFORE any mkdir / streak-file / output-path
# side effects. A missing codex CLI is a FATAL environment error; surfacing
# it before we leave artifacts in ~/.claude/state/ keeps the failure mode
# clean and points the operator at the install issue immediately.
# On Windows + Git Bash, npm installs Codex as `codex.cmd`; bare `codex` may
# not be on PATH even when Codex is functional. Probe both names; only fail
# if neither resolves.
if command -v codex >/dev/null 2>&1; then
  CODEX_CMD=codex
elif command -v codex.cmd >/dev/null 2>&1; then
  CODEX_CMD=codex.cmd
else
  echo "FATAL: codex CLI not in PATH (checked: codex, codex.cmd)" >&2
  exit 3
fi
readonly CODEX_CMD

# Spec + prompt-template existence checks — also run BEFORE any mkdir / state-file
# side effects, for the same reason as the codex check above. A wrong --spec or a
# missing prompt template is FATAL environment misconfiguration; surfacing the
# error before we leave artifacts in ~/.claude/state/ keeps the failure mode
# clean. PROMPT_TEMPLATE may not be defined yet at this point in the script (it's
# resolved a few lines below, after SCRIPT_DIR is computed), so the prompt-template
# existence check is performed at the same place where SCRIPT_DIR / PROMPT_TEMPLATE
# are first available — but the spec check, which only needs $SPEC_PATH (already
# bound at line "$1"), is done here.
if [ ! -f "$SPEC_PATH" ]; then
  echo "FATAL: spec file not found: $SPEC_PATH" >&2
  exit 3
fi

# Streak-state file for the "two consecutive exit-2 → STOP" rule (per Task 6a/6b).
# Without an on-disk artifact, the consecutive-exit-2 counter is unenforceable in
# practice — operators forget to track it across sessions, and a fresh /verify run
# cannot tell whether the previous round on this same spec also hit exit 2. The
# file lives outside the spec dir so it survives `safe-commit.sh`'s squad cleanup.
# Per-spec keying via a hash of the spec path keeps streaks isolated when multiple
# specs are under verification simultaneously.
# Reject HOME values that cannot host a usable state dir: empty, root (`/`), or
# pointing at a non-existent path. `${HOME}/.claude/state` under HOME=/ would
# attempt mkdir at filesystem root — surfaces as a confusing read-only-filesystem
# error and aborts via set -e with rc=1, mimicking ARTIFACTS_FOUND. Surface the
# misconfiguration as exit 3 instead.
if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ] || [ ! -d "$HOME" ]; then
  echo "FATAL: HOME ('${HOME:-<unset>}') is unset, root, or not a directory; cannot locate ~/.claude/state for streak file." >&2
  exit 3
fi
STREAK_DIR="${HOME}/.claude/state"
mkdir -p "$STREAK_DIR" || {
  echo "FATAL: cannot create streak state dir '$STREAK_DIR' (HOME read-only? volume permissions? CI/Docker restricted profile?). Exit 3." >&2
  exit 3
}
# Compute a portable hash of the spec path. Prefer sha256sum (coreutils);
# fall back to shasum -a 256 (stock macOS perl utility). cksum's 32-bit CRC
# has a real collision rate across many distinct spec paths in long-running
# squads, which would alias two specs to the same streak counter and silently
# confuse STOP accounting. Exit 3 (config error) if neither is available.
if command -v sha256sum >/dev/null 2>&1; then
  _sha256() { sha256sum "$@"; }
elif command -v shasum >/dev/null 2>&1; then
  _sha256() { shasum -a 256 "$@"; }
else
  echo "FATAL: neither sha256sum nor shasum found. Install coreutils (Linux: package manager; macOS: stock shasum should be present — check PATH; Windows Git Bash includes sha256sum)." >&2
  exit 3
fi
# Probe `timeout` early (Homebrew installs it as `gtimeout`; detect both).
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=gtimeout
else
  echo "FATAL: neither timeout nor gtimeout found in PATH (Linux: install coreutils; macOS: brew install coreutils). Exit 3." >&2
  exit 3
fi
# Probe `wc` early. The wrapper uses `wc -c` to size-check the spec; placeholder
# hits in the prompt template are counted via `grep -cF`, not `wc -l`. The size
# guard is non-optional; if `wc -c` fails silently, the size guard short-circuits
# to 0 (passing every spec). Surface the missing-binary case as exit 3 here
# rather than letting the failure cascade into a misleading "spec too small"
# error downstream.
if ! command -v wc >/dev/null 2>&1; then
  echo "FATAL: wc binary not found in PATH (install coreutils). Exit 3." >&2
  exit 3
fi

# `mktemp` is hard-required for the prompt-buffer / stderr-buffer / output-temp
# files. Without this probe, mktemp absence surfaces only at the first mktemp
# call (after state-dir creation, after streak file hashing) — at a different
# code site than the other coreutils probes. Pre-flight here to keep error
# diagnostics symmetrical with sha256sum (or shasum)/timeout/wc.
if ! command -v mktemp >/dev/null 2>&1; then
  echo "FATAL: mktemp binary not found in PATH (install coreutils). Exit 3." >&2
  exit 3
fi
# `od` is used by the SPEC_NONCE generator to convert /dev/urandom or /dev/random
# bytes into hex. Absence is non-fatal because the printf '%04x'+epoch+PID
# fallback path covers the no-od case, but emit a one-shot INFO so the operator
# is aware the wrapper is running on the lower-entropy nonce form. We do NOT
# exit 3 — losing /dev/urandom hex nonces only weakens collision resistance
# slightly (epoch+PID is still per-invocation unique on practical hardware).
if ! command -v od >/dev/null 2>&1; then
  echo "INFO: od binary not found in PATH; SPEC_NONCE will use the printf+epoch+PID fallback (lower entropy but per-invocation unique)." >&2
fi
# Canonicalize SPEC_PATH before hashing. Different path
# forms for the same file (./spec.md vs /abs/spec.md vs Windows D:\... vs POSIX
# /d/...) would otherwise key DIFFERENT streak files, defeating the
# consecutive-exit-2 STOP guardrail. Some realpath builds (older BSD/macOS,
# certain BusyBox/Android variants) emit empty stdout with rc=0 on unusual
# inputs — the prior `||`-chained form would then short-circuit with
# SPEC_PATH_CANON="", aliasing every such spec to the empty-string SHA-256 and
# silently disabling STOP across all of them. Gate each fallback explicitly on
# `[ -z ]` so empty-but-rc=0 results fall through.
SPEC_PATH_CANON=$(realpath "$SPEC_PATH" 2>/dev/null || true)
SPEC_PATH_CANON=$(printf '%s' "$SPEC_PATH_CANON" | tr -d '\n\r')
if [ -z "$SPEC_PATH_CANON" ]; then
  SPEC_PATH_CANON=$(readlink -f "$SPEC_PATH" 2>/dev/null || true)
  SPEC_PATH_CANON=$(printf '%s' "$SPEC_PATH_CANON" | tr -d '\n\r')
fi
if [ -z "$SPEC_PATH_CANON" ]; then
  SPEC_PATH_CANON=$(cd "$(dirname "$SPEC_PATH")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$SPEC_PATH")") || SPEC_PATH_CANON=""
  SPEC_PATH_CANON=$(printf '%s' "$SPEC_PATH_CANON" | tr -d '\n\r')
fi
[ -n "$SPEC_PATH_CANON" ] || SPEC_PATH_CANON="$SPEC_PATH"

# Canonicalized SPEC==OUTPUT check (catches symlinked / relative-vs-absolute aliases
# the fast-path string equality at arg-binding time would miss). Mirrors
# SPEC_PATH_CANON's three-step fallback chain so the alias check works on macOS
# without GNU coreutils (`realpath -m` on older BSD silently emits empty stdout
# with rc=0; without fallback, a symlinked copy of the spec passed as the output
# path would be missed and the scan would destroy the spec mid-run).
OUTPUT_PATH_CANON=$(realpath -m "$OUTPUT_PATH" 2>/dev/null || true)
OUTPUT_PATH_CANON=$(printf '%s' "$OUTPUT_PATH_CANON" | tr -d '\n\r')
if [ -z "$OUTPUT_PATH_CANON" ]; then
  OUTPUT_PATH_CANON=$(readlink -f "$OUTPUT_PATH" 2>/dev/null || true)
  OUTPUT_PATH_CANON=$(printf '%s' "$OUTPUT_PATH_CANON" | tr -d '\n\r')
fi
if [ -z "$OUTPUT_PATH_CANON" ]; then
  OUTPUT_PATH_CANON=$(cd "$(dirname "$OUTPUT_PATH")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$OUTPUT_PATH")") || OUTPUT_PATH_CANON=""
  OUTPUT_PATH_CANON=$(printf '%s' "$OUTPUT_PATH_CANON" | tr -d '\n\r')
fi
[ -n "$OUTPUT_PATH_CANON" ] || OUTPUT_PATH_CANON="$OUTPUT_PATH"
if [ "$SPEC_PATH_CANON" = "$OUTPUT_PATH_CANON" ]; then
  echo "FATAL: spec_path and output_findings_path resolve to the same file ($SPEC_PATH_CANON) — running the scan would overwrite the spec." >&2
  exit 3
fi

SPEC_HASH=$(printf '%s' "$SPEC_PATH_CANON" | _sha256 | cut -c1-12)
STREAK_FILE="$STREAK_DIR/codex_postfix_streak_${SPEC_HASH}.txt"

# Streak helpers — called from each exit point. Centralizes the consecutive-exit-2
# counter so the rule documented in Task 6a/6b ("two consecutive exit-2 → STOP") is
# enforced by the wrapper itself, not left to operator discipline.
#
# Symmetric --no-streak semantic. Calibration runs (Task 5a/5b) pass --no-streak;
# under that mode, NEITHER direction touches the streak file: exit 2 does not
# increment, exit 0/1 do not reset. This is intentional. The alternative (have
# calibration CLEAN reset the counter) was rejected because it lets a calibration
# scan retroactively erase a real prior steady-state exit-2 that the operator
# never resolved — calibration measures the wrapper's health on synthetic input,
# which is not the same evidence as "the prior transient cause is gone."
# OPERATOR GOTCHA — if a steady-state exit 2 fired before calibration, the streak
# file still reads "1" after a CLEAN calibration run. Delete the streak file
# manually after resolving the upstream cause; the SKILL.md insertion (Task 6a)
# documents this in the "Consecutive-exit-2 counter — reset rules" block under
# option (b).
streak_reset_and_exit() {  # arg1 = exit code (0 = CLEAN, 1 = ARTIFACTS_FOUND)
  # A5 atomic-write tail: this helper runs on the success paths (CLEAN /
  # ARTIFACTS_FOUND). The codex stdout was staged in OUTPUT_TMP earlier; promote
  # it to OUTPUT_PATH now. Guarded by `-f` because callers from very early exit
  # points (config errors that exit 3) never created OUTPUT_TMP.
  if [ -n "${OUTPUT_TMP:-}" ] && [ -f "$OUTPUT_TMP" ]; then
    mv "$OUTPUT_TMP" "$OUTPUT_PATH"
  fi
  if [ "$NO_STREAK" = "0" ]; then
    # A4 lockdir guard. Mirror the increment path's mkdir-based lock so a CLEAN /
    # ARTIFACTS_FOUND result is unlikely to race with a concurrent transient that is
    # incrementing the same streak file. The streak-file write below is GATED on
    # LOCK_HELD=1: if all 31 lock attempts fail and LOCK_HELD stays 0, the write is
    # SKIPPED (losing one reset is benign — the next exit-0/1 will reset cleanly,
    # whereas a half-truncated file under concurrent write would defeat the STOP
    # guarantee). The rmdir cleanup is also gated on LOCK_HELD=1 so we never remove
    # a directory another process owns. Symmetric with streak_increment_and_exit.
    LOCKDIR="${STREAK_FILE}.lockdir"
    LOCK_HELD=0
    # Retry budget: 31 iterations × 1s sleep = 31s, exceeds the 30s stale-lock
    # threshold by 1s. This guarantees that within one acquire attempt we will
    # either obtain the lock OR observe a stale holder (>30s) and steal it.
    # The prior 10-iteration budget could time out before any stale-recovery
    # path fired, leaving LOCK_HELD=0 and the streak file unwritten under any
    # genuine 11–30s holder.
    LOCK_RETRY_I=0
    while [ "$LOCK_RETRY_I" -lt 31 ]; do
      if mkdir "$LOCKDIR" 2>/dev/null; then
        echo $$ > "$LOCKDIR/pid" 2>/dev/null || :
        LOCK_HELD=1
        LOCKDIR_OWNED="$LOCKDIR"  # Trap rmdirs only when we held the lock.
        break
      fi
      if [ -d "$LOCKDIR" ]; then
        # When both stat forms fail (Termux/Alpine sans coreutils-full),
        # fall back to `date +%s` so the lock looks FRESH (LOCK_AGE = 0). The prior
        # `echo 0` made every concurrent peer's lockdir look ~1.8 billion seconds old,
        # auto-rmdir'ing real holders. Treating an unreadable lock as fresh is safer.
        LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$LOCKDIR" 2>/dev/null || stat -f %m "$LOCKDIR" 2>/dev/null || date +%s)))
        if [ "$LOCK_AGE" -gt 30 ]; then
          # Re-stat just before rmdir to shrink the TOCTOU window — if
          # another peer just acquired the lock (mtime now fresh), do not steal it.
          LOCK_AGE_RECHECK=$(($(date +%s) - $(stat -c %Y "$LOCKDIR" 2>/dev/null || stat -f %m "$LOCKDIR" 2>/dev/null || date +%s)))
          if [ "$LOCK_AGE_RECHECK" -gt 30 ]; then
            HOLDER_PID=$(cat "$LOCKDIR/pid" 2>/dev/null || echo "")
            if [ -n "$HOLDER_PID" ] && kill -0 "$HOLDER_PID" 2>/dev/null; then
              : # holder still alive, skip steal
            else
              rmdir "$LOCKDIR" 2>/dev/null || :
              # Atomic-steal-and-acquire: immediately re-attempt mkdir in the same
              # iteration. The prior shape (rmdir then sleep then retry-mkdir) left
              # a window where a peer could mkdir between our rmdir and the next
              # iteration's mkdir; if our rmdir had stolen a freshly-acquired-but-not-
              # yet-pid-written peer (TOCTOU between LOCK_AGE_RECHECK and rmdir),
              # two writers could enter the critical section. Doing mkdir here makes
              # steal+acquire atomic from our side: either we hold the lock, or
              # another peer raced in (and we yield via sleep+retry without having
              # touched their lockdir).
              if mkdir "$LOCKDIR" 2>/dev/null; then
                echo $$ > "$LOCKDIR/pid" 2>/dev/null || :
                LOCK_HELD=1
                LOCKDIR_OWNED="$LOCKDIR"
                break
              fi
            fi
          fi
        fi
      fi
      sleep 1
      LOCK_RETRY_I=$((LOCK_RETRY_I + 1))
    done
    # Gate the streak-file write on LOCK_HELD so the comment's
    # "best-effort" intent is honored — losing one reset is benign (next exit-0/1
    # will reset), but a half-truncated file under concurrent write is the
    # corruption the lockdir is supposed to avoid.
    # Tolerate write failure (read-only $HOME/.claude/state, NFS
    # permission drift, Windows roaming-profile lock) — emit WARN but don't
    # abort via set -e.
    if [ "$LOCK_HELD" = "1" ]; then
      : > "$STREAK_FILE" 2>/dev/null \
        || echo "WARN: streak file write failed at $STREAK_FILE — continuing without state update" >&2
      rmdir "$LOCKDIR" 2>/dev/null || :
      LOCKDIR_OWNED=""  # Released; trap should not re-rmdir.
    else
      echo "WARN: lockdir $LOCKDIR could not be acquired after retries; skipping streak reset to avoid concurrent-write corruption. The streak counter remains at its previous value; if a prior transient incremented it, the next transient may trigger STOP one round earlier than expected. Symmetric with streak_increment_and_exit." >&2
    fi
  fi
  exit "$1"
}
streak_increment_and_exit() {  # increments streak; exit 2 on first transient, exit 4 on STOP (≥2 consecutive)
  # A5 atomic-write tail: promote the staging file to its final path. Each
  # diagnostic branch (TIMEOUT/AUTH/RATELIMIT/NO_OUTPUT/NO_VERDICT) finishes
  # writing OUTPUT_TMP before calling this helper — the mv finalizes the write.
  if [ -n "${OUTPUT_TMP:-}" ] && [ -f "$OUTPUT_TMP" ]; then
    mv "$OUTPUT_TMP" "$OUTPUT_PATH"
  fi
  if [ "$NO_STREAK" = "1" ]; then
    # Calibration mode — neither read nor write the streak file, do not surface
    # STOP. The caller (Task 5a/5b harness) is responsible for tallying
    # transient outcomes against its own retry/majority budget.
    exit 2
  fi
  # Concurrent-invocation guard: mkdir-based lock instead of flock. `mkdir` is
  # atomic on every POSIX filesystem AND on NTFS via Git Bash on Windows —
  # flock(1)'s behavior on NTFS through Git Bash is unreliable (advisory-only,
  # sometimes a no-op), which left the read-modify-write window racing on
  # Windows runners. mkdir succeeds for the FIRST caller and fails for every
  # concurrent caller until the directory is removed. We retry briefly then
  # proceed best-effort if a stale lockdir is detected (>30s old). The streak
  # read-modify-write below is GATED on LOCK_HELD — if all retry attempts fail,
  # we skip the persistence step rather than risk concurrent-write corruption
  # of the counter (which would defeat the STOP guarantee). The in-memory
  # STREAK still drives this run's STOP decision; the next clean run will
  # reset normally.
  LOCKDIR="${STREAK_FILE}.lockdir"
  LOCK_HELD=0
  # Retry budget: 31 iterations × 1s sleep = 31s, exceeds the 30s stale-lock
  # threshold by 1s. Symmetric with streak_reset_and_exit.
  LOCK_RETRY_I=0
  while [ "$LOCK_RETRY_I" -lt 31 ]; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo $$ > "$LOCKDIR/pid" 2>/dev/null || :
      LOCK_HELD=1
      LOCKDIR_OWNED="$LOCKDIR"  # Trap rmdirs only when we held the lock.
      break
    fi
    # Stale-lock recovery: if the lockdir is older than 30s, the holder almost
    # certainly crashed. Remove it and retry on the next loop iteration.
    # When both stat forms fail (Termux/Alpine sans
    # coreutils-full), fall back to `date +%s` so the lock looks FRESH (LOCK_AGE = 0).
    # The prior `echo 0` made every concurrent peer's lockdir look ~1.8 billion
    # seconds old, auto-rmdir'ing real holders. Symmetric with streak_reset_and_exit.
    if [ -d "$LOCKDIR" ]; then
      LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$LOCKDIR" 2>/dev/null || stat -f %m "$LOCKDIR" 2>/dev/null || date +%s)))
      if [ "$LOCK_AGE" -gt 30 ]; then
        # Re-stat just before rmdir to shrink the TOCTOU window — if
        # another peer just acquired the lock (mtime now fresh), do not steal it.
        # Symmetric with streak_reset_and_exit's stale-lock path.
        LOCK_AGE_RECHECK=$(($(date +%s) - $(stat -c %Y "$LOCKDIR" 2>/dev/null || stat -f %m "$LOCKDIR" 2>/dev/null || date +%s)))
        if [ "$LOCK_AGE_RECHECK" -gt 30 ]; then
          HOLDER_PID=$(cat "$LOCKDIR/pid" 2>/dev/null || echo "")
          if [ -n "$HOLDER_PID" ] && kill -0 "$HOLDER_PID" 2>/dev/null; then
            : # holder still alive, skip steal
          else
            rmdir "$LOCKDIR" 2>/dev/null || :
            # Atomic-steal-and-acquire: immediately re-attempt mkdir in the same
            # iteration. Symmetric with streak_reset_and_exit's path; closes the
            # TOCTOU window between LOCK_AGE_RECHECK and rmdir where a peer could
            # acquire and get their lockdir nuked, then both writers enter the
            # critical section. mkdir here makes steal+acquire atomic from our
            # side: either we hold the lock, or another peer raced in (and we
            # yield via sleep+retry without having touched their lockdir).
            if mkdir "$LOCKDIR" 2>/dev/null; then
              echo $$ > "$LOCKDIR/pid" 2>/dev/null || :
              LOCK_HELD=1
              LOCKDIR_OWNED="$LOCKDIR"
              break
            fi
          fi
        fi
      fi
    fi
    sleep 1
    LOCK_RETRY_I=$((LOCK_RETRY_I + 1))
  done
  PREV=0
  # Cap the read at 16 bytes so a corrupted or hostile streak file (gigabyte-
  # sized random bytes, NUL flood) cannot blow up the shell-variable allocation
  # or burn CPU on the case-pattern numeric check below. A legitimate streak
  # value is one or two ASCII digits.
  [ -f "$STREAK_FILE" ] && PREV=$(head -c 16 "$STREAK_FILE" 2>/dev/null || echo 0)
  # Surface a stderr WARN when corrupt-counter reset fires so an
  # operator who hand-edited the streak file (e.g., Notepad CRLF) sees the
  # silent reset instead of mistakenly trusting that STOP enforcement is intact.
  case "$PREV" in
    '') PREV=0 ;;
    *[!0-9]*)
      echo "WARN: streak file $STREAK_FILE contained non-numeric content; resetting to 0. If this was a manual edit, beware: STOP enforcement just lost one round of state." >&2
      PREV=0
      ;;
  esac
  STREAK=$((PREV + 1))
  # Gate the streak-file write on LOCK_HELD so concurrent invocations cannot
  # interleave a half-truncated file or stomp each other's increments. Under
  # concurrency, an ungated write defeats the STOP guarantee: two peers each
  # read PREV=N, each write N+1, the second pass to ≥2 never lands. If we lose
  # the lock, skip the write — the next exit-0/1 will reset cleanly, and at
  # worst one transient round goes uncounted (benign vs. silent corruption).
  # Tolerate write failure (read-only $HOME/.claude/state, NFS permission drift,
  # Windows roaming-profile lock) — emit WARN but don't abort via set -e.
  if [ "$LOCK_HELD" = "1" ]; then
    echo "$STREAK" > "$STREAK_FILE" 2>/dev/null \
      || echo "WARN: streak file write failed at $STREAK_FILE — continuing without state update" >&2
    rmdir "$LOCKDIR" 2>/dev/null || :
    LOCKDIR_OWNED=""  # Released; trap should not re-rmdir.
  else
    echo "WARN: lockdir $LOCKDIR could not be acquired after retries; skipping streak write to avoid concurrent-write corruption. STOP enforcement may miss this round." >&2
  fi
  if [ "$STREAK" -ge 2 ]; then
    echo "STOP: $STREAK consecutive exit-2 results on $SPEC_PATH (streak file: $STREAK_FILE). Per Task 6a/6b, investigate before next squad dispatch. Reset by either (a) the next scan returning exit 0/1, or (b) deleting the streak file after manually resolving the underlying transient cause and noting the resolution in CURRENT_TASK.md (or your project's state file)." >&2
    # Distinct exit code 4 for the STOP path so callers (the `verify` SKILL.md
    # insertions in Task 6a/6b) can branch on STOP vs. plain transient.
    # Exit 2 = TRANSIENT, single retry permitted; Exit 4 = STOP, do not auto-retry,
    # surface to operator. The `verify` skill's exit-code branching reads exit 4
    # as "halt the calibration / scan loop and surface to user" rather than
    # "retry once."
    exit 4
  fi
  exit 2
}

# Resolve script dir. The cd-and-pwd step canonicalises a relative path to absolute
# (e.g., turns "." into the actual cwd), which is what we want when the script is
# invoked via its full install path. CAVEAT (advisory, not a hard ban): if the
# script is ever placed on PATH and invoked by bare name, `${BASH_SOURCE[0]}` is
# just the bare name, `dirname` returns ".", and SCRIPT_DIR resolves to the
# operator's cwd — wrong. The intended invocation is the full path
# (`~/.claude/scripts/codex-postfix-scan.sh ...`). PATH-installation is permitted
# only after this SCRIPT_DIR resolution is rewritten to handle bare-name lookup
# (e.g., via `realpath "$(command -v "$0")"`); do not symlink as-is.
# Defense-in-depth: refuse bare-name PATH invocation. ${BASH_SOURCE[0]} must
# contain a slash so dirname resolves to the actual install dir, not CWD.
case "${BASH_SOURCE[0]}" in
  */*) : ;;
  *) echo "FATAL: invoke with a path, not a bare PATH name (got: '${BASH_SOURCE[0]}')" >&2; exit 3 ;;
esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_TEMPLATE="$SCRIPT_DIR/codex-postfix-prompt.md"
if [ ! -f "$PROMPT_TEMPLATE" ]; then
  REFERENCE_DIR="$(cd "$SCRIPT_DIR/../reference" 2>/dev/null && pwd)"
  if [ -n "$REFERENCE_DIR" ] && [ -f "$REFERENCE_DIR/codex-postfix-prompt.md" ]; then
    PROMPT_TEMPLATE="$REFERENCE_DIR/codex-postfix-prompt.md"
  fi
fi

[ -f "$PROMPT_TEMPLATE" ]  || { echo "Prompt template missing: $PROMPT_TEMPLATE (checked scripts/ and reference/)" >&2; exit 3; }

# A15: reject unsubstituted channel-template placeholder characters in OUTPUT_PATH.
# The `verify` SKILL.md uses `[chN/]`, `[chN_]`, `[_chN]` as channel-routing
# templates that the operator is supposed to substitute (e.g., `[chN_]` → `ch3_`).
# An operator copy-pasting the template literal would create a path containing
# `[`, `]`, or `*` characters — these survive shell-glob expansion ONLY because
# `safe-commit.sh`'s squad cleanup uses `rm -f "$sd"/*.md` patterns that would
# fail to match a literal-bracket directory. Reject these up front so the
# operator sees the typo before anything is written.
case "$OUTPUT_PATH" in
  *'['*|*']'*|*'*'*|*'?'*)
    echo "Output path contains literal '[', ']', or '*' character: $OUTPUT_PATH" >&2
    echo "These are placeholder characters from the channel-routing template (e.g., [chN_])." >&2
    echo "Substitute the actual channel number, e.g., 'squad_ch3_sonnet/' instead of 'squad_[chN_]sonnet/'." >&2
    exit 3
    ;;
esac

# Resolve OUTPUT_PATH to absolute before squad-binding case statements.
# A relative path like `./scan.md` invoked from inside `verification_findings/squad_ch3_sonnet/`
# would otherwise bypass the top-level binding rule because the case patterns
# anchor on the literal substring `verification_findings/squad_*`. We canonicalize
# via realpath when available, falling back to a portable cd-pwd construction
# under bash 3.2 / Git Bash where realpath may be absent or differ in flag support.
# OUTPUT_PATH retains its original form for filesystem operations (mkdir, redirect
# targets) since both resolve to the same file but the original is shorter in
# error messages.
if command -v realpath >/dev/null 2>&1; then
  OUTPUT_PATH_ABS="$(realpath -m "$OUTPUT_PATH" 2>/dev/null || realpath "$OUTPUT_PATH" 2>/dev/null || echo "$OUTPUT_PATH")"
else
  _op_dir="$(dirname "$OUTPUT_PATH")"
  _op_base="$(basename "$OUTPUT_PATH")"
  if [ -d "$_op_dir" ]; then
    OUTPUT_PATH_ABS="$(cd "$_op_dir" && pwd)/$_op_base"
  else
    case "$_op_dir" in
      /*|[A-Za-z]:*) OUTPUT_PATH_ABS="$_op_dir/$_op_base" ;;
      *)             OUTPUT_PATH_ABS="$(pwd)/$_op_dir/$_op_base" ;;
    esac
  fi
  unset _op_dir _op_base
fi

# Defense-in-depth: if every fallback above still produced a relative path
# (e.g., realpath -m on a macOS without coreutils returns the input verbatim
# when -m is unsupported, or Git Bash's realpath shim accepts paths but emits
# them unchanged), prepend $(pwd)/ so the binding-rule case patterns below
# can reliably anchor on absolute substrings. POSIX path = leading `/`;
# Windows-mixed path under Git Bash = `C:/...` with leading drive letter.
# Anything else is relative — promote it.
case "$OUTPUT_PATH_ABS" in
  /*|[A-Za-z]:/*|[A-Za-z]:\\*)
    : # already absolute (POSIX or Windows drive-letter form)
    ;;
  *)
    OUTPUT_PATH_ABS="$(pwd)/$OUTPUT_PATH_ABS"
    ;;
esac

# Output-path binding rule (matches the documented rule in Architecture and in
# Task 6a/6b). When the output file lands inside `verification_findings/squad*/`,
# it MUST sit at the TOP LEVEL of that squad directory — never inside a
# `spec_rN/` subdir. Reason: `safe-commit.sh`'s squad cleanup runs flat (`rm -f
# "$sd"/*.md` then `rmdir "$sd"`); a nested file survives cleanup and breaks
# `rmdir`. Without this enforcement, an operator typing the path manually can
# silently violate the rule and only discover the breakage at commit time.
#
# Paths OUTSIDE any squad dir (e.g., `/tmp/...` for ad-hoc scans, or
# `verification_findings/codex_postfix_test/...` for fixture testing) are NOT
# subject to safe-commit.sh's squad cleanup and therefore unrestricted — only
# the squad-dir-and-deeper case needs enforcement. Cross-platform: works under
# Git Bash and POSIX shells; uses no GNU-specific extensions.
# Match against the absolute form so a relative path from inside a
# squad dir cannot bypass the binding.
case "$OUTPUT_PATH_ABS" in
  *verification_findings/squad_*/*/*)
    # Path is under a squad dir but at depth >1 (i.e., inside a subdir of squad_*/).
    # Pattern intentionally matches ALL squad_* variants (squad_sonnet, squad_opus,
    # squad_chN_sonnet, etc.) because safe-commit.sh's flat cleanup applies to every
    # squad_* dir, not just sonnet variants.
    echo "Output path violates the squad-dir top-level binding rule: $OUTPUT_PATH" >&2
    echo "Expected: verification_findings/squad_<variant>/<file> (top level only, no subdir)." >&2
    echo "Reason: safe-commit.sh's squad cleanup is flat (rm + rmdir); a nested file would leave a stale dir." >&2
    exit 3
    ;;
esac

# Typo-warning for unrecognized squad-dir variants. The depth-rejection
# case above matches ANY squad_* variant including typos (e.g., squad_typo_sonnet)
# because safe-commit.sh's flat cleanup applies regardless. But a top-level file
# in a typo'd variant (e.g., verification_findings/squad_typo_sonnet/integrity_scan.md)
# would silently survive the depth check. We add a separate WARN-only path-validator
# that fires on top-level files under unrecognized squad variants. The wrapper is
# not a hard validator (the warning is non-fatal) — it just nudges operators to
# notice typos before stale dirs accumulate. Recognized variants enumerated below.
# Enable extglob so `+([0-9])` matches one-or-more digits — handles arbitrary
# channel-number digit counts (ch1, ch12, ch100) without enumerating
# 1-digit / 2-digit / 3-digit cases separately. Restored after the case block.
EXTGLOB_PREV=$(shopt -p extglob || true)  # `shopt -p` returns rc=1 when option is OFF; `|| true` prevents `set -e` from aborting on that benign rc.
shopt -s extglob
# Match against the absolute form (relative-path bypass would otherwise miss the binding).
case "$OUTPUT_PATH_ABS" in
  *verification_findings/squad_sonnet/* | \
  *verification_findings/squad_opus/* | \
  *verification_findings/squad_ch+([0-9])/* | \
  *verification_findings/squad_ch+([0-9])_sonnet/* | \
  *verification_findings/squad_ch+([0-9])_opus/*)
    : # OK — recognized variant
    ;;
  *verification_findings/squad_*)
    echo "WARN: Output path is under an unrecognized squad-dir variant: $OUTPUT_PATH" >&2
    echo "      Known variants: squad_sonnet, squad_opus, squad_chN[_sonnet|_opus]." >&2
    echo "      Proceeding, but verify this is intentional — typo'd squad dirs evade safe-commit.sh's cleanup gate." >&2
    ;;
  *)
    : # Outside any squad dir — unrestricted
    ;;
esac
eval "$EXTGLOB_PREV"  # restore prior extglob state

_OUTPUT_DIRNAME="$(dirname "$OUTPUT_PATH")"
mkdir -p "$_OUTPUT_DIRNAME" 2>/dev/null || :
# Defense-in-depth: mkdir -p exits 0 even when the parent already exists as a
# non-directory (e.g., a regular file at that path). The subsequent redirect
# `> "$OUTPUT_TMP"` would then fail mid-scan with a confusing shell error
# rather than a clean wrapper diagnostic. Verify dirname is actually a
# directory and FATAL out otherwise so the operator sees a clear message.
if [ ! -d "$_OUTPUT_DIRNAME" ]; then
  echo "FATAL: Output directory does not exist or is not a directory: $_OUTPUT_DIRNAME" >&2
  echo "  Cause: parent component is a regular file, mkdir was denied (read-only FS / permissions), or a race deleted the directory after creation." >&2
  exit 3
fi
unset _OUTPUT_DIRNAME

# Embed spec into the prompt template (replace {{SPEC_CONTENTS}}).
# Templated mktemp names so concurrent /tmp inspections (lsof, antivirus scans,
# debug greps) can identify files belonging to this wrapper. Bare `mktemp`
# produces opaque names like `/tmp/tmp.XYZ12` that are indistinguishable from
# arbitrary other tools' temp files.
# A12: portable mktemp template. `mktemp -t prefix` is BSD/macOS-incompatible
# (BSD treats -t differently and requires a template form). Pass a full
# directory + template so both BSD and GNU mktemp produce the expected file.
TMP_PROMPT="$(mktemp "${TMPDIR:-/tmp}/codex-postfix-prompt.XXXXXX")"
TMP_STDERR="$(mktemp "${TMPDIR:-/tmp}/codex-postfix-stderr.XXXXXX")"
# Register the EXIT trap immediately after TMP_PROMPT / TMP_STDERR are created.
# Earlier placement (after OUTPUT_TMP) leaked these temp files on the exit-3
# paths between mktemp and trap (mktemp-failure check + OUTPUT_TMP mktemp
# failure). Safe-deref `${OUTPUT_TMP:-}` so the trap fires cleanly even before
# OUTPUT_TMP exists; `rm -f` ignores empty / missing arguments.
# Trap also fires on SIGINT / SIGTERM / SIGHUP so explicit-kill paths run cleanup.
# LOCKDIR_OWNED is set only after a successful `mkdir` (see streak helpers); the
# trap rmdirs only when this process actually held the lock — preventing a
# concurrent peer's freshly-acquired lockdir from being removed by our exit.
trap 'rm -f "${TMP_PROMPT:-}" "${TMP_STDERR:-}" "${OUTPUT_TMP:-}"; [ -n "${LOCKDIR_OWNED:-}" ] && rmdir "${LOCKDIR_OWNED}" 2>/dev/null || :' EXIT INT TERM HUP

# Detect mktemp failure (TMPDIR full / unwritable). Without an explicit
# check, `set -euo pipefail` doesn't catch the empty `$(...)` substitution.
[ -n "$TMP_PROMPT" ] && [ -n "$TMP_STDERR" ] \
  || { echo "FATAL: mktemp failed (TMPDIR=${TMPDIR:-/tmp} full or unwritable, or mktemp absent — run 'command -v mktemp' to distinguish)" >&2; exit 3; }

# A5 atomic-write staging path. Codex stdout and every diagnostic block write
# to OUTPUT_TMP, which is mv'd to OUTPUT_PATH only at successful exit (inside
# streak_reset_and_exit / streak_increment_and_exit). EXIT trap (registered
# above) removes the staging file if the script aborts mid-write — the operator
# sees either the previous OUTPUT_PATH or no OUTPUT_PATH at all, never a
# half-written file. Use mktemp template so concurrent invocations on the same
# OUTPUT_PATH do not collide on staging — last-writer-wins on the FINAL path is
# acceptable, but concurrent stagers must not delete each other's writing file.
OUTPUT_TMP=$(mktemp "${OUTPUT_PATH}.writing.XXXXXX") \
  || { echo "FATAL: mktemp staging failed at ${OUTPUT_PATH}.writing.XXXXXX" >&2; exit 3; }

# Bash-native spec embedding. The previous `awk -v spec_file="..."` approach ran
# the spec path through awk's `-v` string-escape interpreter and silently mangled
# Windows paths (`\n`, `\t`, `\D`, ...) into bytes that did not exist on disk —
# getline returned 0 and the spec was embedded as empty, producing a false-
# negative CLEAN. The bash-native flow below never passes the spec PATH to any
# escape-interpreting layer; it only reads the file via `cat`, which takes a
# literal pathname. Windows paths with backslashes are honored by Git Bash's
# `cat` directly.
[ -f "$SPEC_PATH" ] || { echo "FATAL: Spec not found at read time: $SPEC_PATH" >&2; exit 3; }
SPEC_BYTES=$(wc -c < "$SPEC_PATH" 2>/dev/null || echo 0)
if [ "$SPEC_BYTES" -eq 0 ]; then
  echo "FATAL: Spec file is empty or unreadable (0 bytes): $SPEC_PATH" >&2
  echo "  Cause: spec became unreadable between existence check and read (race), or genuinely empty." >&2
  exit 3
fi

# Self-scan advisory: a spec that contains the literal `{{SPEC_CONTENTS}}` token
# in its body (e.g., this wrapper's own integrity-scan plan, which documents
# the placeholder mechanism in prose) cannot be cleanly self-scanned. The
# defense-in-depth grep at the post-splice step (see "FATAL: {{SPEC_CONTENTS}}
# placeholder survived bash splice") fires a false-positive because the token
# appears in the spec body — which got embedded between the head/tail markers
# but is detected by a grep that reads head+tail+body. Surface a WARN so the
# operator scans against an escaped copy, not a fatal block (some operators
# legitimately want to attempt the self-scan and inspect the FATAL diagnostic).
if grep -qF '{{SPEC_CONTENTS}}' "$SPEC_PATH" 2>/dev/null; then
  echo "WARN: spec body contains literal \`{{SPEC_CONTENTS}}\` token — this token appears verbatim between the sentinels and is treated as spec content (harmless). The defense-in-depth check is scoped to the template HEAD/TAIL only and does not trigger. Proceeding." >&2
fi

# Meta-spec ANSI-strip caveat: if the spec body documents auth or rate-limit
# vocabulary, the codex CLI may color-wrap those tokens in stderr prompt-echoes
# and the ANSI strip's whitespace handling may not reconstruct exact-line matches
# for the prompt-echo exclusion (`grep -vxFf`). False-positive TRANSIENT_AUTH or
# TRANSIENT_RATE_LIMIT can result. Warn the operator so they don't chase a
# phantom rate-limit / auth failure.
if grep -qiE '(401|403|token expired|please log in|not authenticated|429|rate limit|too many requests)' "$SPEC_PATH" 2>/dev/null; then
  echo "WARN: spec body contains auth/rate-limit vocabulary; if the scan returns TRANSIENT_AUTH or TRANSIENT_RATE_LIMIT, prompt-echo exclusion may have failed on color-coded stderr. Inspect ${TMP_STDERR:-stderr} if available." >&2
fi

# VERDICT-vocabulary advisory (Adv MED-2, ch4 R2): meta-specs that document the
# wrapper's output format may contain literal `VERDICT: CLEAN` or
# `VERDICT: ARTIFACTS_FOUND` lines. Codex can echo such lines into its reply,
# and the wrapper's first-VERDICT parse will match the echoed line before the
# real verdict — potentially suborning the result. Pre-flight WARN matches the
# auth/rate-limit advisory pattern: emit and proceed; operator may escape the
# tokens (e.g., `VERDICT\: CLEAN`) or scan a sanitized copy if the scan returns
# CLEAN unexpectedly.
if grep -qE '^VERDICT: (CLEAN|ARTIFACTS_FOUND)$' "$SPEC_PATH" 2>/dev/null; then
  echo "WARN: spec body contains literal \`VERDICT: CLEAN\` or \`VERDICT: ARTIFACTS_FOUND\` lines; Codex may echo these and the wrapper's first-VERDICT-line parse could match the echoed line before the real verdict. Consider escaping or scanning a sanitized copy if the scan returns CLEAN unexpectedly." >&2
fi

# Locate the {{SPEC_CONTENTS}} placeholder line in the prompt template. We require
# EXACTLY ONE occurrence — multiple placeholders (e.g., a hand-edit that copy-pasted
# the marker) would produce ambiguous embedding (only the first gets substituted,
# remaining ones would survive into the prompt). grep -n returns "LINENUM:LINE";
# we extract the line number with cut.
# Use an explicit if-block instead of `... || echo 0` because under
# `set -euo pipefail`, `grep -c` on no-match returns rc=1 with stdout `0`; the
# fallback `echo 0` then appends a second `0`, producing the multi-line
# `"0\n0"` capture that breaks the integer test below. The if-block sidesteps
# the || semantics entirely.
if PLACEHOLDER_HITS=$(grep -cF '{{SPEC_CONTENTS}}' "$PROMPT_TEMPLATE" 2>/dev/null); then
  :  # grep succeeded; PLACEHOLDER_HITS holds the count
else
  PLACEHOLDER_HITS=0
fi
if [ "$PLACEHOLDER_HITS" -ne 1 ]; then
  echo "FATAL: Prompt template must contain exactly one {{SPEC_CONTENTS}} placeholder (found $PLACEHOLDER_HITS in $PROMPT_TEMPLATE)." >&2
  exit 3
fi
PLACEHOLDER_LINE=$(grep -nF '{{SPEC_CONTENTS}}' "$PROMPT_TEMPLATE" | head -1 | cut -d: -f1)

# Nonce-suffixed spec sentinels. The prompt template uses
# `{{BEGIN_SPEC_SENTINEL}}` and `{{END_SPEC_SENTINEL}}` placeholders (and the
# instructions reference those tokens by name). At wrapper invocation we generate
# a per-run nonce and substitute both placeholders in the prompt scaffold (header
# and footer ONLY — never inside the spliced spec body, which preserves any
# verbatim mentions the spec itself contains). A meta-spec that quotes the literal
# `<!-- BEGIN_SPEC -->` / `<!-- END_SPEC -->` strings (e.g., this plan) cannot
# collide with the wrapper's actual delimiters because the actual delimiters now
# carry a unique nonce, and the spec body is never substituted.
#
# Nonce form: 32 hex chars (128 bits) sourced from /dev/urandom when available,
# falling back to /dev/random, then to bash $RANDOM concatenated multiple times.
# /dev/urandom is the strong default — it's present on Linux/macOS/Git-Bash
# and produces a non-guessable nonce that defeats sentinel-collision attacks
# from a co-located attacker who can observe `ps`/clock/PID. The earlier
# `epoch_RANDOM_PID` form was guessable in under 32K attempts on shared CI.
if [ -r /dev/urandom ]; then
  SPEC_NONCE="$(head -c 16 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n')"
elif [ -r /dev/random ]; then
  SPEC_NONCE="$(head -c 16 /dev/random 2>/dev/null | od -An -tx1 | tr -d ' \n')"
else
  SPEC_NONCE=""
fi
if [ -z "$SPEC_NONCE" ] || [ "${#SPEC_NONCE}" -lt 16 ]; then
  # Fallback for environments without /dev/urandom: concatenate $RANDOM eight
  # times (15 bits each = 120 bits) plus epoch+PID. Less robust than urandom
  # but better than the old single-RANDOM form.
  SPEC_NONCE="$(printf '%04x%04x%04x%04x%04x%04x%04x%04x_%s_%s' \
    "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" \
    "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" \
    "$(date +%s)" "$$")"
fi
BEGIN_SENTINEL="<!-- BEGIN_SPEC_${SPEC_NONCE} -->"
END_SENTINEL="<!-- END_SPEC_${SPEC_NONCE} -->"

# Verify the prompt template uses the placeholder form (catches a stale install
# where the template still has the literal `<!-- BEGIN_SPEC -->` strings — that
# version collides on meta-specs).
if ! grep -qF '{{BEGIN_SPEC_SENTINEL}}' "$PROMPT_TEMPLATE"; then
  echo "FATAL: Prompt template missing {{BEGIN_SPEC_SENTINEL}} placeholder in $PROMPT_TEMPLATE." >&2
  echo "  Cause: stale install. Re-install from the in-tree draft's sibling prompt template." >&2
  exit 3
fi
if ! grep -qF '{{END_SPEC_SENTINEL}}' "$PROMPT_TEMPLATE"; then
  echo "FATAL: Prompt template missing {{END_SPEC_SENTINEL}} placeholder in $PROMPT_TEMPLATE." >&2
  exit 3
fi

# Splice: header (lines 1 .. placeholder-1)  +  spec contents  +  footer (lines placeholder+1 .. EOF).
# Header and footer flow through `sed` to substitute the nonce-suffixed sentinels;
# the spec body itself (`cat "$SPEC_PATH"`) is NEVER piped through sed — that
# preserves verbatim mentions inside the spec, which is the whole point of the
# nonce mechanism. Each step is a single bash builtin / coreutils call with
# literal paths — no escape interpretation of $SPEC_PATH, no awk -v hazard, no
# cygpath dependency.
#
# Sed delimiter choice: pipe `|` is used because the substitution values contain
# only HTML-comment characters (`<`, `!`, `-`, `>`, alphanumeric, `_`); none of
# those collide with `|`. The substitution values cannot contain `|` themselves
# because $SPEC_NONCE is either 32 hex chars (0-9, a-f from /dev/urandom — the
# primary path) or hex+underscore+numeric (the printf '%04x' fallback combined
# with epoch and PID). Neither character class contains `|`.
{
  if [ "$PLACEHOLDER_LINE" -gt 1 ]; then
    head -n $((PLACEHOLDER_LINE - 1)) "$PROMPT_TEMPLATE" \
      | sed -e "s|{{BEGIN_SPEC_SENTINEL}}|${BEGIN_SENTINEL}|g" \
            -e "s|{{END_SPEC_SENTINEL}}|${END_SENTINEL}|g"
  fi
  cat "$SPEC_PATH"
  # A16: guarantee a trailing newline after the spec body before the footer (which
  # contains the END_SPEC sentinel). A spec saved without a final newline would
  # otherwise run the END_SPEC HTML comment onto the spec's last visible line,
  # corrupting the sentinel-counting scope used by Pattern 5/6/7.
  printf '\n'
  tail -n +$((PLACEHOLDER_LINE + 1)) "$PROMPT_TEMPLATE" \
    | sed -e "s|{{BEGIN_SPEC_SENTINEL}}|${BEGIN_SENTINEL}|g" \
          -e "s|{{END_SPEC_SENTINEL}}|${END_SENTINEL}|g"
} > "$TMP_PROMPT"

# Defense-in-depth: strip CRLF from TMP_PROMPT after assembly. The prompt is
# assembled from PROMPT_TEMPLATE + SPEC_PATH; if either has Windows line
# endings (a Windows editor save, a git config that converts on checkout),
# the later `grep -vxFf "$TMP_PROMPT" "$TMP_STDERR"` exact-line exclusion
# fails silently — every prompt-echo line keeps its trailing \r and matches
# nothing in the LF-stripped TMP_STDERR, so prompt content (auth/rate-limit
# vocabulary in the spec body, controlled-vocabulary words in the template
# instructions) bleeds through to detection and produces false TRANSIENT
# verdicts on meta-spec scans.
{ tr -d '\r' < "$TMP_PROMPT" > "${TMP_PROMPT}.lf" && mv "${TMP_PROMPT}.lf" "$TMP_PROMPT"; } || true

# Defense-in-depth placeholder-survival check now
# scopes to TEMPLATE-derived regions (head + tail) only — never the full spliced
# file. The original whole-file check false-positived on meta-specs that document
# the splice mechanism (e.g., this wrapper's own design plan, which references
# `{{SPEC_CONTENTS}}` verbatim). The earlier "exactly one placeholder" check at
# line ~548 already proves the template can't smuggle the placeholder past the
# split — so re-scanning the merged file (which contains spec body text) buys
# nothing and breaks the most important class of input. Head/tail-only check
# preserves the original intent: catch a broken splice where head|tail still
# carries the marker. Spec body content is not the wrapper's concern.
{
  if [ "$PLACEHOLDER_LINE" -gt 1 ]; then
    head -n $((PLACEHOLDER_LINE - 1)) "$PROMPT_TEMPLATE"
  fi
  tail -n +$((PLACEHOLDER_LINE + 1)) "$PROMPT_TEMPLATE"
} | grep -qF '{{SPEC_CONTENTS}}' && {
  echo "FATAL: {{SPEC_CONTENTS}} placeholder survived bash splice (template head/tail still carry the marker)." >&2
  echo "  Cause: prompt template has multiple placeholders or splice logic is broken. Verify $PROMPT_TEMPLATE." >&2
  exit 3
}

# Progress message -> stderr (not stdout): wrapper stdout is captured to the findings
# file via redirect; progress text would otherwise pollute that file.
echo "Running Codex integrity scan on $(basename "$SPEC_PATH")..." >&2

# Pipe prompt via STDIN — `codex exec` reads from stdin when no positional prompt is
# given. This sidesteps the Windows CreateProcess ~32K command-line limit; the
# large specs at ~330 KB exceed the limit by 10x and would crash if passed
# positionally. Empirically verified 2026-05-01: `codex exec` writes ONLY the agent's
# final reply to stdout; banner, session metadata, model name, prompt echo, and token
# count all go to stderr. So stdout -> $OUTPUT_PATH gives a clean findings file with
# no diagnostic preamble, and stderr -> $TMP_STDERR is reserved for the rate-limit
# grep below.
#
# Capture codex's exit status WITHOUT letting `set -e` kill the script and WITHOUT
# discarding the exit code (which a bare `|| true` would do). We use `set +e` /
# `set -e` brackets so $? holds codex's real exit code; that lets the WARN messages
# below surface "codex exited with rc=N" instead of leaving the operator guessing
# whether the wrapper's exit-2 was the rate-limit branch, the empty-output branch,
# or codex's own non-zero exit. Without this, an operator debugging a flaky scan
# cannot tell whether codex itself returned non-zero or whether the wrapper's
# heuristics fired on a successful-but-malformed reply.
# Model: this account's Codex CLI runs ONLY gpt-5.5. The CLI's OWN default is
# gpt-5.3-codex, and ALL '-codex' variants HTTP-400 on a ChatGPT account ("not
# supported when using Codex with a ChatGPT account") -> codex rc=1 -> the scan
# returns VERDICT: TRANSIENT_NO_OUTPUT on EVERY run. So pass -m explicitly.
# Override via the CODEX_MODEL env var if the account's model changes. (cc-sentinel BUG-2)
CODEX_MODEL="${CODEX_MODEL:-gpt-5.5}"
set +e
"$TIMEOUT_CMD" 300 "$CODEX_CMD" exec -m "$CODEX_MODEL" -c model_reasoning_effort="high" --skip-git-repo-check < "$TMP_PROMPT" \
  > "$OUTPUT_TMP" 2>"$TMP_STDERR"
CODEX_EXIT=$?
set -e

# CRLF strip on $TMP_STDERR before any `grep -vxFf "$TMP_PROMPT" "$TMP_STDERR"`
# comparison. On Windows (Git Bash, MSYS2), the codex CLI may emit CRLF line
# endings while $TMP_PROMPT is LF-only — the -vxF exact-line match then fails
# to subtract prompt-echoed lines, leaving them visible to AUTH_RE / RATELIMIT
# regexes and producing false positives on meta-specs that quote auth/429
# tokens in their body. Strip CR bytes once, in place, so all downstream
# comparisons run on a normalized buffer.
if tr -d '\r' < "$TMP_STDERR" > "${TMP_STDERR}.lf" 2>/dev/null; then
  mv "${TMP_STDERR}.lf" "$TMP_STDERR"
else
  rm -f "${TMP_STDERR}.lf" 2>/dev/null || :
  echo "WARN: CRLF strip on $TMP_STDERR failed; AUTH/RATELIMIT detection may misclassify CRLF-suffixed prompt echoes" >&2
fi

# ANSI escape strip on $TMP_STDERR — separate from CRLF strip, both are needed.
# Empirically observed 2026-05-09: codex CLI's `exec` mode reformats prompt-echo
# lines on stderr with ANSI color codes (e.g., reverse-video `\x1B[7m...\x1B[0m`
# for backtick-quoted spans). These embedded escapes break the `grep -vxFf`
# byte-equal exclusion against the LF-only $TMP_PROMPT, surviving prompt-echo
# lines reach the AUTH_RE / RATELIMIT regexes and false-positive when the spec
# body itself documents tokens like "401", "token expired", or "please log in"
# (e.g., this wrapper's own design plan documenting the AUTH detection
# vocabulary). Strip CSI escape sequences (CSI = ESC `[` ... letter) so the
# exact-line match has any chance of subtracting prompt echoes. The pattern
# matches ESC `[` followed by zero-or-more parameter bytes (`0-9` and `;`)
# and a single final byte (`a-zA-Z`); covers all SGR/cursor/clear sequences
# the codex CLI actually emits without overstripping legitimate brackets.
if sed -E $'s/\x1B\\[[0-9;]*[a-zA-Z]//g' "$TMP_STDERR" > "${TMP_STDERR}.noansi" 2>/dev/null; then
  mv "${TMP_STDERR}.noansi" "$TMP_STDERR"
else
  rm -f "${TMP_STDERR}.noansi" 2>/dev/null || :
  echo "WARN: ANSI escape strip on $TMP_STDERR failed; AUTH/RATELIMIT detection may misclassify color-coded prompt echoes" >&2
fi

# NUL strip on $TMP_STDERR symmetric to the OUTPUT_TMP NUL strip below. Without
# this, NUL bytes in Codex stderr cause GNU grep to print "Binary file matches"
# and refuse line matching, defeating the prompt-echo exclusion (`grep -vxFf`)
# that subtracts echoed prompt lines from the AUTH/RATELIMIT regex input.
if tr -d '\0' < "$TMP_STDERR" > "${TMP_STDERR}.nonul" 2>/dev/null; then
  mv "${TMP_STDERR}.nonul" "$TMP_STDERR"
else
  rm -f "${TMP_STDERR}.nonul" 2>/dev/null || :
fi

# rc=127 is "command not found at exec time" — the resolved $CODEX_CMD was on
# PATH at the early probe but failed to exec. Most likely cause now (post-CODEX_CMD
# fix): the binary was uninstalled or moved between probe and exec, or the shim
# referenced by `command -v` no longer resolves to a runnable file. Distinct from
# 124 (timeout) and the other transient classes; surface as fatal misconfig
# (exit 3), not transient.
if [ "$CODEX_EXIT" -eq 127 ]; then
  echo "FATAL: codex CLI exec failed (rc=127, command not found at exec time despite PATH probe). Resolved \$CODEX_CMD=$CODEX_CMD; binary may have been uninstalled or moved mid-session." >&2
  exit 3
fi

# Explicit timeout handling. `timeout 300` exits 124 on kill. A partial reply that
# flushed before the kill could carry a valid VERDICT line but be based on an
# INCOMPLETE read of the spec — Codex may have analyzed only the first quarter
# and emitted CLEAN before being killed. Treating any 124 as TRANSIENT_TIMEOUT
# (regardless of stdout state) closes the false-negative-CLEAN-on-truncated-
# analysis path. The streak counter increments, so two consecutive 300s timeouts
# STOP — appropriate, because a spec consistently exceeding the 300s budget is a
# signal the input is too big or Codex is degraded.
if [ "$CODEX_EXIT" -eq 124 ]; then
  {
    echo "VERDICT: TRANSIENT_TIMEOUT"
    echo ""
    echo "Codex timed out after 300s (rc=124). Any stdout already written may be partial and was discarded for safety."
    echo "Last 20 lines of stderr (captured before EXIT trap deletes \$TMP_STDERR):"
    tail -20 "$TMP_STDERR" | sed 's/^/  /'
  } > "$OUTPUT_TMP"
  echo "WARN: Codex timed out after 300s (rc=124). Diagnostic written to $OUTPUT_PATH." >&2
  streak_increment_and_exit
fi

# Rate-limit / quota detection — match against stderr ONLY. Codex's CLI surfaces
# rate-limit and quota messages on stderr; matching $OUTPUT_PATH would false-positive
# on any spec that mentions "rate limit" or "quota" in its prose (Codex would have
# quoted those strings back in its reply). The regex is tightened to require an
# event qualifier (e.g., "rate-limited", "quota exceeded", "RetryAfter", "429" as
# an HTTP status token) — bare "quota" or "rate limit" in benign metadata lines
# (e.g., "Token quota: 1000 remaining") would otherwise false-positive TRANSIENT.
#
# When a transient cause is detected, the EXIT trap (set above) will delete
# $TMP_STDERR before the operator returns to the terminal — so a WARN message
# directing them to "$OUTPUT_PATH" alone is useless: $OUTPUT_PATH is empty (rate
# limit produced no model reply), and the diagnostic that proves it was a rate
# limit lives in the soon-to-be-deleted $TMP_STDERR. To preserve the diagnostic,
# copy the relevant stderr line(s) into $OUTPUT_PATH itself before exiting, and
# point the operator at $OUTPUT_PATH (which survives the trap).
#
# IMPORTANT regex-mode note: the WORD patterns (rate.?limit, usage.?limit, quota,
# RetryAfter) need `-i` so capitalization variants match (e.g., "Rate Limited",
# "Quota Exceeded", "RetryAfter:"). RetryAfter is alphabetic and lives with the
# words group; only `429` is numeric and lives alone in the no-`-i` regex. A
# future maintainer adding a new transient signal must NOT split alphabetic
# tokens to the numeric regex.
# The numeric 429 status-code pattern, however, must NOT run under `-i` because
# under case-insensitive mode `[^a-z]` is treated as `[^a-zA-Z]`, which means
# common forms like "HTTP 429 Too Many" or "Status: 429" would FAIL to match
# (the lowercase letters in "HTTP"/"Status" fall inside the negated class,
# breaking the alphanumeric boundary the pattern is trying to anchor on).
# Solution: split into two greps — one `-iE` for word patterns, one `-E` (no
# `-i`) for the 429 numeric token. Either match triggers the rate-limit branch.
# Acknowledged false-positive risk on the 429 regex: an unrelated stderr line
# carrying "429" (e.g., a literal 429 in a model-name string or an unrelated
# integer) would route a successful scan to TRANSIENT_RATE_LIMIT. We accept this
# risk because (a) Codex stderr is small and structured and the empirically
# observed false-positive rate is low; (b) a single false TRANSIENT increments
# the streak but resets on the next clean run; (c) two consecutive false-429
# hits WOULD trigger exit 4 STOP — the same operator-intervention path that
# real persistent rate-limits trigger, which is preferable to silently masking
# a real 429 by requiring a co-occurring HTTP-status word (the safer-looking
# alternative would miss real rate-limit events that surface 429 alone). The
# quota/usage punctuation class is broadened to handle common formatted log
# lines (e.g., "quota, exceeded" or "quota — exhausted").
# A3: auth-expired diagnostic. Codex auth failures (expired token, missing
# credentials, 401 from the API) used to fall through to TRANSIENT_NO_OUTPUT,
# leaving the operator to debug an empty findings file with no signal that
# auth was the cause. Surface auth events distinctly so the operator can
# `codex login` and re-run instead of investigating a phantom transient.
# This branch fires BEFORE the rate-limit branch so a 401 carrying both an
# auth message and a "Retry-After" hint is correctly classified as auth (the
# more actionable diagnosis). The tokens scanned for are conservatively
# anchored to common Codex CLI auth-failure surface forms and the standard
# HTTP 401 status; benign words like "authentication" in unrelated stderr
# noise will not match because the regex requires either a status verb
# (expired/invalid/missing/required) or the standalone 401 token.
AUTH_RE='401[[:space:][:punct:]]|please.{0,20}log.?in|token[[:space:][:punct:]]+(expired|invalid|missing|revoked)|invalid[[:space:][:punct:]]+credential|auth(entication)?[[:space:][:punct:]]+(failed|required|expired|missing)|not[[:space:][:punct:]]+authenticated'
# Prompt-echo exclusion for auth detection. codex exec echoes the prompt to
# stderr (verified 2026-05-01). When the prompt is a meta-spec that documents
# auth failure modes — or any spec whose body literally contains tokens like
# `auth-expired`, `401`, `token expired` (this wrapper's own .sh.draft is the
# canonical case: it carries the AUTH_RE pattern and the diagnostic prose) —
# prompt-echo carries those tokens into stderr and false-positives the auth
# grep. Iteration 1 tried filtering markdown-bullet shapes; that caught
# meta-spec PROSE but missed CODE-content meta-specs (the .sh.draft itself).
# Iteration 2 (current): exclude any stderr line whose verbatim text appears
# in TMP_PROMPT — that is content-based, robust to any spec-body shape, and
# cannot mask real CLI-emitted auth lines (which are not in the prompt). The
# fixed-string match is line-anchored (-x) and reads patterns from a file
# (-vxFf), so it scales to large prompts without regex-engine concerns.
if LC_ALL=C grep -vxFf "$TMP_PROMPT" "$TMP_STDERR" | LC_ALL=C grep -qiE "$AUTH_RE"; then
  {
    echo "VERDICT: TRANSIENT_AUTH"
    echo ""
    echo "Codex authentication failure detected on stderr (codex rc=$CODEX_EXIT)."
    echo "Likely cause: token expired, credentials missing, or 401 from the upstream API."
    echo "Resolution: run \`codex login\` (or your install's equivalent) and re-invoke this scan."
    echo "Relevant stderr lines:"
    LC_ALL=C grep -vxFf "$TMP_PROMPT" "$TMP_STDERR" | LC_ALL=C grep -iE "$AUTH_RE" | LC_ALL=C sort -u | sed 's/^/  /'
  } > "$OUTPUT_TMP"
  echo "WARN: Codex auth failure (codex rc=$CODEX_EXIT). Diagnostic written to $OUTPUT_PATH; run \`codex login\` to recover." >&2
  streak_increment_and_exit
fi

# A14: rate-limit alternatives must require an EVENT verb, not bare punctuation.
# An earlier draft included `|: ` as an alternative under `rate.?limit(...)`, which
# turned benign informational lines like "Rate-limit: 5h remaining" or "Rate-limit:
# resets at 12:00" into TRANSIENT_RATE_LIMIT classifications, falsely incrementing
# the streak and tripping STOP on a perfectly healthy session. The verbs below
# (ed/exceeded/reached/hit) require the limit to have been ACTIVATED, not just
# referenced. RetryAfter remains because that token only appears in upstream
# 429-response headers — it is never used in informational metadata.
RATELIMIT_WORDS_RE='rate.?limit(ed| exceeded| reached| hit)|usage.?limit[[:space:][:punct:]]+(exceeded|reached)|quota[[:space:][:punct:]]+(exceeded|reached|exhausted)|RetryAfter'
RATELIMIT_429_RE='(^|[^a-zA-Z0-9])429([^0-9]|$)'
# Same content-based prompt-echo exclusion applied to rate-limit
# detection — `grep -vxFf "$TMP_PROMPT"` removes any stderr line that is a
# verbatim echo of a prompt line, leaving only true CLI-emitted output for the
# regex to scan.
if LC_ALL=C grep -vxFf "$TMP_PROMPT" "$TMP_STDERR" | LC_ALL=C grep -qiE "$RATELIMIT_WORDS_RE" \
   || LC_ALL=C grep -vxFf "$TMP_PROMPT" "$TMP_STDERR" | LC_ALL=C grep -qE "$RATELIMIT_429_RE"; then
  {
    echo "VERDICT: TRANSIENT_RATE_LIMIT"
    echo ""
    echo "Codex rate-limit / quota / usage-limit event detected on stderr (codex rc=$CODEX_EXIT)."
    echo "Relevant stderr lines:"
    {
      LC_ALL=C grep -vxFf "$TMP_PROMPT" "$TMP_STDERR" | LC_ALL=C grep -iE "$RATELIMIT_WORDS_RE" || true
      LC_ALL=C grep -vxFf "$TMP_PROMPT" "$TMP_STDERR" | LC_ALL=C grep -E "$RATELIMIT_429_RE" || true
    } | LC_ALL=C sort -u | sed 's/^/  /'
  } > "$OUTPUT_TMP"
  echo "WARN: Codex rate-limited (codex rc=$CODEX_EXIT). Proceeding without scan. Diagnostic written to $OUTPUT_PATH (stderr captured before EXIT trap deletes \$TMP_STDERR)." >&2
  streak_increment_and_exit
fi

# Fallback: Codex returned no stdout after timeout (rc=124) and auth detection both
# already had their own branches above; if we reach this point, the empty reply is
# from an unknown cause (e.g., Codex exited 0 with nothing on stdout, or a non-124
# rc the timeout/auth heuristics didn't classify). Same preservation rationale as
# the branches above: write a diagnostic into $OUTPUT_PATH so the operator has
# something to read after the EXIT trap removes $TMP_STDERR.
if [ ! -s "$OUTPUT_TMP" ]; then
  {
    echo "VERDICT: TRANSIENT_NO_OUTPUT"
    echo ""
    echo "Codex returned no stdout (codex rc=$CODEX_EXIT; timeout, auth failure, or empty reply)."
    echo "Last 20 lines of stderr (captured before EXIT trap deletes \$TMP_STDERR):"
    tail -20 "$TMP_STDERR" | sed 's/^/  /'
  } > "$OUTPUT_TMP"
  echo "WARN: Codex returned no output (codex rc=$CODEX_EXIT; timeout or auth failure). Diagnostic written to $OUTPUT_PATH." >&2
  streak_increment_and_exit
fi

# BOM strip MUST run BEFORE the VERDICT_LINE grep below — moved here
# from its previous post-VERDICT-detection location, where it was dead code (the
# grep at line below uses ^[[:space:]]* which does not match BOM bytes, so a
# BOM-prefixed CLEAN reply silently routed to TRANSIENT_NO_OUTPUT despite the
# strip's whole purpose being to prevent that). After this strip, all VERDICT
# detection (first-presence grep + verdict-routing greps) runs on the BOM-stripped
# staging file.
# Portability: avoid `sed -i` entirely. BSD `sed -i` (macOS, FreeBSD) requires an
# empty extension argument; GNU `sed -i` (Linux, Git Bash) does not; busybox `sed`
# rejects `-i` outright on some Alpine/Termux builds. Pipe-and-mv is portable
# across all three and avoids the detection branch.
# We DELIBERATELY do not embed the BOM into the regex because grep -E does NOT
# interpret `\xNN` escape sequences as bytes; it treats them as the literal
# characters. sed's `$'...'` ANSI-C-quoted form DOES emit real bytes, so this
# strip works. The strip is a no-op on well-formed input.
if sed $'1s/^\xef\xbb\xbf//' "$OUTPUT_TMP" > "${OUTPUT_TMP}.bomstrip" 2>/dev/null; then
  mv "${OUTPUT_TMP}.bomstrip" "$OUTPUT_TMP"
else
  rm -f "${OUTPUT_TMP}.bomstrip" 2>/dev/null || :
  echo "WARN: BOM-strip pipe failed on $OUTPUT_TMP; proceeding with unstripped file (BOM-prefixed CLEAN may misroute)" >&2
fi

# NUL bytes in Codex stdout cause GNU grep to skip line matching ("Binary file
# matches" stderr) and BSD grep to abort. Strip them so VERDICT detection works.
if tr -d '\0' < "$OUTPUT_TMP" > "${OUTPUT_TMP}.nonul" 2>/dev/null; then
  mv "${OUTPUT_TMP}.nonul" "$OUTPUT_TMP"
else
  rm -f "${OUTPUT_TMP}.nonul" 2>/dev/null || :
fi

# Stream-routing soft assertion. The wrapper-contract documentation in Task 4 and
# the empirical 2026-05-01 verification rely on `codex exec` routing ONLY the
# model reply to stdout. An earlier strict version exited 2 if the FIRST non-empty
# line of $OUTPUT_PATH was not a VERDICT line. That was too brittle — Codex
# occasionally emits a single benign preamble line (e.g., a model-name banner
# that leaked to stdout from a transient CLI bug) followed by a valid VERDICT,
# and the strict assertion converted that perfectly-readable reply into a STOP
# after two such events. The relaxed rule below accepts any output where SOME
# line matches the VERDICT regex, logs WARN to stderr if the VERDICT line is not
# the first non-empty line (so the operator notices stream-routing drift without
# a false STOP), and only fires the strict TRANSIENT branch when NO VERDICT line
# exists at all. Task 1's stdout-only smoke check still validates the strict
# contract once per /3 install — that is the right place to enforce strictness.
#
# `|| true` guards against pipefail killing the script when grep matches
# nothing (the strict no-VERDICT branch handles that case explicitly).
VERDICT_LINE=$(LC_ALL=C grep -nE '^[[:space:]]*VERDICT: ' "$OUTPUT_TMP" | head -1 || true)
if [ -z "$VERDICT_LINE" ]; then
  # No VERDICT line anywhere — preserve original reply, write diagnostic, STOP path.
  # The .raw.md sibling lives next to the FINAL OUTPUT_PATH (not the .writing
  # staging file) so an operator inspecting the squad dir after exit finds it
  # next to the diagnostic. cp from the staging file.
  # `cp` is intentionally NOT probed in the pre-flight block — the
  # `|| echo "WARN: ..."` fallback below is sufficient for this rarely-hit path,
  # and `cp` is universal across every target environment (Git Bash, macOS,
  # Linux, Termux, Alpine). Do not delete the fallback under "we probe what we
  # use" reasoning — that is asymmetric in the OTHER direction (the fallback
  # protects against a forensic-loss silent failure, not against `cp` absence).
  RAW_PRESERVED=0
  cp "$OUTPUT_TMP" "${OUTPUT_PATH}.raw.md" 2>/dev/null && RAW_PRESERVED=1 || \
    echo "WARN: could not preserve raw Codex output at ${OUTPUT_PATH}.raw.md (check disk space / permissions)" >&2
  {
    echo "VERDICT: TRANSIENT_NO_OUTPUT"
    echo ""
    echo "Stream-routing assertion failed (codex rc=$CODEX_EXIT): no VERDICT: line found anywhere in stdout."
    echo ""
    if [ "$RAW_PRESERVED" = "1" ]; then
      echo "Original Codex stdout preserved at: ${OUTPUT_PATH}.raw.md"
    else
      echo "Original Codex stdout could NOT be preserved (cp failed — check disk space and directory permissions)."
    fi
    echo ""
    echo "This suggests the Codex CLI may have regressed on stdout/stderr separation"
    echo "(banner content leaked to stdout, no model reply), or the model returned"
    echo "an unrecognized format. Re-run Task 1's stdout-only smoke check before"
    echo "trusting the wrapper again."
  } > "$OUTPUT_TMP"
  echo "WARN: No VERDICT line in Codex output (codex rc=$CODEX_EXIT). Diagnostic written to $OUTPUT_PATH; original reply preserved at ${OUTPUT_PATH}.raw.md." >&2
  streak_increment_and_exit
fi

VERDICT_LINENUM=$(echo "$VERDICT_LINE" | cut -d: -f1)
# Find the FIRST non-empty line number. If it is not the same as the VERDICT
# line, log a WARN — there is preamble content before the verdict. Do NOT
# convert this to a TRANSIENT/STOP; the verdict itself is intact.
FIRST_NONEMPTY_LINENUM=$(LC_ALL=C grep -nE '[^[:space:]]' "$OUTPUT_TMP" | head -1 | cut -d: -f1 || true)
if [ -n "$FIRST_NONEMPTY_LINENUM" ] && [ "$FIRST_NONEMPTY_LINENUM" -ne "$VERDICT_LINENUM" ]; then
  echo "WARN: VERDICT line is not the first non-empty line of $OUTPUT_PATH (verdict at line $VERDICT_LINENUM, first non-empty at line $FIRST_NONEMPTY_LINENUM). Codex stdout may have a preamble — re-run Task 1's stream-separation check at next /3 install to confirm the contract still holds. Proceeding with the verdict." >&2
fi

# Verdict ordering — check ARTIFACTS_FOUND FIRST. If Codex emits both verdict lines
# (a malformed-output case) the conservative path is to surface artifacts, not silently
# clean. ARTIFACTS_FOUND with an empty body is information-loss; treat as TRANSIENT.
#
# Anchor verdict-routing on the EXACT VERDICT line
# that grep -n already located ($VERDICT_LINENUM), not on the first 5 lines of the
# reply. The previous head -5 cap meant a thinking-preamble pushing VERDICT to line 6+
# fell into the trailing else and emitted TRANSIENT_NO_OUTPUT despite the just-printed
# "Proceeding with the verdict" WARN. The injection-guard rationale (spec quoting
# "VERDICT: CLEAN" inside its body) is satisfied by anchoring on the FIRST
# `^[[:space:]]*VERDICT:` match — the earlier `grep -nE ... | head -1` already does that. A literal
# CLEAN-string inside a code fence further down the reply will not be matched because
# we only inspect $VERDICT_LINENUM (the first match's line number). Artifact-heading
# and Enumeration-trace block checks remain on the full file.
VERDICT_PREFIX='^[[:space:]]*VERDICT: '
VERDICT_HEAD=$(sed -n "${VERDICT_LINENUM}p" "$OUTPUT_TMP")
if printf '%s\n' "$VERDICT_HEAD" | LC_ALL=C grep -qE "${VERDICT_PREFIX}ARTIFACTS_FOUND[[:space:]]*$"; then
  if ! LC_ALL=C grep -qE '^[[:space:]]*###[[:space:]]+[Aa](rtifact[[:space:]]+)?[0-9]+:' "$OUTPUT_TMP"; then
    # Wrapper is reclassifying Codex's ARTIFACTS_FOUND verdict as TRANSIENT (exit 2)
    # because the body is missing. Overwrite OUTPUT_TMP so the findings file's verdict
    # line agrees with the wrapper's exit code; otherwise an operator reading the file
    # sees ARTIFACTS_FOUND while the exit code says transient — contradictory.
    {
      echo "VERDICT: TRANSIENT_NO_OUTPUT"
      echo ""
      echo "Codex emitted ARTIFACTS_FOUND but no '### A1:' artifact body (codex rc=$CODEX_EXIT)."
      echo "Body absence makes the verdict unactionable; reclassifying as transient."
    } > "$OUTPUT_TMP"
    echo "WARN: ARTIFACTS_FOUND but no '### A1:' body present (codex rc=$CODEX_EXIT). See $OUTPUT_PATH" >&2
    streak_increment_and_exit
  fi
  # Mandatory Enumeration trace block check (Pattern 3 proof-of-work). The prompt
  # template requires "## Enumeration trace" under BOTH verdicts. Missing trace =
  # Codex skipped the explicit § N.N enumeration step → treat as malformed/transient.
  if ! LC_ALL=C grep -qE '^[[:space:]]*##[[:space:]]+[Ee]numeration' "$OUTPUT_TMP"; then
    {
      echo "VERDICT: TRANSIENT_NO_OUTPUT"
      echo ""
      echo "Codex emitted ARTIFACTS_FOUND with body but no '## Enumeration trace' block (codex rc=$CODEX_EXIT)."
      echo "Pattern 3 proof-of-work absent; reclassifying as transient."
    } > "$OUTPUT_TMP"
    echo "WARN: ARTIFACTS_FOUND but '## Enumeration trace' block missing (codex rc=$CODEX_EXIT). Pattern 3 proof-of-work absent. See $OUTPUT_PATH" >&2
    streak_increment_and_exit
  fi
  streak_reset_and_exit 1
elif printf '%s\n' "$VERDICT_HEAD" | LC_ALL=C grep -qE "${VERDICT_PREFIX}CLEAN[[:space:]]*$"; then
  if ! LC_ALL=C grep -qE '^[[:space:]]*##[[:space:]]+[Ee]numeration' "$OUTPUT_TMP"; then
    # Wrapper is reclassifying Codex's CLEAN verdict as TRANSIENT (exit 2)
    # because the proof-of-work trace is missing. Overwrite OUTPUT_TMP so the findings
    # file's verdict line agrees with the wrapper's exit code; otherwise an operator
    # reading the file sees CLEAN while the exit code says transient — contradictory.
    {
      echo "VERDICT: TRANSIENT_NO_OUTPUT"
      echo ""
      echo "Codex emitted CLEAN but no '## Enumeration trace' block (codex rc=$CODEX_EXIT)."
      echo "Pattern 3 proof-of-work absent; CLEAN unverifiable, reclassifying as transient."
    } > "$OUTPUT_TMP"
    echo "WARN: CLEAN but '## Enumeration trace' block missing (codex rc=$CODEX_EXIT). Pattern 3 proof-of-work absent — CLEAN unverifiable. See $OUTPUT_PATH" >&2
    streak_increment_and_exit
  fi
  streak_reset_and_exit 0
else
  echo "WARN: VERDICT line at line $VERDICT_LINENUM matched neither ARTIFACTS_FOUND nor CLEAN (codex rc=$CODEX_EXIT). See $OUTPUT_PATH" >&2
  streak_increment_and_exit
fi
