---
name: prove
description: "Report-only completion-proof. Runs the shared /5 9-lens adversarial finderSet over the current scope and surfaces survivors read-only (never fixes). Thin alias to /5's finderSet. Also: /prove --selftest for the in-harness materialization smoke-test."
---

# /prove — Completion Proof (report-only)

**Trigger:** `/prove` (alias of /5's finderSet, run standalone) · `/prove --selftest`

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Full rules: `.claude/reference/channel-routing.md`.

The engine + gate + finderSet live in `.claude/reference/adversarial-loop.md`; the
opt-in schema in `.claude/reference/workflows-config.md`. This skill is the thin spine.

---

## Standalone mode

### Scope resolution

Resolve scope identically to `/5`: CTs (channeled `CURRENT_TASK_chN.md` or shared `CURRENT_TASK.md`) + "diff since session start" (`git diff` of the working tree relative to the last commit at session open) + the plan pointer embedded in the channel CT. "The plan" = the plan file the CT references.

This resolver is **shared with `/5`** — both skills call the same procedure. The build is DRY: no separate `/prove`-only resolution logic.

### MD-15 — No-CT pre-flight error

**MD-15:** When no CT resolves and no plan pointer is found, emit a PRE-FLIGHT ERROR and stop:

```
PROVE ERROR: no scope resolved. No CURRENT_TASK_chN.md or CURRENT_TASK.md found,
and no plan pointer was located. An empty scope finds nothing and would produce a
false CLEAN. Provide a CT or plan pointer before running /prove.
```

Do NOT run the engine on an empty scope. (Exception: `--selftest` mode uses a synthetic fixture and explicitly bypasses this check — see below.)

### MD-16 — No-change short-circuit ("run once")

**MD-16:** Before invoking the gate, compute the `scopeHash` (content digest over the resolved scope snapshot — see `.claude/reference/adversarial-loop.md` §6). If a prior `/prove` run-journal exists for this session with the SAME `scopeHash` AND that run reached `CLEAN`:

```
PROVE: still dry — no changes since HH:MM. (scopeHash unchanged)
To re-run, change a tracked file or pass --force.
```

Stop. The loop lives INSIDE one invocation — run `/prove` once, not five times.

### MD-17 — Mid-sprint pre-flight warn

**MD-17:** Before invoking the gate, inspect the resolved CT for open tasks (unchecked `- [ ]` items with no completion evidence). If open tasks are found:

```
PROVE WARN: this sprint looks mid-build — N open task(s) detected. Lenses 1/2/4
will correctly flag every unfinished task and exhaust maxRounds.
Run anyway? [y/N]
```

Wait for operator confirmation. Default (no input / N) = abort. Y = proceed. This is informational — the operator makes the call.

### MD-18 — Report-only; terminal mapping

**MD-18:** `/prove` is REPORT-ONLY. It NEVER fixes, patches, or re-invokes with corrections.

Engine → operator terminal mapping:

| Engine terminal | `/prove` operator terminal | Meaning |
|---|---|---|
| `CLEAN` | `CLEAN` | No survivors; scope is dry |
| `FINDINGS` | `GAPS_FOUND` | Survivors listed read-only; operator must act separately |
| `CAPPED` | `CAPPED` | Budget/round cap hit; parked items listed |

On `GAPS_FOUND`: surface the survivor list (blocking-first, tagged with originating lens + corroboration count + round + one-line refute-survived note per MD-4) and stop. Never fix. Never call `/5`. The operator decides next steps.

On `CAPPED`: always list parked items (never silent budget stop).

### MD-19 — Never touches the proof sentinel

**MD-19:** `/prove` NEVER creates, reads, or clears the proof-sentinel file. That lifecycle belongs solely to `/5`. `/prove` writes only its own separate jsonl audit entry (path: same `subagents/workflows/<runId>/journal.jsonl` family; sentinel path excluded from lens-9's git-check per `adversarial-loop.md` §2.2).

### MD-20 — Loud degradation

**MD-20:** The operator invoked `/prove` deliberately for assurance. Every fallback must be loud:

```
FALLBACK single-pass — reason: <config OFF | config PARSE-FAIL | tool absent | materialization ERRORED>
```

A silent fallback is a bug. A degraded run that does not banner its reason is a bug. When degraded, the single-pass fallback (today's Step 9.5 audit — the D2 guarantee) executes and its output is presented in full. Never silently succeed on a reduced scope.

---

## `--selftest` mode (R4 materialization contract)

**Trigger:** `/prove --selftest`

**Purpose:** In-harness proof that a thin skill can MATERIALIZE the workflow from the prose proc-doc and execute a real fan-out. This is the R4 PASS contract (§10.1 MD-22).

**Scope:** `--selftest` uses a SYNTHETIC FIXTURE scope — a small well-defined set of fabricated finding-stubs with known coverage gaps. This is the documented exception to the MD-15 no-CT pre-flight error: `--selftest` bypasses the no-CT pre-flight precisely to exercise materialization independently of any real CT.

### PASS contract

`--selftest` PASSES only if ALL of the following hold:

**(a) Probe resolves positively:** `ToolSearch select:Workflow` returns a schema for the Workflow tool. If the probe returns empty/error → FAIL immediately.

```
SELFTEST FAIL: ToolSearch select:Workflow returned no schema. Workflow tool unavailable.
```

**(b) Materialization succeeds:** The §5 gate (`.claude/reference/adversarial-loop.md` heading `## 4`) reaches launch WITHOUT taking any fallback branch. Any of the four fallback banners is a FAIL. A run that exits via ANY fallback is a selftest FAIL, never a caveated pass.

`--selftest` runs BOTH a `/5`-mode assertion sub-block AND a `/4`-mode assertion sub-block in ONE invocation — each keyed to its active finderSet declaration. No mode flag required.

#### `/5`-mode sub-block (9 lenses, deterministic `{6,8,9}`, 3 receipts)

The path banner MUST read:
```
PROVE-GATE: engine path (9 lenses, K=2, max 5)
```

Liveness (journal): `llmFanOutAgentIds[]` count = 6 (lanes 1,2,3,4,5,7); `deterministicReceiptIds[]` count = 3 (lanes 6, 8, 9).

**FILE-TEXT GREP step (b-prose):** grep the deployed `adversarial-loop.md ## 1.2` section for the expected post-edit string:
```bash
grep "all lenses in the active finderSet" ~/.claude/reference/adversarial-loop.md
```
Expected: 1+ match. AND assert the old literal is ABSENT:
```bash
grep "all 9 lenses" ~/.claude/reference/adversarial-loop.md
```
Expected: 0 matches. A builder who updated the receipt struct or count but neglected the prose edit is caught by this assertion.

Stale-receipt rejection: `{6, 8, 9}` set — run one round, mutate scope (H1→H2), assert all three receipts rejected and lenses re-run.

Generalized invalidation path: assert `## 6.3`/`## 6.4` invalidates EXACTLY the active finderSet's declared deterministic lanes (not hardcoded `{6,8,9}`).

#### `/4`-mode sub-block (7 lenses, deterministic `{6}`, 1 receipt)

Use the `/4` finderSet (`## 3b`) with a synthetic fixture scope (one fabricated touched TYPE with known field stubs — same bypass as the standalone --selftest scope, explicitly exempt from MD-15 no-CT pre-flight).

**(i) BANNER assertion:** the `/4` banner-string emits `7 lenses`:
```bash
# Assert banner shows "7 lenses" not "9 lenses"
# (Run engine with /4 finderSet active; read banner from stdout)
# Expected: PROVE-GATE: engine path (7 lenses, K=2, max 5)
```
Failure: banner shows "9 lenses" = residual hardcoded constant.

**(ii) JOURNAL-LIVENESS assertion (separate from banner):**
- `llmFanOutAgentIds[]` count = 6 (lanes 1,2,3,4,5,7)
- `deterministicReceiptIds[]` count = 1 (lane 6 only)

**(iii) `## 3b` existence + 7 lenses named in `## 3b`:**
```bash
grep "## 3b" ~/.claude/reference/adversarial-loop.md
# Expected: 1 match (the section heading)

# Scope Lens count check to ## 3b section only (grep -c "Lens [1-7]" over the full file
# would already pass from the /5 finderSet's Lens 1-9 headings)
awk '/^## 3b\./{found=1} found && /^## [^3]/{exit} found{print}' \
  ~/.claude/reference/adversarial-loop.md | grep -c "Lens [1-7]"
# Expected: 7 (exactly 7 lens headings in ## 3b)
```

**(iv) Generalized liveness resolves for BOTH finderSets:**
- `/5`: 6 agent-ids + 3 receipts (from `/5`-mode sub-block above)
- `/4`: 6 agent-ids + 1 receipt (from the `/4`-mode sub-block)
- `/3`: 3 agent-ids + 2 receipts (from the `/3`-mode sub-block below)

**(v) Stale-receipt rejection for 1-element deterministic set `{6}`:**
Run one round with `/4` finderSet active. Mutate scope (H1→H2). Assert: lane-6 receipt REJECTED, lane 6 re-runs, `dryStreak` NOT incremented.
Failure: 1-element set treated differently from 3-element set = partial generalization bug.

**(vi) Generalized `## 6.3`/`## 6.4` for 1-element set:**
Assert the invalidation path fires for `{6}` (the active finderSet's deterministic lanes), NOT for hardcoded `{6,8,9}`. A partial generalization that left `{6,8,9}` in the invalidation path MUST FAIL this guard.

**(vii) FILE-TEXT GREP — `## 2` fan-out-cap prose:**
```bash
grep "≤ the active finderSet" ~/.claude/reference/adversarial-loop.md
# Expected: 1+ match in ## 2 region

grep "≤9 lenses" ~/.claude/reference/adversarial-loop.md
# Expected: 0 matches
```

**(viii) FILE-TEXT GREP — `## 2.2` jsonl `"lensCount"`:**
```bash
grep '"lensCount": <active' ~/.claude/reference/adversarial-loop.md
# Expected: 1 match (the generalized form)

grep '"lensCount": 9' ~/.claude/reference/adversarial-loop.md
# Expected: 0 matches
```

**(ix) FILE-TEXT GREP — `## 2.2` liveness prose paragraph:**
```bash
grep "all lenses in the active finderSet accounted-for" ~/.claude/reference/adversarial-loop.md
# Expected: 1+ match in ## 2.2 region

grep -E "all-9.*lensStatus|all 9 lenses accounted" ~/.claude/reference/adversarial-loop.md
# Expected: 0 matches outside ## 3 (the /5 finderSet section itself)
```
Catches a builder who fixes `## 1.2` liveness prose and the `## 2.2` jsonl block but leaves the standalone `## 2.2` liveness paragraph hardcoded.

#### `/3`-mode sub-block (5 lenses, deterministic `{4,5}`, 2 receipts)

Use the `/3` finderSet (`## 3c`) with a synthetic build-pipeline fixture (≥2 fabricated plan tasks with known produce/verify handoff stubs; for the same-file case, two tasks that both edit the SAME fixture file). The per-task serial loop is SKILL-orchestrated, so the engine JOURNAL cannot observe "serialized produce + read-only verify" or "checkpoint-after-produce" — those are SKILL-observable (file presence + pipeline-log `seq` ordering), NOT engine-journal assertions.

**Selftest-activation rule (resolves the enable-gate deadlock — self-enable then verified-revert):** the engine path is config-OFF unless `"/3"` is in `enabled-phases`, but the HARD-BLOCK enable gate (obligation 6 / Step 7.7) forbids adding `"/3"` to the LIVE `enabled-phases` until this selftest PASSES — a circular deadlock if the selftest needs the engine path. The `/3`-mode selftest therefore **temporarily self-enables `/3` for the duration of the run, then REVERTS** (mirroring the `/4`-mode activation, made self-reverting): at `/3`-mode start the selftest sets `workflows_enabled: true` AND adds `"/3"` to `enabled-phases` in the config it reads (a scoped, in-run enablement — NOT the live operator enablement obligation 6 gates), runs the assertions on the engine path, then **REVERTS both** (removes `"/3"` from `enabled-phases` and restores the prior `workflows_enabled` value). **The revert MUST be verified before any commit** — the selftest re-reads the config after revert and asserts `"/3"` is absent from `enabled-phases` and `workflows_enabled` is restored; a non-reverted config is a selftest FAIL (leaving `/3` live would bypass the obligation-6 hard-block). This self-contained temporary-enable-then-verified-revert is what lets the selftest reach the engine path WITHOUT the operator first performing the live enablement obligation 6 forbids until the selftest passes.

**Engine-journal assertions (the CHECKPOINT 5-lens engine run — journal-observable):**

**(i) BANNER assertion:** the checkpoint banner emits `PROVE-GATE: … (5 lenses …)` (catches a residual hardcoded "9"/"7"; the `PROVE-GATE:` prefix is the engine's fixed string, only the count is finderSet-relative):
```bash
# Expected: PROVE-GATE: engine path (5 lenses, K=2, max 5)
```
Failure: banner shows "9 lenses" or "7 lenses" = residual hardcoded constant.

**(ii) JOURNAL-LIVENESS assertion (separate from banner):** checkpoint journal liveness resolves for the 5-lens `/3` set — `llmFanOutAgentIds[]` count = 3 (lanes 1,2,3) AND `deterministicReceiptIds[]` count = 2 (lanes 4,5). A valid `/3` checkpoint run = 3 agent ids + 2 receipts (NOT "≥5 agent ids").

**(iii) `## 3c` existence + 5 lenses named in `## 3c` (FILE-TEXT GREP):**
```bash
grep "## 3c" ~/.claude/reference/adversarial-loop.md
# Expected: 1 match (the section heading)
# Anchor the lens-heading match at start-of-line (^**Lens) so the indented `- **Lens 4 (…`/`- **Lens 5 (…`
# bullets in the empty-candidate-behavior subsection are NOT miscounted as lens headings (they are bullets,
# not headings — an unanchored `**Lens [1-5]` would count 7, not 5).
awk '/^## 3c\./{found=1} found && /^## [^3]/{exit} found{print}' \
  ~/.claude/reference/adversarial-loop.md | grep -c "^\*\*Lens [1-5]"
# Expected: 5 (exactly 5 lens headings in ## 3c)
```

**(iv) Stale-receipt REJECTION for the 2-element deterministic set `{4,5}`** (RECEIPT-INVALIDATION + re-run-trigger; NOT a full lane-4 throwaway-worktree mutate-run — the throwaway worktree is used only inside lens 4's test-honesty check, not as the mutation vehicle here): run one checkpoint round (receipts signed at PRIMARY-tree `scopeHash` H1), then mutate a **PRIMARY-TREE in-scope file** (the mutation vehicle is the primary tree so `scopeHash` changes to H2 ≠ H1). Assert BOTH lane-4 (`4/test-honesty`) and lane-5 (`5/consumer-preflight`) receipts are REJECTED and re-run (NOT carried forward against H2 — dry is NOT credited against stale receipts; `## 6.3`/`## 6.4` for a 2-element set, a new cardinality between `/4`'s 1 and `/5`'s 3). After the assertion, **revert the primary-tree mutation** (the mutation is a test vehicle; leaving it would corrupt subsequent build steps). This 2-element-set assertion is the explicit gate that the `{4,5}` cardinality is selftest-demonstrated before `/3` goes live.

**Skill-observable assertions (the per-task SERIAL produce→verify loop — file-presence / pipeline-log ordering, NOT engine-journal):**

**(v) produce→verify file-handoff occurred per task, in serial order:** the fixture has ≥2 tasks; assert one **result-FILE** (`<taskId>.result.json`) + one **verdict-FILE** (`<taskId>.verdict.json`) exist per fixture task under `verification_findings/build_pipeline[_chN]/`, and the skill pipeline-log shows entries in `seq` order — for each task `PRODUCE` before `VERIFY`, and task N's `VERIFY` before task N+1's `PRODUCE` (the serial single-writer ordering). Ordering is read from the monotonic `seq` counter, NOT file-mtime. A no-op / silent fallback produces no result/verdict files and no pipeline-log entries and fails this.

**(vi) checkpoint engine run fires AFTER all per-task VERIFY entries:** the skill writes a `{ stage: CHECKPOINT_ENGINE_START, seq }` entry to the pipeline-log when it fires the checkpoint engine; assert ENTIRELY WITHIN the pipeline-log that every per-task `VERIFY` entry's `seq` is **less than** the `CHECKPOINT_ENGINE_START` `seq`. This is a single-log `seq` ordering check, NOT a cross-log comparison with the engine journal (the journal has no comparable global `seq`; it separately proves the checkpoint RAN via (ii)/(iii), while the pipeline-log proves the ORDER). Catches an implementer who wired the engine (or LLM lenses 1–3) as a per-task interrupt instead of a single skill-fired checkpoint pass (violating WIP §7 and the §3.4 cadence division).

**(vii) `scopeHashChecked`-REJECTION (parent-enforcement, deterministic fixture assertion):** As part of the fixture run, write a verdict-FILE for a synthetic task with a deliberately MISMATCHED `scopeHashChecked` — a value that does NOT match the digest of the task's actual `filesWritten[]`. The fixture then asserts that the parent:
- (a) detects the mismatch (logs or emits a rejection signal, not a silent accept),
- (b) does NOT advance to PRODUCE(N+1) on the basis of the rejected verdict,
- (c) re-runs VERIFY(N) against the actual tree and replaces the rejected verdict-FILE with a fresh one whose `scopeHashChecked` matches.

Implement this as a checkable fixture step: the synthetic task writes a single known file; the fixture computes the expected `scopeHashChecked` via the same content-digest function the engine uses (`## 6`), then writes a verdict-FILE with a deliberately different value (e.g. the hash of an empty string). The parent's rejection is observable as: the original rejected verdict-FILE is replaced (or the pipeline-log records a re-VERIFY entry for the task); the final accepted verdict-FILE carries the correct `scopeHashChecked`. This is a deterministic, mechanizable assertion — NOT prose-only. *Prose-instruction-level only (not a deterministic fixture assertion):* phantom-citation-rejection (the parent rejects a finding whose citation cannot be grounded, both tiers) and the acceptance-criteria empty→description fallback are documented as parent/skill instructions and checked by review — these are not mechanizable in a static fixture.

**(viii) task-local-diff baseline, same-file/two-task case:** the fixture has two tasks that BOTH edit the SAME file; the parent records a baseline ref via **`git stash create`** (a working-tree snapshot object id — NOT `git write-tree`, which serializes the index only) of the working tree at PRODUCE(N) start and persists it as `baselineRef`. Assert that VERIFY(N) — computing the path-scoped diff of the post-PRODUCE(N) tree against THAT recorded baseline — sees ONLY task N's hunk on the shared file, NOT task N−1's hunk (which a cumulative `git diff HEAD` would conflate). ALSO assert the FULL-diff under-declaration check fires: seed task N to silently touch an UNDECLARED file (absent from `filesWritten[]`) and assert VERIFY(N) FAILs it via the full working-tree diff (a path-scoped diff would miss it). Proves both the single pinned task-local baseline mechanism (path-scoped, shared-file isolation) AND the full-diff under-declaration catch; a builder who used cumulative `HEAD`, `git write-tree`, or a path-scoped diff for under-declaration fails this.

**(ix) design-gap → RETURN-TO-`/2` halt:** the fixture seeds a producer **deferral** — a synthetic task whose result-FILE carries a non-empty `deferrals[]` (a design decision the `/2` plan did not resolve). Assert that the per-task verifier emits `verdict: RETURN_TO_2` (NOT PASS, NOT a benign WARN-continue), that the `/3` loop **HALTS** (does NOT advance to the next PRODUCE and the single `/3` commit does NOT fire), and that the parent **writes the `## Return to /2 — design-decision-gap` note to the CT**. This proves the strictly-execution discipline: a `/2`-incompleteness halts-and-returns rather than being conservative-defaulted or parked for `/3`-end approval. A builder who lets `/3` take a default and continue (the removed pre-RQ-3 behavior) fails this.

**(x) `/5`/`/4`-regression guard:** re-run the existing `/5`-mode (9 lenses, 6 agent-ids + 3 receipts) and `/4`-mode (7 lenses, 6 agent-ids + 1 receipt) blocks — adding the `/3` finderSet must not perturb them (each per-mode block remains independently executable; the global PASS contract now spans THREE modes — `/5`, `/4`, `/3`).

**(c) Real LLM fan-out executes:** At least one round of real LLM fan-out executes with the expected lens agents reporting. A no-op, a mock, or a zero-agent round is a FAIL.

**(d) Liveness assertion (journal):** Read the on-disk run-journal at the harness-observed path (`subagents/workflows/<runId>/journal.jsonl`). Assert all lenses in the ACTIVE finderSet's `lensStatus[]` are accounted-for per round: agent IDs for the LLM lanes, signed receipts for the active finderSet's declared deterministic lanes. Absent journal = FAIL. Any missing `lensStatus` entry = FAIL. The count is finderSet-declared (9 for `/5`-mode; 7 for `/4`-mode) — NOT a hardcoded constant.

### Additional deterministic in-harness assertions

These assertions run as part of `--selftest` and point at the relevant proc-doc sections.

#### Stale-receipt assertion

**References:** `adversarial-loop.md` §6 (scopeHash lifecycle + stale-receipt rejection)

**Procedure:**

(a) Run one engine round using the synthetic fixture scope, producing a signed deterministic receipt for a carried-forward lens from the active finderSet's declared deterministic lanes at `scopeHash` H1.

(b) Mutate an in-scope file so the content digest changes to H2 (H2 ≠ H1) — simulating a parent fix, a cross-channel commit, or an untracked/generated file change landing mid-run.

(c) Assert that the next round-boundary **REJECTS** the H1 receipt and re-runs the lens. Specifically: the receipt does NOT count as coverage, `dryStreak` does NOT increment, and the lens must re-run before dry can be credited against H2.

**RED/GREEN contract:** Before the `adversarial-loop.md` §6 re-validation prose exists, no implementing skill can satisfy "stale receipt rejected" → selftest FAIL. After the prose lands and a thin skill executes the §6 procedure → selftest PASS.

**This assertion is the ONLY deterministic guard on `scopeHash` correctness.** The prose in `adversarial-loop.md` §6.1–6.4 specifies the contract; this fixture proves the executing skill satisfies it in-harness.

**Failure condition:** stale receipt accepted without rejection (H1 receipt counts as coverage for the H2 scope → false dry).

#### Partial-journal detection assertion

**References:** `adversarial-loop.md` §8 (compaction / resume handling; atomic-journaling + only-complete-rounds invariant)

**Procedure:**

(a) Write a synthetic partial journal into the harness-observed run-journal path (`subagents/workflows/<runId>/journal.jsonl`):
- Round 1 entry: a **complete** record — all required fields present (`round`, `lensStatus[]` with all lenses in the active finderSet, `llmFanOutAgentIds[]`, `deterministicReceiptIds[]`, `coverageReceipt`, `scopeHash`, `pending`, `terminal: null`), written atomically (no torn line).
- Round 2 entry: a **half-written / torn** record — simulate a mid-round session kill by truncating the journal after N lenses (N < the active finderSet's lens count), leaving an incomplete `lensStatus[]` and no `coverageReceipt` or `terminal` field.

(b) Invoke the gate's cross-session detection path (as if a new session opened against this working tree with a prior run journal present).

(c) Assert ALL of the following hold:

1. **Detection:** The gate DETECTS the incomplete run — it does NOT treat the torn entry as a valid round.
2. **Round reported:** The gate announces the incomplete run and the round it reached — e.g., `Prior run <runId> incomplete at round 2 — restarting gate fresh.`
3. **Restart fresh:** The gate RESTARTS from round 1 with `seen`/`found`/`pending`/`dryStreak` all reset to zero — no findings or dry-streak credit from the prior run carry forward.
4. **dryStreak NOT incremented:** The partial round 2 entry is NOT credited — `dryStreak` is NOT incremented toward CLEAN on the basis of the torn record.

**RED/GREEN contract:** Before the `adversarial-loop.md` §8 atomic-journaling + only-complete-rounds prose exists, no implementing skill can satisfy "partial round not credited" → selftest FAIL. After the prose lands and a thin skill executes the §8 detection procedure → selftest PASS.

**This assertion is the ONLY hard guard on the resume / session-kill logic** — deterministically checkable (yes/no on detection + `dryStreak` not incremented). The prose in `adversarial-loop.md` §8.3–§8.4 specifies the contract; this fixture proves the executing skill satisfies it in-harness.

**Failure condition:** partial journal accepted as liveness-complete — i.e., the torn round-2 entry counts as covered, `dryStreak` is incremented, or the gate does not announce the restart.

### Runtime selftest gate

The in-harness `--selftest` RUN is the Task 7 Step 7.6 acceptance gate. The `/5`-mode sub-block runs under the already-enabled `/5` finderSet; the `/4`-mode sub-block runs once the operator adds `"/4"` to the live `enabled-phases` (the deliberate spend-gated activation step).
