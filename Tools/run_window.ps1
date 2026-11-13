<#+
.SYNOPSIS
    Run one headless Strategy Tester window and report what the run actually did.

.DESCRIPTION
    The tester appends to the same per-day log file for every run, and timestamps restart at the
    window's own start, so a run cannot be identified by its timestamps. This script records the log
    length before launching, waits for "last test passed" in the terminal log, then reads only the
    appended bytes and reports: wall clock, equity first/last/min/max from the per-minute
    [COMPOUNDING-TIER-HEARTBEAT], fill count, consensus decisions/rejects, and the loudest tags.
    Serves a single purpose: turn a backtest into numbers instead of an impression.

.PARAMETER IniPath
    Tester .ini to hand to terminal64.exe /config:

.PARAMETER TimeoutSec
    Wall clock limit. The default is generous: a full 24 h M15 window currently finishes in ~3 minutes.

.EXAMPLE
    .\Tools\run_window.ps1
#>
param(
    [string]$IniPath = 'D:\TraeProjects\metatrader-multistrategy-ea\Tools\backtest.ini',
    [int]$TimeoutSec = 1800,
    # Cold start: archive and remove every file the EA reloads at init. Two runs of the SAME build on the
    # SAME window measured +2.89% and -4.34% because the compounding tier state carried over between
    # them, so a P&L number is only comparable to another number taken from the same starting state.
    [switch]$Cold
)

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

if (-not (Test-Path -LiteralPath $IniPath)) { throw "no such ini: $IniPath" }
$ini = Get-Content -LiteralPath $IniPath -Raw
$fromDate = ([regex]'FromDate=(\S+)').Match($ini).Groups[1].Value
$toDate   = ([regex]'ToDate=(\S+)').Match($ini).Groups[1].Value
$report   = ([regex]'Report=(\S+)').Match($ini).Groups[1].Value

$offset = (Get-Item $testerLog).Length
$termOffset = (Get-Item $termLog).Length

# Carry-over state is a confounding variable: strategy_scoreboard.csv holds per-strategy history and
# parked rows and is loaded at init, so a run that inherits it is not comparable to a run from a wiped
# file. Archive it beside the agent files and report which state this run started from.
$scoreboard = Join-Path $env:APPDATA ('MetaQuotes\Tester\FB9A56D617EDDDFE29EE54EBEFFE96C1\Agent-127.0.0.1-3000\MQL5\Files\strategy_scoreboard.csv')
$stampAll = Get-Date -Format 'HHmmss'
$state = 'cold'
# The tester agent wipes its own MQL5\Files between runs, so an archive written beside the agent file dies
# with the next window. Keep a copy inside the repository, named by the window it describes, so per-strategy
# attribution survives the sweep.
$archDir = Join-Path $PSScriptRoot 'artifacts\scoreboards'
if (Test-Path -LiteralPath $scoreboard) { $state = 'warm' }
if ($Cold) {
    # Everything the EA loads at init and writes back at teardown. Left in place, the tier ladder, the
    # per-strategy history and the parked rows turn a rerun into a different experiment.
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
"window $fromDate .. $toDate | log offset $offset | state=$state (scoreboard $(if($state -like 'warm*'){'archived, run inherits parked rows and per-strategy history'}else{'absent, every row starts at the 0.55 prior'}))"

$sw = [Diagnostics.Stopwatch]::StartNew()
Start-Process -FilePath $terminal -ArgumentList "/config:$IniPath" -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $tail = Read-Shared $termLog $termOffset ([int64]::MaxValue)
    if ($tail -match 'last test passed with result "([^"]*)" in ([\d:\.]+)') {
        "result: $($matches[1]) after $($matches[2]) (wall $([math]::Round($sw.Elapsed.TotalSeconds,1)) s)"
        break
    }
}
if ((Get-Date) -ge $deadline) { "TIMEOUT after $TimeoutSec s - run may still be going" }

# Re-resolve after the wait: if the wall clock rolled to a new day mid-run, this run's output is in the NEW file
# and its start offset is 0 rather than the old file's length.
$newTesterLog = Newest-Log $testerLogDir
if ($newTesterLog -and $newTesterLog -ne $testerLog) { $testerLog = $newTesterLog; $offset = [int64]0 }
$seg = Read-Shared $testerLog $offset ([int64]::MaxValue)
if (-not $seg) { "no EA output appended"; return }

# The scoreboard present now is the one THIS run produced, so it is archived after the run and named after
# the arm and window that produced it. Archiving at start (the previous shape) labelled the previous run's
# data with the current arm's name, which is exactly the kind of silent mislabel this file exists to avoid.
if (Test-Path -LiteralPath $scoreboard) {
    if (-not (Test-Path -LiteralPath $archDir)) { New-Item -ItemType Directory -Path $archDir -Force | Out-Null }
    $archName = 'scoreboard_{0}_{1}-{2}.csv' -f ([IO.Path]::GetFileNameWithoutExtension($IniPath)), ($fromDate -replace '\.', ''), ($toDate -replace '\.', '')
    Copy-Item -LiteralPath $scoreboard -Destination (Join-Path $archDir $archName) -Force
    "scoreboard archived: $archName"
}

$lines = $seg -split "`r`n"

$bal = @()
foreach ($ln in $lines) {
    if ($ln.Contains('COMPOUNDING-TIER-HEARTBEAT') -and $ln -match 'balance=([\d\.]+)') { $bal += [double]$matches[1] }
}
if ($bal.Count -gt 0) {
    $d = [math]::Round($bal[-1] - $bal[0], 2)
    $pct = [math]::Round(100.0 * $d / $bal[0], 3)
    "equity: samples=$($bal.Count) first=$($bal[0]) last=$($bal[-1]) min=$((($bal | Measure-Object -Minimum).Minimum)) max=$((($bal | Measure-Object -Maximum).Maximum)) delta=$d ($pct%)"
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
        if ($q.Count -ge 11) { [pscustomobject]@{ sym=$q[0]; name=$q[1]; trades=[int]$q[2]; wins=[int]$q[5]; health=[double]$q[9]; parked=($q[10].Trim() -notin @('0','')) } }
    }
    "  rows $($sbRows.Count) | with trades $(($sbRows | Where-Object { $_.trades -gt 0 }).Count) | parked $(($sbRows | Where-Object { $_.parked }).Count)"
    $sbRows | Where-Object { $_.trades -gt 0 } | Group-Object name | ForEach-Object {
        [pscustomobject]@{ s=$_.Name; t=($_.Group | Measure-Object trades -Sum).Sum; w=($_.Group | Measure-Object wins -Sum).Sum }
    } | Sort-Object t -Descending | Select-Object -First 6 |
        ForEach-Object { "  $($_.t)`ttrades`t$($_.w)`twins`t$($_.s)" }
}

"report file: " + $(if ($report) { $report } else { '(none requested)' })
$found = Get-ChildItem -LiteralPath 'C:\Program Files\MetaTrader 5 Terminal' -Filter 'backtest_report*' -ErrorAction SilentlyContinue
"report present in terminal dir: " + $found.Count
