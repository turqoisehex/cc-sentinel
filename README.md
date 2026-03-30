# cc-sentinel

[![CI](https://github.com/turqoisehex/cc-sentinel/actions/workflows/ci.yml/badge.svg)](https://github.com/turqoisehex/cc-sentinel/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/turqoisehex/cc-sentinel)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/turqoisehex/cc-sentinel?style=social)](https://github.com/turqoisehex/cc-sentinel)

**Governance infrastructure for Claude Code.** Hooks, agents, and workflows that prevent the failure modes autonomous coding sessions actually hit.

## The Problem

Claude Code is powerful out of the box. But long, autonomous sessions surface real failure modes that no amount of prompting fixes:

| Failure Mode | What Happens | Without cc-sentinel | With cc-sentinel |
|---|---|---|---|
| **Context loss** | After compaction, Claude forgets what it was doing, repeats work, or contradicts earlier decisions | Hours of wasted compute, inconsistent output | Pre-compact hook saves state; post-compact hook restores it. Sessions survive compaction. |
| **Work deferral** | Claude writes "TODO: implement later" or "will add in next step" and never returns | Incomplete features shipped as "done" | Anti-deferral hook detects deferral language in every file write and warns immediately. |
| **False completion** | Claude claims a task is done without verifying | Bugs discovered in production, not development | Stop hook blocks completion claims without verification squad evidence on disk. |
| **Governance drift** | Claude edits its own rules, CLAUDE.md, or config files mid-session | Guardrails silently disabled | File-protection hook blocks writes to protected files. Override requires explicit authorization marker. |
| **Silent compaction** | Context window fills with no warning; state is lost before it can be saved | Unrecoverable mid-task failure | Visual status bar + 5 graduated warnings at 50/65/75/85/92%. |
| **Commit quality** | Large diffs committed without review; tests skipped; formatting inconsistent | Technical debt accumulates per-session | Code commits gated: two adversarial agents review the diff, tests auto-run, formatter auto-runs. Doc-only and config changes pass through lightweight checks. |
| **Agent amnesia** | Subagents start with no knowledge of project conventions or current task state | Agents produce work that contradicts the session | Agent-file-reminder hook injects context. Channel system coordinates parallel agents via file signals. |

cc-sentinel solves these with **hooks that enforce automatically** -- not rules that rely on Claude choosing to follow them.

## How It Works

cc-sentinel is a modular set of Claude Code hooks, slash commands, reference docs, agents, and templates. You install the modules you need. The installer is a conversation -- Claude Code reads your project and recommends what to install.

```
Claude Code: I see this is a Python/Django project with pytest. Here's what I recommend:

  [x] Core (required) -- context loss prevention, anti-deferral, state management
  [x] Context Awareness -- visual context meter in your status bar
  [ ] Verification -- up to 5-agent verification squad before completion claims
  [x] Commit Enforcement -- test gating, auto-format, diff review
  [ ] Sprint Pipeline -- structured /1 through /5 workflow
  [x] Governance Protection -- protect CLAUDE.md and config from mid-session edits
  [x] Notification -- desktop alert when Claude finishes or needs input

Install these 5 modules? (Y/n)
```

### Beyond Code

cc-sentinel's governance works for any Claude Code workflow, not just software engineering:

- **Translation projects** -- Anti-deferral catches "will revisit phrasing later." Verification squad audits consistency across documents. Context awareness prevents mid-chapter compaction.
- **Research workflows** -- State files preserve literature review progress across sessions. Commit enforcement gates research notes through adversarial review. Sprint pipeline structures the research-to-synthesis arc.
- **Data analysis** -- Channel system coordinates parallel analysis streams. Pre-compact hooks save intermediate results. Stop hook prevents premature "analysis complete" claims.

If Claude Code can do it, cc-sentinel can govern it.

## Installation

**Prerequisites:** Node.js, Git, jq, and Python 3. See [Platform Setup](#platform-setup) for one-command install per platform.

**In any Claude Code session:**

```
Install https://github.com/turqoisehex/cc-sentinel
```

Claude Code clones the repo and runs an interactive installer. The expected flow:

1. **Detect** your OS, shell, terminal, and project type. Report findings.
2. **Ask your use case** -- what you use Claude Code for (development, research, writing, etc.).
3. **Present a problem→solution table** showing each failure mode and the module that solves it.
4. **Present a module table** with recommendations. Always offer "All modules" as the first option.
5. **Ask about global vs project install.** Recommend global for most users.
6. **Run the installer** with the selected modules. Do not ask for confirmation after module selection -- just run it.
7. **Offer deny rules** for binary/media file exclusions (conservative: block media/archives/binaries, keep images and PDFs readable).
8. **Suggest plugins** that complement cc-sentinel (superpowers, context7, feature-dev).
9. **Print a summary** of what was installed: modules, hooks, commands, status line, spawn config.
10. **Tell the user to run `/self-test`** in their next session to validate.

**Manual installation:**

```bash
# Clone
git clone https://github.com/turqoisehex/cc-sentinel.git ~/.claude/cc-sentinel

# Install to current project (recommended)
bash ~/.claude/cc-sentinel/install.sh --modules "core,context-awareness,verification" --target project

# Or install globally
bash ~/.claude/cc-sentinel/install.sh --modules "core,context-awareness" --target global

# Windows (PowerShell)
powershell -File ~/.claude/cc-sentinel/install.ps1 -Modules "core,context-awareness" -Target project
```

## Modules

### Core (required)

Prevents the three most common failure modes: context loss, work deferral, and agent amnesia.

| Hook | Event | What It Does |
|---|---|---|
| `anti-deferral.sh` | PreToolUse | Scans every file write for deferral language ("TODO later", "will implement", "future sprint"). Injects a warning into Claude's context requiring explicit developer approval before deferral. |
| `session-orient.sh` | SessionStart | Injects CURRENT_TASK.md contents at session start so Claude has full context from turn one. |
| `pre-compact-state-save.sh` | PreCompact | Last-chance hook before context compaction. Reminds Claude to write all in-progress state to CURRENT_TASK.md. |
| `post-compact-reorient.sh` | SessionStart (compact) | After compaction, re-injects task state so Claude can resume without re-reading files. |
| `agent-file-reminder.sh` | PreToolUse | Reminds agents to write results to files, not just return them in memory (which is lost after the agent exits). |

Also includes:
- **CURRENT_TASK.md template** -- structured state file that survives compaction
- **Channel template** -- for multi-agent parallel work
- **Operator cheat sheet** -- quick reference for all commands
- **`/self-test`** -- diagnostic command that validates your installation

### Context Awareness

Visual context window meter displayed in your Claude Code status bar. Graduated warnings fire as context fills, prompting Claude to save state before compaction hits.

```
context [████████████░░░░░░░░] 62%
```

Thresholds trigger automatic reminders:
- **50%** -- "Documenting as you go?"
- **65%** -- "Could a fresh session resume from your state files?"
- **75%** -- "Document comprehensively and get cold-start ready. Continue working methodically until compaction at ~84%."
- **85%** -- "Commit all changes. State files must be current."
- **92%** -- "Auto-compaction imminent. State files must be complete."

This benefits **Claude Code itself** as much as the user. Without context awareness, Claude has no way to know how full its context window is — it cannot sense compaction approaching. The graduated warnings give Claude actionable signals to save state, wrap up work units, and prepare for compaction before it happens. The user gets visibility too, but the primary consumer is Claude's own decision-making.

Auto-detects terminal Unicode support. Falls back to ASCII (`#`/`-`) when the locale does not indicate UTF-8.

**Windows support:** cc-sentinel includes the only known Windows-compatible version of cc-context-awareness. On macOS/Linux, you can choose between the bundled version or the [canonical repository](https://github.com/sdi2200262/cc-context-awareness).

### Verification

Up to 5-agent verification squad that independently audits work before any completion claim. Each agent has a different adversarial perspective:

| Agent | What It Catches |
|---|---|
| **Mechanical Auditor** | Wrong file paths, constants, enum values, counts, performance issues -- anything greppable |
| **Adversarial Reader** | Spec contradictions, hallucinated content, rule violations, regressions |
| **Completeness Scanner** | Missing requirements, unassigned items, spec gaps |
| **Dependency Tracer** | Missing migrations, untraced call sites, silent default changes |
| **Cold Reader** | Semantic errors invisible to the author -- reads with zero context |

The `stop-task-check.sh` hook fires when Claude tries to stop, requiring verification evidence before allowing completion claims through. Self-attestation ("I verified this") is explicitly rejected -- the hook checks for actual squad output files on disk.

Commands: `/verify`, `/grill` (iterative self-challenge)

### Commit Enforcement

Code commits are gated: tests must pass, formatting must be clean, and two verification agents review the diff before it lands. Documentation-only and config changes pass through lightweight checks without full agent review.

| Component | What It Does |
|---|---|
| `safe-commit.sh` | Runs tests (auto-detects: npm, pytest, cargo, go, flutter, make), blocks on failure |
| `auto-format.sh` | Runs formatter (prettier, black, cargo fmt, dart format, gofmt) on every file write |
| `channel_commit.sh` | Orchestrates: stage, verify, test, format, commit. The single public API for commits. |
| `commit-adversarial.md` | Agent that reviews staged diff for logic errors, spec violations, regressions |
| `commit-cold-reader.md` | Agent that reads staged diff with zero context -- flags anything broken or nonsensical |

Multi-framework auto-detection: the commit hooks detect your project type from manifest files (`package.json`, `Cargo.toml`, `go.mod`, `pubspec.yaml`, `pyproject.toml`, `Makefile`) and run the appropriate test suite and formatter.

**Single-terminal mode:** Works without a Sonnet listener. When no Sonnet heartbeat is detected, the system automatically falls back to local verification — no 5-minute hang, no manual flags needed.

Also supports **multi-channel coordination** for parallel Opus/Sonnet workflows via `SENTINEL_CHANNEL` environment variable.

### Sprint Pipeline

Structured workflow phases for complex features. Each phase has a slash command:

| Command | Phase | Purpose |
|---|---|---|
| `/1` or `/audit` | Audit | Assess current state, identify gaps |
| `/2` or `/design` | Design | Brainstorm, spec, plan, classify tasks |
| `/3` or `/build` | Build | Automated execution of classified plan |
| `/4` or `/perfect` | Perfect | Quality pass, edge cases, polish |
| `/5` or `/finalize` | Finalize | Verification squad, cleanup, completion |

**Example workflow:**

```
You: /2
Claude: [Brainstorms with you, writes spec, creates implementation plan,
         classifies tasks as Opus/Sonnet/Agent, adversarial plan review,
         presents for your approval]

You: /3
Claude: [Executes plan task by task. Commits at phase boundaries.
         Two agents verify every commit. No manual intervention needed.]

You: /4
Claude: [Reads everything fresh. Finds edge cases, inconsistencies,
         quality issues. Fixes them. "Scrap and rewrite" pass.]

You: /5
Claude: [Runs verification squad. Produces final report.
         Cleans up session artifacts. Ready to ship.]
```

Additional Sprint Pipeline commands: `/opus` (channel management), `/sonnet` (Sonnet dispatch), `/rewrite` (content rewrite pipeline), `/spawn` (multi-session launcher).

Core utility commands (available without Sprint Pipeline): `/cold` (cold-start resume), `/cleanup` (session cleanup), `/status` (progress overview).

Recommends complementary Claude Code plugins: superpowers, context7, feature-dev, pr-review-toolkit, claude-md-management, ralph-loop, claude-code-setup. The installer lists each plugin's purpose and install command -- it does not auto-install them.

### Governance Protection

Prevents Claude from editing its own rules mid-session.

- **`file-protection.sh`** -- PreToolUse hook that blocks writes to protected files (CLAUDE.md, settings.json, etc.)
- **Override mechanism** -- Add `GOVERNANCE-EDIT-AUTHORIZED` to CURRENT_TASK.md to temporarily allow edits (creates an audit trail)
- **`/mistake`** -- Structured correction capture that adds to CLAUDE.md's accumulated corrections
- **`/prune-rules`** -- Maintains correction list under soft cap (prevents rule bloat)

### Notification

Desktop alerts when Claude Code completes a task or needs your input. Platform-native:

- **macOS** -- osascript notification + terminal bell
- **Linux** -- notify-send (libnotify) + terminal bell
- **Windows** -- FlashWindowEx taskbar flash + console beeps (uses .NET, pre-installed on Windows 10+; targets Windows Terminal)

## Self-Test

After installation, run `/self-test` to validate your setup. It checks:

- Hooks are registered in settings.json AND their files exist on disk
- Command files are present for each installed module
- Reference files are present for each installed module
- Templates exist (CURRENT_TASK.md or current-task-template.md)
- CLAUDE.md contains cc-sentinel behavioral rules
- Working directory (`verification_findings/`) exists and is gitignored
- Skills are installed for applicable modules
- Auto-invoke rules are present (`.claude/rules/plugin-auto-invoke.md`)

If anything fails, `/self-test` reports exactly what's wrong and how to fix it.

## Project vs Global Install

| | Project (`--target project`) | Global (`--target global`) |
|---|---|---|
| **Location** | `.claude/` in project root | `~/.claude/` |
| **Scope** | This project only | All Claude Code sessions |
| **Recommended for** | Teams, project-specific config | Solo developers, personal defaults |
| **Hook paths** | Relative (`.claude/hooks/...`) | Absolute (`~/.claude/hooks/...`) |

Most users should start with **project install**. Global install is useful for personal defaults you want everywhere.

## Configuration

### Module Selection

Install only what you need. Dependencies are resolved automatically:

```
core (required)
  +-- context-awareness
  +-- verification
  |     +-- commit-enforcement (requires verification)
  |           +-- sprint-pipeline (requires all above)
  +-- governance-protection
  +-- notification
```

### .claudeignore

The installer generates a `.claudeignore` file tuned to your project type (Flutter, Node, Python, Rust, Go) to keep large build artifacts out of Claude's context window.

### Protected Files

By default, `CLAUDE.md` and `settings.json` are protected. Edit `protected-files.txt` to customize:

```
CLAUDE.md
settings.json
```

## Architecture

```
cc-sentinel/
  CLAUDE.md              # Interactive installer (conversation script)
  install.sh             # Unix installer
  install.ps1            # Windows installer
  modules.json           # Module manifest (metadata, dependencies, hook registration)
  modules/
    core/                # Required -- hooks, templates, /cold, /cleanup, /status
    context-awareness/   # Status bar meter, graduated warnings
    verification/        # up to 5-agent squad, /verify, /grill
    commit-enforcement/  # safe-commit, auto-format, channel routing
    sprint-pipeline/     # /1-/5 workflow, /spawn multi-session
    governance-protection/ # file-protection, /mistake, /prune-rules
    notification/        # Platform-native desktop alerts
  templates/
    claudeignore/        # Per-framework .claudeignore templates
```

Each module contains some combination of:
- `hooks/` -- Shell scripts registered in settings.json
- `commands/` -- Slash commands (`.claude/commands/`)
- `reference/` -- Documentation injected into context
- `agents/` -- Agent definitions (`.claude/agents/`)
- `scripts/` -- Utility scripts copied to project root
- `skills/` -- Claude Code skills
- `templates/` -- Project root templates

## Methodology

cc-sentinel implements the workflow principles documented by Boris Cherny -- creator of Claude Code at Anthropic, previously Principal Engineer (IC8) at Meta, author of *Programming TypeScript*. Cherny ships exclusively through Claude Code, routinely producing 10-30 PRs per day. His publicly documented workflow tips have tens of millions of views. cc-sentinel takes what he describes as discipline and makes it infrastructure.

### Verification is non-negotiable

> "Probably the most important thing to get great results out of Claude Code." -- Cherny

Claude's self-assessment of its own work is structurally unreliable. Cherny's workflow embeds adversarial two-layer code review, tests-first development, and stop hooks that block exit on test failure. His `/code-review` command spawns multiple parallel subagents checking style, history, and bugs -- then several more specifically tasked with *challenging* those findings.

> "Say 'Grill me on these changes and don't make a PR until I pass your test.'" -- Cherny

**cc-sentinel enforcement:** `stop-task-check.sh` blocks completion claims without verification evidence on disk. Up to six independent verification agents (mechanical, adversarial, completeness, dependency, cold-reader, performance) audit in parallel. Per-commit adversarial and cold reader agents check every commit. `/grill` provides iterative adversarial self-challenge. Self-attestation is explicitly rejected -- the stop hook checks for actual output files, not Claude's claim that it verified.

### Context is infrastructure, not conversation

Context window degradation is the most consistent failure mode in agentic AI work. Cherny's entire session architecture is designed around this reality: parallel sessions, subagent offloading, lean CLAUDE.md, glob/grep over RAG.

> "Offload individual tasks to subagents to keep your main agent's context window clean and focused." -- Cherny

His team tried vector databases, recursive model-based indexing, and other approaches. Plain filesystem search (glob/grep) driven by the model beat everything.

**cc-sentinel enforcement:** `cc-context-awareness` provides a visual status bar with graduated warnings at 50/65/75/85/92%. Pre-compact hooks force state documentation. Post-compact hooks restore it. The CURRENT_TASK protocol creates complete cold-start survival documents. The channel system enables multi-session parallel execution with file-signal coordination. Cherny accepts ~10-20% session abandonment as the cost of doing business. cc-sentinel's compaction hooks make sessions recoverable instead of disposable.

### Every mistake becomes a rule

> "Claude writes its own correction rules when asked and is eerily good at doing so." -- Cherny

Combined with team-wide PR reviews that update shared CLAUDE.md files in real time, this creates what Dan Shipper calls "Compounding Engineering" -- a system that improves through accumulating project-specific knowledge.

**cc-sentinel enforcement:** `/mistake` provides structured capture: describe the error, search existing rules, strengthen or add, check soft cap, commit. `/prune-rules` provides periodic review with git blame dates, trigger counts, and keep/update/remove recommendations. `anti-deferral.sh` catches when Claude tries to punt known issues. `file-protection.sh` prevents accidental corruption of accumulated rules.

### Build for the model six months from now

> "At Anthropic, we don't build for the model of today, we build for the model of six months from now." -- Cherny

Current-generation models can run autonomously for hours to days, and each generation extends this further. Rules should be revisable. CLAUDE.md should be pruned with each model release.

**cc-sentinel enforcement:** Modular architecture -- install only what the current model needs, remove modules as models improve. `/prune-rules` structures the pruning process with git blame dates and trigger analysis, providing evidence for each rule: when was it last triggered? Has the model improved past it? `/self-test` verifies installation integrity after changes.

### Pour energy into the plan

> "Pour your energy into the plan so Claude can one-shot the implementation." -- Cherny

> "Knowing everything you know now, scrap this and implement the elegant solution." -- Cherny

Every session starts in Plan mode. For complex features, Cherny uses `/feature-dev` -- Claude asks what he wants, builds a specification, creates a detailed plan, then proceeds step by step. For high-stakes plans, he spawns a second Claude instance to review the plan "as a staff engineer."

**cc-sentinel enforcement:** `/design` (alias `/2`) structures the path: brainstorm, spec, plan, adversarial plan review, user approval gate. `/build` (alias `/3`) executes approved plans with verification at each step. `/perfect` (alias `/4`) provides the systematic "scrap and rewrite" pass. Plan-first is not optional -- the sprint pipeline makes plan, build, verify the only path.

### Where cc-sentinel extends beyond

| Capability | Cherny's approach | cc-sentinel |
|---|---|---|
| Context monitoring | Not mentioned | Visual meter + 5 graduated warning tiers |
| Compaction survival | "Abandon degraded sessions" | Pre/post-compact hooks preserve and restore state |
| Anti-deferral | Not mentioned | Hook detects deferral language, requires developer approval |
| Governance protection | Not mentioned | Protected files list + authorization marker protocol |
| Cold-start protocol | CLAUDE.md as ground truth | CURRENT_TASK as complete cold-start survival document |
| Multi-channel coordination | Parallel sessions (independent) | File-signal coordination between orchestrator + executor |
| Verification depth | 2-layer review (check + challenge) | Up to 5 independent agents + per-commit agents + stop hook gate |
| Plan enforcement | Plan mode discipline (manual) | /design forces brainstorm, spec, adversarial review, user gate |
| Completion loops | ralph-loop plugin (re-feed until done) | Stop hook + verification evidence gate + anti-deferral hook (three independent mechanisms) |
| Permission model | Pre-approved allow list (manual) | Same + file-protection hook for governance files + authorization marker protocol |

## Platform Setup

cc-sentinel needs Claude Code, Git, bash, jq, and Python 3. Most platforms have some of these already. The commands below install everything missing.

### Windows

Fresh Windows 10/11 machine -- two commands install everything:

```powershell
winget install --source winget Microsoft.WindowsTerminal Git.Git jqlang.jq Python.Python.3.12 OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
```

**Close and reopen your terminal after this** (PATH updates require a new session), then:

```powershell
npm install -g @anthropic-ai/claude-code
```

This gives you: Windows Terminal, Git Bash (provides bash), jq, Python 3, Node.js (provides npm), and Claude Code.

Windows 11 ships with Windows Terminal pre-installed. winget skips packages that are already installed, so including it is harmless.

### macOS

Fresh Mac -- install Homebrew first, then everything else:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install node jq && npm install -g @anthropic-ai/claude-code
```

macOS Catalina+ includes Python 3, Git, and bash, so only Node.js and jq need to be installed via Homebrew.

If you already have Homebrew, skip the first line. Check what you have: `brew --version && node -v && jq --version`.

### Linux (Debian/Ubuntu)

```bash
sudo apt update && sudo apt install -y nodejs npm jq python3 git && npm install -g @anthropic-ai/claude-code
```

For Node.js 18+ (required by Claude Code), you may need the [NodeSource repository](https://github.com/nodesource/distributions#installation-instructions) if your distro ships an older version:

```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt install -y nodejs
```

### Linux (Fedora/RHEL)

```bash
sudo dnf install -y nodejs npm jq python3 git && npm install -g @anthropic-ai/claude-code
```

### Linux (Arch)

```bash
sudo pacman -S nodejs npm jq python git && npm install -g @anthropic-ai/claude-code
```

### Verify Prerequisites

The cc-sentinel installer checks for `jq`, `python3`, and `bash` before proceeding and exits with specific install instructions if anything is missing. After installing cc-sentinel, run `/self-test` to validate everything is wired up.

### Tested On

| Platform | Version | Architecture |
|---|---|---|
| macOS | 15.2 Sequoia | x86_64 |
| Linux | Mint 22.3 | x86_64 |
| Windows | 10 Pro 10.0.19045 | x86_64 |

Both installers (`install.sh` for Unix, `install.ps1` for Windows) handle platform differences automatically. Windows hooks normalize CRLF via `tr -d '\r'` on jq output. The bundled context-awareness module is the only known Windows-compatible version.

## Uninstalling

The uninstaller removes all cc-sentinel files, cleans hook and permission entries from settings.json, strips the rules block from CLAUDE.md, and removes empty directories. Your non-sentinel hooks, settings, and CLAUDE.md content are preserved.

**From a Claude Code session:**

```
Uninstall cc-sentinel
```

Claude reads the CLAUDE.md uninstall instructions and runs the appropriate command.

**Manual (macOS/Linux):**

```bash
# If you still have the repo cloned:
bash ~/.claude/cc-sentinel/uninstall.sh --target global

# If the repo was deleted, clone it first:
git clone https://github.com/turqoisehex/cc-sentinel /tmp/cc-sentinel
bash /tmp/cc-sentinel/uninstall.sh --target global

# Preview what would be removed without removing it:
bash ~/.claude/cc-sentinel/uninstall.sh --target global --dry-run
```

**Manual (Windows PowerShell):**

```powershell
powershell -File "$env:USERPROFILE\.claude\cc-sentinel\uninstall.ps1" -Target global

# Or with dry run:
powershell -File "$env:USERPROFILE\.claude\cc-sentinel\uninstall.ps1" -Target global -DryRun
```

Replace `global` with `project` if you installed to `.claude/` in a specific project directory.

Restart Claude Code after uninstalling for changes to take effect.

## FAQ

**Does this replace CLAUDE.md?**
No. cc-sentinel adds rules to your existing CLAUDE.md (with clear delimiters) and registers hooks in settings.json. Your existing configuration is preserved.

**Can I uninstall cc-sentinel?**
Yes. See [Uninstalling](#uninstalling) below. The uninstaller removes all sentinel files, cleans hooks and allow rules from settings.json, and strips the rules block from CLAUDE.md.

**Does this work with Claude Code plugins?**
Yes. cc-sentinel hooks and plugins coexist. The sprint-pipeline module recommends complementary plugins but does not require them.

**What about performance?**
Most hooks add 5-15ms per tool call on macOS/Linux (shell startup + jq parse). Windows (Git Bash) overhead is higher but still sub-second. The auto-format hook runs only on file writes and formats only the changed file. Context awareness adds a status line update. None are perceptible during normal use.

**Can I use this with a team?**
Yes. Project install (`.claude/`) commits to your repo, so the whole team gets the same governance. Add `.claude/` to version control.

## Contributing

Contributions are welcome. This is a side project maintained in spare time — please be patient with response times. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and submission guidelines.

Look for issues labeled [`good first issue`](https://github.com/turqoisehex/cc-sentinel/labels/good%20first%20issue) if you're looking for a place to start.

## Credits

- **Boris Cherny** -- Creator of Claude Code at Anthropic. His publicly documented workflow principles form the philosophical foundation. cc-sentinel implements his methodology as enforceable infrastructure. Community index: [howborisusesclaudecode.com](https://howborisusesclaudecode.com). Config reconstruction: [github.com/0xquinto/bcherny-claude](https://github.com/0xquinto/bcherny-claude).
- **cc-context-awareness** by [sdi2200262](https://github.com/sdi2200262/cc-context-awareness) -- Canonical context window monitoring tool for macOS/Linux. cc-sentinel includes a Windows-compatible rewrite (the only known working Windows version) and recommends the canonical version for non-Windows users.
- **Production-refined** through hundreds of hours of iterative development on a production Flutter project, translating Cherny's principles into hooks, agents, and commands that enforce behavior rather than suggest it.

## License

MIT
