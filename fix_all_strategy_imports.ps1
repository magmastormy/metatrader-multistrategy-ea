# Fix all Strategy files imports
$files = Get-ChildItem -Path "Strategies" -Include *.mqh -Recurse

$replacements = @{
    '../Core/StrategyBase.mqh' = '../Core/Strategy/StrategyBase.mqh'
    '../Core/ConfluenceEngine.mqh' = '../Core/Engines/ConfluenceEngine.mqh'
    '../Core/SignalDiagnostics.mqh' = '../Core/Signals/SignalDiagnostics.mqh'
    '../Core/TimeframeConsistency.mqh' = '../Core/Signals/TimeframeConsistency.mqh'
    '../Core/HedgingProtection.mqh' = '../Core/Signals/HedgingProtection.mqh'
    '../Core/MarketRegimeDetector.mqh' = '../Core/Market/MarketRegimeDetector.mqh'
    '../Core/ErrorHandling.mqh' = '../Core/Utils/ErrorHandling.mqh'
    '../Core/Enums.mqh' = '../Core/Utils/Enums.mqh'
    '../Core/OrderInfo.mqh' = '../Core/Trading/OrderInfo.mqh'
    '../Core/HistoryOrderInfo.mqh' = '../Core/Trading/HistoryOrderInfo.mqh'
    '../Core/PositionInfo.mqh' = '../Core/Trading/PositionInfo.mqh'
    '../Core/DealInfo.mqh' = '../Core/Trading/DealInfo.mqh'
    '../Core/Trade.mqh' = '../Core/Trading/Trade.mqh'
}

Write-Host "Fixing Strategy import paths..."

foreach($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $modified = $false
    
    foreach($old in $replacements.Keys) {
        $new = $replacements[$old]
        if($content -match [regex]::Escape($old)) {
            $content = $content -replace [regex]::Escape($old), $new
            $modified = $true
        }
    }
    
    if($modified) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Fixed: $($file.Name)"
    }
}

Write-Host "Strategy import fixing complete!"
