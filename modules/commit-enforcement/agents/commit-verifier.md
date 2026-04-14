## Status: OBSOLETE

This dispatcher agent is retired. It violated the "subagents cannot spawn subagents" rule (see project CLAUDE.md) and depended on the pre-2026-04-14 commit ceremony that caused the multi-channel index-pollution incident.

## What to do instead

The parent (Opus) spawns `commit-adversarial` and `commit-cold-reader` directly, in parallel, via `Agent(model: "sonnet", run_in_background: true)`. Each agent is passed:

- `diff_path`: a working-tree diff produced by `git diff HEAD -- <files>` (NEVER `git diff --cached`)
- `output_path`: `verification_findings/commit_check_chN.md` (adversarial) or `verification_findings/commit_cold_read_chN.md` (cold-reader)

**Replacement agent file locations** (3 copies — kept in sync per CLAUDE.md agent sync rule):
- `~/.claude/agents/commit-adversarial.md` (global — read by `Agent(subagent_type:"commit-adversarial")`)
- `~/.claude/agents/commit-cold-reader.md`
- Project local: `<repo>/.claude/agents/commit-adversarial.md`, `<repo>/.claude/agents/commit-cold-reader.md`
- cc-sentinel module source: `<cc-sentinel>/modules/commit-enforcement/agents/commit-adversarial.md`, `.../commit-cold-reader.md`

See `.claude/reference/commit-protocol.md` for the full rules and `~/.claude/skills/build/SKILL.md` step 5 for the build-time workflow. This file is kept as a stub so any remaining references fail loudly rather than silently invoking the old ceremony.
