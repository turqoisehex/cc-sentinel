# install.ps1 — cc-sentinel Windows installer
# Called by CLAUDE.md conversation script with discovered parameters.
#
# Usage:
#   powershell -File install.ps1 -Modules "core,verification,..." -Target project|global [-BarStyle unicode|ascii|auto] [-DryRun]

param(
    [Parameter(Mandatory=$true)]
    [string]$Modules,

    [Parameter(Mandatory=$true)]
    [ValidateSet("project", "global")]
    [string]$Target,

    [string]$BarStyle = "auto",

    [ValidateSet("bundled", "canonical")]
    [string]$ContextSource = "bundled",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$SentinelRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Verify prerequisites ---
$jqPath = Get-Command jq -ErrorAction SilentlyContinue
if (-not $jqPath) {
    Write-Host ""
    Write-Host "[cc-sentinel] ERROR: jq is required but not found." -ForegroundColor Red
    Write-Host "[cc-sentinel] All cc-sentinel hooks use jq for JSON parsing."
    Write-Host "[cc-sentinel] Install it: choco install jq  OR  winget install jqlang.jq"
    Write-Host "[cc-sentinel] Download: https://jqlang.github.io/jq/download/"
    Write-Host ""
    exit 1
}

$bashPath = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bashPath) {
    Write-Host ""
    Write-Host "[cc-sentinel] ERROR: bash is required but not found." -ForegroundColor Red
    Write-Host "[cc-sentinel] All cc-sentinel hooks require bash (Git Bash on Windows)."
    Write-Host "[cc-sentinel] Install Git for Windows: https://git-scm.com/download/win"
    Write-Host ""
    exit 1
}

# --- Determine target directories ---
if ($Target -eq "global") {
    $ClaudeDir = Join-Path $env:USERPROFILE ".claude"
    $SettingsFile = Join-Path $ClaudeDir "settings.json"
    $HookPrefix = Join-Path $env:USERPROFILE ".claude"
} else {
    $ClaudeDir = ".claude"
    $SettingsFile = Join-Path ".claude" "settings.json"
    $HookPrefix = ".claude"
}

if ($Target -eq "global") {
    $ScriptsDir = Join-Path $env:USERPROFILE ".claude" "scripts"
} else {
    $ScriptsDir = "scripts"
}

function Log($msg) { Write-Host "[cc-sentinel] $msg" }

function Copy-FileChecked($src, $dst) {
    if ($DryRun) {
        Log "  WOULD COPY: $src -> $dst"
    } else {
        $dir = Split-Path -Parent $dst
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -Path $src -Destination $dst -Force
        Log "  Copied: $(Split-Path -Leaf $dst)"
    }
}

