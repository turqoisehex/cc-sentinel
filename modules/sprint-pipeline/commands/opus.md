# /opus N — Set Channel (Opus Session)

Set this session's channel identity. Adapts to project infrastructure.

## Procedure

1. **Detect channel infrastructure.** Check if any of these exist:
   - `channel-template.md`
   - `.claude/reference/channel-routing.md`

2. **If channel infrastructure exists** (cc-sentinel / governance project):
   a. Check Active Channels in `CURRENT_TASK.md`. If `$ARGUMENTS` already listed, warn: "Channel $ARGUMENTS already active — another session may own it."
   b. If `CURRENT_TASK_ch$ARGUMENTS.md` missing, create from whichever template file exists (`CURRENT_TASK_CHANNEL_TEMPLATE.md` or `channel-template.md`):
      - Set `**Channel:** $ARGUMENTS`
      - Move any "Unchanneled Work" content from shared index into the new file.
   c. Add/update Active Channels table in `CURRENT_TASK.md`.
   d. `mkdir -p verification_findings/_pending/ch$ARGUMENTS`
   e. Read `.claude/reference/channel-routing.md` if it exists. Apply for the rest of this session.
   f. **Listener check:** If no Sonnet listener is active on ch$ARGUMENTS (stale/missing heartbeat in `_pending/ch$ARGUMENTS/.heartbeat`), tell user to start `/sonnet $ARGUMENTS` in second terminal, OR use `--local-verify`.
   g. **Critical routing (always apply):**
      - Dispatch files -> `verification_findings/_pending/ch$ARGUMENTS/`
      - Result file suffixes -> `_ch$ARGUMENTS` (e.g., `commit_check_ch$ARGUMENTS.md`)

3. **If no channel infrastructure** (standalone project):
   - Announce: "Opus $ARGUMENTS active." and proceed normally. This session is identified as Opus $ARGUMENTS for coordination purposes.

State lives in `CURRENT_TASK_ch$ARGUMENTS.md` (committed) when infrastructure exists. Do NOT write `.channel` file.
