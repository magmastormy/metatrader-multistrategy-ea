# Final comprehensive path fix
Write-Host "Applying final path fixes..." -ForegroundColor Green

# Get all .mqh files
$files = Get-ChildItem -Recurse -Filter "*.mqh" | Where-Object { $_.FullName -notmatch "\\Include\\" }

foreach($f in $files) {
    $content = Get-Content $f.FullName -Raw
    $originalContent = $content
    
    # Fix 1: Core/Interfaces/IStrategy.mqh -> Interfaces/IStrategy.mqh (or ../../Interfaces/IStrategy.mqh)
    $content = $content -replace '#include\s+"[^"]*Core/Interfaces/IStrategy\.mqh"', '#include "../../Interfaces/IStrategy.mqh"'
    $content = $content -replace '#include\s+"[^"]*Core\\Interfaces\\IStrategy\.mqh"', '#include "../../Interfaces/IStrategy.mqh"'
    
    # Fix 2: Core/AI/HedgingProtection.mqh -> Core/Signals/HedgingProtection.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/AI/HedgingProtection\.mqh"', '#include "$1Core/Signals/HedgingProtection.mqh"'
    
    # Fix 3: Core/Trading/PositionSizer.mqh -> Core/Risk/PositionSizer.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/Trading/PositionSizer\.mqh"', '#include "$1Core/Risk/PositionSizer.mqh"'
    
    # Fix 4: Remove Core/Trading/PortfolioRiskManager.mqh (doesn't exist)
    $content = $content -replace '#include\s+"[^"]*Core/Trading/PortfolioRiskManager\.mqh".*\r?\n', ''
    
    # Fix 5: Core/Trading/MarketAnalysis.mqh -> Core/Market/MarketAnalysis.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/Trading/MarketAnalysis\.mqh"', '#include "$1Core/Market/MarketAnalysis.mqh"'
    
    # Fix 6: Core/AIModules/* -> AIModules/*
    $content = $content -replace '#include\s+"([^"]*?)Core/AIModules/', '#include "$1../AIModules/'
    
    # Fix 7: Core/Utilities/Utilities.mqh -> Utilities/Utilities.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/Utilities/Utilities\.mqh"', '#include "$1../Utilities/Utilities.mqh"'
    
    # Fix 8: Core/Strategy/PositionSizer.mqh -> Core/Risk/PositionSizer.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/Strategy/PositionSizer\.mqh"', '#include "$1Core/Risk/PositionSizer.mqh"'
    
    # Fix 9: Core/StepIndexLevelBreaker.mqh -> Core/Market/StepIndexLevelBreaker.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/StepIndexLevelBreaker\.mqh"', '#include "$1Core/Market/StepIndexLevelBreaker.mqh"'
    
    # Fix 10: Core/ErrorHandling.mqh -> Core/Utils/ErrorHandling.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/ErrorHandling\.mqh"', '#include "$1Core/Utils/ErrorHandling.mqh"'
    
    # Fix 11: Core/Utils/MarketAnalysis.mqh -> Core/Market/MarketAnalysis.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/Utils/MarketAnalysis\.mqh"', '#include "$1Core/Market/MarketAnalysis.mqh"'
    
    # Fix 12: Core/TradeManager.mqh -> Core/Trading/TradeManager.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/TradeManager\.mqh"', '#include "$1Core/Trading/TradeManager.mqh"'
    
    # Fix 13: Core/PositionSizer.mqh -> Core/Risk/PositionSizer.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/PositionSizer\.mqh"', '#include "$1Core/Risk/PositionSizer.mqh"'
    
    # Fix 14: Core/StrategyFactory.mqh -> Core/Strategy/StrategyFactory.mqh
    $content = $content -replace '#include\s+"([^"]*?)Core/StrategyFactory\.mqh"', '#include "$1Core/Strategy/StrategyFactory.mqh"'
    
    # Save if changed
    if($content -ne $originalContent) {
        Set-Content $f.FullName -Value $content -NoNewline
        Write-Host "Fixed paths in $($f.Name)" -ForegroundColor Cyan
    }
}

Write-Host "`nAll paths fixed!" -ForegroundColor Green
