#!/usr/bin/env bash
set -u
# flash-linux.sh — Audio + persistent taskbar flash when CC needs attention
# Hook events: Stop, Notification
#
# Terminal bell triggers urgent hint in most terminals (persistent taskbar
# highlight). wmctrl demands_attention is a fallback for terminals that
# don't convert bell to urgency.

# Drain stdin (CC pipes JSON to all hooks)
cat > /dev/null 2>/dev/null &

# Terminal bell — most terminals set _NET_WM_STATE_DEMANDS_ATTENTION on bell
# when unfocused, which persistently highlights the taskbar entry.
printf '\a'

# Explicit demands_attention as fallback (requires wmctrl + WINDOWID)
if [[ -n "${WINDOWID:-}" ]] && command -v wmctrl &>/dev/null; then
  wmctrl -i -r "$WINDOWID" -b add,demands_attention 2>/dev/null
fi

exit 0
