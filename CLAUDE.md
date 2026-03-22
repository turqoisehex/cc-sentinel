# cc-sentinel

You are installing **cc-sentinel**, a modular governance package for Claude Code. This file instructs you to run an interactive setup conversation with the user.

## Installation Instructions

When the user installs this package (by saying "Install" followed by this repo's URL), follow these steps exactly:

### Step 1: Detect Environment

Before asking any questions, silently detect:
- **OS:** Check `uname -s` or PowerShell `$env:OS`. Determine Windows/macOS/Linux.
- **Existing .claude/:** Check if `.claude/` exists in the current project and `~/.claude/` exists globally.
- **Git:** Check if this is a git repository (`git rev-parse --is-inside-work-tree`).
- **Project type:** Look for `pubspec.yaml` (Flutter), `package.json` (Node.js), `Cargo.toml` (Rust), `go.mod` (Go), `setup.py`/`pyproject.toml` (Python), `Makefile`.
- **Existing hooks:** Check if `.claude/settings.json` or `~/.claude/settings.json` already has hooks configured.

### Step 2: Discovery Questions (one at a time)

Ask these questions one at a time. Wait for each answer before proceeding.

**Question 1:** "What do you use Claude Code for? (For example: software development, research, translation, writing, data analysis, or something else)"

**Question 2:** "Do you work on long, multi-step projects that span multiple sessions? The sprint pipeline (/audit -> /design -> /build -> /perfect -> /finalize) is designed for this."

**Question 3:** (Only if git detected) "Do you want commits to be verified automatically? cc-sentinel can run adversarial checks on every commit and block unverified code."

**Question 4:** "Would you like project-level install (just this project) or global install (all projects)?"
- Explain: Project = `.claude/` in this directory only. Good for trying it out.
- Global = `~/.claude/`. Applies to all projects. Good once you want it everywhere.

### Step 3: Present Pain Points

Based on their answers, present 3-5 of these problems that are most relevant:

1. "It said it was done, but it wasn't." -> Verification module
2. "It lost track mid-session." -> Context Awareness module
3. "It deferred instead of fixing." -> Core (anti-deferral hook)
4. "It modified files it shouldn't." -> Governance Protection module
5. "I walked away and missed the finish." -> Notification module
6. "After compaction, it forgot everything." -> Core (compaction hooks)
7. "It committed untested code." -> Commit Enforcement module
8. "Every session starts from scratch." -> Core (CURRENT_TASK protocol)
9. "I make the same corrections repeatedly." -> Governance Protection (/mistake, /prune-rules)
10. "Complex work has no structure." -> Sprint Pipeline module

For each problem: describe it in one sentence, then say "cc-sentinel fixes this with [specific mechanism]."

### Step 4: Recommend Modules

Based on answers, recommend modules. Always include Core. Show a table:

| Module | What it solves | Recommended? |
|--------|---------------|-------------|
| Core | Context loss, deferral, state management | Always (required) |
| Context Awareness | Silent context window fill | Yes if multi-step work |
| Verification | Premature completion claims | Yes if quality matters |
| Commit Enforcement | Unreviewed commits | Yes if using git |
| Sprint Pipeline | Ad-hoc workflows | Yes if multi-step projects |
| Governance Protection | Accidental rule modification | Yes if using rules |
| Notification | No alerts when done | Yes (low cost) |

Let the user select. Auto-include dependencies (e.g., Sprint Pipeline requires Core + Verification).

### Step 5: Run Installer

Determine the correct installer command based on OS:

**Windows:**
```powershell
powershell -File install.ps1 -Modules "<selected>" -Target "<target>" -BarStyle "<style>"
```

**macOS/Linux:**
```bash
bash install.sh --modules "<selected>" --target "<target>" --bar-style "<style>"
```

If Context Awareness is selected AND the OS is macOS or Linux, ask:
"For context-awareness, would you like to use the bundled version or install from the canonical repository (sdi2200262/cc-context-awareness)? The bundled version works on all platforms. The canonical version is maintained by the original author."

Add `--context-source canonical` or `--context-source bundled` accordingly. On Windows, always use bundled (only known working Windows version).

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

If the Sprint Pipeline module was installed, suggest recommended plugins:

"The sprint pipeline works best with these community plugins. Would you like me to enable them?"

- **superpowers** - brainstorming, planning, TDD, verification workflows
- **context7** - library documentation lookup
- **feature-dev** - guided feature development
- **pr-review-toolkit** - comprehensive PR review
- **claude-md-management** - CLAUDE.md maintenance
- **ralph-loop** - re-feed until completion
- **claude-code-setup** - automation recommendations

If the user agrees, update `enabledPlugins` in their settings.json. If that fails, tell them to run `/plugins` and enable manually.

### Step 8: Run Self-Test

Run `/self-test` to verify the installation.

### Step 9: Getting Started

Based on installed modules, suggest first commands:

- **Core only:** "Try `/cold` to see how CURRENT_TASK.md orientation works."
- **With Verification:** "Try `/grill` after your next piece of work to see adversarial self-checking."
- **With Sprint Pipeline:** "Start your next project with `/audit` to see the full pipeline."
- **With Context Awareness:** "Watch the status bar - it shows your context window usage in real time."

Say: "cc-sentinel is installed and verified. Your sessions are now governed."
