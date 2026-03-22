---
name: configure-context-awareness
description: Configure the cc-context-awareness context window warning system. Use when the user wants to change context warning thresholds, messages, status bar appearance, or other cc-context-awareness settings.
---

# cc-context-awareness Configuration

cc-context-awareness monitors Claude Code context window usage and warns you when it's getting full. It uses a status line to show usage, a hook to inject warnings into the conversation, and a reset handler to clear stale state after compaction.

## Config File

cc-context-awareness can be installed **locally** (per-project) or **globally**:

| Mode | Config location | Settings file |
|------|-----------------|---------------|
| Local (default) | `./.claude/cc-context-awareness/config.json` | `./.claude/settings.local.json` |
| Global | `~/.claude/cc-context-awareness/config.json` | `~/.claude/settings.json` |

**Priority:** Local settings override global (per Claude Code's settings hierarchy). If both exist, the local config is effective in that project.

Always read the current config before making changes. Use the Edit tool — never overwrite the whole file.

## What To Do

1. Read `~/.claude/cc-context-awareness/config.json`
2. Refer to the config schema and examples below
3. Make targeted edits based on what the user wants

## Conflict Handling

### StatusLine conflicts

If another tool (e.g. [ccstatusline](https://github.com/sirmalloc/ccstatusline)) is using the statusLine slot, cc-context-awareness can **wrap** or **merge** with it instead of replacing it. The statusline script writes a flag file that the hook reads — this bridge must be preserved.

**Option 1: Wrap (recommended)**

Create a wrapper script that calls both statuslines:

```bash
#!/usr/bin/env bash
# ~/.claude/statusline-wrapper.sh
INPUT=$(cat)
echo "$INPUT" | /path/to/other/statusline.sh
echo "$INPUT" | ~/.claude/cc-context-awareness/context-awareness-statusline.sh
```

Then update `settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-wrapper.sh"
  }
}
```

**Option 2: Merge**

Copy the flag-writing logic from `~/.claude/cc-context-awareness/context-awareness-statusline.sh` into the existing statusline script. The critical parts are:
1. Reading thresholds from `~/.claude/cc-context-awareness/config.json`
2. Writing the trigger file to `/tmp/.cc-ctx-trigger-{session_id}` when thresholds are crossed
3. Tracking fired tiers in `/tmp/.cc-ctx-fired-{session_id}`
4. Clearing both files on compaction via the `SessionStart` reset handler

The hook reads from the trigger file, so as long as that file is written correctly, warnings will fire.

### Other conflicts

- If the user has other hooks in `settings.json`, never remove them — only modify cc-context-awareness entries
- If editing thresholds, ensure each `level` value is unique

## Config Schema

### `thresholds` (array of objects)

Each threshold triggers a warning when context usage reaches that percentage.

| Field | Type | Description |
|-------|------|-------------|
| `percent` | number | Context usage percentage to trigger at (0–100) |
| `level` | string | Unique tier identifier (e.g. `"warning"`, `"critical"`). Must be unique across thresholds. |
| `message` | string | Message injected into conversation. Supports `{percentage}` and `{remaining}` placeholders |

### `repeat_mode` (string)

Controls when warnings re-fire.

| Value | Behavior |
|-------|----------|
| `"once_per_tier_reset_on_compaction"` | Each tier fires once. Resets if usage drops below the threshold (e.g. after compaction). **Default.** |
| `"once_per_tier"` | Each tier fires once per session. Never resets. |
| `"every_turn"` | Fires on every turn while above the threshold. |

### `statusline` (object)

Controls the status bar appearance.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Show the status line |
| `bar_width` | number | `20` | Width of the progress bar in characters |
| `bar_filled` | string | `"█"` | Character for filled portion |
| `bar_empty` | string | `"░"` | Character for empty portion |
| `format` | string | `"context {bar} {percentage}%"` | Format string. Supports `{bar}` and `{percentage}` |
| `color_normal` | string | `"37"` | ANSI color code for normal state (37=white) |
| `color_warning` | string | `"31"` | ANSI color code for warning state (31=red) |
| `warning_indicator` | string | `""` | Appended to bar when above a threshold. Empty by default (color change is the indicator). |

### `hook_event` (string)

Which Claude Code hook event triggers the context injection.

| Value | Behavior |
|-------|----------|
| `"PreToolUse"` | Fires before every tool call inside the agentic loop. **Default.** |
| `"PostToolUse"` | Fires after every tool call inside the agentic loop. |
| `"UserPromptSubmit"` | Fires once per user prompt. No mid-loop coverage. |

Changing this value also requires re-running the installer to update `settings.json`:
```bash
./install.sh --hook-event PostToolUse
```

### `flag_dir` (string)

Directory for flag files. Default: `"/tmp"`.

## Example Modifications

### Add a critical tier at 95%

Add to the `thresholds` array:
```json
{
  "percent": 95,
  "level": "critical",
  "message": "CRITICAL: Context window is at {percentage}% ({remaining}% remaining). You MUST inform the user immediately and either /compact or wrap up the current task NOW."
}
```

### Lower the warning threshold to 70%

Modify the existing threshold's `percent` field from `80` to `70`.

### Add multiple tiers

Replace the `thresholds` array with:
```json
[
  {"percent": 60, "level": "info", "message": "Context usage at {percentage}%. Consider planning for compaction."},
  {"percent": 80, "level": "warning", "message": "Context at {percentage}% ({remaining}% left). Suggest /compact to the user."},
  {"percent": 95, "level": "critical", "message": "CRITICAL: {percentage}% context used. Wrap up or /compact immediately."}
]
```

### Change bar style to simple ASCII

```json
{
  "bar_filled": "#",
  "bar_empty": "-"
}
```

### Use yellow for warnings instead of red

Set `color_warning` to `"33"` (ANSI yellow).

### Make warnings fire every turn

Set `repeat_mode` to `"every_turn"`.

### Custom warning message with specific instructions

```json
{
  "message": "Context at {percentage}%. Before continuing, summarize what you've done so far and what remains, then ask the user if they want to /compact."
}
```

## Common ANSI Color Codes

| Code | Color |
|------|-------|
| `30` | Black |
| `31` | Red |
| `32` | Green |
| `33` | Yellow |
| `34` | Blue |
| `35` | Magenta |
| `36` | Cyan |
| `37` | White |
