# Fix all Core files internal references
$coreFolders = @("Core\AI", "Core\Engines", "Core\Risk", "Core\Strategy", "Core\Market", 
                 "Core\Monitoring", "Core\Trading", "Core\Signals", "Core\Connectivity", "Core\Utils",
                 "Core\Pipeline", "Core\Management")

$files = @()
foreach($folder in $coreFolders) {
    $files += Get-ChildItem -Path $folder -Include *.mqh -File -ErrorAction SilentlyContinue
}

Write-Host "Found $($files.Count) files to process"

$replacements = @{
    '"Enums.mqh"' = '"../Utils/Enums.mqh"'
    '"DataTypes.mqh"' = '"../Utils/DataTypes.mqh"'
    '"ErrorHandling.mqh"' = '"../Utils/ErrorHandling.mqh"'
    '"Instruments.mqh"' = '"../Utils/Instruments.mqh"'
    '"SymbolContext.mqh"' = '"../Utils/SymbolContext.mqh"'
    '"SessionManager.mqh"' = '"../Utils/SessionManager.mqh"'
    '"ModeManager.mqh"' = '"../Utils/ModeManager.mqh"'
    '"ResourceManager.mqh"' = '"../Utils/ResourceManager.mqh"'
    '"File.mqh"' = '"../Utils/File.mqh"'
    '"FileTxt.mqh"' = '"../Utils/FileTxt.mqh"'
    
    '"AIEngine.mqh"' = '"../Engines/AIEngine.mqh"'
    '"TradingEngine.mqh"' = '"../Engines/TradingEngine.mqh"'
    '"ConfluenceEngine.mqh"' = '"../Engines/ConfluenceEngine.mqh"'
    '"MarketAnalysis.mqh"' = '"../Engines/MarketAnalysis.mqh"'
    '"StructureEngine.mqh"' = '"../Engines/StructureEngine.mqh"'
    '"TrendEngine.mqh"' = '"../Engines/TrendEngine.mqh"'
    '"LiquidityEngine.mqh"' = '"../Engines/LiquidityEngine.mqh"'
    '"VolatilityEngine.mqh"' = '"../Engines/VolatilityEngine.mqh"'
    
    '"AIPerformanceFeedback.mqh"' = '"../AI/AIPerformanceFeedback.mqh"'
    '"AIStrategyOrchestrator.mqh"' = '"../AI/AIStrategyOrchestrator.mqh"'
    '"EnhancedEnsembleVotingSystem.mqh"' = '"../AI/EnhancedEnsembleVotingSystem.mqh"'
    
    '"AdaptiveRiskManager.mqh"' = '"../Risk/AdaptiveRiskManager.mqh"'
    '"EnhancedRiskManager.mqh"' = '"../Risk/EnhancedRiskManager.mqh"'
    '"RiskValidationGate.mqh"' = '"../Risk/RiskValidationGate.mqh"'
    '"PortfolioRiskManager.mqh"' = '"../Risk/PortfolioRiskManager.mqh"'
    '"PositionSizer.mqh"' = '"../Risk/PositionSizer.mqh"'
    '"SafetyLayer.mqh"' = '"../Risk/SafetyLayer.mqh"'
    
    '"StrategyBase.mqh"' = '"../Strategy/StrategyBase.mqh"'
    '"StrategyManager.mqh"' = '"../Strategy/StrategyManager.mqh"'
    '"StrategyFactory.mqh"' = '"../Strategy/StrategyFactory.mqh"'
    '"StrategyWrapper.mqh"' = '"../Strategy/StrategyWrapper.mqh"'
    '"StrategyFunctions.mqh"' = '"../Strategy/StrategyFunctions.mqh"'
    '"MarketConditionStrategySelector.mqh"' = '"../Strategy/MarketConditionStrategySelector.mqh"'
    '"PerformanceBasedStrategyAdapter.mqh"' = '"../Strategy/PerformanceBasedStrategyAdapter.mqh"'
    
    '"MarketRegimeDetector.mqh"' = '"../Market/MarketRegimeDetector.mqh"'
    '"CrashBoomSpikeDetector.mqh"' = '"../Market/CrashBoomSpikeDetector.mqh"'
    '"StepIndexLevelBreaker.mqh"' = '"../Market/StepIndexLevelBreaker.mqh"'
    '"VolatilityIndexOptimizer.mqh"' = '"../Market/VolatilityIndexOptimizer.mqh"'
    '"SyntheticIndexHealthMonitor.mqh"' = '"../Market/SyntheticIndexHealthMonitor.mqh"'
    '"SymbolDiversificationOptimizer.mqh"' = '"../Market/SymbolDiversificationOptimizer.mqh"'
    
    '"PerformanceAnalytics.mqh"' = '"../Monitoring/PerformanceAnalytics.mqh"'
    '"SystemHealthMonitor.mqh"' = '"../Monitoring/SystemHealthMonitor.mqh"'
    
    '"Trade.mqh"' = '"../Trading/Trade.mqh"'
    '"TradeManager.mqh"' = '"../Trading/TradeManager.mqh"'
    '"PositionInfo.mqh"' = '"../Trading/PositionInfo.mqh"'
    '"OrderInfo.mqh"' = '"../Trading/OrderInfo.mqh"'
    '"HistoryOrderInfo.mqh"' = '"../Trading/HistoryOrderInfo.mqh"'
    '"DealInfo.mqh"' = '"../Trading/DealInfo.mqh"'
    '"ProgressiveTakeProfit.mqh"' = '"../Trading/ProgressiveTakeProfit.mqh"'
    '"TPManagerEntry.mqh"' = '"../Trading/TPManagerEntry.mqh"'
    
    '"SignalDiagnostics.mqh"' = '"../Signals/SignalDiagnostics.mqh"'
    '"TimeframeConsistency.mqh"' = '"../Signals/TimeframeConsistency.mqh"'
    '"HedgingProtection.mqh"' = '"../Signals/HedgingProtection.mqh"'
    
    '"BrokerConnectionManager.mqh"' = '"../Connectivity/BrokerConnectionManager.mqh"'
    '"IntegrationHub.mqh"' = '"../Connectivity/IntegrationHub.mqh"'
    '"HTTPClient.mqh"' = '"../Connectivity/HTTPClient.mqh"'
    '"DerivManager.mqh"' = '"../Connectivity/DerivManager.mqh"'
}

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
        Write-Host "Fixed: $($file.Name) in $($file.Directory.Name)"
    }
}

Write-Host "Core internal import fixing complete!"
