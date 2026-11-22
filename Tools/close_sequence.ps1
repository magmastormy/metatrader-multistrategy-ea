<#+
.SYNOPSIS
    Print the close sequence (P&L in order) for one symbol, per run, from the tester journal.

.DESCRIPTION
    A per-symbol loss-streak circuit breaker is only justified if a symbol's losses actually arrive in
    consecutive runs. This prints recognized close records observed in the scanned tail so the streak structure
    can be seen instead of assumed. Missing P&L stays unpriced and breaks a loss streak. Runs are segmented by simulation-time regression (the wall-clock column is
    not a run identity: MT5 flushes a finished run's journal with one stamp).

.PARAMETER Symbol
    Symbol name as it appears in the journal, e.g. 'Volatility 75 Index'.

.PARAMETER TailMB
    Journal tail to scan; the journal is multi-gigabyte.

.EXAMPLE
    .\Tools\close_sequence.ps1 -Symbol 'Volatility 75 Index' -TailMB 430
#>
param(
    [Parameter(Mandatory=$true)][string]$Symbol,
    [int]$TailMB = 430,
    [string]$Path = "$env:APPDATA\MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\Tester\logs\20261112.log"
)

$reader = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
$len = $reader.Length
$start = $len - ([int64]$TailMB * 1MB)
if ($start -lt 0) { $start = [int64]0 }
$reader.Position = $start
$sr = New-Object IO.StreamReader($reader, [Text.Encoding]::Unicode)
if ($start -gt 0) { [void]$sr.ReadLine() }

$runs = New-Object 'System.Collections.Generic.List[object]'
$cur = $null
$lastSim = $null

while (-not $sr.EndOfStream) {
    $ln = $sr.ReadLine()
    if (-not $ln) { continue }
    $f = $ln -split "`t"
    if ($f.Count -lt 4) { continue }
    $msg = $f[$f.Count - 1]

    $sim = $null
    if ($msg -match '^(20\d\d\.\d\d\.\d\d \d\d:\d\d:\d\d)') {
        $sim = [datetime]::ParseExact($matches[1], 'yyyy.MM.dd HH:mm:ss', $null)
    }
    if ($sim) {
        if ($null -eq $lastSim -or $sim -lt $lastSim) {
            $cur = [pscustomobject]@{ start=$sim; end=$sim; partialStart=($runs.Count -eq 0 -and $start -gt 0); closes=(New-Object 'System.Collections.Generic.List[object]') }
            $runs.Add($cur)
        }
        $lastSim = $sim
        if ($cur) { $cur.end = $sim }
    }
    if (-not $cur) { continue }

    $closeKind = $null
    $hasPnl = $false
    $pnl = $null
    if ($msg -match '\[ENGINE-CLOSE\]\s+(?<symbol>[^|]+?)\s+\|\s+ticket=\d+\s+\|\s+position=\d+\s+\|\s+magic=-?\d+(?:\s+\|\s+net=(?<net>[^|]*))?') {
        if ([string]::Equals($matches['symbol'].Trim(), $Symbol, [StringComparison]::OrdinalIgnoreCase)) {
            $closeKind = 'engine'
            $netText = $matches['net']
            $hasPnl = $netText -match '^\s*-?\d+(?:\.\d+)?\s*$'
            if ($hasPnl) { $pnl = [double]::Parse($netText.Trim(), [Globalization.CultureInfo]::InvariantCulture) }
        }
    } elseif ($msg -match 'Trade Closed' -and $msg -match 'Symbol: ([^|]+)') {
        $recordSymbol = $matches[1].Trim()
        if ([string]::Equals($recordSymbol, $Symbol, [StringComparison]::OrdinalIgnoreCase)) {
            $closeKind = 'trade'
            $hasPnl = $msg -match 'Net Profit: (-?\d+(?:\.\d+)?)'
            if ($hasPnl) { $pnl = [double]::Parse($matches[1], [Globalization.CultureInfo]::InvariantCulture) }
        }
    }
    if ($closeKind) {
        $cur.closes.Add([pscustomobject]@{ sim=$lastSim; pnl=$pnl; hasPnl=$hasPnl; kind=$closeKind })
    }
}
$sr.Close(); $reader.Close()

"scanned bytes $start-$len of $len | first run may start mid-run: $($start -gt 0) | run completion not verified"
foreach ($r in $runs) {
    if ($r.closes.Count -eq 0) { continue }
    $pricedCloses = @($r.closes | Where-Object { $_.hasPnl })
    $coverage = [math]::Round(100.0 * $pricedCloses.Count / $r.closes.Count, 1)
    $net = 0.0
    foreach ($close in $pricedCloses) { $net += $close.pnl }
    $engineCloses = @($r.closes | Where-Object { $_.kind -eq 'engine' }).Count
    $startCoverage = if ($r.partialStart) { 'possibly-truncated' } else { 'observed' }
    "=== $Symbol | run $($r.start.ToString('yyyy-MM-dd HH:mm')) -> $($r.end.ToString('yyyy-MM-dd HH:mm')) | start=$startCoverage; end=unverified | closes observed $($r.closes.Count) | parsed P&L $($pricedCloses.Count)/$($r.closes.Count) ($coverage%) | parsed net $([math]::Round($net,2)) | engine closes $engineCloses (no strategy attribution inferred) ==="
    $seq = @()
    $i = 0
    foreach ($c in $r.closes) {
        $i++
        $pnlText = if ($c.hasPnl) { '{0:N2}' -f $c.pnl } else { 'unpriced' }
        $seq += ("{0}[{1}]:{2}" -f $i, $c.kind, $pnlText)
    }
    "  " + ($seq -join '  ')
    # streak statistics: longest losing run, and how much of the net loss sits inside streaks of 2+
    $maxStreak = 0; $streak = 0; $lossInStreaks = 0.0; $streakCount = 0
    foreach ($c in $r.closes) {
        if (-not $c.hasPnl) {
            if ($streak -ge 2) { $streakCount++ }
            $streak = 0
            continue
        }
        if ($c.pnl -lt 0) {
            $streak++
            if ($streak -ge 2) { $lossInStreaks += $c.pnl }
            if ($streak -gt $maxStreak) { $maxStreak = $streak }
        } else {
            if ($streak -ge 2) { $streakCount++ }
            $streak = 0
        }
    }
    if ($streak -ge 2) { $streakCount++ }
    "  longest losing streak $maxStreak | losing runs of 2+ $streakCount | P&L inside runs of 2+ $([math]::Round($lossInStreaks,2))"
}
