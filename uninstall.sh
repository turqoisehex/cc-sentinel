#!/usr/bin/env bash
# uninstall.sh — cc-sentinel uninstaller
# Removes all cc-sentinel files and settings entries. Additive installs
# mean we know exactly what was added — this reverses it.
set -euo pipefail

# --- Config ---
TARGET="global"
DRY_RUN=false
PYTHON=""

log() { echo "[cc-sentinel] $*"; }

usage() {
  cat <<EOF
Usage: bash uninstall.sh [--target global|project] [--dry-run]

Options:
  --target   global (default) or project
  --dry-run  Show what would be removed without removing it
EOF
  exit 0
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Detect Python ---
for p in python3 python; do
  if command -v "$p" &>/dev/null; then PYTHON="$p"; break; fi
done
[[ -z "$PYTHON" ]] && { log "ERROR: Python 3 required"; exit 1; }

# --- Resolve paths ---
if [[ "$TARGET" == "global" ]]; then
  BASE="$HOME/.claude"
  SETTINGS_FILE="$HOME/.claude/settings.json"
  CLAUDE_MD="$HOME/.claude/CLAUDE.md"
else
  BASE=".claude"
  SETTINGS_FILE=".claude/settings.json"
  CLAUDE_MD="CLAUDE.md"
fi

HOOKS_DIR="$BASE/hooks"
SCRIPTS_DIR="$([[ "$TARGET" == "global" ]] && echo "$BASE/scripts" || echo "scripts")"
SKILLS_DIR="$BASE/skills"
REFERENCE_DIR="$BASE/reference"
TEMPLATES_DIR="$BASE/templates"
TOOLS_DIR="$([[ "$TARGET" == "global" ]] && echo "$BASE/tools" || echo "$HOME/.claude/tools")"
CC_AWARENESS="$([[ "$TARGET" == "global" ]] && echo "$BASE/cc-context-awareness" || echo ".claude/cc-context-awareness")"

# --- Known sentinel files ---
HOOKS=(
  agent-file-reminder.sh anti-deferral.sh auto-checkpoint.sh
  auto-format.sh comment-replacement.sh file-protection.sh
  post-compact-reorient.sh pre-compact-state-save.sh safe-commit.sh
  session-orient.sh stop-task-check.sh flash-notification.sh flash.ps1
)

SCRIPTS=(
  channel_commit.sh heartbeat_watcher.sh wait_for_results.sh wait_for_work.sh
)

SKILLS=(
  1 2 3 4 5 audit build cleanup cold configure-context-awareness
  design finalize grill mistake opus perfect prune-rules rewrite
  self-test sonnet spawn status verify
)

REFERENCE=(
  channel-routing.md operator-cheat-sheet.md
  spec-verification.md verification-squad.md
)

TEMPLATES=(
  channel-template.md current-task-template.md
  design-invariants.md plugin-auto-invoke.md terminology.md
)

TOOLS=(spawn.py spawn.json)

AGENTS=("sonnet-implementer.md" "sonnet-verifier.md" "commit-verifier.md" "commit-adversarial.md" "commit-cold-reader.md")

RULES=(design-invariants.md plugin-auto-invoke.md terminology.md)

CONFIG=(protected-files.txt sensitive-patterns.txt)

# Legacy commands (removed in v1.1, but older installs may still have them)
LEGACY_COMMANDS=(
  1.md 2.md 3.md 4.md 5.md audit.md build.md cleanup.md cold.md
  design.md finalize.md grill.md mistake.md opus.md perfect.md
  prune-rules.md rewrite.md self-test.md sonnet.md spawn.md
  status.md verify.md
)

# --- Remove function ---
removed=0
remove_file() {
  local f="$1"
  if [[ -e "$f" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      log "  WOULD REMOVE: $f"
    else
      rm -rf "$f"
      log "  Removed: $f"
    fi
    ((removed++)) || true
  fi
}

# --- Phase 1: Remove files ---
log "cc-sentinel uninstaller"
log "Target: $TARGET ($BASE)"
log ""
log "Removing sentinel files..."

for f in "${HOOKS[@]}"; do remove_file "$HOOKS_DIR/$f"; done
for f in "${SCRIPTS[@]}"; do remove_file "$SCRIPTS_DIR/$f"; done
for f in "${SKILLS[@]}"; do remove_file "$SKILLS_DIR/$f"; done
for f in "${REFERENCE[@]}"; do remove_file "$REFERENCE_DIR/$f"; done
for f in "${TEMPLATES[@]}"; do remove_file "$TEMPLATES_DIR/$f"; done
for f in "${TOOLS[@]}"; do remove_file "$TOOLS_DIR/$f"; done
for f in "${AGENTS[@]}"; do remove_file "$BASE/agents/$f"; done
for f in "${RULES[@]}"; do remove_file "$BASE/rules/$f"; done
for f in "${CONFIG[@]}"; do remove_file "$BASE/$f"; done

# Legacy commands cleanup (from pre-v1.1 installs)
LEGACY_COMMANDS_DIR="$BASE/commands"
for f in "${LEGACY_COMMANDS[@]}"; do remove_file "$LEGACY_COMMANDS_DIR/$f"; done

# Context awareness
remove_file "$CC_AWARENESS"

# Clean up empty directories
for d in "$HOOKS_DIR" "$SCRIPTS_DIR" "$SKILLS_DIR" \
         "$REFERENCE_DIR" "$TEMPLATES_DIR" "$TOOLS_DIR" \
         "$BASE/rules" "$BASE/agents" "$LEGACY_COMMANDS_DIR"; do
  if [[ -d "$d" ]] && [[ -z "$(ls -A "$d" 2>/dev/null)" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      log "  WOULD REMOVE empty dir: $d"
    else
      rmdir "$d" 2>/dev/null && log "  Removed empty dir: $d" || true
    fi
  fi
done

# Export for Python heredoc subprocesses (Phases 2 and 3)
export SETTINGS_FILE CLAUDE_MD

# --- Phase 2: Clean settings.json ---
if [[ -f "$SETTINGS_FILE" ]]; then
  log ""
  log "Cleaning settings.json..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  WOULD CLEAN: hooks, permissions, statusLine from $SETTINGS_FILE"
  else
    "$PYTHON" << 'PYEOF'
import json, os, re

settings_file = os.environ.get("SETTINGS_FILE", "")
if not os.path.exists(settings_file):
    exit(0)

with open(settings_file) as f:
    settings = json.load(f)

changes = []

# Remove sentinel hooks (commands containing sentinel hook/script paths)
sentinel_hook_patterns = [
    "hooks/anti-deferral", "hooks/agent-file-reminder", "hooks/session-orient",
    "hooks/post-compact-reorient", "hooks/pre-compact-state-save",
    "hooks/auto-checkpoint", "hooks/auto-format", "hooks/comment-replacement",
    "hooks/file-protection", "hooks/safe-commit", "hooks/stop-task-check",
    "hooks/flash-notification", "hooks/flash.ps1",
    "scripts/channel_commit", "scripts/wait_for_results", "scripts/wait_for_work",
    "scripts/heartbeat_watcher",
    "cc-context-awareness/context-awareness",
]

if "hooks" in settings:
    for event_type in list(settings["hooks"].keys()):
        original = settings["hooks"][event_type]
        if isinstance(original, list):
            filtered = []
            for hook in original:
                cmd = hook.get("command", "") if isinstance(hook, dict) else ""
                if not any(p in cmd for p in sentinel_hook_patterns):
                    filtered.append(hook)
                else:
                    changes.append(f"  Removed hook: {cmd[:80]}")
            settings["hooks"][event_type] = filtered
            if not filtered:
                del settings["hooks"][event_type]
    if not settings["hooks"]:
        del settings["hooks"]

# Remove sentinel allow rules
sentinel_allow_patterns = [
    "hooks/", "scripts/", "cc-context-awareness/", "tools/",
    "mkdir -p verification_findings", "ls verification_findings",
]

if "permissions" in settings:
    if "allow" in settings["permissions"]:
        original = settings["permissions"]["allow"]
        filtered = [r for r in original
                    if not any(p in r for p in sentinel_allow_patterns)]
        removed_rules = [r for r in original if r not in filtered]
        for r in removed_rules:
            changes.append(f"  Removed allow rule: {r}")
        settings["permissions"]["allow"] = filtered
        if not filtered:
            del settings["permissions"]["allow"]
    if not settings["permissions"] or settings["permissions"] == {}:
        del settings["permissions"]

# Remove statusLine if it's the context-awareness one
if "statusLine" in settings:
    sl = settings["statusLine"]
    cmd = sl.get("command", "") if isinstance(sl, dict) else ""
    if "context-awareness" in cmd:
        del settings["statusLine"]
        changes.append(f"  Removed statusLine: {cmd[:80]}")

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)

for c in changes:
    print(c)
if not changes:
    print("  No sentinel entries found in settings.json")
PYEOF
  fi
fi

# --- Phase 3: Clean CLAUDE.md ---
if [[ -f "$CLAUDE_MD" ]]; then
  log ""
  log "Cleaning CLAUDE.md..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  WOULD REMOVE: cc-sentinel rules block from $CLAUDE_MD"
  else
    "$PYTHON" << 'PYEOF'
import os, re

claude_md = os.environ.get("CLAUDE_MD", "")
if not os.path.exists(claude_md):
    exit(0)

with open(claude_md) as f:
    content = f.read()

# Remove the sentinel rules block
pattern = r'\n?<!-- cc-sentinel rules start -->.*?<!-- cc-sentinel rules end -->\n?'
new_content = re.sub(pattern, '\n', content, flags=re.DOTALL)

if new_content != content:
    # If CLAUDE.md is now empty (only whitespace), remove it
    if not new_content.strip():
        os.remove(claude_md)
        print("  Removed CLAUDE.md (was sentinel-only)")
    else:
        with open(claude_md, "w") as f:
            f.write(new_content)
        print("  Removed cc-sentinel rules block from CLAUDE.md")
else:
    print("  No cc-sentinel rules found in CLAUDE.md")
PYEOF
  fi
fi

# --- Phase 4: Remove cloned repo ---
CLONE_DIR="$HOME/.claude/cc-sentinel"
if [[ -d "$CLONE_DIR" ]]; then
  log ""
  log "Removing cloned cc-sentinel repo..."
  remove_file "$CLONE_DIR"
fi

# Also check /tmp
if [[ -d "/tmp/cc-sentinel" ]]; then
  remove_file "/tmp/cc-sentinel"
fi

# --- Done ---
log ""
if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry run complete. $removed items would be removed."
else
  log "Uninstall complete. $removed items removed."
  log "Restart Claude Code for changes to take effect."
fi
