# Fix files with encoding issues
Write-Host "Fixing encoding and path issues..." -ForegroundColor Green

# Fix AIStrategyOrchestrator.mqh
$file = "Core\AI\AIStrategyOrchestrator.mqh"
if(Test-Path $file) {
    try {
        $content = Get-Content $file -Raw -Encoding UTF8
        $content = $content -replace '#include\s+"\.\.\/Interfaces\/IStrategy\.mqh"', '#include "../../Interfaces/IStrategy.mqh"'
        $content = $content -replace '#include\s+"HedgingProtection\.mqh"', '#include "../Signals/HedgingProtection.mqh"'
        Set-Content $file -Value $content -NoNewline -Encoding UTF8
        Write-Host "Fixed AIStrategyOrchestrator.mqh"
    } catch {
        Write-Host "Error fixing AIStrategyOrchestrator.mqh: $_" -ForegroundColor Red
    }
}

# Fix StrategyManager.mqh
$file = "Core\Strategy\StrategyManager.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Interfaces\/IStrategy\.mqh"', '#include "../../Interfaces/IStrategy.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed StrategyManager.mqh"
}

# Fix StrategyBase.mqh
$file = "Core\Strategy\StrategyBase.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Interfaces\/IStrategy\.mqh"', '#include "../../Interfaces/IStrategy.mqh"'
    $content = $content -replace '#include\s+"\.\.\/Strategy\/PositionSizer\.mqh"', '#include "../Risk/PositionSizer.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed StrategyBase.mqh"
}

# Fix TradeManager.mqh
$file = "Core\Trading\TradeManager.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Trading\/PositionSizer\.mqh"', '#include "../Risk/PositionSizer.mqh"'
    $content = $content -replace '#include\s+"\.\.\/Trading\/PortfolioRiskManager\.mqh".*\r?\n', ''
    $content = $content -replace '#include\s+"\.\.\/Trading\/MarketAnalysis\.mqh"', '#include "../Market/MarketAnalysis.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed TradeManager.mqh"
}

# Fix IntegrationHub.mqh
$file = "Core\Connectivity\IntegrationHub.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/AIModules\/', '#include "../../AIModules/'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed IntegrationHub.mqh"
}

# Fix TradingEngine.mqh AI module includes
$file = "Core\Engines\TradingEngine.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/AIModules\/', '#include "../../AIModules/'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed TradingEngine.mqh AIModules paths"
}

Write-Host "`nAll fixes applied!" -ForegroundColor Green
