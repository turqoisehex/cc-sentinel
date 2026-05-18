#!/usr/bin/env bash
# install.sh — cc-sentinel Unix installer
# Called by CLAUDE.md conversation script with discovered parameters.
#
# Usage:
#   bash install.sh --modules "core,verification,..." --target project|global [--bar-style unicode|ascii|auto] [--deny-rules] [--inject-rules] [--force-overwrite] [--dry-run]

set -euo pipefail

# --- Parse arguments ---
MODULES=""
TARGET=""
BAR_STYLE="auto"
DRY_RUN="false"
INJECT_RULES="false"
FORCE_OVERWRITE="false"
DENY_RULES="false"
SENTINEL_ROOT="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --modules) MODULES="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --bar-style) BAR_STYLE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --inject-rules) INJECT_RULES="true"; shift ;;
    --force-overwrite) FORCE_OVERWRITE="true"; shift ;;
    --deny-rules) DENY_RULES="true"; shift ;;
    --help|-h)
      echo "Usage: bash install.sh --modules \"core,verification,...\" --target project|global [options]"
      echo ""
      echo "Options:"
      echo "  --modules <list>        Comma-separated module names (core always included)"
      echo "  --target <type>         project (local .claude/) or global (~/.claude/)"
      echo "  --bar-style <style>     unicode, ascii, or auto (default: auto)"
      echo "  --deny-rules            Add deny rules to settings.json permissions"
      echo "  --inject-rules          Inject behavioral rules into CLAUDE.md"
      echo "  --force-overwrite       Overwrite locally-modified files on reinstall (default: preserve)"
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
  CLAUDE_MD="$HOME/.claude/CLAUDE.md"
else
  CLAUDE_DIR=".claude"
  SETTINGS_FILE=".claude/settings.json"
  HOOK_PREFIX=".claude"
  CLAUDE_MD="CLAUDE.md"
fi

if [[ "$TARGET" == "global" ]]; then
  SCRIPTS_DIR="$HOME/.claude/scripts"
else
  SCRIPTS_DIR="scripts"
fi

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

if command -v python3 &>/dev/null; then
  PYTHON="python3"
elif command -v python &>/dev/null; then
  PYTHON="python"
