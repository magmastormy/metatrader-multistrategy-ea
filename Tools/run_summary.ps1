<#+
.SYNOPSIS
    One pass over the journal tail: per run, the equity delta from the heartbeat plus the close fact table.

.DESCRIPTION
    run_window.ps1 prints the summary, but its output is lost once the task returns. This rebuilds the same
    numbers from the journal in one streaming pass: `[COMPOUNDING-TIER-HEARTBEAT] balance=` first/last per run
    (about 10,080 samples over 7 simulated days), fills from EXECUTION-RECEIPT, decisions/rejects from the
    consensus lines, and the ordered close sequence per symbol. Close totals describe recognized records in the
    scanned tail; this reader does not verify complete run boundaries or attribute closes to strategies.

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
    [string]$Path = ''
)

if (-not $Path) {
    $logDir = Join-Path $env:APPDATA 'MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\Tester\logs'
    $latestLog = Get-ChildItem -LiteralPath $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}\.log$' } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latestLog) { throw "no dated tester log found in $logDir" }
    $Path = $latestLog.FullName
}
if (-not (Test-Path -LiteralPath $Path)) { throw "no log: $Path" }

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
                start=$sim; end=$sim; firstBal=$null; lastBal=$null; samples=0; partialStart=($runs.Count -eq 0 -and $start -gt 0)
                fills=0; decisions=0; rejects=0; engineCloses=0; unpricedCloses=0
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

    $closeKind = $null
    $sym = '?'
    $hasPnl = $false
    $pnl = $null
    if ($msg -match '\[ENGINE-CLOSE\]\s+(?<symbol>[^|]+?)\s+\|\s+ticket=(?<ticket>\d+)\s+\|\s+position=(?<position>\d+)\s+\|\s+magic=-?\d+(?:\s+\|\s+net=(?<net>[^|]*))?') {
        $closeKind = 'engine'
        $sym = $matches['symbol'].Trim()
        $netText = $matches['net']
        $hasPnl = $netText -match '^\s*-?\d+(?:\.\d+)?\s*$'
        if ($hasPnl) { $pnl = [double]::Parse($netText.Trim(), [Globalization.CultureInfo]::InvariantCulture) }
    } elseif ($msg -match 'Trade Closed') {
        $closeKind = 'trade'
        if ($msg -match 'Symbol: ([^|]+)') { $sym = $matches[1].Trim() }
        $hasPnl = $msg -match 'Net Profit: (-?\d+(?:\.\d+)?)'
        if ($hasPnl) { $pnl = [double]::Parse($matches[1], [Globalization.CultureInfo]::InvariantCulture) }
    }
    if ($closeKind) {
        if ($closeKind -eq 'engine') { $cur.engineCloses++ }
        if (-not $hasPnl) { $cur.unpricedCloses++ }
        $cur.closes.Add([pscustomobject]@{ sim=$lastSim; sym=$sym; pnl=$pnl; hasPnl=$hasPnl; kind=$closeKind })
        if (-not $cur.symNet.ContainsKey($sym)) { $cur.symNet[$sym] = 0.0 }
        if ($hasPnl) { $cur.symNet[$sym] = $cur.symNet[$sym] + $pnl }
    }
}
$sr.Close(); $reader.Close()

"lines scanned: $lines | runs found: $($runs.Count) | scanned bytes $start-$len of $len | first run may start mid-run: $($start -gt 0) | run completion not verified"
foreach ($r in $runs) {
    if ($r.samples -eq 0 -and $r.closes.Count -eq 0) { continue }
    $hasEquity = $null -ne $r.lastBal -and $null -ne $r.firstBal
    $delta = if ($hasEquity) { $r.lastBal - $r.firstBal } else { $null }
    $pct = if ($hasEquity -and $r.firstBal -ne 0) { 100.0 * $delta / $r.firstBal } else { $null }
    $pctText = if ($null -ne $pct) { '{0:N3}%' -f $pct } else { 'n/a' }
    $startCoverage = if ($r.partialStart) { 'possibly-truncated' } else { 'observed' }
    $pricedCloses = @($r.closes | Where-Object { $_.hasPnl })
    $closeCoverage = if ($r.closes.Count -gt 0) { [math]::Round(100.0 * $pricedCloses.Count / $r.closes.Count, 1) } else { 0.0 }
    $closeNet = 0.0
    foreach ($close in $pricedCloses) { $closeNet += $close.pnl }
    "=== run $($r.start.ToString('yyyy-MM-dd HH:mm')) -> $($r.end.ToString('yyyy-MM-dd HH:mm')) | start=$startCoverage; end=unverified"
    if ($hasEquity) {
        "    observed equity: first $($r.firstBal) last $($r.lastBal) delta $([math]::Round($delta,2)) ($pctText) | samples observed $($r.samples)"
    } else {
        "    observed equity: unavailable | samples observed $($r.samples)"
    }
    "    fills $($r.fills) | decisions $($r.decisions) | rejects $($r.rejects)"
    "    close records observed $($r.closes.Count) | parsed P&L $($pricedCloses.Count)/$($r.closes.Count) ($closeCoverage%) | parsed close net $([math]::Round($closeNet,2)) | unpriced $($r.unpricedCloses) | engine closes $($r.engineCloses) (no strategy attribution here)"
    foreach ($k in ($r.symNet.Keys | Sort-Object { -[math]::Abs($r.symNet[$_]) })) {
        $symbolCloses = @($r.closes | Where-Object { $_.sym -eq $k })
        $symbolPriced = @($symbolCloses | Where-Object { $_.hasPnl })
        $symbolEngine = @($symbolCloses | Where-Object { $_.kind -eq 'engine' }).Count
        "      {0,-22} parsed net {1,10:N2}  priced={2}/{3}  engine={4}" -f $k, $r.symNet[$k], $symbolPriced.Count, $symbolCloses.Count, $symbolEngine
    }
    $seq = $r.closes | Where-Object { $_.sym -eq $Symbol }
    foreach ($s in $seq) {
        $pnlText = if ($s.hasPnl) { '{0:N2}' -f $s.pnl } else { 'unpriced' }
        "      $Symbol {0} [{1}] {2}" -f $s.sim.ToString('MM-dd HH:mm'), $s.kind, $pnlText
    }
}
