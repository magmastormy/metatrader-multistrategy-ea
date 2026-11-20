<#+
.SYNOPSIS
    Run one headless Strategy Tester window and report what the run actually did.

.DESCRIPTION
    The tester appends to per-day logs, and simulation timestamps restart at the window's start. This
    script refuses overlapping terminal runs, waits for a fresh "successfully finished" terminal-log
    entry and clean process exit, then validates every expected minute before reporting equity
    first/last/min/max from the per-minute
    [COMPOUNDING-TIER-HEARTBEAT], fill count, consensus decisions/rejects, and the loudest tags.
    Serves a single purpose: turn a backtest into numbers instead of an impression.

.PARAMETER IniPath
    Tester .ini to hand to terminal64.exe /config:

.PARAMETER TimeoutSec
    Wall clock limit. The default is generous: a full 24 h M15 window currently finishes in ~3 minutes.

.EXAMPLE
    .\Tools\run_window.ps1 -IniPath .\Tools\backtest.ini -Cold
#>
param(
    [Parameter(Mandatory=$true)][string]$IniPath,
    [ValidateRange(30, 86400)][int]$TimeoutSec = 1800,
    # Cold start: archive and remove every file the EA reloads at init. Two runs of the SAME build on the
    # SAME window measured +2.89% and -4.34% because the compounding tier state carried over between
    # them, so a P&L number is only comparable to another number taken from the same starting state.
    [switch]$Cold
)

$ErrorActionPreference = 'Stop'

$terminal   = 'C:\Program Files\MetaTrader 5 Terminal\terminal64.exe'
$termLogDir = Join-Path $env:APPDATA 'MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\logs'
$testerLogDir = Join-Path $env:APPDATA 'MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\Tester\logs'

# Both logs are named after the WALL-CLOCK day (yyyyMMdd.log), so a run that crosses midnight writes into a new
# file. Hard-coding the date (the previous shape) made the summary read yesterday's log and print "no EA output
# appended" while the tester was 63% through the window. Resolve the newest file by name on every use.
function Newest-Log([string]$dir) {
    Get-ChildItem -LiteralPath $dir -Filter '*.log' |
        Where-Object { $_.Name -match '^\d{8}\.log$' } |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
$testerLog  = Newest-Log $testerLogDir
$termLog    = Newest-Log $termLogDir

function Read-Shared([string]$path, [int64]$from, [int64]$to) {
    $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($to -gt $fs.Length) { $to = $fs.Length }
        if ($from -ge $to) { return '' }
        $fs.Position = $from
        $buf = New-Object byte[] ($to - $from)
        $fs.Read($buf, 0, $buf.Length) | Out-Null
    } finally { $fs.Close() }
    return [Text.Encoding]::Unicode.GetString($buf)
}

if (-not (Test-Path -LiteralPath $IniPath -PathType Leaf)) { throw "no such ini: $IniPath" }
$IniPath = (Resolve-Path -LiteralPath $IniPath).Path
if (-not $testerLog -or -not $termLog) { throw 'MetaTrader tester and terminal log files must exist before launch' }
$existingProcesses = @(Get-Process -Name terminal64, metatester64 -ErrorAction SilentlyContinue)
if ($existingProcesses.Count -gt 0) {
    $ids = ($existingProcesses | ForEach-Object { $_.Id }) -join ', '
    throw "MetaTrader is already running (PID $ids); refusing a possibly swallowed or overlapping /config launch"
}

$ini = Get-Content -LiteralPath $IniPath -Raw
$fromDate = ([regex]'FromDate=(\S+)').Match($ini).Groups[1].Value
$toDate   = ([regex]'ToDate=(\S+)').Match($ini).Groups[1].Value
$report   = ([regex]'Report=(\S+)').Match($ini).Groups[1].Value
if (-not $fromDate -or -not $toDate) { throw 'INI must contain explicit FromDate and ToDate values' }
try {
    $windowStart = [datetime]::ParseExact($fromDate, 'yyyy.MM.dd', [Globalization.CultureInfo]::InvariantCulture)
    $windowEnd = [datetime]::ParseExact($toDate, 'yyyy.MM.dd', [Globalization.CultureInfo]::InvariantCulture)
} catch {
    throw "INI dates must use yyyy.MM.dd: FromDate='$fromDate', ToDate='$toDate'"
}
$windowMinutes = ($windowEnd - $windowStart).TotalMinutes
$expectedSamples = [int]$windowMinutes
if ($expectedSamples -le 0 -or $windowMinutes -ne $expectedSamples) {
    throw "INI window must have a positive whole-minute duration: $fromDate .. $toDate"
}

