#!/usr/bin/env bash
# cc-context-awareness — Status line sensor (optimized)
# Reads context window data from stdin, manages threshold flags, renders status bar.
# Optimized to minimize subprocess spawning (~3-4 jq calls instead of ~20).

set -u

# Read JSON from stdin
INPUT="$(cat)"

# Parse all input fields in a single jq call
read -r SESSION_ID USED_PCT REMAINING_PCT <<< "$(echo "$INPUT" | jq -r '[
  .session_id // "",
  (.context_window.used_percentage // 0 | floor),
  (.context_window.remaining_percentage // 100 | floor)
] | @tsv' | tr -d '\r')"

# Exit early if no session
[[ -z "$SESSION_ID" ]] && exit 0

# Determine config file location (local takes precedence over global)
if [[ -f "./.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="./.claude/cc-context-awareness/config.json"
elif [[ -f "$HOME/.claude/cc-context-awareness/config.json" ]]; then
  CONFIG_FILE="$HOME/.claude/cc-context-awareness/config.json"
else
  CONFIG_FILE=""
fi

# Parse all config values in a single jq call (with defaults)
# Use newlines + while loop (bash 3 compatible) to handle empty values correctly
if [[ -n "$CONFIG_FILE" ]]; then
  CONFIG_VALUES=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    CONFIG_VALUES+=("$line")
  done < <(jq -r '
    (.flag_dir // "/tmp"),
    (if .statusline.enabled == false then "false" else "true" end),
    (.statusline.bar_width // 20 | tostring),
    (.statusline.bar_filled // "█"),
    (.statusline.bar_empty // "░"),
    (.statusline.format // "context {bar} {percentage}%"),
    (.statusline.color_normal // "37"),
    (.statusline.color_warning // "33"),
    (.statusline.warning_indicator // ""),
    (.statusline.bar_style // "auto"),
    (.repeat_mode // "once_per_tier_reset_on_compaction"),
    ((.thresholds // []) | @json)
  ' "$CONFIG_FILE" | tr -d '\r')
  FLAG_DIR="${CONFIG_VALUES[0]}"
  STATUSLINE_ENABLED="${CONFIG_VALUES[1]}"
  BAR_WIDTH="${CONFIG_VALUES[2]}"
  BAR_FILLED="${CONFIG_VALUES[3]}"
  BAR_EMPTY="${CONFIG_VALUES[4]}"
  FORMAT="${CONFIG_VALUES[5]}"
  COLOR_NORMAL="${CONFIG_VALUES[6]}"
  COLOR_WARNING="${CONFIG_VALUES[7]}"
  WARNING_INDICATOR="${CONFIG_VALUES[8]}"
  BAR_STYLE="${CONFIG_VALUES[9]}"
  REPEAT_MODE="${CONFIG_VALUES[10]}"
  THRESHOLDS_JSON="${CONFIG_VALUES[11]}"
else
  # Defaults if no config file
  FLAG_DIR="/tmp"
  STATUSLINE_ENABLED="true"
  BAR_WIDTH=20
  BAR_FILLED="█"
  BAR_EMPTY="░"
  FORMAT="context {bar} {percentage}%"
  COLOR_NORMAL="37"
  COLOR_WARNING="33"
  WARNING_INDICATOR=""
  BAR_STYLE="auto"
  REPEAT_MODE="once_per_tier_reset_on_compaction"
  THRESHOLDS_JSON="[]"
fi

# Apply bar_style override
if [[ "$BAR_STYLE" == "ascii" ]]; then
  BAR_FILLED="#"
  BAR_EMPTY="-"
elif [[ "$BAR_STYLE" == "auto" ]]; then
  # Test if terminal can render Unicode by checking locale vars + Windows Terminal
  if [[ "${LANG:-}"    == *[Uu][Tt][Ff]* || \
        "${LC_ALL:-}"  == *[Uu][Tt][Ff]* || \
        "${LC_CTYPE:-}" == *[Uu][Tt][Ff]* || \
        -n "${WT_SESSION:-}" ]]; then
    : # Keep Unicode defaults
  else
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

# Exit before rendering if statusline is disabled (thresholds still fire above)
[[ "$STATUSLINE_ENABLED" != "true" ]] && exit 0

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