function Install-Module($moduleName) {
    $moduleDir = Join-Path $SentinelRoot "modules" $moduleName

    if (-not (Test-Path $moduleDir)) {
        Write-Warning "Module directory not found: $moduleDir"
        return
    }

    Log "Installing module: $moduleName"

    # Hooks
    $hooksDir = Join-Path $moduleDir "hooks"
    if (Test-Path $hooksDir) {
        Get-ChildItem $hooksDir -File | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Path $ClaudeDir "hooks" $_.Name)
        }
    }

    # Commands
    $cmdsDir = Join-Path $moduleDir "commands"
    if (Test-Path $cmdsDir) {
        Get-ChildItem $cmdsDir -Filter "*.md" | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Path $ClaudeDir "commands" $_.Name)
        }
    }

    # Reference
    $refDir = Join-Path $moduleDir "reference"
    if (Test-Path $refDir) {
        Get-ChildItem $refDir -Filter "*.md" | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Path $ClaudeDir "reference" $_.Name)
        }
    }

    # Agents
    $agentsDir = Join-Path $moduleDir "agents"
    if (Test-Path $agentsDir) {
        Get-ChildItem $agentsDir -Filter "*.md" | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Path $ClaudeDir "agents" $_.Name)
        }
    }

    # Scripts
    $scriptsModDir = Join-Path $moduleDir "scripts"
    if (Test-Path $scriptsModDir) {
        Get-ChildItem $scriptsModDir -Filter "*.sh" | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Path $ScriptsDir $_.Name)
        }
    }

    # Tools (go to ~/.claude/tools/)
    $toolsDir = Join-Path $moduleDir "tools"
    if (Test-Path $toolsDir) {
        $toolsDest = Join-Path $env:USERPROFILE ".claude" "tools"
        Get-ChildItem $toolsDir -File | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Path $toolsDest $_.Name)
        }
    }

    # Skills
    $skillsDir = Join-Path $moduleDir "skills"
    if (Test-Path $skillsDir) {
        Get-ChildItem $skillsDir -Directory | ForEach-Object {
            $skillName = $_.Name
            Get-ChildItem $_.FullName -File | ForEach-Object {
                Copy-FileChecked $_.FullName (Join-Path $ClaudeDir "skills" $skillName $_.Name)
            }
        }
    }

    # Auto-generate skills from commands (for any command without a hand-crafted skill)
    if (Test-Path $cmdsDir) {
        Get-ChildItem $cmdsDir -Filter "*.md" | ForEach-Object {
            $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $skillFile = Join-Path $ClaudeDir "skills" $cmdName "SKILL.md"
            if (-not (Test-Path $skillFile)) {
                # Extract description from first heading: # /name — Description
                $cmdContent = Get-Content $_.FullName -Raw
                $description = ""
                if ($cmdContent -match "^#\s+[^\n]*?—\s*(.+)") {
                    $description = $Matches[1].Trim()
                } elseif ($cmdContent -match "^#\s+(.+)") {
                    $description = $Matches[1].Trim()
                }
                $skillContent = "---`nname: $cmdName`ndescription: $description`n---`n`n$cmdContent"
                if (-not $DryRun) {
                    $skillDir = Join-Path $ClaudeDir "skills" $cmdName
                    if (-not (Test-Path $skillDir)) { New-Item -ItemType Directory -Path $skillDir -Force | Out-Null }
                    $skillContent | Set-Content $skillFile -NoNewline
                    Log "  Auto-generated skill: $cmdName/SKILL.md"
                } else {
                    Log "  WOULD AUTO-GENERATE skill: $cmdName/SKILL.md"
                }
            }
        }
    }

    # Templates
    $templatesDir = Join-Path $moduleDir "templates"
    if (Test-Path $templatesDir) {
        $rulesTemplates = @("design-invariants.md", "terminology.md", "plugin-auto-invoke.md")
        Get-ChildItem $templatesDir -Filter "*.md" | ForEach-Object {
            if ($rulesTemplates -contains $_.Name) {
                $dest = Join-Path $ClaudeDir "rules" $_.Name
                if (-not (Test-Path $dest)) {
                    Copy-FileChecked $_.FullName $dest
                } else {
                    Log "  Skipped (exists): $($_.Name)"
                }
            } else {
                # Non-rules templates: project root for project installs, ~/.claude/templates/ for global
                if ($Target -eq "global") {
                    Copy-FileChecked $_.FullName (Join-Path $env:USERPROFILE ".claude" "templates" $_.Name)
                } else {
                    Copy-FileChecked $_.FullName $_.Name
                }
            }
        }
    }

    # Config files
    $protectedFiles = Join-Path $moduleDir "protected-files.txt"
    if (Test-Path $protectedFiles) {
        Copy-FileChecked $protectedFiles (Join-Path $ClaudeDir "protected-files.txt")
    }
    $sensitivePatterns = Join-Path $moduleDir "sensitive-patterns.txt"
    if (Test-Path $sensitivePatterns) {
        Copy-FileChecked $sensitivePatterns (Join-Path $ClaudeDir "sensitive-patterns.txt")
    }

    # claude-md rules
    $rulesFile = Join-Path $moduleDir "claude-md-rules.md"
    if (Test-Path $rulesFile) {
        Log "  Rules file available: claude-md-rules.md (will be injected into CLAUDE.md)"
    }
}

function Install-ContextAwareness {
    $moduleDir = Join-Path $SentinelRoot "modules" "context-awareness"

    # Windows always uses bundled (only known working Windows version)
    Log "Installing bundled context-awareness (Windows)..."
    $caTarget = Join-Path $ClaudeDir "cc-context-awareness"

    Get-ChildItem $moduleDir -File | Where-Object { $_.Extension -in ".sh", ".json" -or $_.Name -like "*.sh" } | ForEach-Object {
        Copy-FileChecked $_.FullName (Join-Path $caTarget $_.Name)
    }

    # Update bar_style
    if (-not $DryRun) {
        $configPath = Join-Path $caTarget "config.json"
        if (Test-Path $configPath) {
            $config = Get-Content $configPath | ConvertFrom-Json
            if (-not $config.statusline) {
                $config | Add-Member -NotePropertyName "statusline" -NotePropertyValue @{} -Force
            }
            $config.statusline | Add-Member -NotePropertyName "bar_style" -NotePropertyValue $BarStyle -Force
            $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
        }
    }

    # Skills
    $skillsDir = Join-Path $moduleDir "skills"
    if (Test-Path $skillsDir) {
        Get-ChildItem $skillsDir -Directory | ForEach-Object {
            $skillName = $_.Name
            Get-ChildItem $_.FullName -File | ForEach-Object {
                Copy-FileChecked $_.FullName (Join-Path $ClaudeDir "skills" $skillName $_.Name)
            }
        }
    }
}

