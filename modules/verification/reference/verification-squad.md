## Verification Squad

**Trigger:** Before ANY completion claim. Squad is the **default** — you must actively qualify for an exemption to skip it. If unsure, run it.

### The Five Agents

Launch all 5 in parallel (`run_in_background: true`). Write to `squad_opus/` or `squad_sonnet/` (per session-bound dirs rule below).

| Agent | File | What It Catches |
|---|---|---|
| Mechanical Auditor | `mechanical.md` | Wrong file paths, constants, enum values, counts, **API signatures** — anything greppable against disk |
| Adversarial Reader | `adversarial.md` | **Spec sanity (hallucinated content)**, contradictions, rule violations, impossible instructions, charity bias |
| Completeness Scanner | `completeness.md` | Missing requirements, unassigned items, spec gaps. **Sequential batches of 7 for >20 items.** |
| Dependency Tracer | `dependency.md` | **Missing migrations, silent default changes, untraced call sites** — every change traced one level out |
| Cold Reader | `cold_reader.md` | **Semantic errors invisible to the author** — nonsense, broken/dead instructions, orphaned context, stale language. Reads with zero intent knowledge. |

Each agent MUST end with `VERDICT: PASS` or `VERDICT: FAIL` + issue count.

### Rules

1. **All 5 must PASS** before claiming completion. Any FAIL → fix issues → re-run only the failed agent(s).
2. **Max 3 rounds.** Initial run + 2 re-runs. If any agent still FAILs after round 3: stop fixing. Delete the squad directory. Write remaining issues to CURRENT_TASK.md with `VERIFICATION_BLOCKED` marker and present to user with the list of unresolved issues and recommended actions. Do not attempt further autonomous fixes — remaining issues likely require design judgment.
3. **After all 5 PASS:** Write `VERIFICATION_PASSED` + one-line summary to CURRENT_TASK.md. Note: this is documentation only — hooks do NOT accept it as enforcement evidence. Only actual squad files satisfy the commit gate.
4. **Squad files are ephemeral.** Gitignored. The commit hook cleans only COMPLETED squad directories (all 5 files with VERDICT: PASS) after successful commit. In-progress or failed directories from other sessions are left untouched.
5. **Replaces ad-hoc verification.** No extra agents unless Squad flags areas needing deeper investigation.
6. **Hook-enforced.** The commit hook blocks non-exempt commits without 5/5 PASS in `squad_*/`. Use `--skip-squad` for WIP only.
7. **Session-bound dirs.** `squad_opus/` or `squad_sonnet/` — no default `squad/`.
8. **Source spec rule.** Completeness Scanner SOURCE_SPEC = authoritative spec or user request, never just CURRENT_TASK.md.

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
- **SQUAD_DIR**: `squad_opus/` or `squad_sonnet/`. Channeled: `squad_chN_opus/` or `squad_chN_sonnet/`. Replace in all prompts below. The commit hook cleans on all-PASS commit.

---

## Agent 1: Mechanical Auditor

Output: `verification_findings/SQUAD_DIR/mechanical.md`

```
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
   - Line refs: Read file at that line.
   - **Method/API calls: find the DEFINITION** (not usage). Verify parameters (names, types, count), return type. External libs: context7 MCP or grep `.pub-cache/`.
   - **Enum/constant values: verify actual value**, not just name exists. Count members. Read definitions.

4. Mark: `[V]` VERIFIED, `[X]` UNVERIFIED (searched: [where], closest: [match]), `[~]` APPROXIMATE (differs how).

5. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | FAIL (N issues)
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

### VP Methods

**M4 — String-literal exact match:**
- Every key, label, identifier copied from definition to usage must match character by character
- Use programmatic search (Grep), not visual comparison
- Check: enum member names, constant values, file path strings, JSON keys

**M8 — Quality gate (pattern migration):**
- Find ALL instances of old patterns within affected scope
- Verify every instance updated — not just the ones the work product mentions
- Check implementation matches surrounding code style (naming, structure, error handling)

**Step 10 — Pre-commit diff scan (step numbers reference `.claude/reference/spec-verification.md`):**
- Review staged changes for out-of-scope file modifications
- Flag any file changed that is not mentioned in the work product or task scope

**Step 5 — Invariant grep:**
- Check project rules files (`.claude/rules/design-invariants.md`, terminology, etc.) if they exist
- Grep changes against any project-specific invariants

**Two-layer verification:** After finding issues, challenge each one. Is this a real violation or a false positive? Discard false positives before reporting. Only genuine issues count toward VERDICT.

VERDICT is PASS only if Issues = 0. `[X]` (unverified) = FAIL. `[~]` (approximate) = FAIL if the difference is material (wrong count, wrong type); PASS if cosmetic (e.g., formatting difference). State reasoning for each `[~]`.
```

