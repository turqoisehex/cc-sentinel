## Adversarial Loop — Engine + Gate + Parent Fix-Loop (universal)

Read before any phase skill materializes the adversarial-loop engine. The engine
FINDS; it never WRITES product files — all writes are the parent's. Universal: no
Wakeful/Flutter/Riverpod-isms in engine logic; project mechanisms are supplied by
the phase skill.

## 1. Inputs and definitions

### 1.1 Inputs

| Input | Description |
|-------|-------------|
| `scopeContext` | What finders read: work products, plan, CT, spec, diff, the project DI-graph and entry-point modules. Assembled by the phase skill's shared `scopeContext` resolver. |
| `scopeHash` | A working-tree content digest — see definition below. Computed by the PARENT per engine invocation and passed in. |
| `finderSet` | A named, versioned collection of `finderLenses[]`. The active finderSet = the lenses declared in the phase finderSet section (§3 for `/5`; §3b for `/4`). |
| `finderLenses[]` | N adversarial roles, each a distinct lens and prompt. Each returns a schema-validated VERDICT; a missing or malformed VERDICT = FAIL + auto-retry that lens (never a silent pass). |
| `dedupKey(f)` | The stable identity of a finding across rounds. Used by the dedup filter and the acceptedDeferrals ledger. |
| `verifyLens` | The refute-it check applied to each fresh finding. Runs in a FRESH context — `{finding, scope}` only, never the finder's reasoning chain (Rule 7). |
| `dryRounds` (K) | Consecutive fully-covered rounds with no new real-gap = discovery converged. Floor: 2. Default: 2. |
| `maxRounds` | Hard cap on discovery rounds. Default: 5. Must be ≥ `dryRounds` — if `maxRounds < dryRounds` CLEAN is unreachable; reject at config parse. |
| `budgetGuard` | A ceiling on BOTH axes (rounds AND token/dollar spend), shared across the WHOLE gate including all PARENT re-invocations. Stop if either axis is exhausted. |

### 1.2 Definitions

**`scopeHash`** — A **working-tree content digest** over the resolved in-scope snapshot: the in-scope path set + their tracked-but-dirty content + relevant untracked/generated files + the CT/spec/plan text + the diff payload. A bare git tree hash is too narrow — it misses the uncommitted, untracked, and generated state the engine actually runs over. The PARENT computes it per engine invocation and passes it in; the engine re-validates it at every round boundary and before any terminal verdict. Any mismatch invalidates carried deterministic receipts, resets `dryStreak`, and forces a recompute before dry can be credited. Deferral-ledger and audit writes are EXCLUDED from the digest.

**`materialization`** — An augmented skill authoring and launching a per-run Workflow from the prose proc-doc (no checked-in `.js`). Its success / run-error / no-op / fallback handling is the §4 gate. Confirmed capable (Task-1 spike, `wf_a8e1bb16-3b1`, PASS): a real adversarial-loop was materialized from the proc-doc shape, found a seeded gap, had fresh-context verifiers confirm `real-gap`, and returned `terminal: FINDINGS` with valid liveness.

**`coverage-receipt`** — The per-round record that every lens in the finderSet is accounted-for (the `lensStatus[]` entries) against the current `scopeHash`. A `carried-forward` deterministic lens counts as covered only while its receipt's `scopeHash` still matches the current value. Dry is credited only on a fully-covered round.

**run-journal artifact (provides "liveness")** — ONE on-disk file (`subagents/workflows/<runId>/journal.jsonl`-style; exact path is harness-observed, verified by `--selftest`, not contractual). Per-round fields:

```
{
  round,
  lensStatus[]          // each lens: ran | found-N | errored | carried-forward
  llmFanOutAgentIds[]   // agent ids for the LLM-backed lanes
  deterministicReceiptIds[]  // signed receipts for the active finderSet's declared deterministic lanes
  coverageReceipt,
  scopeHash,
  pending,
  terminal
}
```

**Liveness = all lenses in the active finderSet accounted-for in `lensStatus[]`** — agent ids for the LLM lanes + signed receipts for the active finderSet's declared deterministic lanes. NOT "≥ agent id count": a valid run has agent ids (one per LLM lane) + signed receipts (one per declared deterministic lane). Written by the runtime and agents (a logger-agent if needed, counting against caps/budget) — the workflow script itself has NO filesystem access.

**open-findings set (PARENT)** — `open = (found ∪ disagreements ∪ pending across fix-cycles, by dedupKey) − acceptedDeferrals`. The no-progress circuit-breaker compares open IDENTITIES (not `|open|`) across cycles.

**`acceptedDeferrals` ledger** — Keyed by `dedupKey + STABLE per-finding evidence/content hash (the specific files/lines the finding concerns) + approval-evidence`. NOT keyed by the whole-scope `scopeHash`, which churns on every fix and would re-litigate every deferral. Deferral-ledger and audit writes are themselves excluded from `scopeHash`. A same-key item whose per-finding evidence is UNCHANGED is treated as resolved-for-this-gate and listed in the CLEAN report (it does not re-block). A change to that finding's evidence reopens it. A parked item with NO operator approval is CAPPED, not deferred.

**`effectiveOpen`** — `found − acceptedDeferrals` (matched by `dedupKey` + UNCHANGED per-finding evidence hash). Empty + no disagreements ⇒ operator-CLEAN.

### 1.3 Terminal-state model (two levels)

**Engine, per invocation** (ordered):
- `CLEAN` — converged AND `found`/`disagreements`/`pending` all empty. The engine knows nothing about deferrals.
- `FINDINGS` — converged, gaps remain. An INTERNAL signal to the PARENT to fix + re-invoke. The parent may still close this as operator-CLEAN if `effectiveOpen` is empty.
- `CAPPED` — cap or budget hit before convergence (including a pending backlog).

**Operator-facing** (the closing report):
- For a normal `/5` run: `CLEAN` · `CAPPED` (parked items emitted to CT) · `ERROR → fallback`. The operator never sees `FINDINGS` as a `/5` terminal — the parent loop is still running.
- For report-only `/prove`: one additional terminal — **`GAPS_FOUND`** — surfacing the engine's `FINDINGS` (the survivor list) read-only, without fixing or re-invoking.

### 1.4 Engine return tuple

Every handoff from the engine to the PARENT carries all six fields:

```
{ found, disagreements, pending, terminal, journalArtifact, scopeHash }
```

`pending` must be included in CAPPED reports. `scopeHash` is the value the engine validated at the terminal boundary.

---

## 2. ENGINE — one discovery pass

The engine = one invocation = one discovery pass. The engine NEVER fixes and NEVER writes product files. The workflow script has NO filesystem access; journal and observability writes are done by the runtime and by agents (a logger-agent if needed), never by the engine.

```
ENGINE(scopeContext, scopeHash, finderLenses[], verifyLens, dryRounds K, maxRounds, budgetGuard):

  seen = {}          // all findings ever recorded in this invocation
  found = {}         // verified real-gaps
  disagreements = {} // persistent finder/verifier conflicts — never dropped
  pending = {}       // novel findings awaiting verifyLens classification
  dryStreak = 0

  loop discovery rounds:

    // scopeHash guard — runs at EVERY round boundary
    if scopeHash changed since this round's start:
      invalidate carried deterministic receipts for the active finderSet's declared deterministic lanes
      reset dryStreak to 0
      recompute scopeHash

    // parallel fan-out (≤ concurrency cap, ≤ the active finderSet's lens count)
    raw = parallel(finderLenses -> agent(lens.prompt, scopeContext))

    // schema validation — missing/malformed VERDICT = FAIL + auto-retry that lens
    for each agent VERDICT in raw:
      if missing or malformed: FAIL + auto-retry that lens (never a silent pass)

    // dedup against ALL prior rounds in THIS invocation
    novel = raw − (seen ∪ pending)

    // RECORD BEFORE REFUTE — so a refuted finding cannot recur
    seen   += novel
    pending += novel

    // classify pending via verifyLens (sequential, fresh ctx {finding, scope} only)
    for each f in pending (cap per-round to stay within concurrency; re-queue remainder):
      result = verifyLens({finding: f, scope: scopeContext})
      switch result:
        real-gap              → found += f ; remove from pending
        disagrees-persistently → disagreements += f ; remove from pending
        refuted-clean         → drop ; remove from pending
        inconclusive          → leave in pending (re-queued next round — NEVER silently dropped)

    // coverage: every lens accounted-for for the CURRENT scopeHash
    covered = all lenses in finderLenses[] have a lensStatus entry
              (ran | found-N | errored | carried-forward) valid for the current scopeHash

    // dry credit — ALL conditions required
    if (no NEW real-gap this round) AND covered AND (pending is empty):
      dryStreak++
    else:
      dryStreak = 0

    // write per-round journal entry (runtime + logger-agent; script has no filesystem access)
    journal.append({ round, lensStatus[], llmFanOutAgentIds[], deterministicReceiptIds[],
                     coverageReceipt, scopeHash, pending, terminal: null })

  until dryStreak >= K
     OR round >= maxRounds
     OR budgetGuard low (rounds OR spend)

  // convergence check
  converged = (dryStreak >= K)   // K rounds: no new gap, fully covered, NOTHING pending

  // terminal — re-validate scopeHash BEFORE verdict
  if scopeHash changed: recompute; invalidate receipts; this may change converged (re-loop if budget allows)
  terminal = (converged AND found empty AND disagreements empty) ? CLEAN
           : converged                                           ? FINDINGS
           :                                                       CAPPED

  return { found, disagreements, pending, terminal, journalArtifact, scopeHash }
```

### 2.1 Key correctness notes

