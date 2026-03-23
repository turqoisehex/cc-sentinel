---
name: rewrite
description: "Ground-up rewrite of a subsystem informed by hindsight. Not refactoring — a fresh implementation. Inventories, extracts requirements, designs, builds alongside, proves equivalence, swaps."
---

# /rewrite — Elegant Rewrite

**Trigger:** `/rewrite <subsystem>` — e.g., `/rewrite auth subsystem`

"Knowing everything you know now, scrap this and implement the elegant solution." Not refactoring — ground-up rewrite informed by hindsight.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

## Procedure

### Step 1: Understand what exists

Read the subsystem completely — what the code does, not what comments say. Write **Current State Inventory** to `verification_findings/rewrite_inventory[_chN].md`: files + responsibilities, data flow, external interfaces, test coverage.

### Step 2: Understand what it should do

Read spec, design docs, CT, project rules. Write **Requirements Extraction** to the same file.

### Step 3: Catalog the debt

Compare Steps 1 and 2. Write **Debt Catalog** to the same file: accidental complexity, incomplete migrations, over/under-engineering, naming lies.

### Step 4: Design the elegant version

Write **Rewrite Design** to `verification_findings/rewrite_design[_chN].md`: new file structure, data flow, eliminations, preservations, migration strategy.

Principles: one responsibility per file, minimal interfaces, names match behavior, YAGNI, consistent patterns.

Present design to user. Do NOT proceed without approval.

### Step 5: Build alongside

Never rewrite in-place. New files get `_v2` suffix during construction. Old code stays untouched.

TDD: write failing tests first, then implement. One commit per logical unit via `channel_commit.sh`.

### Step 6: Prove equivalence

Before swapping: (1) existing behavioral tests pass on new, (2) new tests pass, (3) no broken callers, (4) full test suite passes. Write to `verification_findings/rewrite_equivalence[_chN].md`.

### Step 7: Swap and clean

Rename new files to final names, update imports, delete old files (no tombstones), run full tests, atomic commit.

### Step 8: Verify

`/squad on <changed files>`. All 5 agents must pass.

## Rules

- The user invoked `/rewrite`. The answer is yes.
- Preserve all behavior unless user explicitly says to change it.
- Finish the migration. No partial rewrites.
- Old code is your spec when spec is ambiguous (unless it's a known bug).
- Max ~10 files. If scope is larger, ask user to narrow.
