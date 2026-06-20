---
name: build
description: "Automated build execution from approved plan. Routes tasks by classification (Opus/Sonnet/Parent), commits at logical boundaries. Phase /3 of the sprint pipeline. Also invoked as /3."
---

# /build — Build (alias: /3)

**Trigger:** After `/2` produces approved plan, or for mechanical sprint tasks.

**Gate:** If `/2` invoked this session and incomplete, finish `/2` first. `/3` requires a finalized plan in CT with classified tasks.

**Execution is fully automated.** After plan approval, assume developer absent. Never pause to ask "shall I continue?"

Only pause when waiting for agents. `/3` is strictly execution of the `/2`-approved plan and makes no design decision: a design-decision-gap (a choice the `/2` plan left unresolved) is a `/2`-incompleteness that HALTS the build and returns to `/2` (see `## Design decisions during build`), never an in-`/3` pause-and-default.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step in CT. Mark in_progress->completed.

## Procedure

For each step in CT:

1. Read CT for current step.

2. Execute by classification:
   - **`[SONNET]`**: Spawn `sonnet-implementer` subagent via `Agent(model: "sonnet")`. Pass: spec reference, file paths, acceptance criteria, output paths. **When the engine path is enabled (`## Engine path — serial produce→verify`), the implementer writes a structured result-FILE (the `## 3c` result-FILE schema) — NOT a held summary — and PRODUCE stages run SERIALLY (one writer at a time), never `run_in_background` parallel writers.** When the engine path is NOT taken (fallback), today's behavior is unchanged: the subagent writes results to disk and returns a concise summary, parallel tasks via `run_in_background: true` (the fallback preserves the status quo, including the Rule-10 held-summary shape).
   - **`[OPUS]`**: Execute directly. Requires conversation context or design judgment.
   - **`[PARENT]`**: Execute directly. Orchestration or user-facing decision.

   **Duo mode fallback:** If `CC_DUO_MODE=1` is set and a Sonnet listener is active, `[SONNET]` tasks may be dispatched via file-based IPC to `_pending_sonnet/[chN/]` instead.

   **Data model pre-flight (any task touching a declared field):** When a `[SONNET]`, `[OPUS]`, or `[PARENT]` task adds, removes, renames, changes the type of, or changes the default value of a field on a data model (data model classes, schema definitions, entity types, etc.) — silent-fallback bugs can arise from any of these, not just rename/remove, include in the dispatch prompt (or execute directly for `[PARENT]`): "grep every consumer of this field name in `src/` (or `lib/`) + `test/`; confirm any matching consumer reads the same name with no silent fallback (`?? `, `|| `) substituting a default." Full source-spec-code fidelity audit waits for `/perfect` Phase 2.5 per `~/.claude/reference/spec-verification.md`; this pre-flight is cheap insurance, not a substitute.

3. Update CT — cold-start ready, mark completed steps.

4. Repeat until a **commit boundary** (see below).

5. Verify before commit — full rules in `.claude/reference/commit-protocol.md`. READ IT the first time you commit in any session.
   Do NOT pre-stage. The git index is shared across channel sessions.
   Compute the verifier diff (index-independent): `git diff HEAD -- <files> > verification_findings/staged_diff_chN.diff`. NEVER `git diff --cached`. For unchanneled sessions, omit the `_chN` suffix — use `verification_findings/staged_diff.diff`, `commit_check.md`, `commit_cold_read.md`.
   Spawn `commit-adversarial` and `commit-cold-reader` subagents in parallel via `Agent(model: "sonnet")`. In each agent's prompt, pass BOTH:
     - `diff_path`: the staged_diff file from the previous step
     - `output_path`: `verification_findings/commit_check_chN.md` (adversarial) or `verification_findings/commit_cold_read_chN.md` (cold-reader). For unchanneled sessions, use the unsuffixed filenames. The script greps for the chN-suffixed name if `--channel N` is set — wrong `output_path` = script exits 1.
   Agents write `VERDICT: PASS|WARN|FAIL` into those files. No HASH line needed — `channel_commit.sh` stamps the real hash in `--local-verify` mode via sed ("stamps" = overwrites any existing `HASH:` line, or inserts one after `VERDICT:`). Never pre-stage, never pre-hash, never touch the index.
   - PASS/WARN: proceed with `bash scripts/channel_commit.sh --channel N --files "<files>" -m "<message>" --local-verify` (project-local path; the global `~/.claude/scripts/channel_commit.sh` is kept in sync and is equivalent).
   - FAIL: review findings, fix, re-verify.

   **Note:** This verify-before-commit workflow applies ONLY when verifier agents are spawned. The `--skip-squad` flag (used by /finalize pre-verification WIP commits) bypasses agent spawning entirely — no verdict file is written, so there is no PASS/WARN/FAIL outcome to react to. /finalize callers should NOT follow the FAIL branch; if the underlying file state is wrong, fix it before the /finalize run, not after.

   **Duo mode fallback:** Omit `--local-verify` — channel_commit.sh dispatches to the Sonnet listener automatically.

