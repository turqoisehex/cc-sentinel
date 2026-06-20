#!/usr/bin/env bash
# test_build_pipeline_selftest_fixture.sh — static shape assertions for the /3 --selftest fixture.
# The runtime /prove --selftest RUN (the live engine fan-out) is a separate acceptance gate; this
# file asserts the deployed proc-doc + skill carry the /3-mode fixture shape.
set -uo pipefail

PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Resolve each artifact PROJECT-LOCAL-FIRST, then host, then cc-sentinel source — mirroring the existing
# test_prove_selftest_fixture.sh candidate-loop. Wakeful RUNTIME reads the PROJECT-LOCAL `.claude/reference/*`
# (CWD-relative gate resolution), so a host-only check would let project-local B2/C2 drift pass green while
# `/3` inside Wakeful still runs stale engine content. PROJECT_ROOT defaults to CWD; override via $1.
PROJECT_ROOT="${1:-$PWD}"
pick(){ for c in "$@"; do [[ -f "$c" ]] && { printf '%s' "$c"; return 0; }; done; printf '%s' "$1"; }
ENGINE=$(pick "$PROJECT_ROOT/.claude/reference/adversarial-loop.md" \
              "$HOME/.claude/reference/adversarial-loop.md" \
              "D:/Documents/LLM/cc-sentinel/modules/verification/reference/adversarial-loop.md")
PROVE=$(pick "$HOME/.claude/skills/prove/SKILL.md" \
             "D:/Documents/LLM/cc-sentinel/modules/sprint-pipeline/skills/prove/SKILL.md")
BUILD=$(pick "$HOME/.claude/skills/build/SKILL.md" \
             "D:/Documents/LLM/cc-sentinel/modules/sprint-pipeline/skills/build/SKILL.md")
echo "Resolved targets: ENGINE=$ENGINE  PROVE=$PROVE  BUILD=$BUILD"

# --- Group A: ## 3c shape in deployed adversarial-loop.md ---
if [[ ! -f "$ENGINE" ]]; then
  no "A0: deployed adversarial-loop.md not found at $ENGINE (Deploy B not done)"
else
  grep -q "## 3c" "$ENGINE" && ok "A1: ## 3c present" || no "A1: ## 3c absent (Deploy B / Task 1 not done)"
  # Anchor the lens-heading match at start-of-line (^**Lens) so the indented `- **Lens 4 (…`/`- **Lens 5 (…`
  # bullets in the empty-candidate-behavior subsection are NOT miscounted as lens headings (an unanchored
  # `**Lens [1-5]` would count 7, not 5 — the as-built ## 3c carries those two bullet lines).
  cnt=$(awk '/^## 3c\./{f=1} f && /^## [^3]/{exit} f{print}' "$ENGINE" | grep -c "^\*\*Lens [1-5]")
  [[ "$cnt" == "5" ]] && ok "A2: exactly 5 lenses in ## 3c" || no "A2: ## 3c lens count = $cnt (want 5)"
  grep -q "lensCount: 5" "$ENGINE" && ok "A3: lensCount: 5 declared" || no "A3: lensCount: 5 absent"
  grep -q "4/test-honesty" "$ENGINE" && grep -q "5/consumer-preflight" "$ENGINE" \
    && ok "A4: receiptIds namespaced to lanes 4/5" || no "A4: receiptId 4/test-honesty or 5/consumer-preflight absent"
  # receiptIds NOT mis-namespaced to 6/ for the {4,5} checks
  awk '/^## 3c\./{f=1} f && /^## [^3]/{exit} f{print}' "$ENGINE" | grep -qE "6/test-honesty|6/consumer-preflight" \
    && no "A5: {4,5} checks mis-namespaced to 6/ (would corrupt 6.3/6.4)" \
    || ok "A5: no 6/ namespace collision in ## 3c"
fi

# --- Group B: /5 + /4 generalization markers untouched (regression) ---
if [[ -f "$ENGINE" ]]; then
  grep -q "lensCount: 7" "$ENGINE" && ok "B1: ## 3b lensCount: 7 intact" || no "B1: ## 3b lensCount: 7 perturbed"
  grep -q '"lensCount": <active' "$ENGINE" && ok "B2: generalized jsonl lensCount intact" \
    || no "B2: generalized '\"lensCount\": <active' form missing"
  # The pattern matches ONLY the OLD un-generalized stale-receipt PROSE form ("lenses 6, 8, or 9") that lived
  # in ## 6.3/## 6.4 before the /4 generalization — NOT the /5 finderSet's own {6,8,9} lane declaration (a
  # different shape). Its absence anywhere in the engine confirms ## 6.3/## 6.4 were fully generalized.
  grep -qE "lenses 6, 8, or 9|lenses 6/8/9" "$ENGINE" && no "B3: old un-generalized '{6,8,9}' stale-receipt prose back in 6.3/6.4" \
    || ok "B3: no old '{6,8,9}' stale-receipt prose present (6.3/6.4 generalized)"
fi

# --- Group C: /3-mode sub-block in deployed prove/SKILL.md ---
if [[ ! -f "$PROVE" ]]; then
  no "C0: deployed prove/SKILL.md not found at $PROVE (Deploy D not done)"
else
  grep -q "5 lenses, deterministic \`{4,5}\`, 2 receipts" "$PROVE" \
    && ok "C1: /3-mode sub-block header present in deployed prove/SKILL.md" \
    || no "C1: /3-mode sub-block header '5 lenses, deterministic \`{4,5}\`, 2 receipts' absent — Step 7.1 / Deploy D not done"
  grep -q "CHECKPOINT_ENGINE_START" "$PROVE" \
    && ok "C2: pipeline-log checkpoint-ordering assertion present" || no "C2: CHECKPOINT_ENGINE_START assertion absent"
  grep -q "scopeHashChecked" "$PROVE" \
    && ok "C3: scopeHashChecked-rejection assertion present" || no "C3: scopeHashChecked assertion absent"
fi

# --- Group D: build/SKILL.md carries the engine-path orchestration ---
if [[ ! -f "$BUILD" ]]; then
  no "D0: deployed build/SKILL.md not found at $BUILD (Deploy A not done)"
else
  grep -q "PROVE-GATE: engine path (5 lenses" "$BUILD" \
    && ok "D1: /3 PROVE-GATE 5-lens banner present" || no "D1: /3 5-lens banner absent"
  grep -q "RETURN_TO_2\|Return to /2 — design-decision-gap" "$BUILD" \
    && ok "D2: RETURN_TO_2 design-gap halt present" || no "D2: design-gap halt-to-/2 absent"
  grep -q "implement most conservative default, mark provisional" "$BUILD" \
    && no "D3: old conservative-default model still present (RQ-3 not applied)" \
    || ok "D3: old conservative-default model removed"
fi

echo ""
echo "build-pipeline-selftest-fixture: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
