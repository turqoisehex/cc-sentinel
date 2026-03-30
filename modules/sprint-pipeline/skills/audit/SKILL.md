---
name: audit
description: "Sprint start: spec integrity checking, staleness scan, dependency verification, and initial CT setup. Phase /1 of the sprint pipeline. Also invoked as /1."
---

# /audit — Sprint Start (alias: /1)

**Trigger:** Beginning of each sprint. **Prerequisite:** Sprint N code items checked before starting N+1 (developer-parallel tasks excepted).

**Channel:** CT=`CURRENT_TASK_chN.md` (channeled) or `CURRENT_TASK.md`. Scripts: `SENTINEL_CHANNEL=N`. `[chN/]`=dispatch subdir, `[_chN]`=file suffix, `[chN_]`=squad prefix. Full rules: `.claude/reference/channel-routing.md`.

**Step 0:** Before any other work, TaskCreate every step. Mark in_progress->completed.

## Procedure

### Step 1: Spec integrity

User specifies which spec(s). If not specified, ASK.

#### 1a. Dispatch agents

For each spec, count lines and dispatch general-purpose agents (`run_in_background: true`). Substitute ALL placeholders before dispatching: `[SPEC_FILE]`=full path, `[SPEC_NAME]`=filename stem, `[OUTPUT_FILE]`=set per dispatch path below.

**Under 2000 lines:** One agent, full file. `[OUTPUT_FILE]`=`verification_findings/spec_integrity_[SPEC_NAME].md`.

**2000+ lines:** Two-tier dispatch.
a. Grep `## ` headings -> section outline with line ranges.
b. **Tier 1 (structural):** Full file. Prioritize cross-section contradictions.
c. **Tier 2 (detail):** ~1500-2500 line chunks at `## ` boundaries. One agent per chunk.

#### 1b. Parent direct verification (while agents run)

- **Tables:** Verify all arithmetic (row/column sums, totals).
- **Cross-references:** Grep spec references to other files -> verify each exists on disk.
- **Enums/constants:** Grep spec enum values -> compare against code definitions.

#### 1c. Consolidate

Read all agent outputs. Deduplicate with 1b findings. Remove confirmed false positives. Write to `verification_findings/spec_integrity_[SPEC_NAME].md`.

#### 1d. Present findings

Show consolidated findings. Do NOT auto-fix. **User gate.**

### Step 2: Staleness scan + dependency verification

**Default mode:** Spawn Sonnet subagent via `Agent(model: "sonnet")` with the delegation prompt.

**Duo mode:** MANDATORY SONNET DELEGATION. Write prompt to `verification_findings/_pending_sonnet/[chN/]sprint_start_scan_<timestamp>.md`. Three agents:

- **Agent A — Infrastructure:** Read sprint-dependent files. Report: exists/stubbed/missing, line counts, TODO markers.
- **Agent B — Specs:** Read referenced specs. Verify content counts, cross-references, terminology.
- **Agent C — Dependencies:** Prerequisite sprints merged with passing tests.

Read results. Fix stale items. Fix terminology violations on sight.

### Step 3: Write INITIAL CT

Include: infrastructure table, spec status, known tasks, key files table.

### Step 4: Phase-gate verification

**Default mode:** Spawn Sonnet subagent via `Agent(model: "sonnet")` with the delegation prompt.

**Duo mode:** MANDATORY SONNET DELEGATION. Agent checks every CT claim against disk. Fix discrepancies immediately.

### Step 5: Present for user approval

Show CT. Announce `/1` complete. Do NOT proceed to `/2` until user approves.

---

## Agent prompt template

```
Read project-specific rules files (design invariants, terminology, etc.).

Read [SPEC_FILE] in full. For each section in your assigned range, run
checks 1-6 below. Write results to [OUTPUT_FILE] using the format at the end.

--- CHECK 1: COUNT AND CATALOG ---
Count discrete items per section. Record exact counts.

--- CHECK 2: INTERNAL CONSISTENCY ---
Flag values/terms appearing in multiple places with different content.
Quote both sides with line numbers.

--- CHECK 3: SOURCE VERIFICATION ---
Every technique, citation must be traceable to primary source.

--- CHECK 4: DESIGN INVARIANTS ---
Check every section against ALL invariants in project rules files.

--- CHECK 5: CROSS-FILE REFERENCES ---
Verify every referenced file path and section name exists.

--- CHECK 6: CODE CROSS-REFERENCES ---
For specs with structured IDs/enums: verify EACH ID exists in code.

--- OUTPUT FORMAT ---
Write to [OUTPUT_FILE]:
  ## [Section Name]
  Items counted: N
  Contradictions: [list or "none"]
  Source issues: [list or "none"]
  Invariant violations: [list or "none"]
  Cross-file issues: [list or "none"]
  Code mismatches: [list or "none"]
```
