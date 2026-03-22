#!/usr/bin/env bash
# flash-linux.sh — Desktop notification when CC completes or needs input
# Hook events: Stop, Notification

# Terminal bell
printf '\a'

# Desktop notification via notify-send (if available)
if command -v notify-send &>/dev/null; then
  notify-send "Claude Code" "Task completed or needs your attention" --urgency=normal
fi
