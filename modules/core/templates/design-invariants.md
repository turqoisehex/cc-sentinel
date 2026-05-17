## Project Overview

[Project name]: [One-line description of what it does, key technologies, architecture.]

## Design Invariants

If a task conflicts with an invariant, it is WRONG — flag and ask.

Invariants are non-negotiable constraints. Each one should state the rule AND the reason — the reason is what lets an agent judge edge cases instead of blindly following the letter.

**Template depth:** the example invariants below show the required level of specificity. Replace all examples with your actual invariants before using this file.

**Example invariants (replace these):**

1. **No silent data loss.** Every destructive action requires explicit confirmation. Undo must be available for at least 30 seconds. Batch operations preview their scope before executing. Why: users lose trust permanently after one accidental deletion; the cost of a confirmation step is negligible compared to the cost of lost data.

2. **API responses are always typed.** No `any`, no `unknown` at API boundaries, no unvalidated JSON casts. All external data passes through a validation layer before entering the domain. Why: untyped boundaries are where runtime crashes hide — the type system cannot catch what it never sees.

3. **Offline-first.** The app must function without network. Sync is additive (push when available); degraded mode is never an error state. Why: intermittent connectivity is the norm for the target deployment environment; network-dependent critical paths block users.

4. **[Your invariant name].** [Your rule]. Why: [Your reason].

## Tech Stack

- [Framework/library and version constraints]
- [Key architectural decisions (state management, database, etc.)]
- [Typography, theming, or design system choices]
