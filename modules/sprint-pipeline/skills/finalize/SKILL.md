---
name: finalize
description: "Sprint finalization: transcript mining, Sonnet review, spec-to-code verification, accumulated corrections, manual test queue, and channel reset. Phase /5 of the sprint pipeline. Also invoked as /5."
---

# /finalize — Finalize (alias: /5)

After `/perfect`, when sprint work is complete. Handles transcript mining, Sonnet review, spec-to-code verification, accumulated corrections, and reset.

**Abbreviations:** CT = `CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress->completed.

## Steps

### 1. Pre-verification checkpoint

If uncommitted changes: `bash scripts/channel_commit.sh --channel N --files "<files>" -m "wip: pre-verification" --skip-squad`. If clean: skip.

### 2. Review Sonnet's work

If Sonnet contributed this sprint: `git log` to identify Sonnet commits. Read changed files, check against spec and CT acceptance criteria. Fix: wrong behavior, missed edge cases, spec drift, incomplete propagation.

### 3. Decision externalization

**Default mode:** Spawn Sonnet subagent via `Agent(model: "sonnet")` with transcript mining prompt. Output: `verification_findings/transcript_decisions_N[_chN].md`.

**Duo mode:** DELEGATE via `verification_findings/_pending_sonnet/[chN/]transcript_mining_<timestamp>.md`. Wait: `bash scripts/wait_for_results.sh` (run_in_background: true).

Opus collects, deduplicates. For each decision: grep work product for evidence. Missing -> write it now.

### 4. Spec-to-code verification

**Default mode:** Spawn Sonnet subagent via `Agent(model: "sonnet")` with spec-to-code prompt. Procedure: `.claude/reference/spec-verification.md`. Output: `verification_findings/spec_to_code_report[_chN].md`.

**Duo mode:** DELEGATE via `verification_findings/_pending_sonnet/[chN/]spec_to_code_<timestamp>.md`. Wait: `bash scripts/wait_for_results.sh` (run_in_background: true).

### 5. Accumulated Corrections

Review all issues found this sprint. For each: search CLAUDE.md for existing rule -> strengthen/update. Not found -> add as "Never X. Always Y." with rationale. Never duplicate.

### 6. Update manual test queue

Read `MANUAL_TEST_QUEUE.md` (project root). Prune first: for each existing entry, search `test/` for automated coverage added since the entry was created — if now covered, remove it. Then review this sprint's deliverables for items meeting BOTH criteria: (1) cannot be verified by any automated test, script, or integration test, and (2) critically important — if broken, users will notice. Skip cosmetic, edge-case, or "nice to verify" items. For qualifying items not already in the queue, append a row: description, why not automatable, pass criteria, sprint added. If no items qualify, skip this step.

### 7. Final report

- Requirements extracted/verified: N
- Fixed during verification: N (list each)
- Budget: if `ccusage` is available (`npx ccusage` or global install), run `ccusage` for the sprint date range and include total input/output tokens and estimated cost. If not available, note "ccusage not installed" and skip — do not block finalization.
- Quality gate: PASS (spec verified, code verified, 100% implementation, no remaining issues) or FAIL (any gap)

### 8. Merge (if on feature branch)

If on feature branch: merge to main. If already on main: skip.

### 9. Channel cleanup / Reset

**Channeled:** Delete `CURRENT_TASK_chN.md`, remove channel row from shared CT Active Channels table, delete `verification_findings/squad_chN_*/`. Commit: `bash scripts/channel_commit.sh --channel N --files "CURRENT_TASK_chN.md" -m "finalize: remove channel N" --skip-squad`

**Unchanneled:** Overwrite CT with `current-task-template.md` contents. Never blank the file.

Announce sprint complete. Next sprint begins with `/1`.
