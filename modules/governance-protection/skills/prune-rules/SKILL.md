---
name: prune-rules
description: Review and prune accumulated corrections in CLAUDE.md. Use at soft cap (15 corrections), when rules feel stale, or when upgrading to a new model. User decides each item.
---

# /prune-rules — Review Accumulated Corrections

**Trigger:** At soft cap (15 corrections), or when upgrading to a new model.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix.

### Step 0: Authorize governance edit

Write `GOVERNANCE-EDIT-AUTHORIZED` as a standalone line in CT. Must be the ENTIRE line — `grep -qx` match required.

### Step 1: Extract all corrections

Read Accumulated Corrections in CLAUDE.md. List every entry with index number.

### Step 2: Present each for review

For each: rule text, `git blame` date/commit, recent triggers (search last 20 commits + verification_findings), recommendation (**Keep**/triggered or high-risk, **Update**/stale wording, **Remove**/superseded or obsolete, **Promote**/move to an on-demand home).

#### Promotion evaluation

CLAUDE.md is auto-loaded every session — every rule there pays a context cost on every session. **The primary pruning lever is not removal; it is promotion:** moving situational or non-critical rules out of always-loaded CLAUDE.md into a file that loads only when relevant. This recovers soft-cap headroom AND cuts per-session context cost.

**Two-question test — apply to each correction:**

1. **Agent-relevant / ambient?** Does the parent need this rule loaded broadly in (almost) every session — or is it situational, firing only at a specific moment (commit / verify / test-run / deploy / content-edit / engine-change)? (Note: subagents do not read CLAUDE.md; "agent-relevant" means "the parent needs it ambiently.")
2. **Critical to normal healthy functioning?** Would a session go wrong in a hard-to-catch way if this rule were not ambiently loaded? (A pervasive safety/discipline rule with no single trigger = critical. A situational gotcha with a natural trigger-point = not.)

**Decision:** If NOT both (1) AND (2) → **PROMOTE**. If both → **KEEP**. If the bulk is detail already covered by a referenced file → **SLIM** to a one-line pointer.

**Picking the on-demand home + risk:**

The home is the file or skill loaded exactly when the rule applies — a project rules file (e.g. a testing or design-invariants file), a reference doc (loaded "before X"), or the specific skill the rule pertains to (loaded when that skill runs). State the risk:

- **LOW risk:** the home is reliably loaded at the rule's trigger-moment → move fully.
- **MEDIUM risk:** home is usually loaded at the trigger → move the detail, leave a one-line pointer in CLAUDE.md.
- **HIGH risk:** rule applies pervasively with no single trigger → keep it ambient (KEEP or SLIM, not PROMOTE).

### Step 3: Wait for user decisions

Do NOT auto-remove or auto-update. User decides each item.

### Step 4: Apply and commit

**Execution disciplines for promotions (follow in order):**

- **Move-before-remove:** add the rule's full substance to the target file first, verify it landed, and only then remove it from CLAUDE.md. Never remove first — no loss in transit.
- **Universalize public-repo targets:** if the target is a file in a public or shared canonical repo, strip project-specific examples in transit — the public file must stay universal.
- **Don't clobber a contested target:** if the target file has another session's uncommitted work-in-progress, do NOT overwrite it — keep the rule in CLAUDE.md and flag the collision instead.

```bash
bash ~/.claude/scripts/channel_commit.sh --files "CLAUDE.md CURRENT_TASK.md" -m "chore: prune accumulated corrections" --skip-squad
```

### Step 5: Remove governance marker

Remove `GOVERNANCE-EDIT-AUTHORIZED` from CT.
