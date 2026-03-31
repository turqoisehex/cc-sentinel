# cc-sentinel

You are installing **cc-sentinel**, a modular governance package for Claude Code. This file instructs you to run an interactive setup conversation with the user.

## Installation Instructions

When the user installs this package (by saying "Install" followed by this repo's URL), follow these steps exactly:

### Step 1: Detect Environment

Before asking any questions, silently detect. Use built-in tools (Glob, Read) instead of Bash wherever possible — Bash triggers permission prompts, built-in tools do not:
- **OS:** One Bash call: `uname -s` (macOS/Linux) or read `$env:OS` (Windows). This is the only Bash call needed.
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

Present ALL of these problems as a table. Do NOT filter or select a subset. Show all 8 rows:

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

Before running the installer, add allow rules to the target settings.json so cc-sentinel scripts execute without manual approval. Without these, every hook and script triggers a permission prompt — defeating the purpose of automation.

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
"Bash(mkdir -p verification_findings/*)",
"Bash(mkdir -p verification_findings/*/*)",
"Bash(ls verification_findings/*)",
"Bash(ls verification_findings/*/*)"
```

Do this silently — no user prompt needed. The installer will also add these rules mechanically as a safety net.

### Step 5: Run Installer

Reassure the user: "The installer merges additively — it will not overwrite or remove your existing hooks, skills, or settings. It also auto-configures permissions so cc-sentinel scripts run without manual approval."

Determine the correct installer command based on OS. Use the full path to the installer scripts in this repository (the directory containing this CLAUDE.md file):

**Windows:**
```powershell
powershell -File "<this-repo-path>/install.ps1" -Modules "<selected>" -Target "<target>"
```

**macOS/Linux:**
```bash
bash "<this-repo-path>/install.sh" --modules "<selected>" --target "<target>"
```

Replace `<this-repo-path>` with the absolute path to this cloned repository.

If Context Awareness is selected AND the OS is macOS or Linux, ask:
"For context-awareness, would you like to use the bundled version or install from the canonical repository (sdi2200262/cc-context-awareness)? The bundled version works on all platforms. The canonical version is maintained by the original author."

Add `--context-source canonical` or `--context-source bundled` accordingly. On Windows, always use bundled (only known working Windows version).

### Step 5b: Configure Spawn (if Sprint Pipeline selected)

If Sprint Pipeline was installed and `spawn_startup_delay` was captured, write the startup delay to spawn config:

```bash
python3 -c "
import json, pathlib
p = pathlib.Path.home() / '.claude' / 'tools' / 'spawn.json'
p.parent.mkdir(parents=True, exist_ok=True)
cfg = json.loads(p.read_text()) if p.exists() else {}
cfg['startup_delay'] = DELAY
p.write_text(json.dumps(cfg, indent=2))
print('Spawn config written: startup_delay = DELAY')
"
```

Replace `DELAY` with the integer value from the user's answer.

Then run `python3 ~/.claude/tools/spawn.py --setup` to auto-detect terminal and key sender.

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

If they accept, add ONLY these deny rules (no images, no PDFs):
```json
"permissions": {
  "deny": [
    "Read(*.mp3)", "Read(*.mp4)", "Read(*.avi)", "Read(*.mkv)", "Read(*.mov)",
    "Read(*.wav)", "Read(*.flac)", "Read(*.aac)", "Read(*.ogg)",
    "Read(*.zip)", "Read(*.tar.gz)", "Read(*.tar.bz2)", "Read(*.rar)", "Read(*.7z)",
    "Read(*.exe)", "Read(*.dll)", "Read(*.so)", "Read(*.dylib)"
  ]
}
```

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
2. Glob for hook files on disk (`~/.claude/hooks/*.sh` or `.claude/hooks/*.sh`) — count them.
3. Glob for skill directories (`~/.claude/skills/*/SKILL.md` or `.claude/skills/*/SKILL.md`) — count them.
4. Read the target CLAUDE.md — search for `cc-sentinel rules start`.
5. Read settings.json — confirm `permissions.allow` contains cc-sentinel allow rules.

Present results as a table: each check PASS or FAIL with count. Example:

```
Hooks registered:  16/16 PASS
Hook files on disk: 15/15 PASS
Skills:            23/23 PASS
CLAUDE.md rules:   PASS
Permissions:       PASS
```

### Step 9: Getting Started

Based on installed modules, suggest first commands:

- **Core only:** "Try `/cold` to see how CURRENT_TASK.md orientation works."
- **With Verification:** "Try `/grill` after your next piece of work to see adversarial self-checking."
- **With Sprint Pipeline:** "Start your next project with `/audit` to see the full pipeline."
- **With Context Awareness:** "Watch the status bar - it shows your context window usage in real time."

Say: "cc-sentinel is installed and verified. Your sessions are now governed."

## Uninstall

If the user asks to uninstall cc-sentinel, use the uninstaller — never manually `rm -rf`. Determine the correct command based on OS:

**macOS/Linux:**
```bash
bash "<this-repo-path>/uninstall.sh" --target "<target>"
```

**Windows:**
```powershell
powershell -File "<this-repo-path>/uninstall.ps1" -Target "<target>"
```

Replace `<this-repo-path>` with the cloned repo location (typically `~/.claude/cc-sentinel` or `/tmp/cc-sentinel`). If the repo was already deleted, clone it first:
```bash
git clone https://github.com/turqoisehex/cc-sentinel /tmp/cc-sentinel
bash /tmp/cc-sentinel/uninstall.sh --target global
```

Add `--dry-run` to preview what would be removed without removing it.
