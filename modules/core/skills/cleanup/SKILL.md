---
name: cleanup
description: End-of-session housekeeping. Inventories state, commits work, cleans artifacts, documents remaining work. Use when ending a session normally with plenty of context remaining. Lighter than /cold and /finalize.
---

# /cleanup — End-of-Session Housekeeping

Lighter than `/5` (sprint close) and `/cold` (context dying). Run when session ends normally with plenty of context remaining. If context is high (85%+), use `/cold`. **No new work** — /cleanup documents and tidies only. Exception: marking items done that verification proves are actually done.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress->completed.

## Step 1: Inventory Session State

Read CT. Run `git status` and `git diff --stat`. Catalog briefly:
1. **Uncommitted changes** — every modified/untracked file, one-line description.
2. **Active plan items** — unchecked steps from CT's Plan section.
3. **Open items** — TODOs, action items, decisions, follow-ups, non-done markers.

## Step 2: Completeness Audit

For each plan item: verify done by reading target file or grepping (don't trust CT markers alone). Mark done items in CT (Edit). Note remaining with specific files and changes needed.

Context-aware: below 50% context used (plenty of budget remaining) -> verify ALL items; 50-75% used (conserve budget) -> verify only done-marked items.

Report: "N of M plan items complete. Remaining: [list with one-line context each]."

## Step 3: Commit All Work

If uncommitted changes exist, one commit for all session work.

If `scripts/channel_commit.sh` exists (Commit Enforcement module installed), follow `.claude/reference/commit-protocol.md` — multi-channel index safety rules apply:
```bash
bash ~/.claude/scripts/channel_commit.sh [--channel N] --files "<all changed files>" -m "wip: end-of-session commit" --skip-squad
```

If channel_commit.sh is not available (Core-only install — no multi-channel concern):
```bash
git add <all changed files>
git commit -m "wip: end-of-session commit"
```
Use proper message if changes include completed work. Clean tree -> skip.

## Step 4: Clean Artifacts

Delete session artifacts. **Only YOUR channel's artifacts** — never touch other channels' files.

**Channeled:** Delete `verification_findings/_pending_sonnet/chN/*`, `verification_findings/_staging/*`, `verification_findings/squad_chN_sonnet/`, `verification_findings/squad_chN_opus/`, `verification_findings/build_pipeline_chN/`, `verification_findings/cold_prep_result_chN.md`, `verification_findings/transcript_orphan_result_chN.md`. (All paths are subdirectories/files UNDER `verification_findings/` — the `build_pipeline_chN/` entry is `verification_findings/build_pipeline_chN/`, the `/3` write path, NOT a repo-root directory.)

**Unchanneled:** If other channels active (check Active Channels in `CURRENT_TASK.md`), do NOT delete `verification_findings/_pending_sonnet/`. Clean only: `verification_findings/_staging/*`, `verification_findings/squad_sonnet/`, `verification_findings/squad_opus/`, `verification_findings/build_pipeline/`, `verification_findings/cold_prep_result.md`, `verification_findings/transcript_orphan_result.md`. (`build_pipeline/` here is `verification_findings/build_pipeline/`, the `/3` write path.)

The `verification_findings/build_pipeline[_chN]/` artifacts are working-state, gitignored at `verification_findings/build_pipeline*/` (a project running `/3` must add `verification_findings/build_pipeline*/` to its `.gitignore` if not already present — see spec obligation 9(a)) — they are overwritten per run and never committed.

**Do NOT delete:** `/perfect`, spec-to-code, or transcript decision results (sprint records). Files referenced in CT or your project backlog. When in doubt, keep it.

Commit only if tracked files were deleted (squad dirs and `_pending_sonnet/` are gitignored). If `scripts/channel_commit.sh` exists:
```bash
bash ~/.claude/scripts/channel_commit.sh [--channel N] --files "<deleted tracked files>" -m "cleanup: remove session artifacts" --skip-squad
```
If not: `git add <deleted tracked files> && git commit -m "cleanup: remove session artifacts"`

## Step 5: Document Remaining Work

For each incomplete item: ensure CT has enough context for zero-context execution (no "as discussed" — state decisions inline, include file paths, criteria, dependencies). If an item may be missing from your backlog or plan, add `FLAG-FOR-NEXT-SESSION: verify [item] in backlog/plan` to CT. Capture any unwritten design decisions to the relevant file now.

## Step 6: Update or Clear Channel

**Shared CT frontmatter:** Reset frontmatter fields (`goal`, `now`, `next`, `done_this_session`, `decisions`) to empty strings ONLY if this session wrote them. If another session populated the frontmatter, leave it intact — it belongs to that session's context. Check `git log --oneline -1 -- CURRENT_TASK.md` or conversation history to determine authorship. The principle: stale *own* session context is harmful, but another session's live context is not yours to clear.

- **Task in progress:** Edit your CT — update status with last commit hash (`git log --oneline -1`). Add Resume Instructions: what to read, which step to resume, expected agents/listeners, pending decisions, FLAG items.
- **Task complete:** **Remove your row from the Active Channels table entirely** (do NOT strikethrough; closed work leaves no residue). Remove your section content from shared `CURRENT_TASK.md`. Leave other rows and other sessions' section content untouched. Channeled: also delete the channel CT (`git rm CURRENT_TASK_chN.md`) — this is the only place channel CTs get deleted (`/5` marks complete but preserves the CT until `/cleanup` runs). Unchanneled: also reset shared CT frontmatter if this session wrote it (per the principle above).

## Step 7: CT Completeness Gate

Read EVERY CT file that belongs to this session — shared `CURRENT_TASK.md` (your sections only) and your channel CT (`CURRENT_TASK_chN.md`) if channeled. Scan for ANY unchecked task (`- [ ]`), unchecked sub-bullet, open TODO/FIXME, unresolved follow-up, or item without a completion marker or explicit deferral. Items belonging to OTHER channels are out of scope — skip them.

For each item found, determine:
1. **Actually done?** Verify against git log, file state, or grep. If done, check it off now.
2. **Tracked elsewhere?** If it's already in SPRINT_CHECKLIST.md or COMPREHENSIVE_IMPLEMENTATION_PLAN.md as an open item, it's accounted for — not a blocker.
3. **Orphaned?** If it's not done AND not tracked in SPRINT_CHECKLIST/COMPREHENSIVE_IMPLEMENTATION_PLAN — this is a FAIL.

**Any orphaned incomplete item = CLEANUP BLOCKED.** Do not proceed to Step 8. For each orphan: either finish the work (if trivial), add it to SPRINT_CHECKLIST.md/COMPREHENSIVE_IMPLEMENTATION_PLAN.md with enough context for cold-start pickup, or get explicit user permission to drop it. Re-run this step after resolution.

Only proceed when: zero unchecked items remain in your CT scope, or every unchecked item has a matching SC/CIP entry.

## Step 8: Final Commit and Report

If files changed. With channel_commit.sh:
```bash
bash ~/.claude/scripts/channel_commit.sh [--channel N] --files "<changed files>" -m "cleanup: [session state updated | channel N cleared]" --skip-squad
```
Without: `git add <changed files> && git commit -m "cleanup: session state updated"`

Report:
```
CLEANUP COMPLETE
Plan: N/M complete | Commits: N | Artifacts cleaned: N
Remaining: [list or "none"] | Next: [what to do first]
Decisions pending: [list or "none"] | Flags: [list or "none"]
```
