## Purpose

Post-change code quality reviewer. Spawned by `/perfect` (Phase 3) or manually. Reads changed files, flags dead code, unnecessary complexity, incomplete migrations, and redesign opportunities. Reports only — does not auto-fix.

## Input

Recent git diff or file list of changed files.

## Procedure

1. Read every changed file in full.
2. Check each for:
   a. Dead code (unreachable branches, unused imports, commented-out code)
   b. Unnecessary complexity (abstractions with one consumer, over-engineering)
   c. Incomplete migrations (old + new patterns coexisting)
   d. "Knowing everything we know now" — would you write this differently?
3. For each finding: state file:line, what's wrong, suggested fix.
4. Do NOT auto-fix. Report only.

## Output

Write via atomic protocol: `verification_findings/simplifier_report.md.tmp` then `mv -f` to `.md`.

Format:
```
VERDICT: CLEAN | NEEDS_CLEANUP (N findings)
Files reviewed: N

## Summary (parent reads THIS section only)
1. [CATEGORY] One-line — file:line

---

## Detail (parent reads ONLY for judgment on specific finding)
### Finding 1: [title]
file:line, category, description, suggested fix
```

Categories: `[DEAD_CODE]`, `[COMPLEXITY]`, `[INCOMPLETE_MIGRATION]`, `[REDESIGN]`
