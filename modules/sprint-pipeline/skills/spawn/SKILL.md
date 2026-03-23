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

- **opus N** — N Opus sessions in one terminal window (tabs)
- **sonnet N** — N Sonnet sessions in one terminal window (tabs)
- **duo N** — N Sonnet + N Opus in separate named windows (Sonnet launches first so listener is ready for Opus)

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
