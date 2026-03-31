#!/usr/bin/env pwsh
# uninstall.ps1 — cc-sentinel Windows uninstaller
param(
    [ValidateSet("global", "project")]
    [string]$Target = "global",
    [switch]$DryRun
)

function Log { param([string]$msg) Write-Host "[cc-sentinel] $msg" }

# --- Resolve paths ---
if ($Target -eq "global") {
    $Base = Join-Path $env:USERPROFILE ".claude"
    $SettingsFile = Join-Path $Base "settings.json"
    $ClaudeMd = Join-Path $Base "CLAUDE.md"
    $ScriptsDir = Join-Path $Base "scripts"
    $CcAwareness = Join-Path $Base "cc-context-awareness"
} else {
    $Base = ".claude"
    $SettingsFile = Join-Path $Base "settings.json"
    $ClaudeMd = "CLAUDE.md"
    $ScriptsDir = "scripts"
    $CcAwareness = Join-Path $Base "cc-context-awareness"
}

$HooksDir = Join-Path $Base "hooks"
$SkillsDir = Join-Path $Base "skills"
$ReferenceDir = Join-Path $Base "reference"
$TemplatesDir = Join-Path $Base "templates"
$ToolsDir = if ($Target -eq "global") { Join-Path $Base "tools" } else { Join-Path $env:USERPROFILE ".claude" "tools" }

# --- Known sentinel files ---
$Hooks = @(
    "agent-file-reminder.sh", "anti-deferral.sh", "auto-checkpoint.sh",
    "auto-format.sh", "comment-replacement.sh", "file-protection.sh",
    "post-compact-reorient.sh", "pre-compact-state-save.sh", "safe-commit.sh",
    "session-orient.sh", "stop-task-check.sh", "flash-notification.sh", "flash.ps1"
)
$Scripts = @("channel_commit.sh", "heartbeat_watcher.sh", "wait_for_results.sh", "wait_for_work.sh")
$Skills = @(
    "1","2","3","4","5","audit","build","cleanup","cold",
    "configure-context-awareness","design","finalize","grill","mistake",
    "opus","perfect","prune-rules","rewrite","self-test","sonnet",
    "spawn","status","verify"
)
$Reference = @("channel-routing.md","operator-cheat-sheet.md","spec-verification.md","verification-squad.md")
$Templates = @("channel-template.md","current-task-template.md","design-invariants.md","plugin-auto-invoke.md","terminology.md")
$Tools = @("spawn.py", "spawn.json")
$Agents = @("sonnet-implementer.md","sonnet-verifier.md","commit-verifier.md","commit-adversarial.md","commit-cold-reader.md")
$Rules = @("design-invariants.md","plugin-auto-invoke.md","terminology.md")
$Config = @("protected-files.txt","sensitive-patterns.txt")

# Legacy commands (removed in v1.1, but older installs may still have them)
$LegacyCommands = @(
    "1.md","2.md","3.md","4.md","5.md","audit.md","build.md","cleanup.md","cold.md",
    "design.md","finalize.md","grill.md","mistake.md","opus.md","perfect.md",
    "prune-rules.md","rewrite.md","self-test.md","sonnet.md","spawn.md",
    "status.md","verify.md"
)

# --- Remove function ---
$script:removed = 0
function Remove-SentinelItem {
    param([string]$Path)
    if (Test-Path $Path) {
        if ($DryRun) {
            Log "  WOULD REMOVE: $Path"
        } else {
            Remove-Item -Recurse -Force $Path
            Log "  Removed: $Path"
        }
        $script:removed++
    }
}

# --- Phase 1: Remove files ---
Log "cc-sentinel uninstaller"
Log "Target: $Target ($Base)"
Log ""
Log "Removing sentinel files..."

foreach ($f in $Hooks) { Remove-SentinelItem (Join-Path $HooksDir $f) }
foreach ($f in $Scripts) { Remove-SentinelItem (Join-Path $ScriptsDir $f) }
foreach ($f in $Skills) { Remove-SentinelItem (Join-Path $SkillsDir $f) }
foreach ($f in $Reference) { Remove-SentinelItem (Join-Path $ReferenceDir $f) }
foreach ($f in $Templates) { Remove-SentinelItem (Join-Path $TemplatesDir $f) }
foreach ($f in $Tools) { Remove-SentinelItem (Join-Path $ToolsDir $f) }
foreach ($f in $Agents) { Remove-SentinelItem (Join-Path $Base "agents" $f) }
foreach ($f in $Rules) { Remove-SentinelItem (Join-Path $Base "rules" $f) }
foreach ($f in $Config) { Remove-SentinelItem (Join-Path $Base $f) }

# Legacy commands cleanup (from pre-v1.1 installs)
$LegacyCommandsDir = Join-Path $Base "commands"
foreach ($f in $LegacyCommands) { Remove-SentinelItem (Join-Path $LegacyCommandsDir $f) }

