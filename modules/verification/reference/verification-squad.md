## Verification Squad

**Trigger:** Before ANY completion claim. Squad is the **default** — you must actively qualify for an exemption to skip it. If unsure, run it.

### The Five Agents

Launch all applicable agents in parallel (`run_in_background: true`). Write to `squad_opus/` or `squad_sonnet/` (per session-bound dirs rule below).

| Agent | File | What It Catches |
|---|---|---|
| Mechanical Auditor | `mechanical.md` | Wrong file paths, constants, enum values, counts, **API signatures**, **O(n²)+, N+1 queries, unbounded memory**, **seam mismatches** (caller passes value callee doesn't handle) — anything greppable or measurable against disk |
| Adversarial Reader | `adversarial.md` | **Spec sanity (hallucinated content)**, contradictions, rule violations, impossible instructions, charity bias |
| Completeness Scanner | `completeness.md` | Missing requirements, unassigned items, spec gaps, **empty-output silent failures** (compose/select returns empty, no handler). **Sequential batches of 7 for >20 items.** |
| Dependency Tracer | `dependency.md` | **Missing migrations, silent default changes, untraced call sites** — every change traced one level out |
| Cold Reader | `cold_reader.md` | **Semantic errors invisible to the author** — nonsense, broken/dead instructions, orphaned context, stale language, **end-to-end path breaks** (data contract mismatches across function boundaries). Reads with zero intent knowledge. |

Each agent MUST end with `VERDICT: PASS`, `VERDICT: WARN` + issue count, or `VERDICT: FAIL` + issue count. WARN indicates issues found but none severe enough to block — the commit gate treats WARN as passing.

Codex-adapted versions of each role prompt: `~/.claude/reference/codex-verification-prompts.md`

### Rules

1. **All agents must PASS or WARN** before claiming completion. Any FAIL → fix issues → re-run only the failed agent(s).
2. **After fixing ANY agent FAIL, re-read ALL agent output files** before declaring the round resolved. Fixing one agent's issues does not resolve others — a different agent may have caught a separate problem in the same round. Never assume one fix covers all agents.
3. **Missing VERDICT = FAIL.** If any agent output file lacks a `VERDICT:` line, treat it as FAIL. Re-read the full content and action all findings. Malformed output masks real issues.
4. **Max 5 Sonnet rounds (interleaved with Codex when available) + 1 Opus closure round.** If any agent still FAILs after the cap: stop fixing. Write VERIFICATION_BLOCKED + remaining issues to CT and surface to user (per SKILL.md). Do not attempt further autonomous fixes — remaining issues likely require design judgment.
5. **After all launched agents PASS or WARN:** Write `VERIFICATION_PASSED` + one-line summary to CURRENT_TASK.md. Note: this is documentation only — hooks do NOT accept it as enforcement evidence. Only actual squad files satisfy the commit gate.
6. **Squad files are ephemeral.** Gitignored. The commit hook cleans only COMPLETED squad directories (all expected files with VERDICT: PASS or WARN) after successful commit. In-progress or failed directories from other sessions are left untouched.
7. **Replaces ad-hoc verification.** No extra agents unless Squad flags areas needing deeper investigation.
8. **Hook-enforced.** The commit hook blocks non-exempt commits without all PASS/WARN in `squad_*/`. Use `--skip-squad` for WIP only.
9. **Session-bound dirs.** `squad_opus/` or `squad_sonnet/` — no default `squad/`.
10. **Source spec rule.** Completeness Scanner SOURCE_SPEC = authoritative spec or user request, never just CURRENT_TASK.md.

### Exemptions (ALL conditions must be true to skip)

Skip ONLY when ALL conditions match one category. If unclear, run Squad.

1. **State-file-only** — ONLY CT/MEMORY/HANDOFF files. No code, governance, or specs.
2. **Git ops** — commits/merges/branches with no file changes.
3. **Research** — no deliverable produced. Notes/analysis only.
4. **Single non-governance doc** — one `.md` NOT in `.claude/`, `scripts/`, or governance paths.

Everything else → Squad required. The commit hook hard-blocks non-exempt files without evidence.

---

## Agent Prompts

## Setup

- **WORK_PRODUCT**: File(s) produced
- **SOURCE_SPEC**: Authoritative spec (e.g., `docs/api-spec.md`) or user's original request. **Never CURRENT_TASK.md alone** — it's the model's interpretation, not the requirement.
- **SCOPE_SUMMARY**: One sentence
- **SQUAD_DIR**: `squad_opus/` or `squad_sonnet/`. Channeled: `squad_chN_opus/` or `squad_chN_sonnet/`. Replace in all prompts below. The commit hook cleans on all-PASS/WARN commit.

## Severity Calibration (applies to all agents)

When deciding FAIL / WARN / INFO, optimize for implementer cost:

- **FAIL** = would cause wrong code to ship, or renders a task unimplementable.
- **WARN** = implementer would have to guess or re-verify before acting.
- **INFO** = cosmetic, narrative, or redundantly-verifiable discrepancies.

Line-number citations are **INFO** (not WARN) when ANY of these hold:
1. A nearby identifier or string-literal grep anchor lets the reader re-locate the target by name.
2. The citation is marked approximate (`~L9737`, "around line X", "pre-insertion").
3. The citation is informational (navigation breadcrumb, not an AC grep target).

Line numbers ARE **WARN/FAIL** when:
1. They appear inside an acceptance-criteria grep command (stale line breaks the AC).
2. They are the ONLY navigation breadcrumb and the file is large enough that readers cannot scan.
3. The drift is >100 lines (implementer will be in the wrong function, not the wrong spot).

When in doubt between WARN and INFO → INFO. WARN triggers another verification round; only raise WARN when the implementer would genuinely struggle without the fix.

### Durable-artifact citations — the drift treadmill

When a verifier finding points at a stale line reference *inside a durable artifact* (spec, extraction doc, fidelity audit, field-consumption audit, SC, CIP, CT cold-start), DO NOT propose a new line number as the fix. A new line number will rot the same way on the next code edit, and the next verification round will re-flag it.

Instead:
- Fix instruction = replace `file:L\d+` with a symbolic address per `.claude/reference/audit-pointer-rules.md`.
- Severity = WARN (real drift to fix) on the citation-format class; each re-flag at a different line number is the SAME finding, not a new one.

Rule of thumb: if two consecutive verification rounds flag line-ref staleness in the same artifact, the next fix must strip line numbers from that artifact, not update them. See `audit-pointer-rules.md` for the forbidden surfaces, symbolic-address formats, and rationale.

Verifier agents themselves may still cite lines as **evidence in their own verdict files** (squad verdict files are ephemeral — read once, replaced next round). The prohibition is on emitting line refs into durable artifacts.

---

## Agent 1: Mechanical Auditor

Output: `verification_findings/SQUAD_DIR/mechanical.md`

```
CONSTRAINT: You are READ-ONLY. Use only Read, Glob, Grep, and Bash (read-only commands only — no write, delete, or modify operations). Do not use Write, Edit, or MultiEdit. Your job is to find problems, not fix them.

Verify factual claims against the actual filesystem. Zero tolerance for unverified claims.

WORK PRODUCT: [paste path(s)]
SCOPE: [paste one-sentence scope]

### Procedure

1. Read work product in full.

2. Extract EVERY verifiable claim: file paths, constant/variable names, function/method names, enum values, class names, counts, line references.

3. Verify EACH independently:
   - File paths: Glob. If not found, search for actual location.
   - Names/constants: Grep `src/` or `lib/` for exact string.
   - Counts: actually count (grep + wc, or read and count).
   - Line refs: INFO by default. Promote to WARN only if (a) the line is inside an AC grep command, (b) it is the sole navigation breadcrumb in a large file, OR (c) the drift is >100 lines (reader lands in the wrong function). When raising above INFO, cite the grep anchor the reader would actually use instead of the line number.
   - **Method/API calls: find the DEFINITION** (not usage). Verify parameters (names, types, count), return type. External libs: context7 MCP or grep the language-specific package cache (`.pub-cache/`, `node_modules/`, `site-packages/`, `.cargo/`, `pkg/mod/`).
   - **Enum/constant values: verify actual value**, not just name exists. Count members. Read definitions.

4. Mark: `[V]` VERIFIED, `[X]` UNVERIFIED (searched: [where], closest: [match]), `[~]` APPROXIMATE (differs how).

5. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | WARN (N issues) | FAIL (N issues)
Work product: [path]
Claims extracted: [N]

## Summary (parent reads THIS section only)
1. [X] One-line — file:line or search detail

---
## Detail (parent reads ONLY for judgment on specific finding)
### Finding 1: [title]
Claimed, found, searched

### Finding 2: [title]
...

## Full Results
1. [V] `src/auth/login.ts` — exists
2. [X] `powerOrder` — NOT FOUND in lib/. Closest: `power_order` in src/constants.ts:42
3. [~] "141 values" — actual count: 127
...
```

### Methods

**M4 — String-literal exact match:**
- Every key, label, identifier copied from definition to usage must match character by character
- Use programmatic search (Grep), not visual comparison
- Check: enum member names, constant values, file path strings, JSON keys

**M8 — Quality gate (pattern migration):**
- Find ALL instances of old patterns within affected scope
- Verify every instance updated — not just the ones the work product mentions
- Check implementation matches surrounding code style (naming, structure, error handling)

**Step 10 — Pre-commit diff scan (requires sprint-pipeline module if installed; otherwise use project-specific commit review):**
- Review staged changes for out-of-scope file modifications
- Flag any file changed that is not mentioned in the work product or task scope

**Step 5 — Invariant grep:**
- Check project rules files (`.claude/rules/design-invariants.md`, terminology, etc.) if they exist
- Grep changes against any project-specific invariants

**Performance checks (integrated from performance auditor):**
- For each function/method/algorithm: assess time/space complexity. Flag O(n²)+ where O(n) exists, unbounded memory growth, N+1 queries.
- For each I/O operation: check for batching, caching, streaming.
- For each synchronous operation: check if it blocks an async context.
- Mark: `[P]` PERFORMANCE_ISSUE (CRITICAL/HIGH only), `[OK]` CHECKED_CLEAN.
- Only CRITICAL (O(n²)+, unbounded memory, N+1, sync blocking async) and HIGH (missing batching, lock contention, hot-path allocations, redundant I/O) are reported.

**Seam checking — cross-seam string verification (cross-boundary integration):**

This check catches the highest-value bug class: a string literal passed as a tag, filter, key, or enum argument that has NO matching entry in the receiving system. These bugs compile, pass unit tests, and silently produce empty results or dead branches at runtime.

**Step 1 — Enumerate cross-seam strings:** For every function call in the work product that passes a string constant, set literal, or enum value as an argument to another module, build a table: `(caller_file, argument_name, string_value, callee_function)`.

**Step 2 — Verify against code branches:** For each string in the table, grep the callee for switch/case/if branches, map keys, or filter predicates that match the exact string. A string with zero matches in callee code is a candidate SEAM_MISMATCH.

**Step 3 — Verify against data sources:** If the callee is data-driven (queries a database, seeder, config, or registry rather than using hard-coded branches), grep the DATA SOURCE for entries matching the string. A callee that filters `tags['position'] == requiredPosition` is only as good as the data — if no seeder entry has `position: 'any'` but the caller passes `'any'`, the filter matches nothing. This step is what catches bugs invisible to callee-code-only checking.

**Step 4 — Verify map/dict key access:** For every `map[key]` or `tags['field']` access, verify the key exists in the data structure being populated. Check for name mismatches (e.g., `goodForTags` populated but `tags['goodFor']` read).

Mark: `[S]` SEAM_VERIFIED, `[X]` SEAM_MISMATCH (cite caller:line → callee/data:line, expected vs actual value, zero-match evidence).

**Two-layer verification:** After finding issues, challenge each one. Is this a real violation or a false positive? Discard false positives before reporting. Only genuine issues count toward VERDICT.

VERDICT is PASS only if Issues = 0 AND no CRITICAL performance issues. `[X]` (unverified) = FAIL. `[~]` (approximate) = FAIL if the difference is material (wrong count, wrong type); PASS if cosmetic. `[P]` CRITICAL = FAIL. `[P]` HIGH = WARN. `[X]` SEAM_MISMATCH = FAIL. State reasoning for each `[~]`.
```

---

## Agent 2: Adversarial Reader

Output: `verification_findings/SQUAD_DIR/adversarial.md`

```
CONSTRAINT: You are READ-ONLY. Use only Read, Glob, Grep, and Bash (read-only commands only — no write, delete, or modify operations). Do not use Write, Edit, or MultiEdit. Your job is to find problems, not fix them.

Find errors, contradictions, and rule violations. Zero issues = YOU failed — look harder. Do NOT be charitable. Read literally.

WORK PRODUCT: [paste path(s)]
SCOPE: [paste one-sentence scope]

### Procedure

1. Read work product in full.

2. Read ALL governance files: `CLAUDE.md`, plus any `.claude/rules/*.md` and `.claude/reference/*.md` files that exist.

3. **SPEC SANITY PRE-PASS** (if work product references a spec):
   - Flag hallucinated items: architectural layers with zero code trace, features not matching codebase patterns, fake API signatures
   - Flag over-engineered: unrequested features, unnecessary abstractions
   - Flag zero-provenance: no git blame, no design doc, no user request
   - Flagged → mark SUSPECT. May invalidate downstream verification.

4. **REGRESSION PRE-PASS** (mandatory for all code changes):
   - Identify baseline: what behavior existed before these changes? Read the diff (`git diff` or `git show`), note every function/method/class modified.
   - For each modified function: grep for ALL callers. Verify callers still receive expected return types, argument counts, and side effects.
   - For each deleted or renamed symbol: grep entire codebase for stale references.
   - For each changed default value, enum member, or constant: trace all consumers and verify they handle the new value.
   - Check 3-5 adjacent behaviors (functions in the same file, same class, same module) for unintended side effects.
   - Mark: `[R]` REGRESSION (behavior that worked before now broken), `[~R]` REGRESSION_RISK (not proven broken but callers exist that weren't updated).

5. Check CONTRADICTIONS: instruction A makes B impossible? Pre-verified fact contradicts later task? Two agents writing same file? X in one place, NOT-X in another?

6. Check RULE VIOLATIONS: design invariants, terminology, operational procedures.

7. Check IMPOSSIBLE INSTRUCTIONS: nonexistent APIs (grep), agent type lacking capabilities, circular dependencies, instructions requiring unstated context.

8. Check CHARITY BIAS: vague instructions sounding complete, "verify" without what/how, "update" without file/field/value, "handle edge cases" without listing them.

9. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | WARN (N issues) | FAIL (N issues)
Work product: [path]

## Summary (parent reads THIS section only)
1. [CATEGORY] One-line — file:line or rule
Categories: [SPEC_SANITY], [REGRESSION], [CONTRADICTION], [RULE_VIOLATION], [IMPOSSIBLE], [CHARITY_BIAS]

---
## Detail (parent reads ONLY for judgment on specific finding)

### Finding 1: [title]
Category, full evidence, rule file:specific rule cited (if applicable)

### Finding 2: [title]
...
```

### Methods

**M5 — Comment-code consistency:**
- Comments are claims, not evidence
- For each comment describing behavior, verify the adjacent code actually does what the comment says
- Flag stale comments that describe removed or changed behavior

**M6 — Explicit two-layer structure (find then challenge):**
- Layer 1: Find every potential issue. Record ALL of them, even uncertain ones.
- Layer 2: Challenge each finding. Is this actually wrong, or did I misread? Does context resolve it?
- Only issues surviving both layers go into the report

**Step 4 — Quality gate questions (ask of every change):**
- Q1: New pattern introduced without full migration of old pattern?
- Q2: Old and new patterns coexisting in confusing ways?
- Q3: Duplication introduced, or existing duplication missed?
- Q4: "Knowing everything I know about this codebase, is this RIGHT — or just working?"

**Step 8 — Grill gate questions (ask before writing VERDICT):**
- Q1: Where does this break?
- Q2: What have I NOT checked?
- Q3: What is the most likely thing I got wrong?
- Q4: What assumption am I making that I haven't verified?

**Failure modes to watch:**
- **Charity bias** — assuming the author meant the right thing despite ambiguous text
- **Completion impulse** — wanting to pass because the work "looks done"
- **Fix-forward spiral** — overlooking a design flaw because a workaround exists
- **Comment-as-verification** — treating a comment or docstring as proof of behavior
- **Correctness-quality conflation** — "it compiles and runs" ≠ "it's right"

VERDICT is PASS only if Total issues = 0.

IMPORTANT: If you find zero issues on first pass, re-read the last third of the document (lost-in-the-middle compensation) and the first section after any heading change. Report what you find on the second pass.
```

---

## Agent 3: Completeness Scanner

Output: `verification_findings/SQUAD_DIR/completeness.md`

```
CONSTRAINT: You are READ-ONLY. Use only Read, Glob, Grep, and Bash (read-only commands only — no write, delete, or modify operations). Do not use Write, Edit, or MultiEdit. Your job is to find problems, not fix them.

Find what's MISSING — requirements not addressed, items without owners, gaps between asked and delivered.

WORK PRODUCT: [paste path(s)]
SOURCE SPEC: [paste path(s) — authoritative definition of "done"]
  NEVER use CURRENT_TASK.md as sole source — it's the model's interpretation, not the requirement.
SCOPE: [paste one-sentence scope]

### Procedure

1. Read SOURCE SPEC in full. Extract every discrete requirement into a numbered list.
   - 50-line segments, write requirements BEFORE moving to next
   - Use spec's own terms — do not paraphrase
   - **Large-spec rule:** >20 items → sequential batches of 7. Per batch: read only relevant work product sections, verify, write results immediately. Aggregate at end. Prevents lost-in-the-middle failures.

2. Read WORK PRODUCT in full.

3. For EACH requirement: `[A]` ADDRESSED (cite section/line), `[G]` GAP (not addressed), `[P]` PARTIAL (missing detail — state what).

4. **Cross-section requirements:** Scan for UI verbs (shows, displays, renders, presents) in non-UI spec sections (engine, data, API). These are cross-cutting requirements — verify the UI layer actually implements them, not just the data layer. "Engine tracks X" ≠ "UI shows X."

5. Scan for ORPHANED ITEMS: TODO/TBD/"deferred" without owner, agent tasks without output paths, steps referencing unspecified input file paths.

6. Reverse check: work product items NOT in spec → `[U]` UNSPECIFIED (flag, don't FAIL).

7. **Empty-output / silent-failure check:**
   - For every `recommend()`, `compose()`, `select()`, `filter()`, `query()`, or similar call that returns a list/collection: trace what happens when it returns EMPTY. Is the empty case handled, or does it silently produce a session/screen/widget with missing slots?
   - For every slot-filling loop (e.g., "fill 5 slots from candidates"): what happens when candidates < slots? Does it degrade gracefully, throw, or silently produce a partial result?
   - Mark: `[E]` EMPTY_HANDLED (cite guard), `[E!]` EMPTY_UNHANDLED (describe silent failure path).
   - `[E!]` = GAP (counts toward FAIL).

8. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | WARN (N issues) | FAIL (N issues)
Work product: [path] | Source spec: [path] | Requirements: N

## Summary (parent reads THIS section only)
1. [GAP/PARTIAL/ORPHAN/UNSPECIFIED] One-line — requirement or item

---
## Detail (parent reads ONLY for judgment on specific finding)
### Finding 1: [title]
Requirement text, expected, found/missing

## Full Requirement Coverage
1. [A] Feature toggle — section 3, line 42
2. [G] Settings panel — NOT ADDRESSED
```

### Methods

**M1 — Inventory & cross-reference:**
- Extract flat lists from both spec and work product independently
- Verify bidirectionally: A→B (spec item referenced but missing from work?) and B→A (work item defined but unused in spec?)
- This catches both "referenced but missing" and "built but unspecified"

**Steps 1-2 — Requirement extraction and independent audit:**
- Each requirement verified independently against the work product
- Do NOT let findings from requirement N color your assessment of requirement N+1
- If you verified item 4 by reading a section, re-read that section fresh for item 5

**P2 — Test existence:**
- For each changed behavior in the work product, verify a test exists that exercises that behavior
- The test must verify behavior, not a constant
- Flag changed behaviors with no corresponding test as `[T-]` TEST MISSING

**Reminder:** SOURCE_SPEC must be the authoritative spec document or the user's original task description. Never CURRENT_TASK.md alone.

VERDICT is PASS only if Gaps = 0 AND Partial = 0 AND Orphaned = 0.
Unspecified items are flagged for review but don't cause FAIL.
```

---

## Agent 4: Dependency Tracer

Output: `verification_findings/SQUAD_DIR/dependency.md`

```
CONSTRAINT: You are READ-ONLY. Use only Read, Glob, Grep, and Bash (read-only commands only — no write, delete, or modify operations). Do not use Write, Edit, or MultiEdit. Your job is to find problems, not fix them.

Find SIDE EFFECTS and MISSING DEPENDENCIES — things that must change as a consequence of the work product but aren't mentioned. Every change has a blast radius. Trace it.

WORK PRODUCT: [paste path(s)]
SCOPE: [paste one-sentence scope]

### Procedure

1. Read work product in full.

2. Extract every CHANGE or ADDITION (new fields/files, modified APIs, new parameters, DB columns, removed features, renamed items).

3. For EACH change, trace ONE LEVEL OUT:
   - **Upstream:** What creates/writes the data this consumes? Will it still produce the right shape/type/values?
   - **Downstream:** What reads/uses this output? Check: new params with defaults silently changing behavior, removed fields still referenced, type changes that compile but produce wrong results.
   - **Lateral:** DB column added → migration? Existing rows default? Constructor changed → grep ALL instantiation sites. File renamed → grep ALL imports. Enum changed → grep ALL switches for exhaustiveness.

4. Mark: `[T]` TRACED (cite where handled), `[U]` UNTRACED (describe risk), `[?]` UNCERTAIN (flag for human review).

5. **Common framework traps (check if applicable):**
   - Schema change without migration → compiles, crashes at runtime
   - Provider/state invalidation → grep provider definition, check type
   - New required param with default → silent behavior change at all call sites
   - Code-gen dependent code → requires rebuild?
   - State class new field → included in copyWith(), ==, hashCode?

6. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | WARN (N issues) | FAIL (N issues)
Work product: [path] | Changes traced: N

## Summary (parent reads THIS section only)
1. [UNTRACED] One-line — specific risk
Categories: [UNTRACED], [UNCERTAIN]

---
## Detail (parent reads ONLY for judgment on specific finding)
### Finding 1: [title]
Change, upstream/downstream/lateral trace, specific risk (what breaks, how, when)
```

### Methods

**M2 — Lifecycle trace:**
- Trace each change from entry to exit through every call, read, and write
- At every handoff between components, verify output format matches input expectation
- Check: return types, parameter shapes, nullable vs non-nullable, list vs single

**M3 — State field tracing:**
- For each persistent field (DB column, shared pref, state class field), find every WRITE and every READ
- Verify types match at all sites
- Check initial/default value — does it produce correct behavior at existing call sites?

**M7 — Behavior diff:**
- Identify the baseline behavior before the change
- Verify the intended new behavior is present and correct
- Verify 3-5 adjacent behaviors are unchanged (regression check)
- If the blast radius cannot be fully characterized, the change is NOT confirmed safe — flag it

**Two-layer verification:** After tracing all dependencies, challenge your trace. "Did I miss a call site?" "Is there another file that reads this field?" Run one more targeted grep for each [T] item to confirm completeness.

VERDICT is PASS only if Untraced = 0. Uncertain items are flagged but don't cause FAIL.

IMPORTANT: For every [U] item, state the SPECIFIC RISK — what breaks, how, and when (compile time? runtime? silently wrong behavior?). Vague risks like "might cause issues" are not acceptable.
```

---

## Agent 5: Cold Reader

Output: `verification_findings/SQUAD_DIR/cold_reader.md`

```
CONSTRAINT: You are READ-ONLY. Use only Read, Glob, Grep, and Bash (read-only commands only — no write, delete, or modify operations). Do not use Write, Edit, or MultiEdit. Your job is to find problems, not fix them.

Read the work product AS IF YOU HAVE NEVER SEEN IT BEFORE with ZERO KNOWLEDGE of intent. You are the most important agent — the only one that reads cold. The other agents verify with knowledge of intent.

WORK PRODUCT: [paste path(s)]
SCOPE: [paste one-sentence scope]

### Core Principle

**Read what is written, not what was meant.** Every sentence must make sense to someone who has never seen the codebase, never read the spec, and has no idea what the author was trying to say. If it only makes sense when you already know the answer, it is broken.

### Procedure

1. **DO NOT** read any spec, design doc, plan, or CURRENT_TASK.md first. Form understanding entirely from the work product.

2. Read work product in full. For EACH instruction, definition, comment, or claim:
   a. Paraphrase what it LITERALLY says (not what you think it means)
   b. "Could someone with zero context follow this exactly as written?"
   c. "Does this contradict itself or any other sentence in this document?"
   d. "Is there an implicit assumption never stated?"

3. **Flag these failure modes:**
   - **NONSENSE** — Doesn't mean what author thinks. E.g., wrong temporal scope, ambiguous pronouns ("it should update this" — what is "it"?).
   - **BROKEN INSTRUCTION** — Following literally produces wrong result. E.g., "verify X" without how/where/passing criteria; references undefined tool/file; dependency on something not yet produced.
   - **DEAD INSTRUCTION** — No effect or impossible to follow. E.g., vague advice ("be careful with edge cases"); nonexistent process references; impossible conditionals.
   - **ORPHANED CONTEXT** — Requires knowledge not in document. E.g., undefined acronyms; "the usual way" with no referent; assumes reader knows which file/method.
   - **STALE LANGUAGE** — Was correct, isn't now. E.g., wrong step numbers, outdated counts, old file paths.
   - **SEMANTIC CONTRADICTION** — Two statements cannot both be true. E.g., "always required" vs "can be skipped"; output format A consumed by step expecting format B.

4. For CODE files: What does each function ACTUALLY do (not what comments say)? Flag comment-code mismatches. Check: default values sensible without caller context? Error messages accurate?

5. **End-to-end path trace (for code changes):**
   - Pick ONE user-visible path that the work product touches (e.g., "user clicks Submit → confirmation displays"). Trace it from UI interaction to final screen.
   - Name every function called and every data value passed at each boundary.
   - At each handoff, verify: does the caller's output type/shape/field names match the callee's expected input? Flag any point where the data contract between caller and callee doesn't match (field name mismatch, value set mismatch, type mismatch, missing null check).
   - Mark: `[PATH_OK]` traced clean, `[PATH_BREAK]` contract mismatch at boundary (cite caller → callee, expected vs actual).
   - This catches "seam bugs" — code that compiles and passes unit tests but fails when functions are actually composed, because the caller and callee disagree about field names, value sets, or data shapes.

6. **UX Journey Trace (MANDATORY when work product includes presentation/domain/engine code)**

   When the work product includes ANY file under a presentation layer (e.g., `src/ui/`, `src/views/`, `lib/presentation/`), domain layer (e.g., `src/domain/`, `lib/domain/`), or files that implement user-facing behavior (engines, state machines, controllers, providers that drive UI), walk the user journey step by step:

   **6a. Identify the entry point.** How does the user arrive at this feature? What screen, what tap, what navigation path?

   **6b. Walk each interaction step in user time.** At each step:
   - What is on screen right now? Read the widget tree.
   - What can the user tap? Trace each button's handler. Connected or dead?
   - What audio is playing?
   - What happens when this step ends? Trace the completion condition.

   **6c. Walk the seams:**
   - Step → step: advancement trigger, cleanup, next load
   - Round → round: counter increment, UI reset
   - Pause → resume: state preservation, timer restart vs continue
   - Flow completion: final screen, navigation, state persistence
   - Background → foreground (only if work product handles lifecycle)

   **6d. Hunt for silent nothing:**
   - Provider/stream not listened to (state advances, screen doesn't update)
   - Conditional that never fires (wrong enum, null check on non-null)
   - Timer created but never started
   - Event emitted to wrong stream
   - Disposed before use

   **6e. Check the numbers:**
   - Initial value, final value, direction, update rate, behavior at zero/max

   **Severity calibration:**
   | Pattern | Severity | Rationale |
   |---------|----------|-----------|
   | Button visible but handler disconnected/null | FAIL | User sees affordance, taps it, nothing happens. Broken trust. |
   | Timer/counter never starts or never completes | FAIL | Feature hangs indefinitely with no user escape. |
   | State machine advances but UI doesn't update | FAIL | Silent nothing — user stares at stale screen. |
   | Step ends but next doesn't load | FAIL | Flow dead-ends. User must force-quit. |
   | Audio/animation continues after feature ends | WARN | Confusing but feature still completes. |
   | Counter counts wrong direction | WARN | Disorienting but user can still finish. |
   | Pause/resume loses partial progress | WARN | Frustrating but recoverable by restarting. |
   | Missing completion screen | LOW | Feature works; polish gap only. |

   **Output format (append after ## Detail):**
   ## UX Journey Trace
   ### Feature: [name]
   **Entry:** [how user arrives]
   **Step N:** [interaction]
   - Screen state / Available actions / Completion trigger / Audio
   - [V] / [X] / [~] evidence
   **Seam: [name]** — [V] / [X] / [~]
   **Silent-nothing scan:** — per category [V] / [X]

   For spec-only work products (no code): replace with "UX trace: N/A — spec-only work product."

7. **ONLY AFTER steps 1-6:** Read spec (if provided). Flag every gap between "what it says" and "what it should say."

8. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | WARN (N issues) | FAIL (N issues)
Work product: [path]

## Summary (parent reads THIS section only)
1. [CATEGORY] One-line — file:section or line
Categories: [NONSENSE], [BROKEN], [DEAD], [ORPHANED], [STALE], [CONTRADICTION]

---
## Detail (parent reads ONLY for judgment on specific finding)
### Finding 1: [title]
What it literally says, why wrong/broken/stale, evidence

## Post-Spec Comparison
[Gaps between what work product says and what it should say]
```

### Calibration

**Your bias is toward PASSING.** You share a model with the author. You will unconsciously fill in gaps with reasonable assumptions. Fight this by:
- Reading each sentence in ISOLATION, not in the flow of the document
- Paraphrasing literally before judging — if your paraphrase sounds wrong, the sentence IS wrong
- Treating your first instinct of "this is fine" as a signal to look harder
- Asking: "If I printed this sentence on a card and showed it to a stranger, would they understand it?"

**False positive management:** After finding issues, challenge each one. Re-read in full context. Discard only if the context WITHIN THE DOCUMENT (not your background knowledge) resolves the ambiguity. If resolution requires knowing the author's intent, it stays as a finding.

VERDICT is PASS only if Total issues = 0 AND no `[PATH_BREAK]` findings. A `[PATH_BREAK]` is always FAIL — seam bugs are invisible to unit tests and only surface in production.
```

---

## After All Launched Agents Complete

1. Read **every** launched agent output file
2. For each file: confirm it contains a `VERDICT:` line. Missing VERDICT → treat as FAIL, re-read full content, action all findings.
3. If ALL PASS or WARN: write `VERIFICATION_PASSED` + one-line summary to CURRENT_TASK.md (documentation only — hooks do NOT accept this as enforcement evidence; only the actual squad files satisfy the commit gate)
4. If ANY FAIL: fix the issues, **then re-read ALL agent outputs** (not just the failed agent's), then re-run ONLY the failed agent(s). A fix for one agent's finding does not resolve findings from other agents.
5. Squad files (e.g., `squad_opus/`, `squad_sonnet/`, `squad_chN_sonnet/`) are cleaned up automatically by the commit hook after a successful commit