else
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
    return
  fi
  mkdir -p "$(dirname "$dst")"
  # Local-preservation: on reinstall, skip files that the user has modified locally.
  # Gated by the .cc-sentinel-installed marker so fresh installs always proceed.
  # Pass --force-overwrite to replace locally-modified files with the canonical source.
  local marker="${CLAUDE_DIR}/.cc-sentinel-installed"
  if [[ "$FORCE_OVERWRITE" != "true" && -f "$marker" && -f "$dst" ]] && ! cmp -s "$src" "$dst"; then
    log "  SKIPPED (local modifications preserved): $(basename "$dst")"
    return
  fi
  cp "$src" "$dst"
  log "  Copied: $(basename "$dst")"
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
      [[ "$(basename "$f")" == setup-* ]] && continue
      copy_file "$f" "${SCRIPTS_DIR}/$(basename "$f")"
      [[ "$DRY_RUN" != "true" ]] && chmod +x "${SCRIPTS_DIR}/$(basename "$f")"
    done
  fi

  # Tools (go to ~/.claude/tools/)
  if [[ -d "$module_dir/tools" ]]; then
    for f in "$module_dir"/tools/*; do
      [[ ! -f "$f" ]] && continue
      local tools_dir="${HOME}/.claude/tools"
      copy_file "$f" "${tools_dir}/$(basename "$f")"
      [[ "$DRY_RUN" != "true" ]] && chmod +x "${tools_dir}/$(basename "$f")" 2>/dev/null || true
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
    local rules_templates="design-invariants.md terminology.md plugin-auto-invoke.md"
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
        # Non-rules templates: project root for project installs, ~/.claude/templates/ for global
        if [[ "$TARGET" == "global" ]]; then
          copy_file "$f" "${HOME}/.claude/templates/${bname}"
        else
          copy_file "$f" "$bname"
        fi
      fi
    done
  fi

  # Config files
  if [[ -d "$module_dir" ]] && [[ -f "$module_dir/protected-files.txt" ]]; then
    copy_file "$module_dir/protected-files.txt" "${CLAUDE_DIR}/protected-files.txt"
  fi
  if [[ -d "$module_dir" ]] && [[ -f "$module_dir/sensitive-patterns.txt" ]]; then
    copy_file "$module_dir/sensitive-patterns.txt" "${CLAUDE_DIR}/sensitive-patterns.txt"
  fi

  # claude-md rules
  if [[ -f "$module_dir/claude-md-rules.md" ]]; then
    log "  Rules file available: claude-md-rules.md (inject via --inject-rules flag, CLAUDE.md Step 5, or manual copy)"
  fi
}

# --- Special handling: Context Awareness ---
install_context_awareness() {
  local module_dir="${SENTINEL_ROOT}/modules/context-awareness"

  log "Installing bundled context-awareness..."
  local ca_target="${CLAUDE_DIR}/cc-context-awareness"
  for f in "$module_dir"/*.sh "$module_dir"/config.json; do
    [[ ! -f "$f" ]] && continue
    copy_file "$f" "${ca_target}/$(basename "$f")"
    [[ "$DRY_RUN" != "true" && "$f" == *.sh ]] && chmod +x "${ca_target}/$(basename "$f")"
  done

  # Update bar_style in config
  if [[ "$DRY_RUN" != "true" ]]; then
    local config_target="${CLAUDE_DIR}/cc-context-awareness/config.json"
    if [[ -f "$config_target" ]]; then
      _SENTINEL_BAR_STYLE="$BAR_STYLE" _SENTINEL_CONFIG_TARGET="$config_target" "$PYTHON" -c "
import json, os, sys
config_target = os.environ['_SENTINEL_CONFIG_TARGET']
try:
    with open(config_target) as f: c = json.load(f)
except json.JSONDecodeError:
    print('WARNING: config.json contains invalid JSON -- skipping bar_style update.', file=sys.stderr)
    sys.exit(0)
c.setdefault('statusline', {})['bar_style'] = os.environ.get('_SENTINEL_BAR_STYLE', 'auto')
with open(config_target, 'w') as f: json.dump(c, f, indent=2)
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

  # Conflict detection: warn if settings.json already has notification/flash/alert hooks
  # to prevent duplicate popups per event.
  if [[ -f "$SETTINGS_FILE" ]]; then
    local conflict
    conflict=$("$PYTHON" -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        s = json.load(f)
except Exception:
    sys.exit(0)
hooks = s.get('hooks', {})
keywords = ('flash', 'notify', 'alert', 'notification')
for event, entries in hooks.items():
    if event not in ('Stop', 'Notification'):
        continue
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '').lower()
            if any(k in cmd for k in keywords):
                print(f'  {event}: {h[\"command\"]}')
" 2>/dev/null)
    if [[ -n "$conflict" ]]; then
      log "  WARNING: Existing notification hooks detected in $SETTINGS_FILE:"
      echo "$conflict" | while IFS= read -r line; do log "$line"; done
      log "  Skipping notification hook installation to avoid duplicate popups."
      log "  To force install, remove existing notification hooks first."
      export NOTIFICATION_SKIPPED=1
      return
    fi
  fi

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
  "$PYTHON" << 'PYEOF'
import json, sys, os

sentinel_root = os.environ.get("SENTINEL_ROOT", ".")
modules_str = os.environ.get("MODULES", "")
settings_file = os.environ.get("SETTINGS_FILE", "")
hook_prefix = os.environ.get("HOOK_PREFIX", ".claude")
target = os.environ.get("TARGET", "project")

modules = [m.strip() for m in modules_str.split(",") if m.strip()]
notification_skipped = os.environ.get("NOTIFICATION_SKIPPED", "") == "1"

# Resolve notification placeholder before merge so dedup check sees final commands
import platform
os_name = platform.system()
cmd_prefix = "~/.claude" if target == "global" else hook_prefix
if os_name == "Linux" or os_name == "Darwin":
    notif_cmd = f"bash {cmd_prefix}/hooks/flash-notification.sh"
elif os_name == "Windows":
    notif_cmd = f'powershell.exe -ExecutionPolicy Bypass -File "{cmd_prefix}/hooks/flash.ps1"'
else:
    notif_cmd = None

# Read modules.json
with open(os.path.join(sentinel_root, "modules.json")) as f:
    manifest = json.load(f)

# Read existing settings
try:
    with open(settings_file) as f:
        settings = json.load(f)
except json.JSONDecodeError:
    print(f"ERROR: {settings_file} contains invalid JSON.", file=sys.stderr)
    print("Please fix or delete the file and re-run the installer.", file=sys.stderr)
    sys.exit(1)

if "hooks" not in settings:
    settings["hooks"] = {}

# For each installed module, merge its settings_merge.hooks
for mod_key in modules:
    if mod_key == "notification" and notification_skipped:
        continue
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
                # Resolve notification placeholder to platform-specific command
                if cmd == "__NOTIFICATION_SCRIPT__":
                    if notif_cmd:
                        cmd = notif_cmd
                    else:
                        continue  # Skip unresolvable placeholder on unknown OS
                # Replace .claude/ prefix with global path (keep ~ unexpanded so allow rules match)
                elif target == "global":
                    cmd = cmd.replace(".claude/", "~/.claude/")
                new_hook = dict(hook)
                new_hook["command"] = cmd
                new_entry["hooks"].append(new_hook)

            # Skip entries with no resolvable hooks (e.g., unknown OS with only placeholder)
            if not new_entry["hooks"]:
                continue

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

    # Handle statusLine (only add if absent — preserve existing user statusLine)
    if "statusLine" in merge and "statusLine" not in settings:
        sl = dict(merge["statusLine"])
        if target == "global":
            sl["command"] = sl["command"].replace(".claude/", "~/.claude/")
        settings["statusLine"] = sl

# Write back (atomic: temp file + rename)
import tempfile
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(settings_file) or ".", suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w") as f:
        json.dump(settings, f, indent=2)
    os.replace(tmp_path, settings_file)
except:
    os.unlink(tmp_path)
    raise

print(f"Settings merged successfully: {settings_file}")
PYEOF
}

# --- Permission allow rules ---
configure_permissions() {
  log "Configuring allow rules for cc-sentinel scripts..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  WOULD ADD: allow rules to $SETTINGS_FILE"
    return
  fi

  "$PYTHON" << 'PYEOF'
import json, os

settings_file = os.environ.get("SETTINGS_FILE", "")
target = os.environ.get("TARGET", "project")

with open(settings_file) as f:
    settings = json.load(f)

if "permissions" not in settings:
    settings["permissions"] = {}
if "allow" not in settings["permissions"]:
    settings["permissions"]["allow"] = []

existing = set(settings["permissions"]["allow"])

if target == "global":
    rules = [
        "Bash(bash ~/.claude/hooks/*)",
        "Bash(bash ~/.claude/scripts/*)",
        "Bash(bash ~/.claude/cc-context-awareness/*)",
        "Bash(python3 ~/.claude/tools/*)",
        "Bash(python ~/.claude/tools/*)",
        "Bash(python *.claude?tools?*)",
        "Bash(git *)",
        'Bash(powershell *setup-codex*)',
        'Bash(powershell -File *setup-codex*)',
        'Bash(powershell -ExecutionPolicy Bypass *setup-codex*)',
        "Bash(mkdir -p verification_findings/*)",
        "Bash(mkdir -p verification_findings/*/*)",
        "Bash(ls verification_findings/*)",
        "Bash(ls verification_findings/*/*)",
        "PowerShell(git *)",
        "PowerShell(python *.claude?tools?*)",
        "PowerShell(python ~/.claude/tools/*)",
        "PowerShell(python3 ~/.claude/tools/*)",
        "PowerShell(*setup-codex*)",
        "PowerShell(*flash.ps1*)",
        "PowerShell(*install.ps1*)",
        "PowerShell(*uninstall.ps1*)",
        "PowerShell(mkdir *verification_findings*)",
        "PowerShell(*verification_findings*)",
        "Write(CURRENT_TASK*)",
        "Edit(CURRENT_TASK*)",
        "Write(verification_findings/*)",
        "Edit(verification_findings/*)",
    ]
