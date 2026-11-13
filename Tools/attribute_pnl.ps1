<#+
.SYNOPSIS
    Per-strategy dollar attribution from the tester journal, segmented into runs.

.DESCRIPTION
    Every close emits two lines in order:
        [EnterpriseManager] Trade Closed | Symbol: X | Ticket: n | PositionID: n | Net Profit: p | Result: ...
        [TRADE-ATTRIBUTION] Contributors: A,B,
    The first has the money, the second the strategy names. Joining them yields per-strategy P&L that can be
    reconciled against the per-minute [COMPOUNDING-TIER-HEARTBEAT] account delta.

    The journal appends every run and the wall-clock column is not a run identity, but the simulation
    timestamp is: it advances monotonically inside a run and restarts at the window's FromDate for the next.
    So a decrease in simulation time marks a new run. The script is single-pass because the journal is multi-
    gigabyte on this terminal.

.PARAMETER Path
    Tester journal (UTF-16LE).

.PARAMETER LastRuns
    How many trailing runs to report in full.

.EXAMPLE
    .\Tools\attribute_pnl.ps1 -LastRuns 4
#>
param(
    [string]$Path = "$env:APPDATA\MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\Tester\logs\20261112.log",
    [int]$LastRuns = 4,
    # The journal accumulates every run and reaches multiple gigabytes, so only the tail is scanned; the tail
    # is where the runs of interest are. Size it above the combined journal size of every run you want.
    [int]$TailMB = 160
)

if (-not (Test-Path -LiteralPath $Path)) { throw "no log: $Path" }

$runs = New-Object 'System.Collections.Generic.List[object]'
$cur = $null
$lastSim = $null
$lastClose = $null

function NewRun {
    return [pscustomobject]@{
        simStart = $null; simEnd = $null; closes = 0; pnl = 0.0; byStrat = @{}; bySym = @{}; unattributed = 0
    }
}

$reader = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
$len = $reader.Length
$start = $len - ([int64]$TailMB * 1MB)
if ($start -lt 0) { $start = [int64]0 }
$reader.Position = $start
$sr = New-Object IO.StreamReader($reader, [Text.Encoding]::Unicode)
if ($start -gt 0) { [void]$sr.ReadLine() }   # first partial line of the tail is discarded
$n = 0
while (-not $sr.EndOfStream) {
    $ln = $sr.ReadLine()
    $n++
    if (-not $ln) { continue }
    $f = $ln -split "`t"
    if ($f.Count -lt 4) { continue }
    $msg = $f[$f.Count - 1]

    $sim = $null
    if ($msg -match '^(20\d\d\.\d\d\.\d\d \d\d:\d\d:\d\d)') { $sim = [datetime]::ParseExact($matches[1], 'yyyy.MM.dd HH:mm:ss', $null) }
    elseif ($msg -match '^\s*(20\d\d\.\d\d\.\d\d \d\d:\d\d:\d\d)') { $sim = [datetime]::ParseExact($matches[1], 'yyyy.MM.dd HH:mm:ss', $null) }

    if ($sim) {
        if ($null -eq $lastSim -or $sim -lt $lastSim) {
            $cur = NewRun
            $runs.Add($cur)
            $cur.simStart = $sim
        }
        $lastSim = $sim
        if ($cur) { $cur.simEnd = $sim }
    }

    if (-not $cur) { continue }

    if ($msg -match 'Trade Closed') {
        $sym = if ($msg -match 'Symbol: ([^|]+)') { $matches[1].Trim() } else { '?' }
        $pnl = if ($msg -match 'Net Profit: (-?[\d\.]+)') { [double]::Parse($matches[1], [Globalization.CultureInfo]::InvariantCulture) } else { 0.0 }
        $cur.closes++; $cur.pnl += $pnl; $cur.unattributed++
        if (-not $cur.bySym.ContainsKey($sym)) { $cur.bySym[$sym] = [pscustomobject]@{ sym=$sym; pnl=0.0; n=0 } }
        $cur.bySym[$sym].pnl += $pnl; $cur.bySym[$sym].n++
        $lastClose = [pscustomobject]@{ sym=$sym; pnl=$pnl }
        continue
    }

    if ($msg -match 'TRADE-ATTRIBUTION\] Contributors: (.+)$' -and $lastClose -ne $null) {
        $names = @($matches[1] -split ',' | Where-Object { $_.Trim() })
        $share = $lastClose.pnl / [math]::Max(1, $names.Count)
        foreach ($nm in $names) {
            $k = $nm.Trim()
            if (-not $cur.byStrat.ContainsKey($k)) { $cur.byStrat[$k] = [pscustomobject]@{ name=$k; pnl=0.0; n=0 } }
            $cur.byStrat[$k].pnl += $share; $cur.byStrat[$k].n++
        }
        $cur.unattributed--
        $lastClose = $null
    }
}
$sr.Close(); $reader.Close()

"lines scanned: $n | runs found: $($runs.Count)"
$take = $runs | Select-Object -Last $LastRuns
$i = $runs.Count - $take.Count
foreach ($r in $take) {
    $i++
    "=== run $i | $($r.simStart.ToString('yyyy-MM-dd HH:mm')) -> $($r.simEnd.ToString('yyyy-MM-dd HH:mm')) | closes $($r.closes) | net $([math]::Round($r.pnl,2)) | unattributed $($r.unattributed) ==="
    "  by strategy (close split across its contributors):"
    $r.byStrat.Values | Sort-Object pnl | ForEach-Object { "    {0,10:N2}  n={1,4}  {2}" -f $_.pnl, $_.n, $_.name }
    "  by symbol:"
    $r.bySym.Values | Sort-Object pnl | ForEach-Object { "    {0,10:N2}  n={1,4}  {2}" -f $_.pnl, $_.n, $_.sym }
}
