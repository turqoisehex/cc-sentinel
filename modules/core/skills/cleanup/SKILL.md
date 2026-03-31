---
name: cleanup
description: End-of-session housekeeping. Inventories state, commits work, cleans artifacts, documents remaining work. Use when ending a session normally with plenty of context remaining. Lighter than /cold and /finalize.
---

# /cleanup — End-of-Session Housekeeping

Lighter than `/5` (sprint close) and `/cold` (context dying). Run when session ends normally with plenty of context remaining. If context is high (85%+), use `/cold`. **No new work** — /cleanup documents and tidies only. Exception: marking items done that verification proves are actually done.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress→completed.

## Step 1: Inventory Session State

Read CT. Run `git status` and `git diff --stat`. Catalog briefly:
1. **Uncommitted changes** — every modified/untracked file, one-line description.
2. **Active plan items** — unchecked steps from CT's Plan section.
3. **Open items** — TODOs, action items, decisions, follow-ups, non-done markers.

## Step 2: Completeness Audit

For each plan item: verify done by reading target file or grepping (don't trust CT markers alone). Mark done items in CT (Edit). Note remaining with specific files and changes needed.

Context-aware: below 50% context used (plenty of budget remaining) → verify ALL items; 50-75% used (conserve budget) → verify only done-marked items.

Report: "N of M plan items complete. Remaining: [list with one-line context each]."

## Step 3: Commit All Work

If uncommitted changes exist, one commit for all session work.

If `scripts/channel_commit.sh` exists (Commit Enforcement module installed):
```bash
bash scripts/channel_commit.sh [--channel N] --files "<all changed files>" -m "wip: end-of-session commit" --skip-squad
```

If channel_commit.sh is not available (Core-only install):
```bash
git add <all changed files>
git commit -m "wip: end-of-session commit"
```
Use proper message if changes include completed work. Clean tree → skip.

## Step 4: Clean Artifacts

Delete session artifacts. **Only YOUR channel's artifacts** — never touch other channels' files.

**Channeled:** Delete `verification_findings/_pending_sonnet/chN/*`, `_staging/*`, `squad_chN_sonnet/`, `squad_chN_opus/`, `cold_prep_result_chN.md`, `transcript_orphan_result_chN.md`.

**Unchanneled:** If other channels active (check Active Channels in `CURRENT_TASK.md`), do NOT delete `_pending_sonnet/`. Clean only: `_staging/*`, `squad_sonnet/`, `squad_opus/`, `cold_prep_result.md`, `transcript_orphan_result.md`.

**Do NOT delete:** `/perfect`, spec-to-code, or transcript decision results (sprint records). Files referenced in CT or your project backlog. When in doubt, keep it.

Commit only if tracked files were deleted (squad dirs and `_pending_sonnet/` are gitignored). If `scripts/channel_commit.sh` exists:
```bash
bash scripts/channel_commit.sh [--channel N] --files "<deleted tracked files>" -m "cleanup: remove session artifacts" --skip-squad
```
If not: `git add <deleted tracked files> && git commit -m "cleanup: remove session artifacts"`

## Step 5: Document Remaining Work

For each incomplete item: ensure CT has enough context for zero-context execution (no "as discussed" — state decisions inline, include file paths, criteria, dependencies). If an item may be missing from your backlog or plan, add `FLAG-FOR-NEXT-SESSION: verify [item] in backlog/plan` to CT. Capture any unwritten design decisions to the relevant file now.

## Step 6: Update or Clear Channel

- **Task in progress:** Edit CT — update status with last commit hash (`git log --oneline -1`). Add Resume Instructions: what to read, which step to resume, expected agents/listeners, pending decisions, FLAG items.
- **Task complete (channel done):** Clear the channel: `git rm CURRENT_TASK_chN.md`. Update Active Channels table in shared `CURRENT_TASK.md` — strikethrough the row. No state to preserve.

## Step 7: Final Commit and Report

If files changed. With channel_commit.sh:
```bash
bash scripts/channel_commit.sh [--channel N] --files "<changed files>" -m "cleanup: [session state updated | channel N cleared]" --skip-squad
```
Without: `git add <changed files> && git commit -m "cleanup: session state updated"`

Report:
```
CLEANUP COMPLETE
Plan: N/M complete | Commits: N | Artifacts cleaned: N
Remaining: [list or "none"] | Next: [what to do first]
Decisions pending: [list or "none"] | Flags: [list or "none"]
```
