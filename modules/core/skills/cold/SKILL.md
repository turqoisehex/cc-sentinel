---
name: cold
description: Cold start preparation for context handoff. Makes state files zero-context ready with orphan scans and cross-document consistency checks. Use before session end or when context is high (85%+).
---

# /cold — Cold Start Preparation

**Trigger:** Run before session end or when context is high (85%+). Makes CT cold-start ready for a zero-context session.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

## Procedure

**Abbreviations:** CT=your channel CT file (or `CURRENT_TASK.md` if unchanneled). BACKLOG=your project backlog or sprint checklist (if you use one). PLAN=your implementation plan (if you use one).

### Step 0a: Read YAML frontmatter

If the state file (CT) starts with a `---` YAML frontmatter block, read it first. The frontmatter contains structured session context from the previous session: `goal`, `now`, `done_this_session`, `decisions`, `next`, `files_created`, `files_modified`. Use this for fast orientation before reading the full markdown body.

### Step 0: Gate checks and task setup

1. **Sonnet check.** If `scripts/wait_for_results.sh` exists (Commit Enforcement installed): check for an active Sonnet listener. If no heartbeat, warn: "No Sonnet listener — Step 1 will use subagents instead of Sonnet dispatch." If `wait_for_results.sh` does not exist (Core-only install): skip — Step 1 uses subagents directly.
2. **Template check.** If CT Active Task is `(none)` and no plan steps: report "CT at template — nothing to prepare" and **stop**.
3. TaskCreate every step below. Mark in_progress→completed.

### Step 1: Delegate cold-start preparation to Sonnet

Do NOT read backlog or plan in parent — delegate to Sonnet. Identify session transcript (do NOT use `ls -t` — parallel sessions corrupt mtime):
```bash
SESSION_ID=$(tail -1 ~/.claude/history.jsonl | sed 's/.*"sessionId":"\([^"]*\)".*/\1/')
# Validate extraction succeeded (should be UUID-like, not full JSON)
echo "SESSION_ID=$SESSION_ID" && [[ "$SESSION_ID" =~ ^[a-f0-9-]+$ ]] || { echo "ERROR: Failed to extract sessionId"; exit 1; }
SESSION_JSONL=~/.claude/projects/<PROJECT_SLUG>/${SESSION_ID}.jsonl  # Replace <PROJECT_SLUG> with your project path slug
echo "$SESSION_JSONL"
```

**Dispatch decision — four-way case table:**

| `CC_DUO_MODE` | `wait_for_results.sh` exists | Behavior |
|---|---|---|
| unset (default) | yes | Native dispatch via `Agent(model: "sonnet")`. Ignore listener infrastructure. |
| unset (default) | no (core-only) | Native dispatch via `Agent(model: "sonnet")`. Same as above — core-only install still uses native dispatch. |
| `1` (duo) | yes + listener active | File-based dispatch to `_pending_sonnet/`. Write prompt to `verification_findings/_pending_sonnet/[chN/]cold_prep_<timestamp>.md`. Existing behavior. |
| `1` (duo) | yes + no listener | Warn: "No Sonnet listener — Step 1 will use subagents instead." Execute the two agent tasks directly as subagents. |

In default mode, `CC_DUO_MODE` is unset and native dispatch takes priority regardless of whether listener infrastructure exists on disk.

**Default mode:** Spawn the two agent tasks as Sonnet subagents via `Agent(model: "sonnet")` using the prompt content below.

