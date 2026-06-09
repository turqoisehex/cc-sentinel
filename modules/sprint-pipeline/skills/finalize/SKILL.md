---
name: finalize
description: "Sprint finalization: transcript mining, Sonnet review, accumulated corrections, manual test queue, and channel reset. Phase /5 of the sprint pipeline. Also invoked as /5."
---

# /finalize — Finalize (alias: /5)

After `/perfect`, when sprint work is complete. Handles transcript mining, Sonnet review, accumulated corrections, and reset.

**Abbreviations:** CT = `CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress->completed.

**Commit protocol:** All commits issued by /finalize MUST follow `.claude/reference/commit-protocol.md`. READ IT the first time you commit in any session. Never pre-stage, never run `git diff --cached`, never call `git hash-object`. The `--skip-squad` flag bypasses verifier spawning but does NOT permit raw `git add`.

## Steps

### 1. Pre-verification checkpoint

If uncommitted changes: `bash ~/.claude/scripts/channel_commit.sh --channel N --files "<files>" -m "wip: pre-verification" --skip-squad`. If clean: skip.

### 2. Review Sonnet's work

If Sonnet contributed this sprint: `git log` to identify Sonnet commits. Read changed files, check against spec and CT acceptance criteria. Fix: wrong behavior, missed edge cases, spec drift, incomplete propagation.

### 3. Decision externalization

**Default mode:** Spawn Sonnet subagent via `Agent(model: "sonnet")` with transcript mining prompt. Output: `verification_findings/transcript_decisions_N[_chN].md`.

**Duo mode:** DELEGATE via `verification_findings/_pending_sonnet/[chN/]transcript_mining_<timestamp>.md`. Wait: `bash ~/.claude/scripts/wait_for_results.sh` (run_in_background: true).

Opus collects, deduplicates. For each decision: grep work product for evidence. Missing -> write it now.

### 4. Fidelity-audit gate

**Gate authority:** `~/.claude/reference/spec-verification.md` Phases 0-5 (including Phase 4.5 field-consumption audit). Bracket codes: [D] declared-not-consumed, [F] silent-fallback, [M] missing-consumer, [I] incomplete-wiring, [T] test-only. Gate FAILs if `/perfect` Phase 2.5 outputs are missing OR if either output contains any unresolved [D]/[F]/[M]/[I]/[T] finding (each bracket code is a defect class — there is no severity scale within fidelity-audit findings; any [D]/[F]/[M]/[I]/[T] entry that is not yet resolved fails the gate). "Unresolved" means the field/wiring problem is still live in code — fix it (wire it, delete it, or add an SC entry reserving forward-schema use). Prose-only deferral in the audit body is not resolution. The /verify squad's separate HIGH/MEDIUM/LOW/INFO severity vocabulary does not apply here.

Verify that `/perfect` Phase 2.5 ran. Check for both outputs:
- `verification_findings/fidelity_audit[_chN].md`
- `verification_findings/field_consumption_audit[_chN].md`

Missing either → FAIL. Return to `/perfect` and run Phase 2.5 before continuing.

Read both files. Any unresolved [D]/[F]/[M]/[I]/[T] findings → FAIL. Return to `/perfect` — fix, re-run Phase 2.5, then resume `/5` from this step.

Only proceed to Step 5 when both audits exist, both verdicts are PASS (or PASS (N/A) for `field_consumption_audit` when zero data-model fields were in scope this sprint), and no unresolved [D]/[F]/[M]/[I]/[T] findings remain (fidelity-audit findings have no INFO tier — every bracket-code entry must be resolved per the rules above). `PASS (N/A)` from `field_consumption_audit` is acceptable because the absence of declared fields means there is nothing to consume; it is not a softened PASS.

### 5. Accumulated Corrections

Review all issues found this sprint. For each: search CLAUDE.md for existing rule -> strengthen/update. Not found -> add as "Never X. Always Y." with rationale. Never duplicate.

### 6. Reconcile SC and CIP (MANDATORY — not skippable even for doc-only sprints)

Read your project's sprint tracking files (e.g., `SPRINT_CHECKLIST.md` and/or a comprehensive implementation plan). This step is the canonical moment when sprint progress reaches the project's durable tracking surfaces. If your project does not use these files, skip this step.

For each item completed this sprint:
- SC: check off (`- [x]`) with commit hash and date. One-line summary of what shipped.
- CIP: add a status blockquote at the top of the relevant section with date, commits, verdict, and what blocks next.
- If the sprint had a recording-week catalog entry or cross-reference in SC, check that off too.

For incomplete/blocked items: add as unchecked items under the current or next sprint section with blocking reason.

Gate: do not proceed to Step 7 until BOTH files have been updated AND the changes are staged for the /5 commit. Unstaged SC/CIP updates are invisible to future sessions.

### 7. Update manual test queue

Read `MANUAL_TEST_QUEUE.md` (project root). Prune first: for each existing entry, search `test/` for automated coverage added since the entry was created — if now covered, remove it. Then review this sprint's deliverables for items meeting BOTH criteria: (1) cannot be verified by any automated test, script, or integration test, and (2) critically important — if broken, users will notice. Skip cosmetic, edge-case, or "nice to verify" items. For qualifying items not already in the queue, append a row: description, why not automatable, pass criteria, sprint added. If no items qualify, skip this step.

### 8. Final report

- Requirements extracted/verified: N
- Fixed during verification: N (list each)
- Budget: if `ccusage` is installed, run it for the sprint date range and include total input/output tokens and estimated cost. If unavailable, skip this line.
- Quality gate: PASS (spec verified, code verified, 100% implementation, no remaining issues) or FAIL (any gap)

### 9. Merge (if on feature branch)

If on feature branch: merge to main. If already on main: skip.

### 9.5. CT completeness audit (REQUIRED before any cleanup)

#### Shared scope resolver

Build `scopeContext` via the **shared resolver** (used by both `/5` and `/prove` — DRY, no separate implementations):

- Resolved CTs: channeled `CURRENT_TASK_chN.md` (all lines) + relevant section of shared `CURRENT_TASK.md`.
- `git diff` since session start (diff of working tree against the commit that was HEAD when the session opened).
- The plan file referenced by the channel CT's plan pointer.
- The project DI-graph file(s) + entry-point modules.
- Lens-7/8/9 probes (full-suite test runner output, git-status, and the static-analysis receipt).

This resolver is **shared with `/prove`** so that both skills operate on the same scope snapshot.

#### Gate invocation

Read `enabled-phases` from `.claude/reference/workflows-config.md` (key `enabled-phases`, default `["/5"]`).

- **If `/5` is NOT listed in `enabled-phases`:** short-circuit to the existing single-pass fallback (Step 9.5 legacy audit below). This is the D2 guarantee — the pre-existing single-pass IS the mandatory fallback.
- **If `/5` IS listed:** invoke the gate at `.claude/reference/adversarial-loop.md` heading `## 4` with the `/5` finderSet and the `scopeContext` built above.

