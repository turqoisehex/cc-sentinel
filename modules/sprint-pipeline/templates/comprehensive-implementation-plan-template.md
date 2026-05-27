<!--
================================================================================
COMPREHENSIVE_IMPLEMENTATION_PLAN.md — TEMPLATE

PURPOSE
This file is the project's PLANNING CONTEXT — the surrounding "why" and
"in what order" that the SPRINT_CHECKLIST.md cannot capture. SC is "what to
do" (executable). CIP is "what informs the doing" (declarative).

WHO READS IT
- Operator at the start of every sprint (per the sprint-start procedure in SC).
- The /1 (audit) skill when establishing sprint context.
- The /2 (build) skill when proposing architecture.
- Future-you, six months from now, trying to remember why sprint X depends on
  sprint Y, why a particular tradeoff was made, or what was paused on a
  human's decision.

THE CRITICAL DISTINCTION
SC is a ledger. CIP is a memory.

If a fact would be obvious from looking at the codebase or the git log, it
does NOT belong here.

If a fact is a SPRINT-SPECIFIC CHECKBOX ("implement function X"), it does NOT
belong here — it belongs in SC.

What DOES belong here:
- Pre-implementation dependencies that aren't code (design sessions, content
  decisions, legal review, third-party negotiations, hardware acquisitions).
- Asset production sequences (audio recording, video shoots, image rendering,
  dataset collection) whose ordering matters and isn't visible in code.
- Content/data inventories that must be complete before a sprint can ship
  (X exercises in Y categories, N translations, M edge-case fixtures).
- Risk register: technical, schedule, scope, dependency risks with mitigations.
- Critical path: which dependencies, if slipped, slip the whole project.
- Cross-cutting decisions: ones that affect multiple sprints and would be
  invisible if buried in any single sprint's checkboxes.

HOW TO BUILD IT (read once when first creating this file, then delete this block)

1. Open with PROJECT STATUS and PHILOSOPHY. Two or three sentences each.
   - Status: where things stand right now and where to look for current state
     (typically: "See SPRINT_CHECKLIST.md for current completion status").
   - Philosophy: the operating principles that make this project decide A vs B
     when both are defensible — e.g., "ship complete, update conservatively";
     "privacy first"; "neurodivergent-first"; "no feature additions
     post-launch." These principles are the tiebreaker for future scope
     debates, so write them precisely.

2. STRUCTURE NOTE at the top makes the SC/CIP split explicit. New readers
   often need this orientation. Keep it short (two sentences).

3. SECTIONS, ordered roughly by "when in the project lifecycle they matter":
   a. Pre-implementation dependencies (design sessions, content decisions,
      legal, third-party — anything that must happen before sprint code can).
   b. Document/spec cleanup (any pre-work to specs that sprints assume done).
   c. Sprint task index (NOT the tasks themselves — just a pointer to SC and
      a per-sprint summary of WHY this sprint exists, what it unblocks).
   d. Asset/content production sequences (if applicable — audio, video,
      images, datasets — with their own ordering rules).
   e. Content/data completeness inventory (the "have we written enough X?"
      tracker).
   f. Risk register (technical, schedule, scope, dependency — each with
      likelihood/impact and mitigation).
   g. Critical path (the dependency chain whose slippage slips the project).

4. For each PRE-IMPLEMENTATION DEPENDENCY, document:
   - What it produces (the artifact)
   - What sprint(s) it blocks
   - Where the artifact lives (file path, channel, external link)
   - Recommended sequence (which dependencies block other dependencies)

