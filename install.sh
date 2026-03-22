#!/usr/bin/env bash
# install.sh — cc-sentinel Unix installer
# Called by CLAUDE.md conversation script with discovered parameters.
#
# Usage:
#   bash install.sh --modules "core,verification,..." --target project|global [--bar-style unicode|ascii|auto] [--context-source bundled|canonical] [--dry-run]

set -euo pipefail

# --- Parse arguments ---
MODULES=""
TARGET=""
BAR_STYLE="auto"
CONTEXT_SOURCE="bundled"
DRY_RUN="false"
SENTINEL_ROOT="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --modules) MODULES="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --bar-style) BAR_STYLE="$2"; shift 2 ;;
    --context-source) CONTEXT_SOURCE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --help|-h)
      echo "Usage: bash install.sh --modules \"core,verification,...\" --target project|global [options]"
      echo ""
      echo "Options:"
      echo "  --modules <list>        Comma-separated module names (core always included)"
      echo "  --target <type>         project (local .claude/) or global (~/.claude/)"
      echo "  --bar-style <style>     unicode, ascii, or auto (default: auto)"
      echo "  --context-source <src>  bundled or canonical (default: bundled)"
      echo "  --dry-run               Show what would be installed without doing it"
      exit 0
      ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$MODULES" ]] && echo "ERROR: --modules required" >&2 && exit 1
[[ -z "$TARGET" ]] && echo "ERROR: --target required" >&2 && exit 1

# --- Determine target directories ---
if [[ "$TARGET" == "global" ]]; then
  CLAUDE_DIR="$HOME/.claude"
  SETTINGS_FILE="$HOME/.claude/settings.json"
  HOOK_PREFIX="$HOME/.claude"
else
  CLAUDE_DIR=".claude"
  SETTINGS_FILE=".claude/settings.json"
  HOOK_PREFIX=".claude"
fi

SCRIPTS_DIR="scripts"

# --- Helper functions (defined before use) ---
log() { echo "[cc-sentinel] $*"; }

# --- Verify prerequisites ---
if ! command -v jq &>/dev/null; then
  echo ""
  log "ERROR: jq is required but not found."
  log "All cc-sentinel hooks use jq for JSON parsing."
  log "Install it: https://jqlang.github.io/jq/download/"
  echo ""
  exit 1
fi

if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
  echo ""
  log "ERROR: Python 3 is required but not found."
  log "The installer uses Python for settings.json merge."
  log "Install it: https://www.python.org/downloads/"
  echo ""
  exit 1
fi
copy_file() {
  local src="$1" dst="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "  WOULD COPY: $src → $dst"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    log "  Copied: $(basename "$dst")"
  fi
}

