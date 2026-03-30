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

Key settings: `startup_delay` (tune per machine speed), `terminal`, `key_sender`.

## Trust Prompt

When spawn launches CC in a directory without `.claude/settings.json` (including the home directory), CC shows an interactive trust prompt. Spawn automatically dismisses this with an Enter keystroke and waits `trust_prompt_delay` seconds (default: 3) before continuing.

To avoid the extra delay per session, set `project_dir` in `~/.claude/tools/spawn.json` to a project directory that CC has already trusted.

## Startup Delay

The `startup_delay` setting (default: 5s) controls how long spawn waits after launching `claude` before typing commands. If sessions fail to configure, increase this value:

```bash
python3 ~/.claude/tools/spawn.py --setup  # re-detect + write config
```

Or edit `~/.claude/tools/spawn.json` directly: `"startup_delay": 8`

## Requirements

- Python 3 (stdlib only, no pip dependencies)
- A supported terminal emulator
- For keystroke injection: platform-specific requirements (see `--check`)
