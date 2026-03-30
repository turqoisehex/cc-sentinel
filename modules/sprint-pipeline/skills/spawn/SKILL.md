---
name: spawn
description: Launch multiple Claude Code sessions with model selection (opus/sonnet/duo), channel routing, and terminal tab management. Use when the user says /spawn, "launch sessions", "start duo", or wants to open multiple CC windows.
---

# /spawn — Launch Multi-Session Environment

Launch multiple Claude Code sessions. Execute immediately — do not ask for confirmation.

**Run this command now:**

```bash
python3 ~/.claude/tools/spawn.py $ARGUMENTS
```

If `$ARGUMENTS` is empty, run `--check` to show environment status. If spawn.json does not exist, run `--setup` first.

## Modes

| Mode | Sessions | Recommended | Notes |
|------|----------|-------------|-------|
| `opus N` | N Opus | **Yes (default)** | Native Sonnet subagent dispatch. No persistent listener overhead. |
| `sonnet N` | N Sonnet | Specialized | For high-volume Sonnet-only workloads. |
| `duo N` | N Sonnet + N Opus | Legacy/specialized | Persistent listeners via file-based IPC. Use when Sonnet sessions need their own persistent context. |

## Cross-Platform Support

| Platform | Terminal | Keystroke Injection |
|----------|----------|-------------------|
| Windows | Windows Terminal (wt) | ctypes SendInput |
| Linux (X11) | gnome-terminal, konsole, xfce4-terminal | libXtst / xdotool |
| Linux (Wayland) | Any | Not available (commands printed for copy-paste) |
| macOS | iTerm2, Terminal.app | AppleScript |

## Configuration

Config file: `~/.claude/tools/spawn.json` (auto-created by `--setup`).

Key settings: `startup_delay` (tune per machine speed), `terminal`, `key_sender`, `project_dir`.
