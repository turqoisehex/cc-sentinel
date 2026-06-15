#!/usr/bin/env bash
# Pins the /prove --selftest fixture shape: ## 3b existence, 7-lens count in banner,
# 1-element deterministic set in /4 mode, FILE-TEXT GREP assertions for all generalized
# adversarial-loop.md sites. Mirrors test_workflows_config_parser.sh harness style.
set -uo pipefail
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve adversarial-loop.md (host deploy or CWD-relative project install)
ADVERS_LOOP=""
for candidate in \
    "$HOME/.claude/reference/adversarial-loop.md" \
    ".claude/reference/adversarial-loop.md" \
    "$SCRIPT_DIR/../reference/adversarial-loop.md"; do
  [[ -f "$candidate" ]] && { ADVERS_LOOP="$candidate"; break; }
done
[[ -n "$ADVERS_LOOP" ]] || { echo "FAIL: adversarial-loop.md not found at expected deploy targets"; exit 1; }
echo "Using: $ADVERS_LOOP"

# --- Group A: ## 3b existence and finderSet declaration ---

# A1: ## 3b section exists
grep -q "## 3b" "$ADVERS_LOOP" \
  && ok "## 3b section exists" || no "## 3b section missing"

# A2: lensCount: 7 declared in ## 3b (scoped to ## 3b section to avoid /5 section false-pass)
awk '/^## 3b\./{found=1} found && /^## [^3]/{exit} found{print}' "$ADVERS_LOOP" \
  | grep -q "lensCount: 7" \
  && ok "lensCount: 7 declared in ## 3b" || no "lensCount: 7 not found in ## 3b"

# A3: deterministic lane {6} declared in ## 3b
grep -qE "field-consumption.*per-round|receiptId.*6/field-consumption" "$ADVERS_LOOP" \
  && ok "lane-6 per-component cadence declared" || no "lane-6 cadence missing"

# A4: lenses 8 and 9 ABSENT rationale stated
grep -qE "Lenses 8 and 9 are ABSENT|lenses 8.*9.*absent|lens 8.*N/A|structurally N/A" "$ADVERS_LOOP" \
  && ok "lenses 8+9 absent rationale present" || no "lenses 8+9 absent rationale missing"

# A5: adversarial prime present for LLM lanes (## 3b)
grep -qE "Prove that.*wiring is NOT fully|Prove.*M.*NOT fully" "$ADVERS_LOOP" \
  && ok "adversarial prime present in ## 3b" || no "adversarial prime missing from ## 3b"

# A6: verifyLens refute prompt present
grep -qE "try to REFUTE|FRESH AGENT.*context" "$ADVERS_LOOP" \
  && ok "verifyLens refute prompt present" || no "verifyLens refute prompt missing"

# A7: per-instance second pass declared and explicitly tied to [C] fields on multi-instance types
# Scoped to ## 3b (awk window). A loose grep on the full file would pass even if the ## 3b
# text only says "per-instance second pass" without the [C]/multi-instance qualification.
awk '/^## 3b\./{found=1} found && /^## [^3]/{exit} found{print}' "$ADVERS_LOOP" \
  | grep -qE "\[C\].*multi-instance|per-instance second pass.*\[C\]|for every \[C\] field.*multiple instances" \
  && ok "A7: per-instance second pass tied to [C] fields on multi-instance types in ## 3b" \
  || no "A7: per-instance second pass not tied to [C]/multi-instance in ## 3b (authored phrasing required)"

# --- Group B: engine generalization sites (old literals absent) ---

# B1: "all 9 lenses" literal ABSENT from ## 1.2 (generalized away)
grep -q "all 9 lenses" "$ADVERS_LOOP" \
  && no "old 'all 9 lenses' literal still present" || ok "'all 9 lenses' literal absent"

# B2: generalized ## 1.2 narrative present
grep -q "all lenses in the active finderSet" "$ADVERS_LOOP" \
  && ok "'all lenses in the active finderSet' present" || no "generalized ## 1.2 narrative missing"

# B3: "≤9 lenses" literal ABSENT from ## 2
grep -q "≤9 lenses" "$ADVERS_LOOP" \
  && no "old '≤9 lenses' literal still present" || ok "'≤9 lenses' literal absent"

# B4: generalized ## 2 cap prose present
grep -q "≤ the active finderSet" "$ADVERS_LOOP" \
  && ok "generalized fan-out cap prose present" || no "generalized fan-out cap prose missing"

# B5: '"lensCount": 9' jsonl literal ABSENT from ## 2.2
grep -q '"lensCount": 9' "$ADVERS_LOOP" \
  && no "old '\"lensCount\": 9' literal still present" || ok "'\"lensCount\": 9' literal absent"

# B6: generalized lensCount form present in ## 2.2
grep -q '"lensCount": <active' "$ADVERS_LOOP" \
  && ok "generalized lensCount form present" || no "generalized lensCount form missing"