**Duo mode:** Write prompt to `verification_findings/_pending_sonnet/[chN/]cold_prep_<timestamp>.md`. Wait for results:
```bash
rm -f verification_findings/cold_prep_result[_chN].md verification_findings/transcript_orphan_result[_chN].md
bash scripts/wait_for_results.sh verification_findings/cold_prep_result[_chN].md verification_findings/transcript_orphan_result[_chN].md
```

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
> 2. Your project backlog file (if you maintain one — e.g., `BACKLOG.md`, `TODO.md`, or a sprint checklist)
> 3. Your implementation plan file (if you maintain one — e.g., `PLAN.md`, `IMPLEMENTATION_PLAN.md`)
>
> Since the session is ending, no further work will be completed. Classify each item by its current tracking state, not by whether it was "active."
>
> **A. Orphan scan.** Extract every discrete item from CT (tasks, decisions, TODOs, action items, follow-ups, deferred work, design choices, non-done status markers). For each, classify using the first matching row (evaluate top-to-bottom):
>
> | Classification | Meaning | Action |
> |---|---|---|
> | **Incomplete** | Was active but will NOT be completed (the session is ending) | Write to BOTH backlog and plan now. Keep in CT with status and context for next session. |
> | **Permanent-home** | Already tracked in BOTH backlog and plan with matching detail | Verify by grep in both files. If truly present in both, no action needed. |
> | **Partial-home** | Tracked in backlog but not plan, or plan but not backlog | Write to the missing document now. |
> | **Orphan** | Not in backlog, not in plan | Write to BOTH backlog AND plan now. |
> | **Done** | Completed and verified | Must be in Completed Steps section of CT with a one-line summary (e.g., "Step 3: implemented X — verified by test"). If not, add it. |
> | **Dead** | Explicitly dropped with rationale | Remove from CT. If rationale is worth preserving, note it in the relevant spec or backlog. |
>
> Orphan = failure. Zero orphans is the target. Also grep every file path referenced in CT to verify it exists on disk.
>
> **Placement guidance for backlog/plan writes:** When writing items to backlog, add them under the current sprint's section (find the sprint number in CT's header). When writing to plan, add under the relevant feature area or create a "Deferred from Sprint N" section if no area fits. Match the surrounding document's format (checkboxes for backlog, bullet descriptions for plan files).
>
> **B. Cold-start quality pass on CT.** Update CT so a zero-context session can execute every item. For each plan step verify:
> 1. Self-contained context — no "as discussed" or "per earlier decision." State the decision inline.
> 2. Concrete file paths — not "the spec" but the actual path (e.g., `docs/specs/feature_spec.md`).
> 3. Acceptance criteria — what does "done" look like?
> 4. Explicit dependencies — if step N requires step M's output, say so.
> 5. No stale references — grep to verify every path mentioned exists on disk.
> 6. Status markers resolved — every non-done marker has context.
> 7. Sprint/phase context in CT header area (next to Active Task/Status): sprint number, phase (/0-/5), and the most recent commit hash (run `git log --oneline -1`).
>
> Litmus test: re-read CT as if you have never seen this project. Any "what does this mean?" = a gap to fix.
>
> **C. Cross-document consistency.** Catalog all discrepancies first, then fix all:
> - CT → backlog: every active/deferred CT item has a corresponding entry in backlog. If a CT item is a sub-bullet of a step already tracked in backlog, verify the parent item's backlog entry covers it. If unsure whether something is a sub-step or standalone, create a top-level backlog entry.
> - backlog → CT: every "in progress" backlog item either appears in CT or has deferral rationale noted in backlog next to the item.
> - CT → plan: multi-sprint items exist in plan.
> - File references → disk: every path in CT exists (glob/grep).
>
> **D. Write results to `verification_findings/cold_prep_result[_chN].md`** with this format:
> ```
> COLD_PREP_COMPLETE
> Orphans found and resolved: N
> Incomplete items written to backlog/plan: N
> Stale references fixed: N
> CT quality gaps fixed: N
> Cross-doc discrepancies fixed: N
> Unresolvable issues: [list, or "none"]
> ```

**Transcript orphan agent prompt** (second agent in the same prompt file — include the `SESSION_JSONL` path from the "Before dispatching" step):

