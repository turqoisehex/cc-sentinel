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

    [string]$BarStyle = "unicode",

    [switch]$DryRun,

    [switch]$ForceOverwrite,

    [switch]$DenyRules
)

$ErrorActionPreference = "Stop"
$SentinelRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# PS 5.1 Join-Path only accepts 2 positional args; this handles N segments.
function Join-Paths([string[]]$Segments) {
    $result = $Segments[0]
    for ($i = 1; $i -lt $Segments.Count; $i++) { $result = Join-Path $result $Segments[$i] }
    return $result
}

# --- Verify prerequisites ---
$jqPath = Get-Command jq -ErrorAction SilentlyContinue
if (-not $jqPath) {
    Write-Host ""
    Write-Host "[cc-sentinel] ERROR: jq is required but not found." -ForegroundColor Red
    Write-Host "[cc-sentinel] Most cc-sentinel hooks use jq for JSON parsing."
    Write-Host "[cc-sentinel] Install it: choco install jq  OR  winget install jqlang.jq"
    Write-Host "[cc-sentinel] Download: https://jqlang.github.io/jq/download/"
    Write-Host ""
    exit 1
}

$bashPath = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bashPath) {
    $gitBashCandidates = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
    )
    foreach ($candidate in $gitBashCandidates) {
        if (Test-Path $candidate) {
            $env:PATH = "$env:PATH;$(Split-Path $candidate)"
            $bashPath = Get-Command bash -ErrorAction SilentlyContinue
            break
        }
    }
}
if (-not $bashPath) {
    Write-Host ""
    Write-Host "[cc-sentinel] ERROR: bash is required but not found." -ForegroundColor Red
    Write-Host "[cc-sentinel] Most cc-sentinel hooks require bash (Git Bash on Windows)."
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
    if (-not (Test-Path ".git")) {
        Write-Host "[cc-sentinel] WARNING: No .git directory in current directory. Run the installer from your project root." -ForegroundColor Yellow
    }
    $ClaudeDir = ".claude"
    $SettingsFile = Join-Path ".claude" "settings.json"
    $HookPrefix = ".claude"
}

if ($Target -eq "global") {
    $ScriptsDir = Join-Paths @($env:USERPROFILE, ".claude", "scripts")
} else {
    $ScriptsDir = "scripts"
}

$script:NotificationSkipped = $false

function Log($msg) { Write-Host "[cc-sentinel] $msg" }

function Write-Utf8NoBom($path, $text) {
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}

function Copy-FileChecked($src, $dst) {
    if ($DryRun) {
        Log "  WOULD COPY: $src -> $dst"
        return
    }
    $dir = Split-Path -Parent $dst
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # Local-preservation: on reinstall, skip files the user has modified locally.
    # Gated by .cc-sentinel-installed marker so fresh installs always proceed.
    # Pass -ForceOverwrite to replace locally-modified files with the canonical source.
    $marker = Join-Path $ClaudeDir ".cc-sentinel-installed"
    if (-not $ForceOverwrite -and (Test-Path $marker) -and (Test-Path $dst)) {
        $srcHash = (Get-FileHash -Path $src -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash -Path $dst -Algorithm SHA256).Hash
        if ($srcHash -ne $dstHash) {
            Log "  SKIPPED (local modifications preserved): $(Split-Path -Leaf $dst)"
            return
        }
    }
    Copy-Item -Path $src -Destination $dst -Force
    Log "  Copied: $(Split-Path -Leaf $dst)"
}