install_module() {
  local module="$1"
  local module_dir="${SENTINEL_ROOT}/modules/${module}"

  if [[ ! -d "$module_dir" ]]; then
    echo "WARNING: Module directory not found: $module_dir" >&2
    return
  fi

  log "Installing module: $module"

  # Hooks
  if [[ -d "$module_dir/hooks" ]]; then
    for f in "$module_dir"/hooks/*; do
      [[ ! -f "$f" ]] && continue
      copy_file "$f" "${CLAUDE_DIR}/hooks/$(basename "$f")"
      [[ "$DRY_RUN" != "true" ]] && chmod +x "${CLAUDE_DIR}/hooks/$(basename "$f")"
    done
  fi

  # Commands
  if [[ -d "$module_dir/commands" ]]; then
    for f in "$module_dir"/commands/*.md; do
      [[ ! -f "$f" ]] && continue
      copy_file "$f" "${CLAUDE_DIR}/commands/$(basename "$f")"
    done
  fi

  # Reference
  if [[ -d "$module_dir/reference" ]]; then
    for f in "$module_dir"/reference/*.md; do
      [[ ! -f "$f" ]] && continue
      copy_file "$f" "${CLAUDE_DIR}/reference/$(basename "$f")"
    done
  fi

  # Agents
  if [[ -d "$module_dir/agents" ]]; then
    for f in "$module_dir"/agents/*.md; do
      [[ ! -f "$f" ]] && continue
      copy_file "$f" "${CLAUDE_DIR}/agents/$(basename "$f")"
    done
  fi

  # Scripts (go to project root scripts/)
  if [[ -d "$module_dir/scripts" ]]; then
    for f in "$module_dir"/scripts/*.sh; do
      [[ ! -f "$f" ]] && continue
      copy_file "$f" "${SCRIPTS_DIR}/$(basename "$f")"
      [[ "$DRY_RUN" != "true" ]] && chmod +x "${SCRIPTS_DIR}/$(basename "$f")"
    done
  fi

  # Skills
  if [[ -d "$module_dir/skills" ]]; then
    for skill_dir in "$module_dir"/skills/*/; do
      [[ ! -d "$skill_dir" ]] && continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      for f in "$skill_dir"*; do
        [[ ! -f "$f" ]] && continue
        copy_file "$f" "${CLAUDE_DIR}/skills/${skill_name}/$(basename "$f")"
      done
    done
  fi

  # Templates (project root or .claude/rules/ for rule stubs)
  if [[ -d "$module_dir/templates" ]]; then
    local rules_templates="design-invariants.md terminology.md"
    for f in "$module_dir"/templates/*.md; do
      [[ ! -f "$f" ]] && continue
      local bname
      bname=$(basename "$f")
      if echo "$rules_templates" | grep -qw "$bname"; then
        local dest="${CLAUDE_DIR}/rules/${bname}"
        if [[ ! -f "$dest" ]]; then
          copy_file "$f" "$dest"
        else
          log "  Skipped (exists): $bname"
        fi
      else
        copy_file "$f" "$bname"
      fi
    done
  fi

  # Config files
  if [[ -d "$module_dir" ]] && [[ -f "$module_dir/protected-files.txt" ]]; then
    copy_file "$module_dir/protected-files.txt" "${CLAUDE_DIR}/protected-files.txt"
  fi

  # claude-md rules
  if [[ -f "$module_dir/claude-md-rules.md" ]]; then
    log "  Rules file available: claude-md-rules.md (will be injected into CLAUDE.md)"
  fi
}

# --- Special handling: Context Awareness ---
install_context_awareness() {
  local module_dir="${SENTINEL_ROOT}/modules/context-awareness"

  if [[ "$CONTEXT_SOURCE" == "canonical" ]]; then
    log "Installing context-awareness from canonical repo..."
    if [[ "$DRY_RUN" == "true" ]]; then
      log "  WOULD CLONE: sdi2200262/cc-context-awareness → ~/.claude/cc-context-awareness"
    else
      if [[ -d "$HOME/.claude/cc-context-awareness" ]]; then
        log "  Canonical cc-context-awareness already exists, updating..."
        cd "$HOME/.claude/cc-context-awareness" && git pull --quiet && cd - > /dev/null
      else
        git clone https://github.com/sdi2200262/cc-context-awareness "$HOME/.claude/cc-context-awareness"
      fi
    fi
  else
    log "Installing bundled context-awareness..."
    local ca_target="${CLAUDE_DIR}/cc-context-awareness"
    for f in "$module_dir"/*.sh "$module_dir"/config.json; do
      [[ ! -f "$f" ]] && continue
      copy_file "$f" "${ca_target}/$(basename "$f")"
      [[ "$DRY_RUN" != "true" && "$f" == *.sh ]] && chmod +x "${ca_target}/$(basename "$f")"
    done
  fi

  # Update bar_style in config
  if [[ "$DRY_RUN" != "true" ]]; then
    local config_target
    if [[ "$CONTEXT_SOURCE" == "canonical" ]]; then
      config_target="$HOME/.claude/cc-context-awareness/config.json"
    else
      config_target="${CLAUDE_DIR}/cc-context-awareness/config.json"
    fi
    if [[ -f "$config_target" ]] && command -v python3 &>/dev/null; then
      _SENTINEL_BAR_STYLE="$BAR_STYLE" python3 -c "
import json, os
with open('$config_target') as f: c = json.load(f)
c['bar_style'] = os.environ.get('_SENTINEL_BAR_STYLE', 'auto')
with open('$config_target', 'w') as f: json.dump(c, f, indent=2)
" 2>/dev/null || true
    fi
  fi

  # Skills
  if [[ -d "$module_dir/skills" ]]; then
    for skill_dir in "$module_dir"/skills/*/; do
      [[ ! -d "$skill_dir" ]] && continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      for f in "$skill_dir"*; do
        [[ ! -f "$f" ]] && continue
        copy_file "$f" "${CLAUDE_DIR}/skills/${skill_name}/$(basename "$f")"
      done
    done
  fi
}

