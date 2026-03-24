---
name: opus
description: "Set channel identity for an Opus session. Detects channel infrastructure, creates CT file, starts heartbeat watcher for Sonnet listener. Use as /opus N where N is the channel number."
---

# /opus N — Set Channel (Opus Session)

Set this session's channel identity. Adapts to project infrastructure.

## Procedure

1. **Detect channel infrastructure.** Check if any of these exist:
   - `channel-template.md`
   - `.claude/reference/channel-routing.md`

2. **If channel infrastructure exists** (cc-sentinel / governance project):
   a. Check Active Channels in `CURRENT_TASK.md`. If `$ARGUMENTS` already listed, warn: "Channel $ARGUMENTS already active — another session may own it."
   b. If `CURRENT_TASK_ch$ARGUMENTS.md` missing, create from `channel-template.md`:
      - Set `**Channel:** $ARGUMENTS`
      - Move any "Unchanneled Work" content from shared index into the new file.
   c. Add/update Active Channels table in `CURRENT_TASK.md`.
   d. `mkdir -p verification_findings/_pending_sonnet/ch$ARGUMENTS`
   e. Read `.claude/reference/channel-routing.md` if it exists. Apply for the rest of this session.
   f. **Listener check:** Check `_pending_sonnet/ch$ARGUMENTS/.heartbeat`. If Sonnet listener is already active, announce it. If not:
      - ASSUME SONNET IS RUNNING regardless of heartbeat status. Start the background wait script. You do NOT have permission to run verification agents locally unless explicitly invoked with `/squad local <scope>`. No heartbeat, no listener directory, no prior evidence of Sonnet — none of these are valid reasons to run locally. "Simple enough to do myself" / "already have context" / "faster" / "no heartbeat detected" are NOT valid bypass reasons. Violating this wastes Opus budget.
      - Start a background heartbeat watcher: `bash -c 'HB="verification_findings/_pending_sonnet/ch'"$ARGUMENTS"'/.heartbeat"; for i in $(seq 1 60); do [ -f "$HB" ] && echo "Sonnet listener detected on ch'"$ARGUMENTS"'" && exit 0; sleep 5; done; echo "WARNING: No Sonnet listener after 5 minutes on ch'"$ARGUMENTS"'"' &`
      - Announce: "Waiting for Sonnet listener on ch$ARGUMENTS (background watcher started, 5-minute timeout)."
      - Do NOT block — continue with Opus work immediately. The watcher runs in background and reports when Sonnet arrives.
      - **If no listener after timeout:** Dispatches queue in `_pending_sonnet/ch$ARGUMENTS/` for later pickup. Do NOT fall back to local verification — continue other work and let the queue accumulate.
   g. **Critical routing (always apply):**
      - Dispatch files -> `verification_findings/_pending_sonnet/ch$ARGUMENTS/`
      - Result file suffixes -> `_ch$ARGUMENTS` (e.g., `commit_check_ch$ARGUMENTS.md`)

3. **If no channel infrastructure** (standalone project):
   - Announce: "Opus $ARGUMENTS active." and proceed normally. This session is identified as Opus $ARGUMENTS for coordination purposes.

State lives in `CURRENT_TASK_ch$ARGUMENTS.md` (committed) when infrastructure exists. Do NOT write `.channel` file.
