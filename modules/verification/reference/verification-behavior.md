## Verification Behavior Rules

Read before running /verify, /perfect, /grill, or any verification pass.

### Procedural Compliance Is Non-Negotiable

Execute every verification procedure EXACTLY as defined in its procedure file. If it says 5 agents, launch 5 agents. If it says max 3 rounds, stop at 3. There is ZERO discretion to reduce, collapse, compact, abbreviate, or "streamline" any verification procedure. A single comprehensive agent is NOT a substitute for a multi-agent squad. "Context pressure," "equivalent coverage," "already verified," "diminishing returns," and "sufficient confidence" are NEVER valid reasons to skip or reduce steps. These are mechanical commands — execute them without reasoning about whether they can be shortened.

### No Skimming

Context percentage is never a valid reason to skip reading files. If a procedure says "read," read. If context is genuinely tight, delegate the reading to a subagent. Never present a skimmed evaluation as thorough. If you can't do a step properly, say so — don't silently degrade it.

### Externalize Decisions Before Verification

Before any verification or completion claim: replay conversation, list every user decision/approval/rejection, grep work product for each. Anything missing -> write to file immediately. Only then launch verification. Parent session's job — agents lack conversation context.

After edits: re-read edited sections to confirm changes are physically present. Never claim "N fixes applied" based on having called Edit. Gap between "I noted that" and "it's in the file" is where decisions die.

### Fixes Are In-Place Edits — Never Appendices

When a verification round finds wrong text in a spec, code, or any file, the fix is to **edit the original wrong text at its source location**. Find the wrong prose, change it, done.

**Banned fix patterns** (all forms of fix theater that leave the original wrong text in place):
- Appending a "Consolidated fixes" or "Bindings" section at the end of the file
- Writing "§ 3.X R{N} corrections" appendix blocks that describe what earlier sections should say
- Adding "SUPERSEDED" or "OBSOLETE" markers to the original text instead of replacing it
- Writing a "fix_summary" that lists changes as if they were applied, when the original text is untouched
- Any structure where the wrong text and its correction coexist in the same file

**Why this matters for convergence:** Cold readers read linearly. If § 2.3 says X, they implement X — they will never find the correction in § 3.8. Each round's appendix becomes new surface area for the next round's agents to flag. Findings compound instead of subtracting. R11→R15 on the breathing engine spec went from 30 to 40 findings because four rounds of appendix "fixes" never edited the original wrong prose.

**Convergence diagnostic:** If round N+1 has more findings than round N, stop. The fix method is broken. Re-read every "fix" from round N. If any fix was an annotation rather than an in-place edit, convert it before launching the next round.

### /verify full = Full Squad

When `/verify full` is invoked on implementation plans (.md files describing code changes), treat as "mixed" scope — the plan touches source code even though the plan file is markdown. Run all applicable agents. Only use docs-only filtering for pure documentation (READMEs, changelogs, comments).

### Sonnet Listener CT Isolation

Sonnet listener sessions must NEVER write to CURRENT_TASK files, even when the stop hook fires. The /sonnet skill states: "Never write to CURRENT_TASK files" and "Ignore stop hooks." Stop hooks are designed for Opus orchestrator sessions, not stateless Sonnet listeners.