# --- Special handling: Notification ---
install_notification() {
  local module_dir="${SENTINEL_ROOT}/modules/notification"
  local os_type
  os_type="$(uname -s)"

  case "$os_type" in
    Linux*)
      copy_file "$module_dir/flash-linux.sh" "${CLAUDE_DIR}/hooks/flash-notification.sh"
      [[ "$DRY_RUN" != "true" ]] && chmod +x "${CLAUDE_DIR}/hooks/flash-notification.sh"
      ;;
    Darwin*)
      copy_file "$module_dir/flash-macos.sh" "${CLAUDE_DIR}/hooks/flash-notification.sh"
      [[ "$DRY_RUN" != "true" ]] && chmod +x "${CLAUDE_DIR}/hooks/flash-notification.sh"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      copy_file "$module_dir/flash.ps1" "${CLAUDE_DIR}/hooks/flash.ps1"
      log "  Windows notification: flash.ps1"
      ;;
    *)
      log "  WARNING: Unknown OS for notification. Skipping."
      ;;
  esac
}

# --- Settings.json merge ---
merge_settings() {
  log "Merging hook registrations into settings.json..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  WOULD MERGE: hook registrations into $SETTINGS_FILE"
    return
  fi

  # Create settings.json if it doesn't exist
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
  fi

  # Use Python for JSON merge (jq not guaranteed on all systems)
  python3 << 'PYEOF'
import json, sys, os

sentinel_root = os.environ.get("SENTINEL_ROOT", ".")
modules_str = os.environ.get("MODULES", "")
settings_file = os.environ.get("SETTINGS_FILE", "")
hook_prefix = os.environ.get("HOOK_PREFIX", ".claude")
target = os.environ.get("TARGET", "project")

modules = [m.strip() for m in modules_str.split(",") if m.strip()]

# Read modules.json
with open(os.path.join(sentinel_root, "modules.json")) as f:
    manifest = json.load(f)

# Read existing settings
with open(settings_file) as f:
    settings = json.load(f)

if "hooks" not in settings:
    settings["hooks"] = {}

# For each installed module, merge its settings_merge.hooks
for mod_key in modules:
    mod = manifest["modules"].get(mod_key, {})
    merge = mod.get("settings_merge", {})
    hooks = merge.get("hooks", {})

    for event_type, entries in hooks.items():
        if event_type not in settings["hooks"]:
            settings["hooks"][event_type] = []

        for entry in entries:
            # Rewrite hook command paths based on install target
            new_entry = {"matcher": entry.get("matcher", ""), "hooks": []}
            for hook in entry.get("hooks", []):
                cmd = hook.get("command", "")
                # Replace .claude/ prefix with actual target path
                if target == "global":
                    cmd = cmd.replace(".claude/", os.path.expanduser("~/.claude/"))
                new_hook = dict(hook)
                new_hook["command"] = cmd
                new_entry["hooks"].append(new_hook)

            # Check if this exact matcher already exists
            existing = [e for e in settings["hooks"][event_type] if e.get("matcher") == new_entry["matcher"]]
            if existing:
                # Append hooks to existing matcher entry (avoid duplicates)
                for new_hook in new_entry["hooks"]:
                    cmd = new_hook["command"]
                    if not any(h.get("command") == cmd for h in existing[0].get("hooks", [])):
                        existing[0]["hooks"].append(new_hook)
            else:
                settings["hooks"][event_type].append(new_entry)

    # Handle statusLine
    if "statusLine" in merge:
        sl = dict(merge["statusLine"])
        if target == "global":
            sl["command"] = sl["command"].replace(".claude/", os.path.expanduser("~/.claude/"))
        settings["statusLine"] = sl

# Handle notification module — replace __NOTIFICATION_SCRIPT__ placeholder
import platform
os_name = platform.system()
if os_name == "Linux":
    notif_cmd = f"bash {hook_prefix}/hooks/flash-notification.sh"
elif os_name == "Darwin":
    notif_cmd = f"bash {hook_prefix}/hooks/flash-notification.sh"
elif os_name == "Windows":
    notif_cmd = f"powershell -ExecutionPolicy Bypass -File {hook_prefix}/hooks/flash.ps1"
else:
    notif_cmd = None

if notif_cmd:
    for event_type in settings.get("hooks", {}):
        for entry in settings["hooks"][event_type]:
            for hook in entry.get("hooks", []):
                if hook.get("command") == "__NOTIFICATION_SCRIPT__":
                    hook["command"] = notif_cmd

# Write back
with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)

