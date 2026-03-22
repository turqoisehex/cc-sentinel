# /prune-rules — Review Accumulated Corrections

**Trigger:** At soft cap (15 corrections), or when upgrading to a new model.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix.

### Step 0: Authorize governance edit

Write `GOVERNANCE-EDIT-AUTHORIZED` as a standalone line in CT. Must be the ENTIRE line — `grep -qx` match required.

### Step 1: Extract all corrections

Read Accumulated Corrections in CLAUDE.md. List every entry with index number.

### Step 2: Present each for review

For each: rule text, `git blame` date/commit, recent triggers (search last 20 commits + verification_findings), recommendation (**Keep**/triggered or high-risk, **Update**/stale wording, **Remove**/superseded or obsolete, **Promote**/move to `.claude/rules/` or `.claude/reference/`).

### Step 3: Wait for user decisions

Do NOT auto-remove or auto-update. User decides each item.

### Step 4: Apply and commit

Commit the updated CLAUDE.md and CT file with `--skip-squad`.

### Step 5: Remove governance marker

Remove `GOVERNANCE-EDIT-AUTHORIZED` from CT.
