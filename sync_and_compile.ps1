param(
    [string]$MetaTraderRoot = "C:\Program Files\MetaTrader 5",
    [string]$ProjectRoot,
    [switch]$SkipSync
)

$ErrorActionPreference = "Stop"

if (-not $ProjectRoot -or [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSCommandPath
}

Set-Location -Path $ProjectRoot

function Resolve-MetaEditor {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }

    return $null
}

function Sync-Project {
    param(
        [string]$Source,
        [string]$Destination
    )

    Write-Host """""`n====================================================="""""
    Write-Host "   SYNCING PROJECT TO METATRADER 5" -ForegroundColor Cyan
    Write-Host "====================================================="
    Write-Host "Source: $Source" -ForegroundColor Gray
    Write-Host "Target: $Destination" -ForegroundColor Gray

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source directory not found: $Source"
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        Write-Host "Creating target directory..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $excludeDirs = @(
        ".git",
        ".vs",
        "x64",
        "Debug",
        "Release",
        ".windsurf",
        "__pycache__"
    )

    $excludeFiles = @("*.exe", "*.pdb", "*.obj", "*.log")

    $robocopyArgs = @(
        $Source,
        $Destination,
        "/MIR",
        "/R:3",
        "/W:1",
        "/NFL",
        "/NDL",
        "/NP"
    )

    foreach ($dir in $excludeDirs) {
        $robocopyArgs += "/XD"
        $robocopyArgs += $dir
    }

    foreach ($file in $excludeFiles) {
        $robocopyArgs += "/XF"
        $robocopyArgs += $file
    }

    $null = & robocopy @robocopyArgs
    $exitCode = $LASTEXITCODE

    if ($exitCode -ge 8) {
        throw "Sync failed with exit code $exitCode"
    }

    Write-Host "Sync completed (robocopy exit code $exitCode)." -ForegroundColor Green
}

function Show-Log {
    param(
        [string]$Title,
        [string]$Path
    )

    Write-Host """""`n[$Title]""""" -ForegroundColor Cyan

    if (Test-Path -LiteralPath $Path) {
        Get-Content -Path $Path | Write-Host
    }
    else {
        Write-Host "Log file not found: $Path" -ForegroundColor Yellow
    }
}

function Get-CompileErrors {
    param([string]$LogPath)

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return 0
    }

    $content = Get-Content -Path $LogPath
    foreach ($line in $content) {
        if ($line -match '([0-9]+)\s+error\(s\)') {
            return [int]$Matches[1]
        }
    }

    return 0
}

$metaEditorCandidates = @(
    Join-Path -Path $MetaTraderRoot -ChildPath "MetaEditor64.exe"
    "C:\Program Files\MetaTrader 5\MetaEditor64.exe",
    "C:\Program Files (x86)\MetaTrader 5\MetaEditor.exe",
    "C:\Program Files\MetaTrader 5\MetaEditor.exe"
)

$metaEditor = Resolve-MetaEditor -Candidates $metaEditorCandidates

if (-not $metaEditor) {
    throw "MetaEditor executable not found. Checked: $([string]::Join(', ', $metaEditorCandidates))"
}

$targetDir = Join-Path $MetaTraderRoot "MQL5\\Experts\\metatrader-multistrategy-ea"
$mainEa = Join-Path $targetDir "MultiStrategyAutonomousEA.mq5"
$trainerEa = Join-Path $targetDir "AIModules\\NextGenBrainTrainer.mq5"
$mainLog = Join-Path $ProjectRoot "compile_full.log"
$trainerLog = Join-Path $ProjectRoot "compile_trainer.log"

if (-not $SkipSync) {
    Sync-Project -Source $ProjectRoot -Destination $targetDir
} else {
    Write-Host "Skipping sync step as requested." -ForegroundColor Yellow
}

Write-Host """""`n====================================================="""""
Write-Host "   COMPILATION STARTED" -ForegroundColor Cyan
Write-Host "====================================================="

Write-Host "Compiling MultiStrategyAutonomousEA.mq5" -ForegroundColor White
$null = & $metaEditor "/compile:$mainEa" "/log:$mainLog"
$mainExit = $LASTEXITCODE

Write-Host "Compiling AIModules\\NextGenBrainTrainer.mq5" -ForegroundColor White
$null = & $metaEditor "/compile:$trainerEa" "/log:$trainerLog"
$trainerExit = $LASTEXITCODE

Show-Log -Title "compile_full.log" -Path $mainLog
Show-Log -Title "compile_trainer.log" -Path $trainerLog

$mainErrors = Get-CompileErrors -LogPath $mainLog
$trainerErrors = Get-CompileErrors -LogPath $trainerLog
$totalErrors = $mainErrors + $trainerErrors

Write-Host """""`n====================================================="""""
Write-Host "   COMPILATION SUMMARY" -ForegroundColor Cyan
Write-Host "====================================================="
Write-Host "MetaEditor exit codes -> Main: $mainExit, Trainer: $trainerExit" -ForegroundColor Gray
Write-Host "Main EA Errors: $mainErrors" -ForegroundColor Gray
Write-Host "Trainer Errors: $trainerErrors" -ForegroundColor Gray
Write-Host "Total Errors: $totalErrors" -ForegroundColor Gray

if ($totalErrors -eq 0) {
    Write-Host "✅ SUCCESS: All files compiled with 0 errors!" -ForegroundColor Green
    Write-Host "Your EA is ready in MetaTrader 5." -ForegroundColor Green
}
else {
    Write-Host "❌ FAILED: Review the logs above and address the errors." -ForegroundColor Red
}

exit $totalErrors
