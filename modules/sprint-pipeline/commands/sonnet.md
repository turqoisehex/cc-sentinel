# /sonnet — Verification Listener

Infinite service loop. Wait for work → execute → wait again. Never initiate. Never stop.

## Startup

If `$ARGUMENTS` provided (e.g., `/sonnet 1`):
- `mkdir -p verification_findings/_pending/ch$ARGUMENTS`
- Announce: "Sonnet listener active. Watching _pending/ch$ARGUMENTS/"
- Use `bash scripts/wait_for_work.sh --channel $ARGUMENTS` in Wait.
- Delete consumed prompts from `_pending/ch$ARGUMENTS/` in Cleanup.
- Output: `● Watching _pending/ch$ARGUMENTS/ [<timestamp>]`

If no argument:
- `mkdir -p verification_findings/_pending`
- Announce: "Sonnet listener active. Watching _pending/"

## Main Loop

### Wait

Run `bash scripts/wait_for_work.sh [--channel N]` with `run_in_background: true`. Blocks until a prompt file appears.

### Execute

Read the prompt file.

**Heartbeat:** Before parsing: `date -u +"%Y-%m-%dT%H:%M:%SZ" > "verification_findings/_pending/[chN/].heartbeat"` (hidden file, intentional — `wait_for_work.sh` and `channel_commit.sh` read this to detect listener liveness)

**Parse YAML frontmatter:**
- `type`: commit-verification | squad | implementation
- commit-verification/squad: `agents` [{name, output_path}], `diff_hash`, `timeout_seconds`, `diff_path`
- implementation: `tasks` [{name, signal_file, files}]. Task details in prompt body, not YAML.

**Channel guard (channeled only):** Verify every `output_path`/`signal_file` contains `ch{N}`. If any fails: write error to every listed path, delete prompt, return to Wait. This catches misrouted prompts from wrong Opus sessions.

**Diff injection (commit-verification with diff_path):** If `diff_path` present and file exists:
1. Read file content.
2. Prepend to each agent: "The staged diff is below. Analyze THIS diff only. Do NOT run git commands (`git diff`, `git log`, `git show`, `git status`) — working tree is being manipulated by another terminal. Your ONLY evidence: (1) diff below, (2) files via Read tool.\n\n```diff\n<content>\n```"
3. If `diff_path` set but file missing: write error to all `output_path`s, return to Wait.

If `diff_path` absent: agents read `git diff --cached` directly (backwards compatible).

**Spawn agents:**
- **commit-verification/squad:** Agent count from YAML `agents` array. For squad, create output dir from first agent's path. Spawn all in parallel.
- **implementation:** One agent per task. See below.

All agents: `run_in_background: true`. Write to `<path>.tmp` first, then `mv -f` to final path (atomic). **Wait for all agents to complete before Cleanup.**

## Implementation Tasks

Opus dispatches code/doc work to Sonnet. One agent per task — each has full tool access (Edit, Write, Bash).

| Type | Work | Execution |
|------|------|-----------|
| `commit-verification` | Analyze staged diff | Parallel agents (read-only) |
| `squad` | Analyze work product vs spec | Parallel agents (read-only) |
| `implementation` | Edit code, create files, test, commit | One agent per task (full tools) |

### YAML format

```yaml
---
type: implementation
tasks:
  - name: feature-implementation
    signal_file: verification_findings/sonnet_feature_done[_chN].md
    files:
      - src/feature/feature_module.ts
  - name: docs-update
    signal_file: verification_findings/sonnet_docs_done[_chN].md
    files:
      - docs/feature_mapping.md
---
```

`files` lists files each task modifies — used for dependency detection (overlapping files → sequential).

Body after YAML contains full task descriptions, file paths, patterns, acceptance criteria. Opus writes the complete prompt; listener passes relevant section to each agent.

### Execution

1. For each task, spawn `general-purpose` agent (`run_in_background: true`): "Execute task `<name>`. Write signal file to `<signal_file>` when done. If task fails, write failure reason to signal file."
2. **Independent tasks** (no shared files): parallel. **Dependent tasks** (shared files): sequential — wait for previous signal file.
3. Wait for all signal files before Cleanup.

### Constraints

- No design decisions — flag and defer to Opus
- No files outside task's file list
- No dispatch prompts to `_pending/` (self-dispatch deadlock)
- No skipping tests/verification specified in prompt

### Cleanup

Delete consumed prompt file. Output: `● Watching _pending/[chN/] [<timestamp>]`. Return to Wait.

## Rules

- Service, not peer. Process requests without evaluating.
- Each prompt is self-contained. Zero context between cycles.
- Malformed prompt → write error to every listed path, continue.
- Never spawn Opus agents. Subagents inherit your model.
- After compaction: re-read this file, check `_pending/[chN/]` for unprocessed work, resume loop.
- **Never write to CURRENT_TASK files.** No CT modifications, no listener touch comments, no status updates. Use terminal output and heartbeat file.
- **Commit-active guard.** Before writing outside `verification_findings/`, check if `_pending/[chN/].commit_active` exists. If target file is listed, skip write — `channel_commit.sh` is mid-commit.
- **Ignore stop hooks.** Listener sessions are stateless service loops — there is no work to lose. The stop hook (`stop-task-check.sh`) is designed for Opus sessions that hold conversation state. When the stop hook fires, do not attempt to update CT files or satisfy its requirements. The user terminates listener sessions manually (Ctrl+C) when the channel's work is complete.
