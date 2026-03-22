#!/usr/bin/env bash
# PreToolUse hook: remind that agents must write findings to files
# Enforces Rule: "Agents write to files" — context shatters; files survive.
# Explore and Plan agents CANNOT write files — the parent must save their output.
set -u

INPUT="$(cat)"
TOOL="$(echo "$INPUT" | jq -r '.tool_name // ""' | tr -d '\r')"

# Only act on Agent tool
[[ "$TOOL" != "Agent" ]] && exit 0

# Check the agent type
AGENT_TYPE="$(echo "$INPUT" | jq -r '.tool_input.subagent_type // "general-purpose"' | tr -d '\r')"

# Explore and Plan agents cannot write files — parent must save their output
if [[ "$AGENT_TYPE" == "Explore" || "$AGENT_TYPE" == "Plan" ]]; then
  echo '{"additionalContext": "RULE 11 — AGENTS WRITE TO FILES: This '"$AGENT_TYPE"' agent CANNOT write files (no Write/Edit tools). When it returns, YOU must immediately write its findings to a file (e.g., verification_findings/agent_*.md) BEFORE launching more agents or proceeding. 4+ agents dumping results to context can shatter the window."}'
else
  # General-purpose and other agents CAN write — check if the prompt includes file-writing instructions
  PROMPT="$(echo "$INPUT" | jq -r '.tool_input.prompt // ""')"
  if ! echo "$PROMPT" | grep -qiE "(write|save|output).*(file|findings|results|report)|verification_findings"; then
    echo '{"additionalContext": "RULE 11 — AGENTS WRITE TO FILES: This agent prompt does not appear to include instructions to write findings to a file. Every agent MUST write findings to disk (e.g., verification_findings/agent_*.md). Add file-writing instructions to the prompt, or plan to save results yourself after the agent returns."}'
  fi
fi

exit 0