On the gate's `terminal`:
- `CLEAN` → proceed to §9.5a, then Step 10.
- `CAPPED` → list all parked items; apply the existing `/5` FAIL-handling (explicit deferral with SPRINT_CHECKLIST.md entry) fed by the `pending` list from the returned tuple.
- `ERROR → fallback` → the gate already bannered the reason; continue with the single-pass fallback below.
- Any `FINDINGS` survivors → apply the existing `/5` FAIL-handling: fix each or obtain explicit user deferral approval with a SPRINT_CHECKLIST.md entry. Never proceed to Step 10 with unresolved survivors.

The **pre-existing single-pass Step 9.5 audit** (CT completeness check below) IS the mandatory fallback (D2). It runs whenever the gate is skipped, errors, or config is OFF.

#### Legacy single-pass fallback (D2 — also the gate's fallback)

### 9.5a. First-/5 workflow discovery hint (one-time, marker-gated)

On the FIRST `/5` after install when `.claude/reference/workflows-config.md` is
absent or OFF, AND the marker file `.claude/.workflows-hint-shown` does NOT exist:
print ONCE —
  "Tip: the `/5` prove-gate can run a 9-lens adversarial engine instead of the
   single-pass audit. It is default-OFF (budget-respecting). To opt in, edit one
   line in `.claude/reference/workflows-config.md`. (Pro plans also need the
   `/config` Dynamic-workflows row.)"
Then create `.claude/.workflows-hint-shown` so this NEVER repeats. This is a
one-time hint gated behind a marker file — NOT a per-run footer (MD-21).

Read both files in full:
- **Channeled CT** (`CURRENT_TASK_chN.md`) — every line, top to bottom.
- **Shared CT** (`CURRENT_TASK.md`) — every item belonging to this channel/session only (your section). Ignore other channels' sections.

For every item in scope — task, acceptance criterion, sub-bullet, note, follow-up — ask three questions:

1. **Done?** Is there explicit evidence it was completed (commit hash, PASS verdict, output file, code change)?
2. **Fully done?** No partial completion, no "mostly done," no "needs one more thing." Partial = incomplete.
3. **Not orphaned?** Not mentioned mid-file and then dropped without a resolution or a tracked deferral.

**FAIL criteria (do not proceed to Step 10 if any apply):**
- Any item with no completion evidence
- Any item marked complete but with open sub-tasks
- Any item that appears only in the middle of the file with no verdict
- Any item marked "deferred" without EXPLICIT current-conversation permission from the user
- Any TODO, FIXME, or follow-up note that was not converted to SPRINT_CHECKLIST.md / COMPREHENSIVE_IMPLEMENTATION_PLAN.md or resolved

**On FAIL:** List every problematic item verbatim with the line it appears on. Resolve each — fix the work or get explicit user approval to defer with a SPRINT_CHECKLIST.md entry — before proceeding. Do not batch-dismiss; each item requires individual resolution.

**On PASS:** State "CT audit PASS — all N items verified complete" before moving to Step 10.

### 10. Mark complete / Reset

**Channeled:** Mark channel as complete in shared CT Active Channels table (strikethrough). Do NOT delete `CURRENT_TASK_chN.md` — that happens in `/cleanup`. Delete `verification_findings/squad_chN_*/`. Commit: `bash ~/.claude/scripts/channel_commit.sh --channel N --files "CURRENT_TASK_chN.md" -m "finalize: channel N sprint complete" --skip-squad`

**Unchanneled:** Mark sprint complete in CT. Do NOT overwrite or blank CT — `/cleanup` handles reset.

Announce sprint complete. Channel CT persists as a record until `/cleanup` runs. Next sprint begins with `/1`.
