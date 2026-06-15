#!/usr/bin/env bash
# Pins the workflows-config schema contract end-to-end. The parser logic mirrors what
# the §5 gate's Read+parse step executes; this test is the deterministic guard on the
# schema (the config DOC itself is prose, but the SCHEMA is a yes/no contract).
set -uo pipefail
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# parse_config <file> -> prints one of: OFF | PARSE-FAIL | ENABLED | FILE-ABSENT
# and (for ENABLED) the clamped/validated tunables; exit 0 always (gate is fail-open).
# Schema rules (§5 gate logic):
#   - workflows_enabled is the ONLY always-required key; absent → FILE-ABSENT.
#   - workflows_enabled present and false → OFF immediately (no tunable check).
#   - workflows_enabled malformed (not exactly true|false) → PARSE-FAIL (never silent OFF).
#   - workflows_enabled true → THEN validate tunables (dryRounds, maxRounds,
#     enabled-phases, budget, budgetGuard); missing/malformed required-when-enabled key → PARSE-FAIL.
parse_config() {
  local f="$1"
  [[ ! -f "$f" ]] && { echo "FILE-ABSENT"; return; }
  # workflows_enabled is the ONLY always-required key
  grep -qE "^workflows_enabled:" "$f" || { echo "PARSE-FAIL missing:workflows_enabled"; return; }
  local enabled
  enabled=$(grep -E '^workflows_enabled:' "$f" | head -1 | sed 's/.*: *//')
  # malformed boolean (not exactly true or false) → PARSE-FAIL, never silent OFF
  [[ "$enabled" == "true" || "$enabled" == "false" ]] || { echo "PARSE-FAIL malformed-boolean:$enabled"; return; }
  # false → OFF short-circuit; tunables are NOT required (ship-default is workflows_enabled: false only)
  [[ "$enabled" == "false" ]] && { echo "OFF"; return; }
  # enabled=true → validate tunables (dryRounds, maxRounds, enabled-phases required; budget + budgetGuard recognized)
  for k in dryRounds maxRounds enabled-phases; do
    grep -qE "^${k}:" "$f" || { echo "PARSE-FAIL missing:$k"; return; }
  done
  local dry max
  dry=$(grep -E '^dryRounds:' "$f" | head -1 | sed 's/.*: *//')
  max=$(grep -E '^maxRounds:' "$f" | head -1 | sed 's/.*: *//')
  [[ "$dry" =~ ^[0-9]+$ && "$max" =~ ^[0-9]+$ ]] || { echo "PARSE-FAIL nonnumeric"; return; }
  (( max < dry )) && { echo "PARSE-FAIL maxRounds<dryRounds"; return; }   # CLEAN unreachable
  (( dry < 2 )) && dry=2                                                  # floor clamp
  # budget and budgetGuard are recognized optional-when-enabled keys (no presence check required)
  # fanoutTypeCap is an optional key; absent → DEFAULT_8 (never PARSE-FAIL); apply tr -d '\r' for CRLF
  local cap
  if grep -qE "^fanoutTypeCap:" "$f"; then
    cap=$(grep -E '^fanoutTypeCap:' "$f" | head -1 | sed 's/.*: *//' | tr -d '\r')
    [[ "$cap" =~ ^[0-9]+$ ]] || { echo "PARSE-FAIL fanoutTypeCap-nonnumeric:$cap"; return; }
  else
    cap="DEFAULT_8"
  fi
  local phases
  phases=$(grep -E '^enabled-phases:' "$f" | head -1 | sed 's/.*: *//' | tr -d '\r')
  echo "ENABLED dry=$dry max=$max fanoutTypeCap=$cap phases=$phases"
}