**Discovery vs resolution are TWO separate loops — this is what makes CLEAN honest.** The engine's `dryStreak` measures *discovery convergence* (K rounds with no NEW real-gap = "we've found everything"), NOT doneness. If `found` is non-empty at convergence, terminal = `FINDINGS`; the parent fixes and re-invokes fresh. CLEAN requires discovery-dry AND `found` empty AND no open disagreements AND no `pending` backlog. A non-empty survivor set, an unresolved disagreement, or un-refuted findings can never read as CLEAN.

**Dedup vs `seen` is per-invocation; `seen`/`found` reset on each fresh re-invoke.** Everything novel enters `seen` BEFORE refute (else a refuted finding recurs every round and discovery never converges). The parent resets `seen`/`found` on each fresh re-invoke after fixes, proving against the new tree.

**Disagreements are first-class, never dropped.** A persistent finder/verifier conflict is recorded in `disagreements` and returned to the parent; it blocks CLEAN and routes to the parent's MD-5 investigation (§7). It is NOT swallowed as "refuted."

**`verifyLens` runs sequentially after each round's fan-out** — `{finding, scope}` only, never the finder's chain (Rule 7) — keeping concurrency within the cap: finders fan out (≤ active finderSet lens count), then verifiers. A non-empty `pending` backlog blocks dry — un-refuted findings can never count toward a clean round.

**Coverage carry-forward is bound to `scopeHash`.** The engine re-validates it at every round boundary and before any terminal verdict; any in-scope change invalidates carried receipts for the active finderSet's declared deterministic lanes and forces their re-run before dry can be credited. A silently-skipped or errored lens also blocks dry.

### 2.2 Observability + run-journal

All observability artifacts are written by the runtime and by agents (a logger-agent if budget allows) — the workflow script itself has **NO filesystem access**. See §4.4 for the mandatory path banner (MD-1), which lives in the gate.

#### Run-journal artifact (MD-11, §4.1)

ONE on-disk run-journal per engine invocation: `subagents/workflows/<runId>/journal.jsonl`-style. The exact path is harness-observed, verified by `--selftest`, NOT contractual. Per-round fields (exact schema — see naming contract):

```
{
  round,
  lensStatus[],               // each lens: ran | found-N | errored | carried-forward
  llmFanOutAgentIds[],        // agent ids for the LLM-backed lanes (lenses 1–5, 7)
  deterministicReceiptIds[],  // signed receipts for the active finderSet's declared deterministic lanes
  coverageReceipt,
  scopeHash,
  pending,
  terminal                    // null until the terminal round
}
```

**Liveness = all lenses in the active finderSet accounted-for in `lensStatus[]`** — agent ids for the LLM lanes PLUS signed receipts for the active finderSet's declared deterministic lanes. This is NOT "≥ agent id count"; a valid run has one agent id per LLM lane plus one signed receipt per declared deterministic lane. No terminal verdict is accepted without the journal showing all active finderSet lenses accounted-for in `lensStatus[]`. A silent no-op or any fallback can never read as CLEAN — the liveness check catches it.

The proof-sentinel and the jsonl-audit line are **SEPARATE** artifacts from the journal (see §2.2.4 below).

#### Per-round heartbeat (MD-3)

Every progress line emits (text equivalent, screen-reader safe — no glyphs/emoji):

```
Round X/5 · N lenses · F fresh · dryStreak D/2 · budget B%
```

Written by the runtime/logger-agent after each round's journal entry. The round-1 emission also prints the lane-board (one line per lens: lens id + status + agent id or receipt id).

#### First-dry-round PENDING signal (MD-8)

When `dryStreak` first reaches 1 (the first dry round):

```
Round N dry (1/2) — one more clean round required
```

This signal does NOT stop the engine at K=1. The engine requires `dryStreak >= K` (K=2 floor) before crediting CLEAN; this is a progress indicator only.

#### Deterministic pre-pass + per-component cadence (MD-2)

Before any LLM fan-out, the active finderSet's declared deterministic lanes run as a **`--timeout 120s`-bounded labeled deterministic pre-pass** with per-gate progress ticks (one tick per lane as it completes).

Each deterministic lane declares one or more named sub-checks with per-component cadence via the formal schema:

```json
[{ "check": "<name>", "cadence": "per-round" | "pre-gate" | "post-fix" | "pre-gate+post-fix", "receiptId": "<lane>/<name>" }]
```

Valid `cadence` values: `"per-round"` (runs every round), `"pre-gate"` (runs once before LLM fan-out), `"post-fix"` (runs after each PARENT fix), `"pre-gate+post-fix"` (both pre-gate and post-fix but NOT between rounds — used for expensive sub-checks).

**`/5` lens-9 per-component cadence** (the split that a single monolithic cadence attribute would DROP):

```json
[
  { "check": "git-status",  "cadence": "per-round",          "receiptId": "9/git-status"  },
  { "check": "full-suite",  "cadence": "pre-gate+post-fix",  "receiptId": "9/full-suite"  }
]
```

**`/4` lane-6 per-component cadence:**

```json
[{ "check": "field-consumption", "cadence": "per-round", "receiptId": "6/field-consumption" }]
```

Output format (progress ticks, one per sub-check):

```
[deterministic pre-pass] lens-6 field-consumption ... PASS | lens-9 git-status ... PASS | lens-9 full-suite ... PASS (Ns)
```

Lens-9's git-check **EXCLUDES** the proof-sentinel and jsonl-audit paths (§2.2.4) so a sentinel write never triggers a false uncommitted-change block.

#### Survivor presentation (MD-4)

At discovery convergence (terminal = `FINDINGS` or `GAPS_FOUND`), survivors are presented **blocking-first** (highest-severity blockers listed before advisories). Each survivor is a **LINEAR text block** — no glyph/emoji status, no 2-D table:

```
[GAP-N] <title>
  Lens(es): <originating lens(es)>
  Corroboration: <N verifiers confirmed / M rounds persisted>
  Round: <first seen — round R>
  Refute-survived: <one-line note — e.g. "verifier confirmed real-gap after 2 refute attempts">
  Detail: <finding text>
```

This is the deliberate upgrade of Step 9.5's unstructured FAIL list: each item carries its provenance (lens origins), corroboration count, the round it first appeared, and a refute-survived note showing it was not accepted without challenge.

#### Coverage receipt (MD-10)

The per-round `coverageReceipt` field records that every lens in the finderSet is accounted-for against the current `scopeHash`. A `carried-forward` deterministic lens counts as covered only while its receipt's `scopeHash` still matches. Dry is credited only on a fully-covered round; a silently-skipped or errored lens also blocks dry.

#### Operator terminal reports (MD-9, MD-13)

The closing report names the three terminal states **distinctly** — so "no survivors shown" is never ambiguous between truly-dry and out-of-budget:

**`CLEAN`** (discovery converged, `effectiveOpen` empty, no open disagreements):
```
PROVE-GATE: CLEAN — K rounds dry, N findings resolved (M deferred to acceptedDeferrals ledger).
Shape: R rounds total, N found, N resolved, M deferred, D disagreements ruled/advisory.
Convergence path: <round-by-round summary>.
This is a materially better result, NOT a claim of provably 100% complete.
```

**`CAPPED`** (cap or budget hit before convergence — ALWAYS lists parked items; §9.6 item 4 escape-hatch):
```
PROVE-GATE: CAPPED — budget/round-cap reached before convergence.
Parked items (written to CT): <list of open dedupKeys + their lensStatus>.
Shape: R rounds, N found, P pending, D disagreements outstanding.
```

**`ERROR → fallback`** (gate-level exception — materialization errored, tool absent, or config failure):
```
PROVE-GATE: ERROR → fallback — <reason: config OFF | config PARSE-FAIL | tool absent | materialization ERRORED>
Falling back to existing parent-executed single-pass (Step 9.5).
```

For **report-only `/prove`**, a fourth terminal is added when the engine returns `FINDINGS`:

**`GAPS_FOUND`** (engine findings surfaced read-only, no fixing or re-invoking):
```
/prove: GAPS_FOUND — N survivors (report-only; no fixes applied).
<survivor list, blocking-first, provenance-tagged per MD-4>
```

The closing report is always a **"materially better" shape-report** (K rounds, N found, N resolved listed, M deferred, D disagreements ruled/advisory, convergence path). It **NEVER** claims "provably 100% done."

#### Proof-sentinel + jsonl-audit lifecycle (§10.2 item 7)

**Proof-sentinel file:**
- Path (implementer-chosen at install, recorded in config): e.g. `.claude/.prove-gate-sentinel`
- Format: a single-line JSON record — `{ "runId": "<id>", "terminal": "<CLEAN|CAPPED>", "scopeHash": "<hash>", "ts": "<iso8601>" }`
- The **PARENT** writes the sentinel after a passing gate (the engine never writes it; `/prove` neither creates nor reads it — MD-19).
- The sentinel is **DELETED** after the gate passes (sentinel-cleared pattern — a stale "PASSED" can never satisfy a future run). This closes the `--skip-squad` stub-VERDICT staleness loophole.
- Hand-back one-liner emitted by the PARENT on sentinel clear: `prove-gate audit logged; sentinel cleared`

**jsonl-audit line:**
- Path (implementer-chosen, recorded in config): e.g. `.claude/.prove-gate-audit.jsonl`
- Format: one appended line per gate run — `{ "runId": "<id>", "ts": "<iso8601>", "terminal": "<state>", "scopeHash": "<hash>", "lensCount": <active-finderSet-declared count>, "roundsRun": N, "found": N, "deferred": N }`
- The audit is **fail-open**: a hook bug or write failure NEVER hard-locks the session. The gate completes; the audit write is best-effort.
- Lens-9's git-check **EXCLUDES** both the sentinel path and the audit path from its uncommitted-change scan (so audit appends never trigger a false block).

