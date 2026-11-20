<#+
.SYNOPSIS
    Per-strategy dollar attribution from the tester journal, segmented into runs.

.DESCRIPTION
    The close path logs [STRATEGY-GOVERNANCE] with the position ID and exact attribution decision. Only
    single-contributor outcomes are shown as strategy-specific P&L. Diagnostic stored-position attribution
    records are accepted as a fallback for journals without governance records. [ENGINE-CLOSE] records are
    included in priced close totals, but stay unattributed unless matching contributor evidence exists.

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
    [string]$Path = '',
    [int]$LastRuns = 4,
    # The journal accumulates every run and reaches multiple gigabytes, so only the tail is scanned; the tail
    # is where the runs of interest are. Size it above the combined journal size of every run you want.
    [int]$TailMB = 160
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

$runs = New-Object 'System.Collections.Generic.List[object]'
$cur = $null
$lastSim = $null

function NewRun {
    return [pscustomobject]@{
        simStart = $null; simEnd = $null; partialStart = $false; closes = 0; pricedCloses = 0; unpricedCloses = 0; pnl = 0.0; byStrat = @{}; bySym = @{}
        evidenceByPosition = @{}; sharedCloses = 0; sharedPnl = 0.0; excludedByReason = @{}; engineCloses = 0
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
            $cur.partialStart = ($runs.Count -eq 0 -and $start -gt 0)
            $runs.Add($cur)
            $cur.simStart = $sim
        }
        $lastSim = $sim
        if ($cur) { $cur.simEnd = $sim }
    }

    if (-not $cur) { continue }

    if ($msg -match '\[STRATEGY-GOVERNANCE\]\s+position=(\d+)\s*\|\s*outcome=eligible\s*\|\s*strategy=([^|]+)') {
        $positionId = $matches[1]
        $cur.evidenceByPosition[$positionId] = [pscustomobject]@{ kind='eligible'; strategy=$matches[2].Trim() }
        continue
    }

    if ($msg -match '\[STRATEGY-GOVERNANCE\]\s+position=(\d+)\s*\|\s*outcome=excluded\s*\|\s*reason=([^|]+)') {
        $cur.evidenceByPosition[$matches[1]] = [pscustomobject]@{ kind='excluded'; reason=$matches[2].Trim() }
        continue
    }

    if ($msg -match '\[TRADE-ATTRIBUTION\]\s+stored\s+position=(\d+)\s*\|\s*contributors=(.*)$') {
        $names = @($matches[2] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $cur.evidenceByPosition[$matches[1]] = [pscustomobject]@{ kind='contributors'; names=$names }
        continue
    }

    $closeKind = $null
    $sym = '?'
    $positionId = ''
    $hasPnl = $false
    $pnl = 0.0
    if ($msg -match '\[ENGINE-CLOSE\]\s+(?<symbol>[^|]+?)\s+\|\s+ticket=\d+\s+\|\s+position=(?<position>\d+)\s+\|\s+magic=-?\d+(?:\s+\|\s+net=(?<net>[^|]*))?') {
        $closeKind = 'engine'
        $sym = $matches['symbol'].Trim()
        $positionId = $matches['position']
        $netText = $matches['net']
        $hasPnl = $netText -match '^\s*-?\d+(?:\.\d+)?\s*$'
        if ($hasPnl) { $pnl = [double]::Parse($netText.Trim(), [Globalization.CultureInfo]::InvariantCulture) }
    } elseif ($msg -match 'Trade Closed') {
        $closeKind = 'trade'
        $sym = if ($msg -match 'Symbol: ([^|]+)') { $matches[1].Trim() } else { '?' }
        $positionId = if ($msg -match 'PositionID: (\d+)') { $matches[1] } else { '' }
        $hasPnl = $msg -match 'Net Profit: (-?\d+(?:\.\d+)?)'
        if ($hasPnl) { $pnl = [double]::Parse($matches[1], [Globalization.CultureInfo]::InvariantCulture) }
    }

    if ($closeKind) {
        $cur.closes++
        if ($closeKind -eq 'engine') { $cur.engineCloses++ }
        if (-not $cur.bySym.ContainsKey($sym)) { $cur.bySym[$sym] = [pscustomobject]@{ sym=$sym; pnl=0.0; n=0; unpriced=0; engine=0 } }
        $cur.bySym[$sym].n++
        if ($closeKind -eq 'engine') { $cur.bySym[$sym].engine++ }
        if ($hasPnl) {
            $cur.pricedCloses++
            $cur.pnl += $pnl
            $cur.bySym[$sym].pnl += $pnl
        } else {
            $cur.unpricedCloses++
            $cur.bySym[$sym].unpriced++
            if ($positionId -and $cur.evidenceByPosition.ContainsKey($positionId)) {
                [void]$cur.evidenceByPosition.Remove($positionId)
            }
            continue
        }

        $evidence = if ($positionId -and $cur.evidenceByPosition.ContainsKey($positionId)) {
            $matched = $cur.evidenceByPosition[$positionId]
            [void]$cur.evidenceByPosition.Remove($positionId)
            $matched
        } else { $null }

        if ($evidence -and $evidence.kind -eq 'eligible') {
            $name = $evidence.strategy
            if ($name) {
                if (-not $cur.byStrat.ContainsKey($name)) { $cur.byStrat[$name] = [pscustomobject]@{ name=$name; pnl=0.0; n=0 } }
                $cur.byStrat[$name].pnl += $pnl; $cur.byStrat[$name].n++
            } else {
                $reason = 'empty_strategy_name'
                if (-not $cur.excludedByReason.ContainsKey($reason)) { $cur.excludedByReason[$reason] = [pscustomobject]@{ reason=$reason; pnl=0.0; n=0 } }
                $cur.excludedByReason[$reason].pnl += $pnl; $cur.excludedByReason[$reason].n++
            }
        } elseif ($evidence -and $evidence.kind -eq 'excluded' -and $evidence.reason -eq 'multi_contributor_not_causal') {
            $cur.sharedCloses++; $cur.sharedPnl += $pnl
        } elseif ($evidence -and $evidence.kind -eq 'contributors' -and $evidence.names.Count -eq 1) {
            $name = $evidence.names[0]
            if (-not $cur.byStrat.ContainsKey($name)) { $cur.byStrat[$name] = [pscustomobject]@{ name=$name; pnl=0.0; n=0 } }
            $cur.byStrat[$name].pnl += $pnl; $cur.byStrat[$name].n++
        } elseif ($evidence -and $evidence.kind -eq 'contributors' -and $evidence.names.Count -gt 1) {
            $cur.sharedCloses++; $cur.sharedPnl += $pnl
        } else {
            $reason = if (-not $positionId) { 'missing_position_id' } elseif ($evidence -and $evidence.kind -eq 'excluded') { $evidence.reason } elseif ($closeKind -eq 'engine') { 'engine_managed_unattributed' } else { 'no_attribution_evidence' }
            if (-not $cur.excludedByReason.ContainsKey($reason)) { $cur.excludedByReason[$reason] = [pscustomobject]@{ reason=$reason; pnl=0.0; n=0 } }
            $cur.excludedByReason[$reason].pnl += $pnl; $cur.excludedByReason[$reason].n++
        }
    }
}
$sr.Close(); $reader.Close()

