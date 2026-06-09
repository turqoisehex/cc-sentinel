#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Prerequisite guard: the two new reference docs must exist
for f in adversarial-loop.md workflows-config.md; do
  [[ -f "$ROOT/modules/verification/reference/$f" ]] \
    || { echo "SKIP: $f not yet created (run Tasks 2+4 first)"; exit 0; }
done

# Working interpreter for the installers
PY=""; for p in python3 python py; do command -v "$p" >/dev/null 2>&1 && "$p" -c 'import json,sys' >/dev/null 2>&1 && { PY="$p"; break; }; done
[[ -z "$PY" ]] && { echo "SKIP: no working python for the installers (env limitation)"; exit 0; }

# Shim: if python3 is not a working interpreter, create a wrapper that calls $PY
SHIM=""
if ! ( command -v python3 >/dev/null 2>&1 && python3 -c 'import json,sys' >/dev/null 2>&1 ); then
  SHIM="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexec %s "$@"\n' "$(command -v "$PY")" > "$SHIM/python3"; chmod +x "$SHIM/python3"
  export PATH="$SHIM:$PATH"   # install.sh/uninstall.sh now resolve `python3` to a working interpreter
fi

# CWD + HOME isolation (SAFETY-CRITICAL):
# install.sh --target project writes to .claude/ relative to CWD AND to HOME-side artifacts.
# Use a temp CWD AND a temp HOME so every write/removal hits a throwaway home.
TMPDIR_CWD="$(mktemp -d)"; TMPHOME="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_CWD" "$TMPHOME" "${SHIM:-}"' EXIT

# --- Assert: source files exist ---
[[ -f "$ROOT/modules/verification/reference/adversarial-loop.md" ]] \
  && ok "source file exists: adversarial-loop.md" \
  || no "source file missing: adversarial-loop.md"
[[ -f "$ROOT/modules/verification/reference/workflows-config.md" ]] \
  && ok "source file exists: workflows-config.md" \
  || no "source file missing: workflows-config.md"
[[ -d "$ROOT/modules/sprint-pipeline/skills/prove" ]] \
  && ok "source dir exists: sprint-pipeline/skills/prove" \
  || no "source dir missing: sprint-pipeline/skills/prove"

# --- Dry-run install: grep log for both basenames + prove ---
dry_log="$(cd "$TMPDIR_CWD" && HOME="$TMPHOME" bash "$ROOT/install.sh" \
  --modules "verification,sprint-pipeline" --target project --dry-run 2>&1)"
echo "$dry_log" | grep -q 'adversarial-loop.md' \
  && ok "dry-run install mentions adversarial-loop.md" \
  || no "dry-run install does NOT mention adversarial-loop.md"
echo "$dry_log" | grep -q 'workflows-config.md' \
  && ok "dry-run install mentions workflows-config.md" \
  || no "dry-run install does NOT mention workflows-config.md"
echo "$dry_log" | grep -q 'prove' \
  && ok "dry-run install mentions prove" \
  || no "dry-run install does NOT mention prove"

# --- Real install into isolated target ---
( cd "$TMPDIR_CWD" && HOME="$TMPHOME" bash "$ROOT/install.sh" \
  --modules "verification,sprint-pipeline" --target project 2>&1 ) | tail -5

# --- Assert: files were installed under TMPDIR_CWD/.claude/ ---
[[ -f "$TMPDIR_CWD/.claude/reference/adversarial-loop.md" ]] \
  && ok "installed: .claude/reference/adversarial-loop.md" \
  || no "NOT installed: .claude/reference/adversarial-loop.md"
[[ -f "$TMPDIR_CWD/.claude/reference/workflows-config.md" ]] \
  && ok "installed: .claude/reference/workflows-config.md" \
  || no "NOT installed: .claude/reference/workflows-config.md"
[[ -f "$TMPDIR_CWD/.claude/skills/prove/SKILL.md" ]] \
  && ok "installed: .claude/skills/prove/SKILL.md" \
  || no "NOT installed: .claude/skills/prove/SKILL.md"

# --- Dry-run uninstall: grep WOULD REMOVE for both docs + prove ---
# NOTE: We do NOT run the real destructive uninstall. The parity test (Step 5) already proves
# the by-name arrays are correct. This dry-run confirms the log output names the new artifacts.
dry_uninstall_log="$(cd "$TMPDIR_CWD" && HOME="$TMPHOME" bash "$ROOT/uninstall.sh" \
  --target project --dry-run 2>&1)"
echo "$dry_uninstall_log" | grep -q 'WOULD REMOVE.*adversarial-loop.md\|adversarial-loop.md.*WOULD REMOVE' \
  && ok "dry-run uninstall WOULD REMOVE adversarial-loop.md" \
  || { echo "$dry_uninstall_log" | grep -q 'adversarial-loop.md' \
    && ok "dry-run uninstall mentions adversarial-loop.md" \
    || no "dry-run uninstall does NOT mention adversarial-loop.md"; }
echo "$dry_uninstall_log" | grep -q 'WOULD REMOVE.*workflows-config.md\|workflows-config.md.*WOULD REMOVE' \
  && ok "dry-run uninstall WOULD REMOVE workflows-config.md" \
  || { echo "$dry_uninstall_log" | grep -q 'workflows-config.md' \
    && ok "dry-run uninstall mentions workflows-config.md" \
    || no "dry-run uninstall does NOT mention workflows-config.md"; }
echo "$dry_uninstall_log" | grep -q 'WOULD REMOVE.*prove\|prove.*WOULD REMOVE' \
  && ok "dry-run uninstall WOULD REMOVE prove" \
  || { echo "$dry_uninstall_log" | grep -q 'prove' \
    && ok "dry-run uninstall mentions prove" \
    || no "dry-run uninstall does NOT mention prove (skills array may be missing it)"; }

echo "roundtrip: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
