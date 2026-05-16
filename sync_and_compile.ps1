param(
[string]$MetaTraderRoot = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\CF89AB30ACB6DA0DBA14DA647C3517F8",
[string]$Destination,
[string]$ProjectRoot,
[switch]$SkipSync,
[switch]$MirrorSync,
[switch]$SeedTerminalIncludes,
[switch]$KeepCompileArtifacts
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

function Resolve-TerminalIncludePath {
param(
    [string]$AppDataRoot,
    [string[]]$AdditionalCandidates
)

if (-not (Test-Path -LiteralPath $AppDataRoot)) {
    # continue and check explicit candidates below
}
else {
    $terminalRoots = Get-ChildItem -Path $AppDataRoot -Directory -ErrorAction SilentlyContinue
    foreach ($terminal in $terminalRoots) {
        $candidate = Join-Path $terminal.FullName "MQL5\Include\Object.mqh"
        if (Test-Path -LiteralPath $candidate) {
            return (Split-Path -Parent $candidate)
        }
    }
}

foreach ($candidateDir in $AdditionalCandidates) {
    if ([string]::IsNullOrWhiteSpace($candidateDir)) {
        continue
    }
    $candidate = Join-Path $candidateDir "Object.mqh"
    if (Test-Path -LiteralPath $candidate) {
        return (Split-Path -Parent $candidate)
    }
}

return $null
}

function Ensure-TerminalDataIncludes {
param(
    [string]$AppDataRoot,
    [string]$SourceIncludeRoot
)

if ([string]::IsNullOrWhiteSpace($SourceIncludeRoot) -or -not (Test-Path -LiteralPath (Join-Path $SourceIncludeRoot "Object.mqh"))) {
    return
}

if (-not (Test-Path -LiteralPath $AppDataRoot)) {
    return
}

$terminalDirs = Get-ChildItem -Path $AppDataRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^[A-F0-9]{32}$' }

foreach ($terminalDir in $terminalDirs) {
    $targetIncludeRoot = Join-Path $terminalDir.FullName "MQL5\Include"
    $targetObject = Join-Path $targetIncludeRoot "Object.mqh"
    if (Test-Path -LiteralPath $targetObject) {
        continue
    }

    try {
        New-Item -ItemType Directory -Path $targetIncludeRoot -Force -ErrorAction Stop | Out-Null
        Write-Host "Seeding terminal include library: $targetIncludeRoot" -ForegroundColor Yellow
        $null = & robocopy $SourceIncludeRoot $targetIncludeRoot "/E" "/R:2" "/W:1" "/NFL" "/NDL" "/NP"
        $copyExitCode = $LASTEXITCODE
        if ($copyExitCode -ge 8) {
            Write-Host "Warning: include seeding failed for $targetIncludeRoot (robocopy exit code $copyExitCode)." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Warning: include seeding skipped for $targetIncludeRoot ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}
}

function Sync-Project {
param(
[string]$Source,
[string]$Destination,
[switch]$MirrorMode
)

Write-Host "`n====================================================="
Write-Host "   SYNCHRONIZING PROJECT TO METATRADER 5" -ForegroundColor Cyan
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

$resolvedSource = (Resolve-Path -LiteralPath $Source).ProviderPath
$resolvedDestination = [System.IO.Path]::GetFullPath($Destination)
if ($resolvedSource -eq $resolvedDestination) {
    throw "Sync source and destination resolve to the same path: $resolvedSource"
}
if ($resolvedDestination -notmatch [regex]::Escape("\MQL5\Experts\")) {
    throw "Refusing to sync outside MT5 Experts scope: $resolvedDestination"
}

$excludeDirs = @(".git", ".vs", "x64", "Debug", "Release", ".windsurf", "__pycache__", ".agent", ".gemini")
$excludeFiles = @("*.exe", "*.pdb", "*.obj", "*.log")

if ($MirrorMode) {
    Write-Host "Sync mode: MIRROR (deletes target files not present in source)" -ForegroundColor Yellow
    $robocopyArgs = @($Source, $Destination, "/MIR", "/R:3", "/W:1", "/NFL", "/NDL", "/NP")
}
else {
    Write-Host "Sync mode: SAFE COPY (no target deletions)" -ForegroundColor Green
    $robocopyArgs = @($Source, $Destination, "/E", "/R:3", "/W:1", "/NFL", "/NDL", "/NP")
}

foreach ($dir in $excludeDirs) { $robocopyArgs += "/XD"; $robocopyArgs += $dir }
foreach ($file in $excludeFiles) { $robocopyArgs += "/XF"; $robocopyArgs += $file }

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

Write-Host "`n[$Title]" -ForegroundColor Cyan

if (Test-Path -LiteralPath $Path) {
    Get-Content -Path $Path | Write-Host
}
else {
    Write-Host "Log file not found: $Path" -ForegroundColor Yellow
}


}

function Cleanup-CompileArtifacts {
param(
    [string]$RootPath,
    [string[]]$GeneratedArtifacts,
    [switch]$KeepArtifacts
)

if ($KeepArtifacts) {
    Write-Host "Compile artifacts retained (-KeepCompileArtifacts enabled)." -ForegroundColor Yellow
    return
}

$targets = @()
if ($GeneratedArtifacts) {
    $targets += $GeneratedArtifacts
}

$patternTargets = @()
$patternTargets += Get-ChildItem -Path $RootPath -File -Filter "compile_*.log" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
$patternTargets += Get-ChildItem -Path $RootPath -File -Filter "compile_*.txt" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
$patternTargets += Join-Path $RootPath "compile_logs.log"

$targets += $patternTargets
$targets = $targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

$removed = 0
foreach ($target in $targets) {
    if (Test-Path -LiteralPath $target) {
        try {
            Remove-Item -LiteralPath $target -Force -ErrorAction Stop
            $removed++
        }
        catch {
            Write-Host "Warning: failed to remove artifact $target ($($_.Exception.Message))" -ForegroundColor Yellow
        }
    }
}

Write-Host "Compile artifact cleanup complete. Removed $removed file(s)." -ForegroundColor Gray
}

function Get-CompileErrors {
param([string]$LogPath)

if (-not (Test-Path -LiteralPath $LogPath)) {
    return 0
}

# MetaEditor log format is typically: "Result: X errors, Y warnings"
# We use a more flexible regex to catch both "error(s)" and "X errors"
$content = Get-Content -Path $LogPath
foreach ($line in $content) {
    # Matches "Result: 106 errors" or "0 error(s)"
    if ($line -match 'Result:\s+([0-9]+)\s+error') {
        return [int]$Matches[1]
    }
    if ($line -match '([0-9]+)\s+error\(s\)') {
        return [int]$Matches[1]
    }
}

return 0


}

$metaEditorCandidates = @(
Join-Path -Path $MetaTraderRoot -ChildPath "MetaEditor64.exe"
"C:\Program Files\MT5 Weltrade\MetaEditor64.exe",
"C:\Program Files\MetaTrader 5\MetaEditor64.exe",
"C:\Program Files (x86)\MetaTrader 5\MetaEditor.exe",
"C:\Program Files\MetaTrader 5\MetaEditor.exe"
)

$metaEditor = Resolve-MetaEditor -Candidates $metaEditorCandidates

if (-not $metaEditor) {
throw "MetaEditor executable not found. Checked: $([string]::Join(', ', $metaEditorCandidates))"
}

$terminalIncludePath = Resolve-TerminalIncludePath `
    -AppDataRoot (Join-Path $env:APPDATA "MetaQuotes\Terminal") `
    -AdditionalCandidates @(
        (Join-Path $MetaTraderRoot "MQL5\Include"),
        "C:\Program Files\MT5 Weltrade\MQL5\Include",
        "C:\Program Files\MetaTrader 5\MQL5\Include",
        "C:\Program Files (x86)\MetaTrader 5\MQL5\Include"
    )
if (-not $terminalIncludePath) {
Write-Host "Warning: MT5 standard include library was not discovered in known locations. Compilation will continue and MetaEditor will report include errors if unresolved." -ForegroundColor Yellow
}
else {
Write-Host "Detected MT5 include path: $terminalIncludePath" -ForegroundColor Gray
}

if ($SeedTerminalIncludes) {
    $primaryIncludeCandidate = Join-Path $MetaTraderRoot "MQL5\Include"
    $includeSeedSource = $null
    if (Test-Path -LiteralPath (Join-Path $primaryIncludeCandidate "Object.mqh")) {
        $includeSeedSource = $primaryIncludeCandidate
    }
    elseif ($terminalIncludePath) {
        $includeSeedSource = $terminalIncludePath
    }
    Ensure-TerminalDataIncludes -AppDataRoot (Join-Path $env:APPDATA "MetaQuotes\Terminal") -SourceIncludeRoot $includeSeedSource
}
else {
    Write-Host "Terminal include seeding skipped (use -SeedTerminalIncludes to enable)." -ForegroundColor Gray
}

$targetDir = if ([string]::IsNullOrWhiteSpace($Destination)) {
    Join-Path $MetaTraderRoot "MQL5\Experts\metatrader-multistrategy-ea"
} else {
    $Destination
}

if ($Destination -and -not $Destination.Contains("metatrader-multistrategy-ea")) {
    $targetDir = Join-Path $Destination "metatrader-multistrategy-ea"
}

$compileDir = $ProjectRoot

if (-not $SkipSync) {
Sync-Project -Source $ProjectRoot -Destination $targetDir -MirrorMode:$MirrorSync
}

if (-not (Test-Path -LiteralPath $compileDir)) {
    throw "Compile source directory not found: $compileDir"
}

Write-Host "Compilation source: $compileDir" -ForegroundColor Gray
if ($compileDir -ne $targetDir) {
    Write-Host "Deployment target remains: $targetDir" -ForegroundColor Gray
}

Write-Host "`n====================================================="
Write-Host "   COMPILATION STARTED" -ForegroundColor Cyan
Write-Host "====================================================="

$mq5Files = Get-ChildItem -Path $compileDir -Filter "*.mq5" -Recurse

$excludedRelativePaths = @("TestSocket.mq5", "NextGenBrainTrainer.mq5")

$mq5Files = $mq5Files | Where-Object {
$fullName = $_.FullName
$shouldExclude = $false
foreach ($excluded in $excludedRelativePaths) {
if ($fullName -like "*$excluded") {
$shouldExclude = $true
Write-Host "Excluding: $excluded" -ForegroundColor Yellow
break
}
}
-not $shouldExclude
}

if ($mq5Files.Count -eq 0) {
Write-Host "No .mq5 files found in target directory!" -ForegroundColor Red
exit 1
}

$totalErrors = 0
$compilationResults = @()
$unifiedLogPath = Join-Path $ProjectRoot "compile_logs.log"
$generatedCompileArtifacts = @()
$generatedCompileArtifacts += $unifiedLogPath

"Compilation started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $unifiedLogPath -Encoding UTF8

foreach ($file in $mq5Files) {
Write-Host "Compiling $($file.Name)..." -ForegroundColor White

$logName = "compile_" + $file.BaseName + ".log"
$logPath = Join-Path $ProjectRoot $logName
$generatedCompileArtifacts += $logPath

    # MetaEditor compilation
    # Use /portable to resolve standard includes from install-local MQL5\Include when AppData terminal data is unavailable.
    $process = Start-Process -FilePath $metaEditor -ArgumentList "/compile:`"$($file.FullName)`"", "/log:`"$logPath`"", "/portable" -Wait -PassThru
$exitCode = $process.ExitCode

Show-Log -Title $logName -Path $logPath

# Error parsing
$errors = Get-CompileErrors -LogPath $logPath
$totalErrors += $errors

# Logging to unified file
"-------------------------------------------------------------" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
"File: $($file.FullName)`nExit Code: $exitCode`nErrors: $errors" | Out-File -FilePath $unifiedLogPath -Encoding UTF8 -Append
if (Test-Path $logPath) { Get-Content $logPath | Out-File $unifiedLogPath -Encoding UTF8 -Append }

$compilationResults += [PSCustomObject]@{
    File = $file.Name
    ExitCode = $exitCode
    Errors = $errors
}


}

Write-Host "`n====================================================="
Write-Host "   COMPILATION SUMMARY" -ForegroundColor Cyan
Write-Host "====================================================="

foreach ($result in $compilationResults) {
$color = if ($result.Errors -eq 0) { "Green" } else { "Red" }
Write-Host "$($result.File): Errors: $($result.Errors)" -ForegroundColor $color
}

$color = if ($totalErrors -eq 0) { "Green" } else { "Red" }
Write-Host "Total Errors: $totalErrors" -ForegroundColor $color

if ($totalErrors -eq 0) {
Write-Host "✅ SUCCESS: All files compiled with 0 errors!" -ForegroundColor Green
} else {
Write-Host "❌ FAILED: $totalErrors errors found." -ForegroundColor Red
}

Cleanup-CompileArtifacts -RootPath $ProjectRoot -GeneratedArtifacts $generatedCompileArtifacts -KeepArtifacts:$KeepCompileArtifacts

exit $totalErrors