else:
    rules = [
        "Bash(bash .claude/hooks/*)",
        "Bash(bash scripts/*)",
        "Bash(bash .claude/cc-context-awareness/*)",
        "Bash(python3 ~/.claude/tools/*)",
        "Bash(python ~/.claude/tools/*)",
        "Bash(python *.claude?tools?*)",
        "Bash(git *)",
        'Bash(powershell *setup-codex*)',
        'Bash(powershell -File *setup-codex*)',
        'Bash(powershell -ExecutionPolicy Bypass *setup-codex*)',
        "Bash(mkdir -p verification_findings/*)",
        "Bash(mkdir -p verification_findings/*/*)",
        "Bash(ls verification_findings/*)",
        "Bash(ls verification_findings/*/*)",
        "PowerShell(git *)",
        "PowerShell(python *.claude?tools?*)",
        "PowerShell(python ~/.claude/tools/*)",
        "PowerShell(python3 ~/.claude/tools/*)",
        "PowerShell(*setup-codex*)",
        "PowerShell(*flash.ps1*)",
        "PowerShell(*install.ps1*)",
        "PowerShell(*uninstall.ps1*)",
        "PowerShell(mkdir *verification_findings*)",
        "PowerShell(*verification_findings*)",
        "Write(CURRENT_TASK*)",
        "Edit(CURRENT_TASK*)",
        "Write(verification_findings/*)",
        "Edit(verification_findings/*)",
    ]