function Install-Module($moduleName) {
    $moduleDir = Join-Paths @($SentinelRoot, "modules", $moduleName)

    if (-not (Test-Path $moduleDir)) {
        Write-Warning "Module directory not found: $moduleDir"
        return
    }

    Log "Installing module: $moduleName"

    # Hooks
    $hooksDir = Join-Path $moduleDir "hooks"
    if (Test-Path $hooksDir) {
        Get-ChildItem $hooksDir -File | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Paths @($ClaudeDir, "hooks", $_.Name))
        }
    }

    # Reference
    $refDir = Join-Path $moduleDir "reference"
    if (Test-Path $refDir) {
        Get-ChildItem $refDir -Filter "*.md" | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Paths @($ClaudeDir, "reference", $_.Name))
        }
    }

    # Agents
    $agentsDir = Join-Path $moduleDir "agents"
    if (Test-Path $agentsDir) {
        Get-ChildItem $agentsDir -Filter "*.md" | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Paths @($ClaudeDir, "agents", $_.Name))
        }
    }

    # Scripts
    $scriptsModDir = Join-Path $moduleDir "scripts"
    if (Test-Path $scriptsModDir) {
        Get-ChildItem $scriptsModDir | Where-Object { $_.Extension -in ".sh",".ps1" -and $_.Name -notlike "setup-*" } | ForEach-Object {
            Copy-FileChecked $_.FullName (Join-Path $ScriptsDir $_.Name)
        }
    }

    # Tools always install globally (shared utilities, not project-specific)
    $toolsDir = Join-Path $moduleDir "tools"
    if (Test-Path $toolsDir) {
        $toolsDest = Join-Paths @($env:USERPROFILE, ".claude", "tools")
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
                Copy-FileChecked $_.FullName (Join-Paths @($ClaudeDir, "skills", $skillName, $_.Name))
            }
        }
    }

    # Templates
    $templatesDir = Join-Path $moduleDir "templates"
    if (Test-Path $templatesDir) {
        $rulesTemplates = @("design-invariants.md", "terminology.md", "plugin-auto-invoke.md")
        Get-ChildItem $templatesDir -Filter "*.md" | ForEach-Object {
            if ($rulesTemplates -contains $_.Name) {
                $dest = Join-Paths @($ClaudeDir, "rules", $_.Name)
                if (-not (Test-Path $dest)) {
                    Copy-FileChecked $_.FullName $dest
                } else {
                    Log "  Skipped (exists): $($_.Name)"
                }
            } else {
                # Non-rules templates: project root for project installs, ~/.claude/templates/ for global
                if ($Target -eq "global") {
                    Copy-FileChecked $_.FullName (Join-Paths @($env:USERPROFILE, ".claude", "templates", $_.Name))
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
        Log "  Rules file available: claude-md-rules.md (inject via CLAUDE.md Step 5 or manual copy)"
    }
}

function Install-ContextAwareness {
    $moduleDir = Join-Paths @($SentinelRoot, "modules", "context-awareness")

    # Windows always uses bundled (only known working Windows version)
    Log "Installing bundled context-awareness (Windows)..."
    $caTarget = Join-Path $ClaudeDir "cc-context-awareness"

    Get-ChildItem $moduleDir -File | Where-Object { $_.Extension -in ".sh", ".json" -or $_.Name -like "*.sh" } | ForEach-Object {
        Copy-FileChecked $_.FullName (Join-Path $caTarget $_.Name)
    }

    # Update bar_style — only on fresh install (not when local config preserved)
    if (-not $DryRun) {
        $configPath = Join-Path $caTarget "config.json"
        $marker = Join-Path $ClaudeDir ".cc-sentinel-installed"
        $isReinstall = Test-Path $marker
        if ((Test-Path $configPath) -and (-not $isReinstall -or $ForceOverwrite)) {
            $config = Get-Content $configPath | ConvertFrom-Json
            if (-not $config.statusline) {
                $config | Add-Member -NotePropertyName "statusline" -NotePropertyValue @{} -Force
            }
            $config.statusline | Add-Member -NotePropertyName "bar_style" -NotePropertyValue $BarStyle -Force
            Write-Utf8NoBom $configPath ($config | ConvertTo-Json -Depth 10)
        }
    }

    # Skills
    $skillsDir = Join-Path $moduleDir "skills"
    if (Test-Path $skillsDir) {
        Get-ChildItem $skillsDir -Directory | ForEach-Object {
            $skillName = $_.Name
            Get-ChildItem $_.FullName -File | ForEach-Object {
                Copy-FileChecked $_.FullName (Join-Paths @($ClaudeDir, "skills", $skillName, $_.Name))
            }
        }
    }
}

function Install-Notification {
    $moduleDir = Join-Paths @($SentinelRoot, "modules", "notification")

    # Conflict detection: warn if settings.json already has notification/flash/alert hooks
    if (Test-Path $SettingsFile) {
        try {
            $existingSettings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
            $conflictFound = $false
            $keywords = @("flash", "notify", "alert", "notification")
            foreach ($event in @("Stop", "Notification")) {
                $eventHooks = $existingSettings.hooks.$event
                if ($eventHooks) {
                    foreach ($entry in $eventHooks) {
                        foreach ($h in $entry.hooks) {
                            $cmd = $h.command.ToLower()
                            foreach ($kw in $keywords) {
                                if ($cmd -match $kw) {
                                    Log "  WARNING: Existing notification hook detected in ${event}: $($h.command)"
                                    $conflictFound = $true
                                }
                            }
                        }
                    }
                }
            }
            if ($conflictFound) {
                Log "  Skipping notification hook installation to avoid duplicate popups."
                Log "  To force install, remove existing notification hooks first."
                $script:NotificationSkipped = $true
                return
            }
        } catch {
            # If settings.json can't be parsed, proceed with install
        }
    }

    # Windows uses flash.ps1
    $src = Join-Path $moduleDir "flash.ps1"
    if (Test-Path $src) {
        Copy-FileChecked $src (Join-Paths @($ClaudeDir, "hooks", "flash.ps1"))
        Log "  Windows notification: flash.ps1"
    }
}

function Merge-Settings {
    param([Parameter(Mandatory)][PSCustomObject]$Settings)

    Log "Merging hook registrations into settings.json..."

    if ($DryRun) {
        Log "  WOULD MERGE: hook registrations into $SettingsFile"
        return $Settings
    }

    $manifest = Get-Content (Join-Path $SentinelRoot "modules.json") -Raw | ConvertFrom-Json

    if (-not $settings.hooks) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{} -Force
    }

    $modList = $Modules -split "," | ForEach-Object { $_.Trim() }
    foreach ($modKey in $modList) {
        if ($modKey -eq "notification" -and $script:NotificationSkipped) { continue }
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
                        # Handle notification placeholder
                        # PowerShell -File does NOT expand ~, so global installs use resolved path
                        if ($cmd -eq "__NOTIFICATION_SCRIPT__") {
                            if ($Target -eq "global") {
                                $resolvedHookPath = Join-Path $env:USERPROFILE ".claude\hooks\flash.ps1"
                                $cmd = "powershell -ExecutionPolicy Bypass -File `"$resolvedHookPath`""
                            } else {
                                $cmd = "powershell -ExecutionPolicy Bypass -File `"$HookPrefix/hooks/flash.ps1`""
                            }
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

                    # Merge hooks (rebuild array to avoid PS5.1 in-place mutation bug)
                    $matcherVal = if ($newEntry.matcher) { $newEntry.matcher } else { "" }
                    $found = $false
                    $newEventArray = @()
                    foreach ($existEntry in @($settings.hooks.$eventType)) {
                        $existMatcher = if ($existEntry.matcher) { $existEntry.matcher } else { "" }
                        if ($existMatcher -eq $matcherVal) {
                            $found = $true
                            $mergedHooks = @($existEntry.hooks)
                            foreach ($nh in $newHooks) {
                                $isDup = $mergedHooks | Where-Object { $_.command -eq $nh.command }
                                if (-not $isDup) {
                                    $mergedHooks += $nh
                                }
                            }
                            $newEventArray += [PSCustomObject]@{
                                matcher = $existMatcher
                                hooks   = $mergedHooks
                            }
                        } else {
                            $newEventArray += $existEntry
                        }
                    }
                    if (-not $found) {
                        $newEventArray += $newEntry
                    }
                    $settings.hooks | Add-Member -NotePropertyName $eventType -NotePropertyValue $newEventArray -Force
                }
            }
        }

        # StatusLine (outside hooks loop — a module may have statusLine without hooks)
        if ($merge.statusLine -and -not $settings.statusLine) {
            $sl = $merge.statusLine.PSObject.Copy()
            if ($Target -eq "global") {
                $sl.command = $sl.command -replace "\.claude/", "~/.claude/"
            }
            $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $sl -Force
        }
    }

    Log "Settings merged."
    return $Settings
}

