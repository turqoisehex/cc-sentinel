# cc-sentinel

You are installing **cc-sentinel**, a modular governance package for Claude Code. This file instructs you to run an interactive setup conversation with the user.

## Installation Instructions

When the user installs this package (by saying "Install" followed by this repo's URL), follow these steps exactly:

### Step 1: Detect Environment

Before asking any questions, silently detect. Use built-in tools (Glob, Read) instead of Bash wherever possible — Bash triggers permission prompts, built-in tools do not:
- **OS:** Claude Code already knows the platform from session metadata (`win32`, `darwin`, `linux`). Confirm with one Bash call if needed: `uname -s` on Unix or check `$env:OS` on Windows. This is the only Bash call needed for detection (later steps require Bash for installer and setup script execution).
- **Existing .claude/:** Use Glob for `.claude/settings.json` and `~/.claude/settings.json`.
- **Git:** Use Glob for `.git/` in the current directory.
- **Project type:** Use Glob for `pubspec.yaml`, `package.json`, `Cargo.toml`, `go.mod`, `setup.py`, `pyproject.toml`, `Makefile`.
- **Existing hooks:** Use Read on `~/.claude/settings.json` (or `.claude/settings.json`). Check for `"hooks"` key.

### Step 2: Discovery Questions (one at a time, ALL mandatory)

Ask these questions one at a time. Wait for each answer before proceeding. Do NOT skip any question. Do NOT combine questions.

**Question 1 (MANDATORY):** "What do you use Claude Code for? (For example: software development, research, translation, writing, data analysis, or something else)"

**Question 2 (MANDATORY):** "Do you work on long, multi-step projects that span multiple sessions? The sprint pipeline (/audit -> /design -> /build -> /perfect -> /finalize) is designed for this."

**Question 3 (MANDATORY if git detected):** "Do you want commits to be verified automatically? cc-sentinel can run adversarial checks on every commit and block unverified code."

**Question 4 (MANDATORY):** "Would you like project-level install (just this project) or global install (all projects)?"
- Explain: Project = `.claude/` in this directory only. Good for trying it out.
- Global = `~/.claude/`. Applies to all projects. Recommended for most users.

### Step 3: Present Problem→Solution Table

Present ALL of these problems as a table. Do NOT filter or select a subset. Show every row:

| # | Problem | Solution |
|---|---------|----------|
| 1 | "It said it was done, but it wasn't." | Verification — up to 5-agent squad audits before completion |
| 2 | "It slammed into auto-compact and lost its work." | Context Awareness — visual status bar with 5 graduated warnings |
| 3 | "It deferred instead of fixing." | Core — anti-deferral hook scans every write |
| 4 | "After compaction, it forgot everything." | Core — CURRENT_TASK.md state survives compaction |
| 5 | "It committed untested code." | Commit Enforcement — tests, formatting, adversarial diff review |
| 6 | "Complex work has no structure." | Sprint Pipeline — structured /1 through /5 workflow |
| 7 | "It modified files it shouldn't." | Governance Protection — blocks mid-session edits to rules |
| 8 | "I walked away and missed the finish." | Notification — desktop alerts when done |

### Step 4: Recommend Modules

Referencing the problem table above, present the module selection table below. Always include Core.

| Module | What it solves | Recommended? |
|--------|---------------|-------------|
| Core | Context loss, deferral, state management | Always (required) |
| Context Awareness | Silent context window fill | Yes |
| Verification | Premature completion claims | Yes |
| Commit Enforcement | Unreviewed commits | Yes |
| Sprint Pipeline | Ad-hoc workflows | Yes |
| Governance Protection | Accidental rule modification | Yes |
| Notification | No alerts when done | Yes |

Present options in this exact order:
1. **All modules (Recommended)** — install everything
2. Individual module selection

Do NOT present individual selection first. "All modules" is the default. Auto-include dependencies (e.g., Sprint Pipeline requires Core + Verification + Commit Enforcement).

### Step 4b: Spawn Configuration (if Sprint Pipeline selected)


If Sprint Pipeline was selected, ask:

"The Sprint Pipeline includes `/spawn` for launching multiple Claude Code sessions in parallel. How long does Claude Code take to start on your machine? (This is the delay between launching `claude` and the REPL being ready for input. Default: 5 seconds, fast machines: 3 seconds)"

Store the answer as `spawn_startup_delay`. Default 5 if the user skips or says "default."

### Step 4c: Configure Permissions

Before running the installer or setup scripts, add allow rules to the target settings.json so cc-sentinel scripts execute without manual approval. Without these, every hook and script triggers a permission prompt — defeating the purpose of automation.

Determine the settings file:
- **Global:** `~/.claude/settings.json`
- **Project:** `.claude/settings.json`

Read the current settings.json (create `{"permissions":{"allow":[]}}` if it doesn't exist). Merge these entries into `permissions.allow` — never overwrite existing rules:

**Global install:**
```json
"Bash(bash ~/.claude/hooks/*)",
"Bash(bash ~/.claude/scripts/*)",
"Bash(bash ~/.claude/cc-context-awareness/*)",
"Bash(python3 ~/.claude/tools/*)",
"Bash(powershell *setup-codex*)",
"Bash(powershell -File *setup-codex*)",
"Bash(powershell -ExecutionPolicy Bypass *setup-codex*)",
"Bash(mkdir -p verification_findings/*)",
"Bash(mkdir -p verification_findings/*/*)",
"Bash(ls verification_findings/*)",
"Bash(ls verification_findings/*/*)"
```

**Project install:**
```json
"Bash(bash .claude/hooks/*)",
"Bash(bash scripts/*)",
"Bash(bash .claude/cc-context-awareness/*)",
"Bash(python3 ~/.claude/tools/*)",
"Bash(powershell *setup-codex*)",
"Bash(powershell -File *setup-codex*)",
"Bash(powershell -ExecutionPolicy Bypass *setup-codex*)",
"Bash(mkdir -p verification_findings/*)",
"Bash(mkdir -p verification_findings/*/*)",
"Bash(ls verification_findings/*)",
"Bash(ls verification_findings/*/*)"
```

Announce briefly: "Configuring permissions so cc-sentinel scripts run without manual approval..." then write the rules. No user prompt or confirmation needed — just the one-line announcement so it doesn't look like improvisation. The installer will also add these rules mechanically as a safety net.

### Step 4d: Dual-Architecture Verification (if Verification module selected)

If the Verification module was selected (directly or via dependency), ask:

"Do you want dual-architecture verification? This runs OpenAI Codex agents alongside Claude Sonnet during verification rounds. Different model architectures catch different bug classes — issues one model misses, the other catches. Requires an OpenAI account with Codex access (Plus, Pro, Team, or an API key with credits — check OpenAI's current pricing)."

Options: **Yes** / **No, Sonnet-only**

**If No:** Skip to Step 5. Codex is not installed; verification runs Sonnet-only.

**If Yes:** Run the setup script immediately (no further configuration questions — but the flow may pause for user action like running `codex login`). The script probes, installs if needed, and tests auth:

1. **Probe:** Run the platform-appropriate setup script:
   - **macOS/Linux:** `bash "<this-repo-path>/modules/verification/scripts/setup-codex.sh" --probe-only`
   - **Windows:** `powershell -ExecutionPolicy Bypass -File "<this-repo-path>/modules/verification/scripts/setup-codex.ps1" -Mode ProbeOnly`

2. **Handle probe result:**
   - `STATUS: FOUND` → proceed to auth verification (step 3)
   - `STATUS: NOT_FOUND` → attempt install:
     - **macOS/Linux:** `bash "<this-repo-path>/modules/verification/scripts/setup-codex.sh" --install`
     - **Windows:** `powershell -ExecutionPolicy Bypass -File "<this-repo-path>/modules/verification/scripts/setup-codex.ps1" -Mode Install`
   - Result handling:
     - `STATUS: FOUND` or `STATUS: INSTALLED` → proceed to auth verification (step 3)
     - `STATUS: INSTALL_NEED_SUDO` → tell user: "Codex needs elevated permissions to install globally. Run this in a separate terminal (not here — sudo needs a password prompt that Claude Code can't provide):" and show the `CMD:` line verbatim (e.g., `sudo npm install -g @openai/codex`). Do NOT prefix with `!` — sudo requires a real TTY for password entry. Wait for user to confirm they've run it, then re-run `--probe-only` on the same platform script. If FOUND → proceed to auth verification (step 3). If still NOT_FOUND → bail: "Codex installation didn't complete. You can finish later with `npm install -g @openai/codex && codex login`." Skip to Step 5.
     - `STATUS: INSTALL_NO_NODE` → tell user: "Codex requires Node.js. Run this in a separate terminal:" and show the `CMD:` line from output. "Once installed, type anything here and I'll retry." After user's next message: re-run `--install`. If still `INSTALL_NO_NODE` → bail: "Node.js isn't visible in the current session. Restart Claude Code after installing Node, then re-run the installer." Skip to Step 5.
     - `STATUS: INSTALL_FAILED` → tell user: "Codex installation didn't complete. You can set this up later by running `npm install -g @openai/codex && codex login`. Once installed, verify with: (Windows) `powershell -ExecutionPolicy Bypass -File "<this-repo-path>/modules/verification/scripts/setup-codex.ps1" -Mode VerifyAuth` or (macOS/Linux) `bash "<this-repo-path>/modules/verification/scripts/setup-codex.sh" --verify-auth`. Continuing without dual-architecture verification." Skip to Step 5.

3. **Verify auth:**
   - **macOS/Linux:** `bash "<this-repo-path>/modules/verification/scripts/setup-codex.sh" --verify-auth`
   - **Windows:** `powershell -ExecutionPolicy Bypass -File "<this-repo-path>/modules/verification/scripts/setup-codex.ps1" -Mode VerifyAuth`
   - Result handling:
     - `STATUS: AUTH_OK` → "Codex verified and working." Proceed to Step 5.
     - `STATUS: NOT_FOUND` → Codex binary not visible (stale PATH after install). Bail: "Codex installed but not visible in current session. Restart Claude Code, then re-run installer to complete setup." Skip to Step 5.
     - `STATUS: AUTH_FAILED` → tell user: "Codex needs authentication. Type this:" and show the `CMD:` line prefixed with `! ` (e.g., `! codex login`). Explain: "This opens a browser for OAuth. Let me know and I'll verify the connection." After user's next message (regardless of content), re-run `--verify-auth`. Do NOT say "press Enter when done" — on an empty prompt, Enter may do nothing or confuse the user.
     - Second auth failure → "Codex auth didn't complete. You can finish setup later with `codex login`, then verify with: (Windows) `powershell -ExecutionPolicy Bypass -File "<this-repo-path>/modules/verification/scripts/setup-codex.ps1" -Mode VerifyAuth` or (macOS/Linux) `bash "<this-repo-path>/modules/verification/scripts/setup-codex.sh" --verify-auth`. Continuing with Sonnet-only verification." Skip to Step 5.

**Design notes:**
- Never loop more than once on any step. Two failures = bail gracefully.
- The script handles OS-appropriate install paths internally.
- `INSTALL_NEED_SUDO` is Unix-only (macOS/Linux). On Windows, npm global installs go to `%AppData%` — no elevation needed, so the Windows script never emits this status.
- On macOS with Homebrew Node, no sudo needed (Homebrew prefix is user-writable). On Linux with system Node (apt/dnf/pacman), sudo is typical.
- **Never use `!` with `sudo`** — Claude Code's `!` prefix does not provide a PTY, so sudo cannot prompt for a password. Always direct the user to run sudo commands in a separate terminal.
- User-action pauses are sequential: install confirmation first (re-probe to confirm), then auth if needed. This ensures each step's success is verified before proceeding. Aim for minimal pauses (typically 0–2 total), not batching commands that depend on each other's success.

### Step 5: Run Installer

Reassure the user: "The installer merges additively — it will not overwrite or remove your existing hooks, skills, or settings (on reinstall, locally-modified files are preserved; use `-ForceOverwrite` to replace them with canonical versions). It also auto-configures permissions so cc-sentinel scripts run without manual approval."

Determine the correct installer command based on OS. Use the full path to the installer scripts in this repository (the directory containing this CLAUDE.md file):

**Windows:**
```powershell
powershell -ExecutionPolicy Bypass -File "<this-repo-path>/install.ps1" -Modules "<selected>" -Target "<target>"
```

**macOS/Linux:**
```bash
bash "<this-repo-path>/install.sh" --modules "<selected>" --target "<target>"
```

Replace `<this-repo-path>` with the absolute path to this cloned repository. For the initial install run, use only these arguments. Additional flags: `-DenyRules` / `--deny-rules` (Step 5c covers when to append this), `-ForceOverwrite` (forces replacement of locally-modified files — use when a previous install left stale files that should be updated to the canonical version). The `<selected>` value is a comma-separated list with NO spaces (e.g., `core,context-awareness,verification,commit-enforcement,sprint-pipeline,governance-protection,notification`).

### Step 5b: Configure Spawn (if Sprint Pipeline selected)

If Sprint Pipeline was installed and `spawn_startup_delay` was captured, write the startup delay to spawn config. Substitute the actual integer for `N` before running:

**macOS/Linux:**
```bash
SPAWN_DELAY=N python3 -c "
import json, pathlib, os
p = pathlib.Path.home() / '.claude' / 'tools' / 'spawn.json'
p.parent.mkdir(parents=True, exist_ok=True)
cfg = json.loads(p.read_text()) if p.exists() else {}
cfg['startup_delay'] = int(os.environ['SPAWN_DELAY'])
p.write_text(json.dumps(cfg, indent=2))
print('Spawn config written: startup_delay =', cfg['startup_delay'])
"
```

**Windows:**
```powershell
$env:SPAWN_DELAY = "N"; python -c "import json, pathlib, os; p = pathlib.Path.home() / '.claude' / 'tools' / 'spawn.json'; p.parent.mkdir(parents=True, exist_ok=True); cfg = json.loads(p.read_text()) if p.exists() else {}; cfg['startup_delay'] = int(os.environ['SPAWN_DELAY']); p.write_text(json.dumps(cfg, indent=2)); print('Spawn config written: startup_delay =', cfg['startup_delay'])"
```

Then run the setup command to auto-detect terminal and key sender:
- **macOS/Linux:** `python3 ~/.claude/tools/spawn.py --setup`
- **Windows:** `python ~/.claude/tools/spawn.py --setup`

### Step 5c: Review .claudeignore

After the installer runs, tell the user:

"**`.claudeignore` controls what Claude can see.** It works like `.gitignore` — matching files are excluded from Claude's context window. This matters because context is finite: every binary, build artifact, or media file Claude loads is space that could hold your actual code.

Based on your [detected project type] project, the installer created `.claudeignore` with these exclusions:"

Show the contents of the generated .claudeignore file.

"**Options:**
A) Keep this list (recommended for most projects)
B) Expand it — add common media/binary types (*.m4a, *.wav, *.sqlite, *.db, *.woff, *.ttf)
C) I'll customize it myself — just tell me where the file is
D) Something specific — tell me what patterns to add or remove"