"lines scanned: $n | runs found: $($runs.Count) | scanned bytes $start-$len of $len | first run may start mid-run: $($start -gt 0) | run completion not verified"
$take = @($runs | Select-Object -Last $LastRuns)
$i = $runs.Count - $take.Count
foreach ($r in $take) {
    $i++
    $excludedCount = 0
    if ($r.excludedByReason.Count -gt 0) {
        $excludedCount = ($r.excludedByReason.Values | Measure-Object -Property n -Sum).Sum
    }
    $singleContributorCloses = 0
    $singleContributorPnl = 0.0
    foreach ($strategy in $r.byStrat.Values) {
        $singleContributorCloses += $strategy.n
        $singleContributorPnl += $strategy.pnl
    }
    $parsedNet = [math]::Round($r.pnl, 2).ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
    $singleContributorNet = [math]::Round($singleContributorPnl, 2).ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
    $sharedNet = [math]::Round($r.sharedPnl, 2).ToString('F2', [Globalization.CultureInfo]::InvariantCulture)
    $coverage = if ($r.closes -gt 0) { [math]::Round(100.0 * $r.pricedCloses / $r.closes, 1) } else { 0.0 }
    $singleCoverage = if ($r.pricedCloses -gt 0) { [math]::Round(100.0 * $singleContributorCloses / $r.pricedCloses, 1) } else { 0.0 }
    $startCoverage = if ($r.partialStart) { 'possibly-truncated' } else { 'journal-begin-observed' }
    "=== run $i | $($r.simStart.ToString('yyyy-MM-dd HH:mm')) -> $($r.simEnd.ToString('yyyy-MM-dd HH:mm')) | start=$startCoverage; end=unverified | observed closes $($r.closes) | priced P&L $($r.pricedCloses)/$($r.closes) ($coverage%) | parsed net $parsedNet | engine closes $($r.engineCloses) | multi $($r.sharedCloses) | excluded $excludedCount ==="
    "  direct singleton attribution: $singleContributorCloses/$($r.pricedCloses) priced closes ($singleCoverage%) | net $singleContributorNet; not a strategy-removal verdict"
    "  exact single-contributor P&L by strategy:"
    $r.byStrat.Values | Sort-Object pnl | ForEach-Object { "    {0,10:N2}  n={1,4}  {2}" -f $_.pnl, $_.n, $_.name }
    "  multi-contributor closes: $($r.sharedCloses) | net $sharedNet | unallocated"
    "  closes without parsed net P&L: $($r.unpricedCloses) (excluded from all dollar totals)"
    "  other excluded closes: $excludedCount"
    $r.excludedByReason.Values | Sort-Object reason | ForEach-Object { "    {0,10:N2}  n={1,4}  excluded: {2}" -f $_.pnl, $_.n, $_.reason }
    "  by symbol:"
    $r.bySym.Values | Sort-Object pnl | ForEach-Object { "    {0,10:N2}  closes={1,4}  engine={2,3}  unpriced={3,3}  {4}" -f $_.pnl, $_.n, $_.engine, $_.unpriced, $_.sym }
}
