# cc-sentinel — Mac First-Session Experience

You're a Mac user who just discovered Claude Code and heard about cc-sentinel. You want to get sentinel running globally so every project benefits, and you want to see what it actually does.

**Before pasting into Claude Code, run these in your Mac terminal:**

```bash
# 1. Install Homebrew (if you don't have it — skip if `brew --version` works)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Follow the "Next steps" it prints to add brew to your PATH

# 2. Install jq (required — all cc-sentinel hooks use it for JSON parsing)
brew install jq

# 3. Verify prerequisites
jq --version        # should print jq-1.x
python3 --version   # should print Python 3.x (built-in since macOS Catalina)
git --version       # should print git 2.x

# 4. Install Claude Code (if you haven't already)
npm install -g @anthropic-ai/claude-code

# 5. cd to a git project (or create a throwaway one)
mkdir -p ~/test-project && cd ~/test-project
git init && echo "# Test" > README.md && git add -A && git commit -m "init"

# 6. Launch Claude Code
claude
```

Now paste everything below into the Claude Code session.

---

I want to install cc-sentinel — I heard it governs Claude Code sessions to prevent common problems like premature completion, context loss, and undisciplined commits. Set it up globally so it works across all my projects. Here's what I need:

### 1. Clone and Install

Clone cc-sentinel and walk me through the conversational installer. I want all modules — give me everything.

Install globally (`~/.claude/`). For context-awareness, use the bundled version.

```bash
git clone https://github.com/turqoisehex/cc-sentinel.git /tmp/cc-sentinel
```

Then run the installer targeting global:
```bash
bash /tmp/cc-sentinel/install.sh --modules "core,context-awareness,verification,commit-enforcement,sprint-pipeline,governance-protection,notification" --target global
```

After the installer finishes:
1. Inject the CLAUDE.md rules — read `/tmp/cc-sentinel/modules/core/claude-md-rules.md` and append its contents to `~/.claude/CLAUDE.md` wrapped in `<!-- cc-sentinel rules start -->` / `<!-- cc-sentinel rules end -->` delimiters
2. Run `/self-test` and show me every PASS/FAIL line

### 2. See It Working

Now I want to actually experience what sentinel does — not just see test output, but feel the governance in a real workflow. Let's build a small Python utility together.

**2a. Create the project files**

Write `app.py`:
```python
def greet(name):
    return f"Hello, {name}"
```

And `test_app.py`:
```python
from app import greet

def test_greet():
    assert greet("World") == "Hello, World"
```

**2b. Trigger anti-deferral**

Now edit `app.py` and add this function:

```python
def calculate_tax(amount, rate):
    # TODO: will implement proper tax calculation in a future sprint
    return amount * rate
```

The anti-deferral hook should catch "future sprint" and warn me. Tell me what it says.

**2c. Fix and commit properly**

Fix the deferral — remove the TODO comment and just implement it. Then commit both files using the sentinel commit workflow:

```bash
bash ~/.claude/scripts/channel_commit.sh --files "app.py test_app.py" -m "feat: add greeting and tax utilities" --local-verify
```

Tell me what happened — did it detect Python? Did it try to run tests? Did the adversarial reviewer pass?

**2d. Try to break governance**

Try to edit `CLAUDE.md` directly — add a comment at the end. The file-protection hook should block this. Tell me what the block message says.

Now do it properly: add `GOVERNANCE-EDIT-AUTHORIZED` as a standalone line to `CURRENT_TASK.md` (create it if needed), try the edit again, then remove the authorization marker.

**2e. Context awareness**