If user picks A: proceed.
If user picks B: append `*.m4a`, `*.wav`, `*.ogg`, `*.flac`, `*.aac`, `*.sqlite`, `*.db`, `*.woff`, `*.woff2`, `*.ttf`, `*.otf` to the `.claudeignore` file.
If user picks C: say "Edit `.claudeignore` in your project root any time. It uses the same syntax as `.gitignore`."
If user picks D: make the requested changes.

**For global installs (`--target global`):** Skip `.claudeignore` generation. Instead, offer deny rules with this exact explanation:

"`.claudeignore` is project-level — no global equivalent. For global exclusions, deny rules in `~/.claude/settings.json` block the `Read()` tool from loading specific file types into context.

**Important:** Deny rules only block `Read()`. They do NOT block `Bash()` — Claude can still execute files, unzip archives, and process files with CLI tools. However, denying image formats (`*.png`, `*.jpg`) WILL block Claude's built-in image viewing and OCR, since those work through `Read()`.

**Conservative (Recommended):** Block media, video, archives, and binaries. Keep images and PDFs readable for OCR."

If they accept, re-run the installer with `--deny-rules` appended to the command. The installer handles the edit automatically (governance hooks do not block the installer's own settings writes):

**Windows:** append `-DenyRules` to the powershell command
**macOS/Linux:** append `--deny-rules` to the bash command

Do NOT include `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.webp`, `*.svg`, `*.pdf`, or `*.docx` — these are formats Claude can usefully read.

### Step 6: Inject CLAUDE.md Rules

After the installer completes, read `modules/core/claude-md-rules.md` and inject its contents into the user's CLAUDE.md:

1. Check if `CLAUDE.md` exists in the target (project root or `~/.claude/`).
2. If it exists, check if cc-sentinel rules are already present (search for `<!-- cc-sentinel rules start -->`).
3. If not present, append the rules block wrapped in delimiters:

```markdown
<!-- cc-sentinel rules start -->
[contents of claude-md-rules.md]
<!-- cc-sentinel rules end -->
```

4. If CLAUDE.md doesn't exist, create it with the rules block.

### Step 7: Plugin Suggestions

If the Sprint Pipeline module was installed, recommend complementary plugins. Present each with its purpose and install command. Do NOT modify settings.json — plugin installation requires the user to run `/plugins` themselves.

"The sprint pipeline works best with these community plugins. You can enable any of them with `/plugins`:"

- **superpowers** (`superpowers@claude-plugins-official`) — brainstorming, planning, TDD, verification workflows
- **context7** (`context7@claude-plugins-official`) — library documentation lookup
- **feature-dev** (`feature-dev@claude-plugins-official`) — guided feature development
- **pr-review-toolkit** (`pr-review-toolkit@claude-plugins-official`) — comprehensive PR review
- **claude-md-management** (`claude-md-management@claude-plugins-official`) — CLAUDE.md maintenance
- **ralph-loop** (`ralph-loop@claude-plugins-official`) — re-feed until completion
- **claude-code-setup** (`claude-code-setup@claude-plugins-official`) — automation recommendations

### Step 8: Run Self-Test

Skills installed during this session are not loadable until the next session — do NOT invoke `/self-test`. Instead, verify inline using built-in tools (Glob, Read) to avoid permission prompts:

1. Read settings.json — count hook event types and total hook entries.
2. Glob for hook files on disk (`~/.claude/hooks/*` or `.claude/hooks/*`) — count them (includes both `.sh` and `.ps1` hook files).
3. Glob for skill directories (`~/.claude/skills/*/SKILL.md` or `.claude/skills/*/SKILL.md`) — count them.
4. Read the target CLAUDE.md — search for `cc-sentinel rules start`.
5. Read settings.json — confirm `permissions.allow` contains cc-sentinel allow rules.
6. Glob for reference files on disk (`~/.claude/reference/*.md` or `.claude/reference/*.md`) — confirm key files are present. If verification module was installed: `verification-behavior.md`. If governance-protection was installed: `audit-pointer-rules.md`.

Present results as a table: each check PASS or FAIL with count. Exact counts depend on which modules were selected — do not compare to hardcoded expected values. Example format:

```
Hooks registered:   N/N PASS
Hook files on disk: N/N PASS
Skills:             N/N PASS
CLAUDE.md rules:    PASS
Permissions:        PASS
Reference files:    N/N PASS
```

### Step 9: Getting Started

Based on installed modules, suggest first commands:

- **Core only:** "Try `/cold` to see how CURRENT_TASK.md orientation works."
- **With Verification:** "Try `/grill` after your next piece of work to see adversarial self-checking."
- **With Sprint Pipeline:** "Start your next project with `/audit` to see the full pipeline."
- **With Context Awareness:** "Watch the status bar - it shows your context window usage in real time."

If all checks above PASS: Say "cc-sentinel is installed and verified. Your sessions are now governed."

If any check FAILs: Report the failures, suggest running `/self-test` in a new session to diagnose. Do NOT claim "verified" when checks failed.

## Uninstall

If the user asks to uninstall cc-sentinel, use the uninstaller — never manually `rm -rf`. Determine the correct command based on OS:

**macOS/Linux:**
```bash
bash "<this-repo-path>/uninstall.sh" --target "<target>"
```

**Windows:**
```powershell
powershell -ExecutionPolicy Bypass -File "<this-repo-path>/uninstall.ps1" -Target "<target>"
```

Replace `<this-repo-path>` with the cloned repo location (typically `~/.claude/cc-sentinel` or `/tmp/cc-sentinel`). If the repo was already deleted, clone it first:
```bash
git clone https://github.com/turqoisehex/cc-sentinel /tmp/cc-sentinel
bash /tmp/cc-sentinel/uninstall.sh --target global
```

Add `--dry-run` to preview what would be removed without removing it.
