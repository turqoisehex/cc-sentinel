# Manual Test Script — cc-sentinel

## Prerequisites
- A test project with `.claude/` directory and `CLAUDE.md`
- Git initialized, at least one commit
- jq installed
- bash available (Git Bash on Windows)

## T1: Fresh Install (Unix)

1. Clone cc-sentinel to a temp location
2. Run `bash install.sh` from the cc-sentinel directory
3. Answer discovery questions (Q1-Q4)
4. Select all 7 modules
5. Verify: `.claude/settings.json` has all hook entries
6. Verify: `.claude/hooks/` contains all .sh files
7. Verify: `.claude/commands/` contains all .md files
8. Verify: `CLAUDE.md` has cc-sentinel rules block
9. Run `/self-test` — expect all checks PASS

## T2: Fresh Install (Windows PowerShell)

1. Run `powershell -File install.ps1`
2. Repeat verifications from T1

## T3: Incremental Install

1. Install with only Core module
2. Run `/self-test` — expect only Core checks
3. Re-run installer, add Verification module
4. Verify: existing Core hooks preserved, Verification hooks added
5. Run `/self-test` — expect Core + Verification PASS

## T4: Global Install

1. Run installer with `--global` or answer Q4 with "global"
2. Verify: hooks written to `~/.claude/settings.json`
3. Verify: hook file paths use absolute paths (not relative `.claude/`)
4. Open a different project — hooks should fire

## T5: Hook Behavior — Anti-Deferral

1. Start a CC session in the test project
2. Use Edit tool to write "we can address this in a future sprint"
3. Verify: hook injects anti-deferral reminder in additionalContext

## T6: Hook Behavior — Session Orient

1. Create `CURRENT_TASK.md` with task content
2. Start a new CC session
3. Verify: session-orient injects CT summary into session context

## T7: Hook Behavior — Pre/Post Compact

1. Create `CURRENT_TASK.md` and `CLAUDE.md` with content
2. Trigger PreCompact (approach context limit or simulate)
3. Verify: pre-compact injects state file summary
4. Trigger compaction → SessionStart with source=compact
5. Verify: post-compact injects reorientation with file contents

## T8: Hook Behavior — File Protection

1. Add `CLAUDE.md` to `.claude/protected-files.txt`
2. Attempt to Edit `CLAUDE.md` without GOVERNANCE-EDIT-AUTHORIZED in CT
3. Verify: hook blocks with deny decision
4. Add GOVERNANCE-EDIT-AUTHORIZED to CT
5. Attempt Edit again — verify: hook allows

## T9: Hook Behavior — Stop Task Check

1. Create squad evidence in `verification_findings/squad_test/` (5 PASS files)
2. Update `CURRENT_TASK.md` within last 2 minutes
3. Attempt to stop — verify: hook allows
4. Delete squad evidence, attempt to stop after claiming completion
5. Verify: hook blocks with "squad verification required"

## T10: Commit Enforcement

1. Stage a .dart file (non-exempt)
2. Run `bash scripts/channel_commit.sh --files "file.dart" -m "test" --skip-squad --local-verify`
3. Verify: per-commit agent check fires (blocks without evidence)
4. Create valid agent evidence files
5. Re-run — verify: commit succeeds with --skip-squad

## T11: Multi-Channel

1. Set `SENTINEL_CHANNEL=2`
2. Create `CURRENT_TASK_ch2.md`
3. Run channel_commit.sh with `--channel 2`
4. Verify: agent evidence uses `_ch2` suffix
5. Verify: squad evidence uses `ch2_` prefix

## T12: Context Awareness

1. Verify statusLine configured in settings.json
2. Start session — verify status bar shows context percentage
3. As context fills, verify graduated warnings fire at thresholds (50%, 65%, 75%, 85%, 95%)

## T13: Notification

1. Verify platform-appropriate flash script registered in Stop + Notification hooks
2. Complete a task — verify desktop notification fires
3. On Windows: verify terminal bell + FlashWindowEx
4. On macOS: verify terminal bell + osascript notification
5. On Linux: verify terminal bell + notify-send

## T14: Automated Test Suites

Run all test suites and verify pass counts:

```bash
bash modules/core/tests/test_anti_deferral.sh         # expect all PASS
bash modules/core/tests/test_session_orient.sh         # expect all PASS
bash modules/core/tests/test_agent_file_reminder.sh    # expect all PASS
bash modules/core/tests/test_pre_compact.sh            # expect 70 PASS
bash modules/core/tests/test_post_compact.sh           # expect 67 PASS
bash modules/verification/tests/test_stop_task_check.sh # expect all PASS
bash modules/commit-enforcement/tests/test_channel_commit.sh    # expect all PASS
bash modules/commit-enforcement/tests/test_wait_for_results.sh  # expect all PASS
bash modules/commit-enforcement/tests/test_safe_commit.sh       # expect 71 PASS
bash modules/commit-enforcement/tests/test_auto_format.sh       # expect 32 PASS
bash modules/notification/tests/test_notification.sh    # expect 24 PASS
bash modules/context-awareness/tests/test_context_awareness_hook.sh # expect all PASS
bash modules/governance-protection/tests/test_file_protection.sh # expect all PASS
python -m pytest modules/sprint-pipeline/tests/test_spawn.py -v # expect all PASS
```