5. For each RISK, write:
   - The risk itself (specific, falsifiable — not "things might go wrong")
   - Likelihood (high/medium/low) and impact (high/medium/low)
   - Mitigation (what we're doing to reduce it OR the fallback if it fires)
   - Owner / decision-needed-by-when (if applicable)

6. For the CRITICAL PATH section, draw the actual dependency chain. Not every
   dependency — just the ones whose slippage would slip the ship date. A
   diagram in ASCII art is fine. List one dependency per line, with the
   blocking relationship explicit.

7. KEEP CHECKBOXES OUT. If you find yourself writing "[ ] do X" here, move it
   to SC and write "[ ] reason X matters / what unblocks" here instead.

MAINTENANCE
- Update the status header when project state shifts.
- Update the risk register at sprint boundaries (close one out, open the
  next). Stale risks are worse than no risks.
- When a decision is made that resolves a "pending" item, replace the
  pending line with a one-sentence decision record and a date.
- Do NOT delete completed pre-implementation items — strike-through and
  annotate (date, outcome). The CIP is also a project memory.

LINK BACK
- This file is paired with SPRINT_CHECKLIST.md (SC). CIP is "the surrounding
  context that informs decisions." SC is "what to do." Each should reference
  the other near the top.

When you've absorbed the above, delete this comment block and start filling
in the sections below.
================================================================================
-->

# [PROJECT NAME]: Comprehensive Implementation Plan

**Date:** [Created YYYY-MM-DD] ([restructured YYYY-MM-DD if applicable])
**Status:** See `SPRINT_CHECKLIST.md` for current completion status.
**Philosophy:** [Two or three sentences naming the operating principles that
make this project decide A vs B when both are defensible. These principles
are the tiebreaker for future scope debates — write precisely.]

> **STRUCTURE NOTE:** Sprint task lists live ONLY in `SPRINT_CHECKLIST.md`.
> This document provides planning context: pre-implementation dependencies,
> asset production sequences, content inventory, risk analysis, and critical
> path. These two files are complementary — SC is what to do; CIP is the
> surrounding context that informs decisions.

---

## Table of Contents

1. [Pre-Implementation Dependencies](#1-pre-implementation-dependencies)
2. [Pre-Implementation: Document/Spec Cleanup](#2-pre-implementation-document-spec-cleanup)
3. [Sprint Index](#3-sprint-index)
4. [Asset / Content Production Sequence](#4-asset-content-production-sequence)
5. [Content Completeness Inventory](#5-content-completeness-inventory)
6. [Risk Register](#6-risk-register)
7. [Critical Path](#7-critical-path)

---

## 1. Pre-Implementation Dependencies

These items must complete BEFORE their corresponding sprints can begin. Each
has its own artifact (spec, decision document, third-party deliverable) named
explicitly.

### Dependency A: [name] (Sprint [N] prerequisite)
**Artifact:** [path or external link]
**Produces:** [what decision/artifact this resolves]
**Blocks:** [which sprint(s) cannot start until this lands]

### Dependency B: [name] (Sprint [N] prerequisite)
**Artifact:** [path]
**Produces:** [...]
**Blocks:** [...]

[Continue for each pre-implementation dependency.]

### Recommended Sequence

```
1. Dependency A  -> unblocks Sprint N
2. Dependency B  -> unblocks Sprint M
3. ...
```

---

## 2. Pre-Implementation: Document/Spec Cleanup

[Pre-work on specs/docs that sprints assume is already done. List the cleanups,
why each matters, and which sprint depends on which cleanup.]

- [ ] [Cleanup item] — blocks Sprint [N]
- [ ] [Cleanup item] — blocks Sprint [M]

---

## 3. Sprint Index

For each sprint in SC, write a paragraph explaining WHY the sprint exists,
what it unblocks, and what makes it non-trivial. Do NOT duplicate the
checkboxes from SC — those are the executable; this is the rationale.

### Sprint [N]: [name]
[Why this sprint exists. What it unblocks. What the non-obvious risks are.
What dependencies it inherits from earlier sprints.]

### Sprint [N+1]: [name]
[...]

---

## 4. Asset / Content Production Sequence

[Applicable when the project ships non-code assets — audio, video, images,
data, content. If a sprint depends on an asset produced outside the codebase,
the asset's production sequence belongs here. Skip this section if the project
has no such assets.]

### Sequence

```
1. [Asset A produced]  -> consumed by Sprint N
2. [Asset B produced]  -> consumed by Sprint M
3. ...
```

### Per-Asset Detail

**Asset A:** [name]
- Produced by: [who/how]
- Format: [spec]
- Storage location: [path]
- Consumed by: [sprint, feature]

---

## 5. Content Completeness Inventory

[Tracker for "have we written/produced enough X?" Applies when the project
needs to ship N units of content (exercises, lessons, articles, episodes) and
sprint completion depends on hitting that count. Skip if not applicable.]

| Category | Target Count | Current Count | Status |
|----------|--------------|---------------|--------|
| [name] | [N] | [M] | [ON TRACK / BEHIND / COMPLETE] |

---

## 6. Risk Register

For each risk: state it specifically (falsifiable), score likelihood + impact,
name the mitigation or fallback.

### Risk 1: [name]
- **Description:** [specific, falsifiable]
- **Likelihood / Impact:** [H/M/L] / [H/M/L]
- **Mitigation:** [what we're doing] OR **Fallback:** [what we do if it fires]
- **Owner / decision-by:** [who / when, if applicable]

### Risk 2: [name]
[...]

---

## 7. Critical Path

The dependency chain whose slippage slips the project ship date. Not every
dependency — just the ones whose slippage propagates.

```
[Dependency A]
    -> [Dependency B]
        -> Sprint [N]
            -> Sprint [M]
                -> Ship
```

[Annotate any dependency that is currently at risk per Section 6.]
