# Opus Listener — Design Spec

> **Status:** Approved (brainstorm + 3 grill rounds). Ready for implementation plan.

## Goal

Enable Opus sessions to receive prompt files from an orchestrator, eliminating manual session kickoff and enabling mid-flight corrections. Parallel to the existing Sonnet listener system but for Opus-tier work.

## Problem

Current workflow requires manual interaction with each Opus session:
1. Orchestrator writes CT files during /2
2. User runs `/spawn duo N` to open terminal pairs
3. Each Opus session auto-runs `/opus N` but then **waits for manual instructions**
4. User must visit each Opus terminal and tell it what to do
5. Mid-session, if Opus hits an error, user must manually intervene in that terminal

Additionally, Opus frequently bypasses Sonnet dispatch ("I'll just do it myself") because the only liveness signal is a heartbeat file — no proof that Sonnet is actively working on the dispatched prompt.

## Architecture

Three-tier orchestration via file signals:

```
Orchestrator (human in CC terminal)
  ├── writes prompts to _pending_opus/chN/   → Opus picks up, executes
  └── Opus sessions
       └── dispatch to _pending_sonnet/chN/  → Sonnet picks up, executes
```

### Key decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | Rename `_pending/` → `_pending_sonnet/` | Disambiguate from new Opus inbox |
| D2 | New `_pending_opus/chN/` directory | Parallel inbox for Opus sessions |
| D3 | Single `wait_for_work.sh` with `--model` flag | One script, two directories. No code duplication |
| D4 | Oldest-first by mtime | Ensures multi-step prompts execute in sequence |
| D5 | `.active` signal file | Proves listener is processing, not just alive |
| D6 | 15-minute stale threshold (was 300s switch-to-local, 30s warn) | `.active` provides proof-of-work; raise both thresholds — warn at 5 min, switch-to-local at 15 min |
| D7 | `/opus N` starts background listener | Opus is always receivable from the moment it starts |
| D8 | Prompt delivery at tool-call boundary (CC runtime assumption) | CC delivers `run_in_background` completions as system messages; Opus finishes current atomic operation before reading. If CC changes this behavior, prompts may arrive mid-operation — the design tolerates this since prompts are additive instructions, not interrupts |
| D9 | Opus listeners still get stop-hook enforcement | Unlike Sonnet (stateless service loop), Opus holds state and should save it. No implementation change needed — `stop-task-check.sh` fires on every tool call for all sessions. The only change is the pattern exclusion for "Watching..." listener output (Component 6); actual Opus work output is enforced as normal |

## Directory Structure

**Before:**
```
verification_findings/
  _pending/
    chN/
      .heartbeat
      .heartbeat_pid
      prompt_file.md
```

**After:**
```
verification_findings/
  _pending_sonnet/
    chN/
      .heartbeat
      .heartbeat_pid
      .active           ← NEW: written when processing, deleted on cleanup
      prompt_file.md
  _pending_opus/
    chN/
      .heartbeat
      .heartbeat_pid
      .active
      launch_prompt.md
```

Both directories are gitignored (sentinel gitignores all of `verification_findings/`; project `.gitignore` entries need updating from `_pending/` to `_pending_sonnet/` + `_pending_opus/`).

## Component Changes

### 1. `wait_for_work.sh`

**Location:** `modules/commit-enforcement/scripts/wait_for_work.sh`

Current signature: `bash scripts/wait_for_work.sh [--channel N]`
New signature: `bash scripts/wait_for_work.sh --model opus|sonnet [--channel N]`

Changes:
- **`--model` flag** (optional, defaults to `sonnet`): selects `_pending_opus/` or `_pending_sonnet/`. All callers should pass it explicitly; the default exists only for backward compatibility during migration. Unknown values → error and exit (no silent fallback).
- **Oldest-first ordering:** Replace arbitrary glob match with `ls -tr "$PENDING_DIR"/*.md 2>/dev/null | head -1`. Returns oldest mtime first.
- **`.active` signal:** Before returning the filename, write `.active` containing `<ISO-8601-timestamp> processing <filename>`. Written to `$PENDING_DIR/.active`.
- Heartbeat mechanism unchanged (background loop, PPID self-termination).

