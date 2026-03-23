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

# Tier 2: Soft minimization — CC downplaying severity to avoid fixing
HEDGE="not urgent|not critical|minor issue|low priority"
# Dot in as.is is intentional wildcard — matches as-is, as is, as.is
HEDGE="$HEDGE|acceptable as.is|good enough for now|can wait"
HEDGE="$HEDGE|when we have more data|once we have more"

DEFERRAL_PATTERNS="$PUNT|$HEDGE"

if echo "$CONTENT" | grep -qiE "$DEFERRAL_PATTERNS"; then
  echo '{"additionalContext": "RULE VIOLATION — FIX IT NOW: The content you are writing contains deferral language. Unbendable rule: Never label a known problem minor, not urgent, deferred, or acceptable without EXPLICIT developer confirmation. If you genuinely believe deferral is correct, ASK the developer — do not decide unilaterally. Deferral is a developer decision, not yours. If the developer has already approved the deferral, ignore this warning."}'
fi

exit 0
