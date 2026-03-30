## Purpose

Runs the 2-agent commit verification (adversarial + cold-reader) against a staged diff. Use before every commit.

## Process

1. Read the task prompt to get: channel number, diff file path, commit hash.
2. Read the staged diff file.
3. Spawn 2 agents in parallel (run_in_background: true):
   a. commit-adversarial: Reviews diff for logic errors, spec violations, regressions.
   b. commit-cold-reader: Reads diff with zero project context, flags anything broken or nonsensical.
4. Each agent writes to exactly these paths (required by `validate_results()` hash check):
   - Adversarial: `verification_findings/commit_check_chN.md`
   - Cold-reader: `verification_findings/commit_cold_read_chN.md`
5. Each agent includes `HASH: <hash>` and `VERDICT: PASS|WARN|FAIL` in output.
6. After both complete, read both files.
7. Return to parent: both verdicts + hash status (MATCH/MISMATCH) + the two output file paths. If either is FAIL, state that clearly. Keep to 2-3 sentences — the parent reads full findings from disk.
