---
name: cold
description: Cold start preparation for context handoff. Makes state files zero-context ready with orphan scans and cross-document consistency checks. Use before session end or when context is high (85%+).
---

# /cold — Cold Start Preparation

**Trigger:** Run before session end or when context is high (85%+). Makes CT cold-start ready for a zero-context session.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

## Procedure

**Abbreviations:** CT=your channel CT file (or `CURRENT_TASK.md` if unchanneled). BACKLOG=your project backlog or sprint checklist (if you use one). PLAN=your implementation plan (if you use one).

### Step 0: Gate checks and task setup

1. **Sonnet check.** If `scripts/wait_for_results.sh` exists (Commit Enforcement installed): check for an active Sonnet listener. If no heartbeat, warn: "No Sonnet listener — Step 1 will use subagents instead of Sonnet dispatch." If `wait_for_results.sh` does not exist (Core-only install): skip — Step 1 uses subagents directly.
2. **Template check.** If CT Active Task is `(none)` and no plan steps: report "CT at template — nothing to prepare" and **stop**.
3. TaskCreate every step below. Mark in_progress->completed.

### Step 1: Delegate cold-start preparation to Sonnet

Do NOT read backlog or plan in parent — delegate to Sonnet. Identify session transcript (do NOT use `ls -t` — parallel sessions corrupt mtime):
```bash
SESSION_ID=$(tail -1 ~/.claude/history.jsonl | sed 's/.*"sessionId":"\([^"]*\)".*/\1/')
# Validate extraction succeeded (should be UUID-like, not full JSON)
echo "SESSION_ID=$SESSION_ID" && [[ "$SESSION_ID" =~ ^[a-f0-9-]+$ ]] || { echo "ERROR: Failed to extract sessionId"; exit 1; }
SESSION_JSONL=~/.claude/projects/<PROJECT_SLUG>/${SESSION_ID}.jsonl  # Replace <PROJECT_SLUG> with your project path slug
echo "$SESSION_JSONL"
```

Write prompt to `verification_findings/_pending_sonnet/[chN/]cold_prep_<timestamp>.md`. Wait for results:
```bash
rm -f verification_findings/cold_prep_result[_chN].md verification_findings/transcript_orphan_result[_chN].md
```
If `scripts/wait_for_results.sh` exists: `bash scripts/wait_for_results.sh verification_findings/cold_prep_result[_chN].md verification_findings/transcript_orphan_result[_chN].md`

If not (Core-only install without Commit Enforcement): execute the two agent tasks directly as subagents instead of dispatching to Sonnet.

**Prompt file content** (YAML frontmatter required). Resolve bracket notation before writing:

```yaml
---
type: implementation
tasks:
  - name: cold-prep
    signal_file: verification_findings/cold_prep_result[_chN].md
    files:
      - CURRENT_TASK_chN.md
      - "<your backlog file, if any>"
      - "<your plan file, if any>"
  - name: transcript-orphan
    signal_file: verification_findings/transcript_orphan_result[_chN].md
    files:
      - CURRENT_TASK_chN.md
      - "<your backlog file, if any>"
      - "<your plan file, if any>"
---
```

> **Cold-start preparation.** Read these files completely — no skimming:
> 1. `CURRENT_TASK_chN.md` (CT — the channel file, not the shared index) when channeled; `CURRENT_TASK.md` when unchanneled
> 2. Your project backlog file (if you maintain one)
> 3. Your implementation plan file (if you maintain one)
>
> Since the session is ending, no further work will be completed. Classify each item by its current tracking state.
>
> **A. Orphan scan.** Extract every discrete item from CT. For each, classify:
>
> | Classification | Meaning | Action |
> |---|---|---|
> | **Incomplete** | Was active but will NOT be completed | Write to BOTH backlog and plan. Keep in CT with status. |
> | **Permanent-home** | Already tracked in BOTH backlog and plan | Verify by grep. If truly present in both, no action. |
> | **Partial-home** | In one but not the other | Write to the missing document. |
> | **Orphan** | Not in backlog, not in plan | Write to BOTH now. |
> | **Done** | Completed and verified | Must be in Completed Steps with summary. |
> | **Dead** | Explicitly dropped with rationale | Remove from CT. |
>
> **B. Cold-start quality pass on CT.** For each plan step verify: self-contained context, concrete file paths, acceptance criteria, explicit dependencies, no stale references, status markers resolved, sprint/phase context in header.
>
> **C. Cross-document consistency.** CT <-> backlog <-> plan. File references -> disk.
>
> **D. Write results to `verification_findings/cold_prep_result[_chN].md`.**

**Transcript orphan agent** (second agent): scan session transcript for actionable items not captured in CT/backlog/plan. Write to `verification_findings/transcript_orphan_result[_chN].md`.

When both results appear, read them. Unresolvable issues -> add to CT as flagged items.

### Step 2: Grill

Read both agent result files and CT. For each grill question, verify checkable answers with grep/read. Fix CT problems directly.

1. **"Where does this break?"** — Different day, sprint phase, or post-compaction start.
2. **"What have I not checked?"** — Zero stale references? Recent commits reflected in CT?
3. **"What's most likely wrong?"** — Implicit orphans. Stale status markers.
4. **"What assumption haven't I verified?"** — Sprint number? Commit hash? Agent results?

### Step 3: Commit

If CT, backlog, or plan were modified, commit. If all clean, skip.

If `scripts/channel_commit.sh` exists:
```bash
bash scripts/channel_commit.sh --channel N --files "CURRENT_TASK_chN.md <backlog-file> <plan-file>" -m "cold: state files cold-start ready" --skip-squad
```

If not:
```bash
git add CURRENT_TASK_chN.md <backlog-file> <plan-file>
git commit -m "cold: state files cold-start ready"
```

Report: orphans resolved (N), transcript items rescued (N), incomplete items written (N), stale refs fixed (N), grill issues (N found/N fixed).

---

## Notes

- State files only — code must already be committed.
- /cold != template reset. For that: `/5` Step 9.
- Per-commit agents in channel_commit.sh provide verification. No /squad needed.
