# /design — Design + Plan (alias: /2)

**Trigger:** New features, spec gaps, design decisions needed.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress→completed.

## Procedure

### Step 1: Brainstorm

Invoke `superpowers:brainstorming` skill. Flow: brainstorm → design doc → spec review → `superpowers:writing-plans`.

### Step 2: writing-plans produces detailed implementation plan

Let the skill complete fully before proceeding.

### Step 2b: Classify tasks for Opus/Sonnet split

Review every task. Classify each as `[AGENT]`, `[OPUS]`, `[SONNET]`, or `[PARENT]`:

| Tag | When to use |
|-----|------------|
| `[AGENT]` | Self-contained with clear file paths + acceptance criteria. Runs as Opus subagent. |
| `[SONNET]` | Mechanical, pattern-following: spec-to-const definitions, scaffolding from template, bulk rename, test implementation from pattern. |
| `[OPUS]` | Requires parent context, judgment, or design decisions: enriching/rewriting code, refactoring logic, cross-cutting propagation, design invariants, domain-specific UX, architecture. |
| `[PARENT]` | Requires conversation context or orchestration: final verification, squad, user-facing decisions. |

Annotate each task heading with its tag. Add summary table at top. MANDATORY — every plan with >5 tasks has Sonnet-eligible work. If none qualifies, state why.

### Step 3: Decision externalization

**Cannot be delegated — only parent has conversation context.**

BEFORE writing CT:
1. Replay the entire brainstorming conversation.
2. List every user decision, approval, rejection, refinement, constraint.
3. For each: grep the design doc for evidence it's in a file.
4. Missing → write to design doc NOW.

Risk: brainstorming generates the most decisions per turn. They feel captured because they're in conversation. They are NOT captured until in a file.

### Step 4: Scrap and rewrite CT

"Knowing everything you know now, scrap the initial CT and write the thorough, complete, cold-start-ready version with full plan."

Required sections: numbered steps with checkboxes + acceptance criteria, key file paths + infrastructure status, design decisions with rationale, out-of-scope list, each task classified `[AGENT]`/`[OPUS]`/`[SONNET]`/`[PARENT]` (default `[OPUS]`).

Anti-lost-in-the-middle: write in segments of ~7 items, count structural elements, cross-check against plan headings, reverse-scan last third.

### Step 5: Phase-gate verification

MANDATORY SONNET DELEGATION. Write prompt to `verification_findings/_pending/[chN/]plan_adversarial_<timestamp>.md`. Agent writes to `verification_findings/plan_adversarial[_chN].md`. Wait: `bash scripts/wait_for_results.sh verification_findings/plan_adversarial[_chN].md` (`run_in_background: true`). Checks: plan↔design doc match, classification correctness, missing dependencies, cross-model dependencies. Fix issues before proceeding.

### Step 6: Generate Sonnet prompt (MANDATORY)

Always classify. Always generate. If Step 2b found zero [SONNET] tasks, state why and skip.

For [SONNET] tasks, write dispatch-ready prompt to `verification_findings/_pending/[chN/]sonnet_<feature>_<timestamp>.md`. Use `type: implementation` for code tasks, `type: squad` for analysis (see `channel-routing.md` Dispatch Type Selection).

YAML frontmatter required:
```yaml
---
type: implementation
tasks:
  - name: task-name
    signal_file: verification_findings/sonnet_task_done[_chN].md
---
```

Prompt body MUST include: task list with acceptance criteria, file paths, code patterns, field mappings, what NOT to do (Opus-reserved), cross-model dependencies, channel routing (`SENTINEL_CHANNEL=N`).

**Sonnet session rules (include in prompt):** Read CT + shared CT + CLAUDE.md + project-specific rules files first. Do NOT modify files outside task list. Do NOT make design decisions — flag for Opus. Mark completed tasks `[SONNET-DONE]` in CT.

### Step 7: Present for user approval

Show plan (with classification table) and Sonnet prompt. Announce `/2` complete. Do NOT proceed to `/3` until user approves.
