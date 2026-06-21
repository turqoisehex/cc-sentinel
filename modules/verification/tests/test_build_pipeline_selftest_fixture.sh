#!/usr/bin/env bash
# test_build_pipeline_selftest_fixture.sh — static shape assertions for the /3 --selftest fixture.
# The runtime /prove --selftest RUN (the live engine fan-out) is a separate acceptance gate; this
# file asserts the deployed proc-doc + skill carry the /3-mode fixture shape.
set -uo pipefail

PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Resolve each artifact PROJECT-LOCAL-FIRST, then host, then cc-sentinel source — mirroring the existing
# test_prove_selftest_fixture.sh candidate-loop. A consuming project's RUNTIME reads the PROJECT-LOCAL `.claude/reference/*`
# (CWD-relative gate resolution), so a host-only check would let project-local B2/C2 drift pass green while
# `/3` inside the project still runs stale engine content. PROJECT_ROOT defaults to CWD; override via $1.
PROJECT_ROOT="${1:-$PWD}"
# cc-sentinel SOURCE root, computed repo-relative from this test file's location
# (modules/verification/tests/ -> cc-sentinel root), so the last-resort fall-through resolves on ANY
# clone — never a hardcoded developer-machine absolute path (this file ships in the public package).
SENTINEL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
pick(){ for c in "$@"; do [[ -f "$c" ]] && { printf '%s' "$c"; return 0; }; done; printf '%s' "$1"; }
ENGINE=$(pick "$PROJECT_ROOT/.claude/reference/adversarial-loop.md" \
              "$HOME/.claude/reference/adversarial-loop.md" \
              "$SENTINEL_ROOT/modules/verification/reference/adversarial-loop.md")
PROVE=$(pick "$PROJECT_ROOT/.claude/skills/prove/SKILL.md" \
             "$HOME/.claude/skills/prove/SKILL.md" \
             "$SENTINEL_ROOT/modules/sprint-pipeline/skills/prove/SKILL.md")
BUILD=$(pick "$PROJECT_ROOT/.claude/skills/build/SKILL.md" \
             "$HOME/.claude/skills/build/SKILL.md" \
             "$SENTINEL_ROOT/modules/sprint-pipeline/skills/build/SKILL.md")
echo "Resolved targets: ENGINE=$ENGINE  PROVE=$PROVE  BUILD=$BUILD"

# --- Group A: ## 3c shape in deployed adversarial-loop.md ---
if [[ ! -f "$ENGINE" ]]; then
  no "A0: deployed adversarial-loop.md not found at $ENGINE (Deploy B not done)"
