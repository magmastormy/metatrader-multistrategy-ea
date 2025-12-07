# Fix the last 7 remaining errors
Write-Host "Fixing last 7 errors..." -ForegroundColor Green

# 1. Fix TradeManager.mqh
$file = "Core\Trading\TradeManager.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    # Already fixed earlier, but make sure
    $content = $content -replace '#include\s+"\.\.\/Trading\/PositionSizer\.mqh"', '#include "../Risk/PositionSizer.mqh"'
    $content = $content -replace '#include\s+"\.\.\/Trading\/PortfolioRiskManager\.mqh".*\r?\n', ''
    $content = $content -replace '#include\s+"\.\.\/Trading\/MarketAnalysis\.mqh"', '#include "../Market/MarketAnalysis.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed TradeManager.mqh"
}

# 2. Fix CrashBoomSpikeDetector.mqh
$file = "Core\Market\CrashBoomSpikeDetector.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Utilities\/Utilities\.mqh"', '#include "../../Utilities/Utilities.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed CrashBoomSpikeDetector.mqh"
}

# 3. Fix StepIndexLevelBreaker.mqh
$file = "Core\Market\StepIndexLevelBreaker.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Utilities\/Utilities\.mqh"', '#include "../../Utilities/Utilities.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed StepIndexLevelBreaker.mqh"
}

# 4. Fix StrategyBase.mqh
$file = "Core\Strategy\StrategyBase.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Strategy\/PositionSizer\.mqh"', '#include "../Risk/PositionSizer.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed StrategyBase.mqh"
}

# 5. Fix SymbolContext.mqh
$file = "Core\Utils\SymbolContext.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Utils\/MarketAnalysis\.mqh"', '#include "../Market/MarketAnalysis.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed SymbolContext.mqh"
}

Write-Host "`nAll 7 errors fixed!" -ForegroundColor Green
