---
name: design
description: "Design and planning phase: brainstorming, task classification (Opus/Sonnet split), decision externalization, and Sonnet prompt generation. Phase /2 of the sprint pipeline. Also invoked as /2."
---

# /design — Design + Plan (alias: /2)

**Trigger:** New features, spec gaps, design decisions needed.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress->completed.

## Procedure

### Step 1: Brainstorm

Invoke `superpowers:brainstorming` skill. Flow: brainstorm -> design doc -> spec review -> `superpowers:writing-plans`.

### Step 2: writing-plans produces detailed implementation plan

Let the skill complete fully before proceeding.

### Step 2b: Classify tasks for Opus/Sonnet split

Review every task. Classify each as `[OPUS]`, `[SONNET]`, or `[PARENT]`:

| Tag | When to use |
|-----|------------|
| `[SONNET]` | Self-contained with clear file paths + acceptance criteria. Spawned as Sonnet subagent via `Agent(model: "sonnet")`. |
| `[OPUS]` | Requires parent context, judgment, or design decisions. Executed directly by Opus. |
| `[PARENT]` | Requires conversation context, orchestration, or user-facing decisions. |

Classification rules:
1. If a task has clear inputs (file paths), clear outputs (acceptance criteria), and requires no design judgment → `[SONNET]`.
2. When in doubt between OPUS and SONNET → `[OPUS]`. Budget waste from over-classifying as OPUS is recoverable; broken output from under-classifying is not.
3. Everything else → `[SONNET]`. If in doubt between OPUS and SONNET, classify as OPUS.

Annotate each task heading with its tag. Add summary table at top. MANDATORY — every plan with >5 tasks has Sonnet-eligible work.

### Step 3: Decision externalization

**Cannot be delegated — only parent has conversation context.**

BEFORE writing CT:
1. Replay the entire brainstorming conversation.
2. List every user decision, approval, rejection, refinement, constraint.
3. For each: grep the design doc for evidence it's in a file.
4. Missing -> write to design doc NOW.

### Step 4: Scrap and rewrite CT

"Knowing everything you know now, scrap the initial CT and write the thorough, complete, cold-start-ready version with full plan."

Required sections: numbered steps with checkboxes + acceptance criteria, key file paths + infrastructure status, design decisions with rationale, out-of-scope list, each task classified.

### Step 5: Phase-gate verification

**Default mode:** Spawn Sonnet subagent via `Agent(model: "sonnet")` with adversarial plan review prompt. Checks: plan<->design doc match, classification correctness, missing dependencies.

**Duo mode:** MANDATORY SONNET DELEGATION. Write prompt to `verification_findings/_pending_sonnet/[chN/]plan_adversarial_<timestamp>.md`.

### Step 6: Generate Sonnet task specifications (MANDATORY)

For [SONNET] tasks, write task specifications that will be passed to `sonnet-implementer` subagents during /3 build.

**Default mode:** Task specs are embedded directly in the /3 plan (each [SONNET] task's description serves as the subagent prompt).

**Duo mode:** Write dispatch-ready prompt to `verification_findings/_pending_sonnet/[chN/]sonnet_<feature>_<timestamp>.md` with YAML frontmatter.

YAML frontmatter required:
```yaml
---
type: implementation
tasks:
  - name: task-name
    signal_file: verification_findings/sonnet_task_done[_chN].md
---
```

### Step 7: Present for user approval

Show plan (with classification table) and Sonnet prompt. Announce `/2` complete. Do NOT proceed to `/3` until user approves.
