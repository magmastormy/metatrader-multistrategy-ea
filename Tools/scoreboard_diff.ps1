<#+
.SYNOPSIS
    Diff two per-window strategy scoreboards and attribute the P&L difference to individual rows.

.DESCRIPTION
    strategy_scoreboard.csv is the only per-strategy record the EA writes: one row per symbol+strategy with
    trade count, wins, average profit and health. Two arms of a single-variable A/B on the same cold window
    therefore differ trade by trade, and this prints which rows the arms disagree about, sorted by the change
    in trade count and in wins, so a P&L delta can be read as "these rows traded more, these rows got worse".

.PARAMETER Base
    Scoreboard CSV of the control arm.

.PARAMETER Variant
    Scoreboard CSV of the treated arm.

.EXAMPLE
    .\Tools\scoreboard_diff.ps1 -Base Tools\artifacts\scoreboards\scoreboard_backtest_w1b_20260901-20260908.csv -Variant Tools\artifacts\scoreboards\scoreboard_backtest_voters1_20260901-20260908.csv
#>
param(
    [Parameter(Mandatory=$true)][string]$Base,
    [Parameter(Mandatory=$true)][string]$Variant,
    [int]$Top = 25
)

function Read-Sb([string]$path) {
    $rows = @{}
    $lines = [IO.File]::ReadAllLines((Resolve-Path $path))
    foreach ($ln in ($lines | Select-Object -Skip 1)) {
        if (-not $ln.Trim()) { continue }
        $q = $ln -split ';'
        if ($q.Count -lt 11) { continue }
        $key = "$($q[0])|$($q[1])"
        $rows[$key] = [pscustomobject]@{
            sym = $q[0]; name = $q[1]
            trades = [int]$q[2]; success = [int]$q[3]; fail = [int]$q[4]; wins = [int]$q[5]
            avg = 0.0
            health = 0.0
            parked = ($q[10].Trim() -ne '0' -and $q[10].Trim() -ne '')
        }
        $rows[$key].avg = [double]::Parse($q[8], [Globalization.CultureInfo]::InvariantCulture)
        $rows[$key].health = [double]::Parse($q[9], [Globalization.CultureInfo]::InvariantCulture)
    }
    return $rows
}

$A = Read-Sb $Base
$B = Read-Sb $Variant

$all = @()
foreach ($k in ($A.Keys + $B.Keys | Sort-Object -Unique)) {
    $x = $A[$k]; $y = $B[$k]
    if ($null -eq $x) { $x = [pscustomobject]@{ sym=($k -split '\|')[0]; name=($k -split '\|')[1]; trades=0; wins=0; avg=0.0; health=0.0; parked=$false } }
    if ($null -eq $y) { $y = [pscustomobject]@{ sym=($k -split '\|')[0]; name=($k -split '\|')[1]; trades=0; wins=0; avg=0.0; health=0.0; parked=$false } }
    $all += [pscustomobject]@{
        sym=$x.sym; name=$x.name
        tA=$x.trades; tB=$y.trades; dT=$y.trades - $x.trades
        wA=$x.wins;   wB=$y.wins;   dW=$y.wins - $x.wins
        aA=$x.avg;    aB=$y.avg;    dAvg=[math]::Round($y.avg - $x.avg, 2)
        hA=[math]::Round($x.health,2); hB=[math]::Round($y.health,2)
        pA=$x.parked; pB=$y.parked
    }
}

$rowsA = $all | Where-Object { $_.tA -gt 0 }
$rowsB = $all | Where-Object { $_.tB -gt 0 }
"base   : with trades $($rowsA.Count) | total trades $(($rowsA | Measure-Object tA -Sum).Sum) | wins $(($rowsA | Measure-Object wA -Sum).Sum) | parked $(($rowsA | Where-Object pA).Count)"
"variant: with trades $($rowsB.Count) | total trades $(($rowsB | Measure-Object tB -Sum).Sum) | wins $(($rowsB | Measure-Object wB -Sum).Sum) | parked $(($rowsB | Where-Object pB).Count)"
""
"--- rows whose trade count moved most ---"
$all | Where-Object { $_.dT -ne 0 } | Sort-Object { [math]::Abs($_.dT) } -Descending | Select-Object -First $Top |
    ForEach-Object { "  {0,4} -> {1,4}  ({2,5})  wins {3,3} -> {4,3}  avg {5,8:N2} -> {6,8:N2}  {7} {8}" -f $_.tA,$_.tB,$_.dT,$_.wA,$_.wB,$_.aA,$_.aB,$_.sym,$_.name }

""
"--- rows whose win count moved most ---"
$all | Where-Object { $_.dW -ne 0 } | Sort-Object { [math]::Abs($_.dW) } -Descending | Select-Object -First $Top |
    ForEach-Object { "  wins {0,3} -> {1,3}  ({2,4})  trades {3,4} -> {4,4}  avg {5,8:N2} -> {6,8:N2}  {7} {8}" -f $_.wA,$_.wB,$_.dW,$_.tA,$_.tB,$_.aA,$_.aB,$_.sym,$_.name }

""
"--- rows that only the variant parked / only the base parked ---"
foreach ($r in ($all | Where-Object { $_.pA -ne $_.pB })) {
    "  parked {0,5} -> {1,5}  health {2} -> {3}  {4} {5}" -f $_.pA,$_.pB,$_.hA,$_.hB,$_.sym,$_.name
}

""
"--- aggregate by strategy name ---"
$byName = @{}
foreach ($r in $all) {
    if (-not $byName.ContainsKey($r.name)) { $byName[$r.name] = [pscustomobject]@{ name=$r.name; tA=0; tB=0; wA=0; wB=0 } }
    $byName[$r.name].tA += $r.tA; $byName[$r.name].tB += $r.tB
    $byName[$r.name].wA += $r.wA; $byName[$r.name].wB += $r.wB
}
$byName.Values | Sort-Object { [math]::Abs($_.tB - $_.tA) } -Descending | Select-Object -First 12 |
    ForEach-Object { "  {0,5} -> {1,5} trades ({2,5}) | wins {3,4} -> {4,4} | {5}" -f $_.tA,$_.tB,($_.tB-$_.tA),$_.wA,$_.wB,$_.name }
