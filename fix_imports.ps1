# Fix Import Paths Script
$files = Get-ChildItem -Path "." -Include *.mqh,*.mq5 -Recurse

$replacements = @{
    'include "Core\\Enums.mqh"' = 'include "Core\Utils\Enums.mqh"'
    'include "Core\\ErrorHandling.mqh"' = 'include "Core\Utils\ErrorHandling.mqh"'
    'include "Core\\DataTypes.mqh"' = 'include "Core\Utils\DataTypes.mqh"'
    'include "Core\\Instruments.mqh"' = 'include "Core\Utils\Instruments.mqh"'
    'include "Core\\SymbolContext.mqh"' = 'include "Core\Utils\SymbolContext.mqh"'
    'include "Core\\SessionManager.mqh"' = 'include "Core\Utils\SessionManager.mqh"'
    'include "Core\\ModeManager.mqh"' = 'include "Core\Utils\ModeManager.mqh"'
    'include "Core\\ResourceManager.mqh"' = 'include "Core\Utils\ResourceManager.mqh"'
    
    'include "Core\\AIEngine.mqh"' = 'include "Core\Engines\AIEngine.mqh"'
    'include "Core\\TradingEngine.mqh"' = 'include "Core\Engines\TradingEngine.mqh"'
    'include "Core\\ConfluenceEngine.mqh"' = 'include "Core\Engines\ConfluenceEngine.mqh"'
    'include "Core\\MarketAnalysis.mqh"' = 'include "Core\Engines\MarketAnalysis.mqh"'
    
    'include "Core\\AIPerformanceFeedback.mqh"' = 'include "Core\AI\AIPerformanceFeedback.mqh"'
    'include "Core\\AIStrategyOrchestrator.mqh"' = 'include "Core\AI\AIStrategyOrchestrator.mqh"'
    'include "Core\\EnhancedEnsembleVotingSystem.mqh"' = 'include "Core\AI\EnhancedEnsembleVotingSystem.mqh"'
    
    'include "Core\\AdaptiveRiskManager.mqh"' = 'include "Core\Risk\AdaptiveRiskManager.mqh"'
    'include "Core\\EnhancedRiskManager.mqh"' = 'include "Core\Risk\EnhancedRiskManager.mqh"'
    'include "Core\\RiskValidationGate.mqh"' = 'include "Core\Risk\RiskValidationGate.mqh"'
    'include "Core\\PortfolioRiskManager.mqh"' = 'include "Core\Risk\PortfolioRiskManager.mqh"'
    'include "Core\\PositionSizer.mqh"' = 'include "Core\Risk\PositionSizer.mqh"'
    'include "Core\\SafetyLayer.mqh"' = 'include "Core\Risk\SafetyLayer.mqh"'
    
    'include "Core\\StrategyBase.mqh"' = 'include "Core\Strategy\StrategyBase.mqh"'
    'include "Core\\StrategyManager.mqh"' = 'include "Core\Strategy\StrategyManager.mqh"'
    'include "Core\\StrategyFactory.mqh"' = 'include "Core\Strategy\StrategyFactory.mqh"'
    'include "Core\\StrategyWrapper.mqh"' = 'include "Core\Strategy\StrategyWrapper.mqh"'
    'include "Core\\PerformanceBasedStrategyAdapter.mqh"' = 'include "Core\Strategy\PerformanceBasedStrategyAdapter.mqh"'
    
    'include "Core\\MarketRegimeDetector.mqh"' = 'include "Core\Market\MarketRegimeDetector.mqh"'
    'include "Core\\CrashBoomSpikeDetector.mqh"' = 'include "Core\Market\CrashBoomSpikeDetector.mqh"'
    'include "Core\\StepIndexLevelBreaker.mqh"' = 'include "Core\Market\StepIndexLevelBreaker.mqh"'
    'include "Core\\VolatilityIndexOptimizer.mqh"' = 'include "Core\Market\VolatilityIndexOptimizer.mqh"'
    
    'include "Core\\PerformanceAnalytics.mqh"' = 'include "Core\Monitoring\PerformanceAnalytics.mqh"'
    'include "Core\\SystemHealthMonitor.mqh"' = 'include "Core\Monitoring\SystemHealthMonitor.mqh"'
    
    'include "Core\\Trade.mqh"' = 'include "Core\Trading\Trade.mqh"'
    'include "Core\\TradeManager.mqh"' = 'include "Core\Trading\TradeManager.mqh"'
    'include "Core\\PositionInfo.mqh"' = 'include "Core\Trading\PositionInfo.mqh"'
    'include "Core\\OrderInfo.mqh"' = 'include "Core\Trading\OrderInfo.mqh"'
    'include "Core\\HistoryOrderInfo.mqh"' = 'include "Core\Trading\HistoryOrderInfo.mqh"'
    'include "Core\\DealInfo.mqh"' = 'include "Core\Trading\DealInfo.mqh"'
    'include "Core\\ProgressiveTakeProfit.mqh"' = 'include "Core\Trading\ProgressiveTakeProfit.mqh"'
    'include "Core\\TPManagerEntry.mqh"' = 'include "Core\Trading\TPManagerEntry.mqh"'
    
    'include "Core\\SignalDiagnostics.mqh"' = 'include "Core\Signals\SignalDiagnostics.mqh"'
    'include "Core\\TimeframeConsistency.mqh"' = 'include "Core\Signals\TimeframeConsistency.mqh"'
    'include "Core\\HedgingProtection.mqh"' = 'include "Core\Signals\HedgingProtection.mqh"'
    
    'include "Core\\BrokerConnectionManager.mqh"' = 'include "Core\Connectivity\BrokerConnectionManager.mqh"'
    'include "Core\\IntegrationHub.mqh"' = 'include "Core\Connectivity\IntegrationHub.mqh"'
    'include "Core\\HTTPClient.mqh"' = 'include "Core\Connectivity\HTTPClient.mqh"'
    'include "Core\\DerivManager.mqh"' = 'include "Core\Connectivity\DerivManager.mqh"'
}

Write-Host "Fixing import paths in all files..."

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

Write-Host "Import path fixing complete!"