> **Transcript orphan scan.** The Opus session transcript is at `SESSION_JSONL_PATH_HERE`. This is a JSONL file where each line is a JSON object. Extract actionable items by filtering for these `type` values:
> - `"user"` — the developer's messages (decisions, requests, questions, TODOs)
> - `"assistant"` — Opus responses (design choices, commitments, deferred work)
>
> Ignore `progress`, `hook_progress`, `tool_use`, `tool_result`, and `system` types — they are mechanical.
>
> From the user and assistant messages, extract every discrete actionable item: decisions made, TODOs mentioned, design choices, user requests, questions raised, action items, deferred work, and anything the user said that implies future work.
>
> For each extracted item, check whether it is captured in at least one of:
> 1. `CURRENT_TASK.md` (CT)
> 2. Your project backlog file (if you maintain one — e.g., `BACKLOG.md`, `TODO.md`, or a sprint checklist)
> 3. Your implementation plan file (if you maintain one — e.g., `PLAN.md`, `IMPLEMENTATION_PLAN.md`)
>
> Classify each item:
>
> | Classification | Meaning | Action |
> |---|---|---|
> | **Captured** | Present in CT, backlog, or plan with sufficient detail | No action. Note where it lives. |
> | **Partial** | Referenced but missing key context (e.g., decision recorded but rationale omitted) | Add missing detail to the document where it already appears. |
> | **Dropped** | Not in any document | Write to CT as a new action item or decision. If it's multi-sprint scope, also write to plan. If it's current-sprint scope, also write to backlog. |
>
> Dropped = failure. The whole point of this scan is to catch things the session discussed that never made it to disk.
>
> **Write results to `verification_findings/transcript_orphan_result[_chN].md`** with this format:
> ```
> TRANSCRIPT_SCAN_COMPLETE
> Session transcript: [path]
> Items scanned: N
> Captured: N
> Partial (enriched): N
> Dropped (rescued): N
> Unresolvable: [list, or "none"]
> ```
> For each Dropped item, include a one-line summary of what was rescued and where it was written.

When both results appear, read them. Unresolvable issues → add to CT as flagged items (e.g., "UNRESOLVED from /cold: [description]").

### Step 2: Grill

Read both agent result files and CT. For each grill question, verify checkable answers with grep/read. Fix CT problems directly; for backlog/plan problems, add flagged items to CT (e.g., "FIX IN BACKLOG: [description]") — do NOT read backlog/plan in parent.

1. **"Where does this break?"** — Different day, sprint phase, or post-compaction start. What assumptions are baked in?
2. **"What have I not checked?"** — Zero stale references? Recent commits (`git log --oneline -3`) reflected in CT?
3. **"What's most likely wrong?"** — Implicit orphans (decisions buried in paragraphs). Stale status markers.
4. **"What assumption haven't I verified?"** — Sprint number correct? Commit hash right (`git log --oneline -1`)? Agent results report zero unresolvable?

### Step 3: Commit

If CT, backlog, or plan were modified, commit. If all three are clean, skip — no empty commits.

If `scripts/channel_commit.sh` exists (Commit Enforcement module installed):
```bash
bash scripts/channel_commit.sh --channel N --files "CURRENT_TASK_chN.md <backlog-file> <plan-file>" -m "cold: state files cold-start ready" --skip-squad
```
`--skip-squad` — per-commit agents provide sufficient coverage for state-file-only changes.

If channel_commit.sh is not available (Core-only install):
```bash
git add CURRENT_TASK_chN.md <backlog-file> <plan-file>
git commit -m "cold: state files cold-start ready"
```

Report: orphans resolved (N), transcript items rescued (N), incomplete items written (N), stale refs fixed (N), grill issues (N found/N fixed).

---

## Notes

- State files only — code must already be committed.
- /cold ≠ template reset. For that: `/5` Step 9. Step 0 guards against template-state CT.
- Per-commit agents in channel_commit.sh provide verification. No /verify needed.
