<#+
.SYNOPSIS
    Run several DIFFERENT cold windows and report the spread across them.

.DESCRIPTION
    run_sweep.ps1 repeats one window; since Batch 282 made the tester deterministic, N repeats of one
    window are N identical numbers, which measures nothing. A distribution needs different windows, so
    this script walks a list of dates and prints one line per window plus the mean and spread.

.PARAMETER IniNames
    Base names under Tools\ (without .ini). Each file must already carry its own FromDate/ToDate and
    every varied [TesterInputs] knob explicitly - MT5 inherits the previous run's value for any input
    an ini omits.

.PARAMETER Tail
    Prefix for the dumped output of each run.

.EXAMPLE
    .\Tools\run_windows.ps1 -IniNames 'backtest_w2.ini','backtest_w3.ini','backtest_w4.ini'
#>
param(
    [string[]]$IniNames = @('backtest_w2.ini', 'backtest_w3.ini', 'backtest_w4.ini'),
    [int]$TimeoutSec = 3600
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$rows = @()

foreach ($name in $IniNames) {
    $ini = Join-Path $here $name
    if (-not (Test-Path -LiteralPath $ini)) { "MISSING $ini"; continue }
    $dates = (([IO.File]::ReadAllText($ini)) -split "`r?`n" | Where-Object { $_ -match '^FromDate=|^ToDate=' }) -join ' '
    "=== $name | $dates ==="
    $out = & (Join-Path $here 'run_window.ps1') -IniPath $ini -TimeoutSec $TimeoutSec -Cold 2>&1
    $eq = ($out | Where-Object { $_ -match 'equity: samples=' } | Select-Object -First 1)
    $fl = ($out | Where-Object { $_ -match 'fills: ' } | Select-Object -First 1)
    $dc = ($out | Where-Object { $_ -match 'decisions: ' } | Select-Object -First 1)
    $rj = ($out | Where-Object { $_ -match 'rejects: ' } | Select-Object -First 1)
    $pct = $null; $fills = $null; $dec = $null; $rej = $null
    if ($eq -and $eq -match 'delta=(-?[\d\.]+) \((-?[\d\.]+)%\)') { $pct = [double]$matches[2] }
    if ($fl -and $fl -match 'fills: (\d+)') { $fills = [int]$matches[1] }
    if ($dc -and $dc -match 'decisions: (\d+)') { $dec = [int]$matches[1] }
    if ($rj -and $rj -match 'rejects: (\d+)') { $rej = [int]$matches[1] }
    if ($eq) { "  $eq" }
    if ($fl) { "  $fl" }
    if ($dc) { "  $dc" }
    if ($rj) { "  $rj" }
    $rows += [pscustomobject]@{ window = $name; pct = $pct; fills = $fills; decisions = $dec; rejects = $rej }
}

"--- distribution over $($rows.Count) different cold windows ---"
$rows | Format-Table -AutoSize | Out-String
$valid = $rows | Where-Object { $null -ne $_.pct }
if ($valid.Count -ge 2) {
    $s = $valid.pct | Measure-Object -Average -Minimum -Maximum
    $sd = [math]::Sqrt((($valid.pct | ForEach-Object { [math]::Pow($_ - $s.Average, 2) }) | Measure-Object -Sum).Sum / ($valid.Count - 1))
    "mean {0:N3}% | stdev {1:N3}pp | min {2:N3}% | max {3:N3}% | wins {4}/{5}" -f `
        $s.Average, $sd, $s.Minimum, $s.Maximum, ($valid | Where-Object { $_.pct -gt 0 }).Count, $valid.Count
}
