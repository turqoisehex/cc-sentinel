# cc-sentinel Architecture Migration: Native Sonnet Subagent Dispatch

## Context

Model routing has been verified working in CC v2.1.86 on Max 20x. An Opus parent session can reliably spawn Sonnet subagents via `Agent(model: "sonnet")`. JSONL transcript analysis confirmed the subagent actually runs on `claude-sonnet-4-6`, not silently falling back to Opus.

This eliminates the primary reason the duo terminal-pair architecture existed: the inability of Opus to dispatch Sonnet work directly. The file-based IPC, heartbeat polling, wait_for_work.sh listeners, and channel_commit.sh Sonnet-dispatch logic were workarounds for broken model routing. That routing now works natively.

## Objective

Change the default /2 and /3 workflow so that:

1. **Default mode**: Opus sessions spawn Sonnet subagents directly using `Agent(model: "sonnet")` for all [SONNET] classified tasks, as well as verification squads.
2. **Duo mode**: Reserved for special cases where there is a high volume of both Opus-judgment AND Sonnet-mechanical work, and the Sonnet sessions benefit from persistence across Opus compaction cycles.
3. **All agents continue writing results to disk** — the file-based audit trail is preserved. Agents write their full findings to the existing file paths, then pass a concise summary back to the parent. The parent's context stays light; the detailed files remain available for investigation.
4. **Opus sessions can still be spawned in parallel** via `/spawn opus N`. Each Opus session independently spawns its own Sonnet subagents when needed.
5. **No quality changes** — all sessions remain at high effort. Sonnet handles mechanical work, Opus handles judgment. The verification squad (up to 5 agents) continues unchanged in scope and rigor.

## Budget Rationale

Every Opus-to-Sonnet handoff via file-based IPC costs 2-4 Opus turns:
- 1 Opus turn to write the dispatch prompt file
- 1 Opus turn to spawn wait_for_results.sh
- 1-2 Opus turns to read result files when they arrive
- 1 Opus turn to process/act on results

With native subagent dispatch, the same handoff costs 1-2 Opus turns:
- 1 Opus turn to spawn the Agent(model: "sonnet") call
- 1 Opus turn when the subagent returns its summary

At 5-10 handoffs per sprint per Opus session x 5 Opus sessions = 25-50 handoff cycles per sprint. Savings: ~75-150 Opus turns per sprint. On a Max 20x plan where Opus burns budget 5-10x faster than Sonnet, this is significant.

Additionally, eliminating the Sonnet listener terminal sessions frees the Sonnet budget that was consumed by those sessions' system prompt loading, session-orient hooks, and idle turn overhead.

---

## Changes Required

### 1. New Subagent Definition Files

Create the following files in the sprint-pipeline module's `agents/` directory. These define the Sonnet subagents that Opus sessions will spawn directly.

Note: These files use plain markdown format (no YAML frontmatter) — matching the existing agent convention in `.claude/agents/`. The `model: sonnet` routing is specified by the caller via `Agent(model: "sonnet")`, not in the agent file itself.

#### `sonnet-implementer.md`

```markdown
## Purpose

Executes well-specified implementation tasks. Use for [SONNET] classified work with clear file paths, acceptance criteria, and no judgment calls required.

## Rules

1. Write ALL output files to the paths specified in the task prompt.
2. Write each output file to `<path>.tmp` first, then move to final path (atomic write).
3. After completing all work, write a summary file to the path specified in the task prompt (usually `verification_findings/` or alongside the changed files).
4. Return to the parent ONLY a concise summary: what was done, which files were created/modified, and pass/fail status. Do NOT return file contents — the parent will read files if needed.
5. If you encounter ambiguity or a decision that requires judgment, STOP. Write what you found to the summary file and return to the parent with the question. Do NOT make judgment calls.
6. Follow all project conventions from CLAUDE.md.
```

#### `sonnet-verifier.md`

