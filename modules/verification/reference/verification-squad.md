## Verification Squad

**Trigger:** Before ANY completion claim. Squad is the **default** — you must actively qualify for an exemption to skip it. If unsure, run it.

### The Five Agents

Launch all 5 in parallel (`run_in_background: true`). Write to `squad_opus/` or `squad_sonnet/` (per session-bound dirs rule below).

| Agent | File | What It Catches |
|---|---|---|
| Mechanical Auditor | `mechanical.md` | Wrong file paths, constants, enum values, counts, **API signatures** — anything greppable against disk |
| Adversarial Reader | `adversarial.md` | **Spec sanity (hallucinated content)**, contradictions, rule violations, impossible instructions, charity bias |
| Completeness Scanner | `completeness.md` | Missing requirements, unassigned items, spec gaps. **Sequential batches of 7 for >20 items.** |
| Dependency Tracer | `dependency.md` | **Missing migrations, silent default changes, untraced call sites** — every change traced one level out |
| Cold Reader | `cold_reader.md` | **Semantic errors invisible to the author** — nonsense, broken/dead instructions, orphaned context, stale language. Reads with zero intent knowledge. |

Each agent MUST end with `VERDICT: PASS` or `VERDICT: FAIL` + issue count.

### Rules

1. **All 5 must PASS** before claiming completion. Any FAIL → fix issues → re-run only the failed agent(s).
2. **Max 3 rounds.** Initial run + 2 re-runs. If any agent still FAILs after round 3: stop fixing. Delete the squad directory. Write remaining issues to CURRENT_TASK.md with `VERIFICATION_BLOCKED` marker and present to user with the list of unresolved issues and recommended actions. Do not attempt further autonomous fixes — remaining issues likely require design judgment.
3. **After all 5 PASS:** Write `VERIFICATION_PASSED` + one-line summary to CURRENT_TASK.md. Note: this is documentation only — hooks do NOT accept it as enforcement evidence. Only actual squad files satisfy the commit gate.
4. **Squad files are ephemeral.** Gitignored. The commit hook cleans only COMPLETED squad directories (all 5 files with VERDICT: PASS) after successful commit. In-progress or failed directories from other sessions are left untouched.
5. **Replaces ad-hoc verification.** No extra agents unless Squad flags areas needing deeper investigation.
6. **Hook-enforced.** The commit hook blocks non-exempt commits without 5/5 PASS in `squad_*/`. Use `--skip-squad` for WIP only.
7. **Session-bound dirs.** `squad_opus/` or `squad_sonnet/` — no default `squad/`.
8. **Source spec rule.** Completeness Scanner SOURCE_SPEC = authoritative spec or user request, never just CURRENT_TASK.md.

### Exemptions (ALL conditions must be true to skip)

Skip ONLY when ALL conditions match one category. If unclear, run Squad.

1. **State-file-only** — ONLY CT/MEMORY/HANDOFF files. No code, governance, or specs.
2. **Git ops** — commits/merges/branches with no file changes.
3. **Research** — no deliverable produced. Notes/analysis only.
4. **Single non-governance doc** — one `.md` NOT in `.claude/`, `scripts/`, or governance paths.

Everything else → Squad required. The commit hook hard-blocks non-exempt files without evidence.