print(f"Settings merged successfully: {settings_file}")
PYEOF
}

# --- .claudeignore generation ---
generate_claudeignore() {
  log "Generating .claudeignore..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  WOULD GENERATE: .claudeignore based on detected project type"
    return
  fi

  local template=""
  if [[ -f "pubspec.yaml" ]]; then
    template="flutter"
  elif [[ -f "package.json" ]]; then
    template="node"
  elif [[ -f "Cargo.toml" ]]; then
    template="rust"
  elif [[ -f "go.mod" ]]; then
    template="go"
  elif [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]]; then
    template="python"
  fi

  # Always include general template
  local claudeignore=""
  if [[ -f "${SENTINEL_ROOT}/templates/claudeignore/general.claudeignore" ]]; then
    claudeignore=$(cat "${SENTINEL_ROOT}/templates/claudeignore/general.claudeignore")
  fi

  # Add project-specific template
  if [[ -n "$template" ]] && [[ -f "${SENTINEL_ROOT}/templates/claudeignore/${template}.claudeignore" ]]; then
    claudeignore="${claudeignore}"$'\n\n'"# ${template}-specific"$'\n'
    claudeignore="${claudeignore}$(cat "${SENTINEL_ROOT}/templates/claudeignore/${template}.claudeignore")"
  fi

  if [[ -n "$claudeignore" ]]; then
    if [[ -f ".claudeignore" ]]; then
      log "  .claudeignore already exists — appending new entries"
      echo "" >> .claudeignore
      echo "# Added by cc-sentinel" >> .claudeignore
      echo "$claudeignore" >> .claudeignore
    else
      echo "$claudeignore" > .claudeignore
      log "  Created .claudeignore"
    fi
  fi
}

# --- .gitignore update ---
update_gitignore() {
  if [[ -d ".git" ]]; then
    if ! grep -q "verification_findings/" .gitignore 2>/dev/null; then
      if [[ "$DRY_RUN" == "true" ]]; then
        log "  WOULD ADD: verification_findings/ to .gitignore"
      else
        echo "" >> .gitignore
        echo "# cc-sentinel working directory" >> .gitignore
        echo "verification_findings/" >> .gitignore
        log "  Added verification_findings/ to .gitignore"
      fi
    fi
  fi
}

# =====================================================================
# MAIN
# =====================================================================

log "cc-sentinel installer"
log "Target: $TARGET ($CLAUDE_DIR)"
log "Modules: $MODULES"
[[ "$DRY_RUN" == "true" ]] && log "DRY RUN — no files will be modified"

echo ""

# Ensure core is always included
if ! echo "$MODULES" | grep -q "core"; then
  MODULES="core,$MODULES"
fi

# Resolve dependencies
resolve_deps() {
  local manifest="$SENTINEL_ROOT/modules.json"
  local resolved="$MODULES"
  local changed="true"
  while [[ "$changed" == "true" ]]; do
    changed="false"
    IFS=',' read -ra check_array <<< "$resolved"
    for mod in "${check_array[@]}"; do
      mod=$(echo "$mod" | tr -d ' ')
      deps=$(jq -r ".modules[\"$mod\"].dependencies[]? // empty" "$manifest" 2>/dev/null)
      for dep in $deps; do
        if ! echo ",$resolved," | grep -q ",$dep,"; then
          resolved="$dep,$resolved"
          changed="true"
          log "  Auto-adding dependency: $dep (required by $mod)"
        fi
      done

    done
  done
  MODULES="$resolved"
}
resolve_deps

# Export for Python subprocess
export SENTINEL_ROOT MODULES SETTINGS_FILE HOOK_PREFIX TARGET

# Install each module
IFS=',' read -ra MOD_ARRAY <<< "$MODULES"
for mod in "${MOD_ARRAY[@]}"; do
  mod=$(echo "$mod" | tr -d ' ')
  case "$mod" in
    context-awareness) install_context_awareness ;;
    notification) install_notification ;;
    *) install_module "$mod" ;;
  esac
done

echo ""

# Merge settings
merge_settings

# Generate .claudeignore
generate_claudeignore

# Update .gitignore
update_gitignore

# Create verification_findings directory
if echo "$MODULES" | grep -q "verification"; then
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p verification_findings/_pending
    log "Created verification_findings/ directory"
  fi
fi

echo ""
log "Installation complete!"
log "Run /self-test to verify your installation."
