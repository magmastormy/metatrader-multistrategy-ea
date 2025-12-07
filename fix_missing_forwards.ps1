# Fix missing forward declarations
$files = Get-ChildItem -Path "Core" -Include *.mqh -Recurse -File

foreach($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $original = $content
    
    # Add forward declarations at the top after #include section
    $forwardDecls = @(
        "// Forward declarations",
        "class CEnhancedErrorHandler;",
        "class CUtilities;",
        "class CHedgingProtection;",
        "class CMarketAnalysis;",
        "class CModeManager;",
        "class CNextGenStrategyBrain;",
        "class CTransformerBrain;",
        "class SPredictionWithUncertainty;",
        "class CPositionSizer;",
        "class CStrategyManager;",
        "class CTradeManager;",
        "class CPerformanceAnalytics;",
        "class CAIStrategyOrchestrator;",
        "",
        ""
    )
    
    # Insert forward declarations after includes
    $includeEnd = $content.LastIndexOf("#include")
    if($includeEnd -gt -1) {
        $nextLine = $content.IndexOf("`n", $includeEnd)
        if($nextLine -gt -1) {
            $content = $content.Insert($nextLine + 1, "`r`n" + ($forwardDecls -join "`r`n"))
        }
    }
    
    if($content -ne $original) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Added forwards to: $($file.Name)"
    }
}

Write-Host "Forward declarations added!"