$offset = (Get-Item $testerLog).Length
$termOffset = (Get-Item $termLog).Length
$initialTesterLog = $testerLog
$activeTermLog = $termLog

# Carry-over state is a confounding variable: strategy_scoreboard.csv holds per-strategy history and is
# loaded at init, so a run that inherits it is not comparable to a run from a wiped file. Archive it
# beside the agent files and report which state this run started from.
$scoreboard = Join-Path $env:APPDATA ('MetaQuotes\Tester\FB9A56D617EDDDFE29EE54EBEFFE96C1\Agent-127.0.0.1-3000\MQL5\Files\strategy_scoreboard.csv')
$stampAll = Get-Date -Format 'HHmmss'
$state = 'cold'
# The tester agent wipes its own MQL5\Files between runs, so an archive written beside the agent file dies
# with the next window. Keep a copy inside the repository, named by the window it describes, so per-strategy
# attribution survives the sweep.
$archDir = Join-Path $PSScriptRoot 'artifacts\scoreboards'
if (Test-Path -LiteralPath $scoreboard) { $state = 'warm' }
if ($Cold) {
    # Everything the EA loads at init and writes back at teardown. Left in place, the tier ladder and
    # per-strategy history turn a rerun into a different experiment.
    $resetFiles = @('strategy_scoreboard.csv', 'compounding_tier_state.csv', 'CrashRecoveryState.json', 'AI_Health_Dashboard.csv')
    $resetDir = Join-Path (Split-Path $scoreboard) ''
    foreach ($f in $resetFiles) {
        $fp = Join-Path $resetDir $f
        if (Test-Path -LiteralPath $fp) {
            Copy-Item -LiteralPath $fp -Destination ("$fp.$stampAll.bak") -Force
            Remove-Item -LiteralPath $fp -Force
        }
    }
    $state = 'cold-reset'
}
"window $fromDate .. $toDate | log offset $offset | state=$state (scoreboard $(if($state -like 'warm*'){'run inherits saved per-strategy history'}else{'absent, strategies start from code defaults'}))"

$sw = [Diagnostics.Stopwatch]::StartNew()
$startedProcess = Start-Process -FilePath $terminal -ArgumentList ('/config:"{0}"' -f $IniPath) -WindowStyle Hidden -PassThru

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$completionSeen = $false
$completed = $false
$completionLine = ''
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $newestTermLog = Newest-Log $termLogDir
    if ($newestTermLog -and $newestTermLog -ne $activeTermLog) {
        $activeTermLog = $newestTermLog
        $termOffset = [int64]0
    }
    if (-not $activeTermLog -or -not (Test-Path -LiteralPath $activeTermLog)) { continue }
    $activeTermLength = (Get-Item -LiteralPath $activeTermLog).Length
    if ($activeTermLength -lt $termOffset) { $termOffset = [int64]0 }
    $tail = Read-Shared $activeTermLog $termOffset $activeTermLength
    $termOffset = $activeTermLength
    if ($tail -match '(?i)successfully finished') {
        $completionSeen = $true
        $completionLine = ($tail -split "`r?`n" | Where-Object { $_ -match '(?i)successfully finished' } | Select-Object -Last 1).Trim()
    }
    $runningProcesses = @(Get-Process -Name terminal64, metatester64 -ErrorAction SilentlyContinue)
    $startedProcess.Refresh()
    $startedProcessRunning = -not $startedProcess.HasExited
    if ($completionSeen -and -not $startedProcessRunning -and $runningProcesses.Count -eq 0) {
        $completed = $true
        break
    }
    if ($startedProcess.HasExited -and $runningProcesses.Count -eq 0 -and
        -not $completionSeen -and $sw.Elapsed.TotalSeconds -ge 30) {
        throw 'Terminal exited without a fresh successfully-finished record'
    }
}
if (-not $completed) {
    if ((Get-Date) -ge $deadline) { throw "TIMEOUT after $TimeoutSec s; no valid completed run was recorded" }
    throw 'Run did not produce a fresh successfully-finished record and clean terminal exit'
}
"result: successfully finished | wall $([math]::Round($sw.Elapsed.TotalSeconds,1)) s | $completionLine"

