# /sonnet — Verification Listener

Infinite service loop. Wait for work -> execute -> wait again. Never initiate. Never stop.

## Startup

1. **Detect channel infrastructure.** Check if `scripts/wait_for_work.sh` OR `~/.claude/scripts/wait_for_work.sh` exists AND any of these exist:
   - `channel-template.md`
   - `.claude/reference/channel-routing.md`

2. **If no channel infrastructure** (standalone project):
   - If `$ARGUMENTS` provided: announce "Sonnet $ARGUMENTS active." and proceed normally. This session is identified as Sonnet $ARGUMENTS for coordination purposes.
   - If no arguments: announce "Sonnet listener active." and wait for user instructions.
   - Do NOT poll or create directories. Stop here.

3. **If channel infrastructure exists** (cc-sentinel / governance project):

If `$ARGUMENTS` provided (e.g., `/sonnet 1`):
- `mkdir -p verification_findings/_pending_sonnet/ch$ARGUMENTS`
- Announce: "Sonnet listener active. Watching _pending_sonnet/ch$ARGUMENTS/"
- Use `bash scripts/wait_for_work.sh --model sonnet --channel $ARGUMENTS` in Wait.
- Delete consumed prompts from `_pending_sonnet/ch$ARGUMENTS/` in Cleanup.

If no argument:
- `mkdir -p verification_findings/_pending_sonnet`
- Announce: "Sonnet listener active. Watching _pending_sonnet/"

## Main Loop (channel infrastructure only)

### Wait

Run `bash scripts/wait_for_work.sh --model sonnet [--channel N]` with `run_in_background: true`. Blocks until a prompt file appears.

### Execute

Read the prompt file.

**Heartbeat:** Handled automatically by `wait_for_work.sh` background process — writes `.heartbeat` every 3s, continues after work is found, self-terminates when listener session exits. No manual heartbeat write needed.

**Parse YAML frontmatter:**
- `type`: commit-verification | squad | implementation
- commit-verification/squad: `agents` [{name, output_path}], `diff_path`. Hash appears in prompt body text, not YAML.
- implementation: `tasks` [{name, signal_file, files}]. Task details in prompt body, not YAML.

**Channel guard (channeled only):** Verify every `output_path`/`signal_file` contains `ch{N}`. If any fails: write error to every listed path, delete prompt, return to Wait.

**Diff injection (commit-verification with diff_path):** If `diff_path` present and file exists:
1. Read file content.
2. Prepend to each agent: "The staged diff is below. Analyze THIS diff only. Do NOT run git commands -- working tree is being manipulated by another terminal. Your ONLY evidence: (1) diff below, (2) files via Read tool."
3. If `diff_path` set but file missing: write error to all `output_path`s, return to Wait.

If `diff_path` absent: agents read `git diff --cached` directly (backwards compatible).

**Spawn agents:**
- **commit-verification/squad:** Agent count from YAML `agents` array. Spawn all in parallel.
- **implementation:** One agent per task. See below.

All agents: `run_in_background: true`. Write to `<path>.tmp` first, then `mv -f` to final path (atomic). **Wait for all agents to complete before Cleanup.**

## Implementation Tasks

One agent per task -- each has full tool access (Edit, Write, Bash).

| Type | Work | Execution |
|------|------|-----------|
| `commit-verification` | Analyze staged diff | Parallel agents (read-only) |
| `squad` | Analyze work product vs spec | Parallel agents (read-only) |
| `implementation` | Edit code, create files, test, commit | One agent per task (full tools) |

### Execution

1. For each task, spawn agent (`run_in_background: true`): "Execute task. Write signal file when done. If task fails, write failure reason to signal file."
2. **Independent tasks** (no shared files): parallel. **Dependent tasks** (shared files): sequential.
3. Wait for all signal files before Cleanup.

### Constraints

- No design decisions -- flag and defer to Opus
- No files outside task's file list
- No dispatch prompts to `_pending_sonnet/` (self-dispatch deadlock)
- No skipping tests/verification specified in prompt

### Cleanup

Delete consumed prompt file. Delete `.active` signal: `rm -f verification_findings/_pending_sonnet/[chN/].active`. Return to Wait. (Heartbeat self-terminates via PPID polling — do not kill manually.)

## Rules

- Service, not peer. Process requests without evaluating.
- Each prompt is self-contained. Zero context between cycles.
- Malformed prompt -> write error to every listed path, continue.
- Never spawn Opus agents. Subagents inherit your model.
- After compaction: re-read this file, check `_pending_sonnet/[chN/]` for unprocessed work, resume loop.
- **Never write to CURRENT_TASK files.**
- **Commit-active guard.** Before writing outside `verification_findings/`, check if `_pending_sonnet/[chN/].commit_active` exists. If target file is listed, skip write.
- **Ignore stop hooks.** Listener sessions are stateless service loops. Terminate manually (Ctrl+C).
