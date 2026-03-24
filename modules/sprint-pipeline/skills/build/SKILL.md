---
name: build
description: "Automated build execution from approved plan. Routes tasks by classification (Agent/Opus/Sonnet/Parent), commits at logical boundaries. Phase /3 of the sprint pipeline. Also invoked as /3."
---

# /build — Build (alias: /3)

**Trigger:** After `/2` produces approved plan, or for mechanical sprint tasks.

**Gate:** If `/2` invoked this session and incomplete, finish `/2` first. `/3` requires a finalized plan in CT with classified tasks.

**Execution is fully automated.** After plan approval, assume developer absent. Never pause to ask "shall I continue?"

Only pause when: (1) waiting for agents, (2) a design decision genuinely blocks with no safe default.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step in CT. Mark in_progress->completed.

## Procedure

For each step in CT:

1. Read CT for current step.

2. Execute by classification:
   - **`[AGENT]`**: Spawn subagent with step description, acceptance criteria, file paths, targeted context.
   - **`[OPUS]`**: Execute directly. Requires conversation context or design judgment.
   - **`[PARENT]`**: Execute directly. Orchestration or user-facing decision.
   - **`[SONNET]`**: Dispatch to `_pending_sonnet/[chN/]`. Wait via `wait_for_results.sh` (background). Do NOT execute yourself.

3. Update CT — cold-start ready, mark completed steps.

4. Repeat until a **commit boundary** (see below).

5. Commit at boundary:
   ```bash
   bash scripts/channel_commit.sh --channel N --files "<files>" -m "<message>" --skip-squad
   ```

6. Repeat from step 1.

### Commit boundaries

Commit once per logical unit, not per step. Each commit spawns 2 verification agents + test suite.

**Commit after:** completing a task group or phase boundary, finishing all steps that touch the same file set, completing a batch of related tasks, or before switching to a different subsystem.

**Do not commit after:** each individual step, CT-only status updates mid-phase, or trivially small changes.

**Always commit before:** pausing for a design decision, dispatching dependent work, or ending a session.

## Batching rules

**Batch when ALL true:** same code pattern, same spec section, content/data additions only (zero logic), <300 lines inserted.

**Never batch when ANY true:** control flow/state/engine logic, multiple subsystems, design judgment required, different spec sections.

## Design decisions during build

When deferring: (1) note in CT under "Deferred Decisions" immediately, (2) if blocks later step: implement most conservative default, mark provisional, (3) present all deferred at end of `/3`.

## Completion

Announce `/3` complete, readiness for `/4` (`/perfect`). Present deferred decisions if any.
