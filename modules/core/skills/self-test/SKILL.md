---
name: self-test
description: Verify cc-sentinel installation integrity. Checks hooks, skills, references, templates, and CLAUDE.md rules. Run after installation or when things seem broken.
---

# /self-test — Verify Installation Integrity

**Trigger:** `/self-test`

Run diagnostic checks to verify cc-sentinel is correctly installed and configured.

## Procedure

Run each check below. Report PASS/FAIL for each. At the end, summarize with total pass/fail counts.

### 1. Settings.json hooks

Read the project's `.claude/settings.json` (or `~/.claude/settings.json` for global installs). For each installed module, verify that its hooks are registered:

- **Core:** `anti-deferral.sh` in PreToolUse, `session-orient.sh` in SessionStart, `pre-compact-state-save.sh` in PreCompact, `post-compact-reorient.sh` in SessionStart (compact matcher), `agent-file-reminder.sh` in PreToolUse, `auto-checkpoint.sh` in Stop and PreCompact
- **Context Awareness:** `context-awareness-hook.sh` in PreToolUse, `context-awareness-reset.sh` in SessionStart (compact matcher), statusLine configured
- **Verification:** `stop-task-check.sh` in Stop, `comment-replacement.sh` in PostToolUse (Edit|MultiEdit matcher)
- **Commit Enforcement:** `auto-format.sh` in PostToolUse
- **Governance Protection:** `file-protection.sh` in PreToolUse
- **Notification:** platform-appropriate flash script in Stop + Notification

For each hook: check the command path exists as a file on disk. PASS if registered AND file exists. FAIL if either is missing.

### 2. Reference files

Check `.claude/reference/` for expected files:

- **Core:** `operator-cheat-sheet.md`
- **Verification:** `verification-squad.md`
- **Commit Enforcement:** `channel-routing.md`
- **Sprint Pipeline:** `spec-verification.md`

### 3. Templates

Check project root for:
- `CURRENT_TASK.md` or `current-task-template.md` — at least one must exist

### 4. CLAUDE.md rules

Read the project's `CLAUDE.md`. Check for the presence of cc-sentinel behavioral rules (search for "Fix it now" or "cc-sentinel rules" marker). PASS if rules block is present.

### 5. Working directory

If the Verification module is installed, check that `verification_findings/` directory exists. If not, create it.

Check that `verification_findings/` is listed in `.gitignore` (if this is a git repo).

### 6. Skills

Check that installed skills exist in `.claude/skills/<name>/SKILL.md`:

- **Core:** `cleanup`, `cold`, `self-test`, `status`
- **Context Awareness:** `configure-context-awareness`
- **Verification:** `grill`, `verify`
- **Sprint Pipeline:** `1`, `2`, `3`, `4`, `5`, `audit`, `design`, `build`, `perfect`, `finalize`, `opus`, `sonnet`, `rewrite`, `spawn`
- **Governance Protection:** `mistake`, `prune-rules`

### 7. Auto-invoke rules

Check `.claude/rules/plugin-auto-invoke.md` exists. PASS if present, FAIL if missing.

### 8. Summary

Print a summary table:

```
cc-sentinel self-test results:
  Hooks registered:     [N/M PASS]
  Hook files on disk:   [N/M PASS]
  Reference files:      [N/M PASS]
  Templates:            [PASS/FAIL]
  CLAUDE.md rules:      [PASS/FAIL]
  Working directory:    [PASS/FAIL]
  Skills:               [N/M PASS]
  Auto-invoke rules:    [PASS/FAIL]

  Overall: [PASS/FAIL] ([total] checks, [passed] passed, [failed] failed)
```

If any checks fail, list each failure with the expected path and what was missing.
