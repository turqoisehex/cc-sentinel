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

## Phase 2.5 Resolver: Type-Aware `scopeContext`

**Run before the Phase 2.5 engine gate.** Determines the touched data-model TYPE set for this sprint.

### Session-start baseline

"This sprint" = `git diff <session-start-commit> HEAD` (the session-start commit hash is recorded in the channel CT). When reading the commit hash from CT, MUST trim CRLF before passing to git: `git diff "$(tr -d '\r' <<< "$HASH")"`. All git/grep operations execute via the Bash tool (Git Bash on Windows / bash on macOS+Linux) — POSIX/bash syntax only, NOT PowerShell.

### Touched TYPE resolution (PRIMARY + SECONDARY signals)

**PRIMARY — class body changed:** a model/Drift-table/enum class whose class body changed in the baseline diff (field added/removed/renamed, type changed, enum value changed). Include.

**SECONDARY — fidelity-relevant consumer change only (narrow):** a consumer whose change is fidelity-relevant (adds/changes/removes a `??`/`||` default, clamp, transform, or validation applied to `M`'s value; OR substitutes which field of `M` it reads; OR deletes its only read of a field of `M`). A plain read or pass-through rename is NOT fidelity-relevant. Do NOT include every type constructed/read in a touched file.

**SECONDARY — value-bearing literal change:** a type `M` whose instance-level literal value changed in the diff (e.g., a seeder value, a const field, a default parameter value changed in `M`'s body) — even if the class body structure did not change. Include: the literal value on an instance of `M` changed means the field-consumption chain for that literal must be re-audited.

**SECONDARY — governing SOURCE/spec changed:** a type `M` whose primary source document or governing spec was edited in this session's diff. Even if `M`'s code class body is unchanged, a source/spec change means the spec-to-code alignment must be re-verified.

**Provenance (mandatory on every run, including zero-model):** emit one line naming: baseline scanned, changed files list, types mapped, AND types evaluated-but-excluded (with exclusion reason — e.g. "excluded: ProviderX (read-only pass-through)"). Without provenance the run cannot be audited.

### Per-type Phase-0 provenance record

For each touched type emit: `{ type, sourceMaterialPaths[], governingSpecPath }`.

Resolution order: CT plan/spec pointer → `docs/**` scan naming the type → in-scope sprint spec.

**Unresolved source or spec:** this is ONE run-level scoping error, not N per-type `[M]` survivors. Route to `FIDELITY_BLOCKED (unresolved source/spec)`. This type may NOT reach CLEAN.

### N-cap check

Read `fanoutTypeCap` from `workflows-config.md` alongside `K`/`maxRounds`/`budget` (apply `tr -d '\r'` before integer comparison to handle CRLF on Windows). If touched-TYPE count > `fanoutTypeCap`, emit:

```
FIDELITY_BLOCKED: type-cap exceeded
Blocked types (written to CT): <list of type names + reason per type>.
Phase 3 is GATED. Operator must resolve or record an explicit override in CT before Phase 3 proceeds.
Override path: narrow type set via CT annotation | raise fanoutTypeCap | authorise scoped subset.
```

HALT Phase 2.5 before invoking the engine. Phase 3 is gated. Never silently fan out to N > cap.

### Zero-model guard

If the resolved TYPE set is EMPTY, emit the non-opaque banner and skip Phase 2.5 (proceed directly to Phase 3):

```
/4 fidelity: no-model N/A — no touched data-model types this sprint. Resolver scanned <baseline>; changed files: <list>; none mapped to a model TYPE
```

This is NOT a CLEAN terminal, NOT a fallback. Only Phase 2.5 is skipped.

### PARENT fix-application grounding (no-skimming rule)

Before the PARENT treats a finding as resolved after applying a fix, the PARENT MUST ground the fix in a grep/Read call confirming the cited field, method, or file path actually changed as intended — the PARENT cannot rely on "I applied the edit" as proof. Required for every PARENT fix application:

1. Re-read the governing source/spec requirement for `M` (from the Phase-0 provenance record — `governingSpecPath`).
2. grep/Read-confirm the fix landed in the target file at the expected location.
3. Only then may the finding be considered resolved. A fix that lands but does not satisfy the source/spec requirement is NOT resolved — the engine must re-evaluate it in the next round.

### Sequential per-type call shape

Run ONE engine invocation per type. Runs are SEQUENTIAL. Each computes its own `scopeHash` at its start (capturing prior types' fixes). `budgetGuard` is SHARED across ALL type runs + all PARENT re-invocations for the whole `/4`. After all initial per-type runs, the fixed-point pass RE-RESOLVES the TYPE set against the final `scopeHash` — any type newly touched by loop fixes is added and audited (cap: 2 retries; persistent churn → `CAPPED`/`FIDELITY_BLOCKED`).

### Aggregate CLEAN invariants (checked before Phase 3)

Before Phase 3 may proceed, ALL of the following must hold:
1. **No unresolved disagreements:** `disagreements` from any per-type run must be routed — either PARENT-resolved with grounded fix evidence, or surfaced to the operator as `FIDELITY_BLOCKED (unresolved-disagreement)`. Unresolved disagreements gate Phase 3.
2. **No never-started types:** if a type was in the capped set (cap exceeded or budget exhausted before its run could start), it must be handled: either the operator narrows the type set, raises `fanoutTypeCap`, or annotates the CT with an explicit scoped override. Phase 3 is gated until resolved.
3. **Staleness re-check before Phase 3 entry:** After all per-type runs complete, re-validate that `scopeHash` has not changed since the last CLEAN type was audited. If `scopeHash` changed (new commit, file change), re-run any types whose CLEAN was recorded against a prior `scopeHash`. Retry bound: 2 re-checks; if `scopeHash` keeps changing, emit `FIDELITY_BLOCKED (persistent-scope-churn)` and surface to operator.

## Phase 2.5: Fidelity/Field-Consumption Audit (MANDATORY — engine-gated)

**Phase order:** Phase 2 (manual /grill, non-fidelity) MUST complete BEFORE Phase 2.5. Phase 2.5 runs BEFORE Phase 3.

### Gate route

Read `~/.claude/reference/workflows-config.md` (or project-local `.claude/reference/workflows-config.md` — CWD-relative). Parse under schema discipline. If `"/4"` is in `enabled-phases` AND the Workflow tool is available AND the resolver's touched-TYPE set is non-empty:

→ **Engine path:** run the `/4` finderSet fan-out (per `adversarial-loop.md ## 3b`) via the adversarial-loop engine (`adversarial-loop.md ## 4` gate), once per touched type, sequentially.

Else if touched-TYPE set is EMPTY:
→ **Zero-model N/A:** emit the banner (see below), skip Phase 2.5, proceed to Phase 3.

Else:
- `config OFF` (`workflows_enabled: false` / file absent / `"/4"` not in `enabled-phases`):
  → **Fallback** (reason: config OFF) — loud banner + today's Sonnet-delegated Phase 2.5 (manual `spec-verification.md` procedure). This is the `/4`-specific fallback — the D2 guarantee.
- Workflow tool absent:
  → **Fallback** (reason: tool absent) — same Sonnet-delegated Phase 2.5 fallback as above.

### Zero-model banner (non-opaque — operator can distinguish heuristic miss from genuine no-model sprint)

```
/4 fidelity: no-model N/A — no touched data-model types this sprint. Resolver scanned <baseline>; changed files: <list>; none mapped to a model TYPE
```

Emit resolver provenance (baseline scanned, changed files, types evaluated-but-excluded with reasons). Proceed to Phase 3. NOT a CLEAN terminal, NOT the fallback, NOT a finding.

### Engine path: per-type aggregation layer (in SKILL, on top of ## 5)

For each touched type `M` (resolved by the Phase 2.5 resolver, Task 1):

1. PARENT computes `scopeHash` for this type run.
2. PARENT invokes ENGINE with the `/4` finderSet (`## 3b`) and `scopeContext` scoped to `M`.
3. ENGINE returns `{ found, disagreements, pending, terminal, journalArtifact, scopeHash }`.
4. Switch on `terminal`:
   - `CLEAN`: record type `M` as CLEAN at this `scopeHash`. Proceed to next type.
   - `FINDINGS`: PARENT applies fixes (no commit), re-invokes ENGINE fresh for `M`. Loop until CLEAN or CAPPED.
   - `CAPPED`: emit `FIDELITY_BLOCKED` banner for `M` (sub-cause: budget CAPPED / circuit-breaker / max-rounds-no-convergence / persistent-churn). Gate Phase 3.
5. If any type's SOURCE or spec was unresolved at resolver time: emit `FIDELITY_BLOCKED (unresolved source/spec)`. Gate Phase 3.

**`budgetGuard` is SHARED** across all N type runs + all PARENT re-invocations. One `/4` budget, not per-type.

**PARENT phantom-citation rejection:** Every LLM-lane claim assembled into a final artifact MUST be grep/Read-grounded by the PARENT before assembly. If a lane emits a citation the PARENT cannot confirm in a grep/Read, it is flagged as a phantom finding, treated as live, and does NOT ship in the artifact.

### `FIDELITY_BLOCKED` banner (emitted by RESOLVER for cap-exceeded; by PARENT SKILL for per-type CAPPED)

```
FIDELITY_BLOCKED: <sub-cause: type-cap exceeded | unresolved source/spec | budget CAPPED | circuit-breaker>
Blocked types (written to CT): <list of type names + reason per type>.
Phase 3 is GATED. Operator must resolve or record an explicit override in CT before Phase 3 proceeds.
Override path: <narrow type set via CT annotation | raise fanoutTypeCap | authorise scoped subset | resolve source/spec pointer>.
```

`FIDELITY_BLOCKED` GATES Phase 3 — Phase 3 does not proceed until the operator resolves or explicitly overrides and records to CT.

### Artifact assembly (`assert_artifacts_written_after_scopehash_revalidation`)

**Named gate-check (required):** The two audit artifacts (`fidelity_audit[_chN].md` + `field_consumption_audit[_chN].md`) are written ONLY after the FINAL `scopeHash` re-validation completes AND the fixed-point TYPE-set re-resolution is stable. Any code path that writes these artifacts before the final re-validation MUST NOT be reachable.

**Freshness ordering:** After all initial per-type runs, the PARENT:
1. Re-resolves the touched-TYPE SET against the final `scopeHash` (cap: 2 retries; persistent churn → `CAPPED`/`FIDELITY_BLOCKED`).
2. Re-validates every earlier-CLEAN type at the final `scopeHash` (any no-longer-holds type re-runs, re-emitting full inventory).
3. Only when BOTH set-membership and content are stable at the SAME final `scopeHash` → assemble artifacts from: (a) lane emitted inventories (per `## 3b` schema), (b) resolver Phase-0 provenance, (c) shared-field merge.
4. Stamp artifacts with `runId` + final `scopeHash`.
5. Write to `verification_findings/fidelity_audit[_chN].md` + `verification_findings/field_consumption_audit[_chN].md`.

**Shared-field merge:** `[C]` if consumed by ANY consumer, `[T]` if only test consumers across all, `[D]` only if dead across ALL types.

**Audit-pointer rule (MANDATORY in Sonnet dispatch prompt):** Both artifacts are durable — cite code via symbolic addresses (`file.ext :: ModelDefinition(id: 'x').field`), NOT line numbers. Do not emit `file:LN`, `L\d+-L\d+`, `line N`, or `~LN` forms.

### Fallback (when engine path not taken)

```
FALLBACK single-pass — reason: <config OFF | config PARSE-FAIL | tool absent | materialization ERRORED>
```

The `config OFF` reason covers all non-error cases where the engine is not entered: `workflows_enabled: false`, file absent, or `"/4"` not in `enabled-phases`. Per the canonical gate order in `adversarial-loop.md ## 4.3`, `config PARSE-FAIL` is a distinct reason (file present, required key malformed) and must remain in the banner vocabulary — it is NOT collapsed into `config OFF`.

Execute today's Sonnet-delegated `spec-verification.md` procedure (the D2 guarantee). This is the `/4`-specific fallback — NOT the `## 4.4` "today's Step 9.5" (which is `/5`-specific).

### Monitoring-script note

A monitoring script parsing `/4` output must handle all four distinct banner prefixes:
1. `PROVE-GATE:` (engine path)
2. `FALLBACK single-pass —` (fallback path)
3. `/4 fidelity:` (zero-model N/A)
4. `FIDELITY_BLOCKED:` (cap-exceeded / unresolved-source / per-type CAPPED)

A script that only parses `PROVE-GATE:` and `FALLBACK single-pass —` will silently drop all `FIDELITY_BLOCKED:` events.

## Phase 3: Verification Squad

Invoke `/verify` on all `/perfect` work product. Follow the /verify skill procedure EXACTLY — all steps, all agents, all rounds. Do not abbreviate or substitute.

Key alignment points (duplicated here to prevent bypass):
- ALL 5 agents, every invocation. No filtering. Partial run = INVALID.
- **Audit-pointer rule:** when any squad agent proposes a fix to a durable artifact (spec, extraction doc, fidelity/field-consumption audit, SC, CIP, CT cold-start), the fix MUST specify a symbolic address per `~/.claude/reference/audit-pointer-rules.md`, not a new line number. Two consecutive rounds flagging line-ref staleness in the same artifact = next fix strips line numbers from that artifact entirely.
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