else
  # Dot-anchored to match the awk lens-counter below and prove/SKILL.md assertion (iii): the heading
  # is `## 3c.` WITH a trailing period — the dot is intentional, both checks anchor on it consistently.
  grep -q "## 3c\." "$ENGINE" && ok "A1: ## 3c present" || no "A1: ## 3c absent (Deploy B / Task 1 not done)"
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
  # A6: the pipeline-log PRODUCE/VERIFY entries must carry `group` (commit-group id) so multi-checkpoint
  # ordering is provable ENTIRELY within the pipeline-log. Confirm the engine doc's VERIFY entry schema
  # carries `group` (the seq-only form would force external plan knowledge for the per-checkpoint ordering check).
  grep -qE '"stage": "VERIFY", *"seq": <n>, *"group"' "$ENGINE" \
    && ok "A6: pipeline-log VERIFY entry carries group (log-only multi-checkpoint ordering)" \
    || no "A6: pipeline-log VERIFY entry missing group (seq-only — ordering needs external plan knowledge)"
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
  # C4: assertion (ix) RETURN_TO_2 must DIRECTLY assert commit-did-not-fire (git HEAD
  # before/after) AND the CT `## Return to /2` section was written (grep) — not infer "no commit"
  # from the absence of PRODUCE(N+1). Confirm the deployed prove/SKILL.md mechanizes BOTH.
  grep -q "git rev-parse HEAD" "$PROVE" \
    && ok "C4a: (ix) commit-did-not-fire mechanized via git HEAD before/after" \
    || no "C4a: (ix) git rev-parse HEAD before/after assertion absent (no-commit only inferred)"
  grep -q "Return to /2 — design-decision-gap" "$PROVE" \
    && ok "C4b: (ix) CT '## Return to /2' section-write grep mechanized" \
    || no "C4b: (ix) CT Return-to-/2 grep assertion absent"
  # C5: assertion (iv) revert-verify must be CRLF-tolerant — the post-restore content compare normalizes
  # line-endings (tr -d '\r' on both sides) so an Edit/Write CRLF normalization on a Windows host does not
  # false-fire the selftest FAIL gate. Confirm the deployed prove/SKILL.md pins the CRLF-tolerant compare.
  grep -q "CRLF-tolerant" "$PROVE" && grep -q "tr -d '\\\\r'" "$PROVE" \
    && ok "C5: (iv) revert-verify content compare is CRLF-tolerant (tr -d '\\r' both sides)" \
    || no "C5: (iv) CRLF-tolerant revert compare absent (byte-exact compare false-fires on Windows)"
  # C6: the self-revert FAIL path must give the operator an explicit manual config-repair instruction,
  # not a bare FAIL (the live config is left temp-enabled if the revert write itself failed).
  grep -q "CONFIG REPAIR REQUIRED" "$PROVE" \
    && ok "C6: non-reverting-config emits operator CONFIG REPAIR instruction" \
    || no "C6: bare-FAIL on non-revert — no operator repair instruction (live config left temp-enabled)"
  # C7: assertion (vi) must read each per-task VERIFY's commit-group membership from the entry's OWN
  # `group` field (provable ENTIRELY within the pipeline-log), NOT from external plan knowledge — so a
  # multi-checkpoint /3 run's ordering is verifiable from the log alone. Confirm the deployed prove/SKILL.md
  # pins per-entry `group` membership (not "per the plan's commit-group boundary").
  grep -q "whose \`group\` equals G" "$PROVE" \
    && ok "C7: (vi) group membership read from each entry's own group field (log-only proof)" \
    || no "C7: (vi) group membership not log-internal (still needs external plan knowledge)"
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
  # D4: build-gates-ABSENT → lens-5 emits a trivially-covered PASS receipt recording "ext absent"
  # (not a grep crash on a null extension, not a silent lens-5 skip). Confirm the deployed build/SKILL.md
  # pins the trivially-covered "ext absent" receipt path so an implementer cannot guess/crash/skip.
  grep -q "ext absent" "$BUILD" \
    && ok "D4: build-gates-absent → lens-5 trivially-covered PASS receipt ('ext absent')" \
    || no "D4: 'ext absent' trivially-covered lens-5 receipt path absent (null-ext crash/skip undetected)"
  # D5: the scopeHashChecked re-VERIFY loop must have a HARD iteration cap (mirrors engine maxRounds) so an
  # unstable working tree halts with a clear error instead of looping forever. Confirm the deployed
  # build/SKILL.md pins both the cap and the unstable-tree halt error.
  grep -q "scopeHash-unstable" "$BUILD" \
    && ok "D5: scopeHashChecked re-VERIFY loop has an iteration cap + unstable-tree HALT" \
    || no "D5: scopeHashChecked re-VERIFY cap absent (unbounded loop on an unstable tree)"
  # D6: a checkpoint finding that could be either is PRESUMED DESIGN-DECISION → RETURN_TO_2 unless purely a
  # build-execution gap; a producer deferrals[] is automatically DESIGN-DECISION. Confirm the default is pinned
  # so a design-gap cannot be rationalized into a build-execution fix.
  grep -q "PRESUMED DESIGN-DECISION" "$BUILD" \
    && ok "D6: checkpoint-finding default = PRESUMED DESIGN-DECISION (no build-execution rationalization)" \
    || no "D6: design-decision default classification absent (design-gap reclassifiable as build-execution)"
  # D7: duo-mode (CC_DUO_MODE=1) produce->verify contract must be documented — in duo mode the [SONNET] PRODUCE
  # routes through _pending_sonnet/ to a LISTENER, which must STILL write the structured result-FILE (never a
  # held summary), and the PARENT must capture the per-task baseline at PRODUCE(N) START (pre-PRODUCE), before
  # dispatching to the listener. Confirm the deployed build/SKILL.md pins BOTH the listener result-FILE
  # requirement AND the pre-PRODUCE baseline order (duo-mode was otherwise untested by this static fixture).
  grep -q "CC_DUO_MODE" "$BUILD" \
    && grep -q "held summary instead of writing the result-FILE is a build FAIL" "$BUILD" \
    && ok "D7: duo-mode listener writes the structured result-FILE (no held-summary revert)" \
    || no "D7: duo-mode result-FILE contract not documented (listener could revert to held summary)"
  grep -q "BEFORE dispatching the \`\[SONNET\]\` PRODUCE to the listener" "$BUILD" \
    && ok "D7b: duo-mode pre-PRODUCE baseline-capture order documented" \
    || no "D7b: duo-mode pre-PRODUCE baseline order absent (baseline could snapshot post-PRODUCE tree)"
  # D8 (weak prose guard — these two enforcements are review-only by design, not mechanizable in a static
  # fixture; this asserts only that the PROSE requires them, so a future edit cannot silently drop them):
  #   - phantom-citation rejection (parent must not act on an ungroundable citation, both tiers)
  #   - acceptance-criteria empty->task-description fallback (never an empty acceptanceCriteria[])
  grep -q "Phantom-citation rejection" "$BUILD" \
    && ok "D8a: phantom-citation rejection prose present (review-only enforcement documented)" \
    || no "D8a: phantom-citation rejection prose absent"
  grep -q "synthesizes the plan task's \*\*description text\*\*" "$BUILD" \
    && ok "D8b: acceptance empty->task-description fallback prose present (review-only enforcement documented)" \
    || no "D8b: acceptance empty->description fallback prose absent"
  # D9: duo-mode POST-FAIL result-FILE ownership — after a per-task FAIL-fix on the duo path the PARENT
  # directly overwrites the listener-written result-FILE (no re-dispatch to the listener). Confirm the
  # deployed build/SKILL.md pins both the parent-overwrite and the no-re-dispatch.
  grep -q "PARENT directly overwrites the listener-written result-FILE" "$BUILD" \
    && grep -q "no re-dispatch to the listener" "$BUILD" \
    && ok "D9: duo post-FAIL result-FILE ownership = parent-overwrite, no listener re-dispatch" \
    || no "D9: duo post-FAIL result-FILE overwrite/no-re-dispatch contract absent"
  # D10: acceptance-extractor edge rules — First-match-wins (BOTH headings → first encountered wins, no
  # merge) AND block-form capture (numbered/prose/unindented bullets all valid). Confirm the deployed
  # build/SKILL.md pins both (only the empty->description fallback was guarded previously).
  grep -q "First match wins" "$BUILD" \
    && ok "D10a: acceptance extractor First-match-wins rule pinned (no merge/concatenation)" \
    || no "D10a: First-match-wins rule absent (dual-heading merge undefined)"
  grep -q "numbered list" "$BUILD" && grep -q "do NOT assume the bullets are indented" "$BUILD" \
    && ok "D10b: acceptance block-form (numbered/prose/unindented) capture pinned" \
    || no "D10b: acceptance block-form numbered/unindented capture absent"
  # D11: root-absent (not just ext-absent) → lens 5 trivially-covered PASS receipt recording "root absent"
  # (a default src/test root that does not exist must not be a silent miss). D4 covered ext-absent only.
  grep -q "root absent" "$BUILD" \
    && ok "D11: build-gates-absent default root non-existent → lens-5 'root absent' trivially-covered receipt" \
    || no "D11: 'root absent' trivially-covered lens-5 receipt path absent (non-existent default root = silent miss)"
