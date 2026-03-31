# Opus Listener Design Spec — Review

**Spec reviewed:** `docs/specs/2026-03-23-opus-listener-design.md`
**Reviewer:** Spec review agent
**Date:** 2026-03-23

---

## Issue List

### MUST-FIX

**M1. Sentinel `spawn.py` missing from Component Changes and migration list.**
The spec lists `spawn.py` under Component 8 as "Project-level (Wakeful: `spawn.py`, sentinel: to be added or referenced)." However, the sentinel repo already has `modules/sprint-pipeline/tools/spawn.py` with 2 `_pending` references (lines 1032 and 1040). This file is absent from both the numbered Component Changes section and the migration file list. An implementer following the spec would miss it.

**M2. `.active` cleanup not specified for Opus listener.**
The `.active` lifecycle (Section ".active Signal File", step 5) says "Listener cleanup deletes `.active`." For Sonnet, Component 3 explicitly states: "Cleanup step deletes `.active` before re-spawning wait." For Opus, Component 2 step 3 says: "read prompt, delete file, re-spawn `wait_for_work.sh` in background, execute instructions." The "delete file" refers to the prompt `.md` — `.active` deletion is never mentioned in the Opus procedure. An implementer could leave `.active` dangling after every Opus prompt cycle, causing `channel_commit.sh` to permanently see "listener processing."

**M3. Stale `.active` from crashed session has no cleanup path.**
If Opus or Sonnet crashes mid-processing, `.active` persists. The Liveness States table identifies the state "Stale heartbeat + `.active` present = Listener may be stuck" but specifies no remediation. Section 5 (`session-orient.sh`) says it must clean both `_pending_sonnet/` and `_pending_opus/` subdirs but only mentions stale **prompt files** — not stale `.active` files. A crashed session leaves `.active` indefinitely, blocking `channel_commit.sh` (which sees "listener processing" and queues instead of dispatching). Add `.active` cleanup to `session-orient.sh` (e.g., delete `.active` older than 30 minutes).

**M4. Heartbeat threshold description is inaccurate.**
The spec says (Component 4, `channel_commit.sh`): "Stale threshold: 30s → 900s (15 minutes)." The actual code has TWO thresholds:
- Line 210: warn at >30s (`WARNING: Sonnet heartbeat stale`)
- Line 205: switch to local verification at >300s (5 minutes)

The spec conflates these into a single "30s threshold." An implementer reading "30s → 900s" would change the warn threshold on line 210 to 900s, which would suppress all staleness warnings. The spec must specify what happens to BOTH thresholds. Presumably the intent is:
- Warn threshold: 30s → removed (or raised significantly, since `.active` now provides proof-of-work)
- Switch-to-local threshold: 300s → 900s

**M5. `_pending/` → `_pending_sonnet/` is a breaking rename requiring coordinated deployment.**
The spec doesn't address migration ordering. If the sentinel scripts are updated but downstream projects (Wakeful) still reference `_pending/`, or if one terminal has the old code and another has the new code, dispatches go to the wrong directory. The spec needs either:
- A migration section specifying deployment order (sentinel first, then propagate to projects), or
- A transition period where `wait_for_work.sh` checks BOTH `_pending/` and `_pending_sonnet/` and logs a deprecation warning, or
- An explicit statement that this is a coordinated atomic deployment (all files updated in one commit)

### SHOULD-FIX

**S1. Migration count is overstated: "99 occurrences across 32 files."**
Grep of the sentinel repo (excluding the spec itself) finds 74 occurrences of `_pending` across 30 files. This does not account for the spec's own 8 self-references. Even including `_pending` occurrences in comments and strings, 99 is unreachable from the sentinel repo alone. If the count includes Wakeful propagation files (listed separately at the bottom), that should be stated. Inaccurate counts erode implementer trust in the spec's completeness.

**S2. `stop-task-check.sh` pattern update needs specificity.**
The spec says: "Update pattern to match both `_pending_sonnet/` and `_pending_opus/`." The current code (line 100) is:
```bash
if echo "$LAST_MSG" | grep -qiE "Watching _pending/" 2>/dev/null; then
```
The spec should specify the replacement pattern, e.g., `"Watching _pending_(sonnet|opus)/"`. Without this, an implementer might write something that accidentally matches unrelated output.

