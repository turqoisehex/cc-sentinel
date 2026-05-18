#!/usr/bin/env bash
set -u
# flash-macos.sh — Audio + persistent dock bounce when CC needs attention
# Hook events: Stop, Notification
#
# Terminal bell in Terminal.app bounces the dock icon persistently when
# unfocused. iTerm2 shows a badge. afplay adds an audible ping.

# Drain stdin (CC pipes JSON to all hooks)
cat > /dev/null 2>/dev/null &

# System alert sound (audible when AFK)
afplay /System/Library/Sounds/Tink.aiff 2>/dev/null &

# Terminal bell — triggers persistent dock bounce (Terminal.app) or badge (iTerm2)
printf '\a'

exit 0
