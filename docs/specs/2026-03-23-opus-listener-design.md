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
| D9 | Opus listeners still get stop-hook enforcement | Unlike Sonnet (stateless service loop), Opus holds state and should save it |

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
- **`--model` flag** (optional, defaults to `sonnet`): selects `_pending_opus/` or `_pending_sonnet/`. All callers should pass it explicitly; the default exists only for backward compatibility during migration.
- **Oldest-first ordering:** Replace arbitrary glob match with `ls -tr "$PENDING_DIR"/*.md 2>/dev/null | head -1`. Returns oldest mtime first.
- **`.active` signal:** Before returning the filename, write `.active` containing `<ISO-8601-timestamp> processing <filename>`. Written to `$PENDING_DIR/.active`.
- Heartbeat mechanism unchanged (background loop, PPID self-termination).

### 2. `/opus N` command + skill

**Location:** `modules/sprint-pipeline/commands/opus.md`, `modules/sprint-pipeline/skills/opus/SKILL.md`

New additions to the startup procedure:
1. Create Opus pending dir: `mkdir -p verification_findings/_pending_opus/chN`
2. Start background listener: `bash scripts/wait_for_work.sh --model opus --channel N` with `run_in_background: true`
3. On prompt arrival: read prompt, delete prompt file, delete `.active`, re-spawn `wait_for_work.sh` in background, execute instructions
4. Opus finishes current atomic operation before reading a new prompt (prompt delivery is at tool-call boundary)

Updated dispatch path: Sonnet dispatches go to `_pending_sonnet/chN/` (renamed).

Updated Sonnet heartbeat check path: `_pending_sonnet/chN/.heartbeat`.

### 3. `/sonnet` command + skill

**Location:** `modules/sprint-pipeline/commands/sonnet.md`, `modules/sprint-pipeline/skills/sonnet/SKILL.md`

Changes:
- Directory: `_pending_sonnet/chN/` (renamed from `_pending/chN/`)
- `wait_for_work.sh` call adds `--model sonnet`
- Cleanup step deletes `.active` before re-spawning wait

No behavioral changes. Sonnet remains a pure service loop.

### 4. `channel_commit.sh`

**Location:** `modules/commit-enforcement/scripts/channel_commit.sh`

Changes:
- Path: `_pending_sonnet/chN/.heartbeat` (rename)
- Dispatch path: write commit-verification prompts to `_pending_sonnet/chN/`
- Two existing thresholds change:
  - **Warn threshold** (line 210): `age > 30` → `age > 300` (5 min). Warns but continues.
  - **Switch-to-local threshold** (line 205): `age > 300` → `age > 900` (15 min). Falls back to local verification.
- Three-state liveness check (new, before dispatching):
  - `.active` exists → listener processing `<filename>`. Write prompt to `_pending_sonnet/chN/` anyway — listener picks it up next cycle after finishing current work.
  - `.heartbeat` fresh (<15 min) + no `.active` → listener idle, dispatch normally
  - `.heartbeat` stale (>15 min) + no `.active` → warn, switch to local verification

### 5. `session-orient.sh`

**Location:** `modules/core/hooks/session-orient.sh`

Currently cleans stale prompts from `_pending/` and `_pending/ch*/`. Must clean both `_pending_sonnet/` and `_pending_opus/` (and their `ch*/` subdirs). Also clean stale `.active` files older than 30 minutes — these indicate a crashed session that never cleaned up. Without this, a crashed session leaves `.active` indefinitely, causing `channel_commit.sh` to permanently see "listener processing."

### 6. `stop-task-check.sh`

**Location:** `modules/verification/hooks/stop-task-check.sh`

Currently detects Sonnet listeners by matching "Watching _pending/" in output (line 100). Replace pattern with `"Watching _pending_(sonnet|opus)/"`. This allows the stop hook to skip enforcement for both Sonnet and Opus listener output. Note: Opus listener sessions still get full stop-hook enforcement for their actual work — the skip only applies to the "Watching..." status line output from `wait_for_work.sh`.

### 7. `safe-commit.sh`

**Location:** `modules/commit-enforcement/hooks/safe-commit.sh`

Path check at line 75: `_pending${PENDING_SUBDIR}` → `_pending_sonnet${PENDING_SUBDIR}`. This hook checks for the Sonnet listener directory only (commit verification is always dispatched to Sonnet). No need to check `_pending_opus/` — Opus sessions don't receive commit-verification prompts.

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
6. `wait_for_work.sh` re-spawns (fresh heartbeat, no `.active` = idle)

**Consumer:** `channel_commit.sh` checks `.active` before dispatching. Opus orchestrator can read `.active` to see what any session is working on.

