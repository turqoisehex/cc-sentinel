# /spawn — Launch Multi-Session Environment

Launch multiple Claude Code sessions with model selection, channel routing, and terminal tab management.

## Usage

```bash
python ~/.claude/tools/spawn.py                      # GUI mode
python ~/.claude/tools/spawn.py opus 3               # 3 Opus sessions
python ~/.claude/tools/spawn.py sonnet 2             # 2 Sonnet sessions
python ~/.claude/tools/spawn.py duo 2                # 2 Opus + 2 Sonnet (separate windows)
python ~/.claude/tools/spawn.py --check              # Verify dependencies
python ~/.claude/tools/spawn.py --setup              # Configure terminal/key sender
```

## Modes

- **opus** — N Opus sessions in one terminal window (tabs)
- **sonnet** — N Sonnet sessions in one terminal window (tabs)
- **duo** — N Opus + N Sonnet in separate named windows. Creates channel infrastructure if missing.

## Cross-Platform Support

| Platform | Terminal | Keystroke Injection |
|----------|----------|-------------------|
| Windows | Windows Terminal (wt) | ctypes SendInput |
| Linux (X11) | gnome-terminal, konsole, xfce4-terminal | libXtst / xdotool |
| Linux (Wayland) | Any | Not available (commands printed for copy-paste) |
| macOS | iTerm2, Terminal.app | AppleScript |

## Configuration

Config file: `~/.claude/tools/spawn.json` (auto-created by `--setup`).

Key settings: `startup_delay` (tune per machine speed), `terminal`, `key_sender`.

## Requirements

- Python 3 (stdlib only, no pip dependencies)
- A supported terminal emulator
- For keystroke injection: platform-specific requirements (see `--check`)
