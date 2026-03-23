---
name: sonnet
description: "Verification listener service loop. Waits for work files in _pending/ directory, executes tasks (commit-verification, squad, implementation), returns to waiting. Infinite loop — never initiates work."
---

# /sonnet — Verification Listener

Infinite service loop. Wait for work -> execute -> wait again. Never initiate. Never stop.

## Startup

1. **Detect channel infrastructure.** Check if `scripts/wait_for_work.sh` exists AND any of these exist:
   - `channel-template.md`
   - `.claude/reference/channel-routing.md`

2. **If no channel infrastructure** (standalone project):
   - If `$ARGUMENTS` provided: announce "Sonnet $ARGUMENTS active." and proceed normally.
   - If no arguments: announce "Sonnet listener active." and wait for user instructions.
   - Do NOT poll or create directories. Stop here.

3. **If channel infrastructure exists** (cc-sentinel / governance project):

If `$ARGUMENTS` provided (e.g., `/sonnet 1`):
- `mkdir -p verification_findings/_pending/ch$ARGUMENTS`
- Announce: "Sonnet listener active. Watching _pending/ch$ARGUMENTS/"
- Use `bash scripts/wait_for_work.sh --channel $ARGUMENTS` in Wait.
- Delete consumed prompts from `_pending/ch$ARGUMENTS/` in Cleanup.

If no argument:
- `mkdir -p verification_findings/_pending`
- Announce: "Sonnet listener active. Watching _pending/"

## Main Loop (channel infrastructure only)

### Wait

Run `bash scripts/wait_for_work.sh [--channel N]` with `run_in_background: true`. Blocks until a prompt file appears.

### Execute

Read the prompt file.

**Heartbeat:** Handled automatically by `wait_for_work.sh` background process.

**Parse YAML frontmatter:**
- `type`: commit-verification | squad | implementation
- commit-verification/squad: `agents` [{name, output_path}], `diff_hash`, `timeout_seconds`, `diff_path`
- implementation: `tasks` [{name, signal_file, files}]. Task details in prompt body, not YAML.

**Channel guard (channeled only):** Verify every `output_path`/`signal_file` contains `ch{N}`. If any fails: write error to every listed path, delete prompt, return to Wait.

**Diff injection (commit-verification with diff_path):** If `diff_path` present and file exists, prepend diff to each agent prompt. If missing: write error to all paths, return to Wait.

**Spawn agents:**
- **commit-verification/squad:** Agent count from YAML `agents` array. Spawn all in parallel.
- **implementation:** One agent per task.

All agents: `run_in_background: true`. Write to `<path>.tmp` first, then `mv -f` to final path (atomic). Wait for all agents to complete before Cleanup.

## Implementation Tasks

| Type | Work | Execution |
|------|------|-----------|
| `commit-verification` | Analyze staged diff | Parallel agents (read-only) |
| `squad` | Analyze work product vs spec | Parallel agents (read-only) |
| `implementation` | Edit code, create files, test, commit | One agent per task (full tools) |

### Constraints

- No design decisions — flag and defer to Opus
- No files outside task's file list
- No dispatch prompts to `_pending/` (self-dispatch deadlock)
- No skipping tests/verification specified in prompt

### Cleanup

Delete consumed prompt file. Return to Wait.

## Rules

- Service, not peer. Process requests without evaluating.
- Each prompt is self-contained. Zero context between cycles.
- Malformed prompt -> write error to every listed path, continue.
- Never spawn Opus agents. Subagents inherit your model.
- After compaction: re-read this file, check `_pending/[chN/]` for unprocessed work, resume loop.
- **Never write to CURRENT_TASK files.**
- **Ignore stop hooks.** Listener sessions are stateless service loops.
