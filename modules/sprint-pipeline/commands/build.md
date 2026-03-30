# /build — Build (alias: /3)

**Trigger:** After `/2` produces approved plan, or for mechanical sprint tasks.

**Gate:** If `/2` invoked this session and incomplete, finish `/2` first. `/3` requires a finalized plan in CT with classified tasks.

**Execution is fully automated.** After plan approval, assume developer absent. Never pause to ask "shall I continue?"

Only pause when: (1) waiting for agents, (2) a design decision genuinely blocks with no safe default.

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step in CT. Mark in_progress→completed.

## Procedure

For each step in CT:

1. Read CT for current step.

2. Execute by classification:
   - **`[OPUS]`**: Execute directly. Requires conversation context or design judgment.
   - **`[PARENT]`**: Execute directly. Orchestration or user-facing decision.
   - **`[SONNET]`**: Spawn via `Agent(model: "sonnet")` (default mode) or dispatch to `_pending_sonnet/[chN/]` (duo mode). Use dispatch file from `/2` for duo mode. Wait via `wait_for_results.sh` (background). Do NOT execute yourself.

3. Update CT — cold-start ready, mark completed steps.

4. Repeat until a **commit boundary** (see below).

5. Commit at boundary:
   ```bash
   bash scripts/channel_commit.sh --channel N --files "<files>" -m "<message>" --skip-squad
   ```
   If either per-commit agent (commit-adversarial, commit-cold-reader) FAILs: fix, re-run. Always use channel_commit.sh as the public API.

6. Repeat from step 1.

### Commit boundaries

Commit once per logical unit, not per step. Each commit spawns 2 verification agents + test suite — keep the ratio of work to verification high.

**Commit after:** completing a task group or phase boundary, finishing all steps that touch the same file set, completing a batch of related `[SONNET]` tasks, or before switching to a different subsystem.

**Do not commit after:** each individual step, CT-only status updates mid-phase, or trivially small changes that will be followed by more in the same area.

**Always commit before:** pausing for a design decision, dispatching work that depends on committed state, or ending a session.

## Batching rules

**Batch when ALL true:** same code pattern, same spec section, content/data additions only (zero logic), <300 lines inserted.

**Never batch when ANY true:** control flow/state/engine logic, multiple subsystems, design judgment required, different spec sections or categories.

Never cross category boundaries. Split at natural boundary if >300 lines.

## Design decisions during build

Design decision = wrong answer requires architectural rework. Implementation choices with clear precedent (project reference docs) are not design decisions.

When deferring: (1) note in CT under "Deferred Decisions" immediately, (2) if blocks later step: implement most conservative default, mark provisional, (3) present all deferred at end of `/3`.

## Completion

Announce `/3` complete, readiness for `/4` (`/perfect`). Present deferred decisions if any.
