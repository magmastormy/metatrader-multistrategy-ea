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

if (-not $SkipSync) {
    Sync-Project -Source $ProjectRoot -Destination $targetDir
} else {
    Write-Host "Skipping sync step as requested." -ForegroundColor Yellow
}

Write-Host """""`n====================================================="""""
Write-Host "   COMPILATION STARTED" -ForegroundColor Cyan
Write-Host "====================================================="

# Find all .mq5 files in the target directory
Write-Host "Searching for .mq5 files in: $targetDir" -ForegroundColor Cyan
$mq5Files = Get-ChildItem -Path $targetDir -Filter "*.mq5" -Recurse

# Exclude known auxiliary scripts that should not be compiled
$excludedRelativePaths = @(
    "TestSocket.mq5",
    "NextGenBrainTrainer.mq5"
)

$mq5Files = $mq5Files | Where-Object {
    # Get relative path after the target directory prefix
    $prefix = "C:\Program Files\MetaTrader 5\MQL5\Experts\metatrader-multistrategy-ea\"
    $rel = $_.FullName
    if ($rel.StartsWith($prefix)) {
        $rel = $rel.Substring($prefix.Length)
    }
    
    $shouldExclude = $false
    foreach ($excluded in $excludedRelativePaths) {
        if ($rel -like "*$excluded*" -or $rel -eq $excluded) {
            $shouldExclude = $true
            Write-Host "Excluding: $rel" -ForegroundColor Yellow
            break
        }
    }
    -not $shouldExclude
}

if ($mq5Files.Count -eq 0) {
    Write-Host "No .mq5 files found in target directory!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($mq5Files.Count) files:" -ForegroundColor Cyan
$mq5Files | ForEach-Object { Write-Host " - $($_.FullName)" -ForegroundColor Gray }

$totalErrors = 0
$compilationResults = @()

# Create unified log file with UTF-8 encoding
$unifiedLogPath = Join-Path $ProjectRoot "compile_logs.log"
"Compilation started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $unifiedLogPath -Encoding UTF8
"" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append

foreach ($file in $mq5Files) {
    # Get clean relative path after MetaTrader prefix
    $prefix = "C:\Program Files\MetaTrader 5\MQL5\Experts\metatrader-multistrategy-ea\"
    $relPath = $file.FullName
    if ($relPath.StartsWith($prefix)) {
        $relPath = $relPath.Substring($prefix.Length)
    }
    Write-Host "Compiling $relPath" -ForegroundColor White
    
    $logName = "compile_" + $file.BaseName + ".log"
    $logPath = Join-Path $ProjectRoot $logName
    Write-Host "Log path: $logPath" -ForegroundColor Gray
    
    # MetaEditor requires absolute paths
    $compileCmd = "/compile:`"$($file.FullName)`""
    $logCmd = "/log:`"$logPath`""
    
    Write-Host "Executing: $metaEditor $compileCmd $logCmd" -ForegroundColor DarkGray
    
    $process = Start-Process -FilePath $metaEditor -ArgumentList "$compileCmd", "$logCmd" -Wait -PassThru
    $exitCode = $process.ExitCode
    
    Show-Log -Title $logName -Path $logPath
    
    # Append to unified log with UTF-8 encoding
    "=============================================================" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
    "File: $relPath" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
    "Exit Code: $exitCode" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
    "" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
    if (Test-Path -LiteralPath $logPath) {
        Get-Content -Path $logPath -Encoding UTF8 | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
    }
    "" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
    
    $errors = Get-CompileErrors -LogPath $logPath
    $totalErrors += $errors
    
    $compilationResults += [PSCustomObject]@{
        File = $relPath
        ExitCode = $exitCode
        Errors = $errors
    }
}

Write-Host """""`n====================================================="""""
Write-Host "   COMPILATION SUMMARY" -ForegroundColor Cyan
Write-Host "====================================================="

foreach ($result in $compilationResults) {
    $color = if ($result.Errors -eq 0) { "Gray" } else { "Red" }
    Write-Host "$($result.File): Exit Code $($result.ExitCode), Errors: $($result.Errors)" -ForegroundColor $color
}

Write-Host "Total Errors: $totalErrors" -ForegroundColor Gray

# Write summary to unified log
"=============================================================" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
"COMPILATION SUMMARY" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
"=============================================================" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
foreach ($result in $compilationResults) {
    "$($result.File): Exit Code $($result.ExitCode), Errors: $($result.Errors)" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
}
"" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
"Total Errors: $totalErrors" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
"Compilation finished at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append

Write-Host "`nUnified compilation log saved to: $unifiedLogPath" -ForegroundColor Cyan

if ($totalErrors -eq 0) {
    Write-Host "✅ SUCCESS: All files compiled with 0 errors!" -ForegroundColor Green
    Write-Host "Your EA is ready in MetaTrader 5." -ForegroundColor Green
}
else {
    Write-Host "❌ FAILED: Review the logs above and address the errors." -ForegroundColor Red
}

exit $totalErrors