added = []
for rule in rules:
    if rule not in existing:
        settings["permissions"]["allow"].append(rule)
        added.append(rule)

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)

if added:
    for r in added:
        print(f"  Added: {r}")
else:
    print("  Allow rules already present")
PYEOF
}

# --- Permission deny rules ---
configure_deny_rules() {
  log "Configuring deny rules (blocking Read() on media/binary files)..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  WOULD ADD: deny rules to $SETTINGS_FILE"
    return
  fi

  "$PYTHON" << 'PYEOF'
import json, os

settings_file = os.environ.get("SETTINGS_FILE", "")

with open(settings_file) as f:
    settings = json.load(f)

if "permissions" not in settings:
    settings["permissions"] = {}
if "deny" not in settings["permissions"]:
    settings["permissions"]["deny"] = []

existing = set(settings["permissions"]["deny"])

rules = [
    "Read(*.mp3)", "Read(*.mp4)", "Read(*.avi)", "Read(*.mkv)", "Read(*.mov)",
    "Read(*.wav)", "Read(*.flac)", "Read(*.aac)", "Read(*.ogg)",
    "Read(*.zip)", "Read(*.tar.gz)", "Read(*.tar.bz2)", "Read(*.rar)", "Read(*.7z)",
    "Read(*.exe)", "Read(*.dll)", "Read(*.so)", "Read(*.dylib)",
]

added = []
for rule in rules:
    if rule not in existing:
        settings["permissions"]["deny"].append(rule)
        added.append(rule)

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)

if added:
    for r in added:
        print(f"  Added deny: {r}")
else:
    print("  Deny rules already present")
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
      if grep -q "Added by cc-sentinel" .claudeignore 2>/dev/null; then
        log "  .claudeignore already has cc-sentinel entries — skipping"
      else
        log "  .claudeignore already exists — appending new entries"
        echo "" >> .claudeignore
        echo "# Added by cc-sentinel" >> .claudeignore
        echo "$claudeignore" >> .claudeignore
      fi
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

