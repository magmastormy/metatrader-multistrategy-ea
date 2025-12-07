# Fix all remaining compilation errors
Write-Host "Fixing all remaining errors..."

# 1. Fix IntegrationHub.mqh - remove SPredictionWithUncertainty member
$file = "Core\Connectivity\IntegrationHub.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    $content = $content -replace "    SPredictionWithUncertainty uncertainty;[^\n]*\n", ""
    Set-Content $file -Value $content -NoNewline -Encoding UTF8
    Write-Host "Fixed IntegrationHub.mqh"
}

# 2. Fix UnifiedSignalPipeline.mqh - declare resolvedConf variable properly
$file = "Core\Pipeline\UnifiedSignalPipeline.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    # Fix the resolvedConf variable declaration
    $content = $content -replace "double resolvedConf = 0;[\r\n\s]*ENUM_TRADE_SIGNAL resolvedSignal = m_tfConsistency\.GetResolvedSignal\(resolvedConf\);", 
        "double resolvedConf = 0.0;`r`n        ENUM_TRADE_SIGNAL resolvedSignal = m_tfConsistency.GetResolvedSignal(resolvedConf);"
    
    Set-Content $file -Value $content -NoNewline
    Write-Host "Fixed UnifiedSignalPipeline.mqh"
}

# 3. Remove duplicate GetSignalValueInternal from StrategySMC
$file = "Strategies\StrategySMC.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    # Find and remove the duplicate implementation
    $pattern = "double CStrategySMC::GetSignalValueInternal\(const string symbol, const ENUM_TIMEFRAMES timeframe\)[\s\S]*?(?=\n//\+--|$)"
    if($content -match $pattern) {
        $content = $content -replace $pattern, ""
        Set-Content $file -Value $content -NoNewline
        Write-Host "Removed duplicate GetSignalValueInternal from StrategySMC"
    }
}

# 4. Delete TrendEngine duplicate method implementations that don't match declarations
$file = "Core\Engines\TrendEngine.mqh"
if(Test-Path $file) {
    $content = Get-Content $file -Raw
    
    # The AnalyzeTrend method exists at line 463 and is correct - no changes needed
    # We already removed the duplicate declarations
    
    Write-Host "TrendEngine.mqh - keeping existing implementations"
}

Write-Host "`nAll fixes applied!"
