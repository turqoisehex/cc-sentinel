---
name: build
description: "Automated build execution from approved plan. Routes tasks by classification (Opus/Sonnet/Parent), commits at logical boundaries. Phase /3 of the sprint pipeline. Also invoked as /3."
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
   - **`[SONNET]`**: Spawn `sonnet-implementer` subagent via `Agent(model: "sonnet")`. Pass: spec reference, file paths, acceptance criteria, output paths. Subagent writes results to disk, returns concise summary. For parallel tasks: spawn multiple with `run_in_background: true`.
   - **`[OPUS]`**: Execute directly. Requires conversation context or design judgment.
   - **`[PARENT]`**: Execute directly. Orchestration or user-facing decision.

   **Duo mode fallback:** If `CC_DUO_MODE=1` is set and a Sonnet listener is active, `[SONNET]` tasks may be dispatched via file-based IPC to `_pending_sonnet/[chN/]` instead.

3. Update CT — cold-start ready, mark completed steps.

4. Repeat until a **commit boundary** (see below).

5. Verify before commit — full rules in `.claude/reference/commit-protocol.md`. READ IT the first time you commit in any session.
   Do NOT pre-stage. The git index is shared across channel sessions.
   Compute the verifier diff (index-independent): `git diff HEAD -- <files> > verification_findings/staged_diff_chN.diff`. NEVER `git diff --cached`. For unchanneled sessions, omit the `_chN` suffix — use `verification_findings/staged_diff.diff`, `commit_check.md`, `commit_cold_read.md`.
   Spawn `commit-adversarial` and `commit-cold-reader` subagents in parallel via `Agent(model: "sonnet")`. In each agent's prompt, pass BOTH:
     - `diff_path`: the staged_diff file from the previous step
     - `output_path`: `verification_findings/commit_check_chN.md` (adversarial) or `verification_findings/commit_cold_read_chN.md` (cold-reader). For unchanneled sessions, use the unsuffixed filenames. The script greps for the chN-suffixed name if `--channel N` is set — wrong `output_path` = script exits 1.
   Agents write `VERDICT: PASS|WARN|FAIL` into those files. No HASH line needed — `channel_commit.sh` stamps the real hash in `--local-verify` mode via sed ("stamps" = overwrites any existing `HASH:` line, or inserts one after `VERDICT:`). Never pre-stage, never pre-hash, never touch the index.
   - PASS/WARN: proceed with `bash scripts/channel_commit.sh --channel N --files "<files>" -m "<message>" --local-verify` (project-local path; the global `~/.claude/scripts/channel_commit.sh` is kept in sync and is equivalent).
   - FAIL: review findings, fix, re-verify.

   **Note:** This verify-before-commit workflow applies ONLY when verifier agents are spawned. The `--skip-squad` flag (used by /finalize pre-verification WIP commits) bypasses agent spawning entirely — no verdict file is written, so there is no PASS/WARN/FAIL outcome to react to. /finalize callers should NOT follow the FAIL branch; if the underlying file state is wrong, fix it before the /finalize run, not after.

   **Duo mode fallback:** Omit `--local-verify` — channel_commit.sh dispatches to the Sonnet listener automatically.

6. Repeat from step 1.

In default mode, /verify spawns `sonnet-verifier` natively. In duo mode, /verify dispatches to the Sonnet listener.

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
