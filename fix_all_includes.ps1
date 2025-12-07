# Comprehensive include path fix script
Write-Host "Fixing all include paths..." -ForegroundColor Green

# 1. Fix TradingEngine.mqh - strategies are in Strategies/ not Core/Strategies/
$file = "Core\Engines\TradingEngine.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Strategies\/', '#include "../../Strategies/'
    $content = $content -replace '#include\s+"\.\.\/\.\.\/Core\/Strategies\/', '#include "../../Strategies/'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed TradingEngine.mqh"
}

# 2. Fix all files looking for Core/Enums.mqh -> Core/Utils/Enums.mqh
$files = Get-ChildItem -Recurse -Filter "*.mqh" | Where-Object { $_.FullName -notmatch "\\Include\\" }
foreach($f in $files) {
    $content = Get-Content $f.FullName -Raw
    $changed = $false
    
    if($content -match '#include\s+".*Core/Enums\.mqh"') {
        $content = $content -replace '#include\s+"([^"]*?)Core/Enums\.mqh"', '#include "$1Core/Utils/Enums.mqh"'
        $changed = $true
    }
    
    if($content -match '#include\s+".*Core\\Enums\.mqh"') {
        $content = $content -replace '#include\s+"([^"]*?)Core\\Enums\.mqh"', '#include "$1Core/Utils/Enums.mqh"'
        $changed = $true
    }
    
    if($changed) {
        Set-Content $f.FullName -Value $content -NoNewline
        Write-Host "Fixed Core/Enums.mqh path in $($f.Name)"
    }
}

# 3. Fix all files looking for Core/SignalDiagnostics.mqh -> Core/Signals/SignalDiagnostics.mqh
foreach($f in $files) {
    $content = Get-Content $f.FullName -Raw
    $changed = $false
    
    if($content -match '#include\s+".*Core/SignalDiagnostics\.mqh"') {
        $content = $content -replace '#include\s+"([^"]*?)Core/SignalDiagnostics\.mqh"', '#include "$1Core/Signals/SignalDiagnostics.mqh"'
        $changed = $true
    }
    
    if($content -match '#include\s+".*Core\\SignalDiagnostics\.mqh"') {
        $content = $content -replace '#include\s+"([^"]*?)Core\\SignalDiagnostics\.mqh"', '#include "$1Core/Signals/SignalDiagnostics.mqh"'
        $changed = $true
    }
    
    if($changed) {
        Set-Content $f.FullName -Value $content -NoNewline
        Write-Host "Fixed Core/SignalDiagnostics.mqh path in $($f.Name)"
    }
}

# 4. Fix StrategyWrapper.mqh - IStrategy is at Interfaces/ not Core/Interfaces/
$file = "Core\Strategy\StrategyWrapper.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"\.\.\/Interfaces\/IStrategy\.mqh"', '#include "../../Interfaces/IStrategy.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed StrategyWrapper.mqh"
}

# 5. Fix MultiStrategySelection.mqh
$file = "MultiStrategySelection.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    $content = $content -replace '#include\s+"Core/Enums\.mqh"', '#include "Core/Utils/Enums.mqh"'
    $content = $content -replace '#include\s+"Core/StrategyBase\.mqh"', '#include "Core/Strategy/StrategyBase.mqh"'
    $content = $content -replace '#include\s+"Core/StrategyManager\.mqh"', '#include "Core/Strategy/StrategyManager.mqh"'
    $content = $content -replace '#include\s+"Core/AIEngine\.mqh"', '#include "Core/AI/AIEngine.mqh"'
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed MultiStrategySelection.mqh"
}

# 6. Delete or fix MarketRegimeDetector references
$files = Get-ChildItem -Recurse -Filter "*.mqh" | Where-Object { $_.FullName -notmatch "\\Include\\" }
foreach($f in $files) {
    $content = Get-Content $f.FullName -Raw
    if($content -match '#include\s+".*MarketRegimeDetector\.mqh"') {
        $content = $content -replace '#include\s+"[^"]*MarketRegimeDetector\.mqh".*\r?\n', ''
        Set-Content $f.FullName -Value $content -NoNewline
        Write-Host "Removed MarketRegimeDetector.mqh from $($f.Name)"
    }
}

Write-Host "`nAll include paths fixed!" -ForegroundColor Green
