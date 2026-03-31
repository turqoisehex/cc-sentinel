---
goal: ""
now: ""
test: ""
done_this_session: []
blockers: []
questions: []
decisions: []
findings: []
worked: []
failed: []
next: ""
files_created: []
files_modified: []
---

# CURRENT TASK

> **This file is the single source of truth for what CC is doing right now.**
> CC reads this before every action. When it says "No active task," there is
> nothing in progress.

---

## How To Use This File

1. **Starting a new task:** Copy this template's structure below. Fill in the
   Active Task name, write the Big Picture Check (Step 0), then write the
   numbered plan. Set status to "AWAITING USER APPROVAL." Do NOT execute
   anything until the user approves.

2. **During execution:** Work one step at a time. After completing each step,
   mark it done in the Completed Steps section with a one-line summary. Commit
   to git. Then proceed to the next step.

3. **After compaction:** Read CLAUDE.md first, then this file. The Completed
   Steps section tells you where you left off. Resume from the next unchecked
   step.

4. **When the task is complete:** Before clearing, scan this file for:
   - Design decisions, TODOs, action items, "next step" suggestions
   - **Every non-complete status marker**
   Each must be resolved, explicitly dropped with rationale, or have a permanent
   home in project files. Verify against source files — not memory or summaries.
   Discoverability test: *would it be found from docs alone?* If not, write it
   to its home first. THEN overwrite this file with the template.

---

## Active Task: (none)

**Status:** No active task.

---

## Big Picture Check (Step 0)

(How does this task fit the current plan? What are the dependencies? What
authoritative files need to be read before planning?)

---

## Plan

(Numbered steps go here. Each step must be:
- Small enough to execute and verify in one turn
- Have clear acceptance criteria
- Be independently commitable)

---

## Execution Notes

- **One step at a time.** Do not batch steps.
- **Compact freely.** This file survives compaction.
- **After compaction:** Read CLAUDE.md, then this file. Before resuming, verify your understanding of the current step by reading the actual target file(s). Do not trust the compacted summary's description of file state — verify against source. Then continue.
- **When in doubt, ASK.** Do not guess at design intent.
- **Think before answering.** The first assessment is probably overconfident.
- **Context thresholds fire automatically** at 50/65/75/85/95%. Follow their instructions.

---

## Completed Steps

(Mark each step done here with a one-line summary as you go.)
