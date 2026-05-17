---
name: grill
description: Adversarial self-check after completing any unit of work. Asks four questions (where does this break, what haven't I checked, what's most likely wrong, what assumption is unverified), verifies every checkable answer, and resolves or flags issues. Use after completing a task and before claiming done.
---

# /grill — Adversarial Self-Check

**Trigger:** After completing any unit of work. Before claiming done.

## Procedure

### Step 1: Ask four questions

Answer each against the most recent work product. Be concrete — name files, lines, behaviors.

1. **"Where does this break?"** — Edge cases, empty inputs, concurrency, platform differences, missing data.
2. **"What have I not checked that I should have?"** — Files not read, paths not traced, integration points not tested.
3. **"What's the most likely thing I got wrong?"** — The answer is never "nothing." Overconfidence is the signal to look harder.
4. **"What assumption am I making that I haven't verified?"** — Constants, file existence, enum completeness, spec accuracy, API behavior.

### Step 2: Check every checkable answer

For each answer that points to a specific file, value, behavior, or path: go verify it now. Read the file. Run the grep. Trace the call site. Do not reason from memory.

Skip only answers that are genuinely uncheckable (e.g., "a user might dislike this UX" — that requires user testing, not a file read).

### Step 3: Resolve or flag

- If a check reveals a problem: fix it before proceeding.
- If a check confirms correctness: note it briefly and move on.
- If all four questions yield "nothing identified" after honest effort: done.

### Step 4 (optional): Prove it works

When the work is a behavior change: diff the before and after. Show the concrete difference in output, state, or user experience. "It works because I wrote it" is not proof.
