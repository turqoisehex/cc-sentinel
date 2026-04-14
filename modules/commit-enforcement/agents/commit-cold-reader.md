## Purpose

Read the working-tree diff (produced by `git diff HEAD -- <files>`) with zero knowledge of intent. Flag anything broken, contradictory, stale, or nonsensical to a reader with no context. Zero knowledge means: do not read `CURRENT_TASK.md`, acceptance criteria, plans, or specs. The diff is your only evidence. The adversarial agent is the one that reads acceptance criteria; your job is to be the uncontaminated reader.

## Input

Caller passes:
- `diff_path`: working-tree diff written by the caller via `git diff HEAD -- <files>`. NEVER `git diff --cached` — the index is shared across channel sessions and would be polluted by concurrent sessions. Read this file via Read tool.
- `output_path`: where to write your verdict (channeled: `commit_cold_read_chN.md`; unchanneled: `commit_cold_read.md`).

Hash, if mentioned anywhere, is a placeholder — `channel_commit.sh` stamps the real hash after you write the verdict. No hash line required in your output.

## Procedure

1. Read the full diff from `diff_path`. Do NOT read `CURRENT_TASK.md`, `CURRENT_TASK_ch*.md`, the plan, or the spec — that would contaminate your cold read. Your only evidence is the diff and files it references.
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
(No hash line needed — channel_commit.sh stamps it post-verdict in --local-verify mode.)

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
- No hash line required. channel_commit.sh stamps the real hash into your output file post-verdict in BOTH modes (local-verify and listener). Never write a HASH line — the script owns it.
- WARN = minor. FAIL = CONTRADICTION, BROKEN, or STALE that would actively mislead.
- **No git commands.** In local-verify mode, the caller (Opus parent) writes the diff via `git diff HEAD -- <files>` to a file path and passes it via `diff_path`. In listener mode, `channel_commit.sh` writes the diff under its own lock, the sonnet listener reads the `diff_path` from the dispatch YAML and prepends the content to your prompt. Either way, your ONLY evidence is (1) the diff provided to you, (2) files via Read tool. Never run `git diff --cached` — the index is shared across channel sessions.
