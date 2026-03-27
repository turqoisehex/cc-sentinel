# Channel Routing

Commands that dispatch prompt files or reference result files MUST apply channel routing.

## Check

Your channel is determined by **session context**, not a file:

1. **If `/opus N` was called this session:** You are on channel N. Set `SENTINEL_CHANNEL=N` on all script calls.
2. **After compaction:** Read `CURRENT_TASK_chN.md` (your channel file). The shared `CURRENT_TASK.md` has the Active Channels table.
3. **If neither:** Unchanneled mode. No path changes needed.

## Scope Check (MANDATORY before applying routing)

- **Channel-scoped work:** apply channel routing.
- **Cross-channel work** (e.g., full verification, multi-channel audit): use **unchanneled** paths.

**When in doubt: unchanneled is safer than misrouted.**

## Routing Rules (when channeled)

1. **Dispatch directory:** `verification_findings/_pending_sonnet/chN/`
2. **Result filenames:** Append `_chN` before extension (e.g., `commit_check_chN.md`)
3. **Squad directories:** `squad_chN_sonnet/` / `squad_chN_opus/`
4. **YAML output_path:** Write channeled paths into `agents[].output_path` in prompt frontmatter.
5. **Script invocations:**
   ```bash
   bash scripts/channel_commit.sh --channel N --files "f1 f2" -m "message"
   ```
6. **wait_for_results.sh:** Pass channeled file paths as arguments.

## Bracket Notation

Commands use bracket notation to show both forms in one line:

- `[chN/]` = dispatch subdirectory
- `[_chN]` = result file suffix
- `[chN_]` = squad dir prefix

Resolve before running. Unchanneled: omit bracketed portion.

## CURRENT_TASK.md — Split Structure

- **Shared index (`CURRENT_TASK.md`):** Active Channels table, cross-channel context.
- **Channel files (`CURRENT_TASK_chN.md`):** Each channel's plan, status, steps.
- **Glob pattern:** `CURRENT_TASK_ch*.md`

## channel_commit.sh

Public commit API for all sessions.

```bash
bash scripts/channel_commit.sh --channel N --files "f1 f2" -m "message" [--skip-squad] [--local-verify]
```

Handles: staging lock, diff capture, Sonnet dispatch, validation, retry, tests, safe-commit.

## Dispatch Type Selection

| Work | Type | Executed by |
|------|------|-------------|
| Check staged diff before commit | `commit-verification` | Parallel agents (read-only) |
| Verify work product (up to 6-agent squad) | `squad` | Parallel agents (read-only) |
| Edit code, create files, run tests | `implementation` | One agent per task (full access) |

## Git Conflict Resolution

When channel work conflicts with main or another channel:

1. `git stash` your uncommitted changes.
2. `git pull --rebase origin main` (or the target branch).
3. `git stash pop` — if conflicts, resolve manually.
4. For each conflicting file: read both versions, merge intentionally. Never blindly accept "ours" or "theirs."
5. Run tests after resolution.
6. Commit the merge via `channel_commit.sh`.

## Known Limitations

- **Self-dispatch deadlock:** Sonnet cannot consume prompts it writes.
- **CT race condition:** `.commit_active` prevents concurrent file modifications.
- **Heartbeat:** `wait_for_work.sh` spawns a background heartbeat process (writes `.heartbeat` every 3s, PID in `.heartbeat_pid`). Background process survives after work is found and self-terminates when the listener session exits (PPID polling). Stale >30s = warning.
- **Cross-channel squad leak:** Squad directories from one channel could theoretically satisfy another channel's completion gate if both are active simultaneously. The stop hook scopes checks to active CT files to mitigate this.
