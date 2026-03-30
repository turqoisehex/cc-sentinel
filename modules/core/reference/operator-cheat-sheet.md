# Operator Cheat Sheet

Quick reference for running CC sessions with cc-sentinel governance.

---

## Sprint Pipeline

| Phase | Command | Alias | What it does |
|-------|---------|-------|-------------|
| Audit | `/audit` | `/1` | Spec integrity, scan deps, write CURRENT_TASK.md |
| Design | `/design` | `/2` | Brainstorm → spec → implementation plan |
| Build | `/build` | `/3` | Autonomous execution of approved plan |
| Quality | `/perfect` | `/4` | Evaluate → simplify or rewrite → grill → verify → prove correctness |
| Finalize | `/finalize` | `/5` | Review, prove, close out, reset |

## Utility Commands

| Command | What it does |
|---------|-------------|
| `/opus N` | Set channel for multi-Opus parallel sessions |
| `/grill` | Adversarial self-check (4 questions, verify each) |
| `/verify [scope]` | up to 6-agent verification (default/full/last N/since/on) |
| `/cold` | Prepare CURRENT_TASK.md for cold start |
| `/sonnet` | Verification listener (duo mode only — run in Sonnet terminal) |
| `/rewrite` | Ground-up rewrite of a subsystem |
| `/mistake` | Capture CC error into governance rules |
| `/prune-rules` | Review accumulated corrections — promote, merge, or delete |
| `/status` | Phase, progress, blockers, context usage |
| `/cleanup` | End-of-session housekeeping |
| `/self-test` | Verify installation integrity |

---

## Default Workflow (Native Dispatch)

1. Opus terminal: `/audit` → `/design` → `/build` → `/perfect` → `/finalize`
2. Sonnet work spawned natively via `Agent(model: "sonnet")` — no separate terminal needed
3. For parallel Opus sessions: `/spawn opus N` — each Opus dispatches to others via `_pending_opus/`

## Duo Workflow (Persistent Sonnet Listeners)

For high-volume Sonnet work benefiting from session persistence. Set via `/spawn duo N` which sets `CC_DUO_MODE=1`.

1. **Terminal 1 (Opus Ch1):** `/opus 1` → work through pipeline
2. **Terminal 2 (Sonnet Ch1):** `/sonnet 1` (watches `_pending_sonnet/ch1/` only)
3. **Terminal 3 (Opus Ch2):** `/opus 2` → work through pipeline
4. **Terminal 4 (Sonnet Ch2):** `/sonnet 2` (watches `_pending_sonnet/ch2/` only)

Each channel pair is isolated: Opus N dispatches to `_pending_sonnet/chN/`, Sonnet N watches only `_pending_sonnet/chN/`. Result files get `_chN` suffix. CURRENT_TASK.md uses shared + channel sections.

---

## What to Expect

**During `/build`:** CC works autonomously. Only pauses for genuine design decisions.

**Verification is aggressive.** Every commit runs per-commit agents (adversarial + cold reader). Completion claims require fresh squad evidence on disk.

**After compaction:** CC re-reads CLAUDE.md → CURRENT_TASK.md → resumes. If confused, kill and restart.

---

## When to Kill a Session

- Same mistake twice after correction
- Contradicts design invariants or project rules
- Claims done without verification
- Context above ~75% and responses getting sloppy
- You're fighting it more than directing it

`/clear` or close terminal. `CURRENT_TASK.md` preserves state.

---

## Key Files

| File | Purpose |
|------|---------|
| `CURRENT_TASK.md` | Session state — read first after every compaction |
| `CLAUDE.md` + `.claude/rules/` | Always-loaded rules |
| `.claude/commands/` | Slash commands |
| `.claude/agents/` | Agent definitions |
| `.claude/reference/` | On-demand docs |
| `verification_findings/` | Ephemeral squad/agent output (gitignored) |

---

## Terminology

| Term | Meaning |
|------|---------|
| **TaskCreate** | Claude Code's built-in task tracking tool. Commands use "TaskCreate every step" to mean: create a checklist of tasks and mark them in_progress → completed as you go. |
| **CT** | CURRENT_TASK.md — the session state file. |
| **Squad** | The verification squad — up to 6 agents (mechanical, adversarial, completeness, dependency, cold reader, performance). Invoked via `/verify`. |

---

## Governance Edits

Protected files: CLAUDE.md, slash commands, agents, rules.

1. Add `GOVERNANCE-EDIT-AUTHORIZED` as standalone line in `CURRENT_TASK.md`
2. Edit the protected file
3. Remove the marker

---

## Commits

```bash
# Normal (verification + tests)
bash scripts/channel_commit.sh --files "file1 file2" -m "message"

# Skip squad (WIP/intermediate commits)
bash scripts/channel_commit.sh --files "file1 file2" -m "message" --skip-squad

# Channel-specific
bash scripts/channel_commit.sh --channel N --files "file1 file2" -m "message"
```