# --- Inject CLAUDE.md rules ---
inject_claude_rules() {
  local rules_file="${SENTINEL_ROOT}/modules/core/claude-md-rules.md"
  [[ ! -f "$rules_file" ]] && return

  local target_claude
  if [[ "$TARGET" == "global" ]]; then
    target_claude="${HOME}/.claude/CLAUDE.md"
  else
    target_claude="CLAUDE.md"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  WOULD INJECT: cc-sentinel rules into $target_claude"
    return
  fi

  if [[ -f "$target_claude" ]] && grep -q "cc-sentinel rules start" "$target_claude" 2>/dev/null; then
    log "  cc-sentinel rules already present in $target_claude — skipping"
    return
  fi

  local rules_content
  rules_content=$(cat "$rules_file")

  if [[ -f "$target_claude" ]]; then
    {
      echo ""
      echo "<!-- cc-sentinel rules start -->"
      echo "$rules_content"
      echo "<!-- cc-sentinel rules end -->"
    } >> "$target_claude"
    log "  Injected cc-sentinel rules into existing $target_claude"
  else
    mkdir -p "$(dirname "$target_claude")"
    {
      echo "# CLAUDE.md"
      echo ""
      echo "<!-- cc-sentinel rules start -->"
      echo "$rules_content"
      echo "<!-- cc-sentinel rules end -->"
    } > "$target_claude"
    log "  Created $target_claude with cc-sentinel rules"
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
  local iterations=0
  while [[ "$changed" == "true" ]]; do
    ((iterations++)) || true
    if [[ $iterations -gt 100 ]]; then
      echo "ERROR: Circular dependency detected in modules.json" >&2; exit 1
    fi
    changed="false"
    IFS=',' read -ra check_array <<< "$resolved"
    for mod in "${check_array[@]}"; do
      mod=$(echo "$mod" | tr -d ' ')
      deps=$(jq -r ".modules[\"$mod\"].dependencies[]? // empty" "$manifest" 2>/dev/null | tr -d '\r')
      for dep in $deps; do
        if ! echo ",$resolved," | grep -q ",$dep,"; then
          resolved="$dep,$resolved"
          changed="true"
          log "  Auto-adding dependency: $dep (required by $mod)"
        fi
      done

    done
  done
  # Deduplicate while preserving order
  local seen="" deduped=""
  IFS=',' read -ra dedup_array <<< "$resolved"
  for mod in "${dedup_array[@]}"; do
    mod=$(echo "$mod" | tr -d ' ')
    if ! echo ",$seen," | grep -q ",$mod,"; then
      [[ -n "$deduped" ]] && deduped="$deduped,$mod" || deduped="$mod"
      seen="$seen,$mod"
    fi
  done
  MODULES="$deduped"
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

# For global installs, rewrite script paths in reference and skill .md files
if [[ "$TARGET" == "global" && "$DRY_RUN" != "true" ]]; then
  log "Rewriting script paths for global install..."
  for md_file in "${CLAUDE_DIR}"/reference/*.md; do
    [[ ! -f "$md_file" ]] && continue
    if grep -q 'bash scripts/' "$md_file" 2>/dev/null; then
      tmp_file="${md_file}.tmp"
      sed "s|bash scripts/|bash ~/.claude/scripts/|g" "$md_file" > "$tmp_file" && mv "$tmp_file" "$md_file"
      log "  Updated paths in: $(basename "$md_file")"
    fi
  done
  if [[ -d "${CLAUDE_DIR}/skills" ]]; then
    for skill_file in "${CLAUDE_DIR}"/skills/*/SKILL.md; do
      [[ ! -f "$skill_file" ]] && continue
      if grep -q 'bash scripts/' "$skill_file" 2>/dev/null; then
        tmp_file="${skill_file}.tmp"
        sed "s|bash scripts/|bash ~/.claude/scripts/|g" "$skill_file" > "$tmp_file" && mv "$tmp_file" "$skill_file"
        log "  Updated paths in: skills/$(basename "$(dirname "$skill_file")")/SKILL.md"
      fi
    done
  fi
fi

# Merge settings
merge_settings

# Configure permissions (allow rules for cc-sentinel scripts)
configure_permissions

# Configure deny rules (if requested)
if [[ "$DENY_RULES" == "true" ]]; then
  configure_deny_rules
fi

# Generate .claudeignore (project installs only — global uses deny rules)
if [[ "$TARGET" != "global" ]]; then
  generate_claudeignore
fi

# Inject CLAUDE.md rules (if requested)
if [[ "$INJECT_RULES" == "true" ]]; then
  inject_claude_rules
fi

# Update .gitignore
update_gitignore

# Create verification_findings directory
if echo "$MODULES" | grep -q "verification"; then
  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p verification_findings/_pending_sonnet verification_findings/_pending_opus
    log "Created verification_findings/ directory"
  fi
fi

# Auto-configure spawn (if sprint-pipeline installed)
if echo "$MODULES" | grep -q "sprint-pipeline"; then
  if [[ -f "${HOME}/.claude/tools/spawn.py" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      log "  WOULD RUN: spawn.py --setup"
    else
      log "Configuring spawn (auto-detect terminal + key sender)..."
      "$PYTHON" "${HOME}/.claude/tools/spawn.py" --setup 2>/dev/null || log "  spawn.py --setup failed — run manually: python3 ~/.claude/tools/spawn.py --setup"
      # Write default startup_delay to spawn.json
      spawn_json="${HOME}/.claude/tools/spawn.json"
      if [[ ! -f "$spawn_json" ]] || ! "$PYTHON" -c "import json; d=json.load(open('$spawn_json')); assert 'startup_delay' in d" 2>/dev/null; then
        "$PYTHON" -c "
import json, pathlib
p = pathlib.Path('$spawn_json')
p.parent.mkdir(parents=True, exist_ok=True)
cfg = json.loads(p.read_text()) if p.exists() else {}
cfg.setdefault('startup_delay', 5)
p.write_text(json.dumps(cfg, indent=2))
print('  Spawn config: startup_delay =', cfg['startup_delay'])
"
      fi
    fi
  fi
fi

# Count installed artifacts
SKILL_COUNT=0; HOOK_COUNT=0; SCRIPT_COUNT=0; REF_COUNT=0
if [[ -d "${CLAUDE_DIR}/skills" ]]; then
  for f in "${CLAUDE_DIR}"/skills/*/SKILL.md; do [[ -f "$f" ]] && SKILL_COUNT=$((SKILL_COUNT + 1)); done
fi
if [[ -d "${CLAUDE_DIR}/hooks" ]]; then
  HOOK_COUNT=$(find "${CLAUDE_DIR}/hooks" -maxdepth 1 -type f 2>/dev/null | wc -l)
fi
if [[ -d "$SCRIPTS_DIR" ]]; then
  SCRIPT_COUNT=$(find "$SCRIPTS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
fi
if [[ -d "${CLAUDE_DIR}/reference" ]]; then
  REF_COUNT=$(find "${CLAUDE_DIR}/reference" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l)
fi
log "  Hooks: $HOOK_COUNT  Skills: $SKILL_COUNT  Scripts: $SCRIPT_COUNT  Reference: $REF_COUNT"

# Write the install marker. On subsequent reinstalls, copy_file() uses this
# marker to gate local-preservation: files present and modified are kept as-is
# (pass --force-overwrite to replace). Fresh installs never see the marker so
# they always install canonical content.
REPORT_PATH="${CLAUDE_DIR}/install-report.md"

if [[ "$DRY_RUN" != "true" ]]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${CLAUDE_DIR}/.cc-sentinel-installed"

  # Write install report (Claude can Read this file without shell commands)
  REF_LIST="none"
  if [[ -d "${CLAUDE_DIR}/reference" ]]; then
    REF_LIST=$(ls "${CLAUDE_DIR}/reference/"*.md 2>/dev/null | while read -r f; do echo "- $(basename "$f")"; done)
    [[ -z "$REF_LIST" ]] && REF_LIST="none"
  fi
  cat > "$REPORT_PATH" <<REPORT
# cc-sentinel install report
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Target: $TARGET
Modules: $MODULES

## Counts
Hooks: $HOOK_COUNT
Skills: $SKILL_COUNT
Scripts: $SCRIPT_COUNT
Reference: $REF_COUNT

## Status
$(if grep -q "cc-sentinel rules start" "$CLAUDE_MD" 2>/dev/null; then echo "ALL PASS"; else echo "PASS (CLAUDE.md rules pending — inject via conversation Step 5 or --inject-rules)"; fi)
REPORT
fi

echo ""
log "Installation complete!"
log "Install details: $REPORT_PATH"
log "Start a new Claude Code session, then run /self-test to verify your installation."