Check the status bar — is the context meter visible? What percentage does it show? Is it using Unicode blocks (█/░) or ASCII (#/-)? My terminal supports Unicode.

**2f. Try /grill**

Run `/grill` to adversarially challenge the work we just did. It should ask four questions and verify each answer. Tell me what it finds.

**2g. Try /status**

Run `/status` to see the current session state.

### 3. Verify Platform-Specific Mac Items

Run these and tell me what each one produces:

```bash
# macOS notification — should trigger terminal bell + Notification Center popup
echo '{}' | bash ~/.claude/hooks/flash-notification.sh

# Verify it's the macOS version (should contain "osascript", NOT "notify-send")
head -5 ~/.claude/hooks/flash-notification.sh

# Pre-compact hook (state save reminder)
echo '{}' | bash ~/.claude/hooks/pre-compact-state-save.sh

# Post-compact hook (reorientation — compact source)
echo '{"source":"compact"}' | bash ~/.claude/hooks/post-compact-reorient.sh

# Post-compact (non-compact source — should produce no output)
echo '{"source":"normal"}' | bash ~/.claude/hooks/post-compact-reorient.sh

# BSD stat (macOS native — should return epoch timestamp)
stat -f %m CURRENT_TASK.md 2>/dev/null && echo "BSD stat works"

# GNU stat (should NOT work on stock macOS)
stat -c %Y CURRENT_TASK.md 2>&1 || echo "GNU stat unavailable (expected on macOS)"

# Unicode locale check
echo "LANG=$LANG"
```

### 4. Test Spawn Configuration

Check that spawn was configured with my startup delay:

```bash
python3 ~/.claude/tools/spawn.py --check --json
python3 ~/.claude/tools/spawn.py --dry-run duo 2
```

The dry-run should show the full sequence of what spawn would do — opening windows, typing commands, waiting for startup. If my project directory triggers a trust prompt, it should show the trust prompt dismissal step too.

### 5. Run the Automated Test Suites

Run every test script that ships with sentinel:

```bash
cd /tmp/cc-sentinel
for test in modules/*/tests/test_*.sh; do
  echo "=== $test ==="
  bash "$test" 2>&1
  echo ""
done
```

Also run the Python spawn tests:
```bash
python3 -m pytest modules/sprint-pipeline/tests/test_spawn.py -v
```

### 6. Final Report

Create a summary table marking every feature FIRED / NOT FIRED / BLOCKED / ERROR with exact output:

```
INSTALLATION
  [ ] Installer detected macOS (Darwin)
  [ ] All 7 modules installed globally to ~/.claude/
  [ ] /self-test — all checks PASS
  [ ] .claudeignore generated
  [ ] Notification: flash-macos.sh (not Linux/Windows version)

HOOKS
  [ ] anti-deferral.sh — caught "future sprint" language
  [ ] session-orient.sh — injected context on session start
  [ ] pre-compact-state-save.sh — state reminder (manual test)
  [ ] post-compact-reorient.sh — reorientation (manual test)
  [ ] post-compact-reorient.sh — correctly ignored non-compact source
  [ ] agent-file-reminder.sh — reminded agent about file output
  [ ] stop-task-check.sh — completion check (fires when you say "done")
  [ ] auto-format.sh — fired after file write
  [ ] file-protection.sh — BLOCKED unauthorized CLAUDE.md edit
  [ ] file-protection.sh — ALLOWED authorized edit
  [ ] flash-notification.sh — terminal bell + osascript notification

CONTEXT AWARENESS
  [ ] Status bar visible with context percentage
  [ ] Renders correctly (Unicode █/░ or ASCII #/- based on locale)

COMMIT ENFORCEMENT
  [ ] channel_commit.sh — commit succeeded
  [ ] Detected Python project type
  [ ] --local-verify mode worked

SPRINT PIPELINE
  [ ] /status — reported session state
  [ ] /grill — adversarial self-check completed
  [ ] spawn --check detected platform correctly
  [ ] spawn --dry-run showed full sequence

GOVERNANCE
  [ ] File protection blocked, then allowed with marker
  [ ] Protected files list installed

PLATFORM-SPECIFIC (macOS)
  [ ] BSD stat -f %m works
  [ ] GNU stat -c %Y fails gracefully
  [ ] osascript notification fired
  [ ] Unicode bar rendering under UTF-8 locale
  [ ] flash-notification.sh is macOS version (osascript)

AUTOMATED TEST SUITES
  [ ] test_anti_deferral.sh — X/X PASS
  [ ] test_session_orient.sh — X/X PASS
  [ ] test_agent_file_reminder.sh — X/X PASS
  [ ] test_pre_compact.sh — X/X PASS
  [ ] test_post_compact.sh — X/X PASS
  [ ] test_stop_task_check.sh — X/X PASS
  [ ] test_safe_commit.sh — X/X PASS
  [ ] test_channel_commit.sh — X/X PASS
  [ ] test_wait_for_results.sh — X/X PASS
  [ ] test_auto_format.sh — X/X PASS
  [ ] test_notification.sh — X/X PASS
  [ ] test_context_awareness_hook.sh — X/X PASS
  [ ] test_file_protection.sh — X/X PASS
  [ ] test_spawn.py — X/X PASS
```

Fill in every checkbox. For any NOT FIRED or FAIL, explain why and what the fix would be.

### 7. What's Next

After the report, tell me:
- Which features you think are most valuable for my workflow
- Any configuration I should tune
- How to start my next project with the full sprint pipeline (`/audit` → `/design` → `/build` → `/perfect` → `/finalize`)

Then stop — this will test the notification hook. I should hear a bell and see a macOS notification.
