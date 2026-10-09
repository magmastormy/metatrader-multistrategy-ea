# sync_and_compile.ps1 — Sync project files to Deriv MT5 terminal and compile
# Usage: .\sync_and_compile.ps1 [-SkipCompile] [-KeepLog] [-All]
#   -SkipCompile : sync only, no compilation
#   -KeepLog    : keep per-file compile logs
#   -All        : compile ALL root .mq5 files (default: only the autonomous EA)

param(
    [switch]$SkipCompile = $false,
    [switch]$KeepLog = $false,
    [switch]$All = $false
)

$ErrorActionPreference = "Stop"

# --- Configuration ---
$ProjectRoot = "D:\TraeProjects\metatrader-multistrategy-ea"
$TerminalHash = "FB9A56D617EDDDFE29EE54EBEFFE96C1"
$MQL5Dir = "$env:APPDATA\MetaQuotes\Terminal\$TerminalHash\MQL5"
$MetaEditor = "C:\Program Files\MetaTrader 5 Terminal\MetaEditor64.exe"
$MainEA = "MultiStrategyAutonomousEA.mq5"
$EAFolder = "MultiStrategyAutonomousEA"  # All files go under Experts/MultiStrategyAutonomousEA/

# --- Validate paths ---
if (-not (Test-Path $ProjectRoot)) { throw "Project root not found: $ProjectRoot" }
if (-not (Test-Path $MQL5Dir)) { throw "MT5 MQL5 directory not found: $MQL5Dir" }
if (-not (Test-Path $MetaEditor)) { throw "MetaEditor not found: $MetaEditor" }

# Base destination: Experts/MultiStrategyAutonomousEA/
$EADst = Join-Path $MQL5Dir "Experts\$EAFolder"

# --- Excluded directories (not synced to MT5) ---
$ExcludedDirs = @("Dashboard", "node_modules", ".venv-ea-dashboard", ".trae")

# --- Sync functions ---
function Sync-Directory($Src, $Dst) {
    if (-not (Test-Path $Dst)) { $null = New-Item -ItemType Directory -Path $Dst -Force }
    $count = 0
    $files = @(Get-ChildItem $Src -File | Where-Object { $_.Extension -match '\.(mq[45h]|mqh)$' })
    foreach ($f in $files) {
        $dstFile = Join-Path $Dst $f.Name
        $srcHash = (Get-FileHash $f.FullName -Algorithm MD5).Hash
        $dstHash = ""
        if (Test-Path $dstFile) { $dstHash = (Get-FileHash $dstFile -Algorithm MD5).Hash }
        if ($srcHash -ne $dstHash) {
            try { $null = Copy-Item $f.FullName $dstFile -Force -ErrorAction Stop; $count++ }
            catch { Write-Host "[SYNC] Skipped $($f.Name) (permission denied)" -ForegroundColor Yellow }
        }
    }
    return $count
}

function Sync-AllFiles($Src, $Dst) {
    if (-not (Test-Path $Dst)) { $null = New-Item -ItemType Directory -Path $Dst -Force }
    $count = 0
    $files = @(Get-ChildItem $Src -File)
    foreach ($f in $files) {
        $dstFile = Join-Path $Dst $f.Name
        $srcHash = (Get-FileHash $f.FullName -Algorithm MD5).Hash
        $dstHash = ""
        if (Test-Path $dstFile) { $dstHash = (Get-FileHash $dstFile -Algorithm MD5).Hash }
        if ($srcHash -ne $dstHash) {
            try { $null = Copy-Item $f.FullName $dstFile -Force -ErrorAction Stop; $count++ }
            catch { Write-Host "[SYNC] Skipped $($f.Name) (permission denied)" -ForegroundColor Yellow }
        }
    }
    return $count
}

function Sync-Recursive($Src, $Dst) {
    $total = (Sync-Directory $Src $Dst)
    if ($null -eq $total) { $total = 0 }
    $dirs = @(Get-ChildItem $Src -Directory | Where-Object { $ExcludedDirs -notcontains $_.Name })
    foreach ($d in $dirs) {
        $childDst = Join-Path $Dst $d.Name
        $sub = (Sync-Recursive $d.FullName $childDst)
        if ($null -ne $sub) { $total = [int]$total + [int]$sub }
    }
    return $total
}