# (1) absent file = FILE-ABSENT (gate maps to OFF/fallback, NOT parse-fail)
[[ "$(parse_config "$TMP/none.md")" == "FILE-ABSENT" ]] && ok "absent=FILE-ABSENT" || no "absent"
# (2) shipped-default stub (workflows_enabled: false only, no tunables) = OFF (NOT PARSE-FAIL)
printf 'workflows_enabled: false\n' > "$TMP/default.md"
[[ "$(parse_config "$TMP/default.md")" == "OFF" ]] && ok "shipped-default=OFF" || no "shipped-default"
# (3) malformed boolean (not exactly true|false) = PARSE-FAIL (NOT silent OFF)
printf 'workflows_enabled: yes\n' > "$TMP/malformed.md"
[[ "$(parse_config "$TMP/malformed.md")" == PARSE-FAIL* ]] && ok "malformed-bool=PARSE-FAIL" || no "malformed-bool"
# (4) enabled=true with missing required tunable = PARSE-FAIL
printf 'workflows_enabled: true\ndryRounds: 2\n' > "$TMP/broken.md"   # missing maxRounds + enabled-phases
[[ "$(parse_config "$TMP/broken.md")" == PARSE-FAIL* ]] && ok "enabled-missing-tunable=PARSE-FAIL" || no "enabled-missing-tunable"
# (5) maxRounds<dryRounds rejected
printf 'workflows_enabled: true\ndryRounds: 3\nmaxRounds: 2\nenabled-phases: ["/5"]\n' > "$TMP/bad.md"
[[ "$(parse_config "$TMP/bad.md")" == *"maxRounds<dryRounds"* ]] && ok "max<dry rejected" || no "max<dry"
# (6) dryRounds below floor clamps to 2
printf 'workflows_enabled: true\ndryRounds: 1\nmaxRounds: 5\nenabled-phases: ["/5"]\n' > "$TMP/floor.md"
[[ "$(parse_config "$TMP/floor.md")" == *"dry=2"* ]] && ok "floor clamp" || no "floor"
# (7) enabled=false with no tunables present = OFF (not PARSE-FAIL — tunables only required when enabled)
printf 'workflows_enabled: false\n' > "$TMP/off.md"
[[ "$(parse_config "$TMP/off.md")" == "OFF" ]] && ok "false-no-tunables=OFF" || no "false-no-tunables"
# (8) valid enabled with all required tunables = ENABLED
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/5"]\n' > "$TMP/on.md"
[[ "$(parse_config "$TMP/on.md")" == ENABLED* ]] && ok "valid=ENABLED" || no "valid"
# (9) enabled with optional budget/budgetGuard recognized (no PARSE-FAIL)
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/5"]\nbudget: {rounds: 12}\nbudgetGuard: true\n' > "$TMP/full.md"
[[ "$(parse_config "$TMP/full.md")" == ENABLED* ]] && ok "budget+budgetGuard=ENABLED" || no "budget+budgetGuard"

# (10) fanoutTypeCap present with valid integer is parsed (with CRLF trim guard)
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/4","/5"]\nfanoutTypeCap: 12\n' \
  > "$TMP/cap_valid.md"
result=$(parse_config "$TMP/cap_valid.md")
[[ "$result" == *"fanoutTypeCap=12"* ]] && ok "fanoutTypeCap valid int parsed" || no "fanoutTypeCap valid int: got $result"

# (11) fanoutTypeCap absent => defaults to 8 without PARSE-FAIL (optional key)
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/4","/5"]\n' \
  > "$TMP/cap_absent.md"
result=$(parse_config "$TMP/cap_absent.md")
[[ "$result" == *"fanoutTypeCap=DEFAULT_8"* ]] && ok "fanoutTypeCap absent=DEFAULT_8 not PARSE-FAIL" \
  || no "fanoutTypeCap absent: got $result"

# (12) enabled-phases ["/4","/5"] is valid — both phases present in output
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/4","/5"]\n' \
  > "$TMP/both_phases.md"
result=$(parse_config "$TMP/both_phases.md")
[[ "$result" == ENABLED* && "$result" == *"/4"* && "$result" == *"/5"* ]] \
  && ok "enabled-phases /4+/5 = ENABLED with both phases in output" \
  || no "enabled-phases /4+/5: got $result"

echo "config-parser: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
