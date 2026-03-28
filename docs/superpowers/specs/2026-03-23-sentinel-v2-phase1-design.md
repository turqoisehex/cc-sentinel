# Sentinel v2 Phase 1 — Design Spec

**Date:** 2026-03-23
**Scope:** 8 low-risk, high-benefit features (prompt engineering + light bash)
**Approach:** Phased delivery (pivot from D9's original big-bang decision — user approved phased approach after research showed 16 features need Python/complex infrastructure). Phase 1 = easy + safe + high benefit.
**Credits:** See `docs/plans/archive/2026-03-23-sentinel-v2-credits.md`

---

## Features

### F1. YAML Frontmatter for CURRENT_TASK.md
**Module:** Core | **Type:** Template edit | **Risk:** None

Add YAML frontmatter block to `modules/core/templates/current-task-template.md`. Fields adapted from Continuous-Claude-v3's handoff format (~400 tokens vs ~2000 markdown):

```yaml
---
goal: ""
now: ""
test: ""
done_this_session: []
blockers: []
questions: []
decisions: []
findings: []
worked: []
failed: []
next: ""
files_created: []
files_modified: []
---
```

The markdown body below the frontmatter remains unchanged. `/cold` reads frontmatter for fast orientation. `/1` (sprint start) also reads frontmatter to pick up session context from the previous session. `pre-compact-state-save.sh` instructs model to populate it (via prompt injection — not transcript parsing, which is deferred to Phase 2).

**Files changed:** `modules/core/templates/current-task-template.md`, `modules/core/commands/cold.md` + `skills/cold/SKILL.md` (add frontmatter-read step), `modules/sprint-pipeline/commands/1.md` + `skills/1/SKILL.md` (add frontmatter-read step)

---

### F2. Auto-Checkpoint on Stop + PreCompact
**Module:** Core | **Type:** New bash hook | **Risk:** Very low (git stash is non-destructive)

New file: `modules/core/hooks/auto-checkpoint.sh`

Triggers: **Stop** and **PreCompact** (via two settings_merge entries).

Mechanism (adapted from claudekit's `create-checkpoint.ts`):
1. `git add -A` (temporarily stage all)
2. `git stash create "sentinel-checkpoint: <ISO timestamp>"` → returns SHA (no working dir change)
3. `git stash store -m "sentinel-checkpoint: <ISO timestamp>" <SHA>`
4. `git reset` (unstage)
5. Prune oldest sentinel checkpoints beyond max (hardcoded `MAX_CHECKPOINTS=10` in script): filter `git stash list` for entries matching `sentinel-checkpoint:` prefix, count only those, drop the oldest beyond MAX_CHECKPOINTS. Never prune non-sentinel stashes.

Behavior:
- Silent: exits 0 with no stdout (matching codebase convention — silent hooks produce no output, not `{}`)
- Graceful: if not in git repo or no changes, exit 0
- Never modifies working directory (`stash create` + `stash store`, not `stash push`)

**Files created:** `modules/core/hooks/auto-checkpoint.sh`
**Files changed:** `modules.json` (add Stop + PreCompact entries to core `settings_merge` AND add `auto-checkpoint.sh` to core `files.hooks` list)

**Installer note:** Core's new Stop entry must merge with existing Stop entries from verification (stop-task-check.sh) and notification modules. The installer's array-merge logic already handles this — SessionStart has cross-module entries today. Verify at implementation time.

---

### F3. Auto-Handoff Enhancement on PreCompact
**Module:** Core | **Type:** Edit existing hook prompt | **Risk:** None

Enhancement to `modules/core/hooks/pre-compact-state-save.sh`. The existing hook tells the model to update CT. Add explicit instructions to populate YAML frontmatter fields via prompt injection (the model fills in the values based on session context — distinct from D4's original "transcript parsing" approach, which is deferred to Phase 2):

Add to BOTH MSG branches (lines ~44 and ~46 — the if/else for has-task vs no-task). Append after existing instructions in each branch:
```
YAML FRONTMATTER: Update the YAML block at the top of your state file with:
- goal: one sentence describing the session objective
- now: which step is currently in progress
- done_this_session: list of completed items with file paths
- decisions: key choices made this session
- next: what the next session should do first
- files_created/files_modified: paths touched this session
```

**Files changed:** `modules/core/hooks/pre-compact-state-save.sh`

---

### F4. Performance Agent (6th Squad Member)
**Module:** Verification | **Type:** New markdown prompt | **Risk:** None

Add Agent 6 to `modules/verification/reference/verification-squad.md`:

**Performance Auditor** — flags algorithm complexity (O(n^2) where O(n) exists), unbounded memory growth, N+1 queries, synchronous blocking in async contexts, missing batching, lock contention. Rates CRITICAL/HIGH/MEDIUM/LOW. Only reports CRITICAL and HIGH.

Procedure matches existing agents: read work product → extract concerns → verify each against source → mark [P] PERFORMANCE_ISSUE / [~] POTENTIAL / [OK] CHECKED_CLEAN → write via atomic protocol.

Output: `verification_findings/SQUAD_DIR/performance.md` (where `SQUAD_DIR` is the session-bound squad directory — `squad_opus/`, `squad_sonnet/`, or channeled `squad_chN_opus/` etc., as defined in verification-squad.md "Setup" section)

**Files changed:** `modules/verification/reference/verification-squad.md`

---

### F5. Smart Agent Filtering + 6-Agent Update
**Module:** Verification + Commit Enforcement | **Type:** Edit prompts + hooks | **Risk:** Low (gate logic change needs care)

Enhancement to `modules/verification/commands/verify.md` Step 4. Before launching agents, classify changed files and only launch relevant agents:

| File Category | Agents Launched |
|---|---|
| Docs only (.md, .txt, .rst) | cold_reader |
| Tests only (*_test.*, *_spec.*, test_*) | mechanical, completeness |
| Config only (.json, .yaml, .toml, .env*) | adversarial, dependency |
| Source code (everything else) | all 6 |
| Mixed | union of matching categories |

Also update all "5 agents" references to "up to 6 agents" and add `performance.md` to agent lists.

**Gate coordination for smart filtering:** When squad launches fewer than 6 agents, write a `manifest.json` to the squad directory listing which agents were launched:
```json
{"launched": ["cold_reader.md"], "reason": "docs-only scope", "timestamp": "..."}
```
Both `stop-task-check.sh` and `safe-commit.sh` gate logic changes from "all 6 must exist and PASS" to "all agents listed in manifest.json must exist and PASS; if no manifest, expect all 6." This makes the gates filter-aware.

**manifest.json edge cases:** If manifest.json exists but is unparseable (invalid JSON), treat as "no manifest" (expect all 6) and log a warning. If `launched` array is empty, treat as "no manifest." Stale manifests are not a concern because verify.md manages manifest.json at launch time: filtered runs write a manifest listing launched agents, and full-scope runs (all 6 agents) delete any existing manifest.json to prevent a stale partial-run manifest from reducing expectations on the next run. Gates only read manifest.json during the same commit flow.

**Files with hardcoded "5 agents" that need updating:**
- `modules/verification/reference/verification-squad.md` (heading, rules, multiple references)
- `modules/verification/commands/verify.md` + `skills/verify/SKILL.md`
- `modules/verification/hooks/stop-task-check.sh` (SQUAD_EXPECTED array at line ~205 + threshold at lines ~223-239)
- `modules/commit-enforcement/hooks/safe-commit.sh` (`SQUAD_EXPECTED` at line ~196 + `SQUAD_EXPECTED_CLEAN` at line ~241 — two arrays in this file, three total counting stop-task-check.sh above)
- `modules/commit-enforcement/tests/test_safe_commit.sh`
- `modules/verification/tests/test_stop_task_check.sh`
- `modules/sprint-pipeline/commands/perfect.md` + `skills/perfect/SKILL.md`
- `modules/sprint-pipeline/commands/rewrite.md` + `skills/rewrite/SKILL.md`
- `modules/sprint-pipeline/templates/plugin-auto-invoke.md`
- `modules/commit-enforcement/reference/channel-routing.md`
- `modules/core/reference/operator-cheat-sheet.md`
- `README.md` (5 occurrences: lines ~30, ~127, ~281 as literal "5-agent"; lines ~307 and ~311 as prose "five more" / "Five independent")
- `modules.json` (verification module description at line ~176: "5-agent verification squad")

**Note:** verify.md and SKILL.md also have "read all output files" references in their post-launch results-reading steps — a distinct update site from the launch/count references.

**Files changed:** All files listed above (~17 files). Key gate-change files: `stop-task-check.sh` (manifest.json gate), `safe-commit.sh` (manifest.json gate + SQUAD_EXPECTED_CLEAN for post-commit cleanup).

---

### F6. Comment Replacement Detection Hook
**Module:** Verification | **Type:** New bash hook | **Risk:** Very low (warning only, never blocks)

New file: `modules/verification/hooks/comment-replacement.sh`

Trigger: **PostToolUse** matched to `Edit|MultiEdit` (not Write — Write replaces entire files without old/new string pairs).

Logic:
1. Read `tool_input.old_string` and `tool_input.new_string` (or `.edits[]` for MultiEdit)
2. Skip if file is markdown/docs (`.md`, `.txt`, `.rst`)
3. Skip if old content was already primarily comments
4. Count comment lines in new content (`//`, `#`, `/* */`, `<!-- -->`, `--`, `* `)
5. If old had code AND new is >50% comments: return `additionalContext` warning
6. Warning text: "You appear to have replaced code with a comment placeholder. This is almost never correct. Restore the original code and integrate your changes properly."

Never blocks — advisory only via `additionalContext`.

**Files created:** `modules/verification/hooks/comment-replacement.sh`
**Files changed:** `modules.json` (add PostToolUse entry to verification `settings_merge` AND add `comment-replacement.sh` to verification `files.hooks` list). Cross-module merge: commit-enforcement already has PostToolUse — installer must merge arrays.

---

### F7. Sensitive File Patterns
**Module:** Governance | **Type:** New config file + hook enhancement | **Risk:** Low

New file: `modules/governance-protection/sensitive-patterns.txt` (at module root, matching `protected-files.txt` convention)

~70 patterns from claudekit organized across 11 categories. **Directory-scoped patterns use bash case-glob matching against full `$FILE_PATH`:**
```
# ENVIRONMENT
*.env
*.env.*
!*.env.example
!*.env.template
# CERTIFICATE
*.pem
*.key
*.crt
*.pfx
*.p12
*.cer
# SSH — directory patterns match at any depth (second pass uses $FILE_PATH not basename)
*/.ssh/*
*/id_rsa*
*/id_ed25519*
*.ppk
*/authorized_keys
*/known_hosts
# CLOUD
*/.aws/*
*/.azure/*
*/.gcloud/*
*/.terraform/*
...etc (~70 total, 11 categories, adapted for bash glob)
```

**Note on recursive depth:** `*/.ssh/*` matches files at any nesting depth within `.ssh/` because `[[ "$FILE_PATH" == $PATTERN ]]` with `*` matches path separators in bash. For example, `*/.ssh/*` matches both `/home/user/.ssh/id_rsa` and `/home/user/.ssh/keys/backup.pem` because the trailing `*` consumes everything after `.ssh/`. Both `*` and `**` are functionally equivalent in bash `==` pattern matching (neither does true recursive globbing — they both match any characters including `/`). Some patterns in `sensitive-patterns.txt` use `**` for readability convention; both forms work.

Enhancement to `modules/governance-protection/hooks/file-protection.sh`:
- After existing exact-match check against `protected-files.txt` (using `$FILENAME` basename), add second pass
- Load `sensitive-patterns.txt` from same search path
- Second pass matches against **full `$FILE_PATH`**, not basename
- Use bash glob matching: `[[ "$FILE_PATH" == $PATTERN ]]`
- Support negation patterns (lines starting with `!`). **Evaluation order:** Two-pass within the loop — first collect all deny matches, then check negation patterns. If any negation pattern matches the file path, remove it from the deny set. This means negation patterns act as blanket exemptions regardless of position in the file (e.g., `!*.env.example` exempts that file even if `*.env` matched earlier).
- Different deny reason: "SENSITIVE: This file matches a credential/secret pattern and should not be read or modified by Claude."
- **Loop structure:** Second pass runs as a separate `while read` loop AFTER the existing protected-files loop completes — not nested inside it. Each file path gets checked against protected-files.txt first, then against sensitive-patterns.txt. Both passes operate on the same `$FILE_PATH` variable from the outer `tool_input.file_path` extraction.
- **GOVERNANCE_AUTHORIZED bypass:** `file-protection.sh` line ~77 has `[[ "$GOVERNANCE_AUTHORIZED" == "true" ]] && exit 0` which fires BEFORE both passes. This is **intentional** — governance-authorized sessions (e.g., `/mistake` edits) are explicitly trusted to modify protected files. The sensitive-patterns second pass inherits this bypass. If a future requirement needs credential protection to be non-bypassable, it should be a separate hook, not part of file-protection.sh.

**Files created:** `modules/governance-protection/sensitive-patterns.txt`
**Files changed:** `modules/governance-protection/hooks/file-protection.sh`, `modules.json` (add to config list)

---

### F10. Read-Only Agent Constraints
**Module:** Verification | **Type:** Edit existing prompts | **Risk:** None

Add constraint lines to ALL squad agents in `modules/verification/reference/verification-squad.md`:

For all 6 agents (mechanical, adversarial, completeness, dependency, cold_reader, performance), add to their prompt headers:
```
CONSTRAINT: You are READ-ONLY. Use only Read, Glob, Grep, and Bash (read-only commands).
Do not use Write, Edit, or MultiEdit. Your job is to find problems, not fix them.
```

All 6 agents are functionally read-only today (they only write their output file via atomic protocol), but none have an explicit constraint. Making it explicit for all agents ensures consistency and prevents accidental work-product modification by any agent.

**Design choice:** OMC uses YAML `disallowedTools` (runtime-enforced by CC). We use prompt-level CONSTRAINT text instead because sentinel's squad agents are launched via prompt injection into subagent calls, not via direct API — there is no YAML frontmatter mechanism available. The prompt-level constraint is effective: these agents have no motivation to write (their task is finding problems).

**Files changed:** `modules/verification/reference/verification-squad.md`

---

## Summary of File Changes

**New files (5):**
- `modules/core/hooks/auto-checkpoint.sh`
- `modules/verification/hooks/comment-replacement.sh`
- `modules/governance-protection/sensitive-patterns.txt`
- `modules/core/tests/test_auto_checkpoint.sh` (F2 test harness)
- `modules/verification/tests/test_comment_replacement.sh` (F6 test harness)

**Modified files (~25, including propagation of 6-agent change):**
- `modules/core/templates/current-task-template.md` (F1)
- `modules/core/commands/cold.md` + `skills/cold/SKILL.md` (F1 — add frontmatter-read step)
- `modules/sprint-pipeline/commands/1.md` + `skills/1/SKILL.md` (F1 — add frontmatter-read step)
- `modules/core/hooks/pre-compact-state-save.sh` (F3)
- `modules/verification/reference/verification-squad.md` (F4, F5, F10)
- `modules/verification/commands/verify.md` + `skills/verify/SKILL.md` (F5)
- `modules/verification/hooks/stop-task-check.sh` (F5 — gate logic + SQUAD_EXPECTED)
- `modules/commit-enforcement/hooks/safe-commit.sh` (F5 — gate logic + SQUAD_EXPECTED + SQUAD_EXPECTED_CLEAN)
- `modules/commit-enforcement/tests/test_safe_commit.sh` (F5)
- `modules/verification/tests/test_stop_task_check.sh` (F5)
- `modules/sprint-pipeline/commands/perfect.md` + `skills/perfect/SKILL.md` (F5)
- `modules/sprint-pipeline/commands/rewrite.md` + `skills/rewrite/SKILL.md` (F5)
- `modules/sprint-pipeline/templates/plugin-auto-invoke.md` (F5)
- `modules/commit-enforcement/reference/channel-routing.md` (F5)
- `modules/core/reference/operator-cheat-sheet.md` (F5)
- `README.md` (F5 — 5 occurrences: 3 literal "5-agent" + 2 prose at lines ~307/~311)
- `modules/governance-protection/hooks/file-protection.sh` (F7)
- `modules.json` (F2, F5, F6, F7)

**No Python. No new modules.** Installer changes limited to `install.sh` and `install.ps1` deploying `sensitive-patterns.txt` (F7) alongside `protected-files.txt`.

---

## Testing Strategy

Each feature can be tested independently:
- F1: Verify template has valid YAML frontmatter (parse test)
- F2: Run hook in test harness with mock git repo (existing test pattern)
- F3: Verify pre-compact hook output includes frontmatter instructions
- F4: Verify prompt is well-formed markdown
- F5: Verify verify.md references 6 agents; verify stop-task-check.sh uses dynamic count
- F6: Run hook with mock Edit input containing code→comment replacement
- F7: Run file-protection.sh with sensitive file paths
- F10: Verify constraint text present in agent prompts

---

## Out of Scope (Phase 2+)

- Passive correction capture (Stop hook scanning transcripts) — needs transcript path derivation
- Drift detector — needs Python, UserPromptSubmit untested
- Model routing — needs Python in spawn.py
- Spawn management overhaul — ~500-800 lines Python (covers worker health monitoring #22, git worktree isolation #23, done signal protocol #24)
- L1 codebase index — new module + Python script
- Compiler-in-the-loop — high annoyance risk
- Auto-learner scoring — needs tuning
- Adaptive quality gates — needs data collection
- Session-based hook disable — touches every hook
- HUD/statusline enhancements — terminal rendering risk
- Premortem skill — low priority for Phase 1
- Deny-rule generator — installer only
- Skill activation hints — nice-to-have
- File claim tracking — depends on spawn overhaul