## Liveness States

| `.heartbeat` | `.active` | Interpretation |
|---|---|---|
| Fresh (<15 min) | Absent | Listener alive, idle, ready for work |
| Fresh (<15 min) | Present | Listener alive, processing `<filename>` |
| Stale (>15 min) | Present | Listener may be stuck (processing but no heartbeat refresh) |
| Stale (>15 min) | Absent | Listener likely down |
| Missing | Any | Listener not started or crashed |

## Full Flow Example

**Sprint start (orchestrator session):**
1. User runs `/2` — orchestrator designs work, determines 3 channels needed
2. Orchestrator writes `CURRENT_TASK_ch1.md`, `CURRENT_TASK_ch2.md`, `CURRENT_TASK_ch3.md`
3. Orchestrator writes launch prompts to `_pending_opus/ch1/`, `_pending_opus/ch2/`, `_pending_opus/ch3/`
4. User runs `/spawn duo 3` — opens 3 Opus + 3 Sonnet terminals

**Auto-start (each Opus session):**
5. `/spawn duo` types `/opus N` in each Opus window
6. `/opus N` creates channel, starts `wait_for_work.sh --model opus --channel N` in background
7. Wait script finds the launch prompt (oldest-first), writes `.active` (`2026-03-23T20:15:00Z processing launch_prerequisites.md`), returns filename
8. Opus reads prompt, deletes prompt file, deletes `.active`, re-spawns wait in background, begins work
9. Opus dispatches mechanical work to Sonnet via `_pending_sonnet/chN/`

**Mid-flight correction (orchestrator):**
10. User tells orchestrator: "Ch2 is stuck, send it this fix"
11. Orchestrator writes `_pending_opus/ch2/fix_breathwork_error.md`
12. Ch2's background wait finds it, writes `.active`, returns filename
13. Opus ch2 reads correction, deletes prompt + `.active`, re-spawns wait, adjusts, continues

**Orchestrator checking status:**
14. Reads `_pending_sonnet/ch1/.active` → "processing squad_ch1.md" (Sonnet busy with ch1's squad)
15. Reads `_pending_opus/ch2/.heartbeat` → fresh, no `.active` → ch2 Opus idle

## Migration: `_pending/` → `_pending_sonnet/`

~75 occurrences across 31 files in the sentinel repo. Full file list:

**Scripts (functional — must update):**
- `modules/commit-enforcement/scripts/wait_for_work.sh` (3)
- `modules/commit-enforcement/scripts/channel_commit.sh` (2)
- `modules/commit-enforcement/hooks/safe-commit.sh` (1)
- `modules/core/hooks/session-orient.sh` (5)
- `modules/verification/hooks/stop-task-check.sh` (2)
- `modules/sprint-pipeline/tools/spawn.py` (2)
- `install.sh` (1)
- `install.ps1` (1)

**Commands + Skills (documentation — must update):**
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
- `scripts/wait_for_work.sh`
- `scripts/channel_commit.sh`
- `.claude/commands/sonnet.md`, `opus.md`, and other commands
- `.claude/reference/channel-routing.md`
- `.gitignore`
- `CLAUDE.md` accumulated corrections
- `spawn.py` (template string + mkdir)

### Migration strategy

This is a **coordinated atomic deployment** within each repo. All `_pending/` → `_pending_sonnet/` renames happen in a single commit per repo. Running listeners must be restarted after the commit (they watch the old path).

**Order:**
1. Sentinel repo: single commit renames all 32 files. Run all test suites to verify.
2. Wakeful repo: propagate the same rename. Restart any active Sonnet/Opus listeners.
3. Any other downstream projects: update on next install or manual propagation.

No transition period or dual-path support. The directories are gitignored (runtime-only), so there is no git history to break. The only coordination needed is: don't have a listener running on the old path while dispatching to the new path. Restarting listeners after the commit handles this.

## Testing

- All existing tests in `test_safe_commit.sh`, `test_channel_commit.sh`, `test_session_orient.sh`, `test_stop_task_check.sh` must pass after rename
- New tests for `wait_for_work.sh`: `--model` flag, oldest-first ordering, `.active` write
- New test for `channel_commit.sh`: three-state liveness check (`.active` present, fresh heartbeat, stale heartbeat)

## Out of Scope

- Opus-to-Opus dispatch (Opus sessions don't send prompts to other Opus sessions — orchestrator does)
- YAML frontmatter parsing for Opus prompts (Opus reads prose; structured YAML optional)
- Changes to the verification squad system (squad dispatch still goes through Sonnet)
