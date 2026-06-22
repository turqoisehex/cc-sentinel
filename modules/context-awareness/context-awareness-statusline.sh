#!/usr/bin/env bash
# cc-context-awareness — Status line sensor (optimized)
# Reads context window data from stdin, manages threshold flags, renders status bar.
# Optimized to minimize subprocess spawning (~3-4 jq calls instead of ~20).

set -u

# Read JSON from stdin
INPUT="$(cat)"

# Parse session id + REAL token usage, and derive the percentage ourselves.
# We compute from actual token counts rather than the payload's `used_percentage`
# because some Claude Code builds mis-report `context_window_size` (e.g. a
# 1M-context model that still reports 200000) and clamp `used_percentage` at 100,
# which pins the bar at 100%. Deriving from `total_input_tokens` against the real
# window fixes that. On correctly-reported windows this equals `used_percentage`,
# so behaviour is unchanged for everyone else.
read -r SESSION_ID USED_TOKENS REPORTED_WINDOW <<< "$(echo "$INPUT" | jq -r '
  .context_window as $cw |
  # used_tokens: prefer total_input_tokens; else sum current_usage (only if
  # present — an absent current_usage must fall through, not resolve to 0); else
  # derive from used_percentage (older CC builds with no token fields); else 0.
  ( $cw.total_input_tokens
    // ( if ($cw.current_usage // null) != null
         then ( ($cw.current_usage.input_tokens // 0)
              + ($cw.current_usage.cache_creation_input_tokens // 0)
              + ($cw.current_usage.cache_read_input_tokens // 0) )
         else null end )
    // ( ( ($cw.used_percentage // 0) * ($cw.context_window_size // 200000) / 100 ) | floor )
    // 0 ) as $tokens |
  [ .session_id // "", $tokens, ($cw.context_window_size // 200000) ] | @tsv
' | tr -d '\r')"
[[ "$USED_TOKENS" =~ ^[0-9]+$ ]] || USED_TOKENS=0
{ [[ "$REPORTED_WINDOW" =~ ^[0-9]+$ ]] && [[ "$REPORTED_WINDOW" != "0" ]]; } || REPORTED_WINDOW=200000
# Safety invariant (no model assumption): a session cannot hold more tokens than
# its window, so if usage exceeds the reported size the report is wrong and the
# real window must be the larger 1M tier. This never triggers on a correctly
# reported window, so it is a no-op for normal users.
WINDOW="$REPORTED_WINDOW"
[[ "$USED_TOKENS" -gt "$WINDOW" ]] && WINDOW=1000000
USED_PCT=$(( USED_TOKENS * 100 / WINDOW ))
(( USED_PCT > 100 )) && USED_PCT=100
REMAINING_PCT=$(( 100 - USED_PCT ))

# Exit early if no session
[[ -z "$SESSION_ID" ]] && exit 0

# Determine config file location (env override, then script-relative, then local CWD, then global)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${CC_CTX_CONFIG:-}" && -f "$CC_CTX_CONFIG" ]]; then
  CONFIG_FILE="$CC_CTX_CONFIG"
elif [[ -f "$_SCRIPT_DIR/config.json" ]]; then
  CONFIG_FILE="$_SCRIPT_DIR/config.json"
elif [[ -f "./.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="./.claude/cc-context-awareness/config.json"
elif [[ -f "$HOME/.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"
else
  CONFIG_FILE=""
fi

# Parse all config values in a single jq call (with defaults)
# Use newlines + while loop (bash 3 compatible) to handle empty values correctly
CONFIG_VALUES=()
if [[ -n "$CONFIG_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    CONFIG_VALUES+=("$line")
  done < <(jq -r '
    (.flag_dir // "/tmp"),
    (.statusline.bar_width // 20 | tostring),
    (.statusline.bar_filled // "█"),
    (.statusline.bar_empty // "░"),
    (.statusline.format // "context {bar} {percentage}%"),
    (.statusline.color_normal // "37"),
    (.statusline.color_warning // "31"),
    (.statusline.warning_indicator // ""),
    (.statusline.bar_style // "auto"),
    (.repeat_mode // "once_per_tier_reset_on_compaction"),
    ((.thresholds // []) | @json),
    (if .statusline.enabled == false then "false" else "true" end)
  ' "$CONFIG_FILE" 2>/dev/null | tr -d '\r')
fi

if [[ ${#CONFIG_VALUES[@]} -ge 12 ]]; then
  FLAG_DIR="${CONFIG_VALUES[0]}"
  BAR_WIDTH="${CONFIG_VALUES[1]}"
  BAR_FILLED="${CONFIG_VALUES[2]}"
  BAR_EMPTY="${CONFIG_VALUES[3]}"
  FORMAT="${CONFIG_VALUES[4]}"
  COLOR_NORMAL="${CONFIG_VALUES[5]}"
  COLOR_WARNING="${CONFIG_VALUES[6]}"
  WARNING_INDICATOR="${CONFIG_VALUES[7]}"
  BAR_STYLE="${CONFIG_VALUES[8]}"
  REPEAT_MODE="${CONFIG_VALUES[9]}"
  THRESHOLDS_JSON="${CONFIG_VALUES[10]}"
  STATUSLINE_ENABLED="${CONFIG_VALUES[11]}"
else
  FLAG_DIR="/tmp"
  BAR_WIDTH=20
  BAR_FILLED="█"
  BAR_EMPTY="░"
  FORMAT="context {bar} {percentage}%"
  COLOR_NORMAL="37"
  COLOR_WARNING="31"
  WARNING_INDICATOR=""
  BAR_STYLE="auto"
  REPEAT_MODE="once_per_tier_reset_on_compaction"
  THRESHOLDS_JSON="[]"
  STATUSLINE_ENABLED="true"
fi

# Apply bar_style override
if [[ "$BAR_STYLE" == "ascii" ]]; then
  BAR_FILLED="#"
  BAR_EMPTY="-"
elif [[ "$BAR_STYLE" == "auto" ]]; then
  # Default: Unicode. Fall back to ASCII only with positive evidence of non-Unicode.
  # Git Bash on Windows never sets LANG/LC_ALL but supports Unicode fine.
  _use_ascii=false
  if [[ -z "${MSYSTEM:-}" && -z "${WT_SESSION:-}" ]]; then
    # Not Windows — check locale
    _locale="${LANG:-}${LC_ALL:-}"
    if [[ -n "$_locale" && "$_locale" != *UTF* && "$_locale" != *utf* ]]; then
      _use_ascii=true
    fi
  fi
  if [[ "$_use_ascii" == "true" ]]; then
    BAR_FILLED="#"
    BAR_EMPTY="-"
  fi
fi
# bar_style=unicode: keep config values as-is (Unicode is the default)

FIRED_FILE="${FLAG_DIR}/.cc-ctx-fired-${SESSION_ID}"
TRIGGER_FILE="${FLAG_DIR}/.cc-ctx-trigger-${SESSION_ID}"

# Load fired-tiers tracking
if [[ -f "$FIRED_FILE" ]]; then
  FIRED="$(cat "$FIRED_FILE")"
else
  FIRED='{}'
fi

# Process all thresholds in a single jq call
# Returns: exceeded (true/false), new_fired JSON, trigger JSON (if any)
THRESHOLD_RESULT="$(jq -c --argjson used "$USED_PCT" --argjson remaining "$REMAINING_PCT" \
  --argjson fired "$FIRED" --arg repeat_mode "$REPEAT_MODE" '
  # Sort thresholds by percent
  (. | sort_by(.percent)) as $sorted |

  # Track state
  {
    any_exceeded: false,
    fired: $fired,
    trigger: null
  } |

  # Process each threshold
  reduce $sorted[] as $t (.;
    if $used >= ($t.percent | tonumber) then
      .any_exceeded = true |
      if (.fired[$t.level] != true) or ($repeat_mode == "every_turn") then
        # Fire this threshold
        .trigger = {
          percentage: $used,
          remaining: $remaining,
          level: $t.level,
          message: ($t.message | gsub("{percentage}"; ($used | tostring)) | gsub("{remaining}"; ($remaining | tostring)))
        } |
        .fired[$t.level] = true
      else
        .
      end
    else
      # Below threshold - reset if needed
      if (.fired[$t.level] == true) and ($repeat_mode != "once_per_tier") then
        .fired |= del(.[$t.level])
      else
        .
      end
    end
  )
' <<< "$THRESHOLDS_JSON")"

# Extract results in a single jq call
read -r ANY_EXCEEDED NEW_FIRED TRIGGER <<< "$(echo "$THRESHOLD_RESULT" | jq -r '[
  .any_exceeded,
  (.fired | @json),
  (.trigger | @json)
] | @tsv' | tr -d '\r')"

# Write trigger file if threshold was crossed
if [[ "$TRIGGER" != "null" ]]; then
  echo "$TRIGGER" > "$TRIGGER_FILE"
fi

# Persist fired-tiers tracking
echo "$NEW_FIRED" > "$FIRED_FILE"

# Skip rendering if statusline.enabled is false (thresholds still fire above)
[[ "$STATUSLINE_ENABLED" == "false" ]] && exit 0

# Render status bar efficiently (no loops)
FILLED_COUNT=$(( USED_PCT * BAR_WIDTH / 100 ))
EMPTY_COUNT=$(( BAR_WIDTH - FILLED_COUNT ))

# Build bar using loop (tr corrupts multi-byte Unicode chars like █/░)
BAR=""
for ((i=0; i<FILLED_COUNT; i++)); do BAR+="$BAR_FILLED"; done
for ((i=0; i<EMPTY_COUNT; i++)); do BAR+="$BAR_EMPTY"; done

# Build output from format string
OUTPUT="${FORMAT//\{bar\}/$BAR}"
OUTPUT="${OUTPUT//\{percentage\}/$USED_PCT}"

# Append warning indicator and set color
if [[ "$ANY_EXCEEDED" == "true" ]]; then
  OUTPUT="${OUTPUT}${WARNING_INDICATOR}"
  COLOR="$COLOR_WARNING"
else
  COLOR="$COLOR_NORMAL"
fi

# Print with ANSI color
printf '\033[%sm%s\033[0m' "$COLOR" "$OUTPUT"