6. Repeat from step 1.

In default mode, /verify spawns `sonnet-verifier` natively. In duo mode, /verify dispatches to the Sonnet listener.

## Engine path — serial produce→verify (when `"/3"` is enabled)

**Gate route (model-side, pre-invocation — reuse `adversarial-loop.md ## 4` VERBATIM).** Read the config with project-local precedence: when invoked inside a project, read the project-local `.claude/reference/workflows-config.md` (CWD-relative); the host `~/.claude/reference/workflows-config.md` is the fallback only when no project-local copy resolves. (Not "either/or" — project-local takes precedence when present, host otherwise; same precedence as `/4`/`/5`.) Parse under the schema discipline (`## 4.3`). The engine path is taken ONLY when `workflows_enabled: true` AND `"/3"` is in `enabled-phases` AND the live `ToolSearch select:Workflow` probe resolves. Otherwise → the `/3`-specific FALLBACK (today's single-pass build, § Procedure unchanged). The four fallback banner reasons are `config OFF` · `config PARSE-FAIL` · `tool absent` · `materialization ERRORED` (`## 4.4`, verbatim).

**Mandatory top-of-output path banner** (the FIXED engine `PROVE-GATE:` prefix per `## 4.4` — only the lens COUNT is finderSet-relative):
- Engine path: `PROVE-GATE: engine path (5 lenses, K=2, max 5)`
- Fallback path: `FALLBACK single-pass — reason: <config OFF | config PARSE-FAIL | tool absent | materialization ERRORED>`

The `/3` engine reads `K`/`maxRounds`/`budget`/`budgetGuard`/`enabled-phases` for the checkpoint engine, plus the optional `build-gates` key (`{ src, test, ext, diffScan?, gates: [{name, cmd}] }`) consumed by the per-task verify tier (absent → skill defaults, cheap-gate tier degrades to lenses 4/5 only, never PARSE-FAIL).

**Skill-default `src`/`test`/`ext` (pinned — so an absent `build-gates` never scans the wrong tree).** When `build-gates` is absent (or omits `src`/`test`/`ext`), the lens-4/lens-5 greps use the skill's pinned defaults: `src = "src"`, `test = "test"`, `ext` = the project's predominant source extension (detected from the working tree by file count, falling back to a no-op trivially-covered lens-5 PASS with a receipt when no single extension dominates — never a silent wrong-tree scan). For this project (Wakeful, a Flutter/Dart tree) the correct values are `src: "lib"`, `test: "test"`, `ext: "dart"` — which is why Wakeful's `build-gates` MUST be populated with `{ src: "lib", test: "test", ext: "dart", … }` rather than relying on the generic `src`/`test` default (the generic default `src = "src"` would miss Wakeful's `lib/` tree). The skill states these defaults explicitly and, when it falls back to them, emits the default values into the pipeline-log so an operator can see which roots lens 5 actually scanned. A default that resolves to a non-existent root yields a trivially-covered lens-5 PASS with a receipt recording "root absent," never a silent miss.

### Single-threaded-writes invariant (HARD — WIP §9.3)

All product writes during `/3` are single-threaded and orchestrator-owned. The PRODUCE lane has **exactly one active writer at any instant** — the parent (for `[OPUS]`/`[PARENT]`, written directly) or a single serialized Sonnet implementer (for `[SONNET]`, one at a time). The engine fans out **read-only verifiers only**. Because the per-task loop is serial, this is true by construction — `/3` never spawns two concurrent code-writers. **No parallel worktree-writers** (the literal WIP §9.3 multi-writer pattern, forbidden). `[SONNET]` tasks that today use `run_in_background: true` for "parallel tasks" run as **serialized PRODUCE stages** under the engine path — one writer at a time.

### Duo-mode (`CC_DUO_MODE=1`) propagation (REQUIRED — duo mode must NOT revert to held-summary)

