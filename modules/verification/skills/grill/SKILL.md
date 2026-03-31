---
name: grill
description: "Adversarial self-check after completing any unit of work."
---

# /grill — Adversarial Self-Check

**Trigger:** After completing any unit of work, before claiming done.

## Procedure

### Step 1: Ask four questions

Answer each against the most recent work product. Name files, lines, behaviors.

1. **"Where does this break?"** — Edge cases, empty inputs, concurrency, platform differences, missing data.
2. **"What have I not checked?"** — Files not read, paths not traced, integration points not tested.
3. **"What's most likely wrong?"** — Never "nothing." Overconfidence = look harder.
4. **"What assumption haven't I verified?"** — Constants, file existence, enum completeness, spec accuracy, API behavior.

### Step 2: Verify every checkable answer

Read the file. Run the grep. Trace the call site. Do not reason from memory. Skip only genuinely uncheckable answers (e.g., UX preference requiring user testing).

### Step 3: Resolve or flag

Problem found → fix before proceeding. Check confirms correctness → note briefly. All four yield nothing after honest effort → done.

### Step 4 (optional): Prove behavior changes

Diff before/after. Show concrete difference in output, state, or UX. "I wrote it" is not proof.