# Include every wall-clock-dated tester log touched by this run, retaining the captured offset only for
# the file active before launch. This preserves pre-midnight samples if the run crosses midnight.
$newestTesterLog = Newest-Log $testerLogDir
if (-not $newestTesterLog) { throw 'Tester journal disappeared before summary could be validated' }
$initialLogName = [IO.Path]::GetFileName($initialTesterLog)
$finalLogName = [IO.Path]::GetFileName($newestTesterLog)
$runLogs = @(Get-ChildItem -LiteralPath $testerLogDir -Filter '*.log' |
    Where-Object { $_.Name -match '^\d{8}\.log$' -and $_.Name -ge $initialLogName -and $_.Name -le $finalLogName } |
    Sort-Object Name)
$segments = foreach ($log in $runLogs) {
    $startAt = if ($log.FullName -eq $initialTesterLog) { $offset } else { [int64]0 }
    if ($log.Length -lt $startAt) { $startAt = [int64]0 }
    Read-Shared $log.FullName $startAt ([int64]::MaxValue)
}
$seg = $segments -join ''
if (-not $seg) { throw 'No tester journal bytes appended; refusing to report a result' }

# The scoreboard present now is the one THIS run produced, so it is archived after the run and named after
# the arm and window that produced it. Archiving at start (the previous shape) labelled the previous run's
# data with the current arm's name, which is exactly the kind of silent mislabel this file exists to avoid.
if (Test-Path -LiteralPath $scoreboard) {
    if (-not (Test-Path -LiteralPath $archDir)) { New-Item -ItemType Directory -Path $archDir -Force | Out-Null }
    $archName = 'scoreboard_{0}_{1}-{2}.csv' -f ([IO.Path]::GetFileNameWithoutExtension($IniPath)), ($fromDate -replace '\.', ''), ($toDate -replace '\.', '')
    Copy-Item -LiteralPath $scoreboard -Destination (Join-Path $archDir $archName) -Force
    "scoreboard archived: $archName"
}

$lines = $seg -split "`r?`n"