fi

# --- Group E: .gitignore covers the build_pipeline artifacts (obligation 9(a)) ---
# The /3 pipeline writes working-state under verification_findings/build_pipeline[_chN]/, which is
# overwritten per run and reaped at /cleanup — it must never be committed. Confirm the CONSUMING
# project's .gitignore (PROJECT_ROOT) carries a build_pipeline ignore so the gitignore obligation
# has a deterministic guard (prose alone was the LOW gap). The obligation applies only to a project
# that actually runs /3 (one that uses the verification_findings/ working-state convention) — the
# cc-sentinel PACKAGE itself does not run /3 on itself, so its package .gitignore is correctly exempt.
# Gate on the verification_findings/ convention: present => build_pipeline MUST be ignored; otherwise N/A.
# Obligation is met by EITHER an explicit build_pipeline ignore OR a blanket `verification_findings/`
# ignore (a bare-directory line that already covers every build_pipeline* subdir).
GI="$PROJECT_ROOT/.gitignore"
if [[ -f "$GI" ]] && grep -q "verification_findings" "$GI"; then
  if grep -q "build_pipeline" "$GI" || grep -qE "^verification_findings/?\s*$" "$GI"; then
    ok "E1: build_pipeline artifacts gitignored in $GI (explicit or blanket verification_findings/)"
  else
    no "E1: build_pipeline not gitignored in $GI (obligation 9(a))"
  fi
else
  ok "E1: $PROJECT_ROOT does not use the verification_findings/ /3-consumer convention — gitignore obligation N/A (skipped)"
fi

echo ""
echo "build-pipeline-selftest-fixture: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