function Sync-RecursiveAll($Src, $Dst) {
    $total = (Sync-AllFiles $Src $Dst)
    if ($null -eq $total) { $total = 0 }
    $dirs = @(Get-ChildItem $Src -Directory | Where-Object { $ExcludedDirs -notcontains $_.Name })
    foreach ($d in $dirs) {
        $childDst = Join-Path $Dst $d.Name
        $sub = (Sync-RecursiveAll $d.FullName $childDst)
        if ($null -ne $sub) { $total = [int]$total + [int]$sub }
    }
    return $total
}

# --- Sync root .mq5/.mqh files into EA folder ---
Write-Host "[SYNC] Syncing root .mq5/.mqh files..." -ForegroundColor Cyan
$rootCount = Sync-Directory $ProjectRoot $EADst
Write-Host "[SYNC] Root files: $rootCount files updated"

# --- Sync Core/ ---
Write-Host "[SYNC] Syncing Core/..." -ForegroundColor Cyan
$coreSrc = Join-Path $ProjectRoot "Core"
$coreDst = Join-Path $EADst "Core"
$coreCount = Sync-Recursive $coreSrc $coreDst
Write-Host "[SYNC] Core/: $coreCount files updated"

# --- Sync Strategies/ ---
Write-Host "[SYNC] Syncing Strategies/..." -ForegroundColor Cyan
$stratSrc = Join-Path $ProjectRoot "Strategies"
$stratDst = Join-Path $EADst "Strategies"
$stratCount = Sync-Recursive $stratSrc $stratDst
Write-Host "[SYNC] Strategies/: $stratCount files updated"

# --- Sync AIModules/ ---
Write-Host "[SYNC] Syncing AIModules/..." -ForegroundColor Cyan
$aiSrc = Join-Path $ProjectRoot "AIModules"
$aiDst = Join-Path $EADst "AIModules"
$aiCount = 0
if (Test-Path $aiSrc) {
    $aiCount = Sync-Recursive $aiSrc $aiDst
}
Write-Host "[SYNC] AIModules/: $aiCount files updated"

# --- Sync Interfaces/ ---
Write-Host "[SYNC] Syncing Interfaces/..." -ForegroundColor Cyan
$ifSrc = Join-Path $ProjectRoot "Interfaces"
$ifDst = Join-Path $EADst "Interfaces"
$ifCount = 0
if (Test-Path $ifSrc) {
    $ifCount = Sync-Recursive $ifSrc $ifDst
}
Write-Host "[SYNC] Interfaces/: $ifCount files updated"

# --- Sync Include/ (project sub-dir with Indicators/) ---
Write-Host "[SYNC] Syncing Include/..." -ForegroundColor Cyan
$incSrc = Join-Path $ProjectRoot "Include"
$incDst = Join-Path $EADst "Include"
$incCount = 0
if (Test-Path $incSrc) {
    $incCount = Sync-Recursive $incSrc $incDst
}
Write-Host "[SYNC] Include/: $incCount files updated"

# --- Sync Utilities/ ---
Write-Host "[SYNC] Syncing Utilities/..." -ForegroundColor Cyan
$utilSrc = Join-Path $ProjectRoot "Utilities"
$utilDst = Join-Path $EADst "Utilities"
$utilCount = 0
if (Test-Path $utilSrc) {
    $utilCount = Sync-Recursive $utilSrc $utilDst
}
Write-Host "[SYNC] Utilities/: $utilCount files updated"

# --- Sync MQHModelTrainer/ (training sub-project; required by the root
#     MQHHyperparameterTuner / MQHModelVisualizer / MQHModelEvaluator scripts whose
#     #include "MQHModelTrainer/..." directives resolve relative to the EA folder) ---
Write-Host "[SYNC] Syncing MQHModelTrainer/..." -ForegroundColor Cyan
$mqtSrc = Join-Path $ProjectRoot "MQHModelTrainer"
$mqtDst = Join-Path $EADst "MQHModelTrainer"
$mqtCount = 0
if (Test-Path $mqtSrc) {
    $mqtCount = Sync-Recursive $mqtSrc $mqtDst
}
Write-Host "[SYNC] MQHModelTrainer/: $mqtCount files updated"

# --- Sync Resources/ (all file types, including .bin, .onnx) ---
Write-Host "[SYNC] Syncing Resources/..." -ForegroundColor Cyan
$resSrc = Join-Path $ProjectRoot "Resources"
$resDst = Join-Path $EADst "Resources"
$resCount = 0
if (Test-Path $resSrc) {
    $resCount = Sync-RecursiveAll $resSrc $resDst
}
Write-Host "[SYNC] Resources/: $resCount files updated"

