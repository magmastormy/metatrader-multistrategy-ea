<#+
.SYNOPSIS
    Run several DIFFERENT cold windows and report the spread across them.

.DESCRIPTION
    Runs explicitly supplied, distinct INI windows cold, reports each validated result, and computes
    distribution statistics from successful windows only. Failed or missing windows never enter the
    measured distribution.

.PARAMETER IniNames
    Base names under Tools\ (without .ini). Each file must already carry its own FromDate/ToDate and
    every varied [TesterInputs] knob explicitly - MT5 inherits the previous run's value for any input
    an ini omits.

.EXAMPLE
    .\Tools\run_windows.ps1 -IniNames 'backtest_w2.ini','backtest_w3.ini','backtest_w4.ini'
#>
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string[]]$IniNames,
    [ValidateRange(30, 86400)][int]$TimeoutSec = 3600
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$rows = [System.Collections.Generic.List[object]]::new()
$windowSpecs = [System.Collections.Generic.List[object]]::new()
$seenNames = @{}

if ($IniNames.Count -lt 2) { throw 'At least two distinct cold windows are required for a distribution' }

foreach ($name in $IniNames) {
    if ([IO.Path]::GetFileName($name) -ne $name -or [IO.Path]::GetExtension($name) -ne '.ini') {
        throw "Expected an .ini base name under Tools: $name"
    }
    if ($seenNames.ContainsKey($name)) { throw "Duplicate INI supplied: $name" }
    $seenNames[$name] = $true
    $ini = Join-Path $here $name
    if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) { throw "Missing INI: $ini" }
    $content = [IO.File]::ReadAllText($ini)
    $fromMatch = [regex]::Match($content, '(?m)^FromDate=(\S+)\s*$')
    $toMatch = [regex]::Match($content, '(?m)^ToDate=(\S+)\s*$')
    if (-not $fromMatch.Success -or -not $toMatch.Success) { throw "$name must contain explicit FromDate and ToDate values" }
    try {
        $from = [datetime]::ParseExact($fromMatch.Groups[1].Value, 'yyyy.MM.dd', [Globalization.CultureInfo]::InvariantCulture)
        $to = [datetime]::ParseExact($toMatch.Groups[1].Value, 'yyyy.MM.dd', [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        throw "$name dates must use yyyy.MM.dd"
    }
    if ($to -le $from) { throw "$name has a non-positive window: $($from.ToString('yyyy.MM.dd')) .. $($to.ToString('yyyy.MM.dd'))" }
    [void]$windowSpecs.Add([pscustomobject]@{ name = $name; path = $ini; from = $from; to = $to; dates = "FromDate=$($from.ToString('yyyy.MM.dd')) ToDate=$($to.ToString('yyyy.MM.dd'))" })
}

$orderedSpecs = @($windowSpecs | Sort-Object from)
for ($i = 1; $i -lt $orderedSpecs.Count; $i++) {
    if ($orderedSpecs[$i].from -lt $orderedSpecs[$i - 1].to) {
        throw "Overlapping windows are not independent: $($orderedSpecs[$i - 1].name) and $($orderedSpecs[$i].name)"
    }
}

foreach ($spec in $windowSpecs) {
    $name = $spec.name
    try {
        $ini = $spec.path
        "=== $name | $($spec.dates) ==="
        $out = & (Join-Path $here 'run_window.ps1') -IniPath $ini -TimeoutSec $TimeoutSec -Cold 2>&1
        $eq = $out | Where-Object { $_ -match 'equity: samples=' } | Select-Object -First 1
        $fl = $out | Where-Object { $_ -match 'fills: ' } | Select-Object -First 1
        $dc = $out | Where-Object { $_ -match 'decisions: ' } | Select-Object -First 1
        $rj = $out | Where-Object { $_ -match 'rejects: ' } | Select-Object -First 1
        if (-not $eq -or $eq -notmatch 'delta=(-?[\d\.]+) \((-?[\d\.]+)%\)') {
            throw 'Completed window returned no parseable equity summary'
        }
        $pct = [double]::Parse($matches[2], [Globalization.CultureInfo]::InvariantCulture)
        $fills = $null; $dec = $null; $rej = $null
        if ($fl -and $fl -match 'fills: (\d+)') { $fills = [int]$matches[1] }
        if ($dc -and $dc -match 'decisions: (\d+)') { $dec = [int]$matches[1] }
        if ($rj -and $rj -match 'rejects: (\d+)') { $rej = [int]$matches[1] }
        if ($eq) { "  $eq" }
        if ($fl) { "  $fl" }
        if ($dc) { "  $dc" }
        if ($rj) { "  $rj" }
        [void]$rows.Add([pscustomobject]@{ window = $name; status = 'valid'; pct = $pct; fills = $fills; decisions = $dec; rejects = $rej; error = '' })
    } catch {
        $message = $_.Exception.Message
        Write-Warning "$name failed: $message"
        [void]$rows.Add([pscustomobject]@{ window = $name; status = 'failed'; pct = $null; fills = $null; decisions = $null; rejects = $null; error = $message })
    }
}

"--- distribution over $(@($rows | Where-Object { $_.status -eq 'valid' }).Count) valid cold windows ($($rows.Count) attempted) ---"
$rows | Select-Object window, status, pct, fills, decisions, rejects, error | Format-Table -AutoSize | Out-String
$valid = @($rows | Where-Object { $_.status -eq 'valid' -and $null -ne $_.pct })
if ($valid.Count -ge 2) {
    $s = $valid.pct | Measure-Object -Average -Minimum -Maximum
    $sd = [math]::Sqrt((($valid.pct | ForEach-Object { [math]::Pow($_ - $s.Average, 2) }) | Measure-Object -Sum).Sum / ($valid.Count - 1))
    "mean {0:N3}% | stdev {1:N3}pp | min {2:N3}% | max {3:N3}% | wins {4}/{5}" -f `
        $s.Average, $sd, $s.Minimum, $s.Maximum, ($valid | Where-Object { $_.pct -gt 0 }).Count, $valid.Count
}
if ($valid.Count -lt 2) { throw 'Fewer than two valid cold windows completed; no distribution was calculated' }
if (@($rows | Where-Object { $_.status -eq 'failed' }).Count -gt 0) {
    throw 'One or more windows failed; inspect warnings and rerun those windows before using the distribution'
}