### 2. `/opus N` command + skill

**Location:** `modules/sprint-pipeline/commands/opus.md`, `modules/sprint-pipeline/skills/opus/SKILL.md`

New additions to the startup procedure:
1. Create Opus pending dir: `mkdir -p verification_findings/_pending_opus/chN`
2. Start background listener: `bash scripts/wait_for_work.sh --model opus --channel N` with `run_in_background: true`
3. On prompt arrival: read prompt file. If file is missing (orchestrator deleted it), log warning to stdout and re-spawn `wait_for_work.sh` in background (return to listening). Otherwise: delete prompt file, execute instructions. On completion (cleanup): delete `.active`, re-spawn `wait_for_work.sh` in background. `.active` remains present throughout execution so observers can see what the session is working on.
4. Opus finishes current atomic operation before reading a new prompt (prompt delivery is at tool-call boundary)

Updated dispatch path: Sonnet dispatches go to `_pending_sonnet/chN/` (renamed).

Updated Sonnet heartbeat check path: `_pending_sonnet/chN/.heartbeat`.

### 3. `/sonnet` command + skill

**Location:** `modules/sprint-pipeline/commands/sonnet.md`, `modules/sprint-pipeline/skills/sonnet/SKILL.md`

Changes:
- Directory: `_pending_sonnet/chN/` (renamed from `_pending/chN/`)
- `wait_for_work.sh` call adds `--model sonnet`
- Cleanup step (after processing work): delete `.active`, then re-spawn wait

No behavioral changes. Sonnet remains a pure service loop.

### 4. `channel_commit.sh`

**Location:** `modules/commit-enforcement/scripts/channel_commit.sh`

Changes:
- Path: `_pending_sonnet/chN/.heartbeat` (rename)
- Dispatch path: write commit-verification prompts to `_pending_sonnet/chN/`
- Two existing thresholds change:
  - **Warn threshold** (line 210): `age > 30` → `age > 300` (5 min). Warns but continues.
  - **Switch-to-local threshold** (line 205): `age > 300` → `age > 900` (15 min). Falls back to local verification.
- Liveness check (new, at existing `check_heartbeat()` call site — determines logging and fallback, not whether to dispatch). All states match the Liveness States table:
  - `.active` exists + `.heartbeat` fresh (<5 min) → listener alive, processing `<filename>`. Write prompt to `_pending_sonnet/chN/` anyway — listener picks it up next cycle after finishing current work.
  - `.active` exists + `.heartbeat` warn-stale (5–15 min) → listener busy on long task. Log `.active` contents, dispatch normally.
  - `.active` exists + `.heartbeat` stale (>15 min) → listener may be stuck. Log warning with `.active` contents. Write prompt anyway (if listener recovers it will pick it up), but also fall back to local verification for this dispatch.
  - `.heartbeat` fresh (<5 min) + no `.active` → listener idle, dispatch normally.
  - `.heartbeat` warn-stale (5–15 min) + no `.active` → listener slow or briefly stalled. Warn, dispatch normally.
  - `.heartbeat` stale (>15 min) + no `.active` → listener likely down. Warn, switch to local verification.
  - `.heartbeat` missing + any `.active` state → listener not started or crashed. Switch to local verification.

### 5. `session-orient.sh`

**Location:** `modules/core/hooks/session-orient.sh`

Currently cleans stale prompts from `_pending/` and `_pending/ch*/` (existing threshold: 1 hour for `.md` files). Must clean both `_pending_sonnet/` and `_pending_opus/` (and their `ch*/` subdirs), applying the same 1-hour stale-prompt threshold to both. Also clean stale `.active` files older than 30 minutes — these indicate a crashed session that never cleaned up.