$samples = New-Object 'System.Collections.Generic.List[object]'
foreach ($ln in $lines) {
    $fields = $ln -split "`t"
    if ($fields.Count -lt 4) { continue }
    $msg = $fields[$fields.Count - 1]
    if ($msg -match '^\s*(20\d\d\.\d\d\.\d\d \d\d:\d\d:\d\d).*\[COMPOUNDING-TIER-HEARTBEAT\].*balance=(-?\d+(?:\.\d+)?)') {
        $simTime = [datetime]::ParseExact($matches[1], 'yyyy.MM.dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        $balance = [double]::Parse($matches[2], [Globalization.CultureInfo]::InvariantCulture)
        $samples.Add([pscustomobject]@{ time=$simTime; balance=$balance })
    }
}
$expectedStart = $windowStart
if ($samples.Count -ne $expectedSamples -or $samples[0].time -ne $expectedStart) {
    $actualStart = if ($samples.Count -gt 0) { $samples[0].time.ToString('yyyy.MM.dd HH:mm:ss') } else { 'none' }
    throw "Invalid measurement window: expected $expectedSamples heartbeat samples from $($expectedStart.ToString('yyyy.MM.dd HH:mm:ss')); found $($samples.Count) starting $actualStart"
}
for ($i = 1; $i -lt $samples.Count; $i++) {
    if ($samples[$i].time -ne $samples[$i - 1].time.AddMinutes(1)) {
        throw "Invalid measurement window: heartbeat gap or duplicate at $($samples[$i].time.ToString('yyyy.MM.dd HH:mm:ss'))"
    }
}
$bal = @($samples | ForEach-Object { $_.balance })
if ($bal.Count -gt 0) {
    $d = [math]::Round($bal[-1] - $bal[0], 2)
    $pct = [math]::Round(100.0 * $d / $bal[0], 3)
    $minBalance = ($bal | Measure-Object -Minimum).Minimum
    $maxBalance = ($bal | Measure-Object -Maximum).Maximum
    [string]::Format([Globalization.CultureInfo]::InvariantCulture,
        'equity: samples={0} first={1:F2} last={2:F2} min={3:F2} max={4:F2} delta={5:F2} ({6:F3}%)',
        $bal.Count, $bal[0], $bal[-1], $minBalance, $maxBalance, $d, $pct)
}
"fills: " + ([regex]::Matches($seg, 'EXECUTION-RECEIPT')).Count
"decisions: " + ([regex]::Matches($seg, 'CONSENSUS-DECISION')).Count
"rejects: " + ([regex]::Matches($seg, 'CONSENSUS-REJECT')).Count
"advisory: " + ([regex]::Matches($seg, 'CONSENSUS-ADVISORY')).Count
"blocked: " + ([regex]::Matches($seg, 'EXECUTION-BLOCKED')).Count
"dashErr: " + ([regex]::Matches($seg, 'DASHBOARD-BRIDGE-ERROR')).Count
"infoMirror: " + ([regex]::Matches($seg, '\[INFO\]')).Count
"logMB: " + [math]::Round($seg.Length / 1MB, 2)

$tags = @{}
foreach ($m in ([regex]'\[[A-Za-z0-9\-]{3,30}\]').Matches($seg)) {
    $k = $m.Value
    $tags[$k] = 1 + $(if ($tags.ContainsKey($k)) { $tags[$k] } else { 0 })
}
"--- loudest tags ---"
$tags.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 |
    ForEach-Object { "  $($_.Value)`t$($_.Name)" }

"--- fills by symbol ---"
$lines | Where-Object { $_.Contains('EXECUTION-RECEIPT') } |
    ForEach-Object { if ($_ -match 'RECEIPT\] ([^|]+)\|') { $matches[1].Trim() } } |
    Group-Object | Sort-Object Count -Descending |
    ForEach-Object { "  $($_.Count)`t$($_.Name)" }

"--- reject reasons ---"
# `-split '|'` is a regex alternation and matches everything, so the old version always printed an
# empty bucket. Classify by the line's own wording instead.
$lines | Where-Object { $_.Contains('CONSENSUS-REJECT') } |
    ForEach-Object {
        if     ($_ -match 'single voter confidence')   { 'single_voter_floor' }
        elseif ($_ -match 'Winning votes')             { 'min_voters' }
        elseif ($_ -match 'Support ratio')             { 'support_floor' }
        elseif ($_ -match 'Quorum ratio')             { 'quorum_ratio' }
        else                                           { 'other' }
    } | Group-Object | Sort-Object Count -Descending |
    ForEach-Object { "  $($_.Count)`t$($_.Name)" }

"--- strategy scoreboard ---"
if (Test-Path -LiteralPath $scoreboard) {
    $sbRows = [IO.File]::ReadAllLines($scoreboard) | Select-Object -Skip 1 | ForEach-Object {
        $q = $_ -split ';'
        if ($q.Count -ge 10) { [pscustomobject]@{ sym=$q[0]; name=$q[1]; trades=[int]$q[2]; wins=[int]$q[5]; health=[double]$q[9] } }
    }
    "  rows $($sbRows.Count) | with trades $(($sbRows | Where-Object { $_.trades -gt 0 }).Count)"
    $sbRows | Where-Object { $_.trades -gt 0 } | Group-Object name | ForEach-Object {
        [pscustomobject]@{ s=$_.Name; t=($_.Group | Measure-Object trades -Sum).Sum; w=($_.Group | Measure-Object wins -Sum).Sum }
    } | Sort-Object t -Descending | Select-Object -First 6 |
        ForEach-Object { "  $($_.t)`ttrades`t$($_.w)`twins`t$($_.s)" }
}

"report file: " + $(if ($report) { $report } else { '(none requested)' })
$found = Get-ChildItem -LiteralPath 'C:\Program Files\MetaTrader 5 Terminal' -Filter 'backtest_report*' -ErrorAction SilentlyContinue
"report present in terminal dir: " + $found.Count
