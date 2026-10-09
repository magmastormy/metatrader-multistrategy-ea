"START" | Set-Content -Encoding ASCII "D:\TraeProjects\metatrader-multistrategy-ea\_mk_start.txt"
$ErrorActionPreference = "Stop"
try {
  $log = "C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\MQL5\logs\20260915.log"
  $out = "D:\TraeProjects\metatrader-multistrategy-ea\_log_analysis.txt"
  $opens = [System.Collections.Generic.List[string]]::new()
  $consensusCount = 0; $quorumNotMet = 0
  $circuitCount = 0
  $disabledReg = 0; $enabledFalse = 0
  $initList = [System.Collections.Generic.List[string]]::new()
  $deinitList = [System.Collections.Generic.List[string]]::new()
  $noSignalSamples = [System.Collections.Generic.List[string]]::new()
  $riskRejectSamples = [System.Collections.Generic.List[string]]::new()
  $total = 0
  $dailyLoss = 0; $cooldown = 0; $noSignal = 0; $riskReject = 0
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  Get-Content $log -Encoding Unicode -ReadCount 2000 | ForEach-Object {
    foreach ($line in $_) {
      $total++
      $parts = $line -split "`t"
      $t = if ($parts.Count -ge 3) { $parts[2] } else { "?" }
      $sym = "?"
      if ($line -match '\(([^,]+),') { $sym = $Matches[1].Trim() }
      if ($line -match 'TRADE-OP' -and $line -match 'OPEN') {
        $opens.Add("$t|$sym|$line")
      }
      if ($line -match 'CONSENSUS') {
        $consensusCount++
        if ($line -match 'not met|insufficient|below|fewer|low|quorum') { $quorumNotMet++ }
      }
      if ($line -match 'RISK-CIRCUIT-BREAKER') { $circuitCount++ }
      if ($line -match 'disabled by registry') { $disabledReg++ }
      if ($line -match 'Enabled: false') { $enabledFalse++ }
      if ($line -match '\[INIT-START\]|OnInit') { $initList.Add($t) }
      if ($line -match '\[DEINIT-START\]|OnDeinit') { $deinitList.Add($t) }
      if ($line -match 'DailyLossLimit|daily loss|daily drawdown') { $dailyLoss++ }
      if ($line -match 'Cooldown|cooldown') { $cooldown++ }
      if ($line -match 'no signal|no trade|no valid signal|signal.*none|NO SIGNAL') { $noSignal++; if ($noSignalSamples.Count -lt 5) { $noSignalSamples.Add($t+' '+($line -replace '\t',' ')) } }
      if ($line -match 'risk.*reject|rejected by risk|risk_approved.*false|not approved') { $riskReject++; if ($riskRejectSamples.Count -lt 5) { $riskRejectSamples.Add($t+' '+($line -replace '\t',' ')) } }
    }
  }
  $sw.Stop()
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("TOTAL_LINES=$total  ELAPSED_MS=$($sw.ElapsedMilliseconds)")
  $lines.Add("TRADE_OPENS=$($opens.Count)")
  $lines.Add("CONSENSUS_LINES=$consensusCount  QUORUM_NOT_MET_LINES=$quorumNotMet")
  $lines.Add("RISK_CIRCUIT_LINES=$circuitCount")
  $lines.Add("DISABLED_BY_REGISTRY=$disabledReg  ENABLED_FALSE=$enabledFalse")
  $lines.Add("DAILYLOSS_HITS=$dailyLoss  COOLDOWN_HITS=$cooldown  NOSIGNAL_HITS=$noSignal  RISKREJECT_HITS=$riskReject")
  $lines.Add("INIT_TIMES($($initList.Count))=" + ($initList -join ','))
  $lines.Add("DEINIT_TIMES($($deinitList.Count))=" + ($deinitList -join ','))
  $lines.Add("--- ALL OPENS (time|symbol) ---")
  foreach ($o in ($opens | Sort-Object)) { $sp=$o-split '\|'; $lines.Add("   $($sp[0])  [$($sp[1])]") }
  $lines.Add("--- OPENS PER SYMBOL ---")
  $sg = @{}
  foreach ($o in $opens) { $sp=$o-split '\|'; $s=$sp[1]; if(-not $sg.ContainsKey($s)){$sg[$s]=0} $sg[$s]++ }
  foreach ($k in $sg.Keys) { $lines.Add("   $k = $($sg[$k])") }
  $lines.Add("--- NOSIGNAL SAMPLES ---")
  foreach ($s in $noSignalSamples) { $lines.Add("   $s") }
  $lines.Add("--- RISKREJECT SAMPLES ---")
  foreach ($s in $riskRejectSamples) { $lines.Add("   $s") }
  Set-Content -Encoding ASCII $out $lines
  "DONE" | Set-Content -Encoding ASCII "D:\TraeProjects\metatrader-multistrategy-ea\_mk_done.txt"
} catch {
  "ERROR: $($_.Exception.Message)" | Set-Content -Encoding ASCII "D:\TraeProjects\metatrader-multistrategy-ea\_analyze_err.txt"
}
