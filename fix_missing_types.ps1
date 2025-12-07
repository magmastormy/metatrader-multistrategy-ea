# Fix missing type declarations
Write-Host "Fixing missing type declarations..."

# Create a common types header
$typesHeader = @"
//+------------------------------------------------------------------+
//| Common Types and Forward Declarations                            |
//+------------------------------------------------------------------+
#ifndef COMMON_TYPES_MQH
#define COMMON_TYPES_MQH

// Forward declarations for all common classes
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;
class CResourceManager;
class CSessionManager;
class CInstrumentRegistry;
class CSymbolContext;

// Common structs
struct SPredictionWithUncertainty
{
    double prediction;
    double uncertainty;
    datetime timestamp;
    bool isValid;
};

struct SMarketState
{
    ENUM_MARKET_REGIME regime;
    double volatility;
    double trendStrength;
    bool isTrending;
    datetime lastUpdate;
};

#endif // COMMON_TYPES_MQH
"@

# Save to Core/Utils/CommonTypes.mqh
Set-Content -Path "Core\Utils\CommonTypes.mqh" -Value $typesHeader -NoNewline
Write-Host "Created CommonTypes.mqh"

# Now add this include to all Core files
$coreFiles = Get-ChildItem -Path "Core" -Include "*.mqh" -Recurse -File

foreach($file in $coreFiles) {
    $content = Get-Content $file.FullName -Raw
    
    # Skip if already includes CommonTypes
    if($content -match "CommonTypes\.mqh") {
        continue
    }
    
    # Add include after the first #include
    $firstInclude = $content.IndexOf("#include")
    if($firstInclude -gt -1) {
        $lineEnd = $content.IndexOf("`n", $firstInclude)
        if($lineEnd -gt -1) {
            $content = $content.Insert($lineEnd + 1, "`r`n#include \"CommonTypes.mqh\"`r`n")
            Set-Content -Path $file.FullName -Value $content -NoNewline
            Write-Host "Added CommonTypes to: $($file.Name)"
        }
    }
}

# Also add to main EA
$eaContent = Get-Content "MultiStrategyAutonomousEA.mq5" -Raw
if($eaContent -notmatch "CommonTypes\.mqh") {
    $firstInclude = $eaContent.IndexOf("#include")
    if($firstInclude -gt -1) {
        $lineEnd = $eaContent.IndexOf("`n", $firstInclude)
        if($lineEnd -gt -1) {
            $eaContent = $eaContent.Insert($lineEnd + 1, "`r`n#include \"Core\\Utils\\CommonTypes.mqh\"`r`n")
            Set-Content -Path "MultiStrategyAutonomousEA.mq5" -Value $eaContent -NoNewline
            Write-Host "Added CommonTypes to main EA"
        }
    }
}

Write-Host "Type declarations fix complete!"
