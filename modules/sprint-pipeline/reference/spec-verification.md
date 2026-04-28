## Source-Spec-Code Fidelity Verification

**Trigger:** `/perfect` (/4), Phase 2.5. Before claiming any screen, module, feature, or sprint is complete.

Verifies that the code actually does what the SOURCE material specifies — not just that the code matches the spec, and not just that the tests pass. Catches three failure classes that pure spec↔code checking misses:

1. **Source-fidelity drift** — spec silently departed from the source; spec↔code verification confirms an incorrect contract.
2. **Declaration-without-consumer** — data layer declares a field or parameter, no runtime component reads it (aspirational/dead fields).
3. **Silent fallback override** — consumer has `?? default` or `|| fallback` that substitutes a value when the expected declaration is absent or named differently; declaration exists in the data layer but never reaches the runtime.

Every failure in this class looks like MATCH from any single-direction check. Only by tracing source → spec → code → consumer, in both directions, do these surface.

---

### Phase 0: Identify the SOURCE materials

The source is the primary material the spec claims to implement: books, research papers, traditional texts, authoritative external documentation, user decisions recorded in transcripts, domain-expert input. A **decisions file** is NOT a source — it is a summary of decisions made when reading sources. A **prior spec version** is NOT a source — it is a work product.

For each section of the spec being verified, identify the corresponding source and record its path. No source → FLAG before proceeding (the spec has drifted off its basis; verify intent with the developer before continuing).

Never substitute a decisions file, a prior CC summary, or a brainstorming doc for the source. Only primary sources count.

### Phase 1: Identify the Authoritative Spec

Find spec section(s) defining "done": relevant spec files, `docs/plans/*.md`, or project planning documents. No spec → flag before proceeding.

### Phase 2: Extract the Flat Checklist — from the SOURCE first, then the SPEC

**2a. Source-side extraction.** Read each source section **in full, start to finish**. Extract every discrete claim, numeric value, procedural step, safety note, ratio, count, duration, or named behavior into a numbered flat list. Record the source file:lines for each item.

**2b. Spec-side extraction.** Repeat for the spec. Same flat-list format.

**2c. Bidirectional cross-reference.**
- Every source item → which spec item implements it? (Missing = spec drift.)
- Every spec item → which source item justifies it? (Missing = spec fabrication.)
- Flag both directions explicitly in the report. Never dismiss either side.

**Anti-lost-in-the-middle rules (apply to BOTH source and spec extraction):**

1. **Read in segments of 50 lines max.** After each segment, write down every item found in that segment before moving to the next. Extraction happens DURING reading, not after.
2. **Use the document's own terms.** Do not paraphrase, summarize, or combine items. Separate claims = separate items.
3. **Count structural elements.** How many UI widgets? Data flows? Conditional behaviors? Numeric constants? These counts become verification targets.
4. **Cross-check against headings.** Re-read ONLY headings, subheadings, and bold text. Does every heading have at least one checklist item? Zero = missed section.
5. **Reverse-scan the last third.** Items in the final third are most likely to be missed. After extraction, re-read the last 30% and verify coverage.
6. **Cross-section verb scan.** Grep for UI verbs (`shows`, `displays`, `renders`, `presents`) in non-UI sections. Each hit = cross-cutting requirement; both sides must be verified independently. "Engine tracks X" ≠ "UI shows X."
7. **Numeric-value scan.** Grep the source for numbers (durations, ratios, counts, seconds, BPM, etc.). Every numeric source claim becomes a verification target — you must produce the corresponding runtime number by tracing code in Phase 3. Unable to trace = FAIL.

Output: numbered flat lists (source + spec) with file:lines and item counts.

### Phase 3: Verify Each Item Against Code — TERMINATING AT THE CONSUMER

For EACH item, independently verify (grep or Read — not from memory).

**Critical rule: verification terminates at the consumer, not the declaration.** "The data model declares `restBetweenRounds`" is NOT verification that the rest is honored. You must grep the consumer (engine, widget, runtime component) for the field name and confirm it is READ and USED.

**Procedure for every item:**

1. **Declaration check.** Grep the data layer for the field/value. Found? Note file:line.
2. **Consumer check.** Grep all runtime components (engines, widgets, services, DAOs) for the same field name. Who reads it? Cite file:line of the READ.
3. **Semantic check.** Does the consumer use the value the way the spec says? A field that is read but thrown into a log = NOT consumed.
4. **Silent-fallback scan.** Grep the consumer for `?? ` and `|| ` and default values near the consumption site. If the consumer has `params['fieldX'] ?? 4`, and no test proves the exercise declares `fieldX`, then the exercise silently gets 4 — FAIL.

Mark each item:
- `[P]` PRESENT — declared AND consumed AND semantically correct. Cite both file:lines.
- `[D]` DECLARED-ONLY — declared but no consumer. Aspirational/dead field. **FAIL.**
- `[F]` FALLBACK — consumer has silent `??`/`||` that would trigger if the declared field is missing/renamed. **FAIL** unless explicit test proves declaration matches the consumer's expected key.
- `[M]` MISSING — not declared at all. **FAIL.**
- `[I]` INCOMPLETE — declared and consumed but semantics drift from spec. **FAIL.**

**Numeric trace rule:** for every numeric source claim, write out the full path: source value N → spec value N → data layer N → consumer's computed runtime N. If you cannot produce the final runtime number by tracing code, mark `[I]` with reason "cannot trace to runtime" — do NOT write `[P]`.

**Comment-vs-behavior rule:** design intent expressed in code comments that the consumer does not implement = `[D]`. A comment saying "rest between rounds honored" while the engine never reads `restBetweenRounds` is an `[D]`, not a `[P]`.

### Phase 4: Reverse Verify (Code → Spec → Source)

Scan implementation for features NOT in spec. For each:
- Is it in the source but missing from the spec? = spec gap, flag.
- Is it in neither? = speculative feature, flag.
- Is it in the spec but removed from code? = regression, flag.

### Phase 4.5: Field-Consumption Audit (one page, every run)

For each data model touched this sprint (ExerciseDefinition, ModuleTemplate, ParameterDef, any config/schema class with declared fields):

1. List every field declared on the model.
2. For each field, grep the entire `lib/` and `test/` tree for reads of that field name.
3. Mark each field:
   - `[C]` CONSUMED — at least one runtime component reads and uses the field. Cite file:line.
   - `[T]` TEST-ONLY — only tests read the field. **FAIL** (field does nothing in production).
   - `[D]` DEAD — no reads anywhere. **FAIL** (declaration without consumer).

Every `[T]` and `[D]` finding goes in the report. Resolution options: (a) wire the field to a consumer, (b) delete the field, (c) explicitly mark it as reserved-schema with a sprint task to wire it. Silent "it's aspirational" is not acceptable.

Output: `verification_findings/field_consumption_audit[_chN].md` with one table per model.

### Phase 5: Report

Include:
- Total source items: N. [P]/[D]/[F]/[M]/[I] counts.
- Total spec items: N. [P]/[D]/[F]/[M]/[I] counts.
- Code-only count (reverse verify).
- Field-consumption audit: per-model table with [C]/[T]/[D] counts.
- Every numeric source value with its full trace to runtime (or `[I]` if untraced).

**VERDICT:**
- **PASS** — all items [P], all fields [C], all numerics traced.
- **FAIL** — any [D], [F], [M], [I], [T] finding, OR any numeric that cannot be traced to runtime.

FAIL = not complete. Implement or explicitly defer with a tracked task before close-out.