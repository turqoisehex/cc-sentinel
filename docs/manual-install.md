# Manual Installation

For most users, the guided install is easier — type `Install https://github.com/turqoisehex/cc-sentinel` in any Claude Code session. These instructions are for users who prefer to run the installer directly.

## Clone

```bash
git clone https://github.com/turqoisehex/cc-sentinel.git ~/.claude/cc-sentinel
```

Windows (PowerShell):

```powershell
git clone https://github.com/turqoisehex/cc-sentinel.git "$env:USERPROFILE\.claude\cc-sentinel"
```

## Run the Installer

```bash
# Install to current project
bash ~/.claude/cc-sentinel/install.sh --modules "core,context-awareness,verification" --target project

# Or install globally
bash ~/.claude/cc-sentinel/install.sh --modules "core,context-awareness" --target global
```

Windows (PowerShell — run directly, do not wrap in `powershell -File`):

```powershell
& "$env:USERPROFILE\.claude\cc-sentinel\install.ps1" -Modules "core,context-awareness" -Target project
```

## Available Modules

- `core` (required) — context loss prevention, anti-deferral, state management
- `context-awareness` — visual context meter in status bar
- `verification` — multi-model verification squad
- `commit-enforcement` — test gating, auto-format, diff review
- `sprint-pipeline` — structured /1 through /5 workflow
- `governance-protection` — protect CLAUDE.md and config files
- `notification` — desktop alert when Claude finishes or needs input

## Flags

| Flag | Description |
|------|-------------|
| `--modules "m1,m2,..."` | Comma-separated module list |
| `--target global\|project` | Install scope (default: global) |
| `--dry-run` / `-DryRun` | Preview without changes |
| `--deny-rules` / `-DenyRules` | Add binary/media deny rules |
| `--inject-rules` | Append behavioral rules to CLAUDE.md (Unix) |
| `--force-overwrite` / `-ForceOverwrite` | Overwrite existing files |

## Post-Install

After installing, start a new Claude Code session and run `/self-test` to verify everything landed correctly.
