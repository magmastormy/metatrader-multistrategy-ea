# Comprehensive fix for all remaining compilation issues
Write-Host "Starting comprehensive fix..."

# 1. Fix all array parameters in all files
$files = Get-ChildItem -Path "." -Include "*.mqh","*.mq5" -Recurse -File

$arrayFixes = @{
    '\(string strategies\[\]' = '(string &strategies[]'
    '\(string signals\[\]' = '(string &signals[]'
    '\(double weights\[\]' = '(double &weights[]'
    '\(ENUM_TRADE_SIGNAL signals\[\]' = '(ENUM_TRADE_SIGNAL &signals[]'
    '\(double confidences\[\]' = '(double &confidences[]'
    '\(ENUM_TIMEFRAMES timeframes\[\]' = '(ENUM_TIMEFRAMES &timeframes[]'
    '\(bool enabledFlags\[\]' = '(bool &enabledFlags[]'
    '\(string selectedStrategies\[\]' = '(string &selectedStrategies[]'
    '\(double ma_fast\[\]' = '(double &ma_fast[]'
    '\(double ma_medium\[\]' = '(double &ma_medium[]'
    '\(double ma_slow\[\]' = '(double &ma_slow[]'
    '\(double ma\[\]' = '(double &ma[]'
    '\(int success\[\]' = '(int &success[]'
    '\(int failures\[\]' = '(int &failures[]'
    '\(double avgConf\[\]' = '(double &avgConf[]'
}

Write-Host "Fixing array parameters in $($files.Count) files..."

foreach($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $original = $content
    
    foreach($pattern in $arrayFixes.Keys) {
        $replacement = $arrayFixes[$pattern]
        $content = $content -replace $pattern, $replacement
    }
    
    if($content -ne $original) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Fixed arrays in: $($file.Name)"
    }
}

# 2. Add common forward declarations to all Core files
$coreFiles = Get-ChildItem -Path "Core" -Include "*.mqh" -Recurse -File

$forwardDecls = @"
// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

"@

Write-Host "Adding forward declarations to $($coreFiles.Count) Core files..."

foreach($file in $coreFiles) {
    $content = Get-Content $file.FullName -Raw
    
    # Skip if already has forward declarations
    if($content -match "Forward declarations") {
        continue
    }
    
    # Find position after last #include
    $includePattern = "#include.*"
    $matches = [regex]::Matches($content, $includePattern)
    
    if($matches.Count -gt 0) {
        $lastInclude = $matches[$matches.Count - 1]
        $insertPos = $lastInclude.Index + $lastInclude.Length
        
        # Find end of line
        $lineEnd = $content.IndexOf("`n", $insertPos)
        if($lineEnd -gt -1) {
            $content = $content.Insert($lineEnd + 1, "`r`n" + $forwardDecls)
            Set-Content -Path $file.FullName -Value $content -NoNewline
            Write-Host "Added forwards to: $($file.Name)"
        }
    }
}

Write-Host "Comprehensive fix complete!"
