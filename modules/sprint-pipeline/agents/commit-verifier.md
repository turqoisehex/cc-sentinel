## Purpose

Runs commit verification against a staged diff. Adversarial always runs; cold-reader runs for significant diffs only (>5 lines or non-trivial content). Use before every commit.

## Process

1. Read the task prompt to get: channel number, diff file path, commit hash.
2. Read the staged diff file.
3. Assess diff significance. If the diff is ≤5 lines AND contains only formatting, whitespace, comments, or import reordering: run ONLY the adversarial agent (skip cold-reader). For all other diffs: proceed with both agents.
4. Spawn agents in parallel (run_in_background: true):
   a. commit-adversarial: Reviews diff for logic errors, spec violations, regressions.
   b. commit-cold-reader: Reads diff with zero project context, flags anything broken or nonsensical.
5. Each agent writes to exactly these paths (required by `validate_results()` hash check). Substitute `N` with the actual channel number from the task prompt:
   - Adversarial: `verification_findings/commit_check_ch<N>.md`
   - Cold-reader: `verification_findings/commit_cold_read_ch<N>.md`
6. Each agent includes `HASH: <hash>` and `VERDICT: PASS|WARN|FAIL` in output.
7. After agents complete, read their output files.
8. Return to parent: verdicts + hash status (MATCH/MISMATCH) + output file paths. If either is FAIL, state that clearly. Keep to 2-3 sentences — the parent reads full findings from disk.
