---
name: perfect
description: "Post-implementation quality pass: evaluate, grill loop, verification squad, and proof of correctness with user gates. Phase /4 of the sprint pipeline. Also invoked as /4."
---

# /perfect — Post-Implementation Quality Pass (alias: /4)

`/perfect` (session files) or `/perfect <subsystem>` (named target)

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress->completed.

## Delegation

**Default mode:** Steps marked DELEGATE: spawn Sonnet subagent via `Agent(model: "sonnet")` with the delegation prompt. Output to `verification_findings/` paths specified per step.

**Duo mode:** Steps marked DELEGATE: update CT first, write self-contained prompt to `verification_findings/_pending_sonnet/[chN/]`, wait via `bash scripts/wait_for_results.sh <paths>`.

## Phase 1: Scope and Evaluate

### 1. Scope

- Bare: session files, fall back to `git diff main...HEAD`.
- Named subsystem: read every file -> `verification_findings/perfect_inventory[_chN].md`.

### 2. Evaluate

Read in-scope files + authoritative spec + project rules. Catalog: accidental complexity, incomplete migrations, over/under-engineering, naming lies. Write to `verification_findings/perfect_evaluation[_chN].md`.

### 3. Branch — user gate

- **Already elegant** -> Phase 2.
- **Sound approach, messy execution** -> Step 4, then Phase 2.
- **Mediocre approach** -> Step 5, then Phase 2.

Present assessment. Wait for approval.

### 4. Simplify

DELEGATE `perfect_simplify_<timestamp>.md`, four agents. Report only. Read spec for agent check details before writing prompts. YAML frontmatter required — resolve bracket notation before writing:

```yaml
---
type: squad
agents:
  - name: code-reuse
    output_path: verification_findings/perfect_simplify_reuse[_chN].md
  - name: code-quality
    output_path: verification_findings/perfect_simplify_quality[_chN].md
  - name: efficiency
    output_path: verification_findings/perfect_simplify_efficiency[_chN].md
  - name: migration-completeness
    output_path: verification_findings/perfect_simplify_migration[_chN].md
---
```

Opus reviews all four → `verification_findings/perfect_simplify_report[_chN].md`. Non-mechanical fixes directly; mechanical back to Sonnet. If tests break, revert. Commit via `channel_commit.sh`.

### 5. Scrap and rewrite

**5a** Design → `verification_findings/perfect_rewrite_design[_chN].md`: file structure, data flow, eliminations, preservations, migration strategy. **User gate.**
**5b** DELEGATE build.
**Default mode:** Spawn `sonnet-implementer` via `Agent(model: "sonnet")`. `_v2` suffix. TDD. One commit per unit via `channel_commit.sh`.
**Duo mode:** Write to `_pending_sonnet/[chN/]perfect_rewrite_<timestamp>.md`.

**5c** DELEGATE swap.
**Default mode:** Spawn `sonnet-implementer` via `Agent(model: "sonnet")`. Rename, update imports, delete old. Atomic commit.
**Duo mode:** Write to `_pending_sonnet/[chN/]perfect_swap_<timestamp>.md`.
**5d** Same as Step 4 scoped to new code. Output paths `perfect_simplify_v2_*.md`.
**5e** Prove equivalence: existing behavioral tests pass, new tests pass, no broken callers. Write to `verification_findings/perfect_equivalence[_chN].md`.

## Phase 2: Grill Loop (max 5 rounds)

`/grill` all `/perfect` work product. Fix -> test -> repeat until clean or 5 rounds. Batch all grill fixes into one commit before Phase 3. If approach is wrong (not cleanup), go back to Step 2. After round 5, present to user.

## Phase 3: Squad Loop (max 3 rounds)

DELEGATE `perfect_squad_<timestamp>.md` with 5-agent prompts from `.claude/reference/verification-squad.md` → `verification_findings/squad_[chN_]sonnet/`.

All agents must `VERDICT: PASS` or `VERDICT: WARN`. FAIL: fix → re-run failed agents only. Repeat until clean or 3 rounds. After round 3, present remaining to user.

## Phase 4: Prove Correctness — user gate

DELEGATE `perfect_proof_<timestamp>.md`, two agents. Read spec for agent task details before writing prompts. YAML frontmatter required — resolve bracket notation before writing:

```yaml
---
type: squad
agents:
  - name: behavioral-change-map
    output_path: verification_findings/perfect_proof_changes[_chN].md
  - name: test-coverage-audit
    output_path: verification_findings/perfect_proof_coverage[_chN].md
---
```

Both agents run in parallel (no runtime dependency). After both complete, Opus reads Agent 1 then Agent 2, combines → `verification_findings/perfect_proof[_chN].md`. Present plain English: what changed, what's tested, what's not, gaps. **Stop.** User decides.

## Rules

1. Evaluate before acting. Never simplify what you'll scrap.
2. Sonnet runs mechanical analysis. Opus reviews and fixes.
3. Finish migrations completely.
4. Tests earn their place. Delete bad tests.
5. Plain English proof, not code dump.
6. User gates: Step 3, Step 5a, Phase 4.
7. No scope creep.
8. Subsystem inventory in flat file, not memory.

After Phase 4 user gate: announce `/4` complete, ready for `/5` (`/finalize`).