Both the proof-sentinel and the jsonl-audit are SEPARATE from the run-journal (`subagents/workflows/<runId>/journal.jsonl`). The journal is runtime-written per-round; the sentinel and audit are PARENT-written at gate completion.

---

## 3. The 9-lens `/5` finderSet

This is the named `/5` finderSet. All nine lenses apply universally — no project-specific mechanisms are baked into the engine. The concrete mechanism (e.g., which DI-graph file, which test command) is supplied by the phase skill. Wakeful examples appear only as parentheticals.

**Each LLM lens is primed:** *"Prove this sprint is NOT fully done. Default to finding a gap."*

**`verifyLens` prompt:** *"Is this really an open gap, or is there evidence it's complete?"* — refute only; fresh context `{finding, scope}` only.

### Deterministic pre-passes

Lenses 6, 8, and 9 run as cheap deterministic checks BEFORE any LLM fan-out:
- Run ONCE as a pre-gate.
- Run AGAIN only after the parent applies fixes.
- Between fixes, their results **carry forward** as coverage for each round (while `scopeHash` matches).
- Lens 9 splits by cadence: the git-status component re-runs each round (cheap); the full-suite component runs only at pre-gate and post-fix (slow — the full suite is too expensive to repeat per round).
- A stale carried-forward receipt is invalidated the moment `scopeHash` changes.

### The 9 lenses

