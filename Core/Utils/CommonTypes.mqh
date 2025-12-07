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
class CEnsembleMetaLearner;
class CMarketRegimeClassifier;

// Common structs
// Note: Full SPredictionWithUncertainty struct defined in AIModules/UncertaintyQuantifier.mqh
/*
struct SPredictionWithUncertainty
{
    double prediction;
    double uncertainty;
    datetime timestamp;
    bool isValid;
};
*/

struct SMarketState
{
    ENUM_MARKET_REGIME regime;
    double volatility;
    double trendStrength;
    bool isTrending;
    datetime lastUpdate;
};

#endif // COMMON_TYPES_MQH
