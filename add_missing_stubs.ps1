# Add missing method stubs to fix compilation errors
Write-Host "Adding missing method implementations..."

# 1. Add TrendEngine methods
$file = "Core\Engines\TrendEngine.mqh"
$content = Get-Content $file -Raw

$methods = @"

//+------------------------------------------------------------------+
//| Analyze Trend (Public wrapper)                                  |
//+------------------------------------------------------------------+
TrendState CTrendEngine::AnalyzeTrend(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    double ma_fast[3], ma_medium[3], ma_slow[3], ma[3];
    return CalculateMAs(symbol, timeframe, ma_fast, ma_medium, ma_slow, ma);
}

//+------------------------------------------------------------------+
//| Calculate Trend Strength (Public wrapper)                       |
//+------------------------------------------------------------------+
double CTrendEngine::CalculateTrendStrength(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    double ma_fast[3], ma_medium[3], ma_slow[3];
    int handleFast = iMA(symbol, timeframe, 20, 0, MODE_SMA, PRICE_CLOSE);
    int handleMedium = iMA(symbol, timeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
    int handleSlow = iMA(symbol, timeframe, 200, 0, MODE_SMA, PRICE_CLOSE);
    
    if(CopyBuffer(handleFast, 0, 0, 3, ma_fast) != 3) return 0;
    if(CopyBuffer(handleMedium, 0, 0, 3, ma_medium) != 3) return 0;
    if(CopyBuffer(handleSlow, 0, 0, 3, ma_slow) != 3) return 0;
    
    return GetTrendStrength(ma_fast, ma_medium, ma_slow);
}

//+------------------------------------------------------------------+
//| Calculate Trend Angle (Public wrapper)                          |
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
    $content = $content.Insert($endifPos, $methods + "`r`n")
    Set-Content $file -Value $content -NoNewline
    Write-Host "Added methods to TrendEngine"
}

# 2. Add GetSignalValueInternal to StrategySMC
$file = "Strategies\StrategySMC.mqh"
$content = Get-Content $file -Raw

$method = @"

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
    $content = $content.Insert($endifPos, $method + "`r`n")
    Set-Content $file -Value $content -NoNewline
    Write-Host "Added GetSignalValueInternal to StrategySMC"
}

Write-Host "Method stubs added successfully!"
