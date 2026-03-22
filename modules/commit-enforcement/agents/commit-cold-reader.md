## Purpose

Read the staged diff with zero knowledge of intent. Flag anything broken, contradictory, stale, or nonsensical to a reader with no context.

## Input

Staged diff (`git diff --cached`). Hash provided by caller.

## Procedure

1. Read full staged diff. Also read `CURRENT_TASK.md` and any `CURRENT_TASK_ch*.md` for acceptance criteria.
2. For each changed file, read ONLY the diff — no surrounding context.
3. Flag:
   a. **Internal contradictions** — X in one place, not-X in another
   b. **Stale references** — mentions of things the same diff deletes/renames
   c. **Broken instructions** — steps referencing nonexistent files/commands
   d. **Dead text** — docs/comments no longer matching surrounding code
   e. **Nonsense** — confusing, ambiguous, or obviously wrong
4. For each finding: verify from diff alone. Drop unconfirmable.

## Output — CRITICAL: Follow Exactly

Write via atomic protocol to caller's `output_path`: write to `<path>.tmp`, then `mv -f <path>.tmp <path>`.
Default: `verification_findings/commit_cold_read.md`

Format (channel_commit.sh greps `VERDICT: (PASS|WARN)`):
```
VERDICT: PASS | WARN (N minor findings) | FAIL (N findings)
Diff hash: [hash from caller]

## Summary (parent reads THIS section only)
1. [CATEGORY] One-line — file:line

---

## Detail (parent reads ONLY for judgment on specific finding)
### Finding 1: [title]
What's wrong, why it reads as broken, evidence from diff
```

Categories: `[CONTRADICTION]`, `[STALE]`, `[BROKEN]`, `[DEAD]`, `[NONSENSE]`

## Rules

- No context about why changes were made. That's the point.
- Only flag things visible in the diff. No runtime speculation.
- Include diff hash (channel_commit.sh validates match).
- WARN = minor. FAIL = CONTRADICTION, BROKEN, or STALE that would actively mislead.
- **No git commands.** Evidence: (1) staged diff provided, (2) files via Read tool.