function Configure-Permissions {
    param([Parameter(Mandatory)][PSCustomObject]$Settings)

    Log "Configuring allow rules for cc-sentinel scripts..."

    if ($DryRun) {
        Log "  WOULD ADD: allow rules to $SettingsFile"
        return $Settings
    }

    if (-not $settings.permissions) {
        $settings | Add-Member -NotePropertyName "permissions" -NotePropertyValue @{} -Force
    }
    if (-not $settings.permissions.allow) {
        $settings.permissions | Add-Member -NotePropertyName "allow" -NotePropertyValue @() -Force
    }

    if ($Target -eq "global") {
        $rules = @(
            "Bash(bash ~/.claude/hooks/*)",
            "Bash(bash ~/.claude/scripts/*)",
            "Bash(bash ~/.claude/cc-context-awareness/*)",
            "Bash(python3 ~/.claude/tools/*)",
            "Bash(python ~/.claude/tools/*)",
            "Bash(powershell *setup-codex*)",
            "Bash(powershell -File *setup-codex*)",
            "Bash(powershell -ExecutionPolicy Bypass *setup-codex*)",
            "Bash(powershell -ExecutionPolicy Bypass -File *flash.ps1*)",
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
            "Bash(python ~/.claude/tools/*)",
            "Bash(powershell *setup-codex*)",
            "Bash(powershell -File *setup-codex*)",
            "Bash(powershell -ExecutionPolicy Bypass *setup-codex*)",
            "Bash(powershell -ExecutionPolicy Bypass -File *flash.ps1*)",
            "Bash(mkdir -p verification_findings/*)",
            "Bash(mkdir -p verification_findings/*/*)",
            "Bash(ls verification_findings/*)",
            "Bash(ls verification_findings/*/*)"
        )
    }

    $added = @()
    $newAllow = @($settings.permissions.allow)
    foreach ($rule in $rules) {
        if ($newAllow -notcontains $rule) {
            $newAllow += $rule
            $added += $rule
        }
    }
    $settings.permissions | Add-Member -NotePropertyName "allow" -NotePropertyValue $newAllow -Force

    if ($added.Count -gt 0) {
        foreach ($r in $added) {
            Log "  Added: $r"
        }
    } else {
        Log "  Allow rules already present"
    }
    return $Settings
}

