# Simple fix for Core files
$files = Get-ChildItem -Path "Core" -Include *.mqh -Recurse -File

Write-Host "Found $($files.Count) Core files"

foreach($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $original = $content
    
    # Fix relative includes
    $content = $content -replace '#include "Enums\.mqh"', '#include "../Utils/Enums.mqh"'
    $content = $content -replace '#include "ErrorHandling\.mqh"', '#include "../Utils/ErrorHandling.mqh"'
    $content = $content -replace '#include "StrategyBase\.mqh"', '#include "../Strategy/StrategyBase.mqh"'
    $content = $content -replace '#include "TradeManager\.mqh"', '#include "../Trading/TradeManager.mqh"'
    $content = $content -replace '#include "SignalDiagnostics\.mqh"', '#include "../Signals/SignalDiagnostics.mqh"'
    $content = $content -replace '#include "TimeframeConsistency\.mqh"', '#include "../Signals/TimeframeConsistency.mqh"'
    $content = $content -replace '#include "PerformanceAnalytics\.mqh"', '#include "../Monitoring/PerformanceAnalytics.mqh"'
    $content = $content -replace '#include "AIStrategyOrchestrator\.mqh"', '#include "../AI/AIStrategyOrchestrator.mqh"'
    
    if($content -ne $original) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Fixed: $($file.Name)"
    }
}

Write-Host "Done!"