function Install-Notification {
    $moduleDir = Join-Path $SentinelRoot "modules" "notification"

    # Windows uses flash.ps1
    $src = Join-Path $moduleDir "flash.ps1"
    if (Test-Path $src) {
        Copy-FileChecked $src (Join-Path $ClaudeDir "hooks" "flash.ps1")
        Log "  Windows notification: flash.ps1"
    }
}

function Merge-Settings {
    Log "Merging hook registrations into settings.json..."

    if ($DryRun) {
        Log "  WOULD MERGE: hook registrations into $SettingsFile"
        return
    }

    # Create settings.json if needed
    $settingsDir = Split-Path -Parent $SettingsFile
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
    if (-not (Test-Path $SettingsFile)) { '{}' | Set-Content $SettingsFile }

    try {
        $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    } catch {
        Write-Error "ERROR: $SettingsFile contains invalid JSON. Please fix or delete the file and re-run the installer."
        exit 1
    }
    $manifest = Get-Content (Join-Path $SentinelRoot "modules.json") -Raw | ConvertFrom-Json

    if (-not $settings.hooks) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{} -Force
    }

    $modList = $Modules -split "," | ForEach-Object { $_.Trim() }
    foreach ($modKey in $modList) {
        $mod = $manifest.modules.$modKey
        if (-not $mod) { continue }
        $merge = $mod.settings_merge
        if (-not $merge) { continue }

        if ($merge.hooks) {
            foreach ($prop in $merge.hooks.PSObject.Properties) {
                $eventType = $prop.Name
                $entries = @($prop.Value)

                if (-not $settings.hooks.$eventType) {
                    $settings.hooks | Add-Member -NotePropertyName $eventType -NotePropertyValue @() -Force
                }

                foreach ($entry in $entries) {
                    $newHooks = @()
                    foreach ($hook in $entry.hooks) {
                        $cmd = $hook.command
                        if ($Target -eq "global") {
                            # Use ~/ prefix so allow rules match (bash expands ~ at runtime)
                            $cmd = $cmd -replace "\.claude/", "~/.claude/"
                        }
                        # Windows: wrap bash commands with full path
                        if ($cmd -match "^bash ") {
                            $gitBash = "C:/Program Files/Git/bin/bash.exe"
                            if (Test-Path $gitBash) {
                                # Keep as-is — CC handles bash invocation
                            }
                        }

                        # Handle notification placeholder (use ~/ for global so allow rules match)
                        if ($cmd -eq "__NOTIFICATION_SCRIPT__") {
                            $cmdPrefix = if ($Target -eq "global") { "~/.claude" } else { $HookPrefix }
                            $cmd = "powershell -ExecutionPolicy Bypass -File $cmdPrefix/hooks/flash.ps1"
                        }

                        $newHooks += @{
                            type = $hook.type
                            command = $cmd
                            timeout = $hook.timeout
                        }
                    }

                    $newEntry = @{
                        matcher = if ($entry.matcher) { $entry.matcher } else { "" }
                        hooks = $newHooks
                    }

                    # Append (avoid duplicates by command string)
                    $existing = $settings.hooks.$eventType | Where-Object { $_.matcher -eq $newEntry.matcher }
                    if ($existing) {
                        foreach ($nh in $newHooks) {
                            $isDup = $existing.hooks | Where-Object { $_.command -eq $nh.command }
                            if (-not $isDup) {
                                $existing.hooks += $nh
                            }
                        }
                    } else {
                        $settings.hooks.$eventType += $newEntry
                    }
                }
            }
        }

        # StatusLine (outside hooks loop — a module may have statusLine without hooks)
        if ($merge.statusLine) {
            $sl = $merge.statusLine.PSObject.Copy()
            if ($Target -eq "global") {
                $sl.command = $sl.command -replace "\.claude/", "~/.claude/"
            }
            $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $sl -Force
        }
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsFile
    Log "Settings merged: $SettingsFile"
}

