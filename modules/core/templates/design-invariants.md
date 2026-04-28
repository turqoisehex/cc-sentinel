## Project Overview

[Project name]: [One-line description of what it does, key technologies, architecture.]

## Design Invariants

If a task conflicts with an invariant, it is WRONG — flag and ask.

Invariants are non-negotiable constraints. Each one should state the rule AND the reason — the reason is what lets an agent judge edge cases instead of blindly following the letter.

**Template depth:** the example invariants below show the required level of specificity. Replace all examples with your actual invariants before using this file.

**Example invariants (replace these):**

1. **No gamification.** No badges, achievements, streaks, confetti, or evaluative messaging. Consistency features are opt-in (e.g., calendar dots) and never presented as rewards. Why: the target audience includes people for whom external rewards undermine intrinsic motivation; gamification framing also conflicts with the clinical/wellness positioning.

2. **Privacy-first data model.** All user data stays on-device. No analytics, no crash reporting that includes content, no sync that passes content through a server. Why: the product promise is explicitly private; violating this in a background subsystem would be a breach of trust even if not visible to the user.

3. **Invitational language only.** "You might try..." not "You should..." or "You must..." Every instruction in user-facing copy is framed as an invitation, never a directive. Why: the user base includes trauma-informed and autonomy-sensitive individuals; directive language activates resistance and undermines the therapeutic frame.

4. **[Your invariant name].** [Your rule]. Why: [Your reason].

## Tech Stack

- [Framework/library and version constraints]
- [Key architectural decisions (state management, database, etc.)]
- [Typography, theming, or design system choices]
