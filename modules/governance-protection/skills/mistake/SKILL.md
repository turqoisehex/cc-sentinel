---
name: mistake
description: Correct and encode a mistake into CLAUDE.md accumulated corrections. Use after any caught mistake — by user, verification, or hook. Searches for existing rules, strengthens or adds new ones.
---

# /mistake — Correct and Encode

**Trigger:** After any caught mistake — by user, verification, or hook.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix.

### Step 0: Authorize governance edit

Write `GOVERNANCE-EDIT-AUTHORIZED` as a standalone line in CT. Must be the ENTIRE line — `grep -qx` match required.

### Step 1: Describe the mistake

One sentence: the file, the rule violated, the incorrect output. No hedging.

### Step 2: Search for existing rule

Grep Accumulated Corrections in CLAUDE.md for keywords from the mistake. Not memory.

### Step 3: Strengthen or add

- **Found:** Update existing rule with new trigger pattern. Make harder to skip.
- **Not found:** Add: "Never do X. Always do Y instead." + one-sentence rationale.

### Step 4: Check soft cap

Count Accumulated Corrections entries. If >= 15: warn user, invoke `/prune-rules` before adding.

### Step 5: Commit

```bash
bash scripts/channel_commit.sh --files "CLAUDE.md" -m "fix: encode correction" --governance
```

### Step 6: Remove governance marker

Remove `GOVERNANCE-EDIT-AUTHORIZED` from CT.
