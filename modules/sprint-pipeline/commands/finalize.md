# /finalize — Finalize (alias: /5)

After `/perfect`, when sprint work is complete. Handles transcript mining, Sonnet review, spec-to-code verification, accumulated corrections, and reset.

**Abbreviations:** CT = `CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress→completed.

## Steps

### 1. Pre-verification checkpoint

If uncommitted changes: `bash scripts/channel_commit.sh --channel N --files "<files>" -m "wip: pre-verification" --skip-squad`. If clean: skip.

### 2. Review Sonnet's work

If Sonnet contributed this sprint: `git log` to identify Sonnet commits. Read changed files, check against spec and CT acceptance criteria. Fix: wrong behavior, missed edge cases, spec drift, incomplete propagation.

### 3. Decision externalization

DELEGATE via `verification_findings/_pending/[chN/]transcript_mining_<timestamp>.md`. Identify sprint transcripts using `history.jsonl` session IDs filtered by sprint date range. Skip previously-mined transcripts. Output: `verification_findings/transcript_decisions_N[_chN].md`. Wait: `bash scripts/wait_for_results.sh verification_findings/transcript_decisions_N[_chN].md` (`run_in_background: true`).

Opus collects, deduplicates. For each decision: grep work product for evidence. Missing → write it now.

### 4. Spec-to-code verification

DELEGATE via `verification_findings/_pending/[chN/]spec_to_code_<timestamp>.md`. Procedure: `.claude/reference/spec-verification.md`. Output: `verification_findings/spec_to_code_report[_chN].md`. Wait: `bash scripts/wait_for_results.sh verification_findings/spec_to_code_report[_chN].md` (`run_in_background: true`).

### 5. Accumulated Corrections

Review all issues found this sprint. For each: search CLAUDE.md for existing rule → strengthen/update. Not found → add as "Never X. Always Y." with rationale. Never duplicate.

### 6. Generate test script

Write `test_script_sprint_N.md` — manual test scenarios for sprint deliverables.

### 7. Final report

- Requirements extracted/verified: N
- Fixed during verification: N (list each)
- Quality gate: PASS (spec verified, code verified, 100% implementation, no remaining issues) or FAIL (any gap)

### 8. Merge (if on feature branch)

If on feature branch: merge to main. If already on main: skip.

### 9. Channel cleanup / Reset

**Channeled:** Delete `CURRENT_TASK_chN.md`, remove channel row from shared CT Active Channels table, delete `verification_findings/squad_chN_*/`. Commit: `bash scripts/channel_commit.sh --channel N --files "CURRENT_TASK_chN.md" -m "finalize: remove channel N" --skip-squad`

**Unchanneled:** Overwrite CT with `current-task-template.md` contents. Never blank the file.

Announce sprint complete. Next sprint begins with `/1`.
