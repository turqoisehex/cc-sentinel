#!/usr/bin/env bash
set -u
# flash-linux.sh — Desktop notification when CC completes or needs input
# Hook events: Stop, Notification

# Drain stdin (CC pipes JSON to all hooks)
cat > /dev/null 2>/dev/null &

# Terminal bell
printf '\a'

# Desktop notification via notify-send (if available)
if command -v notify-send &>/dev/null; then
  notify-send "Claude Code" "Task completed or needs your attention" --urgency=normal
fi
