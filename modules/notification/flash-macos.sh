#!/usr/bin/env bash
# flash-macos.sh — Desktop notification when CC completes or needs input
# Hook events: Stop, Notification

# Drain stdin (CC pipes JSON to all hooks)
cat > /dev/null 2>/dev/null &

# Terminal bell
printf '\a'

# macOS notification via osascript
osascript -e 'display notification "Task completed or needs your attention" with title "Claude Code"' 2>/dev/null || true
