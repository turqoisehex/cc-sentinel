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

### 6. Reconcile SC and CIP

Read `SPRINT_CHECKLIST.md` and `COMPREHENSIVE_IMPLEMENTATION_PLAN.md`. For each item completed this sprint: check it off with commit hash. For incomplete items discovered during verification (MISS/PARTIAL/blocked): add as unchecked items under the current or next sprint section. Never leave completed work untracked or incomplete work unmarked.

### 7. Update manual test queue

Read `MANUAL_TEST_QUEUE.md` (project root). Prune first: for each existing entry, search `test/` for automated coverage added since the entry was created — if now covered, remove it. Then review this sprint's deliverables for items meeting BOTH criteria: (1) cannot be verified by any automated test, script, or integration test, and (2) critically important — if broken, users will notice. Skip cosmetic, edge-case, or "nice to verify" items. For qualifying items not already in the queue, append a row: description, why not automatable, pass criteria, sprint added. If no items qualify, skip this step.

### 8. Final report

- Requirements extracted/verified: N
- Fixed during verification: N (list each)
- Budget: run `ccusage` for the sprint date range and include total input/output tokens and estimated cost.
- Quality gate: PASS (spec verified, code verified, 100% implementation, no remaining issues) or FAIL (any gap)

### 9. Merge (if on feature branch)

If on feature branch: merge to main. If already on main: skip.

### 9.5. CT completeness audit (REQUIRED before any cleanup)

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
- Any TODO, FIXME, or follow-up note that was not converted to SC.md / CIP.md or resolved

**On FAIL:** List every problematic item verbatim with the line it appears on. Resolve each — fix the work or get explicit user approval to defer with a SC.md entry — before proceeding. Do not batch-dismiss; each item requires individual resolution.

**On PASS:** State "CT audit PASS — all N items verified complete" before moving to Step 10.

### 10. Mark complete / Reset

**Channeled:** Mark channel as complete in shared CT Active Channels table (strikethrough). Do NOT delete `CURRENT_TASK_chN.md` — that happens in `/cleanup`. Delete `verification_findings/squad_chN_*/`. Commit: `bash ~/.claude/scripts/channel_commit.sh --channel N --files "CURRENT_TASK_chN.md" -m "finalize: channel N sprint complete" --skip-squad`

**Unchanneled:** Mark sprint complete in CT. Do NOT overwrite or blank CT — `/cleanup` handles reset.

Announce sprint complete. Channel CT persists as a record until `/cleanup` runs. Next sprint begins with `/1`.
