# setup-codex.ps1 — Probe, install, and verify Codex CLI (Windows)
# Called by cc-sentinel installer after user opts into dual-architecture verification.
#
# Usage: powershell -File setup-codex.ps1 [-Mode ProbeOnly|Install|VerifyAuth]
#
# Output: machine-readable STATUS lines (same vocabulary as setup-codex.sh, minus INSTALL_NEED_SUDO which is Unix-only)

param(
    [ValidateSet("ProbeOnly", "Install", "VerifyAuth")]
    [string]$Mode = "ProbeOnly"
)

$ErrorActionPreference = "Stop"

function Find-Codex {
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($codex) { return $codex.Source }
    $codexCmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
    if ($codexCmd) { return $codexCmd.Source }
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCmd) {
        $npmPrefix = & npm config get prefix 2>$null
        if ($npmPrefix) {
            $directPath = Join-Path $npmPrefix "codex.cmd"
            if (Test-Path $directPath) { return $directPath }
        }
    }
    return $null
}

function Invoke-Probe {
    $bin = Find-Codex
    if ($bin) {
        try {
            $ver = @(& $bin --version 2>$null)[0]
            if (-not $ver) { $ver = "unknown" }
        } catch {
            $ver = "unknown"
        }
        Write-Output "STATUS: FOUND $ver"
    } else {
        Write-Output "STATUS: NOT_FOUND"
    }
}

function Invoke-Install {
    $bin = Find-Codex
    if ($bin) {
        try {
            $ver = @(& $bin --version 2>$null)[0]
            if (-not $ver) { $ver = "unknown" }
        } catch {
            $ver = "unknown"
        }
        Write-Output "STATUS: FOUND $ver"
        return
    }

    # Check for npm
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Write-Output "STATUS: INSTALL_NO_NODE"
        Write-Output "CMD: winget install OpenJS.NodeJS.LTS"
        return
    }

    # On Windows, npm global goes to %AppData% — no elevation needed
    try {
        $npmOutput = & npm install -g @openai/codex 2>&1
        $bin = Find-Codex
        if ($bin) {
            try {
                $ver = @(& $bin --version 2>$null)[0]
                if (-not $ver) { $ver = "unknown" }
            } catch {
                $ver = "unknown"
            }
            Write-Output "STATUS: INSTALLED $ver"
        } else {
            Write-Output "STATUS: INSTALL_FAILED"
            Write-Output "CMD: npm install -g @openai/codex"
            if ($npmOutput) { Write-Output "DETAIL: $($npmOutput | Select-Object -Last 3 | Out-String)" }
        }
    } catch {
        Write-Output "STATUS: INSTALL_FAILED"
        Write-Output "CMD: npm install -g @openai/codex"
        Write-Output "DETAIL: $($_.Exception.Message)"
    }
}

function Find-CodexJs {
    # Resolve the actual codex.js entry point for direct node invocation.
    # Shell wrappers (.cmd/.ps1) cause quoting hell with Start-Process.
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCmd) {
        $npmPrefix = & npm config get prefix 2>$null
        if ($npmPrefix) {
            $jsPath = Join-Path $npmPrefix "node_modules\@openai\codex\bin\codex.js"
            if (Test-Path $jsPath) { return $jsPath }
        }
    }
    # Fallback: derive from codex.cmd location
    $codexCmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
    if ($codexCmd) {
        $dir = Split-Path $codexCmd.Source -Parent
        $jsPath = Join-Path $dir "node_modules\@openai\codex\bin\codex.js"
        if (Test-Path $jsPath) { return $jsPath }
    }
    return $null
}

function Invoke-VerifyAuth {
    $bin = Find-Codex
    if (-not $bin) {
        Write-Output "STATUS: NOT_FOUND"
        return
    }

    # Resolve node.exe and codex.js for direct invocation (avoids .cmd/.ps1 quoting issues)
    $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
    $codexJs = Find-CodexJs

    if (-not $nodeExe -or -not $codexJs) {
        # Fallback: use PS Job with 30s timeout (& operator has no native timeout)
        try {
            $job = Start-Job -ScriptBlock {
                param($b)
                & $b exec -m gpt-4.1-mini --sandbox read-only --skip-git-repo-check --ephemeral "Reply with exactly one word: SENTINEL" 2>&1
            } -ArgumentList $bin
            $null = Wait-Job $job -Timeout 30
            if ($job.State -ne "Completed") {
                Stop-Job $job
                Remove-Job $job -Force
                Write-Output "STATUS: AUTH_FAILED"
                Write-Output "CMD: codex login"
                Write-Output "DETAIL: timed out after 30s"
                return
            }
            $result = Receive-Job $job
            Remove-Job $job -Force
            $resultStr = $result -join "`n"
            if ($resultStr -match "SENTINEL") {
                Write-Output "STATUS: AUTH_OK"
            } elseif ($resultStr -match "auth|login|key|credential|unauthorized|not configured|forbidden|403") {
                Write-Output "STATUS: AUTH_FAILED"
                Write-Output "CMD: codex login"
            } elseif ($resultStr -match "rate.limit|quota|model_not_found|invalid_model|not supported") {
                Write-Output "STATUS: AUTH_OK"
            } else {
                Write-Output "STATUS: AUTH_FAILED"
                Write-Output "CMD: codex login"
                Write-Output "DETAIL: $($result | Select-Object -Last 3 | Out-String)"
            }
        } catch {
            Write-Output "STATUS: AUTH_FAILED"
            Write-Output "CMD: codex login"
            Write-Output "DETAIL: $($_.Exception.Message)"
        }
        return
    }

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $args = @("`"$codexJs`"", "exec", "-m", "gpt-4.1-mini", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral", "`"Reply with exactly one word: SENTINEL`"")
        $proc = Start-Process -FilePath $nodeExe -ArgumentList $args -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -NoNewWindow -PassThru
        $exited = $proc.WaitForExit(30000)
        if (-not $exited) {
            $proc.Kill()
            Write-Output "STATUS: AUTH_FAILED"
            Write-Output "CMD: codex login"
            Write-Output "DETAIL: timed out after 30s"
            return
        }

        $output = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue

        if ($proc.ExitCode -eq 0 -and $output -and $output -match "SENTINEL") {
            Write-Output "STATUS: AUTH_OK"
        } elseif ($proc.ExitCode -eq 0 -and -not $stderr) {
            Write-Output "STATUS: AUTH_OK"
        } else {
            if ($stderr -match "auth|login|key|credential|unauthorized|not configured|forbidden|403") {
                Write-Output "STATUS: AUTH_FAILED"
                Write-Output "CMD: codex login"
            } elseif ($stderr -match "rate.limit|quota") {
                Write-Output "STATUS: AUTH_OK"
            } elseif ($stderr -match "model_not_found|invalid_model|no such model|not supported") {
                Write-Output "STATUS: AUTH_OK"
            } else {
                Write-Output "STATUS: AUTH_FAILED"
                Write-Output "CMD: codex login"
                if ($stderr) { Write-Output "DETAIL: $($stderr.Trim().Split([Environment]::NewLine) | Select-Object -Last 3 | Out-String)" }
            }
        }
    } catch {
        Write-Output "STATUS: AUTH_FAILED"
        Write-Output "CMD: codex login"
        Write-Output "DETAIL: $($_.Exception.Message)"
    } finally {
        Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

switch ($Mode) {
    "ProbeOnly"   { Invoke-Probe }
    "Install"     { Invoke-Install }
    "VerifyAuth"  { Invoke-VerifyAuth }
}
