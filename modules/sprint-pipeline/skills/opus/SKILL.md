---
name: opus
description: "Set channel identity for an Opus session. Detects channel infrastructure, creates CT file, starts Opus listener (receives prompts from orchestrator), starts heartbeat watcher for Sonnet listener. Use as /opus N where N is the channel number."
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
   e. `mkdir -p verification_findings/_pending_opus/ch$ARGUMENTS`
   f. Read `.claude/reference/channel-routing.md` if it exists. Apply for the rest of this session.
   g. **Opus listener startup:** Start background listener to receive prompts from the orchestrator:
      - Announce: "Opus listener active. Watching _pending_opus/ch$ARGUMENTS/ for new work..."
      - `bash scripts/wait_for_work.sh --model opus --channel $ARGUMENTS` with `run_in_background: true`
      - On prompt arrival: read the prompt file. If file is missing (orchestrator deleted it), log warning and re-spawn `wait_for_work.sh` in background. Otherwise: delete prompt file, execute instructions. On completion (cleanup): delete `.active`, re-spawn `wait_for_work.sh --model opus --channel $ARGUMENTS` in background.
      - `.active` remains present throughout execution so observers can see what this session is working on.
      - Opus finishes current atomic operation before reading a new prompt (prompt delivery is at tool-call boundary).
   h. **Sonnet listener check:** Check `_pending_sonnet/ch$ARGUMENTS/.heartbeat`. If Sonnet listener is already active, announce it. If not:
      - ASSUME SONNET IS RUNNING regardless of heartbeat status. You do NOT have permission to run verification agents locally unless explicitly invoked with `/squad local <scope>`. No heartbeat, no listener directory, no prior evidence of Sonnet — none of these are valid reasons to run locally. "Simple enough to do myself" / "already have context" / "faster" / "no heartbeat detected" are NOT valid bypass reasons. Violating this wastes Opus budget.
      - Start a background heartbeat watcher: `bash -c 'HB="verification_findings/_pending_sonnet/ch'"$ARGUMENTS"'/.heartbeat"; for i in $(seq 1 60); do [ -f "$HB" ] && echo "Sonnet listener detected on ch'"$ARGUMENTS"'" && exit 0; sleep 5; done; echo "WARNING: No Sonnet listener after 5 minutes on ch'"$ARGUMENTS"'"' &`
      - Do NOT block — continue with Opus work immediately.
      - **If no listener after timeout:** Dispatches queue in `_pending_sonnet/ch$ARGUMENTS/` for later pickup. Do NOT fall back to local verification.
   i. **Critical routing (always apply):**
      - Sonnet dispatch -> `verification_findings/_pending_sonnet/ch$ARGUMENTS/`
      - Opus prompt inbox -> `verification_findings/_pending_opus/ch$ARGUMENTS/`
      - Result file suffixes -> `_ch$ARGUMENTS` (e.g., `commit_check_ch$ARGUMENTS.md`)

3. **If no channel infrastructure** (standalone project):
   - Announce: "Opus $ARGUMENTS active." and proceed normally. This session is identified as Opus $ARGUMENTS for coordination purposes.

State lives in `CURRENT_TASK_ch$ARGUMENTS.md` (committed) when infrastructure exists. Do NOT write `.channel` file.