# --- Sync IndicatorManager.mqh into EA folder ---
Write-Host "[SYNC] Syncing IndicatorManager.mqh..." -ForegroundColor Cyan
$imSrc = Join-Path $ProjectRoot "IndicatorManager.mqh"
$imDst = Join-Path $EADst "IndicatorManager.mqh"
$imCount = 0
if (Test-Path $imSrc) {
    $srcHash = (Get-FileHash $imSrc -Algorithm MD5).Hash
    $dstHash = if (Test-Path $imDst) { (Get-FileHash $imDst -Algorithm MD5).Hash } else { "" }
    if ($srcHash -ne $dstHash) {
        Copy-Item $imSrc $imDst -Force
        $imCount = 1
    }
}
Write-Host "[SYNC] IndicatorManager.mqh: $imCount files updated"

# --- Also sync IndicatorManager.mqh to MQL5 Include/ for #include <IndicatorManager.mqh> ---
$imIncDst = Join-Path $MQL5Dir "Include\IndicatorManager.mqh"
if (Test-Path $imSrc) {
    $dstHash2 = if (Test-Path $imIncDst) { (Get-FileHash $imIncDst -Algorithm MD5).Hash } else { "" }
    if ($srcHash -ne $dstHash2) {
        Copy-Item $imSrc $imIncDst -Force
    }
}

# --- Sync Python/ ---
Write-Host "[SYNC] Syncing Python/..." -ForegroundColor Cyan
$pySrc = Join-Path $ProjectRoot "Python"
$pyDst = Join-Path $MQL5Dir "Files\Python"
$pyCount = 0
if (Test-Path $pySrc) {
    if (-not (Test-Path $pyDst)) { $null = New-Item -ItemType Directory -Path $pyDst -Force }
    $pyFiles = @(Get-ChildItem $pySrc -File)
    foreach ($pf in $pyFiles) {
        $dstFile = Join-Path $pyDst $pf.Name
        try { $null = Copy-Item $pf.FullName $dstFile -Force -ErrorAction Stop; $pyCount++ }
        catch { Write-Host "[SYNC] Skipped $($pf.Name) (permission denied)" -ForegroundColor Yellow }
    }
}
Write-Host "[SYNC] Python/: $pyCount files updated"

$totalSynced = $rootCount + $coreCount + $stratCount + $aiCount + $ifCount + $incCount + $utilCount + $mqtCount + $resCount + $imCount + $pyCount
Write-Host "[SYNC] Total: $totalSynced files updated" -ForegroundColor $(if ($totalSynced -gt 0) { "Yellow" } else { "Green" })

if ($SkipCompile) {
    Write-Host "[SYNC] Skipping compilation (-SkipCompile)" -ForegroundColor Gray
    exit 0
}

# --- Compile ONLY the autonomous EA (skip other project .mq5 files) ---
Write-Host ""
Write-Host "[COMPILE] Starting MetaEditor compilation — compiling ONLY $MainEA (other .mq5 files are synced but not compiled)..." -ForegroundColor Cyan

# Only the autonomous EA is compiled by default. Other project .mq5 files (Testing EA,
# trainers, evaluators, exporters, etc.) are still synced but intentionally NOT compiled.
# Pass -All to compile every root .mq5 file.
if ($All) {
    $projectMq5Files = @(Get-ChildItem $ProjectRoot -Filter "*.mq5" -File)
} else {
    $mainEaSrc = Join-Path $ProjectRoot $MainEA
    if (-not (Test-Path $mainEaSrc)) {
        throw "Main EA not found: $mainEaSrc"
    }
    $projectMq5Files = @([System.IO.FileInfo]$mainEaSrc)
}

Write-Host "[COMPILE] Found $($projectMq5Files.Count) project .mq5 file(s) to compile" -ForegroundColor Gray

$totalErrors = 0
$totalWarnings = 0
$results = @()