Remove-SentinelItem $CcAwareness

# Clean empty directories
$AgentsDir = Join-Path $Base "agents"
$RulesDir = Join-Path $Base "rules"
foreach ($d in @($HooksDir,$ScriptsDir,$SkillsDir,$ReferenceDir,$TemplatesDir,$ToolsDir,$AgentsDir,$RulesDir,$LegacyCommandsDir)) {
    if ((Test-Path $d) -and @(Get-ChildItem $d -Force).Count -eq 0) {
        if ($DryRun) { Log "  WOULD REMOVE empty dir: $d" }
        else { Remove-Item $d; Log "  Removed empty dir: $d" }
    }
}

# --- Phase 2: Clean settings.json ---
if (Test-Path $SettingsFile) {
    Log ""
    Log "Cleaning settings.json..."
    if ($DryRun) {
        Log "  WOULD CLEAN: hooks, permissions, statusLine"
    } else {
        $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json

        $hookPatterns = @(
            "hooks/anti-deferral","hooks/agent-file-reminder","hooks/session-orient",
            "hooks/post-compact-reorient","hooks/pre-compact-state-save",
            "hooks/auto-checkpoint","hooks/auto-format","hooks/comment-replacement",
            "hooks/file-protection","hooks/safe-commit","hooks/stop-task-check",
            "hooks/flash-notification","hooks/flash.ps1",
            "scripts/channel_commit","scripts/wait_for_results","scripts/wait_for_work",
            "scripts/heartbeat_watcher","cc-context-awareness/context-awareness"
        )

        if ($settings.hooks) {
            foreach ($eventType in @($settings.hooks.PSObject.Properties.Name)) {
                $hooks = @($settings.hooks.$eventType)
                $filtered = @($hooks | Where-Object {
                    $cmd = if ($_ -is [PSCustomObject]) { $_.command } else { "" }
                    -not ($hookPatterns | Where-Object { $cmd -like "*$_*" })
                })
                if ($filtered.Count -eq 0) {
                    $settings.hooks.PSObject.Properties.Remove($eventType)
                } else {
                    $settings.hooks.$eventType = $filtered
                }
            }
            if (@($settings.hooks.PSObject.Properties).Count -eq 0) {
                $settings.PSObject.Properties.Remove("hooks")
            }
        }

        $allowPatterns = @("hooks/","scripts/","cc-context-awareness/","tools/","mkdir -p verification_findings","ls verification_findings")
        if ($settings.permissions -and $settings.permissions.allow) {
            $settings.permissions.allow = @($settings.permissions.allow | Where-Object {
                $rule = $_; -not ($allowPatterns | Where-Object { $rule -like "*$_*" })
            })
            if ($settings.permissions.allow.Count -eq 0) {
                $settings.permissions.PSObject.Properties.Remove("allow")
            }
            if (@($settings.permissions.PSObject.Properties).Count -eq 0) {
                $settings.PSObject.Properties.Remove("permissions")
            }
        }

        if ($settings.statusLine -and $settings.statusLine.command -like "*context-awareness*") {
            $settings.PSObject.Properties.Remove("statusLine")
            Log "  Removed statusLine"
        }

        $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsFile
        Log "  Cleaned settings.json"
    }
}

# --- Phase 3: Clean CLAUDE.md ---
if (Test-Path $ClaudeMd) {
    Log ""
    Log "Cleaning CLAUDE.md..."
    if ($DryRun) {
        Log "  WOULD REMOVE: cc-sentinel rules block"
    } else {
        $content = Get-Content $ClaudeMd -Raw
        $pattern = '(?s)\n?<!-- cc-sentinel rules start -->.*?<!-- cc-sentinel rules end -->\n?'
        $newContent = [regex]::Replace($content, $pattern, "`n")
        if ($newContent -ne $content) {
            if ([string]::IsNullOrWhiteSpace($newContent)) {
                Remove-Item $ClaudeMd
                Log "  Removed CLAUDE.md (was sentinel-only)"
            } else {
                Set-Content $ClaudeMd $newContent
                Log "  Removed cc-sentinel rules block"
            }
        } else {
            Log "  No cc-sentinel rules found"
        }
    }
}

# --- Phase 4: Remove cloned repo ---
$CloneDir = Join-Path $env:USERPROFILE ".claude" "cc-sentinel"
if (Test-Path $CloneDir) {
    Log ""
    Log "Removing cloned cc-sentinel repo..."
    Remove-SentinelItem $CloneDir
}

# --- Done ---
Log ""
if ($DryRun) {
    Log "Dry run complete. $($script:removed) items would be removed."
} else {
    Log "Uninstall complete. $($script:removed) items removed."
    Log "Restart Claude Code for changes to take effect."
}
