<#+
.SYNOPSIS
    One pass over the journal tail: per run, the equity delta from the heartbeat plus the close fact table.

.DESCRIPTION
    run_window.ps1 prints the summary, but its output is lost once the task returns. This rebuilds the same
    numbers from the journal in one streaming pass: `[COMPOUNDING-TIER-HEARTBEAT] balance=` first/last per run
    (about 10,080 samples over 7 simulated days), fills from EXECUTION-RECEIPT, decisions/rejects from the
    consensus lines, and the ordered close sequence per symbol.

.PARAMETER TailMB
    Journal tail to scan. A 7-day M15 run is roughly 130-200 MB of journal, so 200 covers one run comfortably.

.PARAMETER Symbol
    Symbol whose close sequence is printed in order.

.EXAMPLE
    .\Tools\run_summary.ps1 -TailMB 200 -Symbol 'Volatility 75 Index'
#>
param(
    [int]$TailMB = 200,
    [string]$Symbol = 'Volatility 75 Index',
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
$lines = 0

while (-not $sr.EndOfStream) {
    $ln = $sr.ReadLine()
    if (-not $ln) { continue }
    $lines++
    $f = $ln -split "`t"
    if ($f.Count -lt 4) { continue }
    $msg = $f[$f.Count - 1]

    $sim = $null
    if ($msg -match '^(20\d\d\.\d\d\.\d\d \d\d:\d\d:\d\d)') {
        $sim = [datetime]::ParseExact($matches[1], 'yyyy.MM.dd HH:mm:ss', $null)
    }
    if ($sim) {
        if ($null -eq $lastSim -or $sim -lt $lastSim) {
            $cur = [pscustomobject]@{
                start=$sim; end=$sim; firstBal=$null; lastBal=$null; samples=0
                fills=0; decisions=0; rejects=0
                closes=(New-Object 'System.Collections.Generic.List[object]')
                symNet=@{}
            }
            $runs.Add($cur)
        }
        $lastSim = $sim
        if ($cur) { $cur.end = $sim }
    }
    if (-not $cur) { continue }

    if ($msg -match '\[COMPOUNDING-TIER-HEARTBEAT\].*balance=([\-\d\.]+)') {
        $b = [double]::Parse($matches[1], [Globalization.CultureInfo]::InvariantCulture)
        if ($null -eq $cur.firstBal) { $cur.firstBal = $b }
        $cur.lastBal = $b
        $cur.samples++
    }
    elseif ($msg -match '\[EXECUTION-RECEIPT\]') { $cur.fills++ }
    elseif ($msg -match '\[CONSENSUS-DECISION\]') { $cur.decisions++ }
    elseif ($msg -match '\[CONSENSUS-REJECT\]') { $cur.rejects++ }

    if ($msg -match 'Trade Closed' -and $msg -match 'Net Profit: (-?[\d\.]+)') {
        $pnl = [double]::Parse($matches[1], [Globalization.CultureInfo]::InvariantCulture)
        $sym = '?'
        if ($msg -match 'Symbol: ([^|]+?) \| Ticket') { $sym = $matches[1].Trim() }
        $cur.closes.Add([pscustomobject]@{ sim=$lastSim; sym=$sym; pnl=$pnl })
        if (-not $cur.symNet.ContainsKey($sym)) { $cur.symNet[$sym] = 0.0 }
        $cur.symNet[$sym] = $cur.symNet[$sym] + $pnl
    }
}
$sr.Close(); $reader.Close()

"lines scanned: $lines | runs found: $($runs.Count)"
foreach ($r in $runs) {
    if ($r.samples -eq 0 -and $r.closes.Count -eq 0) { continue }
    $delta = if ($null -ne $r.lastBal -and $null -ne $r.firstBal) { $r.lastBal - $r.firstBal } else { 0 }
    $pct = if ($r.firstBal) { 100.0 * $delta / $r.firstBal } else { 0 }
    "=== run $($r.start.ToString('yyyy-MM-dd HH:mm')) -> $($r.end.ToString('yyyy-MM-dd HH:mm'))"
    "    equity: first $($r.firstBal) last $($r.lastBal) delta $([math]::Round($delta,2)) ($([math]::Round($pct,3))%) samples $($r.samples)"
    "    fills $($r.fills) | decisions $($r.decisions) | rejects $($r.rejects) | closes $($r.closes.Count)"
    foreach ($k in ($r.symNet.Keys | Sort-Object { -[math]::Abs($r.symNet[$_]) })) {
        $n = ($r.closes | Where-Object { $_.sym -eq $k }).Count
        "      {0,-22} {1,10:N2}  n={2}" -f $k, $r.symNet[$k], $n
    }
    $seq = $r.closes | Where-Object { $_.sym -eq $Symbol }
    foreach ($s in $seq) { "      $Symbol {0} {1:N2}" -f $s.sim.ToString('MM-dd HH:mm'), $s.pnl }
}