foreach ($srcFile in $projectMq5Files) {
    $fileName = $srcFile.Name
    $dstFile = Join-Path $EADst $fileName
    
    # Only compile if the file exists in the MT5 terminal (it should be synced already)
    if (-not (Test-Path $dstFile)) {
        Write-Host "[COMPILE] SKIP $fileName (not found in MT5 terminal)" -ForegroundColor Yellow
        continue
    }

    $fileLog = Join-Path $ProjectRoot "compile_$($srcFile.BaseName).log"
    if (Test-Path $fileLog) {
        try { Remove-Item $fileLog -Force -ErrorAction Stop }
        catch { try { Clear-Content $fileLog -ErrorAction Stop } catch { } }
    }

    $compileArgs = @("/compile:$dstFile", "/log:$fileLog")
    Write-Host "[COMPILE] Compiling $fileName..." -ForegroundColor Gray

    # Clear any lingering headless MetaEditor worker from a previous file. MetaEditor
    # enforces a single instance, so a leftover worker swallows this build. Kill it
    # BEFORE launching the next compile (after the previous file's result is captured).
    Get-Process -Name "metaeditor64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    # Launch MetaEditor headless via the call operator. Start-Process crashes in this
    # environment with "Item has already been added. Key in dictionary: 'PATH'/'Path'"
    # (a duplicate environment-key bug), so invoke it directly instead.
    & $MetaEditor $compileArgs

    # MetaEditor spawns a worker that writes the .ex5 + log AFTER the GUI parent exits.
    # Poll for the log file to APPEAR, then for the "Result:" line (up to 180s), keeping
    # this script alive so the orphaned worker is not killed mid-write.
    $logReady = $false
    $deadline = (Get-Date).AddSeconds(180)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $fileLog) {
            $lc = Get-Content $fileLog -Raw -Encoding Unicode
            if ($lc -match 'Result:') { $logReady = $true; break }
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $logReady) {
        Write-Host "  [COMPILE] WARNING: log not finalized within 180s for $fileName" -ForegroundColor Yellow
    }

    $fileErrors = 0
    $fileWarnings = 0
    if (Test-Path $fileLog) {
        $logContent = Get-Content $fileLog -Raw
        
        # Parse "Result:" line for accurate error/warning counts
        $resultLine = ($logContent -split "`n" | Where-Object { $_ -match 'Result:' } | Select-Object -Last 1)
        if ($resultLine) {
            # Parse "Result: X errors, Y warnings" format
            if ($resultLine -match '(\d+)\s+errors?') { $fileErrors = [int]$Matches[1] }
            if ($resultLine -match '(\d+)\s+warnings?') { $fileWarnings = [int]$Matches[1] }
            Write-Host "  $($resultLine.Trim())" -ForegroundColor $(if ($fileErrors -gt 0) { "Red" } else { "Green" })
        } else {
            # Fallback: count error/warning lines with line number pattern
            $errorMatches = [regex]::Matches($logContent, '^\s*\d+:\s*error\s+\d+:', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $warningMatches = [regex]::Matches($logContent, '^\s*\d+:\s*warning\s+\d+:', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            $fileErrors = $errorMatches.Count
            $fileWarnings = $warningMatches.Count
            Write-Host "  File: $fileErrors errors, $fileWarnings warnings" -ForegroundColor $(if ($fileErrors -gt 0) { "Red" } else { "Green" })
        }

        # Print error lines with file:line details
        if ($fileErrors -gt 0) {
            $errorLines = $logContent -split "`n" | Where-Object { $_ -match 'error\s+\d+:' }
            foreach ($el in $errorLines) {
                Write-Host "  | $($el.Trim())" -ForegroundColor Red
            }
        }
        
        # Print warning lines if any
        if ($fileWarnings -gt 0) {
            $warningLines = $logContent -split "`n" | Where-Object { $_ -match 'warning\s+\d+:' }
            foreach ($wl in $warningLines) {
                Write-Host "  | $($wl.Trim())" -ForegroundColor Yellow
            }
        }

        # Clean up per-file log unless KeepLog (best-effort; SafeDelete hook may block)
        if (-not $KeepLog) {
            try { Remove-Item $fileLog -Force -ErrorAction Stop } catch { }
        }
    } else {
        Write-Host "  No log file generated for $fileName" -ForegroundColor Yellow
    }

    $totalErrors += $fileErrors
    $totalWarnings += $fileWarnings
    $results += [PSCustomObject]@{
        File     = $fileName
        Errors   = $fileErrors
        Warnings = $fileWarnings
    }
}

# --- Final summary ---
Write-Host ""
Write-Host "=== COMPILE SUMMARY ===" -ForegroundColor White
foreach ($r in $results) {
    $color = if ($r.Errors -gt 0) { "Red" } elseif ($r.Warnings -gt 0) { "Yellow" } else { "Green" }
    Write-Host ("  {0,-40} {1} errors, {2} warnings" -f $r.File, $r.Errors, $r.Warnings) -ForegroundColor $color
}
Write-Host ""
if ($totalErrors -gt 0) {
    Write-Host "[COMPILE] OVERALL FAILED — $totalErrors total errors, $totalWarnings total warnings" -ForegroundColor Red
} else {
    Write-Host "[COMPILE] OVERALL SUCCESS — 0 errors, $totalWarnings total warnings" -ForegroundColor Green
}