```markdown
## Purpose

Runs the verification squad against completed work. Spawns up to 5 parallel verification agents, collects results to disk, returns consolidated summary to parent.

## Process

1. Read the task prompt to identify: scope of work, files changed, spec to verify against.
2. Determine which verification agents to launch based on file categories:
   - Docs only (.md, .txt, .rst) -> cold_reader only
   - Tests only -> mechanical, completeness
   - Config only (.json, .yaml, .toml) -> adversarial, dependency
   - Source code / mixed -> all 5: mechanical, adversarial, completeness, dependency, cold_reader
3. Write a manifest.json to the squad output directory recording which agents were launched and why.
4. Spawn each verification agent in parallel (run_in_background: true).
5. Each agent writes its findings to its designated file path (e.g., `verification_findings/squad_chN_sonnet/mechanical.md`).
6. After all agents complete, read all result files.
7. Return to parent ONLY: overall verdict + count of findings by severity + path to summary file. Do NOT return the full findings text.

## Verification Agent Prompts

Use the same agent prompts as defined in the verification-squad.md reference. Each agent:
- Writes to `<output_path>.tmp` first, then atomic move
- Includes its verdict as the first line: `VERDICT: PASS|WARN|FAIL`
- Includes the verification hash if one was provided
```

#### `commit-verifier.md`

```markdown
## Purpose

Runs the 2-agent commit verification (adversarial + cold-reader) against a staged diff. Use before every commit.

## Process

1. Read the task prompt to get: channel number, diff file path, commit hash.
2. Read the staged diff file.
3. Spawn 2 agents in parallel (run_in_background: true):
   a. commit-adversarial: Reviews diff for logic errors, spec violations, regressions.
   b. commit-cold-reader: Reads diff with zero project context, flags anything broken or nonsensical.
4. Each agent writes to its designated output path (e.g., `verification_findings/commit_check_chN.md`, `verification_findings/commit_cold_read_chN.md`).
5. Each agent includes `HASH: <hash>` and `VERDICT: PASS|WARN|FAIL` in output.
6. After both complete, read both files.
7. Return to parent: both verdicts + hash confirmation + path to files. If either is FAIL, state that clearly.
```

### 2. Changes to /2 Design Phase (Task Classification)

Remove the `[AGENT]` tag entirely. Update the classification table to 3 tags:

| Tag | When to use |
|-----|------------|
| `[SONNET]` | Self-contained with clear file paths + acceptance criteria, OR mechanical/pattern-following work. Opus spawns `sonnet-implementer` subagent via `Agent(model: "sonnet")`. |
| `[OPUS]` | Requires parent context, judgment, or design decisions. |
| `[PARENT]` | Requires conversation context or orchestration. |

Classification rules:
1. Requires architectural judgment, design tradeoffs, or interpreting ambiguous requirements? -> `[OPUS]`
2. Requires the orchestrator's conversation context? -> `[PARENT]`
3. Everything else -> `[SONNET]`. If in doubt between OPUS and SONNET, classify as OPUS — quality over budget.

Also update Steps 5 and 6 to use native subagent dispatch instead of writing to `_pending_sonnet/`.

### 3. Changes to /3 Build Phase (Execution Flow)

New execution flow:

1. Read task list from /2 output
2. For `[SONNET]` tasks: spawn `sonnet-implementer` subagent directly via `Agent(model: "sonnet")`.
   - Pass the task prompt including: spec reference, file paths, acceptance criteria, output paths for result files.
   - The subagent writes results to disk, returns a concise summary.
   - The Opus parent reads the summary, decides pass/fail, proceeds to next task or requests fixes.
   - Parallel SONNET tasks: spawn multiple subagents with `run_in_background: true`.
3. For `[OPUS]` tasks: execute directly in current session, or dispatch to another Opus session via file-based IPC if running `/spawn opus N`.
4. For `[PARENT]` tasks: execute in current session. Unchanged.
5. After each task group: spawn `commit-verifier` subagent via `Agent(model: "sonnet")`.
   - The subagent runs the 2-agent commit check (adversarial + cold-reader), writes results to disk, returns verdicts.
   - If PASS/WARN: proceed with commit via `channel_commit.sh --local-verify`.
   - If FAIL: present findings to Opus for judgment.
