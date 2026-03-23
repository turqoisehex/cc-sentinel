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
#   "anti-deferral"       — the hook's own name (in comments)

# Tier 1: Explicit postponement — CC pushing work to a later time
PUNT="future (sprint|pass|work|task|session|effort|iteration)"
PUNT="$PUNT|next sprint|later sprint|defer to sprint|defer this"
PUNT="$PUNT|handle this later|address this later|tackle later"
PUNT="$PUNT|out of scope for now|separate (pass|effort|session) needed"
PUNT="$PUNT|deferred [—(]|deferred as |deferred to "
PUNT="$PUNT|TODO.*(later|future|someday|eventually)"
PUNT="$PUNT|revisit in a future|we can revisit"

# Tier 2: Soft minimization — CC downplaying severity to avoid fixing
HEDGE="not urgent|not critical|minor issue|low priority"
HEDGE="$HEDGE|acceptable as.is|good enough for now|can wait"
HEDGE="$HEDGE|when we have more data|once we have more"

DEFERRAL_PATTERNS="$PUNT|$HEDGE"

if echo "$CONTENT" | grep -qiE "$DEFERRAL_PATTERNS"; then
  echo '{"additionalContext": "RULE VIOLATION — FIX IT NOW: The content you are writing contains deferral language. Unbendable rule: Never label a known problem minor, not urgent, deferred, or acceptable without EXPLICIT developer confirmation. If you genuinely believe deferral is correct, ASK the developer — do not decide unilaterally. Deferral is a developer decision, not yours. If the developer has already approved the deferral, ignore this warning."}'
fi

exit 0
