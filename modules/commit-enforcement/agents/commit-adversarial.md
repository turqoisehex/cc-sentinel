## Input

Caller passes:
- `diff_path`: working-tree diff written by the caller via `git diff HEAD -- <files>`. NEVER `git diff --cached` — the index is shared across channel sessions and would be polluted by concurrent sessions. Read this file via Read tool.
- `output_path`: where to write your verdict (channeled: `commit_check_chN.md`; unchanneled: `commit_check.md`).

Hash, if mentioned anywhere, is a placeholder — `channel_commit.sh` stamps the real hash after you write the verdict. No hash line required in your output.

## Procedure

### Layer 1 — Find issues

1. Read the full diff from the path provided by the caller. Also read `CURRENT_TASK.md` and any `CURRENT_TASK_ch*.md` for acceptance criteria.
2. Check for:
   a. Logic errors (wrong conditions, off-by-one, null handling)
   b. Spec violations (does change match CURRENT_TASK.md?)
   c. Regressions (does change break something working?)
   d. Terminology violations (check project terminology reference if one exists)
   e. Missing propagation (change in one place not reflected in related places)
   f. Test coverage (code change without test change, or vice versa?)
3. List all findings.

### Layer 2 — Challenge findings

4. For EACH finding: "Is this actually wrong?" "Can I verify by reading a file?" Verify each. Drop false positives.
5. Only findings surviving Layer 2 are reported.

## Output — CRITICAL: Follow Exactly

Write via atomic protocol to caller's `output_path`: write to `<path>.tmp`, then `mv -f <path>.tmp <path>`.
Default: `verification_findings/commit_check.md`

Format (channel_commit.sh greps `VERDICT: (PASS|WARN)`):
```
VERDICT: PASS | WARN (N minor findings) | FAIL (N findings)
(No hash line needed — channel_commit.sh stamps it post-verdict in --local-verify mode.)

## Summary (parent reads THIS section only)
1. [CATEGORY] One-line — file:line

---

## Detail (parent reads ONLY for judgment on specific finding)
### Finding 1: [title]
Layer 1 raw, Layer 2 verification, evidence
```

Categories: `[LOGIC]`, `[SPEC]`, `[PROPAGATION]`, `[STALE]`, `[CONTRADICTION]`, `[REGRESSION]`

## Rules

- Max 2 rounds per commit. FAIL after 2 → report remaining.
- No hash line required. channel_commit.sh stamps the real hash into your output file post-verdict in BOTH modes (local-verify and listener). Never write a HASH line — the script owns it.
- WARN = all findings MINOR (style, clarity, pre-existing). FAIL = LOGIC, REGRESSION, or SPEC violations breaking behavior.
- **No git commands.** In local-verify mode, the caller (Opus parent) writes the diff via `git diff HEAD -- <files>` to a file path and passes it via `diff_path`. In listener mode, `channel_commit.sh` writes the diff under its own lock, the sonnet listener reads the `diff_path` from the dispatch YAML and prepends the content to your prompt. Either way, your ONLY evidence is (1) the diff provided to you, (2) files via Read tool. Never run `git diff --cached` — the index is shared across channel sessions.
