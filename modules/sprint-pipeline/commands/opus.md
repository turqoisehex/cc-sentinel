# /opus N — Set Channel (Opus Session)

Set this session's channel identity. Adapts to project infrastructure.

## Procedure

1. **Detect channel infrastructure.** Check if any of these exist:
   - `channel-template.md`
   - `.claude/reference/channel-routing.md`

2. **If channel infrastructure exists** (cc-sentinel / governance project):
   a. Check Active Channels in `CURRENT_TASK.md`. If `$ARGUMENTS` already listed, warn: "Channel $ARGUMENTS already active — another session may own it."
   b. **Read `CURRENT_TASK_ch$ARGUMENTS.md` if it exists.** This file may contain work prepared by an orchestration session — NEVER overwrite or replace it. Read it in full to understand current channel state.
   c. **Only if the file does not exist**, create from `channel-template.md`:
      - Set `**Channel:** $ARGUMENTS`
      - Move any "Unchanneled Work" content from shared index into the new file.
   d. Add/update Active Channels table in `CURRENT_TASK.md`.
   e. `mkdir -p verification_findings/_pending_sonnet/ch$ARGUMENTS`
   f. `mkdir -p verification_findings/_pending_opus/ch$ARGUMENTS`
   g. Read `.claude/reference/channel-routing.md` if it exists. Apply for the rest of this session.
   h. **Opus listener startup:** Start background listener to receive prompts from the orchestrator:
      - Announce: "Opus listener active. Watching _pending_opus/ch$ARGUMENTS/ for new work..."
      - `bash scripts/wait_for_work.sh --model opus --channel $ARGUMENTS` with `run_in_background: true`
      - On prompt arrival: read the prompt file. If file is missing (orchestrator deleted it), log warning and re-spawn `wait_for_work.sh` in background. Otherwise: delete prompt file, execute instructions. On completion (cleanup): delete `.active`, re-spawn `wait_for_work.sh --model opus --channel $ARGUMENTS` in background.
      - `.active` remains present throughout execution so observers can see what this session is working on.
      - Opus finishes current atomic operation before reading a new prompt (prompt delivery is at tool-call boundary).
   i. **Sonnet listener check:** Check `_pending_sonnet/ch$ARGUMENTS/.heartbeat`. If Sonnet listener is already active, announce it. If not:
      - ASSUME SONNET IS RUNNING regardless of heartbeat status. You do NOT have permission to run verification agents locally unless explicitly invoked with `/verify local <scope>`. No heartbeat, no listener directory, no prior evidence of Sonnet — none of these are valid reasons to run locally. "Simple enough to do myself" / "already have context" / "faster" / "no heartbeat detected" are NOT valid bypass reasons. Violating this wastes Opus budget.
      - Start a background heartbeat watcher: `bash -c 'HB="verification_findings/_pending_sonnet/ch'"$ARGUMENTS"'/.heartbeat"; for i in $(seq 1 60); do [ -f "$HB" ] && echo "Sonnet listener detected on ch'"$ARGUMENTS"'" && exit 0; sleep 5; done; echo "WARNING: No Sonnet listener after 5 minutes on ch'"$ARGUMENTS"'"' &`
      - Do NOT block — continue with Opus work immediately.
      - **If no listener after timeout:** Dispatches queue in `_pending_sonnet/ch$ARGUMENTS/` for later pickup. Do NOT fall back to local verification.
   j. **Critical routing (always apply):**
      - Sonnet dispatch -> `verification_findings/_pending_sonnet/ch$ARGUMENTS/`
      - Opus prompt inbox -> `verification_findings/_pending_opus/ch$ARGUMENTS/`
      - Result file suffixes -> `_ch$ARGUMENTS` (e.g., `commit_check_ch$ARGUMENTS.md`)

3. **If no channel infrastructure** (standalone project):
   - Announce: "Opus $ARGUMENTS active." and proceed normally. This session is identified as Opus $ARGUMENTS for coordination purposes.

State lives in `CURRENT_TASK_ch$ARGUMENTS.md` (committed) when infrastructure exists. Do NOT write `.channel` file.