The augmented skill has a second `[SONNET]` dispatch surface: in duo mode `[SONNET]` PRODUCE work routes through `_pending_sonnet/[chN/]` to a listener rather than a native subagent. The produce→verify file-handoff MUST be propagated to that listener contract so duo mode does NOT silently revert to the held-summary shape this design kills. **Baseline-capture order is identical to native mode — at PRODUCE(N) START, before any PRODUCE work begins.** In duo mode: the PARENT FIRST captures the per-task `git stash create` baseline (BEFORE dispatching the `[SONNET]` PRODUCE to the listener) and persists it as `baselineRef` — exactly the same pre-PRODUCE order as native mode, so the task-local FULL/path-scoped diffs and the `baselineRef` the result schema requires are computed against task N's START state (a baseline captured AFTER the listener's PRODUCE would snapshot the post-PRODUCE tree and the diffs would no longer be "task N since start"). THEN the LISTENER (executing the `[SONNET]` PRODUCE) writes the `<taskId>.result.json` result-FILE per the `## 3c` result schema (NOT a concise summary), echoing in the `baselineRef` the parent already captured; AFTER PRODUCE completes the PARENT runs the read-only deterministic VERIFY (parent-side or a parent-spawned read-only verifier) against that pre-PRODUCE baseline, writes/reads the `<taskId>.verdict.json` verdict-FILE, and appends the PRODUCE/VERIFY pipeline-log entries (the parent owns the log in BOTH modes). The result/verdict/pipeline-log contract — and the pre-PRODUCE baseline-capture order — is identical across native and duo modes; only the PRODUCE execution surface differs (native subagent vs `_pending_sonnet/` listener). **A duo-mode `[SONNET]` task that returns a held summary instead of writing the result-FILE is a build FAIL** (it would revert the Rule-10 violation this design kills).

### The serial per-task loop (a plain ordered skill loop, NOT a concurrency primitive, NOT an engine invocation)

For each plan task in CT order:

