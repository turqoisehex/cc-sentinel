---
name: perfect
description: "Post-implementation quality pass: evaluate, grill loop, verification squad, and proof of correctness with user gates. Phase /4 of the sprint pipeline. Also invoked as /4."
---

# /perfect — Post-Implementation Quality Pass (alias: /4)

`/perfect` (session files) or `/perfect <subsystem>` (named target)

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress->completed.

## Delegation

**Default mode:** Steps marked DELEGATE: spawn Sonnet subagent via `Agent(model: "sonnet")` with the delegation prompt. Output to `verification_findings/` paths specified per step.

**Duo mode:** Steps marked DELEGATE: update CT first, write self-contained prompt to `verification_findings/_pending_sonnet/[chN/]`, wait via `bash ~/.claude/scripts/wait_for_results.sh <paths>`.

## Phase 1: Scope and Evaluate

### 1. Scope

- Bare: session files, fall back to `git diff main...HEAD`.
- Named subsystem: read every file -> `verification_findings/perfect_inventory[_chN].md`.

### 2. Evaluate

Read in-scope files + authoritative spec + project rules. Catalog: accidental complexity, incomplete migrations, over/under-engineering, naming lies. Write to `verification_findings/perfect_evaluation[_chN].md`.

### 3. Branch — user gate

- **Already elegant** -> Phase 2.
- **Sound approach, messy execution** -> Step 4, then Phase 2.
- **Mediocre approach** -> Step 5, then Phase 2.

Present assessment. Wait for approval.

### 4. Simplify

DELEGATE four agents. Report only. YAML frontmatter required.

### 5. Scrap and rewrite

**5a** Design -> user gate.
**5b** DELEGATE build. Sonnet: scaffolding. Opus: judgment.
**5c** DELEGATE swap. Rename, update imports, delete old.
**5d** Same as Step 4 scoped to new code.
**5e** Prove equivalence.

## Phase 2: Grill Loop (max 5 rounds)

`/grill` all `/perfect` work product. Fix -> test -> repeat until clean or 5 rounds. **Do NOT commit in /4.** Grill fixes accumulate and ship in /5's single sprint-close commit. **Commit protocol reference** (for the /5 commit): `.claude/reference/commit-protocol.md` — use `git diff HEAD -- <files>` for verifier input, never `git diff --cached`, never pre-stage.

## Phase 2.5: Source-Spec-Code Fidelity Audit (MANDATORY)

Catches bugs where data declares X, consumer does Y, no verifier opened the consumer file. Runs before the squad, before commit.

**Procedure:** Full procedure lives in `.claude/reference/spec-verification.md`. Key points duplicated here to prevent bypass:

- **Source-first.** Enter verification from the SOURCE materials (books, research, transcripts, domain-expert input) — NOT from a decisions file, prior CC summary, or brainstorming doc. Those are work products, not sources.
- **Bidirectional extraction.** Flat-list the source AND the spec. Cross-reference every source item → spec item, every spec item → source item. Either-side gaps = FAIL.
- **Terminate at the consumer.** Every spec claim must be traced to the runtime component that READS and USES the field — not just to the declaration. A declared field that no engine/widget reads is a dead declaration, not a fulfilled spec.
- **Silent-fallback scan.** Grep consumers for `?? ` and `|| ` near each consumption site. If a consumer has `params['fieldX'] ?? default` and no test proves the model declares `fieldX`, that's a silent override — FAIL.
- **Numeric trace.** Every numeric source value (duration, ratio, count, BPM) must be traceable source value → spec value → data-layer value → runtime value. Cannot produce the runtime number by tracing code = FAIL.
- **Comment-vs-behavior.** Design intent in code comments that the consumer doesn't implement = FAIL. Aspirational comments do not count as implementation.

**Field-consumption audit (one page, every `/4` run):** For each data model touched this sprint, list every declared field and grep the codebase for reads. Mark each: [C] consumed by runtime, [T] test-only (FAIL), [D] dead (FAIL). Output: `verification_findings/field_consumption_audit[_chN].md`. Every [T] or [D] requires resolution — wire the field, delete it, or explicitly mark it reserved with a tracked wiring task. Silent "it's aspirational" is not acceptable.

**Delegation:** DELEGATE. Spawn Sonnet subagent via `Agent(model: "sonnet")` with `.claude/reference/spec-verification.md` as the procedure and the in-scope sources + specs + code files as inputs. Output: `verification_findings/fidelity_audit[_chN].md` + `verification_findings/field_consumption_audit[_chN].md`.

**Fix loop:** Same shape as Phase 2 grill. Every [D]/[F]/[M]/[I]/[T] finding = fix before Phase 3. Max 5 rounds. After round 5 with unresolved non-INFO findings: write `FIDELITY_BLOCKED` + remaining issues to CT, surface to user. Do NOT proceed to the verification squad with known fidelity gaps.

## Phase 3: Verification Squad

Invoke `/verify` on all `/perfect` work product. Follow the /verify skill procedure EXACTLY — all steps, all agents, all rounds. Do not abbreviate or substitute.

Key alignment points (duplicated here to prevent bypass):
- ALL 5 agents, every invocation. No filtering — the smart-filtering rules in `/verify` do NOT apply here. Partial run = INVALID.
- Write `manifest.json` before launching. Launch all 5 in ONE message.
- Fix ALL findings above INFO before next round — not just FAILs. FAIL, WARN, HIGH, MEDIUM, LOW = fix. Only INFO deferred.
- NEVER self-certify verification results. After fixes, always launch a fresh squad.
- Re-run ONLY failed/warned agent(s) in follow-up rounds. Fresh open-ended scope, not "verify fix X."
- Max 5 rounds. After round 5: write `VERIFICATION_BLOCKED` + remaining issues to CT, present to user.

## Phase 4: Prove Correctness — user gate

DELEGATE two agents: behavioral-change-map + test-coverage-audit. Opus combines -> present plain English: what changed, what's tested, what's not.

### Verification Summary Table

Include a summary table of all verification rounds run during this `/4` session (Phase 2 grill + Phase 3 squad). This gives the developer a quick audit trail confirming verification was thorough. Format:

```markdown
### Verification Rounds

| Round | Type | Agents | Result | Fixes applied |
|-------|------|--------|--------|---------------|
| Grill R1 | /grill | — | Clean | 0 |
| Squad R1 | /verify | 5/5 (mech, adv, comp, dep, cold) | 4 PASS, 1 WARN | 1 (double-hedge) |
| Squad R2 | /verify (adv only) | 1/1 | PASS | 0 |
```

- One row per round (grill rounds + squad rounds).
- **Agents** column: count launched / count expected. For squad rounds, list agent names in parentheses. For re-runs, list only the re-run agents.
- **Result** column: per-agent verdicts summarized (e.g., "4 PASS, 1 WARN").
- **Fixes applied** column: count of fixes made before the next round.
- Table goes in the Phase 4 presentation to the user, after the behavioral proof and before announcing `/4` complete.

## Rules

1. Evaluate before acting. Never simplify what you'll scrap.
2. Sonnet runs mechanical analysis. Opus reviews and fixes.
3. Finish migrations completely.
4. Tests earn their place. Delete bad tests.
5. Plain English proof, not code dump.
6. User gates: Step 3, Step 5a, Phase 4.
7. No scope creep.
8. Subsystem inventory in flat file, not memory.

After Phase 4 user gate: announce `/4` complete, ready for `/5` (`/finalize`).