---

## Agent 2: Adversarial Reader

Output: `verification_findings/SQUAD_DIR/adversarial.md`

```
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

4. Check CONTRADICTIONS: instruction A makes B impossible? Pre-verified fact contradicts later task? Two agents writing same file? X in one place, NOT-X in another?

5. Check RULE VIOLATIONS: design invariants, terminology, operational procedures.

6. Check IMPOSSIBLE INSTRUCTIONS: nonexistent APIs (grep), agent type lacking capabilities, circular dependencies, instructions requiring unstated context.

7. Check CHARITY BIAS: vague instructions sounding complete, "verify" without what/how, "update" without file/field/value, "handle edge cases" without listing them.

8. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | FAIL (N issues)
Work product: [path]

## Summary (parent reads THIS section only)
1. [CATEGORY] One-line — file:line or rule
Categories: [SPEC_SANITY], [CONTRADICTION], [RULE_VIOLATION], [IMPOSSIBLE], [CHARITY_BIAS]

---
## Detail (parent reads ONLY for judgment on specific finding)

### Finding 1: [title]
Category, full evidence, rule file:specific rule cited (if applicable)

### Finding 2: [title]
...
```

### VP Methods

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

**Failure modes to watch (VP Appendix B):**
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

4. Scan for ORPHANED ITEMS: TODO/TBD/"deferred" without owner, agent tasks without output paths, steps referencing unspecified input file paths.

5. Reverse check: work product items NOT in spec → `[U]` UNSPECIFIED (flag, don't FAIL).

6. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | FAIL (N issues)
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

### VP Methods

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
VERDICT: PASS | FAIL (N issues)
Work product: [path] | Changes traced: N

## Summary (parent reads THIS section only)
1. [UNTRACED] One-line — specific risk
Categories: [UNTRACED], [UNCERTAIN]

---
## Detail (parent reads ONLY for judgment on specific finding)
### Finding 1: [title]
Change, upstream/downstream/lateral trace, specific risk (what breaks, how, when)
```

### VP Methods

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
Read the work product AS IF YOU HAVE NEVER SEEN IT BEFORE with ZERO KNOWLEDGE of intent. You are the most important agent — the only one that reads cold. The other four verify with knowledge of intent.

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

5. **ONLY AFTER steps 1-4:** Read spec (if provided). Flag every gap between "what it says" and "what it should say."

6. Write via atomic protocol: `.tmp` then `mv -f` to final path.

```
VERDICT: PASS | FAIL (N issues)
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

VERDICT is PASS only if Total issues = 0.
```

---

## After All Five Complete

1. Read all 5 output files
2. If ALL PASS: write `VERIFICATION_PASSED` + one-line summary to CURRENT_TASK.md (documentation only — hooks do NOT accept this as enforcement evidence; only the actual squad files satisfy the commit gate)
3. If ANY FAIL: fix the issues, then re-run ONLY the failed agent(s)
4. Squad files (e.g., `squad_opus/`, `squad_sonnet/`, `squad_chN_sonnet/`) are cleaned up automatically by the commit hook after a successful commit
