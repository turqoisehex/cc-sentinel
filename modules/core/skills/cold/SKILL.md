---
name: cold
description: Cold start preparation for context handoff. Default mode (slim) edits CT in place — parent-direct, no dispatch, ~1% context burn. `/cold full` adds backlog/plan reconciliation, transcript orphan scan, and grill. Use slim mid-session at 80%+; use full at session end.
---

# /cold — Cold Start Preparation

**Modes:**
- **`/cold`** (default, slim) — parent reads CT and edits it in place to be cold-start ready. No agents, no grill. Safe to run at 80%+ context.
- **`/cold full`** — slim CT pass + two Sonnet agents (cold-prep + transcript-orphan) + parent grill. Use at session end when you want orphan rescue and full backlog/plan cross-check.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

---

## Default (slim) procedure

**Trigger:** Run when context is high (80%+) or before /clear/compact, to make CT readable by a zero-context session.

### Step 0: Resolve target CT

- Channeled session: target = `CURRENT_TASK_chN.md` for the active channel.
- Unchanneled session: target = `CURRENT_TASK.md`.
- If both shared CT and a channel CT are live in this session, edit both.

### Step 1: Read CT in full

Read the entire target CT file (Read tool, no offset). Do not skim. Do not delegate.

### Step 2: Edit CT in place for cold-start readability

Edit only — never rewrite from scratch, never blank. For each active section:

- **Self-contained context.** Remove "see above" / "from earlier in this session" / "as we discussed" references. Replace with concrete content or a file:section pointer.
- **Concrete file paths.** Every referenced file is a real, current path on disk. Spot-check the ones you're least sure about.
- **Current status.** Status markers reflect what is actually true now, not what was true when the line was written. Phase markers (e.g., "/3 done", "R3 fixes applied") match the actual state.
- **Active Channels table.** Each row's Phase and Status columns reflect the real current state. Remove or update stale "in flight" markers.
- **Next action concrete.** The "Next action" for each active task is executable by a fresh session: command line, file paths, decision criteria — no implicit context.
- **Resolve dangling references.** Anything pointing to a verification_findings/ file, a commit hash, or a plan section: confirm it still exists (Bash `ls` or grep). Fix or remove.

If shared CT and channel CT both exist, ensure they don't contradict each other (Active Channels table in shared CT vs. channel CT's own status).

Report: "/cold slim: edited <file>, fixed N stale refs, resolved N dangling references." If nothing needed changing: "/cold slim: CT already cold-start ready."

---

## `/cold full` procedure

**Trigger:** Session end, or when you want backlog/plan reconciliation + transcript orphan rescue in addition to the CT pass.

Run the slim procedure (Steps 0–2 above) first, then continue with the steps below.

### Step 0a: Read YAML frontmatter

If the state file (CT) starts with a `---` YAML frontmatter block, read it first. The frontmatter contains structured session context from the previous session: `goal`, `now`, `done_this_session`, `decisions`, `next`, `files_created`, `files_modified`. Use this for fast orientation before reading the full markdown body.

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
bash ~/.claude/scripts/wait_for_results.sh verification_findings/cold_prep_result[_chN].md verification_findings/transcript_orphan_result[_chN].md
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

### Step 2: Grill and report

Read both agent result files and CT. For each grill question, verify checkable answers with grep/read. Fix CT problems directly.

1. **"Where does this break?"** — Different day, sprint phase, or post-compaction start.
2. **"What have I not checked?"** — Zero stale references? Recent commits reflected in CT?
3. **"What's most likely wrong?"** — Implicit orphans. Stale status markers.
4. **"What assumption haven't I verified?"** — Sprint number? Commit hash? Agent results?

Report: orphans resolved (N), transcript items rescued (N), incomplete items written (N), stale refs fixed (N), grill issues (N found/N fixed).

---

## Notes

- Slim `/cold` is parent-direct: no agents, no grill. Use freely at 80%+.
- `/cold full` is state-file housekeeping only.
- /cold != template reset. For that: `/5` Step 9.
