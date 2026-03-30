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

DELEGATE four agents. Report only. YAML frontmatter required.

### 5. Scrap and rewrite

**5a** Design -> user gate.
**5b** DELEGATE build. Sonnet: scaffolding. Opus: judgment.
**5c** DELEGATE swap. Rename, update imports, delete old.
**5d** Same as Step 4 scoped to new code.
**5e** Prove equivalence.

## Phase 2: Grill Loop (max 5 rounds)

`/grill` all `/perfect` work product. Fix -> test -> repeat until clean or 5 rounds. Batch all grill fixes into one commit before Phase 3.

## Phase 3: Squad Loop (max 3 rounds)

DELEGATE 6-agent squad from `.claude/reference/verification-squad.md`. All agents must PASS or WARN. FAIL: fix -> re-run failed agents only. Max 3 rounds.

## Phase 4: Prove Correctness — user gate

DELEGATE two agents: behavioral-change-map + test-coverage-audit. Opus combines -> present plain English: what changed, what's tested, what's not.

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
