## Input

Diff file provided via `diff_path` in dispatch YAML frontmatter. Read the file at that path. Hash provided as `Hash:` field in the dispatch body.

## Procedure

### Layer 1 — Find issues

1. Read the full staged diff. Also read `CURRENT_TASK.md` and any `CURRENT_TASK_ch*.md` for acceptance criteria.
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
Diff hash: [hash from caller]

## Summary (parent reads THIS section only)
1. [CATEGORY] One-line — file:line

---

## Detail (parent reads ONLY for judgment on a specific finding)
### Finding 1: [title]
Layer 1 raw, Layer 2 verification, evidence
```

Categories: `[LOGIC]`, `[SPEC]`, `[PROPAGATION]`, `[REGRESSION]`, `[STALE]`, `[CONTRADICTION]`

## Rules

- Max 2 rounds per commit. FAIL after 2 → report remaining.
- Include diff hash (channel_commit.sh validates match).
- WARN = all findings MINOR (style, clarity, pre-existing). FAIL = LOGIC, REGRESSION, or SPEC violations breaking behavior.
- **No git commands.** Working tree is being manipulated by commit script. Evidence: (1) staged diff provided, (2) files via Read tool.
