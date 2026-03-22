# /cold — Cold Start Preparation

**Trigger:** Run at 75% context warning or before session end. Makes CT cold-start ready for a zero-context session.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

## Procedure

**Abbreviations:** SC=`SPRINT_CHECKLIST.md`, CIP=`COMPREHENSIVE_IMPLEMENTATION_PLAN.md`, CT=your channel CT file (or `CURRENT_TASK.md` if unchanneled).

### Step 0: Gate checks and task setup

1. **Sonnet listener** must be running. If not: STOP, tell user to start it.
2. **Template check.** If CT Active Task is `(none)` and no plan steps: report "CT at template — nothing to prepare" and **stop**.
3. TaskCreate every step below. Mark in_progress→completed.

### Step 1: Delegate cold-start preparation to Sonnet

Do NOT read SC or CIP in parent — delegate to Sonnet. Identify session transcript (do NOT use `ls -t` — parallel sessions corrupt mtime):
```bash
SESSION_ID=$(tail -1 ~/.claude/history.jsonl | sed 's/.*"sessionId":"\([^"]*\)".*/\1/')
# Validate extraction succeeded (should be UUID-like, not full JSON)
echo "SESSION_ID=$SESSION_ID" && [[ "$SESSION_ID" =~ ^[a-f0-9-]+$ ]] || { echo "ERROR: Failed to extract sessionId"; exit 1; }
SESSION_JSONL=~/.claude/projects/<PROJECT_SLUG>/${SESSION_ID}.jsonl  # Replace <PROJECT_SLUG> with your project path slug
echo "$SESSION_JSONL"
```

Write prompt to `verification_findings/_pending/[chN/]cold_prep_<timestamp>.md`. Wait:
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
      - SPRINT_CHECKLIST.md
      - COMPREHENSIVE_IMPLEMENTATION_PLAN.md
  - name: transcript-orphan
    signal_file: verification_findings/transcript_orphan_result[_chN].md
    files:
      - CURRENT_TASK_chN.md
      - SPRINT_CHECKLIST.md
      - COMPREHENSIVE_IMPLEMENTATION_PLAN.md
---
```

> **Cold-start preparation.** Read these files completely — no skimming:
> 1. `CURRENT_TASK_chN.md` (CT — the channel file, not the shared index) when channeled; `CURRENT_TASK.md` when unchanneled
> 2. `SPRINT_CHECKLIST.md` (SC)
> 3. `COMPREHENSIVE_IMPLEMENTATION_PLAN.md` (CIP)
>
> Since the session is ending, no further work will be completed. Classify each item by its current tracking state, not by whether it was "active."
>
> **A. Orphan scan.** Extract every discrete item from CT (tasks, decisions, TODOs, action items, follow-ups, deferred work, design choices, non-done status markers). For each, classify using the first matching row (evaluate top-to-bottom):
>
> | Classification | Meaning | Action |
> |---|---|---|
> | **Incomplete** | Was active but will NOT be completed (the session is ending) | Write to BOTH SC and CIP now. Keep in CT with status and context for next session. |
> | **Permanent-home** | Already tracked in BOTH SC and CIP with matching detail | Verify by grep in both files. If truly present in both, no action needed. |
> | **Partial-home** | Tracked in SC but not CIP, or CIP but not SC | Write to the missing document now. |
> | **Orphan** | Not in SC, not in CIP | Write to BOTH SC AND CIP now. |
> | **Done** | Completed and verified | Must be in Completed Steps section of CT with a one-line summary (e.g., "Step 3: implemented X — verified by test"). If not, add it. |
> | **Dead** | Explicitly dropped with rationale | Remove from CT. If rationale is worth preserving, note it in the relevant spec or SC. |
>
> Orphan = failure. Zero orphans is the target. Also grep every file path referenced in CT to verify it exists on disk.
>
> **Placement guidance for SC/CIP writes:** When writing items to SC, add them under the current sprint's section (find the sprint number in CT's header). When writing to CIP, add under the relevant feature area or create a "Deferred from Sprint N" section if no area fits. Match the surrounding document's format (checkboxes for SC, bullet descriptions for CIP).
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
> - CT → SC: every active/deferred CT item has a corresponding entry in SC. If a CT item is a sub-bullet of a step already tracked in SC, verify the parent item's SC entry covers it. If unsure whether something is a sub-step or standalone, create a top-level SC entry.
> - SC → CT: every "in progress" SC item either appears in CT or has deferral rationale noted in SC next to the item.
> - CT → CIP: multi-sprint items exist in CIP.
> - File references → disk: every path in CT exists (glob/grep).
>
> **D. Write results to `verification_findings/cold_prep_result[_chN].md`** with this format:
> ```
> COLD_PREP_COMPLETE
> Orphans found and resolved: N
> Incomplete items written to SC/CIP: N
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
> 2. `SPRINT_CHECKLIST.md` (SC)
> 3. `COMPREHENSIVE_IMPLEMENTATION_PLAN.md` (CIP)
>
> Classify each item:
>
> | Classification | Meaning | Action |
> |---|---|---|
> | **Captured** | Present in CT, SC, or CIP with sufficient detail | No action. Note where it lives. |
> | **Partial** | Referenced but missing key context (e.g., decision recorded but rationale omitted) | Add missing detail to the document where it already appears. |
> | **Dropped** | Not in any document | Write to CT as a new action item or decision. If it's multi-sprint scope, also write to CIP. If it's current-sprint scope, also write to SC. |
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

Read both agent result files and CT. For each grill question, verify checkable answers with grep/read. Fix CT problems directly; for SC/CIP problems, add flagged items to CT (e.g., "FIX IN SC: [description]") — do NOT read SC/CIP in parent.

1. **"Where does this break?"** — Different day, sprint phase, or post-compaction start. What assumptions are baked in?
2. **"What have I not checked?"** — Zero stale references? Recent commits (`git log --oneline -3`) reflected in CT?
3. **"What's most likely wrong?"** — Implicit orphans (decisions buried in paragraphs). Stale status markers.
4. **"What assumption haven't I verified?"** — Sprint number correct? Commit hash right (`git log --oneline -1`)? Agent results report zero unresolvable?

### Step 3: Commit

If CT, SC, or CIP were modified, commit. If all three are clean, skip — no empty commits.

```bash
bash scripts/channel_commit.sh --channel N --files "CURRENT_TASK_chN.md SPRINT_CHECKLIST.md COMPREHENSIVE_IMPLEMENTATION_PLAN.md" -m "cold: state files cold-start ready" --skip-squad
```

`--skip-squad` — per-commit agents provide sufficient coverage for state-file-only changes.

Report: orphans resolved (N), transcript items rescued (N), incomplete items written (N), stale refs fixed (N), grill issues (N found/N fixed).

---

## Notes

- State files only — code must already be committed.
- /cold ≠ template reset. For that: `/5` Step 9. Step 0 guards against template-state CT.
- Per-commit agents in channel_commit.sh provide verification. No /squad needed.
