# Final comprehensive fix for all remaining errors
Write-Host "Applying final fixes..."

# 1. Add missing method declarations to TrendEngine class
$file = "Core\Engines\TrendEngine.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    # Find the public section and add missing methods
    $publicSection = "public:`r`n    // Constructor/Destructor"
    $newMethods = @"
public:
    // Constructor/Destructor
    
    // Public wrapper methods
    TrendState AnalyzeTrend(const string symbol, ENUM_TIMEFRAMES timeframe);
    double CalculateTrendStrength(const string symbol, ENUM_TIMEFRAMES timeframe);
    double CalculateTrendAngle(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Constructor/Destructor
"@
    
    $content = $content -replace [regex]::Escape($publicSection), $newMethods
    Set-Content $file -Value $content -NoNewline
    Write-Host "Added method declarations to TrendEngine"
}

# 2. Add missing method declarations to SignalDiagnostics
$file = "Core\Signals\SignalDiagnostics.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    # Add missing method declarations
    $searchPattern = "void LogStrategyError\(const string strategyName,"
    if($content -match $searchPattern) {
        $insertAfter = "void LogStrategyError(const string strategyName,`r`n                         const string errorType,`r`n                         const string details);"
        $newDecls = @"
void LogStrategyError(const string strategyName,
                         const string errorType,
                         const string details);
                         
    void LogOrchestrationDecision(const string &selectedStrategies[], 
                                  const double &weights[],
                                  const int count,
                                  const ENUM_TRADE_SIGNAL finalSignal,
                                  const double confidence,
                                  const string reason);
                                  
    void LogHedgingPrevented(const string strategy,
                            ENUM_TRADE_SIGNAL attemptedSignal,
                            const string reason);
"@
        $content = $content -replace [regex]::Escape($insertAfter), $newDecls
        Set-Content $file -Value $content -NoNewline
        Write-Host "Added method declarations to SignalDiagnostics"
    }
}

# 3. Add missing method to StrategySMC class
$file = "Strategies\StrategySMC.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    # Add method declaration in class
    if($content -match "class CStrategySMC") {
        # Find protected or private section
        $searchPattern = "protected:"
        if($content -match $searchPattern) {
            $insertAfter = "protected:`r`n    // Internal methods"
            $newDecl = "protected:`r`n    // Internal methods`r`n    double GetSignalValueInternal() const;"
            $content = $content -replace [regex]::Escape($insertAfter), $newDecl
        }
    }
    
    # Add implementation
    $endClass = "// End of class"
    $impl = @"

//+------------------------------------------------------------------+
//| Get Signal Value Internal                                       |
//+------------------------------------------------------------------+
double CStrategySMC::GetSignalValueInternal() const
{
    return m_lastSignalStrength;
}

// End of class
"@
    if($content -match "#endif") {
        $content = $content -replace "#endif", $impl + "`r`n#endif"
        Set-Content $file -Value $content -NoNewline
        Write-Host "Added GetSignalValueInternal to StrategySMC"
    }
}

Write-Host "Final fixes complete!"
