<#+
.SYNOPSIS
    Run N cold Strategy Tester windows and report the spread of the result, not one number.

.DESCRIPTION
    A single window cannot answer "is this profitable". Measured on this repository: the same build, same
    window (2026.09.01 -> 09.08), fully cold, produced +5.03% and then a different run of the identical
    binary produced -4.34% once the compounding-tier state carried over - the spread between runs is
    larger than every effect the team has been crediting to code changes. So a result is only meaningful
    as a distribution: this script runs -Cold windows back to back and prints each run plus mean, stdev,
    min and max.

.PARAMETER Runs
    How many windows to run. Each 7-day M15 window costs ~22 minutes of wall clock.

.PARAMETER IniPath
    Tester .ini handed to terminal64.exe /config:.

.EXAMPLE
    .\Tools\run_sweep.ps1 -Runs 5
#>
param(
    [int]$Runs = 5,
    [string]$IniPath = 'D:\TraeProjects\metatrader-multistrategy-ea\Tools\backtest.ini'
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$results = @()

for ($i = 1; $i -le $Runs; $i++) {
    "=== run $i of $Runs ==="
    $out = & (Join-Path $here 'run_window.ps1') -IniPath $IniPath -TimeoutSec 3600 -Cold 2>&1
    $line = ($out | Where-Object { $_ -match 'equity: samples=' }) | Select-Object -First 1
    $deltaLine = ($out | Where-Object { $_ -match 'fills: ' }) | Select-Object -First 1
    $pct = $null; $fills = $null
    if ($line -and $line -match 'delta=(-?[\d\.]+) \((-?[\d\.]+)%\)') { $pct = [double]$matches[2] }
    if ($deltaLine -and $deltaLine -match 'fills: (\d+)') { $fills = [int]$matches[1] }
    "  -> $pct % on $fills fills"
    $results += [pscustomobject]@{ run = $i; pct = $pct; fills = $fills }
}

"--- distribution over $Runs cold runs ---"
$valid = $results | Where-Object { $null -ne $_.pct }
$valid | Format-Table -AutoSize | Out-String
if ($valid.Count -ge 2) {
    $s = $valid.pct | Measure-Object -Average -Minimum -Maximum
    $sd = [math]::Sqrt((($valid.pct | ForEach-Object { [math]::Pow($_ - $s.Average, 2) }) | Measure-Object -Sum).Sum / ($valid.Count - 1))
    "mean {0:N3}% | stdev {1:N3}pp | min {2:N3}% | max {3:N3}% | fills mean {4:N0}" -f $s.Average, $sd, $s.Minimum, $s.Maximum, ($valid.fills | Measure-Object -Average).Average
}
