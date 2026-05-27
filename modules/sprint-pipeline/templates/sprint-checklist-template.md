<!--
================================================================================
SPRINT_CHECKLIST.md — TEMPLATE

PURPOSE
This file is the project's executable task ledger. It is the source of truth for
"what is done, what is in progress, what is next" at sprint-level granularity.
It is read by the /1 (audit), /2 (build), /3 (execute), /4 (perfect), and
/5 (finalize) skills. Cross-sprint incomplete items live HERE (and in
COMPREHENSIVE_IMPLEMENTATION_PLAN.md), NOT in channel CTs.

WHO READS IT
- The operator, every session start.
- Every cc-sentinel sprint-pipeline skill (/1–/5).
- /verify and /perfect agents looking for acceptance criteria.
- Future-you, six months from now, trying to remember why a sprint was paused.

HOW TO BUILD IT (read once when first creating this file, then delete this block)

1. Anchor on the project's HIGH-LEVEL GOAL. One or two sentences. What is being
   shipped, to whom, at what quality bar, by when (if any). Everything below
   serves that goal — sprints that don't trace back to it are scope creep.

2. Decompose the goal into PHASES. A phase is a multi-sprint band of work that
   shares a coherent theme (foundation, core features, intelligence layer,
   polish, launch). 4–7 phases is typical. Each phase ends at a checkpoint
   where the project could plausibly stop and still have shipped something
   coherent.

3. Within each phase, decompose into SPRINTS. A sprint is a coherent unit of
   work that produces a verifiable, demonstrable outcome — not just "code
   written" but "feature works end-to-end at the agreed quality bar." Sprints
   should be sized so that one sprint fits comfortably in a single sprint-
   pipeline pass (/1 → /2 → /3 → /4 → /5). If a sprint sprawls past that,
   split it (e.g., 14a/14b/14c).

4. For EACH sprint, write CHECKBOXES at the granularity of "a reviewer could
   confirm this is done by looking at the artifact." Not "implement feature X"
   (too vague) and not "edit file Y line 47" (too brittle). Aim for
   "[user-visible behavior] works on [target platform] via [verification
   method]." Group related boxes under subheadings.

5. Add a PRIORITIZATION GUIDE at the top: a small table mapping phase numbers
   to sprint ranges and theme. This is the navigation aid for new sessions.

6. Add MANDATORY OPERATING RULES near the top — anything the project enforces
   that would otherwise drift. Common examples:
   - Sprint ordering (must do N before N+1, or explicitly parallel)
   - Sprint-start procedure (read CIP, scan affected docs, run /1)
   - Sprint-close-out procedure (checkbox audit, quality gate, regression,
     device verification — the "80% trap" prevention)
   - Cross-cutting initiatives that thread through multiple sprints

7. Add a CROSS-CUTTING section for work that doesn't fit one sprint —
   compliance, security, accessibility, performance — naming where it lands
   and what blocks ship until it lands.

8. KEEP IT FLAT. One file, scrollable. Section anchors are fine but resist the
   urge to split into per-sprint files; the value of this document is that
   ONE read gives you the whole project shape.

ENCODING RULES (apply to every line you write below)
- ASCII only by default. If the host project allows Unicode em-dashes, curly
  quotes, etc., declare that explicitly here. Otherwise: -- for em-dash,
  straight quotes, [x]/[ ] for checkboxes.
- No emojis unless the host project's CLAUDE.md explicitly allows them.

MAINTENANCE
- Mark boxes [x] as work lands. Never delete a completed box — the ledger is
  the audit trail. If a box was wrong, strike it through and add a note.
- When a sprint slips, document WHY in the sprint's own section, not buried in
  the CIP. The /5 skill expects to find slip rationale here.
- Sprint numbering is permanent. If sprint 14 splits into 14a/14b post-hoc,
  do not renumber subsequent sprints.

LINK BACK
- This file is paired with COMPREHENSIVE_IMPLEMENTATION_PLAN.md (CIP). SC is
  "what to do." CIP is "the surrounding context that informs decisions." Each
  should reference the other near the top.

When you've absorbed the above, delete this comment block and start filling
in the sections below.
================================================================================
-->

# [PROJECT NAME] — Sprint Checklist

<!-- ENCODING NOTE: ASCII only. Use -- for dashes, straight quotes, [x]/[ ]
for checkboxes. -->

Use this to track progress. Check boxes as you complete tasks.

> **Before proposing next steps or starting a new sprint:** Read
> `COMPREHENSIVE_IMPLEMENTATION_PLAN.md` for critical path, risks, blocking
> dependencies, and decision context. SC is what to do; CIP is the surrounding
> context that informs decisions.

---

## Project Goal

[ONE OR TWO SENTENCES. What is being shipped, to whom, at what quality bar.]

---

## Prioritization Guide

| Phase | Sprint Range | Focus |
|-------|--------------|-------|
| Phase 1: [name] | [N-M] | [theme] |
| Phase 2: [name] | [N-M] | [theme] |
| Phase 3: [name] | [N-M] | [theme] |
| ...                                  |

**Cross-cutting:** [Initiatives that span multiple sprints — e.g., accessibility,
security, internationalization, content/data work that distributes across
sprints rather than living in one. Name where each lands and what blocks ship
until it lands.]

**Sprint Ordering Rule:** [State explicitly whether sprints must complete in
strict order, what (if any) work can run in parallel, and the rationale.
Default for most projects: strict order; the only exception is non-coding work
the operator can run in parallel.]

**Sprint Start Procedure:** [What every sprint must do before any task begins.
At minimum: read CIP for context, scan affected specs and reference docs for
stale terminology or contradictions, run /1 (audit). Spell out so it cannot be
skipped.]

**Sprint Close-Out Procedure (MANDATORY):** [What every sprint must do before
being marked complete. At minimum: checkbox audit (no silently dropped items),
literal execution of the sprint's quality gate, full regression run, end-to-end
verification on the target platform/device, and an artifact (test script,
demo, screenshot) that proves it. The purpose of this section is to prevent
the "80% trap" where 80% complete gets called done.]

**Quality Assurance:** [Per-sprint gate definition. How is "done" verified? If
the gate is blocked after N sessions, what is the escalation path?]

---

## Sprint 0: [name] [STATUS]

- [ ] [Checkbox at "reviewer could confirm this" granularity]
- [ ] ...

---

## Sprint 1: [name] [STATUS]

### [Subgroup]
- [ ] ...

### [Subgroup]
- [ ] ...

---

[Continue for each sprint. Repeat the [STATUS] tag — COMPLETE, IN PROGRESS,
PENDING, BLOCKED — at sprint-header level so a Ctrl-F surfaces sprint state
instantly.]

---

## Cross-Sprint Carry-Over

[Items that surfaced mid-sprint but were deferred to a later sprint. Each entry
names the originating sprint, the target sprint, and the reason for deferral.
This is the explicit overflow ledger — never silently drop work.]

- **Item:** [description]
  - **Origin:** Sprint [N]
  - **Target:** Sprint [M]
  - **Reason:** [why this slipped]

---

## Open Questions / Decisions Pending

[Live list of decisions that block one or more sprints. Each entry: the
question, what blocks on it, and who/when decides.]

- **Question:** [text]
  - **Blocks:** Sprint [N], [feature]
  - **Decider/timing:** [who, when]
