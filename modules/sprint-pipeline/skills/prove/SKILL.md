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
- `/4`: 6 agent-ids + 1 receipt (from this sub-block)

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

**(c) Real LLM fan-out executes:** At least one round of real LLM fan-out executes with the expected lens agents reporting. A no-op, a mock, or a zero-agent round is a FAIL.

**(d) Liveness assertion (journal):** Read the on-disk run-journal at the harness-observed path (`subagents/workflows/<runId>/journal.jsonl`). Assert all lenses in the ACTIVE finderSet's `lensStatus[]` are accounted-for per round: agent IDs for the LLM lanes, signed receipts for the active finderSet's declared deterministic lanes. Absent journal = FAIL. Any missing `lensStatus` entry = FAIL. The count is finderSet-declared (9 for `/5`-mode; 7 for `/4`-mode) — NOT a hardcoded constant.

### Additional deterministic in-harness assertions

These assertions run as part of `--selftest` and point at the relevant proc-doc sections.

#### Stale-receipt assertion

**References:** `adversarial-loop.md` §6 (scopeHash lifecycle + stale-receipt rejection)

**Procedure:**

(a) Run one engine round using the synthetic fixture scope, producing a signed deterministic receipt for a carried-forward lens (6, 8, or 9) at `scopeHash` H1.

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
