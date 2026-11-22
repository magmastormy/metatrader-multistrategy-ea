param(
    [Parameter(Mandatory=$true)][ValidateSet('baseline','candidate')][string]$Arm,
    [Parameter(Mandatory=$true)][ValidateSet('w1','w2','w3','w4b','w5')][string]$Window,
    [Parameter(Mandatory=$true)][string]$RunTag
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$runRoot = $PSScriptRoot
$testerLogDir = Join-Path $env:APPDATA 'MetaQuotes\Terminal\FB9A56D617EDDDFE29EE54EBEFFE96C1\Tester\logs'
$runner = Join-Path $repoRoot 'Tools\run_window.ps1'
$configName = 'intent_trace_' + $RunTag + '_' + $Arm + '_' + $Window + '.ini'
$config = Join-Path $runRoot ('configs\' + $configName)
$outputDir = Join-Path $runRoot $Arm
$prefix = $Arm + '_' + $Window
$journalPath = Join-Path $outputDir ($prefix + '.journal.log')
$tracePath = Join-Path $outputDir ($prefix + '.intent.log')
$runnerPath = Join-Path $outputDir ($prefix + '.runner.log')
$resultPath = Join-Path $outputDir ($prefix + '.result.json')
foreach($path in @($journalPath,$tracePath,$runnerPath,$resultPath)) {
    if(Test-Path -LiteralPath $path) { throw "Refusing to overwrite run artifact: $path" }
}
if(-not (Test-Path -LiteralPath $config)) { throw "Missing tester config: $config" }
if(Get-Process terminal64,metatester64 -ErrorAction SilentlyContinue) { throw 'A MetaTrader process is already running; refusing overlapping tester runs' }

$before = @{}
Get-ChildItem -LiteralPath $testerLogDir -Filter '*.log' -File | ForEach-Object { $before[$_.FullName] = [int64]$_.Length }
$startedAt = (Get-Date).ToString('o')
Write-Output "START $Arm $Window using $config"
$runnerOutput = @()
$status = 'valid'
$errorMessage = ''
try {
    $runnerOutput = @(& $runner -IniPath $config -TimeoutSec 3600 -Cold 2>&1)
} catch {
    $status = 'failed'
    $errorMessage = $_.Exception.Message
    $runnerOutput += 'RUNNER_ERROR: ' + $errorMessage
}

$journalParts = [System.Collections.Generic.List[string]]::new()
$logFiles = [System.Collections.Generic.List[string]]::new()
foreach($file in (Get-ChildItem -LiteralPath $testerLogDir -Filter '*.log' -File | Sort-Object Name)) {
    $from = [int64]0
    if($before.ContainsKey($file.FullName) -and $file.Length -ge $before[$file.FullName]) { $from = $before[$file.FullName] }
    if($file.Length -le $from) { continue }
    $stream = [IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $to = [int64]$stream.Length
        if($from -ge $to) { continue }
        $stream.Position = $from
        $buffer = New-Object byte[] ([int]($to - $from))
        $read = 0
        while($read -lt $buffer.Length) {
            $count = $stream.Read($buffer,$read,$buffer.Length - $read)
            if($count -le 0) { break }
            $read += $count
        }
        if($read -lt $buffer.Length) {
            if($read -eq 0) { $buffer = [byte[]]@() } else { $buffer = $buffer[0..($read - 1)] }
        }
        $segment = [Text.Encoding]::Unicode.GetString($buffer)
        [void]$journalParts.Add(('=== ' + $file.Name + ' bytes ' + $from + '..' + $to + ' ===' + [Environment]::NewLine + $segment))
        [void]$logFiles.Add($file.Name)
    } finally { $stream.Close() }
}
$journal = $journalParts -join [Environment]::NewLine
$journalLines = $journal -split '\r?\n'
$traceLines = @($journalLines | Where-Object { $_ -match 'intent_id=|\bUNTRACKED\b|EXECUTION-RECEIPT|CONSENSUS-DECISION|CONSENSUS-REJECT|CONSENSUS-ADVISORY|EXECUTION-BLOCKED' })
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($journalPath,$journal,$utf8NoBom)
[IO.File]::WriteAllText($tracePath,($traceLines -join [Environment]::NewLine),$utf8NoBom)
$runnerText = $runnerOutput | Out-String -Width 500
if($errorMessage) { $runnerText += [Environment]::NewLine + 'RUNNER_ERROR: ' + $errorMessage + [Environment]::NewLine }
[IO.File]::WriteAllText($runnerPath,$runnerText,$utf8NoBom)

$equity = $runnerOutput | Where-Object { $_ -match '^equity: samples=' } | Select-Object -First 1
$fills = $runnerOutput | Where-Object { $_ -match '^fills: ' } | Select-Object -First 1
$decisions = $runnerOutput | Where-Object { $_ -match '^decisions: ' } | Select-Object -First 1
$rejects = $runnerOutput | Where-Object { $_ -match '^rejects: ' } | Select-Object -First 1
$ids = [regex]::Matches($journal,'intent_id=(.+?)(?:\s*\||$)') | ForEach-Object { $_.Groups[1].Value.Trim() } | Sort-Object -Unique
$receipts = @($journalLines | Where-Object { $_ -match 'EXECUTION-RECEIPT' })
$trackedReceipts = @($receipts | Where-Object { $_ -match 'intent_id=[^\s|]+' })
$result = [ordered]@{
    arm=$Arm
    window=$Window
    status=$status
    startedAt=$startedAt
    endedAt=(Get-Date).ToString('o')
    error=$errorMessage
    equitySummary=[string]$equity
    receiptSummary=[string]$fills
    decisionSummary=[string]$decisions
    rejectSummary=[string]$rejects
    uniqueIntentIds=@($ids).Count
    receiptLines=$receipts.Count
    receiptsWithIntentId=$trackedReceipts.Count
    journalLines=$journalLines.Count
    traceLines=$traceLines.Count
    testerLogFiles=@($logFiles)
    journalArtifact=$journalPath
    intentArtifact=$tracePath
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding utf8
Write-Output "STATUS $status | unique_intents=$($result.uniqueIntentIds) | receipts=$($result.receiptLines) | receipts_with_id=$($result.receiptsWithIntentId) | trace_lines=$($result.traceLines)"
if($equity) { Write-Output $equity }
if($fills) { Write-Output $fills }
if($decisions) { Write-Output $decisions }
if($rejects) { Write-Output $rejects }
Write-Output "ARTIFACTS $journalPath | $tracePath"
if($status -ne 'valid') { throw "Backtest did not validate: $Arm $Window" }