function Configure-Permissions {
    Log "Configuring allow rules for cc-sentinel scripts..."

    if ($DryRun) {
        Log "  WOULD ADD: allow rules to $SettingsFile"
        return
    }

    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json

    if (-not $settings.permissions) {
        $settings | Add-Member -NotePropertyName "permissions" -NotePropertyValue @{} -Force
    }
    if (-not $settings.permissions.allow) {
        $settings.permissions | Add-Member -NotePropertyName "allow" -NotePropertyValue @() -Force
    }

    $existing = @($settings.permissions.allow)

    if ($Target -eq "global") {
        $rules = @(
            "Bash(bash ~/.claude/hooks/*)",
            "Bash(bash ~/.claude/scripts/*)",
            "Bash(bash ~/.claude/cc-context-awareness/*)",
            "Bash(python3 ~/.claude/tools/*)",
            "Bash(mkdir -p verification_findings/*)",
            "Bash(mkdir -p verification_findings/*/*)",
            "Bash(ls verification_findings/*)",
            "Bash(ls verification_findings/*/*)"
        )
    } else {
        $rules = @(
            "Bash(bash .claude/hooks/*)",
            "Bash(bash scripts/*)",
            "Bash(bash .claude/cc-context-awareness/*)",
            "Bash(python3 ~/.claude/tools/*)",
            "Bash(mkdir -p verification_findings/*)",
            "Bash(mkdir -p verification_findings/*/*)",
            "Bash(ls verification_findings/*)",
            "Bash(ls verification_findings/*/*)"
        )
    }

    $added = @()
    foreach ($rule in $rules) {
        if ($existing -notcontains $rule) {
            $settings.permissions.allow += $rule
            $added += $rule
        }
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsFile

    if ($added.Count -gt 0) {
        foreach ($r in $added) {
            Log "  Added: $r"
        }
    } else {
        Log "  Allow rules already present"
    }
}

function New-Claudeignore {
    Log "Generating .claudeignore..."

    if ($DryRun) {
        Log "  WOULD GENERATE: .claudeignore"
        return
    }

    $template = ""
    if (Test-Path "pubspec.yaml") { $template = "flutter" }
    elseif (Test-Path "package.json") { $template = "node" }
    elseif (Test-Path "Cargo.toml") { $template = "rust" }
    elseif (Test-Path "go.mod") { $template = "go" }
    elseif ((Test-Path "setup.py") -or (Test-Path "pyproject.toml")) { $template = "python" }

    $content = ""
    $generalPath = Join-Path $SentinelRoot "templates" "claudeignore" "general.claudeignore"
    if (Test-Path $generalPath) { $content = Get-Content $generalPath -Raw }

    if ($template) {
        $specificPath = Join-Path $SentinelRoot "templates" "claudeignore" "$template.claudeignore"
        if (Test-Path $specificPath) {
            $content += "`n`n# $template-specific`n"
            $content += Get-Content $specificPath -Raw
        }
    }

    if ($content) {
        if (Test-Path ".claudeignore") {
            $existing = Get-Content ".claudeignore" -Raw
            if ($existing -match "Added by cc-sentinel") {
                Log "  .claudeignore already has cc-sentinel entries — skipping"
            } else {
                Add-Content ".claudeignore" "`n# Added by cc-sentinel`n$content"
                Log "  Appended to existing .claudeignore"
            }
        } else {
            $content | Set-Content ".claudeignore"
            Log "  Created .claudeignore"
        }
    }
}

function Update-Gitignore {
    if (Test-Path ".git") {
        $gitignore = if (Test-Path ".gitignore") { Get-Content ".gitignore" -Raw } else { "" }
        if ($gitignore -notmatch "verification_findings/") {
            if ($DryRun) {
                Log "  WOULD ADD: verification_findings/ to .gitignore"
            } else {
                Add-Content ".gitignore" "`n# cc-sentinel working directory`nverification_findings/"
                Log "  Added verification_findings/ to .gitignore"
            }
        }
    }
}

# =====================================================================
# MAIN
# =====================================================================

Log "cc-sentinel installer (Windows)"
Log "Target: $Target ($ClaudeDir)"
Log "Modules: $Modules"
if ($DryRun) { Log "DRY RUN - no files will be modified" }

Write-Host ""

# Ensure core is always included
if ($Modules -notmatch "core") { $Modules = "core,$Modules" }

# Resolve dependencies
$manifest = Get-Content (Join-Path $SentinelRoot "modules.json") -Raw | ConvertFrom-Json
$changed = $true
while ($changed) {
    $changed = $false
    $checkArray = $Modules -split "," | ForEach-Object { $_.Trim() }
    foreach ($mod in $checkArray) {
        $modDef = $manifest.modules.$mod
        if ($modDef -and $modDef.dependencies) {
            foreach ($dep in $modDef.dependencies) {
                if (($Modules -split "," | ForEach-Object { $_.Trim() }) -notcontains $dep) {
                    $Modules = "$dep,$Modules"
                    $changed = $true
                    Log "  Auto-adding dependency: $dep (required by $mod)"
                }
            }
        }
    }
}

# Deduplicate modules (preserving order)
$Modules = (($Modules -split "," | ForEach-Object { $_.Trim() } | Select-Object -Unique) -join ",")

# Install each module
$modArray = $Modules -split "," | ForEach-Object { $_.Trim() }
foreach ($mod in $modArray) {
    switch ($mod) {
        "context-awareness" { Install-ContextAwareness }
        "notification" { Install-Notification }
        default { Install-Module $mod }
    }
}

# For global installs, rewrite script paths in command and reference .md files
if ($Target -eq "global" -and -not $DryRun) {
    Log "Rewriting script paths for global install..."
    foreach ($subdir in @("commands", "reference")) {
        $mdPath = Join-Path $ClaudeDir $subdir
        if (Test-Path $mdPath) {
            Get-ChildItem $mdPath -Filter "*.md" | ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                if ($content -match "bash scripts/") {
                    $content = $content -replace "bash scripts/", "bash ~/.claude/scripts/"
                    $content | Set-Content $_.FullName -NoNewline
                    Log "  Updated paths in: $($_.Name)"
                }
            }
        }
    }

    # Also rewrite paths in skill files
    $skillsPath = Join-Path $ClaudeDir "skills"
    if (Test-Path $skillsPath) {
        Get-ChildItem $skillsPath -Directory | ForEach-Object {
            $skillFile = Join-Path $_.FullName "SKILL.md"
            if (Test-Path $skillFile) {
                $content = Get-Content $skillFile -Raw
                if ($content -match "bash scripts/") {
                    $content = $content -replace "bash scripts/", "bash ~/.claude/scripts/"
                    $content | Set-Content $skillFile -NoNewline
                    Log "  Updated paths in: skills/$($_.Name)/SKILL.md"
                }
            }
        }
    }
}

