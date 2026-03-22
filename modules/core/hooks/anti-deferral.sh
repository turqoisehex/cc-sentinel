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

# Deferral patterns — phrases CC uses to punt known issues
# These catch "future sprint", "next sprint", "later sprint", "defer to sprint N", etc.
# Deliberately does NOT match "deferred" in past-tense documentation of user decisions.
DEFERRAL_PATTERNS="future sprint|next sprint|later sprint|defer to sprint|defer this|not urgent|minor issue|low priority|acceptable as.is|good enough for now|when we have more data|once we have more|handle this later|address this later|out of scope for now|we can revisit|revisit in a future|not critical|can wait|tackle later|TODO.*(later|future|someday|eventually)"

if echo "$CONTENT" | grep -qiE "$DEFERRAL_PATTERNS"; then
  echo '{"additionalContext": "RULE VIOLATION — FIX IT NOW: The content you are writing contains deferral language. Unbendable rule: Never label a known problem minor, not urgent, deferred, or acceptable without EXPLICIT developer confirmation. If you genuinely believe deferral is correct, ASK the developer — do not decide unilaterally. Deferral is a developer decision, not yours. If the developer has already approved the deferral, ignore this warning."}'
fi

exit 0