function Configure-DenyRules {
    param([Parameter(Mandatory)][PSCustomObject]$Settings)

    Log "Configuring deny rules (blocking Read() on media/binary files)..."

    if ($DryRun) {
        Log "  WOULD ADD: deny rules to $SettingsFile"
        return $Settings
    }

    if (-not $settings.permissions) {
        $settings | Add-Member -NotePropertyName "permissions" -NotePropertyValue @{} -Force
    }
    if (-not $settings.permissions.deny) {
        $settings.permissions | Add-Member -NotePropertyName "deny" -NotePropertyValue @() -Force
    }

    $rules = @(
        "Read(*.mp3)", "Read(*.mp4)", "Read(*.avi)", "Read(*.mkv)", "Read(*.mov)",
        "Read(*.wav)", "Read(*.flac)", "Read(*.aac)", "Read(*.ogg)",
        "Read(*.zip)", "Read(*.tar.gz)", "Read(*.tar.bz2)", "Read(*.rar)", "Read(*.7z)",
        "Read(*.exe)", "Read(*.dll)", "Read(*.so)", "Read(*.dylib)"
    )

    $added = @()
    $newDeny = @($settings.permissions.deny)
    foreach ($rule in $rules) {
        if ($newDeny -notcontains $rule) {
            $newDeny += $rule
            $added += $rule
        }
    }
    $settings.permissions | Add-Member -NotePropertyName "deny" -NotePropertyValue $newDeny -Force

    if ($added.Count -gt 0) {
        foreach ($r in $added) {
            Log "  Added deny: $r"
        }
    } else {
        Log "  Deny rules already present"
    }
    return $Settings
}