6. At phase end: spawn `sonnet-verifier` subagent via `Agent(model: "sonnet")`.
   - The subagent coordinates the full squad (up to 5 agents), writes all findings to disk, returns consolidated summary.

### 4. Changes to channel_commit.sh

> **Implementation note:** The originally proposed `--native-verify` flag was not needed. The existing `--local-verify` flag already provides identical behavior — it skips `dispatch_and_wait()` when verification results are already on disk. No changes to `channel_commit.sh` were required.

The existing `--local-verify` flag:
- When set: skip the heartbeat check, skip writing to `_pending_sonnet/`, skip wait_for_results.sh. The caller (Opus parent) has already run verification via its own Sonnet subagent before calling channel_commit.sh.
- When not set: existing behavior unchanged (backward compatible for duo mode).

### 5. Changes to /opus N (Channel Initialization)

Default mode (no `CC_DUO_MODE=1` env var):
- Still create channel infrastructure directories (`_pending_sonnet/chN/`, `_pending_opus/chN/`)
- Do NOT start `wait_for_work.sh` for the Sonnet listener
- Do NOT start the heartbeat watcher
- Do start the Opus listener if `_pending_opus/chN/` dispatch is used

Duo mode (when `CC_DUO_MODE=1` is set):
- Create directories as above
- Start Opus listener: `bash scripts/wait_for_work.sh --model opus --channel N`
- Start heartbeat watcher for Sonnet
- Full existing behavior preserved

### 6. Changes to /verify

Default mode: Spawn `sonnet-verifier` subagent via `Agent(model: "sonnet")`. Pass scope, spec, and agent list.

Duo mode: Existing file-based dispatch to `_pending_sonnet/`.

### 7. Changes to /finalize and /audit

Steps that say "MANDATORY SONNET DELEGATION. Write prompt to `_pending_sonnet/...`" must be conditionalized:
- Default mode: spawn Sonnet subagent directly
- Duo mode: file-based dispatch as before

### 8. Changes to /sonnet

Add a note that `/sonnet` is duo-mode-only. In default mode (no persistent Sonnet listener), this skill is not needed. The Opus session spawns Sonnet subagents natively.

### 9. Changes to /spawn

Add `CC_DUO_MODE=1` to the env_prefix for duo mode sessions. IMPORTANT: prepend to the existing env_prefix, do not replace it — `SENTINEL_LISTENER=true` must be preserved for Sonnet sessions.

```python
# In the per-session launch loop, AFTER existing env_prefix assignment:
if mode == "duo":
    env_prefix = "CC_DUO_MODE=1 " + env_prefix
```

Add informational note when duo mode is selected.

Update `/spawn` SKILL.md modes table to indicate that `opus N` is the recommended default (native subagent dispatch) and `duo N` is for special cases.

### 10. Changes to CLAUDE.md Rules

The dispatch rules live in skill SKILL.md files and in `modules/core/claude-md-rules.md` (the rules injected into project CLAUDE.md files during installation). Update these to be conditional:

**Default mode:** Spawn Sonnet subagents directly via `Agent(model: "sonnet")`. All subagents write results to disk at standard file paths. Return only concise summaries to parent.

**Duo mode** (when `CC_DUO_MODE=1` or Sonnet listeners active): Use file-based IPC via `_pending_sonnet/` as before.

When spawning Sonnet subagents, always set `model: "sonnet"` explicitly. Omitted model defaults to inherit (runs on Opus).

---

## What This Does NOT Change

- Quality floor: everything stays at high effort, Opus for judgment, Sonnet for mechanical work
- Verification rigor: same 5-agent squad, same 2-agent commit checks, same stop hook gates
- File-based audit trail: all agents still write to disk at the same paths
- Context management: parent context stays light (summaries only), full details on disk
- Governance hooks: anti-deferral, file-protection, compaction survival all unchanged
- Commit gating: tests must pass, formatting must be clean, verification must pass
- These files: anti-deferral.sh, session-orient.sh, pre-compact-state-save.sh, post-compact-reorient.sh, agent-file-reminder.sh, file-protection.sh, stop-task-check.sh, context-awareness, verification agent prompts (content), safe-commit.sh, auto-format.sh
