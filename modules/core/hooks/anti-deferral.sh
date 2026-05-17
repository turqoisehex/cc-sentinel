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
# Tier 1b: Design-doc deferral phrasing — spec/plan-specific patterns
# These slipped past the original Tier 1 because they appear in formal
# Non-Goals / Out-of-Scope sections where "defer until X" sounds reasoned.
# Rule 0 still applies: no deferral without explicit developer approval.
PUNT="$PUNT|defer until|deferred until"
PUNT="$PUNT|follow-up sprint|follow.up sprint"
PUNT="$PUNT|follow-up task|follow.up task"
PUNT="$PUNT|unchecked (follow.up )?task"
PUNT="$PUNT|at sprint close|on sprint close|when (the )?sprint closes"
PUNT="$PUNT|deferred to a (future|follow.up|later|subsequent)"
PUNT="$PUNT|will be added to.*SPRINT_CHECKLIST"
PUNT="$PUNT|added to.*SPRINT_CHECKLIST.*as (an )?unchecked"
PUNT="$PUNT|retrofit(ted|ting)? deferred|retrofit (is )?deferred"
PUNT="$PUNT|generaliz(e|ation) deferred|generaliz(e|ation) (is )?deferred"
# Section-header sniff — Non-Goals and Out-of-Scope are the usual hiding spots.
# These fire on the header itself so a design doc writing one triggers review.
PUNT="$PUNT|^## (Non.Goals|Out.of.Scope|Follow.ups|Out.of.Scope / Follow.ups)"
PUNT="$PUNT|^### (Non.Goals|Out.of.Scope|Follow.ups)"

# Tier 1c: Phase-handoff deferral — labeling unfinished work as "gaps"
# and pushing it across the /1-/5 sprint boundary. Build (/3) must not
# leave work for quality (/4) or finalize (/5) to inherit. The recap
# idiom "Known gaps for /4:" is the canonical offender — it sounds
# like reasoned status but is unauthorized deferral by another name.
PUNT="$PUNT|(known|remaining|outstanding|pending|carry.over) gaps?( for|:|\b)"
PUNT="$PUNT|gaps? for /[0-9]"
PUNT="$PUNT|gaps? for /(perfect|finalize|build|design|audit|grill|verify)"
PUNT="$PUNT|gaps? (to address|to fix|to resolve|to handle|to tackle) (in|during|at)"
PUNT="$PUNT|(work|wiring|composition|dispatch|hookup|integration|plumbing) (for|in) /[0-9]"
PUNT="$PUNT|(address|fix|resolve|handle|tackle|complete|wire|dispatch) (this |these |it )?in /[0-9]"
PUNT="$PUNT|(address|fix|resolve|handle|tackle|complete) (this |these |it )?in /(perfect|finalize)"
# "needs X-level Y" — passive deferral framing that sounds architectural
PUNT="$PUNT|needs (session.level|future|separate|dedicated|later|subsequent|downstream|upstream) (dispatch|wiring|composition|integration|hookup|work|implementation|plumbing)"
PUNT="$PUNT|(future|later|deferred|separate).session (work|wiring|dispatch|composition|hookup)"
# Recap-section headers that frame unfinished work as acceptable
PUNT="$PUNT|^(Known|Remaining|Outstanding|Carry.over|Pending) (gaps?|work|items?|tasks?)( for|:)"
PUNT="$PUNT|^(## |### )?(Known|Remaining|Outstanding) (gaps?|work) for /[0-9]"

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

if echo "$CONTENT" | grep -qiE "$DEFLECT"; then
  echo '{"additionalContext": "RULE VIOLATION — RESPONSIBILITY DEFLECTION: The content you are writing reclassifies a found issue as pre-existing, known, legacy, or not-your-problem. Rules: (1) If you found it — in a verification squad, /grill, /4, /verify, code review, or any other inspection — you own it. Fix it now, in this body of work, with the same verification treatment as everything else. (2) \"Pre-existing\" is not an exemption. The squad found it because it matters. Roll it into the current fix loop. (3) Do NOT present found issues to the user as \"pre-existing items\" or \"things that could be fixed later.\" Determine what needs to happen and do it. (4) The ONLY valid escape: the developer has typed the word \"defer\" alongside the specific item name in this conversation. Self-authorization does not count."}'
elif echo "$CONTENT" | grep -qiE "$PUNT|$HEDGE"; then
  echo '{"additionalContext": "RULE VIOLATION — FIX IT NOW: The content you are writing contains deferral language. Rules: (1) Never label a known problem as deferred, blocked, or not-urgent without EXPLICIT developer confirmation in this conversation. (2) If you found it, you own it — fix it now, in this body of work. (3) \"Fix it\" means do the actual work, not relabel status text or present options. (4) The ONLY valid escape: the developer has typed the word \"defer\" alongside the specific item name in this conversation. Self-authorization does not count."}'
fi

exit 0
