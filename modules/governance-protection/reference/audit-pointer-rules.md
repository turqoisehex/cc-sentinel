# Audit & Spec Pointer Rules

**Purpose:** stop line-number drift from multiplying verification rounds.

Line numbers rot. Every code edit shifts them. In artifacts that are re-read across sprint rounds, a `file.dart:L487` citation becomes a false claim the next time anything above line 487 gets touched. Verification agents then flag the false claim, the fix-pass "corrects" the line number, another edit shifts it again, and the cycle repeats. The drift is structural — it is not a code-quality signal.

Fix: durable artifacts reference code by **symbolic address only**. Ephemeral surfaces may use line numbers as usual.

## Where line numbers ARE forbidden (durable artifacts)

These files are re-read across multiple verification rounds and sprints. Line numbers written into them rot between reads:

- `specs/**`
- `docs/**` — especially fidelity, traceability, and extraction subdirectories
- `verification_findings/fidelity_audit*.md`
- `verification_findings/field_consumption_audit*.md`
- `SPRINT_CHECKLIST.md` task items
- `COMPREHENSIVE_IMPLEMENTATION_PLAN.md`
- `CURRENT_TASK*.md` cold-start entries, handoff sections, § cross-references
- Any doc cited by another doc (citations rot together)

## Where line numbers ARE fine (ephemeral surfaces)

These surfaces are read once and discarded, or die with the commit:

- Assistant text in conversation (user navigates by click)
- Tool outputs (Bash, Grep, Read results)
- `verification_findings/squad_*/{mechanical,adversarial,completeness,dependency,cold_reader}.md` "Evidence:" columns (read once per round, replaced next round)
- Commit messages, PR descriptions
- `git blame` / `git log` output

## Symbolic address formats

Prefer the most specific form that resolves uniquely.

| Target | Format | Example |
|---|---|---|
| Top-level symbol | `file.ext :: symbolName` | `routine_engine.dart :: isBreathingModule` |
| Class member | `file.ext :: ClassName.memberName` | `engine.dart :: Engine._advance` |
| Keyed list entry | `file.ext :: ModelName(id: 'x').field` | `exercises.dart :: ExerciseDefinition(id: 'breathing_sitali').parameters.inhaleSeconds` |
| Seeder/registry entry | `file.ext :: _addContent('id')` | `seeder.dart :: _addContent('breathing_bhramari')` |
| Code branch within function | `file :: function :: branch description` | `engine.dart :: _handleTick :: isBreathingModule check` |
| Spec section | `spec.md § N.N Heading` | `api_spec.md § 3.2 Request Format` |
| CT section | `CURRENT_TASK_chN.md § Heading` | `CURRENT_TASK_ch2.md § /1 FOLLOW-UP` |
| SC item | `SPRINT_CHECKLIST.md § Sprint Heading` | `SPRINT_CHECKLIST.md § Sprint 14 Fixes` |
| Comment | `file :: NOTE above symbol` | `engine.dart :: NOTE above _advance` |

Do not include line numbers as "redundant belt-and-suspenders" alongside symbolic addresses — the line number will still rot and create drift. Pick one form, use it alone.

## Writing rule (prospective)

When any agent writes to a file in the "durable artifacts" list above:

- Emit symbolic addresses.
- Do not emit `file:L\d+`, `L\d+-L\d+`, `line N`, `around line N`, `~LN` forms.
- Quote verbatim snippets where locality matters — the quote is self-locating via grep.

## Retroactive rule (when touching existing docs)

Opportunistic strip: if you are editing a section of a durable artifact that contains `:L\d+` or `L\d+` refs, convert them to symbolic form in the same edit. Do not launch a dedicated strip sprint — cost exceeds value.

## Verifier agents

Mechanical, adversarial, dependency, and cold-reader agents may still cite `file:line` as **evidence in their own verdict files** (those files are ephemeral — read once, replaced next round). But when an agent's *fix instruction* targets a durable artifact, the fix must specify a symbolic address, not a new line number.

Example — WRONG:

> Finding: `fidelity_audit_ch3.md` cites `breathwork_exercises.dart:L487` — actual L438.
> Fix: change `L487` to `L438`.

Example — CORRECT:

> Finding: `fidelity_audit_ch3.md` cites `breathwork_exercises.dart:L487` — this reference rots on every code edit above line 487.
> Fix: replace with `breathwork_exercises.dart :: ExerciseDefinition(id: 'breathing_sitali').parameters.inhaleSeconds`.

## Exceptions

None load-bearing. If a situation seems to require a line number, check:

- Is the target a symbol? Use the symbol.
- Is it a specific value inside a block? Use `parent :: field` or `parent :: key.subkey`.
- Is it a comment? Describe the subject (`NOTE above X`) or drop the citation — assert behavior, not comment text.
- Is it a runtime line from a stack trace? That's ephemeral (verdict/evidence) — fine.

## Rationale — why this matters

Observed across long-running projects: 25+ WARN findings across 4 verification rounds were 100% line-drift. Each fix-pass corrected cited line numbers, which moved on the next code edit, which triggered the next verification round to re-flag the same class of issue at different numbers. Rule of thumb: if your R(N+1) squad reports the same finding class at different line numbers than R(N), you are on a drift treadmill. Switching the citation format breaks the cycle structurally.
