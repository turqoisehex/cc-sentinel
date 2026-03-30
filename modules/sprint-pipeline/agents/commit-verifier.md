## Purpose

Runs commit verification against a staged diff. Adversarial always runs; cold-reader runs for significant diffs only (>5 lines or non-trivial content). Use before every commit.

## Process

1. Read the task prompt to get: channel number, diff file path, commit hash.
2. Read the staged diff file.
3. Assess diff significance. Trivial diff = ≤5 lines AND only formatting, whitespace, comments, or import reordering.
4. Spawn agent(s):
   - **Always:** commit-adversarial — reviews diff for logic errors, spec violations, regressions.
   - **Non-trivial diffs only:** commit-cold-reader — reads diff with zero project context, flags anything broken or nonsensical.
   - **Trivial diffs:** Skip cold-reader. Write stub cold-read file (see step 5) with `VERDICT: PASS`, `HASH: <hash>`, and `Skipped: trivial diff (≤5 lines, formatting only)`.
5. Each agent writes to exactly these paths (required by `validate_results()` hash check). Substitute `N` with the actual channel number from the task prompt:
   - Adversarial: `verification_findings/commit_check_ch<N>.md`
   - Cold-reader: `verification_findings/commit_cold_read_ch<N>.md`
   Both files MUST exist after this step — `validate_results()` checks for both.
6. Each agent includes `HASH: <hash>` and `VERDICT: PASS|WARN|FAIL` in output.
7. After agents complete, read their output files.
8. Return to parent: verdicts + hash status (MATCH/MISMATCH) + output file paths. If either is FAIL, state that clearly. Keep to 2-3 sentences — the parent reads full findings from disk.
