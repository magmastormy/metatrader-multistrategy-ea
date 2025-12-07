# Fix remaining 100 errors
Write-Host "Fixing remaining errors..."

# 1. Add missing method stubs to TrendEngine
$file = "Core\Engines\TrendEngine.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    # Add missing method implementations before the last #endif
    $missingMethods = @"

//+------------------------------------------------------------------+
//| Analyze Trend (Wrapper method)                                  |
//+------------------------------------------------------------------+
TrendState CTrendEngine::AnalyzeTrend(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    TrendState state;
    double ma_fast[3], ma_medium[3], ma_slow[3], ma[3];
    state = CalculateMAs(symbol, timeframe, ma_fast, ma_medium, ma_slow, ma);
    return state;
}

//+------------------------------------------------------------------+
//| Calculate Trend Strength (Wrapper method)                       |
//+------------------------------------------------------------------+
double CTrendEngine::CalculateTrendStrength(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    double ma_fast[3], ma_medium[3], ma_slow[3];
    // Get MAs
    int handleFast = iMA(symbol, timeframe, 20, 0, MODE_SMA, PRICE_CLOSE);
    int handleMedium = iMA(symbol, timeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
    int handleSlow = iMA(symbol, timeframe, 200, 0, MODE_SMA, PRICE_CLOSE);
    
    if(CopyBuffer(handleFast, 0, 0, 3, ma_fast) != 3) return 0;
    if(CopyBuffer(handleMedium, 0, 0, 3, ma_medium) != 3) return 0;
    if(CopyBuffer(handleSlow, 0, 0, 3, ma_slow) != 3) return 0;
    
    return GetTrendStrength(ma_fast, ma_medium, ma_slow);
}

//+------------------------------------------------------------------+
//| Calculate Trend Angle (Wrapper method)                          |
//+------------------------------------------------------------------+
double CTrendEngine::CalculateTrendAngle(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    double ma[10];
    int handle = iMA(symbol, timeframe, 20, 0, MODE_SMA, PRICE_CLOSE);
    if(CopyBuffer(handle, 0, 0, 10, ma) != 10) return 0;
    return CalculateAngle(ma, 5);
}

"@
    
    # Insert before #endif
    $endifPos = $content.LastIndexOf("#endif")
    if($endifPos -gt -1) {
        $content = $content.Insert($endifPos, $missingMethods + "`r`n")
        Set-Content $file -Value $content -NoNewline
        Write-Host "Added missing methods to TrendEngine"
    }
}

# 2. Add missing methods to SignalDiagnostics
$file = "Core\Signals\SignalDiagnostics.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    $missingMethods = @"

//+------------------------------------------------------------------+
//| Log Orchestration Decision                                      |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogOrchestrationDecision(const string &selectedStrategies[], 
                                                  const double &weights[],
                                                  ENUM_TRADE_SIGNAL finalSignal,
                                                  double confidence,
                                                  const string reason)
{
    if(!m_enableLogging) return;
    
    string msg = StringFormat("[ORCHESTRATION] Signal: %s | Confidence: %.2f | Reason: %s",
                            EnumToString(finalSignal), confidence, reason);
    Print(msg);
}

//+------------------------------------------------------------------+
//| Log Hedging Prevented                                           |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogHedgingPrevented(const string strategy,
                                            ENUM_TRADE_SIGNAL attemptedSignal,
                                            const string reason)
{
    if(!m_enableLogging) return;
    
    string msg = StringFormat("[HEDGING] Prevented %s signal from %s | Reason: %s",
                            EnumToString(attemptedSignal), strategy, reason);
    Print(msg);
}

"@
    
    $endifPos = $content.LastIndexOf("#endif")
    if($endifPos -gt -1) {
        $content = $content.Insert($endifPos, $missingMethods + "`r`n")
        Set-Content $file -Value $content -NoNewline
        Write-Host "Added missing methods to SignalDiagnostics"
    }
}

# 3. Add missing method to StrategySMC
$file = "Strategies\StrategySMC.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    $missingMethod = @"

//+------------------------------------------------------------------+
//| Get Signal Value Internal                                       |
//+------------------------------------------------------------------+
double CStrategySMC::GetSignalValueInternal() const
{
    return m_lastSignalStrength;
}

"@
    
    $endifPos = $content.LastIndexOf("#endif")
    if($endifPos -gt -1) {
        $content = $content.Insert($endifPos, $missingMethod + "`r`n")
        Set-Content $file -Value $content -NoNewline
        Write-Host "Added missing method to StrategySMC"
    }
}

Write-Host "Remaining errors fix complete!"
