#!/usr/bin/env bash
# PreToolUse hook: detect deferral language in file edits
# Enforces Rule: "Fix it now" — CC must not unilaterally defer known issues.
# Deferral to CURRENT_TASK.md with a concrete plan is fine.
# Deferral to undocumented future dates ("future sprint", "not urgent") is not.
set -u

INPUT="$(cat)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // ""' | tr -d '\r')"

# Only act on file-writing tools
[[ "$TOOL" != "Write" && "$TOOL" != "Edit" && "$TOOL" != "MultiEdit" ]] && exit 0

# Extract content being written
if [[ "$TOOL" == "Write" ]]; then
  CONTENT="$(echo "$INPUT" | jq -r '.tool_input.content // ""')"
elif [[ "$TOOL" == "MultiEdit" ]]; then
  CONTENT="$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string // empty] | join("\n")')"
else
  CONTENT="$(echo "$INPUT" | jq -r '.tool_input.new_string // ""')"
fi

[[ -z "$CONTENT" ]] && exit 0

# Deferral patterns — phrases CC uses to punt known issues.
# Two tiers: PUNT catches explicit postponement actions,
# HEDGE catches soft language that minimizes or deprioritizes.
#
# Design: "future sprint" is obvious, but CC also defers via
# "separate pass needed", "future work", "deferred (known debt)".
# The word "deferred" alone is too broad (appears in user-decision
# docs and git history). We match it only when CC is the actor:
# "deferred —", "deferred (", "deferred as", "deferred to".
#
# Safe from false positives:
#   "user deferred X"     — has "user" before "deferred"
#   "previously deferred" — past-tense documentation
#   "deferred loading"    — technical term (no punctuation after)

# Tier 1: Explicit postponement — CC pushing work to a later time
PUNT="future (sprint|pass|work|task|session|effort|iteration)"
PUNT="$PUNT|next sprint|later sprint|defer to sprint|defer this"
PUNT="$PUNT|handle this later|address this later|tackle later"
PUNT="$PUNT|out of scope for now|separate (pass|effort|session) needed"
# Split em-dash and paren — [—(] bracket fails under LC_ALL=C (multibyte)
PUNT="$PUNT|deferred —|deferred [(]|deferred as |deferred to "
PUNT="$PUNT|TODO.*(later|future|someday|eventually)"
PUNT="$PUNT|revisit in a future|we can revisit"
PUNT="$PUNT|next session|next conversation|separate session"
PUNT="$PUNT|note.*(for|it).*(next|later)|note this for|flag.*(for|it).*(next|later)"

# Tier 2: Soft minimization — CC downplaying severity to avoid fixing
HEDGE="not urgent|not critical|minor issue|low priority"
# Dot in as.is is intentional wildcard — matches as-is, as is, as.is
HEDGE="$HEDGE|acceptable as.is|good enough for now|can wait"
HEDGE="$HEDGE|when we have more data|once we have more"
HEDGE="$HEDGE|tracked in|tracked as|gaps tracked|to be written"

# Tier 3: Responsibility deflection — framing found work as "not my problem"
#
# Design: CC avoids work by reclassifying it as inherited, pre-existing,
# or someone else's responsibility. The word "blocked" is weaponized to
# make doable-but-laborious tasks sound immovable. "Pre-existing" implies
# "was here before me, therefore not mine to fix." These are all forms of
# deferral that bypass Tier 1/2 patterns.
#
# False positive safety: the warning message includes an escape hatch
# for developer-approved usage. Aggressive matching is intentional —
# better to fire and be overridden than to miss and silently defer.
DEFLECT="pre-existing"
DEFLECT="$DEFLECT|known (issue|bug|debt|problem)"
DEFLECT="$DEFLECT|existing (issue|bug|debt|problem)"
DEFLECT="$DEFLECT|legacy (issue|bug|debt|problem)"
DEFLECT="$DEFLECT|already (broken|wrong|incorrect)"
DEFLECT="$DEFLECT|not (my|our) (problem|responsibility|concern|job)"
DEFLECT="$DEFLECT|inherited (issue|bug|debt|problem)"
DEFLECT="$DEFLECT|outside (my|this|the|current) scope"
DEFLECT="$DEFLECT|someone else.*(fix|handle|address|resolve)"
DEFLECT="$DEFLECT|was (like this|this way) before"

DEFERRAL_PATTERNS="$PUNT|$HEDGE|$DEFLECT"

if echo "$CONTENT" | grep -qiE "$DEFERRAL_PATTERNS"; then
  echo '{"additionalContext": "RULE VIOLATION — FIX IT NOW: The content you are writing contains deferral or responsibility-deflection language. Rules: (1) Never label a known problem as deferred, blocked, pre-existing, or not-my-problem without EXPLICIT developer confirmation. (2) If you found it, you own it — fix it or ask to defer. (3) \"Fix it\" means do the actual work, not relabel status text. If the developer has already approved the deferral, ignore this warning."}'
fi

exit 0
