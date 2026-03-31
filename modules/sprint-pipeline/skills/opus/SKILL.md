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
   b. **Read `CURRENT_TASK_ch$ARGUMENTS.md` if it exists.** This file may contain work prepared by an orchestration session — NEVER overwrite or replace it. Read it in full to understand current channel state.
   c. **Only if the file does not exist**, create from `channel-template.md`:
      - Set `**Channel:** $ARGUMENTS`
      - Move any "Unchanneled Work" content from shared index into the new file.
   d. Add/update Active Channels table in `CURRENT_TASK.md`.
   e. `mkdir -p verification_findings/_pending_sonnet/ch$ARGUMENTS`
   f. `mkdir -p verification_findings/_pending_opus/ch$ARGUMENTS`
   g. Read `.claude/reference/channel-routing.md` if it exists. Apply for the rest of this session.
   h. **Mode detection:** Run `echo $CC_DUO_MODE` to check environment. If `1`, follow duo mode. If empty/unset, follow default (native dispatch) mode.

   i. **Listener startup:**
      - **Duo mode** (`CC_DUO_MODE=1`): Start Opus listener: `bash scripts/wait_for_work.sh --model opus --channel N` (run_in_background: true). On prompt arrival: read, delete, execute, re-spawn.
      - **Default mode** (no `CC_DUO_MODE`): Start Opus listener (same as duo). The Opus listener is needed in ALL multi-session configurations — `/spawn opus N` dispatches work to other Opus sessions via `_pending_opus/`. Only Sonnet listener startup is skipped in default mode (Sonnet work uses native `Agent(model: "sonnet")` dispatch instead).

   j. **Sonnet availability:**
      - **Default mode**: Sonnet subagents spawned natively via `Agent(model: "sonnet")`. No listener needed. No heartbeat watcher.
      - **Duo mode** (`CC_DUO_MODE=1`): ASSUME SONNET IS RUNNING. Start heartbeat watcher: `bash scripts/heartbeat_watcher.sh --channel N` (run_in_background: true). Do NOT block — continue with Opus work immediately.

   k. **Critical routing (always apply):**
      - Sonnet dispatch →`verification_findings/_pending_sonnet/ch$ARGUMENTS/`
      - Opus prompt inbox →`verification_findings/_pending_opus/ch$ARGUMENTS/`
      - Result file suffixes →`_ch$ARGUMENTS` (e.g., `commit_check_ch$ARGUMENTS.md`)

3. **If no channel infrastructure** (standalone project):
   - Announce: "Opus $ARGUMENTS active." and proceed normally. This session is identified as Opus $ARGUMENTS for coordination purposes.

State lives in `CURRENT_TASK_ch$ARGUMENTS.md` (committed) when infrastructure exists. Do NOT write `.channel` file.