**Lens 1 — Plan-execution completeness (LLM)**
Was every task in the plan executed? Is each task evidenced by a commit, PASS, or tangible output? The phase skill supplies "the plan" (from the channel CT's plan pointer).

**Lens 2 — Acceptance-criteria evidence (LLM)**
Is each acceptance criterion mapped to a specific commit, PASS verdict, or output artifact? Unwitnessed criteria are gaps.

**Lens 3 — Decision propagation / spec drift (LLM)**
Is every brainstorm or design decision captured in a file AND reflected in code? A decision that appears in a spec but has no corresponding code change is a gap. A code change that contradicts a recorded decision is drift.

**Lens 4 — Orphaned / partial work (LLM)**
Are there mid-file TODOs, "mostly done" markers, dropped sub-bullets, half-finished stubs, or commented-out blocks that were meant to be completed? Partial work is a gap even if the file compiles.

**Lens 5 — Cross-file consistency (LLM)**
Are the sprint checklist (SC) and comprehensive implementation plan (CIP) reconciled? Is the manual-test queue up to date? Are there stale cross-references, mismatched version strings, or orphaned documentation sections?

**Lens 6 — Test-honesty (deterministic pre-pass)**
Does each new or changed test catch a *real* bug — or is it tautological, unguarded, or a hardcoded-copy that would pass against any implementation?

- Where a seam exists: run a source-assert + RED-on-revert check. A test that does not turn red when the behavior is reverted is tautological.
- Where no seam exists (inline logic): run a deterministic **mutate-and-run** check in a **throwaway worktree or temp copy** — never the primary tree, because mutating it would change `scopeHash` and the engine never writes product files. Mutate the inline logic, re-run the test. Still passing = tautological. NOT an LLM "does this hit the seam?" judgment — LLMs are negation-blind and cannot reliably answer this.
- Durable fix: create the seam (extract the helper) so the deterministic check applies going forward.

**Lens 7 — Runtime-wiring: constructor axis (LLM)**
Does the production dependency-injection graph actually inject the declared dependencies — or do unit mocks hide a dead graph?

Verified via the **project-provided DI-graph probe** (supplied by the phase skill, not baked into the engine). *Wakeful example: a live `ProviderContainer *Wired` non-null assertion against the production provider graph.* A mock-covered constructor graph looks wired but is not.

**Lens 8 — Runtime-wiring: call-site axis (deterministic pre-pass)**
Is each entry point actually reached, with its call-site source-asserted so that "deleting the block fails a test"?

Split from Lens 7 because call-site-only defects have no constructor field to null-assert — a single wiring lens is structurally blind to this class. Verified via the **project-provided entry-point probe** (supplied by the phase skill). *Wakeful example: ch15 GAP-A — the highest-severity gap, missed by a unified wiring lens.*

**Lens 9 — Committed-state / gate-integrity (deterministic pre-pass, scoped + triaged)**
Two sub-checks with different cadences:

- **git-status (re-runs each round):** Scoped to this channel's commit file-list. Own-channel uncommitted changes block. Foreign-channel WIP does NOT block — "any non-empty git status = blocking" is the naive form; it would false-block a healthy cross-channel `/5` where another channel's WIP legitimately sits in the tree.
- **Full-suite no-tag-exclusions run (pre-gate + post-fix only):** Triage required — own-channel failure blocks; cross-channel-WIP failure → align-forward-without-committing or surface a cross-channel design decision, never stall. The phase skill supplies the test command and the channel's commit file-list.

Targets the class the manual loop hit twice: own-channel uncommitted files and slow-tagged suite entries hidden by tag exclusions.

### FIX-B: DI-graph and entry points in `scopeContext`

The production DI-graph file(s) and entry-point modules MUST be included in `scopeContext` — without the live graph in scope, lenses 7 and 8 are toothless. The phase skill supplies these paths per-project; they are not baked into the engine.

---

## 3b. The 7-lens `/4` finderSet

This is the named `/4` finderSet. Runs once per touched data-model TYPE `M` (determined by the Phase 2.5 resolver in the `/4` skill). **Lenses 8 and 9 are ABSENT** — they are structurally N/A for `/4` because `/4` never commits and runs pre-commit: lens 8 (call-site wiring assertions that require "deleting the block fails a test") and lens 9 (committed-state / full-suite / git-status) both require a committed state that `/4` does not produce. They apply post-commit only (`/5`'s domain). A `/4` finderSet reader must see this rationale without leaving `## 3b`. `lensCount: 7`.

**finderSet declaration (read by the engine's lens-structure generalization):**
- `lensCount: 7`
- LLM lanes: `{1, 2, 3, 4, 5, 7}` — `model: sonnet` each
- Deterministic lane: `{6}` — per-component cadence: `[{ "check": "field-consumption", "cadence": "per-round", "receiptId": "6/field-consumption" }]`
- Deterministic count: 1 receipt per round

**Adversarial prime (LLM lanes 1–5, 7 only):** *"Prove that `M`'s wiring is NOT fully or correctly complete. Default to finding a gap. 'Looks wired' = look harder — grep the call sites, open the cited file, confirm the claim."* Lane 6 is deterministic and is NOT primed.

**Citation content-match obligation (LLM lanes):** Every finding citing a specific field, method, or file path MUST include a grep or Read artifact confirming the cited target was opened and the claimed content confirmed — never inferred from memory. A phantom citation (resolves-but-absent) is itself a finding. The PARENT must NOT assemble an unchecked LLM-lane claim into the artifact; if a lane emits a citation the PARENT cannot ground in a grep/Read, it is flagged as a phantom finding and treated as a live finding to fix.

**`verifyLens` refute prompt (domain-specific; runs in a FRESH AGENT/context — never the same session or context window as the finder; only `{finding, scope}` is passed in, never the finder's reasoning chain):**
*"Given {finding, type `M`, scope}: try to REFUTE — is this field truly dead? Is this fallback truly hiding a gap? Is this consumer truly missing? Default to REFUTED if the claim cannot be grounded in a grep/Read call on the cited target. Keep only survivors."*

**Post-fix requirement re-read:** After the PARENT applies each fix and before a finding is considered resolved, the PARENT re-reads the governing source/spec requirement for `M` (as resolved in the Phase-0 provenance record) and confirms the fix actually satisfies that requirement — not merely that the finder stopped re-discovering it. A fix that lands but does not satisfy the requirement is NOT resolved.

### The 7 lenses

**Lens 1 — `[D]` declared-not-consumed (LLM)**
A field, enum value, or method of `M` declared in the codebase but never read by any runtime consumer. Grep the project's source tree (`<src>` supplied by the phase skill) for read sites. A declaration with zero read sites is dead — FAIL.

*Adversarial prime applies. Per-type scope.*

**Lens 2 — `[F]` silent-fallback (LLM)**
A consumer swallowing `M`'s value with a `??` or `||` default that hides a wiring gap — `params['fieldX'] ?? 4` where no test confirms `M` declares `fieldX`. Grep consumers for `?? ` and `|| ` near each consumption site.

*Adversarial prime applies. Per-type scope.*

**Lens 3 — `[M-class]` missing-consumer + regression (LLM)**
A spec-required behavior of `M` with no code consumer — INCLUDING Phase-4(c): a whole spec feature with zero code declaration or consumer. Distinct from the run-level "source/spec unresolved" scoping error. Trace every spec requirement for `M` to a runtime component that READS and USES the field.

*Adversarial prime applies. Per-type scope.*

**Lens 4 — `[I]` incomplete-wiring (LLM)**
A partially-wired path for `M`: the type is declared, a consumer exists, but the data flow has a break — a field that is passed to a constructor but never stored, a parameter read once but never propagated downstream, a conditional that short-circuits before the value reaches the display layer.

*Adversarial prime applies. Per-type scope.*

**Lens 5 — `[T]` value-trace + test-only (LLM)**
Enumerate every numeric SOURCE claim governing `M` (duration, ratio, count, rate, threshold). Trace: source value → spec value → data-layer value → runtime value. **Each hop GROUNDED in an actual grep/Read call, never inferred from memory** (per `spec-verification.md` Phase 3). A consumed-but-WRONG-value field is a finding. Flag test-only fields (`[T]`).

*Adversarial prime applies. Per-type scope.*

**Lens 6 — field-consumption inventory (DETERMINISTIC)**
The FULL `[C]/[T]/[D]` per-field table for `M`. Procedure: recursive grep over the project's source and test trees for files in `M`'s language — the primary portable form is `find <src> <test> -name '*.<ext>' | xargs grep -l 'TypeName'` (POSIX `find | xargs grep`), where `<src>`, `<test>`, and `<ext>` are supplied by the phase skill for the project's language (e.g. `find lib test -name '*.dart'` for Dart, `find src test -name '*.ts'` for TypeScript) — executed via the skill's Bash tool on Git Bash/bash, NOT PowerShell; use `tr -d '\r'` for CRLF-tolerant output on Windows hosts. The `grep -r --include='*.<ext>'` form is also acceptable where supported (both GNU grep and BSD/macOS grep support `--include`; the `find | xargs grep` form is the primary for maximum portability). Then the per-instance second pass: for every `[C]` field on a type that can have multiple instances, enumerate EVERY instance and confirm the field value on each — not just one match. A missing value on any instance = silent default = finding.

*Deterministic — no adversarial prime. Per-component cadence: `{ "check": "field-consumption", "cadence": "per-round", "receiptId": "6/field-consumption" }`.*

**Lens 7 — source↔spec↔model drift + Phase-2 extraction (LLM)**
Emit the numbered Phase-2 flat-list of `M`'s source items with `[P]/[D]/[F]/[M]/[I]` counts (not only drift survivors — the FULL extraction). Flag drift between `M`'s primary SOURCE, governing spec, and current code shape. Both directions: source item → spec item AND spec item → source item. Either-side gap = FAIL.

*Adversarial prime applies. Per-type scope.*

### Inventory contract (full `spec-verification.md`-conformant payload)

"Compact" describes `## 3b`'s document length, NOT the emitted inventory schema. Every lane EMITS its full structured inventory payload — not only survivors. The assembled artifact MUST carry all `spec-verification.md` REPORT fields:

- **`[C]/[T]/[D]` per-field table** (from lens 6): every declared field, its status, consumers.
- **Value-trace ledger** (from lens 5): source claim → spec → data → runtime, per numeric value, each hop grounded in a grep/Read.
- **Phase-2 numbered bidirectional cross-reference** (from lens 7): source items ↔ spec items, both directions, with `[P]/[D]/[F]/[M]/[I]` counts and Phase-5 summary counts (source total, spec total, code-only count).
- **Phase-0 provenance** (from the resolver, not from lanes): `{ type, sourceMaterialPaths[], governingSpecPath }` — written as the audit's mandatory source-identification section.

The PARENT assembles from lane inventories + resolver Phase-0 provenance. Lanes 1–5, 7 = LLM (`model: sonnet`); lane 6 = deterministic. No severity scale.

### Shared-field merge rule

When N types share a field across per-type inventories, the merged assessment is `[C]` if consumed by ANY consumer, `[T]` if only test consumers across all, `[D]` only if dead across ALL types.

---

## 3c. The 5-lens `/3` finderSet

This is the named `/3` finderSet — the lenses the ENGINE runs **only at the checkpoint** (a commit-group / phase boundary, FIRED BY THE SKILL, never by the engine mid-task). It adapts the `/5` lenses (`## 3`) to **pre-commit, build-time** verification. It is **NOT** the per-task verify: the per-task skill stage runs only the deterministic lanes `{4,5}` + cheap gates (`/3` skill, §3.4 of the design). `lensCount: 5`. Lenses are universal; concrete mechanisms (test command, source tree, consumer grep, diff-scan) are **supplied by the build skill** (the `build-gates` config key) — no language/framework-isms in the engine.

**Lens-exclusion rationale (a `## 3c` reader sees why `lensCount` is 5 without leaving `## 3c`):** the set is deliberately smaller than `/5`'s 9 and `/4`'s 7. `/5`-only lenses are **N/A pre-commit** and owned downstream: full plan-execution completeness, cross-file SC/CIP reconciliation, committed-state/full-suite, and call-site entry-point reachability all require a committed state or a sprint-scale scope that `/3` (pre-commit, commit-group scope) does not have. `/4`'s per-type fan-out is also absent (`/3` verifies a commit-group, not a touched-TYPE set). These belong to `## 3b` (`/4`), `## 3` (`/5`), and the commit-time `commit-adversarial`+`commit-cold-reader` pair. The checkpoint LLM pass `{1,2,3}` is a deliberately modest **shift-left lighten-`/4` tripwire**, NOT a replication of `/4`'s or `/5`'s depth.

**finderSet declaration (read by the engine's lens-structure generalization):**
- `lensCount: 5`. The ENGINE runs this finderSet as a single 5-lens loop-until-dry **only at the checkpoint**, where all 5 are accounted-for per round — `{4,5}` run FRESH as deterministic pre-passes + `{1,2,3}` as LLM fan-out (exactly how `/5` runs `{6,8,9}` deterministic + `{1-5,7}` LLM in ONE finderSet). There is NO per-task engine invocation; a per-task run of only `{4,5}` could never cover the 5-lens set, so it would never be an engine round.
- LLM lanes: `{1, 2, 3}` — `model: sonnet` each. They run **only in the checkpoint engine loop** (never per-task, never as a skill-layer pre-pass).
- Deterministic lanes: `{4, 5}` — engine per-component cadence `[{ "check": "test-honesty", "cadence": "per-round", "receiptId": "4/test-honesty" }]` / `[{ "check": "consumer-preflight", "cadence": "per-round", "receiptId": "5/consumer-preflight" }]` (the per-component cadence schema, `## 2.2` MD-2). The engine re-runs these checks FRESH at the checkpoint; they are NOT carried-forward receipts pre-computed elsewhere. The skill-layer per-task execution of the same `{4,5}` checks is a SEPARATE shift-left pass (catch-and-fix at the task) that feeds NOTHING into the engine round. **receiptIds are namespaced to lanes 4 and 5 respectively — NOT `6/…`: the `/5` lens-6 namespace would collide and corrupt `## 6.3`/`## 6.4` stale-receipt handling for the `{4,5}` set.**
- Deterministic count: 2 receipts per round.
- Excluded vs `/5`: plan-completeness, cross-file SC/CIP reconcile, call-site entry-point reachability, committed-state/full-suite — N/A pre-commit; owned downstream (rationale above).

**Adversarial prime (LLM lanes 1–3 only, checkpoint engine loop over the commit-group):** *"Prove this commit-group is NOT correctly or completely done. Default to finding a gap. 'Looks done' = look harder — open the cited file, grep the call sites, confirm the changes against the commit-group's acceptance criteria."* Lanes 4 and 5 are deterministic and are NOT primed.

**Citation content-match obligation (BOTH tiers):** Every finding citing a specific field, method, or file path MUST include a grep/Read artifact confirming the target was opened and the content confirmed — never from memory. A phantom citation (resolves-but-absent) is itself a finding. The PARENT must not act on an unchecked claim; an ungroundable citation is flagged as a phantom and treated as a live finding. This applies to the checkpoint LLM lanes AND the per-task deterministic tier (where citations are grep-results).

**`verifyLens` refute prompt (domain-specific; FRESH AGENT/context — never the finder's session or chain; only `{finding, scope}` passed in, per `## 1.1` Rule 7):** *"Given {finding, commit-group scope}: try to REFUTE — does the diff actually satisfy this criterion? Is this really drift, or did the plan authorize it? Is this TODO actually load-bearing, or a benign note? Default to REFUTED if the claim cannot be grounded in a grep/Read on the cited target. Keep only survivors."*

### The 5 lenses

**Lens 1 — Acceptance-criteria-met (LLM)**
Does the commit-group's produced code satisfy the acceptance criteria for every task in the group, *evidenced*? Each criterion must map to a specific change in the diff that satisfies it; an unwitnessed or hand-waved criterion is a gap. (Adapts `## 3` lens 2, scoped to the **commit-group**.)

*Adversarial prime applies. Commit-group scope. Checkpoint engine loop ONLY (never per-task).*

**Lens 2 — Spec-drift (LLM)**
Did any implementer in the commit-group deviate from the task's spec/plan intent? A change that contradicts a recorded decision, silently broadens scope, or substitutes a different approach than the plan specified is drift. (Adapts `## 3` lens 3, scoped to the **commit-group**.)

*Adversarial prime applies. Commit-group scope. Checkpoint engine loop ONLY.*

**Lens 3 — No-orphan / partial-work (LLM)**
Does the commit-group leave mid-file TODOs, "mostly done" markers, dropped sub-bullets, half-finished stubs, commented-out blocks, or provisional defaults never revisited? Partial work is a gap even if the files compile. The checkpoint lens catches **undeclared** orphans; the per-task deterministic pass surfaces **declared** ones (the result-file `todos[]`/`deferrals[]`). (Adapts `## 3` lens 4, scoped to the **commit-group**.)

*Adversarial prime applies. Commit-group scope. Checkpoint engine loop ONLY.*

**Lens 4 — Test-honesty (DETERMINISTIC)**
Does each new/changed test catch a *real* bug, or is it tautological/unguarded/hardcoded-copy? **Where a seam exists:** source-assert + RED-on-revert. **Where no seam exists (inline logic):** deterministic **mutate-and-run** in a **throwaway worktree/temp copy** — never the primary tree (the engine never writes product files, and a primary-tree mutation would change `scopeHash`). Still passing after mutation = tautological. NOT an LLM "does this hit the seam?" judgment. **Identical mechanism to `## 3` lens 6 / `## 3b` lane 6** — mutate the inline logic in a temp copy, re-run the task's test, still-passing = tautological, clean up the temp; never the primary tree. *Note on "read-only":* the verifier stage is read-only with respect to product files; the throwaway worktree/temp copy (seeded from the primary tree, discarded after the run) is an internal instrument of the check, not a product artifact — the primary tree is never modified.

*Deterministic — no adversarial prime. Engine per-component cadence: `{ "check": "test-honesty", "cadence": "per-round", "receiptId": "4/test-honesty" }`. At the checkpoint the engine's receipt is keyed to the PRIMARY-tree `scopeHash`; the throwaway worktree is used only for the mutate-and-run. The skill ALSO runs this check per-task as a shift-left check — that per-task run is NOT carried forward as a receipt; the checkpoint engine re-runs it FRESH. The engine cadence value is `per-round`; "per-task" is the skill-layer execution, never an engine cadence value.*

**Lens 5 — Data-model-consumer pre-flight (DETERMINISTIC)**
The build skill's grep-every-consumer rule (`build/SKILL.md` § Procedure step 2 "Data model pre-flight"), promoted from producer self-advice to a **fresh-read deterministic check**: if this task adds/removes/renames/retypes/changes-the-default-of a field on a data model, grep EVERY consumer of that field name across the project's source + test trees (forward-slash include patterns; `tr -d '\r'` CRLF-tolerant; portable `find <src> <test> -name '*.<ext>' | xargs grep -l` form, `<src>`/`<test>`/`<ext>` supplied by the skill via `build-gates`). Confirm every matching consumer reads the same name with **no silent fallback** (`?? `/`|| `) substituting a default. A silent-fallback consumer of a changed field is a gap. **The task diff is the AUTHORITATIVE source of changed-field detection** (via the skill-supplied `diffScan` mechanism): the producer's `changedFields[]` is a **declaration the verifier cross-checks** — a field-change evident in the diff but absent from `changedFields[]` is **itself a FAIL** (under-declaration). The skill greps consumers of the **union** of diff-detected and declared field names. This reuses the **deterministic consumer-grep mechanism** — the silent-fallback `?? `/`|| ` grep over every consumer, akin to `## 3b` lane-6's deterministic shape — **NOT** `## 3b` lane-2's LLM silent-fallback prompt (a `model: sonnet` judgment lane); `/3`'s lens 5 is DETERMINISTIC and runs the grep procedure. It is the per-task, shift-left twin of the silent-fallback check, caught at the task that changed the field, not at `/4`.

*Deterministic — no adversarial prime. Engine per-component cadence: `{ "check": "consumer-preflight", "cadence": "per-round", "receiptId": "5/consumer-preflight" }`. The skill ALSO runs this per-task as a shift-left check; that per-task run is NOT carried forward as a receipt — the checkpoint engine re-runs it FRESH over the commit-group scope. The engine cadence value is `per-round`; "per-task" is the skill-layer execution, never an engine cadence value.*

### Empty-candidate behavior (deterministic lanes 4/5 — trivially covered, NOT a FAIL, NOT a silent skip)

A deterministic lane with no work still emits a **PASS with a receipt** so the round's coverage is witnessed (a silent skip would leave the engine's coverage model unable to distinguish "ran and found nothing" from "never ran"):
- **Lens 4 (test-honesty), no changed tests** ⇒ trivially-covered PASS with a receipt (`4/test-honesty`, zero candidates).
- **Lens 5 (consumer pre-flight), no changed data-model fields** (`changedFields[]` empty AND no field-change in the diff) **OR zero consumer matches** ⇒ trivially-covered PASS with a receipt (`5/consumer-preflight`, zero candidates).
- **Absent `build-gates` config** (or an absent `gates` sub-list) ⇒ the cheap-gate tier degrades to lenses 4/5 only with the skill-default `src`/`test`/`ext`; the lane is trivially-covered, never a PARSE-FAIL and never a silent skip.
In every case the receipt records the empty candidate set explicitly.

### File-handoff schemas — result-FILE and verdict-FILE (the Rule-10 spine)

Both are JSON, schema-validated under the schema-validation-as-FAIL discipline (`## 1.1` / `## 2` / `## 2.2` — a missing/malformed file = a finding, never a silent pass). The parent orchestrates from THEM, never from a held summary.

**Paths / lifecycle (the selftest discovers these):** all artifacts live under the per-run `verification_findings/build_pipeline[_chN]/` directory (the `_chN` channel suffix mirrors the squad-dir convention):
- **result-FILE** — `verification_findings/build_pipeline[_chN]/<taskId>.result.json` (one per task; written by PRODUCE).
- **verdict-FILE** — `verification_findings/build_pipeline[_chN]/<taskId>.verdict.json` (per-task); `verification_findings/build_pipeline[_chN]/checkpoint-<group>.verdict.json` (checkpoint engine, `taskId: 'checkpoint:<group>'`).
- **pipeline-log** — `verification_findings/build_pipeline[_chN]/pipeline-log.jsonl` (one append-only log per `/3` run; the globally-monotonic `seq` ordering substrate).
All three are **overwritten per `/3` run** and **cleaned at `/cleanup`** (never committed — working-state under `verification_findings/`).

**Result-FILE schema (the PRODUCE stage writes this; the verifier reads it):**

```json
{
  "taskId":        "<plan-task id>",          // required
  "classification": "SONNET | OPUS | PARENT", // required
  "filesWritten":  ["<path>", ...],           // required — paths the producer wrote
  "acceptanceCriteria": [                       // required, MUST be non-empty — when the plan task has no explicit Acceptance field, the skill synthesizes the task description text as the single criterion and writes it HERE (NOT left as []), so the result-FILE, the verifier input, and the surfaced criteriaChecked[] all agree (the synthesized fallback is materialized into the result-FILE, never diverging between channels)
    { "criterion": "<text>", "satisfiedBy": "<diff ref: file + the change that satisfies it>" }
  ],
  "changedFields": [ "<field name added/removed/renamed/retyped on a data model>", ... ], // required (may be [] if the task changes no data-model field) — a DECLARATION the verifier cross-checks against the diff; a field-change visible in the diff but absent here = FAIL (under-declaration); lens 5 greps consumers of the union (diff-detected ∪ declared)
  "deferrals":     [ "<provisional decision / parked item>", ... ],  // optional
  "todos":         [ "<TODO / partial-work note>", ... ],           // optional
  "diffScope":     "<the git-diff range / file set for this task>",  // required
  "baselineRef":   "<the git stash create object id captured by the parent at PRODUCE(N) start>"  // required — the PERSISTED per-task baseline; a resumed /3 reconstructs `git diff <baselineRef>` (full + path-scoped) from this rather than falling back to cumulative HEAD. Written by the PARENT (the parent owns baseline capture), not the producer
}
```

The producer's prose claims are **inputs to verification, never a license to proceed**. `deferrals`/`todos` being non-empty is a signal the orphan/no-orphan lens (lens 3, at the checkpoint) and the strictly-execution discipline act on: a non-empty `todos[]` is a build-execution gap the parent FIXES; a non-empty `deferrals[]` is a `/2`-incompleteness that HALTS the loop and returns to `/2` — `/3` never carries either forward as a provisional default.

The two tiers write **two DIFFERENT verdict files** — they do NOT share one schema. Each is pinned separately: the **per-task verdict-FILE** carries the per-task `PASS | FAIL | RETURN_TO_2` enum + the producer-surfaced fields; the **checkpoint verdict-FILE** carries the engine's `CLEAN | FINDINGS | CAPPED` terminal + the survivor findings, and has NO per-task verdict enum and NO single `declaredIncomplete` (the checkpoint has no single producer to copy partial-work from). Conflating them was the prior defect.

**Per-task verdict-FILE schema (`<taskId>.verdict.json` — the per-task skill verifier writes this; the parent reads it):**

```json
{
  "taskId":   "<plan-task id>",                          // required
  "verdict":  "PASS | FAIL | RETURN_TO_2",               // required — PASS / FAIL (build-execution gap, parent fixes) / RETURN_TO_2 (design-decision-gap, /2 incomplete → halt + return to /2); no benign WARN tier (/3 = strictly execution). This enum is PER-TASK ONLY — the checkpoint engine does NOT use it (it has its own `terminal` field below)
  "findings": [                                           // required (may be [])
    {
      "source":   "<lens-<n> | gate-<name>>",            // required — a lens finding ("lens-4"/"lens-5") OR a non-lens cheap-gate failure ("gate-analyze"/"gate-format"/"gate-test"); a cheap-gate failure has no lens id and uses the gate-<name> form
      "severity": "FAIL | WARN | HIGH | MEDIUM | LOW | INFO",  // required — enum
      "address":  "<symbolic addr>",
      "issue":    "<text>",
      "citation": "<grep/Read artifact>"
    }
  ],
  "criteriaChecked": [                                   // required, MUST be non-empty — the acceptance criteria SURFACED into the verdict for the parent's record; the SAME criterion set as the result-FILE's `acceptanceCriteria[]` copied through verbatim, so it inherits that field's non-empty guarantee (`acceptanceCriteria[]` is itself MUST-be-non-empty — synthesized from the task description when no explicit Acceptance field exists), so an empty `criteriaChecked[]` is a schema violation, never the no-criteria case. The per-task verifier does NOT score these (acceptance-criteria-met is a checkpoint LLM lens), so per-task `met` is recorded as the producer's claim verbatim
    { "criterion": "<text>", "met": true, "evidence": "<diff ref / grep-Read artifact>" }
  ],
  "declaredIncomplete": {                                 // required — the producer's self-declared partial work, surfaced from the result-FILE (a deterministic read, no LLM judgment)
    "todos":     [ "<TODO / partial-work note>", ... ],   // copied from the result-FILE todos[]
    "deferrals": [ "<provisional decision / parked item>", ... ]  // copied from the result-FILE deferrals[]
  },
  "scopeHashChecked": "<the scopeHash the verdict was computed against>"  // required — a content digest over task N's filesWritten[] (deferral-ledger and audit writes excluded, mirroring ## 6.1 exclusions), computed by the PARENT at the PRODUCE(N)→VERIFY(N) handoff using the same content-digest function the engine uses (## 6)
}
```

The per-task verdict-file carries a flat `PASS | FAIL` plus the halt-return-to-`/2` signal (the per-task verifier is a single read-only deterministic pass — no engine terminal; `/3` is strictly execution, so there is no benign WARN-and-continue tier). The `criteriaChecked[]` and `declaredIncomplete` fields are the surfaced-data channel the §5 rollup reads. The parent reads the verdict-FILE — **never a held summary** — and rejects any verdict-file whose `scopeHashChecked` does not match the tree VERIFY actually ran against.

**Checkpoint verdict-FILE schema (`checkpoint-<group>.verdict.json` — the checkpoint engine writes this; the parent reads it). This is a DISTINCT schema from the per-task verdict-FILE — it carries the engine TERMINAL, NOT the per-task verdict enum:**

```json
{
  "taskId":   "checkpoint:<group>",                      // required — the synthetic checkpoint id, never a plan-task id
  "terminal": "CLEAN | FINDINGS | CAPPED",               // required — the ENGINE's two-level terminal (## 1.3); there is NO `verdict: PASS|FAIL|RETURN_TO_2` field here (that enum is per-task only). The parent reads THIS field for checkpoint state
  "findings": [                                           // required (may be []) — the engine's surviving findings for this terminal; same finding shape as the per-task verdict's findings[] (source / severity / address / issue / citation)
    {
      "source":   "<lens-<n> | gate-<name>>",
      "severity": "FAIL | WARN | HIGH | MEDIUM | LOW | INFO",
      "address":  "<symbolic addr>",
      "issue":    "<text>",
      "citation": "<grep/Read artifact>"
    }
  ],
  "criteriaChecked": [                                   // required, MUST be non-empty — at the checkpoint, the acceptance-criteria-met LLM lens (lens 1) records the EVIDENCED result (not a producer claim): `met` is the lens verdict, `evidence` the grep/Read artifact. Scoped to the commit-group's tasks; non-empty because every task in the group carries a non-empty `acceptanceCriteria[]` (the result-FILE guarantee), so the union the lens scores is always non-empty
    { "criterion": "<text>", "met": true, "evidence": "<diff ref / grep-Read artifact>" }
  ],
  "scopeHashChecked": "<the engine's full-scope scopeHash>"  // required — the full-scope scopeHash the engine validated at the terminal boundary (## 6.2), NOT a per-task digest
}
```

The checkpoint verdict-FILE has **no per-task `verdict` enum and no single `declaredIncomplete`** — a `checkpoint:<group>` output has no single producer/result-file to copy partial-work from, so those per-task-only fields are absent by construction. The parent reads the checkpoint's `terminal` field (`CLEAN`/`FINDINGS`/`CAPPED`) and dispatches per §5; the checkpoint engine's per-round survivor list conforms to the `findings[]` shape above. The per-task tier has a `verdict` and the parent acts on `PASS/FAIL/RETURN_TO_2`; the checkpoint tier has a `terminal` and the parent acts on `CLEAN/FINDINGS/CAPPED`.

---

## 4. The opt-in / fallback / budget gate

### 4.1 Gate pseudocode

```
gate(phase, finderSet):
  if config file absent:                                          # universal default
      FALLBACK; banner "reason: config OFF"; return
  parse config under schema (see §4.3 config-read semantics)     # PARSE BEFORE evaluating enabled —
  on a required key missing/malformed:                           #   a present-but-broken file must not
      auto-retry the parse; if it still fails:                   #   read as "OFF"
          FALLBACK; banner "reason: config PARSE-FAIL"; return   # NOT silent OFF
  if workflows_enabled == false OR phase not in enabled-phases:
      FALLBACK; banner "reason: config OFF"; return
  if Workflow tool not available (live ToolSearch select:Workflow probe — see §4.5 caveat):
      FALLBACK; banner "reason: tool absent"; return
  try: materialize adversarial-loop from the proc-doc + launch it with finderSet args
  on materialization / launch-denied / no-op / run ERROR:        # the R4 tell — distinct, LOUD
      FALLBACK; banner "reason: materialization ERRORED (<sub: errored | launch-not-approved | no-op>)" + jsonl pointer; return
  hand { found, disagreements, pending, terminal, journalArtifact, scopeHash } to the PARENT fix-loop
  # full tuple — CAPPED reports MUST include `pending`
```

**Every branch `return`s.** FALLBACK = the existing parent-executed single-pass (decision D2), loud-bannered with its reason. The gate is invoked model-side, in the markdown proc, pre-invocation — before any workflow script runs.

**Gate order** (canonical): `absent → OFF; else PARSE FIRST → broken-key = PARSE-FAIL; else disabled/phase-not-listed → OFF; else tool absent → fallback; else materialize+launch → error/launch-denied/no-op → fallback.` Parsing precedes the enabled check so a present-but-broken config cannot masquerade as OFF.

### 4.2 Two independent signals

The gate requires two INDEPENDENT signals. Neither alone is sufficient:

- **Intent = config file** `.claude/reference/workflows-config.md`, carrying `workflows_enabled: false` (default OFF) **plus the engine tunables an env var cannot hold** (`dryRounds`/K, `maxRounds`, budget in both rounds and spend, `enabled-phases`, `budgetGuard`), parsed under JSON-schema discipline. One cross-platform `Read` carries the whole knob-set; file-absent / key-false = OFF. (A config file beats an env var on three real deltas: cross-platform-identical syntax, always-present, schema-parse discipline.)
- **Availability = a mandatory live Workflow-tool probe** (`ToolSearch select:Workflow`). An intent flag can never answer "does this harness expose the tool." Both signals run **model-side, pre-invocation** — the "tool absent" branch is unevaluable from inside a JS workflow.

**Env var `SENTINEL_WORKFLOWS`** is at most an **optional convenience override** of the file's `workflows_enabled` key — never the primary mechanism.

### 4.3 Config-read semantics (three distinct cases)

Resolves the absent-vs-malformed ambiguity:

(a) **File absent OR `workflows_enabled: false`** → `config OFF`. The universal default: a user who never created the file gets today's single-pass behavior. The mandatory top-of-output banner still prints (per §4.4), but this is the expected, quiet case.

(b) **File present; a required key missing/malformed** → schema FAIL + auto-retry (JSON-schema discipline). If it still fails after retry: log + fallback bannered `config PARSE-FAIL`. Do NOT silently default to OFF — a half-written config must not look like "off."

(c) **Parse otherwise fails** → log + fallback bannered `config PARSE-FAIL`.

Config keys (exact, from the shared naming contract): `workflows_enabled` (default `false`), `dryRounds` (alias K; floor 2), `maxRounds` (must be ≥ `dryRounds` — if `maxRounds < dryRounds`, CLEAN is unreachable; reject at parse), `budget` (rounds AND spend), `enabled-phases` (default `["/5"]`), `budgetGuard`, `fanoutTypeCap` (optional int, default 8; the maximum touched data-model TYPE count for `/4` Phase 2.5; absent → 8 without PARSE-FAIL), `build-gates` (optional nested object `{ src, test, ext, diffScan?, gates: [{name, cmd}] }` supplying the `/3` per-task verify mechanisms; absent → skill defaults, malformed → graceful-default-with-warning, never PARSE-FAIL). Config file path: `.claude/reference/workflows-config.md`.

### 4.4 Mandatory path banner (MD-1)

The path banner is **mandatory and top-of-output** on EVERY run:

- **Engine path:** `PROVE-GATE: engine path (<active finderSet lens count> lenses, K=2, max 5)`
- **Fallback path:** `FALLBACK single-pass — reason: <config OFF | config PARSE-FAIL | tool absent | materialization ERRORED>`

Exactly **four banner reasons**:
1. `config OFF` — file absent, or `workflows_enabled: false`, or `phase not in enabled-phases`.
2. `config PARSE-FAIL` — file present but a required key is missing/malformed and auto-retry failed.
3. `tool absent` — Workflow tool not available per the live probe.
4. `materialization ERRORED` — the R4 tell; carries a jsonl pointer. Its silence on a misconfigured install is itself the tell that the workflow flag never flipped.

`materialization ERRORED` is the louder R4 tell because a silent no-op on a broken installation would appear identical to `config OFF`. The jsonl pointer lets operators inspect why the materialization failed.

**Two fallback tiers:**
- **MANDATORY automatic degradation** for ANY gate-skip = the **existing parent-executed single-pass** (today's Step 9.5) — simple, zero-change, the D2 guarantee. This is the per-invocation default for all four banner reasons.
- The richer **parent-executed 9-lens loop** (Opus hand-spawns lenses across rounds) is a *second, opt-in* degradation an operator may choose if materialization proves chronically unreliable (discovered via `/prove --selftest`); it is a **deferred build item, out of beachhead scope** (§10.2), NOT the automatic per-invocation degradation.

### 4.5 Harness-level disable and launch-approval notes

**Harness-level disable is separate from intent.** `CLAUDE_CODE_DISABLE_WORKFLOWS=1` / `disableWorkflows: true` in managed settings make the Workflow tool unavailable regardless of `workflows_enabled: true` in the config file. This is caught by the **availability probe**, not the intent flag, and surfaces as the banner reason `tool absent`.

**⚠ ToolSearch-probe is an UNVERIFIED availability signal.** Whether `ToolSearch select:Workflow` reliably returns the tool schema when workflows are enabled (and nothing when disabled) is not documented. A false-absent probe would cause a silent fallback on a capable harness. Fallback option (to validate during controlled dry-runs): attempt a no-op materialization and catch the error rather than relying solely on the probe.

**Launch approval (permission mode).** Skill-instruction authorizes *attempting* a Workflow call, but depending on permission mode Claude Code may surface a per-run approval prompt. A denied or cancelled launch is treated as a **materialization error** (loud fallback, `materialization ERRORED` banner + jsonl pointer), never a silent hang.

### 4.6 Full-tuple handoff to the PARENT fix-loop

On success, the gate hands off to the §5 PARENT fix-loop the complete six-field engine return tuple:

```
{ found, disagreements, pending, terminal, journalArtifact, scopeHash }
```

`pending` MUST be included in CAPPED reports. `scopeHash` is the value the engine validated at the terminal boundary. This is the same tuple defined in §1.4 — the gate and the engine use the same six-field contract; no field is omitted at the handoff boundary.

---

## 5. PARENT fix-loop

The PARENT owns ALL writes. The PARENT fix-loop bounds the TOTAL gate across all engine re-invocations.

```
PARENT fix-loop:

  // acceptedDeferrals is a durable ledger, persists across re-invocations
  // keyed by: dedupKey + STABLE per-finding evidence hash + approval-evidence
  // NOT keyed by whole-scope scopeHash (which churns every fix)

  loop:

    // parent computes scopeHash before each engine invocation
    scopeHash = compute_working_tree_content_digest(in_scope_paths, tracked_dirty_content,
                                                    untracked_generated, CT_spec_plan_text,
                                                    diff_payload)
    // deferral-ledger writes excluded from the digest

    { found, disagreements, pending, terminal, journalArtifact, scopeHash }
      = invoke ENGINE(scopeContext, scopeHash, finderSet, ...)
      // seen/found/pending RESET on each fresh re-invoke (MD-7)

    switch terminal:

      CLEAN:
        // engine found nothing; check whether deferrals explain any prior gaps
        report operator-CLEAN (list acceptedDeferrals in the closing report)
        DONE

      CAPPED:
        // cap or budget hit — HALT; never re-invoke after CAPPED
        write { found, disagreements, pending } + diagnostics → CT
        report operator-CAPPED (always list parked items — escape-hatch, §9.6 item 4)
        HALT

      FINDINGS:
        // converged but gaps remain — the ONLY terminal that drives fix + re-invoke
        effectiveOpen = found − acceptedDeferrals
                        // matched by dedupKey + UNCHANGED per-finding evidence hash

        if effectiveOpen empty AND disagreements empty:
          // only accepted deferrals remained; do not re-litigate
          report operator-CLEAN (list carried acceptedDeferrals)
          DONE

        else:
          // resolve each item in effectiveOpen
          for each gap in effectiveOpen:
            either: fix it (auto-fix mechanical gaps; confirm-only genuine forks/deferrals)
            or:     record a NEW acceptedDeferral keyed by:
                      dedupKey + per-finding evidence-hash + approval-evidence
          // MD-5 investigation for disagreements (see §7)
          for each d in disagreements:
            run bounded investigation (§7)
          recompute scopeHash (a fix changed the tree)
          continue → RE-INVOKE engine FRESH (seen/found/pending reset)

    // circuit-breaker — PARENT level, across fix-cycles, by IDENTITY not count
    no-progress: across 2 fix-cycles, NO open identity (dedupKey) was resolved/deferred
                 AND no new evidence changed
                 → report operator-CAPPED; HALT
                 (a count-only test false-trips when item A is fixed as item B newly appears)

    thrash: the same dedupKey re-survives after an attempted fix
            → run MD-5 investigation (§7); then escalate to operator-CAPPED

    if budgetGuard low (rounds OR spend):
      write unresolved → CT
      report operator-CAPPED
      HALT
```

### 5.1 Fix-loop correctness notes

**`CAPPED` is a HALT — never re-invoked.** Only `FINDINGS` (converged, gaps remain) drives a fix + fresh re-invocation. `CAPPED` writes parked items to CT and stops, so `maxRounds` and budget actually bound the gate. The operator never sees `FINDINGS` as a `/5` terminal.

**`effectiveOpen` determines operator-CLEAN, not raw `found`.** Accepted deferrals don't block CLEAN; an unapproved gap cannot be silently dropped. A deferred gap, re-found on a fresh pass, closes (matched by `dedupKey` + UNCHANGED evidence hash) instead of re-litigating.

**Circuit-breaker identity-comparison.** The `no-progress` check compares open IDENTITIES (dedupKeys) across 2 fix-cycles, not the raw count. This prevents false-trips when item A is fixed as item B newly appears (the "$47k-class burn" pattern: a loop with a completion signal but no no-progress signal).

**Thrash** = the same `dedupKey` re-surviving after an attempted fix. Routes to the MD-5 investigation (§7) before escalating.

**Writes stay single-threaded.** Only the parent Opus may write product files, fixes, deferrals, and MD-5 corrections. The engine is read-mostly; a workflow cannot spawn grill/investigation subagents (subagents cannot spawn subagents).

### 5.2 Open-findings running set + `acceptedDeferrals` ledger

**`open` running set (PARENT, across fix-cycles):**

```
open = (found ∪ disagreements ∪ pending across fix-cycles, by dedupKey) − acceptedDeferrals
```

The `no-progress` circuit-breaker compares open **IDENTITIES** (dedupKeys), not `|open|`, across cycles. A count-only test false-trips when item A is fixed while item B newly appears.

**`acceptedDeferrals` ledger:**

- **Keyed by:** `dedupKey + STABLE per-finding evidence/content hash (the specific files/lines the finding concerns) + approval-evidence`
- **NOT keyed by** the whole-scope `scopeHash`, which churns on every fix and would re-litigate every deferral on the next re-invoke.
- **Deferral-ledger and audit writes are EXCLUDED from `scopeHash`** — a deferral record can never invalidate the receipts it's associated with.
- **Unchanged-evidence same-key item:** if the per-finding evidence hash is UNCHANGED across a re-invocation, the item is treated as resolved-for-this-gate and **LISTED** in the CLEAN report. It does NOT re-block.
- **Changed evidence:** if that finding's evidence changes (the files/lines it concerns are edited), the item **reopens** and must be re-evaluated.
- **Unapproved park:** a finding that was neither fixed nor given explicit operator approval is **CAPPED**, not deferred. A gap cannot be silently dropped by omitting it from the ledger.

**Operator-CLEAN depends on `open` empty, not raw `found` empty.** Accepted deferrals don't block CLEAN; an unapproved gap cannot be silently dropped.

### 5.3 MD-6 behavioral rule + MD-7 cross-invocation tally

**MD-6 — Auto-fix vs confirm:**

> Auto-fix mechanical, unambiguous gaps (a missed SC checkbox, a stale ref, an un-propagated decision-into-a-file) and report after — no confirmation needed. CONFIRM only deferrals and genuine forks (operator decision required before recording an `acceptedDeferral`).

This governs WHEN the gate pauses for operator confirmation vs auto-proceeds. Mechanical gaps are fixed silently and reported in the tally (MD-7). Only recording an `acceptedDeferral` or resolving a genuine design fork requires an explicit operator decision.

**MD-7 — Cross-invocation tally (PARENT loop progress display):**

At each re-invocation of the ENGINE the PARENT emits:

```
Round N of <=M — re-running after K fixes; seen F | resolved R | deferred D | dry-streak S/2
```

This is the **parent-loop** progress display, tracking cumulative state across ALL engine re-invocations. It is **DISTINCT from the per-round engine heartbeat** (MD-3, `## 2.2`), which tracks discovery state within a single engine invocation. Both are required; neither substitutes for the other.

Fields: `N` = current re-invocation number; `M` = maxRounds (config); `K` = fixes applied since the last invocation; `F` = total findings seen across all invocations; `R` = resolved (fixed or closed by deferral match); `D` = deferred to `acceptedDeferrals`; `S/2` = current dry-streak vs. required K.

---

## 6. `scopeHash` lifecycle + stale-receipt rejection

### 6.1 Definition

**`scopeHash`** is a **working-tree CONTENT digest** over the resolved in-scope snapshot:

- The in-scope path set + their **tracked-but-dirty content** (uncommitted edits)
- **Relevant untracked/generated files** (generated sources, build artifacts the engine runs over)
- The **CT/spec/plan text** (state files, the authoritative plan, relevant specs)
- The **diff payload** (the `git diff` since session-start)

A bare git tree hash is **too narrow** — it misses uncommitted edits, untracked files, and generated state the engine actually observes. `scopeHash` must capture everything the engine's lens prompts can read; a tree hash cannot.

**Excluded from the digest:**

- **Deferral-ledger writes** (new `acceptedDeferrals` entries, ledger append-only writes)
- **Audit writes** (jsonl-audit appends, proof-sentinel file)

These writes are PARENT-owned bookkeeping; including them would churn `scopeHash` on every fix and would re-litigate every carried receipt after a deferral record — defeating the purpose of a stable receipt.

### 6.2 Compute / recompute lifecycle

**PARENT computes per engine invocation.** Before each call to `ENGINE(...)`, the PARENT executes:

```
scopeHash = compute_working_tree_content_digest(
    in_scope_paths,          // resolved in-scope file set
    tracked_dirty_content,   // content of uncommitted (dirty) tracked files
    untracked_generated,     // relevant untracked + generated files
    CT_spec_plan_text,       // CT / spec / plan documents
    diff_payload             // git diff since session-start
    // deferral-ledger and audit writes EXCLUDED
)
```

This value is passed in to the ENGINE at invocation time. The PARENT recomputes it after every fix before the next re-invocation (a fix changes the tree; the new invocation must prove against the fixed state).

**ENGINE re-validates at every round boundary AND before any terminal verdict.** The engine does not trust that `scopeHash` is stable across a long multi-round run. At the start of each discovery round (before fanning out the lenses) and again before emitting any terminal (`CLEAN` / `FINDINGS` / `CAPPED`), the engine re-checks whether the content digest still matches the value passed in at invocation time.

### 6.3 Mismatch handling

When the engine detects a `scopeHash` change mid-invocation (re-validation does not match):

1. **Invalidate carried deterministic receipts** — any `carried-forward` receipt for the active finderSet's declared deterministic lanes that was signed against the prior `scopeHash` is **rejected**. A receipt is valid only while its signed `scopeHash` matches the current value. A stale receipt cannot count as coverage for the changed tree.
2. **Reset `dryStreak` to 0** — no dry credit can be carried across a scope change. The lens fan-out must re-run against the new state before dry is credited.
3. **Recompute `scopeHash`** — the engine updates its local `scopeHash` to the new digest and continues from the current round. The forced re-run of the deterministic lenses ensures the new receipt is signed against the correct content.

**Why this matters:** A parent fix, a cross-channel commit landing in the working tree, or an untracked/generated file changing mid-run all churn `scopeHash`. Without re-validation, a carried deterministic receipt could mask a regression introduced by those changes — a stale PASS covering a newly-broken tree. The per-round-boundary re-validation closes this hole.

### 6.4 Stale-receipt rejection rule

A **carried-forward deterministic lens receipt** (for any of the active finderSet's declared deterministic lanes) counts as coverage for a round **only while its signed `scopeHash` still matches the current `scopeHash`**.

On mismatch, the receipt is **REJECTED**:

- The lens is removed from coverage carry-forward for this round.
- The lens re-runs (as part of the deterministic pre-pass triggered by the scope change).
- Only after the re-run produces a new receipt signed against the current `scopeHash` does that lens contribute to coverage and dry-streak credit again.

**What this closes:** The stale-PASS-masks-regression hole. Three concrete triggers:

1. **A parent fix** edits a source file covered by lens 6 (test-honesty) — the old receipt was signed before the fix; the test may now behave differently.
2. **A cross-channel commit** lands a file in the working tree — the old receipt was signed before that content existed in scope.
3. **An untracked/generated file changes** (e.g., a codegen output regenerated between rounds) — the old receipt missed the new content.

In all three cases, carrying the old receipt forward would produce a false dry. Rejecting it forces the deterministic pass to re-run and produce a receipt that actually covers the changed tree.

### 6.5 Selftest assertion

The `--selftest` contract (`prove/SKILL.md` `#### Stale-receipt assertion`) verifies this rule deterministically in-harness:

1. Run one engine round, producing a deterministic receipt signed at `scopeHash` H1.
2. Mutate an in-scope file so the content digest changes to H2 (H2 ≠ H1).
3. Assert the next round-boundary **rejects** the H1 receipt and re-runs the lens — does NOT credit dry against the stale receipt.

This is the ONLY deterministic guard on `scopeHash` correctness. The prose in §6.1–6.4 specifies the contract; the selftest fixture proves the executing skill satisfies it. Before this §6 prose exists, no implementing skill can satisfy "stale receipt rejected" → selftest FAIL. After the prose lands and a thin skill executes it → selftest PASS.

---

## 7. MD-5 disagreement investigation

A persistent finder/verifier conflict (or finder/finder conflict) is returned first-class in `disagreements` by the engine and handled exclusively by the PARENT — not the engine. A `disagreements`-nonempty return blocks CLEAN (see §2.1). A workflow cannot spawn the grill/investigation subagents (subagents cannot spawn subagents), and only the parent may write the tombstone-free correction.

**This supersedes §9.2-item-3's "surface, don't average."** A disagreement is not merely surfaced as advisory, nor averaged away, nor does it pause `/5` mid-run for an interactive ruling — the PARENT runs a bounded investigation to ground truth and corrects cleanly, escalating to CT only when the investigation cannot converge within budget.

### 7.1 Investigation procedure

Run by the PARENT. Draw from the outer loop's shared `budgetGuard` (an expensive investigation shortens remaining rounds across the whole gate).

**Step 1 — Classify the disagreement type:**
- **Feature-design disagreement** ("should it be A or B?"): investigate *intent* — relevant specs, brainstorm decisions, design invariants, source consensus.
- **Code/technical/infra disagreement** ("is the mechanism correct?"): investigate *mechanism* — git history (log/blame: what it was meant to be + how it evolved), call-sites, library docs, context7 (for API questions).

**Step 2 — Bounded investigation (concrete stop condition):**
- At most N `/grill` rounds (default 3) + one git-history sweep + the relevant doc/context7 reads.
- Continue until the full scope and history are known with certainty.
- Draw from the shared `budgetGuard` — an expensive investigation shortens the remaining discovery rounds.

**Step 3 — Correct or escalate:**
- If investigation converges: correct CLEANLY — no tombstones (Rule 5: update all references, delete clean, no "was-X-now-Y" residue) so the same confusion cannot recur.
- If investigation cannot converge within budget: write the item to CT tagged `ESCALATION`; emit in the CAPPED terminal report (MD-9/MD-13). The gate does NOT pause `/5` mid-run for an interactive ruling.

**Step 4 — Thrash detection:**
- If the same `dedupKey` re-survives after an attempted correction, this is a thrash signal. Route to the parent circuit-breaker → escalate to `operator-CAPPED` (§5 no-progress/thrash breaker).

### 7.2 Why the engine cannot investigate

The engine fans out only read-mostly finders and verifiers. Investigation requires writing (tombstone-free correction), multi-step bounded reasoning (grill rounds + git + docs), and potentially spawning the grill subagents — all of which belong to the parent. Only the parent writes; only the parent orchestrates multi-step investigation. This is the rule from §9.3: "Don't Build Multi-Agents" for writers; fan out only read-mostly verification.

---

## 8. Compaction / resume handling

Three distinct events; the journal's sole job in all three is **audit / detection / liveness** — it is NOT the replay substrate.

### 8.1 Event 1 — Compaction (session alive): non-event

A compaction fires mid-session but **keeps the session alive**. A background workflow persists across compaction — the runtime continues running the workflow; no intervention is required. Demonstrated: research run `wf_a34d41c1-7c9` continued through a manual `/compact` and completed as task `wn3ib8ywc`. There is nothing to detect, resume, or restart. The round-journal accumulates normally.

### 8.2 Event 2 — Same-session interruption: harness-observed resume

Within the SAME session, an interruption **may** be recovered via the Workflow tool's same-session resume mechanism. In this harness the mechanism is `resumeFromRunId`; the **exact API name and journal layout are harness-observed, NOT contractual** — they are verified by `/prove --selftest` and must not be assumed portable across harness versions.

When the resume mechanism is available, it **reuses the runtime's cached completed-agent results** for rounds that already finished — no re-fan-out of those agents. The on-disk journal is consulted for audit, liveness, and detection purposes only; it is **NOT the documented replay substrate**. The runtime's in-memory (or runtime-cached) state is what drives re-entry, not the journal records.

**If a same-session resume mechanism is absent in the harness, treat ANY interruption as a kill** (see Event 3 below). This makes the procedure harness-portable: a skill that follows this rule degrades safely on any harness.

### 8.3 Event 3 — Session kill: detect-via-journal + restart fresh (no replay)

When a session is killed (process exit, harness restart, or a new session opening against the same working tree), the Workflow tool's runtime state is gone. **The next session cannot resume the prior workflow run.** There is no cross-session replay path.

The new session uses the journal ONLY to **detect** that a prior run was incomplete:

1. Read the journal at the harness-observed path (`subagents/workflows/<runId>/journal.jsonl`).
2. Find the last complete round record (an entry with a non-null or terminal field that represents a fully-written round). A round record is complete only if it was written atomically (see §8.4).
3. Announce the incomplete run and the round it reached — e.g.: `Prior run <runId> incomplete at round N — restarting gate fresh.`
4. **Restart the gate cleanly from round 1**, with a fresh `seen`/`found`/`pending`/`dryStreak`. No findings, receipts, or dry-streak credit from the prior run carry forward.

The prior run's incomplete state is NOT re-ingested as a head start. Any `dryStreak` value from the prior run is discarded. Only complete rounds count (§8.4).

### 8.4 Atomic per-round journaling + only-complete-rounds invariant

**Journal writes MUST be atomic per round.** The implementing skill must use a write-then-rename pattern (write to a temp file, rename into place) or an append-only complete-line scheme so that a torn write (process killed mid-write) leaves at most an incomplete line — never a half-written record that would be mistaken for a complete round entry.

**Only complete rounds ever count toward `dryStreak`.** This is a corollary of MD-10 (coverage-receipt-gated dry) applied across session boundaries:

- A partial round — one whose journal entry was never completed — is NOT counted as covered.
- A round from a prior run that is detected as incomplete (torn line, missing fields, absent terminal marker) is NOT credited.
- A gate restarted after a session kill starts from `dryStreak = 0`, regardless of how many rounds the prior run accumulated.

**Why this matters:** Without atomic writes and the only-complete-rounds rule, a torn journal entry could be mistaken for a dry round, advancing `dryStreak` toward CLEAN on coverage the gate never actually achieved. The partial-journal detection assertion in `/prove --selftest` (`#### Partial-journal detection assertion`) is the deterministic guard on this invariant.
