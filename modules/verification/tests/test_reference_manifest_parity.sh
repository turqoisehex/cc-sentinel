#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../.." && pwd)"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Working-interpreter probe: on Windows/Git Bash `python3` may resolve to a non-functional
# WindowsApps alias, so probe for an interpreter that actually RUNS (not just one on PATH).
PYTHON=""
for p in python3 python py; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import json,sys' >/dev/null 2>&1; then PYTHON="$p"; break; fi
done
[[ -z "$PYTHON" ]] && { echo "FAIL: no working python interpreter (tried python3/python/py)"; exit 2; }

# On Windows/Git Bash, $ROOT is a POSIX path (/d/...) but Python needs a native path (D:/...).
# Use cygpath if available, otherwise pass ROOT as-is (Linux/macOS).
PYROOT="$ROOT"
if command -v cygpath >/dev/null 2>&1; then PYROOT="$(cygpath -w "$ROOT")"; fi

# Helper: check ALL modules.*.files.reference arrays (union) for a basename.
# Reference files live under many modules (core, commit-enforcement, sprint-pipeline,
# governance-protection, verification, ...) — they all install into the single host
# ~/.claude/reference/, so parity is a GLOBAL union, not just the verification module.
in_modules_json_ref() {
  "$PYTHON" -c "
import json, sys, os
data = json.load(open(os.path.join(sys.argv[1], 'modules.json')))
refs = set()
for m in data.get('modules',{}).values():
    refs.update(m.get('files',{}).get('reference',[]))
print('yes' if sys.argv[2] in refs else 'no')
" "$PYROOT" "$1" 2>/dev/null | grep -q 'yes'
}

# Helper: extract REFERENCE=( ... ) array entries from uninstall.sh
# The real shape is a multi-line array: REFERENCE=(\n  "a.md" "b.md"\n  "c.md"\n)
# Use awk to grab everything between REFERENCE=( and the closing ), then extract .md tokens.
extract_uninstall_sh_ref() {
  awk '/^REFERENCE=\(/{found=1; next} found && /^\)/{exit} found{print}' "$ROOT/uninstall.sh" \
    | tr ' ' '\n' | tr -d '"' | grep '\.md$'
}
in_uninstall_sh_ref() {
  extract_uninstall_sh_ref | grep -qx "$1"
}

# Helper: extract $Reference = @(...) array entries from uninstall.ps1
# The real shape is a single-line array: $Reference = @("a.md","b.md",...)
# Scope to the $Reference = @( ... ) assignment line only — never scan other quoted .md strings.
# Use grep -oE (portable POSIX ERE) rather than grep -oP (PCRE, unavailable on some Windows Bash).
extract_uninstall_ps1_ref() {
  grep -E '^\$Reference\s*=' "$ROOT/uninstall.ps1" \
    | grep -oE '"[^"]+\.md"' | tr -d '"'
}
in_uninstall_ps1_ref() {
  extract_uninstall_ps1_ref | grep -qx "$1"
}

# --- FORWARD: every reference file is in all three lists ---
for f in "$ROOT"/modules/*/reference/*.md; do
  [[ -f "$f" ]] || continue; b="$(basename "$f")"
  in_modules_json_ref "$b" && ok "modules.json ref has $b" || no "modules.json ref missing $b"
  in_uninstall_sh_ref "$b"  && ok "uninstall.sh REFERENCE has $b"  || no "uninstall.sh REFERENCE missing $b"
  in_uninstall_ps1_ref "$b" && ok "uninstall.ps1 \$Reference has $b" || no "uninstall.ps1 \$Reference missing $b"
done

# --- REVERSE (bash): every REFERENCE=() entry is a real file ---
while IFS= read -r b; do
  [[ -z "$b" ]] && continue
  found=0
  for f in "$ROOT"/modules/*/reference/"$b"; do [[ -f "$f" ]] && { found=1; break; }; done
  [[ $found -eq 1 ]] && ok "real file for uninstall.sh REFERENCE entry: $b" \
                      || no "stale uninstall.sh REFERENCE entry (no file): $b"
done < <(extract_uninstall_sh_ref)

# --- REVERSE (ps1): every $Reference entry is a real file ---
while IFS= read -r b; do
  [[ -z "$b" ]] && continue
  found=0
  for f in "$ROOT"/modules/*/reference/"$b"; do [[ -f "$f" ]] && { found=1; break; }; done
  [[ $found -eq 1 ]] && ok "real file for uninstall.ps1 \$Reference entry: $b" \
                      || no "stale uninstall.ps1 \$Reference entry (no file): $b"
done < <(extract_uninstall_ps1_ref)

# --- REVERSE (modules.json): every modules.*.files.reference entry is a real file ---
# Note: Python on Windows emits \r\n; strip \r so the basename matches the filesystem glob.
while IFS= read -r b; do
  b="${b%$'\r'}"  # strip trailing carriage return (Windows Python stdout)
  [[ -z "$b" ]] && continue
  found=0
  for f in "$ROOT"/modules/*/reference/"$b"; do [[ -f "$f" ]] && { found=1; break; }; done
  [[ $found -eq 1 ]] && ok "real file for modules.json ref entry: $b" \
                      || no "stale modules.json ref entry (no file): $b"
done < <("$PYTHON" -c "
import json, sys, os
data = json.load(open(os.path.join(sys.argv[1], 'modules.json')))
seen=set()
for m in data.get('modules',{}).values():
    for r in m.get('files',{}).get('reference',[]):
        if r not in seen:
            seen.add(r); print(r)
" "$PYROOT" 2>/dev/null)

# --- EXPLICIT: the two new docs appear in all three lists ---
for b in adversarial-loop.md workflows-config.md; do
  in_modules_json_ref "$b" && ok "new doc in modules.json ref: $b" || no "new doc missing modules.json ref: $b"
  in_uninstall_sh_ref "$b"  && ok "new doc in uninstall.sh REFERENCE: $b"  || no "new doc missing uninstall.sh REFERENCE: $b"
  in_uninstall_ps1_ref "$b" && ok "new doc in uninstall.ps1 \$Reference: $b" || no "new doc missing uninstall.ps1 \$Reference: $b"
done

echo "manifest-parity: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