Write-Host ""
Merge-Settings
Configure-Permissions
New-Claudeignore
Update-Gitignore

# Create verification_findings
if ($Modules -match "verification" -and -not $DryRun) {
    New-Item -ItemType Directory -Path "verification_findings/_pending_sonnet" -Force | Out-Null
    New-Item -ItemType Directory -Path "verification_findings/_pending_opus" -Force | Out-Null
    Log "Created verification_findings/ directory"
}

# Auto-configure spawn (if sprint-pipeline installed)
if ($Modules -match "sprint-pipeline") {
    $spawnPath = Join-Path $env:USERPROFILE ".claude" "tools" "spawn.py"
    if (Test-Path $spawnPath) {
        if ($DryRun) {
            Log "  WOULD RUN: spawn.py --setup"
        } else {
            Log "Configuring spawn (auto-detect terminal + key sender)..."
            try {
                & python3 $spawnPath --setup 2>$null
            } catch {
                Log "  spawn.py --setup failed — run manually: python3 ~/.claude/tools/spawn.py --setup"
            }
        }
    }
}

# Verify all commands have matching skills
$missingSkills = 0
$commandsPath = Join-Path $ClaudeDir "commands"
if (Test-Path $commandsPath) {
    Get-ChildItem $commandsPath -Filter "*.md" | ForEach-Object {
        $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $skillFile = Join-Path $ClaudeDir "skills" $cmdName "SKILL.md"
        if (-not (Test-Path $skillFile)) {
            Log "  WARNING: command '$cmdName' has no matching skill at skills/$cmdName/SKILL.md"
            $missingSkills++
        }
    }
}
if ($missingSkills -eq 0) {
    Log "All commands have matching skills"
} else {
    Log "$missingSkills command(s) missing skills"
}

Write-Host ""
Log "Installation complete!"
Log "Run /self-test to verify your installation."
