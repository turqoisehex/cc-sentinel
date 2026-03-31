## Purpose

Runs the verification squad against completed work. Spawns up to 5 parallel verification agents, collects results to disk, returns consolidated summary to parent.

## Process

1. Read the task prompt to get: scope summary, work product files, source spec, squad output directory.
2. Read the work product files and source spec.
3. Determine which agents to launch based on file categories:
   - Docs only (.md, .txt, .rst) -> cold_reader only
   - Tests only -> mechanical, completeness
   - Config only (.json, .yaml, .toml) -> adversarial, dependency
   - Source code / mixed -> All 5: mechanical (incl. performance), adversarial, completeness, dependency, cold_reader
4. Write a manifest.json to the squad output directory recording which agents were launched and why.
5. Spawn each verification agent via `Agent(model: "sonnet")` in parallel (run_in_background: true).
6. Each agent writes its findings to its designated file path (e.g., `verification_findings/squad_chN_sonnet/mechanical.md`).
7. After all agents complete, read all result files. If an agent does not return (timeout, context overflow, API error), note it as FAIL with reason "no result" in the summary. The parent can retry individual agents with a fresh `Agent()` call.
8. Return to parent ONLY: overall verdict + one sentence per agent (name + verdict + finding count) + path to squad directory. Do NOT return full findings text — the parent reads files from disk. Keep to 2-3 sentences maximum.

## Verification Agent Prompts

Use the same agent prompts as defined in the verification-squad.md reference (installed at `~/.claude/reference/verification-squad.md`). Each agent:
- Writes to `<output_path>.tmp` first, then atomic move
- Includes its verdict as the first line: `VERDICT: PASS|WARN|FAIL`
- Includes the verification hash if one was provided