1. **Record the per-task baseline.** Before PRODUCE(N), the PARENT records ONE pinned baseline ref of the working tree at that instant via **`git stash create`** — THE single pinned baseline primitive (not an open menu): it returns a dangling commit object id capturing the full WORKING TREE (including unstaged content) without touching the index or the stash stack, so it is safe to call mid-build and is index-independent (consistent with the commit protocol's index-separation discipline). **`git write-tree` is NOT used** — it serializes the INDEX only, not the working tree, so it would diff against the wrong state on unstaged task edits. The parent writes the captured object id into the result-FILE as `baselineRef` AND the pipeline-log, so a resumed `/3` reconstructs the diffs from the persisted ref rather than falling back to the buggy cumulative `HEAD`. The first task's baseline is the `/3`-entry working-tree snapshot via the SAME `git stash create` (NOT `HEAD` — on a dirty tree `HEAD` would conflate pre-existing uncommitted changes into task 1's diff).

2. **PRODUCE(N) — single writer.** The implementer (Sonnet subagent for `[SONNET]`; the parent directly for `[OPUS]`/`[PARENT]`) writes the code change AND a **result-FILE** to `verification_findings/build_pipeline[_chN]/<taskId>.result.json` against the `## 3c` result-FILE schema (structured JSON, NOT freeform prose). An orchestration-only `[PARENT]` task with no file writes declares `"filesWritten": []` and is exempt from the diff-based lens-4/5 checks (still writes a result-file so the verifier confirms the exemption). PRODUCE(N) fully completes before VERIFY(N) begins. **Acceptance-criteria extraction (BOTH repo heading shapes) + empty→task-description fallback.** The skill extracts the task's acceptance criteria from the CT/plan task, and MUST handle the TWO heading shapes the repo's plans actually use:
- the plain `Acceptance:` form — a single-line field, e.g. `Acceptance: build_runner succeeds, flutter test passes.` (as in `docs/superpowers/plans/2026-05-15-sprint-16a-journaling.md`). Split the trailing text on commas/semicolons into individual criteria.
- the bold `**Acceptance:**` form — a bold heading followed by a nested checklist of `- [ ]`/`- ` bullets beneath it (as in `docs/superpowers/plans/2026-04-16-sprint14e-yoga-nidra-dedup.md`). Each bullet is one criterion.

The extractor detects whichever shape is present (grep for `^\s*\**Acceptance:\**` — the `\**` tolerates the bold markers — then: if text follows on the same line, parse the inline form; else collect the following indented `- ` bullets) and passes the criterion list to the producer, which writes it into `acceptanceCriteria[]`.

If the task has **no explicit `Acceptance:`/`**Acceptance:**` field** (absent or empty), the skill synthesizes the plan task's **description text** (the task title + purpose statement) as the single criterion AND the producer **writes that synthesized criterion into `acceptanceCriteria[]`** (NOT leaving it `[]`) — so the result-FILE, the verifier input, and the surfaced `criteriaChecked[]` all carry the SAME criterion set with no divergence. The verifier NEVER receives an empty `acceptanceCriteria[]` (an empty set would trivially PASS every task). A result-FILE with `acceptanceCriteria: []` and no task-description fallback is a PRODUCE FAIL. This extraction is the build skill's responsibility — never left to the verifier to infer.

3. **VERIFY(N) — fresh-context, read-only deterministic skill verify (NOT the engine).** A distinct agent (never the producer's session) reads (a) the result-FILE, (b) the task's acceptance criteria (surfaced into the verdict-file, NOT scored — acceptance-criteria-met is a checkpoint LLM lens), and (c) TWO diffs against the recorded PRODUCE(N) `baselineRef` (NOT `git diff HEAD` which is cumulative once multiple uncommitted tasks touch a file; index-independent, never `--cached`): the **FULL** working-tree diff `git diff "$baselineRef"` (NO pathspec) to enumerate every changed path for the `filesWritten[]` under-declaration check, and the **path-scoped** diff `git diff "$baselineRef" -- $(the result-FILE filesWritten[] paths)` for the lens-4/lens-5 content checks. It runs the **deterministic lenses `{4,5}` + the project cheap gates ONLY** (NO LLM lenses, NO per-task acceptance-criteria scoring) + the `filesWritten[]`-vs-FULL-diff under-declaration cross-check (a path in the full diff absent from `filesWritten[]` = FAIL; a path-scoped diff would self-blind this). It surfaces the result-file `todos[]`/`deferrals[]` into the verdict-file `declaredIncomplete` (a deterministic read). It writes a **per-task verdict-FILE** to `verification_findings/build_pipeline[_chN]/<taskId>.verdict.json` against the `## 3c` per-task verdict-FILE schema. **The parent reads THAT verdict-FILE — never a held summary.**

4. **Parent resolves the verdict (§5).** A per-task FAIL routes to the PARENT immediately (shift-left fix-before-proceed). After a fix, the parent **re-captures the task scope** (`filesWritten[]` ∪ fix-touched files), updates `diffScope`, re-captures the task-local diff against the SAME PRODUCE(N) baseline, and re-runs VERIFY(N). The loop does not advance to PRODUCE(N+1) until task N's verdict is green or its finding is fixed. A `RETURN_TO_2` verdict HALTS the loop (design-decision-gap — see Task 4 / §5).

5. **PRODUCE(N+1).** Only after VERIFY(N) is green.

**`scopeHashChecked` enforcement (parent).** The parent REJECTS any verdict-FILE whose `scopeHashChecked` ≠ the digest of the tree the verifier actually ran against. **Per-task:** the parent computes `scopeHashChecked` at the PRODUCE(N)→VERIFY(N) handoff as a content digest over task N's `filesWritten[]` (deferral-ledger + audit writes excluded, per `## 6.1`), using the same content-digest function the engine uses (`## 6`). A mismatch ⇒ the parent re-runs VERIFY(N) rather than trusting the field.

**Phantom-citation rejection (parent, BOTH tiers).** The parent must not act on any finding whose `citation` cannot be grounded in a grep/Read on the cited target. An ungroundable citation is itself a phantom finding, treated as live. Applies to the checkpoint LLM lanes AND the per-task deterministic `{4,5}` grep-result citations.

### The pipeline-log (PARENT-written, the ordering-evidence substrate)

The PARENT appends one entry per stage to `verification_findings/build_pipeline[_chN]/pipeline-log.jsonl`:
- `{ "task": "<taskId>", "stage": "PRODUCE", "seq": <n> }` and `{ "task": "<taskId>", "stage": "VERIFY", "seq": <n> }` for each per-task stage;
- a single `{ "stage": "CHECKPOINT_ENGINE_START", "seq": <n> }` entry (no `task`) appended at the instant the skill fires the checkpoint engine.

All entries are keyed by a **globally-monotonic `seq` counter the PARENT increments for the whole `/3` run** (NOT file-mtime, NOT a cross-log comparison with the engine journal). The PARENT writes ALL entries — including for `[SONNET]` tasks (the parent logs the PRODUCE/VERIFY boundaries; the subagent never writes the log). The pipeline-log is the ordering evidence the `--selftest` assertions (v)/(vi) read; the `CHECKPOINT_ENGINE_START` entry lets assertion (vi) prove "checkpoint fired after all per-task VERIFYs" ENTIRELY within the pipeline-log (the engine journal separately proves the checkpoint RAN, but the two logs are never seq-compared).

*Out-of-scope note: a disjoint-file PRODUCE latency-overlap (running an earlier task's VERIFY concurrently with a later task's PRODUCE when their file sets are provably disjoint) is a possible future optimization, NOT specified here. The only specified per-task path is serial.*

### The checkpoint engine run (the ONLY tier that invokes the engine)

After every task's PRODUCE→VERIFY has completed for the commit-group, the SKILL fires the ENGINE (`## 4` gate) ONCE at the commit-group / phase boundary (skill-fired, never engine mid-task, per WIP §7), running the full 5-lens `## 3c` finderSet as a single loop-until-dry: the deterministic lanes `{4,5}` re-run FRESH as pre-passes over the commit-group scope (signed at the current `scopeHash`, NOT carried-forward from the per-task tier) + the LLM lanes `{1,2,3}` fan out — all 5 accounted-for per round. **"Light" means FEWER LENSES (3 LLM vs `/5`'s 5) + SMALLER SCOPE (the commit-group, not the sprint) — NOT fewer rounds:** the checkpoint loop runs to K dry rounds using the config `K`/`maxRounds` (the same engine, the same loop). For the one-commit-per-`/3` default cadence the checkpoint is ONCE, at the end of `/3`, immediately before the commit pair. For a genuine load-bearing mid-`/3` split (the § Commit boundaries exception), each commit-group boundary is a checkpoint run. The checkpoint skeptic runs BEFORE the `commit-adversarial`+`commit-cold-reader` pair — complementary, not a replacement.

### Commit boundaries

**Default cadence: once at end of /3, once at end of /5.** Each commit spawns 2 verification agents + test suite — that cost means fewer, larger commits, not more granular ones.

- **/3 (build):** One commit covering ALL code changes built during /3, at the very end. Not per-phase, not per-subsystem, not per file set. One commit.
- **/5 (finalize):** One commit covering /4 quality changes + sprint close artifacts (CLAUDE.md corrections, SC/CIP updates, etc.).
- **/2 (design):** No commit. Plan and CT updates are included in the /3 commit.
- **/4 (perfect):** No commit. /4 code changes are committed in /5.

**Exception — commit mid-/3 only when:** (1) a plan-defined commit task explicitly separates two phases for a stated reason (e.g., infrastructure must land before features that depend on it AND they cannot be batched), AND (2) you cannot complete /3 in one session. Even then, verify the plan's reason is real before splitting.

**Plan-generated commit tasks:** Plans are sometimes generated with mid-/3 "Commit Phase N" tasks. Ignore them — they are non-compliant with the one-commit rule. Follow the commit boundaries here, not the plan's task structure. If the plan has a genuinely load-bearing mid-/3 split (infrastructure dependency), the exception above applies; state the reason in CT before committing early.

**Never commit because:** a phase feels "done," the file set is different, "while agents run," or as a checkpoint. These are not reasons. Agent cost is real — wasted verifier spawns consume the developer's paid budget.

**If you mis-spawn verifiers:** Use TaskStop immediately to cancel them. "They're almost done" does not justify letting them run. Budget waste IS harm.

## Batching rules

**Batch when ALL true:** same code pattern, same spec section, content/data additions only (zero logic), <300 lines inserted.

**Never batch when ANY true:** control flow/state/engine logic, multiple subsystems, design judgment required, different spec sections.

## Design decisions during build — `/3` is STRICTLY EXECUTION (never makes or defers a decision)

`/3` is strictly execution of the `/2`-approved plan. ALL design decisions are made, externalized, and approved during `/2`. `/3` NEVER makes or defers a design decision. There is NO "Deferred Decisions" list and NO `/3`-end deferred-decision report.

A `/3` **design-decision-gap** — a choice the `/2` plan did not resolve (surfaced as a producer `deferrals[]`, or a checkpoint/per-task finding requiring a choice the plan did not make) — is a **`/2` INCOMPLETENESS**, not a `/3` decision to make. The moment one is surfaced, the PARENT:
1. **HALTS the build** (the single `/3` commit does NOT fire);
2. writes a `## Return to /2 — design-decision-gap` note to the **channel CT** stating, in plain language, which decision the `/2` plan left unresolved;
3. echoes the same in the `/3` stdout closure (the owner reads stdout; the CT copy is the durable backup).

`/3` **never** conservative-defaults-and-continues, never marks-provisional, and never parks the decision for end-of-`/3` approval. A `/3` run that does any of those instead of halting and returning to `/2` is a build FAIL.

**Governance reconciliation (the CLAUDE.md Process rule):** the CLAUDE.md Process rule forbids deferral without explicit current-conversation permission, and requires `/3` never pause between tasks. This model satisfies it directly — there is no `/3` deferral to require permission for, because no design decision is ever made or deferred at `/3`. A `/2`-incompleteness halts to `/2` (a return-to-`/2` boundary), which is not an in-`/3` deferral or a deliberation pause. (The "/3: never pause between tasks" clause still holds — `/3` does not pause to deliberate; it halts only on a `/2`-incompleteness.)

### Terminal model (the `## 1.3` two-level model applied to `/3`)

The engine's two-level terminal model (`## 1.3`) applies **only to the checkpoint engine run** — the per-task tier is a skill-orchestrated deterministic verify with NO engine terminals.

**Per-task VERIFY (SKILL deterministic tier — NO engine terminals):** the verdict-FILE carries `PASS | FAIL | RETURN_TO_2`. **Verdict rollup:** FAIL if any lens-4/lens-5 check or project cheap-gate fails. `declaredIncomplete` is resolved by class, never carried forward as a benign WARN — a non-empty `todos[]` (incomplete implementation) ⇒ **BUILD-EXECUTION FAIL** the PARENT fixes (pure execution; the loop does not advance until it is gone); a non-empty `deferrals[]` (a design decision the `/2` plan did not resolve) ⇒ **`RETURN_TO_2`**: the loop HALTS and the parent surfaces "design-decision-gap — `/2` plan incomplete; return to `/2`." PASS only when no gate fails AND `declaredIncomplete` is empty. No LLM lenses run at this tier.

**Checkpoint engine run (the ONLY tier with engine terminals — `## 1.3`):**
- **CLEAN** (engine converged; `found`/`disagreements`/`pending` empty) → proceed to the commit pair.
- **FINDINGS** (engine converged, gaps remain — internal signal) → resolved by **finding class**:
  - **(a) BUILD-EXECUTION gap** — produced code does not match the `/2` plan / its acceptance criteria, or is incomplete (a stub, a dropped sub-bullet, a tautological test, a silent-fallback consumer). Pure execution (no design judgment — the plan already says what the code must be) → the **PARENT FIXES** (single-threaded writes) and re-invokes the engine fresh (`seen`/`found`/`pending` reset, per `## 5`). The operator never sees engine `FINDINGS` for a build-execution gap — the parent fix-loop is still running.
  - **(b) DESIGN-DECISION gap** — a finding requiring a CHOICE the `/2` plan did not resolve. This is a **`/2` INCOMPLETENESS**: `/3` **HALTS** and surfaces **"design-decision-gap — `/2` plan incomplete; return to `/2`"** (a CAPPED-style halt — the single `/3` commit does not fire — plus the CT `## Return to /2 — design-decision-gap` note). Never conservative-defaults-and-continues, never parks for end-of-`/3` approval.
- **CAPPED** (cap/budget/circuit-breaker before convergence) → the PARENT writes parked items + diagnostics to CT, emits the CAPPED report, and **HALTS** (never re-invokes after CAPPED, `## 5.1`). The single `/3` commit does not fire.

**Operator-facing `/3` terminals:** `CLEAN` (checkpoint dry → commit pair → single commit) · `RETURN-TO-/2` (design-decision-gap — `/2` was incomplete; build halts pre-commit, CT records the gap) · `CAPPED` (parked to CT, build halts pre-commit) · `ERROR → fallback` (gate-level exception → today's single-pass build). Banner strings per `## 2.2` (MD-9), prefixed with the engine's FIXED `PROVE-GATE:` prefix (`## 4.4`).

## Completion

Announce `/3` complete, readiness for `/4` (`/perfect`). There are NO deferred decisions to present — `/3` is strictly execution and makes/defers none (see `## Design decisions during build`). The only non-CLEAN closures are `RETURN-TO-/2` (a design-decision-gap surfaced — the `/2` plan was incomplete; build halted pre-commit, CT records the gap) and `CAPPED` (parked to CT, build halted pre-commit).