Note: `session-orient.sh` fires only at SessionStart (hook trigger). Between sessions, a stale `.active` could persist. As a secondary defense, `channel_commit.sh`'s liveness check treats "stale heartbeat + `.active` present" as "listener may be stuck" and falls back to local verification — so a stuck `.active` degrades gracefully rather than blocking indefinitely.

### 6. `stop-task-check.sh`

**Location:** `modules/verification/hooks/stop-task-check.sh`

Currently detects Sonnet listeners by matching "Watching _pending/" in output (line 100). Replace pattern with `"Watching _pending_(sonnet|opus)/"`. This allows the stop hook to skip enforcement for both Sonnet and Opus listener output. Note: the "Watching..." string is emitted by the `/sonnet` and `/opus` command/skill docs (the announce line), not by `wait_for_work.sh` itself (which only returns a filename on stdout). Opus listener sessions still get full stop-hook enforcement for their actual work — the skip only applies to the "Watching..." announce line.

### 7. `safe-commit.sh`

**Location:** `modules/commit-enforcement/hooks/safe-commit.sh`

Path check at line 75: `_pending${PENDING_SUBDIR}` → `_pending_sonnet${PENDING_SUBDIR}`. `$PENDING_SUBDIR` is a variable already defined in `safe-commit.sh` (set from the `--channel` flag, e.g., `/ch1` or empty for unchanneled). This hook checks for the Sonnet listener directory only (commit verification is always dispatched to Sonnet). No need to check `_pending_opus/` — Opus sessions don't receive commit-verification prompts.

### 8. `spawn.py`

**Locations:**
- Sentinel: `modules/sprint-pipeline/tools/spawn.py` (lines 1032, 1040)
- Wakeful: `spawn.py` (lines 910, 918)

Changes (both copies):
- Scaffold template string: `_pending/chN/` → `_pending_sonnet/chN/`
- `mkdir` call: create both `_pending_sonnet/chN/` and `_pending_opus/chN/`
- No changes to session launch sequence (already calls `/opus N` which now starts the listener)

### 9. Installers

- `install.sh` line 662: `mkdir -p verification_findings/_pending` → create both dirs
- `install.ps1` line 506: same

## `.active` Signal File

**Format:** Single line: `<ISO-8601-timestamp> processing <prompt-filename>`

Example: `2026-03-23T20:15:00Z processing perfect_squad_ch1.md`

**Lifecycle:**
1. `wait_for_work.sh` finds oldest `.md` file
2. Writes `.active` with timestamp + filename
3. Returns filename to listener (stdout)
4. Listener processes work
5. Listener cleanup deletes `.active`
6. Listener session re-spawns `wait_for_work.sh` in background (fresh heartbeat, no `.active` = idle)

**Collision:** If `.active` already exists when `wait_for_work.sh` writes (e.g., residual from a crash before `session-orient.sh` runs), silently overwrite. The new timestamp + filename is the current truth.

**Consumer:** `channel_commit.sh` checks `.active` at its `check_heartbeat()` call site (logging and fallback decision, not a dispatch gate). Opus orchestrator can read `.active` to see what any session is working on.

## Liveness States

| `.heartbeat` | `.active` | Interpretation | `channel_commit.sh` action |
|---|---|---|---|
| Fresh (<5 min) | Absent | Listener alive, idle | Dispatch normally |
| Fresh (<5 min) | Present | Listener alive, processing `<filename>` | Write prompt anyway (queued for next cycle) |
| Warn-stale (5–15 min) | Absent | Listener slow or briefly stalled | Warn, dispatch normally |
| Warn-stale (5–15 min) | Present | Listener busy on long task | Log `.active` contents, dispatch normally |
| Stale (>15 min) | Present | Listener may be stuck | Log warning, dispatch + fall back to local |
| Stale (>15 min) | Absent | Listener likely down | Warn, switch to local verification |
| Missing | Any | Listener not started or crashed | Switch to local verification |

