# cc-sentinel

**Governance infrastructure for Claude Code.** Hooks, agents, and workflows that prevent the failure modes autonomous coding sessions actually hit.

## The Problem

Claude Code is powerful out of the box. But long, autonomous sessions surface real failure modes that no amount of prompting fixes:

| Failure Mode | What Happens | Cost |
|---|---|---|
| **Context loss** | After compaction, Claude forgets what it was doing, repeats work, or contradicts earlier decisions | Hours of wasted compute, inconsistent output |
| **Work deferral** | Claude writes "TODO: implement later" or "will add in next step" and never returns | Incomplete features shipped as "done" |
| **False completion** | Claude claims a task is done without verifying | Bugs discovered in production, not development |
| **Governance drift** | Claude edits its own rules, CLAUDE.md, or config files mid-session | Guardrails silently disabled |
| **Silent compaction** | Context window fills with no warning; state is lost before it can be saved | Unrecoverable mid-task failure |
| **Commit quality** | Large diffs committed without review; tests skipped; formatting inconsistent | Technical debt accumulates per-session |
| **Agent amnesia** | Subagents start with no knowledge of project conventions or current task state | Agents produce work that contradicts the session |

cc-sentinel solves these with **hooks that enforce automatically** -- not rules that rely on Claude choosing to follow them.

## How It Works

cc-sentinel is a modular set of Claude Code hooks, slash commands, reference docs, agents, and templates. You install the modules you need. The installer is a conversation -- Claude Code reads your project and recommends what to install.

```
Claude Code: I see this is a Python/Django project with pytest. Here's what I recommend:

  [x] Core (required) -- context loss prevention, anti-deferral, state management
  [x] Context Awareness -- visual context meter in your status bar
  [ ] Verification -- 5-agent verification squad before completion claims
  [x] Commit Enforcement -- test gating, auto-format, diff review
  [ ] Sprint Pipeline -- structured /1 through /5 workflow
  [x] Governance Protection -- protect CLAUDE.md and config from mid-session edits
  [x] Notification -- desktop alert when Claude finishes or needs input

Install these 5 modules? (Y/n)
```

## Installation

**In any Claude Code session:**

```
Install https://github.com/turqoisehex/cc-sentinel
```

Claude Code reads the repo's CLAUDE.md, which contains an interactive installer. It will:

1. Detect your OS, shell, and project type
2. Ask what problems you want solved (one question at a time)
3. Recommend modules based on your answers
4. Run the installer script
5. Inject rules into your project's CLAUDE.md
6. Verify the installation with `/self-test`

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
| `anti-deferral.sh` | PreToolUse | Scans every file write for deferral language ("TODO later", "will implement", "placeholder"). Blocks the write with a specific error message. |
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
[|||||||||||||........] 62% context used
```

Thresholds trigger automatic reminders:
- **50%** -- "Documenting as you go?"
- **65%** -- "Could a fresh session resume from your state files?"
- **75%** -- "Wrap up current unit of work."
- **85%** -- "State files current. Commit if at a natural boundary."
- **95%** -- "Auto-compaction imminent. State files must be complete."

**Windows support:** cc-sentinel includes the only known Windows-compatible version of cc-context-awareness. On macOS/Linux, you can choose between the bundled version or the [canonical repository](https://github.com/sdi2200262/cc-context-awareness).

### Verification

Five-agent verification squad that independently audits work before any completion claim. Each agent has a different adversarial perspective:

| Agent | What It Catches |
|---|---|
| **Mechanical Auditor** | Wrong file paths, constants, enum values, counts -- anything greppable |
| **Adversarial Reader** | Spec contradictions, hallucinated content, rule violations |
| **Completeness Scanner** | Missing requirements, unassigned items, spec gaps |
| **Dependency Tracer** | Missing migrations, untraced call sites, silent default changes |
| **Cold Reader** | Semantic errors invisible to the author -- reads with zero context |

The `stop-task-check.sh` hook fires when Claude tries to stop, requiring verification evidence before allowing completion claims through.

Commands: `/squad`, `/grill` (iterative self-challenge)

### Commit Enforcement

Every commit is gated: tests must pass, formatting must be clean, and two verification agents review the diff before it lands.

| Component | What It Does |
|---|---|
| `safe-commit.sh` | Runs tests (auto-detects: npm, pytest, cargo, go, flutter, make), blocks on failure |
| `auto-format.sh` | Runs formatter (prettier, black, cargo fmt, dart format, gofmt) on every file write |
| `channel_commit.sh` | Orchestrates: stage, verify, test, format, commit. The single public API for commits. |
| `commit-adversarial.md` | Agent that reviews staged diff for logic errors, spec violations, regressions |
| `commit-cold-reader.md` | Agent that reads staged diff with zero context -- flags anything broken or nonsensical |

Multi-framework auto-detection: the commit hooks detect your project type from manifest files (`package.json`, `Cargo.toml`, `go.mod`, `pubspec.yaml`, `pyproject.toml`, `Makefile`) and run the appropriate test suite and formatter.

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

Additional commands: `/cold` (cold-start resume), `/cleanup` (session cleanup), `/opus` (channel management), `/sonnet` (Sonnet dispatch), `/status` (progress overview), `/rewrite` (content rewrite pipeline).

Recommends complementary Claude Code plugins: superpowers, context7, feature-dev, pr-review-toolkit.

### Governance Protection

Prevents Claude from editing its own rules mid-session.

- **`file-protection.sh`** -- PreToolUse hook that blocks writes to protected files (CLAUDE.md, settings.json, etc.)
- **Override mechanism** -- Add `GOVERNANCE-EDIT-AUTHORIZED` to CURRENT_TASK.md to temporarily allow edits (creates an audit trail)
- **`/mistake`** -- Structured correction capture that adds to CLAUDE.md's accumulated corrections
- **`/prune-rules`** -- Maintains correction list under soft cap (prevents rule bloat)

### Notification

Desktop alerts when Claude Code completes a task or needs your input. Platform-native:

- **macOS** -- osascript notification
- **Linux** -- notify-send (libnotify)
- **Windows** -- PowerShell toast notification (BurntToast or Windows.UI.Notifications)

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
  +-- commit-enforcement (requires core + verification)
  +-- sprint-pipeline (requires core + verification)
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
    core/                # Required -- hooks, templates, reference
    context-awareness/   # Status bar meter, graduated warnings
    verification/        # 5-agent squad, /squad, /grill
    commit-enforcement/  # safe-commit, auto-format, channel routing
    sprint-pipeline/     # /1-/5 workflow, /cold, /cleanup
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

## Requirements

- Claude Code CLI
- Bash (Git Bash on Windows)
- `jq` (used by hooks for JSON parsing)
- Python 3 (used by installer for settings.json merge on Unix)

## FAQ

**Does this replace CLAUDE.md?**
No. cc-sentinel adds rules to your existing CLAUDE.md (with clear delimiters) and registers hooks in settings.json. Your existing configuration is preserved.

**Can I uninstall a module?**
Remove its files from `.claude/` and its hook entries from `.claude/settings.json`. The installer will add uninstall support in a future version.

**Does this work with Claude Code plugins?**
Yes. cc-sentinel hooks and plugins coexist. The sprint-pipeline module recommends complementary plugins but does not require them.

**What about performance?**
Most hooks add 5-15ms per tool call (shell startup + jq parse). The auto-format hook runs only on file writes and formats only the changed file. Context awareness adds a status line update. None are perceptible during normal use.

**Can I use this with a team?**
Yes. Project install (`.claude/`) commits to your repo, so the whole team gets the same governance. Add `.claude/` to version control.

## License

MIT