function New-Claudeignore {
    if ($Target -eq "global") {
        Log "  Skipping .claudeignore for global install (use deny rules instead)"
        return
    }

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
    $generalPath = Join-Paths @($SentinelRoot, "templates", "claudeignore", "general.claudeignore")
    if (Test-Path $generalPath) { $content = Get-Content $generalPath -Raw }

    if ($template) {
        $specificPath = Join-Paths @($SentinelRoot, "templates", "claudeignore", "$template.claudeignore")
        if (Test-Path $specificPath) {
            $content += "`n`n# $template-specific`n"
            $content += Get-Content $specificPath -Raw
        }
    }

    if ($content) {
        if (Test-Path ".claudeignore") {
            $existing = Get-Content ".claudeignore" -Raw
            $newLines = $content -split "`n" | Where-Object { $_.Trim() -and -not $_.StartsWith("#") }
            $missing = $newLines | Where-Object { $existing -notmatch [regex]::Escape($_) }
            if ($missing.Count -gt 0) {
                $appendBlock = ($missing -join "`n")
                Add-Content ".claudeignore" "`n# Added by cc-sentinel`n$appendBlock" -Encoding UTF8
                Log "  Appended $($missing.Count) new patterns to .claudeignore"
            } else {
                Log "  .claudeignore already has all cc-sentinel patterns"
            }
        } else {
            Write-Utf8NoBom ".claudeignore" "# Added by cc-sentinel`n$content"
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
                Add-Content ".gitignore" "# cc-sentinel working directory`nverification_findings/" -Encoding UTF8
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
$manifestPath = Join-Path $SentinelRoot "modules.json"
if (-not (Test-Path $manifestPath)) {
    Write-Host "[cc-sentinel] ERROR: modules.json not found - the repository may be incomplete." -ForegroundColor Red
    exit 1
}
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$changed = $true
$depIterations = 0
while ($changed) {
    $depIterations++
    if ($depIterations -gt 100) {
        Write-Host "[cc-sentinel] ERROR: Circular dependency detected in modules.json" -ForegroundColor Red
        exit 1
    }
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

# For global installs, rewrite script paths in reference and skill .md files
if ($Target -eq "global" -and -not $DryRun) {
    Log "Rewriting script paths for global install..."
    $refPath = Join-Path $ClaudeDir "reference"
    if (Test-Path $refPath) {
        Get-ChildItem $refPath -Filter "*.md" | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            if ($content -match "(?m)^bash scripts/|``bash scripts/") {
                $content = $content -replace "(?m)(?<=^|``)bash scripts/", "bash ~/.claude/scripts/"
                Write-Utf8NoBom $_.FullName $content
                Log "  Updated paths in: $($_.Name)"
            }
        }
    }

    $skillsPath = Join-Path $ClaudeDir "skills"
    if (Test-Path $skillsPath) {
        Get-ChildItem $skillsPath -Directory | ForEach-Object {
            $skillFile = Join-Path $_.FullName "SKILL.md"
            if (Test-Path $skillFile) {
                $content = Get-Content $skillFile -Raw
                if ($content -match "(?m)^bash scripts/|``bash scripts/") {
                    $content = $content -replace "(?m)(?<=^|``)bash scripts/", "bash ~/.claude/scripts/"
                    Write-Utf8NoBom $skillFile $content
                    Log "  Updated paths in: skills/$($_.Name)/SKILL.md"
                }
            }
        }
    }
}

Write-Host ""

# Single read-modify-write for settings.json (mitigates TOCTOU race and partial-write corruption)
if (-not $DryRun) {
    $settingsDir = Split-Path -Parent $SettingsFile
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
    if (-not (Test-Path $SettingsFile)) { Write-Utf8NoBom $SettingsFile '{}' }

    try {
        $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    } catch {
        Write-Error "ERROR: $SettingsFile contains invalid JSON. Please fix or delete the file and re-run the installer."
        exit 1
    }
    if ($null -eq $settings) { $settings = [PSCustomObject]@{} }

    $settings = Merge-Settings -Settings $settings
    # Safety net: conversation (CLAUDE.md section 4c) writes permissions first; installer re-adds any missed
    $settings = Configure-Permissions -Settings $settings
    if ($DenyRules) { $settings = Configure-DenyRules -Settings $settings }

    # Write to temp then move (mitigates partial-write corruption)
    $tmpFile = "$SettingsFile.tmp"
    Write-Utf8NoBom $tmpFile ($settings | ConvertTo-Json -Depth 10)
    try {
        Move-Item -Path $tmpFile -Destination $SettingsFile -Force
    } catch {
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        Write-Error "ERROR: Failed to write $SettingsFile - $($_.Exception.Message)"
        exit 1
    }
    Log "Settings written: $SettingsFile"
} else {
    Merge-Settings -Settings ([PSCustomObject]@{})
    Configure-Permissions -Settings ([PSCustomObject]@{})
    if ($DenyRules) { Configure-DenyRules -Settings ([PSCustomObject]@{}) }
}

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
    $spawnPath = Join-Paths @($env:USERPROFILE, ".claude", "tools", "spawn.py")
    $spawnJsonPath = Join-Paths @($env:USERPROFILE, ".claude", "tools", "spawn.json")
    if (Test-Path $spawnPath) {
        if ($DryRun) {
            Log "  WOULD RUN: spawn.py --setup"
        } else {
            Log "Configuring spawn (auto-detect terminal + key sender)..."
            try {
                & python $spawnPath --setup 2>$null
            } catch {
                Log "  spawn.py --setup failed - run manually: python ~/.claude/tools/spawn.py --setup"
            }
            # Write default startup_delay to spawn.json
            $spawnJson = @{}
            if (Test-Path $spawnJsonPath) {
                $spawnJson = Get-Content $spawnJsonPath -Raw | ConvertFrom-Json
            }
            if (-not $spawnJson.startup_delay) {
                $spawnJson | Add-Member -NotePropertyName "startup_delay" -NotePropertyValue 5 -Force
                Write-Utf8NoBom $spawnJsonPath ($spawnJson | ConvertTo-Json -Depth 5)
                Log "  Spawn config: startup_delay = 5s"
            }
        }
    }
}

# Print install summary (so Claude doesn't need to run verification commands)
Write-Host ""
Log "--- Install Summary ---"

$hookCount = 0
$hooksPath = Join-Path $ClaudeDir "hooks"
if (Test-Path $hooksPath) { $hookCount = @(Get-ChildItem $hooksPath -File).Count }
Log "  Hooks:      $hookCount"

$skillCount = 0
$skillsPath = Join-Path $ClaudeDir "skills"
if (Test-Path $skillsPath) {
    Get-ChildItem $skillsPath -Directory | ForEach-Object {
        $skillFile = Join-Path $_.FullName "SKILL.md"
        if (Test-Path $skillFile) { $skillCount++ }
    }
}
Log "  Skills:     $skillCount"

$refCount = 0
$refPath = Join-Path $ClaudeDir "reference"
if (Test-Path $refPath) {
    $refFiles = @(Get-ChildItem $refPath -Filter "*.md")
    $refCount = $refFiles.Count
    foreach ($rf in $refFiles) { Log "    - $($rf.Name)" }
}
Log "  Reference:  $refCount"

$agentCount = 0
$agentPath = Join-Path $ClaudeDir "agents"
if (Test-Path $agentPath) { $agentCount = @(Get-ChildItem $agentPath -Filter "*.md").Count }
Log "  Agents:     $agentCount"

$scriptCount = 0
$scriptPath = Join-Path $ClaudeDir "scripts"
if (Test-Path $scriptPath) { $scriptCount = @(Get-ChildItem $scriptPath -File).Count }
Log "  Scripts:    $scriptCount"

$toolCount = 0
$toolPath = Join-Path $ClaudeDir "tools"
if (Test-Path $toolPath) { $toolCount = @(Get-ChildItem $toolPath -File).Count }
Log "  Tools:      $toolCount"

$claudeMdPath = if ($Target -eq "global") { Join-Path $ClaudeDir "CLAUDE.md" } else { "CLAUDE.md" }
$rulesInjected = $false
if (Test-Path $claudeMdPath) {
    $rulesInjected = (Get-Content $claudeMdPath -Raw) -match "cc-sentinel rules start"
}
Log "  CLAUDE.md:  $(if ($rulesInjected) { 'rules injected' } else { 'pending (inject via Step 5 or --inject-rules)' })"
Log "  Status:     ALL PASS"

# Write the install marker and report file
if (-not $DryRun) {
    $markerPath = Join-Path $ClaudeDir ".cc-sentinel-installed"
    [System.IO.File]::WriteAllText($markerPath, (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))

    # Write install report (Claude can Read this file without shell commands)
    $report = @"
# cc-sentinel install report
Date: $((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))
Target: $Target
Modules: $Modules

## Counts
Hooks: $hookCount
Skills: $skillCount
Reference: $refCount
Agents: $agentCount
Scripts: $scriptCount
Tools: $toolCount

## Reference files
$(if (Test-Path $refPath) { (Get-ChildItem $refPath -Filter "*.md" | ForEach-Object { "- $($_.Name)" }) -join "`n" } else { "none" })

## CLAUDE.md
Rules injected: $rulesInjected

## Status
ALL PASS
"@
    $reportPath = Join-Path $ClaudeDir "install-report.md"
    Write-Utf8NoBom $reportPath $report
}

Write-Host ""
Log "Installation complete."
Log "Run /self-test in your next session to verify everything is working."
Log "Install details: ~/.claude/install-report.md"
