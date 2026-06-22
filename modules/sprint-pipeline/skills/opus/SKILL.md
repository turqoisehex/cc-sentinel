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
      - **Both modes**: Start Opus listener: `bash ~/.claude/scripts/wait_for_work.sh --model opus --channel N` (run_in_background: true). The listener is needed in ALL multi-session configurations — `/spawn opus N` dispatches work to other Opus sessions via `_pending_opus/`. Only Sonnet listener startup is skipped in default mode.
      - **When the background task completes (exit 0): work has arrived.** The script's stdout (in the task output file) contains the path to the prompt file. Read the task output to get the path, then follow the **Prompt Execution Protocol** below.

   i.1. **Prompt Execution Protocol (MANDATORY):**

      When a prompt file is found (whether the listener fires immediately during setup or later):

      1. **Read** the prompt file in full.
      2. **Delete** the prompt file (it has been received; deletion prevents re-execution).
      3. **Execute the work described in the prompt file immediately — WITHOUT asking the user for confirmation.** Dispatched work is pre-approved by the session that placed it. The user does not need to be consulted. "Shall I proceed?" / "Ready to begin?" / "Want me to start?" are all WRONG. Just do the work.
      4. When execution completes (or context runs low), re-spawn the listener.

      **If the listener fires immediately during setup** (file was pre-placed before this session started): this is the session's PRIMARY work. Complete any remaining setup steps quickly, then execute the prompt. Do not announce setup completion and wait — the prompt IS your instruction.

      **Prompt file format** (what to expect):
      ```
      # EXECUTE: [task title]
      ## WORK_PRODUCT: [file(s) being modified]
      ## SCOPE: [what's covered]
      ---
      ## INSTRUCTION
      [concrete steps to execute — treat as direct orders]
      ---
      ## KEY CONTEXT
      [background the executor needs]
      ```

      The `# EXECUTE:` header signals this is a task to perform, not context to consider. The INSTRUCTION section contains the steps. Follow them literally.

   j. **Sonnet availability:**
      - **Default mode**: Sonnet subagents spawned natively via `Agent(model: "sonnet")`. No listener needed. No heartbeat watcher.
      - **Duo mode** (`CC_DUO_MODE=1`): ASSUME SONNET IS RUNNING. Start heartbeat watcher: `bash ~/.claude/scripts/heartbeat_watcher.sh --channel N` (run_in_background: true). Do NOT block — continue with Opus work immediately.

   k. **Critical routing (always apply):**
      - Sonnet dispatch -> `verification_findings/_pending_sonnet/ch$ARGUMENTS/`
      - Opus prompt inbox -> `verification_findings/_pending_opus/ch$ARGUMENTS/`
      - Result file suffixes -> `_ch$ARGUMENTS` (e.g., `commit_check_ch$ARGUMENTS.md`)

3. **If no channel infrastructure** (standalone project):
   - Announce: "Opus $ARGUMENTS active." and proceed normally. This session is identified as Opus $ARGUMENTS for coordination purposes.

State lives in `CURRENT_TASK_ch$ARGUMENTS.md` (committed) when infrastructure exists. Do NOT write `.channel` file.
