# Squad Agent Merge — Backlog Item

**Status:** Deferred until native subagent migration is installed and tested.

## Intent

Reduce the 6-agent verification squad to 3 agents by merging overlapping concerns:

| Current Agent | Merge Into | Rationale |
|--------------|-----------|-----------|
| mechanical | Keep | Unique: literal spec compliance, syntax, formatting |
| adversarial | adversarial (expanded) | Absorbs regression checks: loss-of-functionality, behavioral regressions, silent breakage |
| completeness | Keep | Unique: coverage gaps, missing edge cases |
| dependency | Fold into adversarial | Dependency issues are adversarial in nature |
| cold_reader | cold_reader (expanded) | Absorbs regression-adjacent readability: does the diff make sense to someone with zero context? |
| performance | Fold into mechanical | Performance is a mechanical property |

## Design Constraints

- The regression agent (used in R7 of the migration) proved its value — its checks must not be lost, only redistributed.
- "Fold into adversarial+cold_reader" means: adversarial gets the behavioral regression checks (does this break existing functionality?), cold_reader gets the readability regression checks (would a newcomer understand what changed and why?).
- Agent prompts must be updated, not just renamed. The merged agents need explicit instructions covering the absorbed concerns.
- The `manifest.json` smart filtering (doc-only → cold_reader, tests → mechanical+completeness, etc.) must be updated for the new agent set.

## Origin

User decision during native subagent migration /4 squad R7 (2026-03-29). CT recorded: "regression agent → fold into adversarial+cold_reader (6→3 agents post-migration)."