**S3. `safe-commit.sh` description incomplete.**
The spec says (Component 7): "Path check at line 75: `_pending${PENDING_SUBDIR}` → `_pending_sonnet${PENDING_SUBDIR}`." But this change means `safe-commit.sh` only checks for the Sonnet listener directory. If in the future Opus sessions also trigger `safe-commit.sh` (which they do — D9 says "Opus listeners still get stop-hook enforcement"), the hook should check for EITHER listener directory. The spec should clarify whether `safe-commit.sh` should check `_pending_sonnet` only or also `_pending_opus`.

**S4. D8 "prompt delivery at tool-call boundary" is a Claude Code runtime behavior, not something the spec can enforce.**
The spec states: "CC delivers `run_in_background` completions as system messages; Opus finishes current atomic operation before reading." This is a description of CC's existing behavior, not a design decision. If CC ever changes this behavior, the assumption breaks silently. The spec should note this as an assumption/dependency rather than a decision, and specify fallback behavior if prompts arrive mid-operation.

**S5. Flow example omits `.active` lifecycle.**
The Full Flow Example (steps 5-13) never mentions `.active` being written or deleted. Step 7 says "Wait script finds the launch prompt (oldest-first), writes `.active`, returns filename" — good, `.active` creation is shown. But step 8 says "Opus reads prompt, deletes file, re-spawns wait in background, begins work" without mentioning `.active` deletion. The flow example should demonstrate the complete `.active` lifecycle to be self-contained.

**S6. Three-state liveness check in `channel_commit.sh` — "queue dispatch" behavior undefined.**
Component 4 says when `.active` exists: "log what it's working on, queue dispatch." What does "queue dispatch" mean? Write the prompt file to `_pending_sonnet/` anyway (and the listener picks it up after finishing current work)? Or defer and retry? The current `wait_for_work.sh` processes one file at a time (oldest-first), so writing the file is probably fine — but the spec should say so explicitly. An implementer might build an actual queue mechanism.

### NIT

**N1. Sonnet SKILL.md has 10 occurrences, not 9 as stated in the count grep.**
The migration list says `modules/sprint-pipeline/skills/sonnet/SKILL.md` has 10 occurrences. Grep of the actual file returns 9 lines containing `_pending`. If one line contains `_pending` twice, that accounts for the discrepancy — but occurrence counts should be by-line for implementer use (since text replacement is line-oriented).

**N2. `--model` flag described as "required" then "Default: `sonnet`".**
Line 86 says `--model` flag is "(required)" and then in parentheses says "Default: `sonnet` (backward compat)." A required flag with a default is contradictory. Pick one: either it's required (callers must pass it), or it defaults to `sonnet` (callers can omit it).

**N3. D6 rationale references "was 30s" but the production threshold is 300s.**
D6 says: "15-minute stale threshold (was 30s)." As noted in M4, the functional threshold (switch-to-local) is 300s, not 30s. The 30s threshold only triggers a warning. This is misleading in the decision table even if the detailed description eventually clarifies.

**N4. Component numbering gap: no Component for `wait_for_results.sh`.**
`channel_commit.sh` calls `wait_for_results.sh` (line 158) which is a separate script. If `wait_for_results.sh` has any `_pending/` references, it would be missed. (Grep shows it does not, so this is informational — but the spec should confirm it was checked.)

---

## Verdict: **Issues Found**

The spec is well-structured and covers the design comprehensively. The migration file list is notably thorough. However, 5 MUST-FIX issues need resolution before implementation:

1. The sentinel's own `spawn.py` is missing from the change list (M1)
2. `.active` cleanup is unspecified for Opus (M2) and for crash recovery (M3)
3. The heartbeat threshold description conflates two distinct thresholds (M4)
4. The breaking rename has no migration/deployment strategy (M5)

Once these are addressed, the spec is implementable.

## Resolution Status (2026-03-30)

All MUST-FIX items were addressed during implementation:
- M1-M5: Resolved — implementation incorporated all review feedback. See deployed code and tests for verification.