# B7: standalone ## 2.2 liveness prose paragraph OLD form absent
grep -qE "all-9.*lensStatus|Liveness = all-9" "$ADVERS_LOOP" \
  && no "old 'all-9 lensStatus' prose still present" || ok "'all-9 lensStatus' prose absent"

# B8: generalized ## 2.2 liveness prose present
grep -q "all lenses in the active finderSet accounted-for" "$ADVERS_LOOP" \
  && ok "generalized ## 2.2 liveness prose present" || no "generalized ## 2.2 liveness prose missing"

# B9: ## 6.3 old "lenses 6, 8, or 9" form absent
grep -q "lenses 6, 8, or 9" "$ADVERS_LOOP" \
  && no "old 'lenses 6, 8, or 9' literal in ## 6.3 still present" || ok "'lenses 6, 8, or 9' literal absent"

# B10: ## 6.4 old "lenses 6/8/9" form absent (outside ## 3 section)
# We cannot easily scope to outside ## 3, but the ## 6.4 section is easily searchable
grep -qE "deterministic lens receipt.*lenses 6/8/9|receipt.*lenses 6/8/9" "$ADVERS_LOOP" \
  && no "old 'lenses 6/8/9' in ## 6.4 still present" || ok "'lenses 6/8/9' in ## 6.4 absent"

# B11: per-component cadence schema declared (MD-2 generalization)
grep -q '"check":.*"cadence":.*"receiptId"' "$ADVERS_LOOP" \
  && ok "per-component cadence schema present" || no "per-component cadence schema missing"

# B12: ## 4.4 banner generalized (old "9 lenses" form absent from ## 4.4)
grep -q "engine path (9 lenses" "$ADVERS_LOOP" \
  && no "old 'engine path (9 lenses' literal in ## 4.4 still present" \
  || ok "'engine path (9 lenses' literal in ## 4.4 absent"

# B13: ## 4.4 banner generalized form present
grep -q "engine path.*active finderSet lens count" "$ADVERS_LOOP" \
  && ok "generalized ## 4.4 banner form present" || no "generalized ## 4.4 banner form missing"

# B14: ## 1.1 finderSet input row — old "/5 finderSet = the 9 lenses" literal ABSENT
grep -qE "/5 finderSet = the 9 lenses|finderSet = the 9 lenses" "$ADVERS_LOOP" \
  && no "old '## 1.1 finderSet = the 9 lenses' literal still present" \
  || ok "'finderSet = the 9 lenses' literal absent from ## 1.1"

# B15: ## 1.1 finderSet input row — generalized "active finderSet = the lenses declared in the phase" present
grep -q "active finderSet = the lenses declared in the phase" "$ADVERS_LOOP" \
  && ok "generalized ## 1.1 finderSet-relative phrasing present" \
  || no "generalized ## 1.1 finderSet-relative phrasing missing"

# --- Group C: workflows-config fanoutTypeCap ---
WFCFG=""
for candidate in \
    "$HOME/.claude/reference/workflows-config.md" \
    ".claude/reference/workflows-config.md" \
    "$SCRIPT_DIR/../reference/workflows-config.md"; do
  [[ -f "$candidate" ]] && { WFCFG="$candidate"; break; }
done
[[ -n "$WFCFG" ]] || { echo "FAIL: workflows-config.md not found at expected deploy targets"; exit 1; }

grep -q "fanoutTypeCap" "$WFCFG" \
  && ok "fanoutTypeCap present in workflows-config.md" || no "fanoutTypeCap missing from workflows-config.md"

# --- Group D: /4-mode sub-block present in deployed prove/SKILL.md ---
# D1 is the MECHANICAL RED→GREEN for Task 7: FAILS before Step 7.1 edits prove/SKILL.md
# (the /4-mode sub-block header is absent); PASSES after Step 7.1 + Deploy D.
PROVE_SKILL=""
for candidate in \
    "$HOME/.claude/skills/prove/SKILL.md" \
    "$SCRIPT_DIR/../../sprint-pipeline/skills/prove/SKILL.md"; do
  [[ -f "$candidate" ]] && { PROVE_SKILL="$candidate"; break; }
done
if [[ -z "$PROVE_SKILL" ]]; then
  no "D1: prove/SKILL.md not found at ~/.claude/skills/prove/SKILL.md (Deploy D not yet done)"
else
  # D1: the /4-mode sub-block header — introduced verbatim by Step 7.1, absent before it
  grep -q "7 lenses, deterministic \`{6}\`, 1 receipt" "$PROVE_SKILL" \
    && ok "D1: /4-mode sub-block header present in deployed prove/SKILL.md" \
    || no "D1: /4-mode sub-block header '7 lenses, deterministic \`{6}\`, 1 receipt' absent — Step 7.1 not yet applied or Deploy D not yet done"
fi

# --- Summary ---
echo ""
echo "prove-selftest-fixture: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