## Full Flow Example

**Sprint start (orchestrator session):**
1. User runs `/2` — orchestrator designs work, determines 3 channels needed
2. Orchestrator writes `CURRENT_TASK_ch1.md`, `CURRENT_TASK_ch2.md`, `CURRENT_TASK_ch3.md`
3. Orchestrator writes launch prompts to `_pending_opus/ch1/`, `_pending_opus/ch2/`, `_pending_opus/ch3/`
4. User runs `/spawn duo 3` — opens 3 Opus + 3 Sonnet terminals

**Auto-start (each Opus session):**
5. `/spawn duo` types `/opus N` in each Opus window and `/sonnet N` in each Sonnet window
6. `/opus N` creates channel, starts `wait_for_work.sh --model opus --channel N` in background
7. Wait script finds the launch prompt (oldest-first), writes `.active` (`2026-03-23T20:15:00Z processing launch_prerequisites.md`), returns filename
8. Opus reads prompt, deletes prompt file, begins work (`.active` remains present — observers see what it's working on)
9. Opus dispatches mechanical work to Sonnet via `_pending_sonnet/chN/`
9a. When work completes: Opus deletes `.active`, re-spawns `wait_for_work.sh` in background

**Mid-flight correction (orchestrator):**
10. User tells orchestrator: "Ch2 is stuck, send it this fix"
11. Orchestrator writes `_pending_opus/ch2/fix_breathwork_error.md`
12. Ch2's background wait finds it, writes `.active`, returns filename
13. Opus ch2 reads correction, deletes prompt, adjusts work (`.active` persists during execution). On completion: deletes `.active`, re-spawns wait

**Orchestrator checking status:**
14. Reads `_pending_sonnet/ch1/.active` → "processing squad_ch1.md" (Sonnet busy with ch1's squad)
15. Reads `_pending_opus/ch2/.heartbeat` → fresh, no `.active` → ch2 Opus idle

## Migration: `_pending/` → `_pending_sonnet/`

101 occurrences across 33 files in the sentinel repo. Full file list:

**Scripts (functional — must update):**
- `modules/commit-enforcement/scripts/wait_for_work.sh` (3)
- `modules/commit-enforcement/scripts/channel_commit.sh` (2)
- `modules/commit-enforcement/hooks/safe-commit.sh` (1)
- `modules/core/hooks/session-orient.sh` (5)
- `modules/verification/hooks/stop-task-check.sh` (2)
- `modules/sprint-pipeline/tools/spawn.py` (2)
- `install.sh` (1)
- `install.ps1` (1)

**Commands + Skills (documentation — path-only `_pending/` → `_pending_sonnet/` string rename, no behavioral changes; owned by Components 2 and 3 for opus/sonnet files, remainder assigned to a single implementation plan task as mechanical find-and-replace across all listed files):**
- `modules/sprint-pipeline/commands/sonnet.md` (9)
- `modules/sprint-pipeline/skills/sonnet/SKILL.md` (10)
- `modules/sprint-pipeline/commands/opus.md` (5)
- `modules/sprint-pipeline/skills/opus/SKILL.md` (5)
- `modules/sprint-pipeline/commands/build.md` (1)
- `modules/sprint-pipeline/skills/build/SKILL.md` (1)
- `modules/sprint-pipeline/commands/design.md` (2)
- `modules/sprint-pipeline/skills/design/SKILL.md` (2)
- `modules/sprint-pipeline/commands/finalize.md` (2)
- `modules/sprint-pipeline/skills/finalize/SKILL.md` (2)
- `modules/sprint-pipeline/commands/perfect.md` (3)
- `modules/sprint-pipeline/skills/perfect/SKILL.md` (1)
- `modules/sprint-pipeline/commands/audit.md` (2)
- `modules/sprint-pipeline/skills/audit/SKILL.md` (1)
- `modules/sprint-pipeline/templates/plugin-auto-invoke.md` (1)
- `modules/core/commands/cold.md` (1)
- `modules/core/skills/cold/SKILL.md` (1)
- `modules/core/commands/cleanup.md` (3)
- `modules/core/skills/cleanup/SKILL.md` (3)
- `modules/core/reference/operator-cheat-sheet.md` (4)
- `modules/commit-enforcement/reference/channel-routing.md` (1)

**Tests (fixtures — must update):**
- `modules/commit-enforcement/tests/test_safe_commit.sh` (16)
- `modules/commit-enforcement/tests/test_channel_commit.sh` (5)
- `modules/core/tests/test_session_orient.sh` (2)
- `modules/verification/tests/test_stop_task_check.sh` (1)

**Wakeful propagation (after sentinel):**
- `scripts/wait_for_work.sh` (add `--model` flag, oldest-first, `.active` write)
- `scripts/channel_commit.sh` (path rename + threshold update: warn 30→300, switch-to-local 300→900, four-state liveness check)
- `scripts/claude-hooks/safe-commit.sh` (path rename)
- `scripts/claude-hooks/stop-task-check.sh` (add listener bypass for `"Watching _pending_(sonnet|opus)/"` — currently absent from Wakeful copy)
- `.claude/commands/sonnet.md`, `opus.md`, `squad.md`, `1.md`–`5.md`, `cold.md`, `cleanup.md`, and other commands containing `_pending/`
- `.claude/reference/channel-routing.md`
- `.gitignore` (replace `verification_findings/_pending/` with `verification_findings/_pending_sonnet/` + `verification_findings/_pending_opus/`)
- `CLAUDE.md` — two references: line 36 (`dispatch via _pending/[chN/]`) and Workflow section (`File-signal via _pending/`). **Governance-protected file: requires GOVERNANCE-EDIT-AUTHORIZED marker in CT before editing.**
- `spawn.py` (template string + mkdir both dirs)

### Migration strategy

This is a **coordinated atomic deployment** within each repo. All `_pending/` → `_pending_sonnet/` renames happen in a single commit per repo. Running listeners must be restarted after the commit (they watch the old path).

**Order:**
1. Sentinel repo: single commit renames all 33 files. Run all test suites to verify.
2. Wakeful repo: propagate the same rename. Restart any active Sonnet/Opus listeners.
3. Any other downstream projects: update on next install or manual propagation.

No transition period or dual-path support. The directories are gitignored (runtime-only), so there is no git history to break. The only coordination needed is: don't have a listener running on the old path while dispatching to the new path. Restarting listeners after the commit handles this.

## Testing

- All existing tests in `test_safe_commit.sh`, `test_channel_commit.sh`, `test_session_orient.sh`, `test_stop_task_check.sh` must pass after rename
- New tests for `wait_for_work.sh`: `--model` flag, oldest-first ordering, `.active` write, `.active` overwrite when pre-existing (silently replace)
- New tests for `channel_commit.sh`: liveness check covering all 7 states from the Liveness States table (fresh+absent, fresh+present, warn-stale+absent, warn-stale+present, stale+present, stale+absent, missing)
- New tests for `session-orient.sh`: `.active` stale cleanup in both `_pending_sonnet/chN/` and `_pending_opus/chN/` (create `.active` older than 30 min in each, verify both deleted on session start)
- Update `test_stop_task_check.sh` fixture: change `"Watching _pending/"` to `"Watching _pending_sonnet/"` (matches new regex `_pending_(sonnet|opus)/`; add second fixture with `"Watching _pending_opus/"` to verify both variants bypass)
- New test for `spawn.py`: verify both `_pending_sonnet/chN/` and `_pending_opus/chN/` directories are created

## Out of Scope

- Opus-to-Opus dispatch (Opus sessions don't send prompts to other Opus sessions — orchestrator does)
- YAML frontmatter parsing for Opus prompts (Opus reads prose; structured YAML optional)
- Changes to the verification squad system (squad dispatch still goes through Sonnet)
