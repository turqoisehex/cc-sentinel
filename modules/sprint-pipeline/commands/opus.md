# /opus N — Set Channel

Set this session's channel. Create per-channel CT file if needed.

1. Check Active Channels in `CURRENT_TASK.md`. If $ARGUMENTS already listed, warn: "Channel $ARGUMENTS already active — another session may own it."
2. If `CURRENT_TASK_ch$ARGUMENTS.md` missing, create from `CURRENT_TASK_CHANNEL_TEMPLATE.md`:
   - Set `**Channel:** $ARGUMENTS`
   - Move any "Unchanneled Work" content from shared index into the new file.
3. Add/update Active Channels table in `CURRENT_TASK.md`.
4. `mkdir -p verification_findings/_pending/ch$ARGUMENTS`
5. Announce: "Channel $ARGUMENTS active. All commands MUST route through ch$ARGUMENTS. Channel file: `CURRENT_TASK_ch$ARGUMENTS.md`."
6. Read `.claude/reference/channel-routing.md`. Apply for the rest of this session.
7. **Listener check:** If no Sonnet listener is active on ch$ARGUMENTS (stale/missing heartbeat in `_pending/ch$ARGUMENTS/.heartbeat`), tell user to start `/sonnet $ARGUMENTS` in second terminal, OR use `--local-verify`.

**Critical routing (always apply):**
- Dispatch files → `verification_findings/_pending/ch$ARGUMENTS/`
- Result file suffixes → `_ch$ARGUMENTS` (e.g., `commit_check_ch$ARGUMENTS.md`)
- Script prefix → `SENTINEL_CHANNEL=$ARGUMENTS`

State lives in `CURRENT_TASK_ch$ARGUMENTS.md` (committed). Shared `CURRENT_TASK.md` (gitignored) tracks active channels. Do NOT write `.channel` file.
