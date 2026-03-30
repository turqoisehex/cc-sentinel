# Squad Agent Merge — COMPLETE (2026-03-30)

**Status:** Implemented. 6→5 agents.

## Decision

Evidence-based analysis of 8-9 verification rounds across 6 squad directories showed each agent catches genuinely unique findings that other agents miss. Only performance→mechanical was safe to merge without quality loss.

## Final Agent Set (5)

| Agent | Absorbed | Unique Value |
|-------|----------|-------------|
| mechanical | + performance | Byte-level propagation parity, parameter ranges, enum validity, O(n²)+, N+1 queries, hot-path allocation |
| adversarial | + regression pre-pass | Env var edge cases, subagent env inheritance, voice compliance, mandatory regression checking (callers, stale refs, changed defaults) |
| completeness | (unchanged) | Exhaustive dispatch site tables, spec §-by-§ coverage maps, out-of-scope negative guards, gap closure tracking |
| dependency | (unchanged) | File collision matrices, DAG proofs, write hazards, end-to-end chain tracing |
| cold_reader | (unchanged) | Zero-context readability, orphaned context, outcome claims, jargon, presuppositions |

## Why Not 3

Original plan was 6→3 (fold dependency→adversarial, completeness→adversarial, performance→mechanical). Analysis of actual findings showed:
- **dependency** uniquely caught Wayland SENTINEL_LISTENER gap, file collision matrices, SONNET-before-OPUS write hazards — adversarial never finds these
- **completeness** uniquely caught missing DB tables, exhaustive dispatch site enumeration, Implementation Status Maps — adversarial focuses on what's wrong, not what's missing

## Changes Made

- `verification-squad.md`: Agent 6 (performance) removed, performance checks merged into Agent 1 (mechanical) prompt
- Adversarial: Step 4 "Regression Pre-Pass" added as mandatory for all code changes — caller tracing, stale reference grep, changed-default consumer verification
- Propagated to `~/.claude/reference/verification-squad.md`

## Origin

User decision during native subagent migration /5 finalize (2026-03-30). Original 6→3 intent from /4 R7 (2026-03-29), revised after evidence-based analysis.
