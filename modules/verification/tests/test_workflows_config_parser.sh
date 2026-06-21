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
  # build-gates: optional NESTED object (single-line inline OR multi-line YAML block)
  # Absent => DEFAULT (no warn); malformed shape => DEFAULT_WARN; well-formed => OK(...); NEVER PARSE-FAIL
  local bg
  if grep -qE "^build-gates:" "$f"; then
    # Collect the build-gates block: the build-gates: line PLUS all immediately following
    # indented/continuation lines (handles multi-line YAML-block format).
    # Use awk: start at ^build-gates:, collect lines until a non-indented non-empty line.
    #
    # COMMENT-STYLE ASSUMPTION (load-bearing — do not break silently): both the `^build-gates:`
    # presence guard above and this awk block assume the DEFAULT-OFF stub in workflows-config.md is
    # HTML-comment-guarded — the commented stub line begins with `<!--`, NOT `^build-gates:`, so it is
    # correctly skipped (a commented stub must never parse as a live config). If the stub format ever
    # changes to a `#`-style YAML comment (`# build-gates: …`) the `^build-gates:` anchor still skips it
    # (the `# ` prefix keeps it off column 0); but a bare un-prefixed `build-gates:` left uncommented in
    # the stub WOULD be collected here. The guard is the `<!--`/`#`-prefixed-stub convention — keep the
    # stub commented (HTML `<!-- … -->` as shipped) so this parser never ingests example values.
    local bgblock
    bgblock=$(awk '/^build-gates:/{found=1; print; next}
                  found && /^[[:space:]]/{print; next}
                  found && /^[^[:space:]]/{exit}' "$f" | tr -d '\r')
    # Extract src, test, ext, diffScan (optional) — present in either inline or block format
    local s t e ds g namecnt cmdcnt
    s=$(printf '%s' "$bgblock" | grep -oE 'src:[[:space:]]*"?[^",}[:space:]]+"?' | head -1 | sed -E 's/src:[[:space:]]*"?([^",}[:space:]]+)"?/\1/')
    t=$(printf '%s' "$bgblock" | grep -oE 'test:[[:space:]]*"?[^",}[:space:]]+"?' | head -1 | sed -E 's/test:[[:space:]]*"?([^",}[:space:]]+)"?/\1/')
    e=$(printf '%s' "$bgblock" | grep -oE 'ext:[[:space:]]*"?[^",}[:space:]]+"?' | head -1 | sed -E 's/ext:[[:space:]]*"?([^",}[:space:]]+)"?/\1/')
    # diffScan is OPTIONAL (absent => skill default); captured here so the skill can read it
    ds=$(printf '%s' "$bgblock" | grep -oE 'diffScan:[[:space:]]*"?[^"]+' | head -1 | sed -E 's/diffScan:[[:space:]]*"?(.*)/\1/' | sed -E 's/"[[:space:]]*[},]?[[:space:]]*$//')
    # Validate the `gates` array-of-{name,cmd} shape. The malformed case `gates: "oops"` (a STRING,
    # not an array of objects) must be REJECTED to DEFAULT_WARN — so presence of `gates:` alone is
    # NOT sufficient. Require BOTH: at least one `name:` AND a matching `cmd:` (every gate object has
    # both keys). A scalar `gates: "oops"` has zero `name:`/`cmd:` pairs => malformed.
    namecnt=$(printf '%s' "$bgblock" | grep -oE '(^[[:space:]]*-[[:space:]]+name:|[{,][[:space:]]*name:|^[[:space:]]*name:)' | wc -l | tr -d ' ')
    cmdcnt=$(printf '%s' "$bgblock" | grep -oE 'cmd:' | wc -l | tr -d ' ')
    g=$namecnt
    # gates is present AND well-formed only when it parses to >=1 {name,cmd} pair (name count == cmd
    # count, both >=1). A `gates:` key with no valid pair (e.g. gates: "oops") is malformed.
    # Detect the `gates` SUB-key specifically — NOT the `build-gates:` PARENT key (a bare `grep 'gates:'`
    # would match `build-gates:` and wrongly report the sub-list present). The sub-key appears either after
    # `{`/`,` (inline form) or at line-start with leading indentation (multi-line YAML block); `build-gates:`
    # at column 0 is `build-gates:` (prefixed by `build-`), so `^[[:space:]]*gates:` does not match it.
    local gates_present=0 gates_ok=0
    if printf '%s' "$bgblock" | grep -qE '(^[[:space:]]*gates:|[{,][[:space:]]*gates:)'; then
      gates_present=1
      if [[ "$namecnt" -ge 1 && "$namecnt" -eq "$cmdcnt" ]]; then gates_ok=1; fi
    fi
    # diffScan is OPTIONAL: surface it in the parsed output so the skill's lens-5 can read it; absent => the
    # literal "default" token (the skill substitutes its own changed-field detector). It MUST appear in the
    # emitted value — capturing it in a local that dies with the function would make it invisible to the skill.
    [[ -z "$ds" ]] && ds="default"
    # Three-way semantics (a present-but-no-gates block is NOT malformed — it gracefully degrades like an absent
    # build-gates, with NO warning; DEFAULT_WARN is reserved for a genuinely malformed shape):
    #   - src/test/ext present AND a well-formed gates array (>=1 {name,cmd} pair) => OK(...)
    #   - src/test/ext present AND NO `gates:` key at all                         => DEFAULT (cheap-gate tier
    #         degrades to lenses 4/5 only, NO warning — same as an absent build-gates; an omitted gates sub-list
    #         is a valid minimalist config, not a malformed one)
    #   - otherwise (missing src/test/ext, OR a present-but-malformed `gates:` e.g. the scalar `gates: "oops"`)
    #                                                                              => DEFAULT_WARN (graceful
    #         default + warning, never PARSE-FAIL)
    if [[ -n "$s" && -n "$t" && -n "$e" && "$gates_ok" -eq 1 ]]; then
      bg="OK(src=$s,test=$t,ext=$e,diffScan=$ds,gates=$g)"   # diffScan surfaced for the skill (lens 5); "default" when absent
    elif [[ -n "$s" && -n "$t" && -n "$e" && "$gates_present" -eq 0 ]]; then
      bg="DEFAULT"        # src/test/ext present, gates sub-list omitted: graceful cheap-gate degrade, NO warning
    else
      bg="DEFAULT_WARN"   # genuinely malformed shape (bad gates array, or missing src/test/ext): graceful default + warning, never PARSE-FAIL
    fi
  else
    bg="DEFAULT"          # absent: skill defaults, no warning
  fi
  echo "ENABLED dry=$dry max=$max fanoutTypeCap=$cap phases=$phases build-gates=$bg"
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

# (N) build-gates well-formed single-line nested object parses correctly
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/3","/5"]\nbuild-gates: { src: "lib", test: "test", ext: "dart", gates: [ { name: "analyze", cmd: "flutter analyze" } ] }\n' \
  > "$TMP/bg_valid.md"
result=$(parse_config "$TMP/bg_valid.md")
[[ "$result" == *"build-gates=OK(src=lib,test=test,ext=dart,diffScan=default,gates=1)"* ]] \
  && ok "build-gates well-formed single-line parsed" || no "build-gates valid single-line: got $result"

# (N+1) build-gates well-formed MULTI-LINE nested object (src/test/ext/gates on separate lines) parses correctly
# The config format supports YAML-block style: subsequent indented lines belong to build-gates.
# The parser must handle the object spanning multiple lines (not just grep the first line).
cat > "$TMP/bg_multiline.md" << 'MLEOF'
workflows_enabled: true
dryRounds: 2
maxRounds: 5
enabled-phases: ["/3","/5"]
build-gates:
  src: "lib"
  test: "test"
  ext: "dart"
  gates:
    - name: "analyze"
      cmd: "flutter analyze"
    - name: "test"
      cmd: "flutter test"
MLEOF
result=$(parse_config "$TMP/bg_multiline.md")
[[ "$result" == *"build-gates=OK(src=lib,test=test,ext=dart,diffScan=default,gates=2)"* ]] \
  && ok "build-gates well-formed multi-line parsed" || no "build-gates valid multi-line: got $result"

# (N+2) build-gates malformed (gates not an array of {name,cmd}) => graceful-default WITH warning, NOT PARSE-FAIL
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/3","/5"]\nbuild-gates: { src: "lib", gates: "oops" }\n' \
  > "$TMP/bg_malformed.md"
result=$(parse_config "$TMP/bg_malformed.md")
[[ "$result" == *"build-gates=DEFAULT_WARN"* && "$result" != *"PARSE-FAIL"* ]] \
  && ok "build-gates malformed=DEFAULT_WARN not PARSE-FAIL" || no "build-gates malformed: got $result"

# (N+3) build-gates absent => skill defaults, NO warning, NOT PARSE-FAIL
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/3","/5"]\n' \
  > "$TMP/bg_absent.md"
result=$(parse_config "$TMP/bg_absent.md")
[[ "$result" == *"build-gates=DEFAULT"* && "$result" != *"DEFAULT_WARN"* && "$result" != *"PARSE-FAIL"* ]] \
  && ok "build-gates absent=DEFAULT no warning" || no "build-gates absent: got $result"

# (N+3a) build-gates present with src/test/ext but NO gates sub-list => DEFAULT (graceful cheap-gate degrade,
# NO warning). An omitted gates sub-list is a valid minimalist config (the cheap-gate tier degrades to lenses
# 4/5 only, exactly as an absent build-gates does — per §3.3 empty-candidate behavior), NOT a malformed shape.
# DEFAULT_WARN is reserved for a genuinely malformed shape (a present-but-bad gates array, or missing src/test/ext).
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/3","/5"]\nbuild-gates: { src: "lib", test: "test", ext: "dart" }\n' \
  > "$TMP/bg_nogates.md"
result=$(parse_config "$TMP/bg_nogates.md")
[[ "$result" == *"build-gates=DEFAULT"* && "$result" != *"DEFAULT_WARN"* && "$result" != *"PARSE-FAIL"* ]] \
  && ok "build-gates present-but-no-gates=DEFAULT no warning (graceful degrade, not malformed)" || no "build-gates no-gates sub-list: got $result"

# (N+3b) build-gates with optional diffScan present => still well-formed OK(...) (diffScan is optional and captured)
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/3","/5"]\nbuild-gates: { src: "lib", test: "test", ext: "dart", diffScan: "git diff -- lib", gates: [ { name: "analyze", cmd: "flutter analyze" } ] }\n' \
  > "$TMP/bg_diffscan.md"
result=$(parse_config "$TMP/bg_diffscan.md")
[[ "$result" == *"build-gates=OK(src=lib,test=test,ext=dart,diffScan=git diff -- lib,gates=1)"* ]] \
  && ok "build-gates with optional diffScan parses OK + surfaces diffScan" || no "build-gates diffScan: got $result"

# (N+4) enabled-phases contains "/3" — membership recognized
printf 'workflows_enabled: true\ndryRounds: 2\nmaxRounds: 5\nenabled-phases: ["/3","/5"]\n' \
  > "$TMP/phases_with_3.md"
result=$(parse_config "$TMP/phases_with_3.md")
[[ "$result" == *'phases='*'"/3"'* || "$result" == *"phases="*"/3"* ]] \
  && ok 'enabled-phases includes "/3" recognized' || no 'enabled-phases "/3" not recognized: got $result'

echo "config-parser: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
