# sync_and_compile.ps1 — Sync project files to Deriv MT5 terminal and compile
# Usage: .\sync_and_compile.ps1 [-SkipCompile] [-KeepLog]

param(
    [switch]$SkipCompile = $false,
    [switch]$KeepLog = $false
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

# --- Sync MQHModelTrainer/ ---
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

# --- Compile ---
Write-Host ""
Write-Host "[COMPILE] Starting MetaEditor compilation..." -ForegroundColor Cyan

$eaPath = Join-Path $EADst $MainEA
if (-not (Test-Path $eaPath)) {
    throw "EA file not found at: $eaPath"
}

$logFile = Join-Path $ProjectRoot "compile_result.log"
if (Test-Path $logFile) { Remove-Item $logFile -Force }

$compileArgs = "/compile:`"$eaPath`" /log:`"$logFile`""
Write-Host "[COMPILE] $MetaEditor $compileArgs" -ForegroundColor Gray

$proc = Start-Process -FilePath $MetaEditor -ArgumentList $compileArgs -NoNewWindow -Wait -PassThru

# --- Parse results ---
Start-Sleep -Milliseconds 500

if (Test-Path $logFile) {
    $logContent = Get-Content $logFile -Raw
    Write-Host ""
    Write-Host "=== COMPILE LOG ===" -ForegroundColor White
    Write-Host $logContent

    # Check for errors
    $errorCount = ([regex]::Matches($logContent, '\berror\b')).Count
    $warnCount = ([regex]::Matches($logContent, '\bwarning\b')).Count

    Write-Host ""
    if ($errorCount -gt 0) {
        Write-Host "[COMPILE] FAILED — $errorCount errors, $warnCount warnings" -ForegroundColor Red
    } else {
        Write-Host "[COMPILE] SUCCESS — 0 errors, $warnCount warnings" -ForegroundColor Green
    }

    if (-not $KeepLog -and $errorCount -eq 0) {
        Remove-Item $logFile -Force
        Write-Host "[COMPILE] Log file removed (use -KeepLog to preserve)" -ForegroundColor Gray
    }
} else {
    Write-Host "[COMPILE] No log file generated. Exit code: $($proc.ExitCode)" -ForegroundColor Yellow
}



# --- Final summary ---
Write-Host ""
Write-Host "=== COMPILE SUMMARY ===" -ForegroundColor White
if ($totalErrors -gt 0) {
    Write-Host "[COMPILE] OVERALL FAILED — $totalErrors total errors, $totalWarnings total warnings" -ForegroundColor Red
} else {
    Write-Host "[COMPILE] OVERALL SUCCESS — 0 errors, $totalWarnings total warnings" -ForegroundColor Green
}
