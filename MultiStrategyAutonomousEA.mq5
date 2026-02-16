//+------------------------------------------------------------------+
//| MultiStrategyAutonomousEA.mq5 - Advanced AI Trading System      |
//| Autonomous multi-strategy EA with Python AI integration           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

//--- Input parameters (Fixed compilation errors)
input double InpLotSize = 0.1;              // Base lot size
input int InpMagicNumber = 123456;         // Magic number
input bool InpUseEnhancedRisk = true;      // Enable adaptive sizing inside unified risk manager
input double InpMaxRiskPerTrade = 2.0;    // Max risk per trade (e.g., 2.0 for 2%)
input double InpMaxDailyRisk = 6.0;       // Max daily risk (e.g., 6.0 for 6%)
input double InpMaxPortfolioRisk = 10.0;   // Max total portfolio risk (e.g., 10.0 for 10%)
input double InpMaxDrawdown = 15.0;       // Max drawdown (e.g., 15.0 for 15%)
input string InpSymbolsToTrade = "Step Index.0,Jump 10 Index.0,AUXUSD.0,EURUSD.0";               // Comprehensive test symbols
input int    InpMinSecondsBetweenTrades = 120;    // Cooldown in seconds between trades
input int    InpMaxPositionsTotal = 15;           // Global position limit
input bool   InpAllowSyntheticOffHours = true;    // Allow synthetic indices to trade 24/7 (outside normal forex hours)

//--- Strategy Selection (for testing)
input group "Strategy Selection"
input bool InpEnableMomentum = true;         // Enable Momentum Strategy
input bool InpEnableTrend = false;           // Enable Trend Strategy
input bool InpEnableFibonacci = false;        // Enable Fibonacci Strategy
input bool InpEnableElliottWave = false;       // Enable Elliott Wave Enhanced Strategy
input bool InpEnableSupportResistance = false; // Enable Support/Resistance + Trendlines
input bool InpEnableUnifiedICT = true;         // Enable Unified ICT/SMC Strategy
input bool InpEnableCandlestick = false;       // Enable Candlestick Patterns Strategy
input bool InpUseCuratedStrategySet = true;    // Enable curated production strategy subset

//--- AI Mode Settings (NEW)
input group "AI Engine Settings"
input bool InpEnableAIMode = false;            // Enable AI Mode
input bool InpEnableNeuralNetwork = false;     // Enable Neural Network
input bool InpEnableTransformer = false;       // Enable Transformer Brain
input bool InpEnableEnsemble = false;          // Enable Ensemble Learning
input double InpAIConfidenceThreshold = 0.60;  // AI Confidence Threshold (Increased for better quality)
input double InpAIWeightMultiplier = 1.0;      // AI Weight Multiplier

//--- NN attribution forward-test diagnostics
input group "NN Attribution Diagnostics"
input bool InpEnableNNAttributionDiagnostics = false; // Enable NN attribution live diagnostics
input bool InpRunNNAttributionSelfTest = false;       // Run local mapping self-test at init

//--- Runtime Cadence + NN Online Learning
input group "Runtime Cadence & Learning"
input bool InpEnableHybridCadence = true;             // Enable hybrid cadence (new-bar + timed intrabar scans)
input int  InpIntrabarScanSeconds = 10;               // Intrabar scan interval in seconds
input bool InpIntrabarChartSymbolOnly = true;         // Restrict intrabar scans to chart symbol
input bool InpEnableNNPseudoLabeling = true;          // Enable pseudo-labeling when no trade-linked label exists
input int  InpNNPseudoLabelBarsAhead = 1;             // Pseudo-label horizon in bars
input int  InpNNSampleIntervalSeconds = 30;           // Observation sampling interval (seconds)
input int  InpNNCheckpointEveryLabeled = 10;          // Checkpoint every N newly labeled samples

//--- Enterprise Mode Settings
input group "Enterprise Mode"
input bool InpUseSignalPipeline = true;        // Use Signal Pipeline
input bool InpUseOrchestrator = true;          // Legacy flag (trade decisions now governed by EnterpriseManager only)
input double InpMinTrendStrength = 50.0;       // Minimum Trend Strength
input double InpMaxVolatility = 3.0;           // Maximum Volatility %
input bool InpEnableStructureFilter = true;    // Enable Structure Filter
input bool InpEnableLiquidityFilter = true;    // Enable Liquidity Filter
input bool InpSignalScanOnNewBarOnly = true;   // Evaluate fresh entry signals only on new bar
input int  InpPortfolioMaxPositionsPerSymbol = 2; // EA-side precheck before risk gate

//--- Include files
#include <Object.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "Interfaces\IStrategy.mqh"
#include "Core\Utils\ErrorHandling.mqh"
#include "IndicatorManager.mqh"
#include "Core\Utils\Instruments.mqh"
#include "Core\Risk\UnifiedRiskManager.mqh"
#include "Core\Risk\PositionSizer.mqh"
#include "Core\Monitoring\PerformanceAnalytics.mqh"
#include "Core\AI\AIPerformanceFeedback.mqh"
#include "Core\AI\AIStrategyOrchestrator.mqh"
#include "Core\Trading\TradeManager.mqh"
#include "Core\Engines\MarketAnalysis.mqh"
// DELETED: #include "Core\Connectivity\IntegrationHub.mqh"
#include "Core\Strategy\StrategyBase.mqh"
#include "Strategies\SimpleMomentumStrategy.mqh"
// DELETED: #include "Core\Engines\TradingEngine.mqh"
#include "Core\Utils\SymbolContext.mqh"
#include "Core\Strategy\StrategyWrapper.mqh"
// AUDIT FIX: Removed duplicate #include "IndicatorManager.mqh" (already included at line 68)
#include "AIModules\NextGenStrategyBrain.mqh"
#include "AIModules\TransformerBrain.mqh"
#include "AIModules\EnsembleMetaLearner.mqh"
#include "AIModules\NeuralNetworkStrategy.mqh"
#include "Core\Engines\AIEngine.mqh"

// Enterprise Components
#include "Core\Management\EnterpriseStrategyManager.mqh"
#include "Core\Pipeline\UnifiedSignalPipeline.mqh"
#include "Core\Engines\StructureEngine.mqh"
#include "Core\Engines\TrendEngine.mqh"
#include "Core\Engines\LiquidityEngine.mqh"
#include "Core\Engines\VolatilityEngine.mqh"

// Enhanced Strategies
#include "Strategies\StrategyElliottWaveEnhanced.mqh"
#include "Strategies\StrategyCandlestick.mqh"

// Advanced AI Modules
// DELETED: #include "AIModules\GeneticOptimizer.mqh"

// Advanced Signal Validation and Position Management
#include "Core\Signals\AdvancedSignalValidator.mqh"
#include "Core\Trading\AdvancedPositionManager.mqh"
#include "Core\Strategy\AIStrategyAdapter.mqh"
#include "Core\Visualization\VisualDashboard.mqh"

//+------------------------------------------------------------------+
//| Forward declarations
//+------------------------------------------------------------------+
// Classes now included from separate files

//+------------------------------------------------------------------+
//| Momentum strategy for multi-instrument orchestration             |
//+------------------------------------------------------------------+
// CSimpleMomentumStrategy moved to Strategies/SimpleMomentumStrategy.mqh

//+------------------------------------------------------------------+
//| Progressive TP entry wrapper per position                        |
//+------------------------------------------------------------------+
// CTPManagerEntry moved to Core/TPManagerEntry.mqh

// CStrategyWrapper moved to Core/StrategyWrapper.mqh

//+------------------------------------------------------------------+
//| Symbol execution context                                         |
//+------------------------------------------------------------------+
// CSymbolContext moved to Core/SymbolContext.mqh

//--- Global variables
CSymbolInfo globalSymbol;
CAccountInfo account;
CEnhancedErrorHandler errorHandler;
CUnifiedRiskManager unifiedRiskManager;
CPerformanceAnalytics performanceAnalytics;
CAIPerformanceFeedback aiFeedback;
// CAIStrategyOrchestrator aiOrchestrator; // Already declared? Check global scope.
// Using global aiOrchestrator
CAIStrategyOrchestrator aiOrchestrator;
CUtilities utilities;

// CAIIntegrationHub is now included from Core/IntegrationHub.mqh

CNextGenStrategyBrain aiNextGenBrain;
CTransformerBrain transformerBrain;
CEnsembleMetaLearner ensembleLearner;
CNeuralNetworkStrategy* neuralNetStrategy = NULL;
CNeuralNetworkStrategy* g_neuralNetStrategies[];
string g_neuralNetStrategySymbols[];
ulong g_predictionPositionIds[];
string g_predictionIdsByPosition[];
ulong g_pendingClosePositionIds[];
double g_pendingCloseNetProfit[];
CPositionSizer positionSizer;
CMarketAnalysis marketAnalysis;
// DELETED: CAIIntegrationHub integrationHub;
CInstrumentRegistry instrumentRegistry;

CTradeManager tradeManager;


// REMOVED: CTradingEngine tradingEngine; // Dead code removal
CEnterpriseStrategyManager* g_enterpriseManager = NULL; // Enterprise Strategy Manager
CEnterpriseStrategyManager* g_enterpriseManagers[];      // Per-symbol managers
string g_enterpriseManagerSymbols[];                     // Manager symbol mapping
CAdvancedSignalValidator* g_signalValidator = NULL; // Advanced Signal Validator
CAdvancedPositionManager* g_positionManager = NULL; // Advanced Position Manager
// g_AIEngine declared in AIEngine.mqh
CVisualDashboard g_dashboard;

//--- Performance tracking
// Centralized in CPerformanceAnalytics but kept here for display compatibility
double peakEquity = 0.0;
double initialBalance = 0.0;
double accountBalance = 0.0;
double accountEquity = 0.0;
double currentEquity = 0.0;
double currentDrawdown = 0.0;
double totalProfit = 0.0;
double totalLoss = 0.0;
int totalTrades = 0;
int winningTrades = 0;
int losingTrades = 0;
double maxDrawdown = 0.0;

//--- Missing time variables
datetime currentTime = 0;

//--- Risk management
double currentRiskPerTrade = 0.0;
double dailyRiskUsed = 0.0;
double maxDailyRisk = 0.0;
bool recoveryMode = false;
bool drawdownMode = false;
double g_currentDrawdown = 0.0;
ENUM_MARKET_REGIME g_currentRegime = MARKET_REGIME_UNKNOWN;
double g_correlationMatrix[10][10];
datetime g_lastTradeTime = 0;
int g_totalActivePositions = 0;
string g_activePairs[];
datetime g_lastSymbolBarTimes[];
datetime g_lastIntrabarScanTime[];
int g_minTimeBetweenTrades = 120;
int g_maxPositionsAllowed = 10;
string g_symbolsToTrade = "";
bool g_beastModeProtection = true;
bool systemInitialized = false;
bool tradingEnabled = false;

// NN attribution diagnostics counters
int g_nnDiagEntryMapCount = 0;
int g_nnDiagCloseByIdCount = 0;
int g_nnDiagCloseFallbackCount = 0;
int g_nnDiagCloseMissCount = 0;
int g_nnDiagPartialCloseCount = 0;
datetime g_nnDiagLastSummaryTime = 0;

// Runtime heartbeat + rejection telemetry
ulong g_hbScansAttempted = 0;
ulong g_hbIntrabarScansExecuted = 0;
ulong g_hbNoSignalCount = 0;
ulong g_hbValidatorRejects = 0;
ulong g_hbRiskRejects = 0;
ulong g_hbTradesOpened = 0;
ulong g_hbQuietNoNewBar = 0;
datetime g_lastHeartbeatLogTime = 0;
datetime g_lastNNHealthLogTime = 0;

// Risk configuration defaults (overridable by configuration modules)
double DefaultStopLossPips = 20.0;
double DefaultTakeProfitPips = 40.0;
double MaxRiskPerTrade = 2.0;
double AccountRiskMax = 10.0;
double DrawdownReduceThreshold = 5.0;
double CorrelationThreshold = 0.7;



//--- Market state tracking
ENUM_MARKET_REGIME currentRegime = MARKET_REGIME_UNKNOWN;
double currentVolatility = 0.0;
double currentATR = 0.0;
double regimeStrength = 0.0;
double momentumScore = 0.0;
double volumeRatio = 0.0;
bool newsEventActive = false;

//--- AI telemetry
int aiSignalCounter = 0;
datetime lastSignalTime = 0;
double aiSuccessRate = 0.0;

//--- Time management
datetime startTime = 0;
datetime lastTickTime = 0;
int tickCounter = 0;
int barCounter = 0;
bool isNewBar = false;

//+------------------------------------------------------------------+
//| Helper: Initialize AI systems                                    |
//+------------------------------------------------------------------+
// [DEAD CODE REMOVED] InitializeAISystems and DeinitializeAISystems
// AI initialization strategy moved to OnInit/OnDeinit with proper gating

//+------------------------------------------------------------------+
//| Get Symbol Context Wrapper                                       |
//+------------------------------------------------------------------+
// [REMOVED] GetSymbolContext - Context management moved to CEnterpriseStrategyManager

//+------------------------------------------------------------------+
//| Update performance tracking                                      |
//+------------------------------------------------------------------+
void UpdatePerformanceTracking()
{
    // Delegate to centralized analytics
    performanceAnalytics.UpdateRealTimeMetrics();
}

//+------------------------------------------------------------------+
//| Save performance data                                            |
//+------------------------------------------------------------------+
void SavePerformanceData()
{
    performanceAnalytics.SaveReportToCSV("MultiStrategyEA_Performance.csv");
}

//+------------------------------------------------------------------+
//| Check if new bar                                                 |
//+------------------------------------------------------------------+
bool IsNewBar(const string symbolParam, const ENUM_TIMEFRAMES timeframe)
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(symbolParam, timeframe, 0);

    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Get last error message                                           |
//+------------------------------------------------------------------+
string GetLastErrorMessage()
{
    int errorCode = GetLastError();
    return IntegerToString(errorCode);
}

//+------------------------------------------------------------------+
//| Helper: Count EA Positions (by magic number)                     |
//+------------------------------------------------------------------+
int GetEAPositionCount()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            // Check if position belongs to this EA (by magic number)
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
                count++;
        }
    }
    return count;
}

int GetOpenPositionCountForSymbol(const string symbol, const bool onlyThisEAMagic = false)
{
    if(symbol == "")
        return 0;

    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        if(PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

        if(onlyThisEAMagic && PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
            continue;

        count++;
    }

    return count;
}

string ExtractPredictionIdFromComment(const string comment)
{
    int marker = StringFind(comment, "|N:");
    if(marker < 0)
        return "";

    int start = marker + 3;
    if(start >= StringLen(comment))
        return "";

    return StringSubstr(comment, start);
}

string BuildTradeCommentWithPrediction(const string baseComment, const string predictionId)
{
    string comment = baseComment;
    if(predictionId == "")
        return comment;

    string suffix = "|N:" + predictionId;
    const int maxCommentLength = 31;
    int availableBase = maxCommentLength - StringLen(suffix);
    if(availableBase < 0)
        return StringSubstr(suffix, 0, maxCommentLength);

    if(StringLen(comment) > availableBase)
        comment = StringSubstr(comment, 0, availableBase);

    return comment + suffix;
}

int FindPredictionPositionIndex(const ulong positionId)
{
    for(int i = 0; i < ArraySize(g_predictionPositionIds); i++)
    {
        if(g_predictionPositionIds[i] == positionId)
            return i;
    }
    return -1;
}

void UpsertPredictionPositionMap(const ulong positionId, const string predictionId)
{
    if(positionId == 0 || predictionId == "")
        return;

    int idx = FindPredictionPositionIndex(positionId);
    if(idx >= 0)
    {
        g_predictionIdsByPosition[idx] = predictionId;
        return;
    }

    int size = ArraySize(g_predictionPositionIds);
    ArrayResize(g_predictionPositionIds, size + 1);
    ArrayResize(g_predictionIdsByPosition, size + 1);
    g_predictionPositionIds[size] = positionId;
    g_predictionIdsByPosition[size] = predictionId;
}

string GetPredictionIdForPosition(const ulong positionId)
{
    int idx = FindPredictionPositionIndex(positionId);
    if(idx < 0 || idx >= ArraySize(g_predictionIdsByPosition))
        return "";
    return g_predictionIdsByPosition[idx];
}

void RemovePredictionPositionMap(const ulong positionId)
{
    int idx = FindPredictionPositionIndex(positionId);
    if(idx < 0)
        return;

    int last = ArraySize(g_predictionPositionIds) - 1;
    if(last < 0)
        return;

    if(idx != last)
    {
        g_predictionPositionIds[idx] = g_predictionPositionIds[last];
        g_predictionIdsByPosition[idx] = g_predictionIdsByPosition[last];
    }

    ArrayResize(g_predictionPositionIds, last);
    ArrayResize(g_predictionIdsByPosition, last);
}

int FindPendingCloseProfitIndex(const ulong positionId)
{
    for(int i = 0; i < ArraySize(g_pendingClosePositionIds); i++)
    {
        if(g_pendingClosePositionIds[i] == positionId)
            return i;
    }
    return -1;
}

void AccumulatePendingCloseProfit(const ulong positionId, const double netProfit)
{
    if(positionId == 0)
        return;

    int idx = FindPendingCloseProfitIndex(positionId);
    if(idx >= 0)
    {
        g_pendingCloseNetProfit[idx] += netProfit;
        return;
    }

    int size = ArraySize(g_pendingClosePositionIds);
    ArrayResize(g_pendingClosePositionIds, size + 1);
    ArrayResize(g_pendingCloseNetProfit, size + 1);
    g_pendingClosePositionIds[size] = positionId;
    g_pendingCloseNetProfit[size] = netProfit;
}

double ConsumePendingCloseProfit(const ulong positionId)
{
    int idx = FindPendingCloseProfitIndex(positionId);
    if(idx < 0)
        return 0.0;

    double accumulated = g_pendingCloseNetProfit[idx];
    int last = ArraySize(g_pendingClosePositionIds) - 1;
    if(last >= 0)
    {
        if(idx != last)
        {
            g_pendingClosePositionIds[idx] = g_pendingClosePositionIds[last];
            g_pendingCloseNetProfit[idx] = g_pendingCloseNetProfit[last];
        }
        ArrayResize(g_pendingClosePositionIds, last);
        ArrayResize(g_pendingCloseNetProfit, last);
    }

    return accumulated;
}

void ClearPendingCloseProfit(const ulong positionId)
{
    int idx = FindPendingCloseProfitIndex(positionId);
    if(idx < 0)
        return;

    int last = ArraySize(g_pendingClosePositionIds) - 1;
    if(last >= 0)
    {
        if(idx != last)
        {
            g_pendingClosePositionIds[idx] = g_pendingClosePositionIds[last];
            g_pendingCloseNetProfit[idx] = g_pendingCloseNetProfit[last];
        }
        ArrayResize(g_pendingClosePositionIds, last);
        ArrayResize(g_pendingCloseNetProfit, last);
    }
}

bool IsPositionIdStillOpen(const ulong positionId)
{
    if(positionId == 0)
        return false;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
        if(identifier == positionId)
            return true;
    }

    return false;
}

void NNDiagLog(const string message)
{
    if(InpEnableNNAttributionDiagnostics)
        Print("[NN-DIAG] ", message);
}

void NNDiagPrintSummary(const string context = "")
{
    if(!InpEnableNNAttributionDiagnostics)
        return;

    string tag = (context == "") ? "runtime" : context;
    PrintFormat("[NN-DIAG] Summary (%s) | EntryMap=%d | CloseById=%d | CloseFallback=%d | CloseMiss=%d | PartialClose=%d | ActiveMap=%d",
                tag,
                g_nnDiagEntryMapCount,
                g_nnDiagCloseByIdCount,
                g_nnDiagCloseFallbackCount,
                g_nnDiagCloseMissCount,
                g_nnDiagPartialCloseCount,
                ArraySize(g_predictionPositionIds));
    g_nnDiagLastSummaryTime = TimeCurrent();
}

bool RunNNAttributionSelfTest()
{
    if(!InpRunNNAttributionSelfTest)
        return true;

    NNDiagLog("Self-test started");
    bool ok = true;

    string testPrediction = "12345678901234";
    string comment = BuildTradeCommentWithPrediction("Enterprise AI Signal", testPrediction);
    string extracted = ExtractPredictionIdFromComment(comment);
    if(extracted != testPrediction)
    {
        ok = false;
        NNDiagLog("Self-test failed: comment prediction extraction mismatch");
    }

    const ulong testPositionId = 999001;
    UpsertPredictionPositionMap(testPositionId, testPrediction);
    if(GetPredictionIdForPosition(testPositionId) != testPrediction)
    {
        ok = false;
        NNDiagLog("Self-test failed: position->prediction map upsert/get mismatch");
    }
    RemovePredictionPositionMap(testPositionId);
    if(GetPredictionIdForPosition(testPositionId) != "")
    {
        ok = false;
        NNDiagLog("Self-test failed: position->prediction map remove mismatch");
    }

    NNDiagLog(ok ? "Self-test passed" : "Self-test failed");
    return ok;
}

//+------------------------------------------------------------------+
//| Authoritative risk decision helper                               |
//| NOTE: UnifiedRiskManager is the only trade-entry veto authority. |
//+------------------------------------------------------------------+
bool ApproveTradeByUnifiedRisk(const STradeValidationRequest &request,
                               const string phaseTag,
                               SValidationResult &result)
{
    result = unifiedRiskManager.ValidateTradeRequest(request, phaseTag);
    if(!result.approved)
    {
        g_hbRiskRejects++;
        Print("[RISK-CONTRACT] REJECTED (", phaseTag, ") ",
              request.symbol, " | ", result.message);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Strategy-name helper                                             |
//+------------------------------------------------------------------+
string GetStrategyNameByIndex(const int index)
{
    switch(index)
    {
        case 0: return "Momentum";
        case 1: return "Trend";
        case 2: return "Fibonacci";
        case 3: return "Elliott Wave";
        case 4: return "Support/Resistance";
        case 5: return "Unified ICT";
        case 6: return "Candlestick";
        default: return "Unknown";
    }
}

string BuildEnabledStrategyList(const bool &strategyFlags[])
{
    string enabled = "";
    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(!strategyFlags[i])
            continue;

        if(StringLen(enabled) > 0)
            enabled += ", ";
        enabled += GetStrategyNameByIndex(i);
    }

    if(StringLen(enabled) == 0)
        return "None";

    return enabled;
}

//+------------------------------------------------------------------+
//| Build strategy flags + curated profile filtering                 |
//+------------------------------------------------------------------+
void BuildStrategyFlags(bool &strategyFlags[])
{
    ArrayResize(strategyFlags, 7);
    strategyFlags[0]  = InpEnableMomentum;
    strategyFlags[1]  = InpEnableTrend;
    strategyFlags[2]  = InpEnableFibonacci;
    strategyFlags[3]  = InpEnableElliottWave;
    strategyFlags[4]  = InpEnableSupportResistance;
    strategyFlags[5]  = InpEnableUnifiedICT;
    strategyFlags[6]  = InpEnableCandlestick;

    if(!InpUseCuratedStrategySet)
        return;

    bool curatedMask[7] = {
        true,   // Momentum
        false,  // Trend
        false,  // Fibonacci
        false,  // Elliott Wave
        false,  // Support/Resistance
        true,   // Unified ICT
        false   // Candlestick
    };

    int enabledBefore = 0;
    int enabledAfter = 0;
    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(strategyFlags[i])
            enabledBefore++;

        if(strategyFlags[i] && !curatedMask[i])
        {
            strategyFlags[i] = false;
            Print("[CURATION] Disabled by curated profile: ", GetStrategyNameByIndex(i));
        }

        if(strategyFlags[i])
            enabledAfter++;
    }

    PrintFormat("[CURATION] Production strategy profile active (%d -> %d enabled)", enabledBefore, enabledAfter);
    Print("[CURATION] Effective runtime strategy set: ", BuildEnabledStrategyList(strategyFlags));
}

//+------------------------------------------------------------------+
//| Manager lookup helpers                                           |
//+------------------------------------------------------------------+
int FindEnterpriseManagerIndex(const string symbol)
{
    for(int i = 0; i < ArraySize(g_enterpriseManagerSymbols); i++)
    {
        if(g_enterpriseManagerSymbols[i] == symbol)
            return i;
    }
    return -1;
}

CEnterpriseStrategyManager* GetEnterpriseManagerForSymbol(const string symbol)
{
    int idx = FindEnterpriseManagerIndex(symbol);
    if(idx < 0 || idx >= ArraySize(g_enterpriseManagers))
        return NULL;
    return g_enterpriseManagers[idx];
}

int GetTotalActiveStrategyCount()
{
    int total = 0;
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        if(g_enterpriseManagers[i] != NULL)
            total += g_enterpriseManagers[i].GetActiveStrategyCount();
    }
    return total;
}

int GetTotalActiveBrainStrategyCount()
{
    int total = 0;
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        if(g_enterpriseManagers[i] != NULL)
            total += g_enterpriseManagers[i].GetActiveBrainStrategyCount();
    }
    return total;
}

void ReleaseEnterpriseManagers()
{
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        if(g_enterpriseManagers[i] != NULL)
        {
            delete g_enterpriseManagers[i];
            g_enterpriseManagers[i] = NULL;
        }
    }
    ArrayResize(g_enterpriseManagers, 0);
    ArrayResize(g_enterpriseManagerSymbols, 0);
    ArrayResize(g_lastSymbolBarTimes, 0);
    ArrayResize(g_lastIntrabarScanTime, 0);
    g_enterpriseManager = NULL;
}

int FindNeuralNetStrategyIndex(const string symbol)
{
    for(int i = 0; i < ArraySize(g_neuralNetStrategySymbols); i++)
    {
        if(g_neuralNetStrategySymbols[i] == symbol)
            return i;
    }
    return -1;
}

CNeuralNetworkStrategy* GetNeuralNetForSymbol(const string symbol)
{
    int idx = FindNeuralNetStrategyIndex(symbol);
    if(idx < 0 || idx >= ArraySize(g_neuralNetStrategies))
        return NULL;
    return g_neuralNetStrategies[idx];
}

void ReleaseNeuralNetStrategies()
{
    for(int i = 0; i < ArraySize(g_neuralNetStrategies); i++)
    {
        if(g_neuralNetStrategies[i] != NULL)
        {
            delete g_neuralNetStrategies[i];
            g_neuralNetStrategies[i] = NULL;
        }
    }
    ArrayResize(g_neuralNetStrategies, 0);
    ArrayResize(g_neuralNetStrategySymbols, 0);
    ArrayResize(g_predictionPositionIds, 0);
    ArrayResize(g_predictionIdsByPosition, 0);
    ArrayResize(g_pendingClosePositionIds, 0);
    ArrayResize(g_pendingCloseNetProfit, 0);
    neuralNetStrategy = NULL;
}

bool InitializeNeuralNetForSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(StringLen(symbol) == 0)
    {
        Print("[AI-MODE] Skipping NN initialization for empty symbol");
        return false;
    }

    if(!SymbolSelect(symbol, true))
    {
        Print("[AI-MODE] Skipping NN initialization for unavailable symbol: ", symbol);
        return false;
    }

    CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(symbol);
    if(symbolManager == NULL || symbolManager.GetActiveStrategyCount() <= 0)
    {
        Print("[AI-MODE] Skipping NN initialization; no active strategy manager for ", symbol);
        return false;
    }

    if(GetNeuralNetForSymbol(symbol) != NULL)
        return true;

    CNeuralNetworkStrategy* nn = new CNeuralNetworkStrategy();
    if(nn == NULL)
    {
        Print("[AI-MODE] Failed to allocate Neural Network for ", symbol);
        return false;
    }

    if(!nn.Initialize(symbol, timeframe))
    {
        Print("[AI-MODE] Neural Network initialization failed for ", symbol);
        delete nn;
        return false;
    }

    nn.ConfigureOnlineLearning(InpEnableNNPseudoLabeling,
                               InpNNPseudoLabelBarsAhead,
                               InpNNSampleIntervalSeconds,
                               InpNNCheckpointEveryLabeled);

    int currentSize = ArraySize(g_neuralNetStrategies);
    ArrayResize(g_neuralNetStrategies, currentSize + 1);
    ArrayResize(g_neuralNetStrategySymbols, currentSize + 1);
    g_neuralNetStrategies[currentSize] = nn;
    g_neuralNetStrategySymbols[currentSize] = symbol;

    if(symbolManager != NULL)
    {
        double aiWeight = InpAIWeightMultiplier > 0 ? InpAIWeightMultiplier : 3.0;
        if(!symbolManager.RegisterStrategy(new CAIStrategyAdapter(nn), "Neural Network AI", true, aiWeight, PERIOD_CURRENT, true))
            Print("[AI-MODE] WARNING: Failed to register NN adapter for ", symbol);
    }

    Print("[AI-MODE] Neural Network ready for ", symbol);
    return true;
}

bool InitializeEnterpriseManagerForSymbol(const string symbol, bool &strategyFlags[])
{
    CEnterpriseStrategyManager* manager = new CEnterpriseStrategyManager();
    if(manager == NULL)
    {
        Print("[ERROR] Failed to allocate Enterprise Strategy Manager for ", symbol);
        return false;
    }

    if(!manager.Initialize(symbol, (ENUM_TIMEFRAMES)Period(), InpUseSignalPipeline,
                           &tradeManager, &positionSizer, (long)InpMagicNumber))
    {
        Print("[ERROR] Failed to initialize Enterprise Strategy Manager for ", symbol);
        delete manager;
        return false;
    }

    if(InpUseSignalPipeline)
    {
        SignalFilterSettings filters;
        filters.enableTrendFilter = true;
        filters.enableVolatilityFilter = true;
        filters.enableLiquidityFilter = InpEnableLiquidityFilter;
        filters.enableStructureFilter = InpEnableStructureFilter;
        filters.minConfidence = InpAIConfidenceThreshold;
        filters.maxVolatility = InpMaxVolatility;
        filters.minTrendStrength = (int)InpMinTrendStrength;
        manager.SetPipelineFilters(filters);
    }

    manager.SetMinQuorum(2);
    Print("[CURATION] Effective strategy set for ", symbol, ": ", BuildEnabledStrategyList(strategyFlags));
    manager.AutoRegisterStrategies(strategyFlags);

    int size = ArraySize(g_enterpriseManagers);
    ArrayResize(g_enterpriseManagers, size + 1);
    ArrayResize(g_enterpriseManagerSymbols, size + 1);
    ArrayResize(g_lastSymbolBarTimes, size + 1);
    g_enterpriseManagers[size] = manager;
    g_enterpriseManagerSymbols[size] = symbol;
    g_lastSymbolBarTimes[size] = 0;

    if(symbol == _Symbol)
        g_enterpriseManager = manager;

    Print("[ENTERPRISE] Manager initialized for ", symbol, " with ", manager.GetActiveStrategyCount(), " active strategies");
    return true;
}

//+------------------------------------------------------------------+
//| Expert Advisor Initialization                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Advanced AI Trading System v2.0 Starting");
    Print("[MULTI-STRATEGY-EA] ========================================");

    // Validate MetaTrader 5 environment
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Alert("[CRITICAL] Trading is not allowed in the terminal! Enable AutoTrading!");
        return INIT_FAILED;
    }

    if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Alert("[CRITICAL] Trading is not allowed for this EA! Check EA properties!");
        return INIT_FAILED;
    }

    if(!tradeManager.Initialize((uint)InpMagicNumber, "MultiStrategyAutonomousEA"))
    {
        Print("[CRITICAL] Failed to initialize TradeManager");
        return INIT_FAILED;
    }
    tradeManager.SetMaxDailyLoss(MathMax(0.0, AccountInfoDouble(ACCOUNT_BALANCE) * (InpMaxDailyRisk / 100.0)));
    tradeManager.SetExternalRiskAuthority(true);

    // Validate account type and permissions
    ENUM_ACCOUNT_TRADE_MODE tradeMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
    if(tradeMode == ACCOUNT_TRADE_MODE_DEMO)
        Print("[INFO] Running on DEMO account");
    else if(tradeMode == ACCOUNT_TRADE_MODE_REAL)
        Print("[WARNING] Running on REAL account - Trade carefully!");
    else if(tradeMode == ACCOUNT_TRADE_MODE_CONTEST)
        Print("[INFO] Running on CONTEST account");

    // Display account information
    Print("[ACCOUNT] Broker: ", AccountInfoString(ACCOUNT_COMPANY));
    Print("[ACCOUNT] Account: ", AccountInfoInteger(ACCOUNT_LOGIN));
    Print("[ACCOUNT] Currency: ", AccountInfoString(ACCOUNT_CURRENCY));
    Print("[ACCOUNT] Leverage: 1:", AccountInfoInteger(ACCOUNT_LEVERAGE));
    Print("[ACCOUNT] Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    Print("[ACCOUNT] Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
    Print("[ACCOUNT] Free Margin: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));

    // AUDIT FIX: Gate AI subsystem initialization behind InpEnableAIMode
    if(InpEnableAIMode)
    {
        Print("[AI] Initializing AI subsystems...");

        if(!aiNextGenBrain.Initialize(Symbol(), Period()))
        {
            Print("[ERROR] Failed to initialize NextGen AI Brain");
            return INIT_FAILED;
        }

        if(InpEnableTransformer)
        {
            if(!transformerBrain.Initialize())
            {
                Print("[ERROR] Failed to initialize Transformer Brain");
                return INIT_FAILED;
            }
        }
        else
        {
            Print("[AI] Transformer disabled by input flag");
        }

        if(InpEnableEnsemble)
        {
            if(!ensembleLearner.Initialize())
            {
                Print("[ERROR] Failed to initialize Ensemble Learner");
                return INIT_FAILED;
            }
        }
        else
        {
            Print("[AI] Ensemble learner disabled by input flag");
        }

        Print("[AI] Configured AI subsystems initialized successfully");
    }
    else
    {
        Print("[AI] AI Mode disabled — skipping AI subsystem initialization");
    }

    // Initialize shared orchestrator only for optional AI adaptation modules.
    if(InpEnableAIMode)
    {
        if(!aiOrchestrator.Initialize(0.4, 5))
        {
            Print("[CRITICAL] Failed to initialize AI Strategy Orchestrator");
            return INIT_FAILED;
        }
        Print("[INIT] AI Strategy Orchestrator initialized (AI adaptation only)");
    }
    else
    {
        if(InpUseOrchestrator)
            Print("[AI] InpUseOrchestrator is legacy; trade decisions remain manager-governed");
        Print("[AI] Orchestrator disabled (AI mode off)");
    }

    // Initialize unified risk authority (single risk contract)
    SUnifiedRiskConfig unifiedRiskConfig;
    unifiedRiskConfig.baseRiskPerTradePercent = InpMaxRiskPerTrade;
    unifiedRiskConfig.minRiskPerTradePercent = MathMax(0.1, InpMaxRiskPerTrade * 0.5);
    unifiedRiskConfig.maxRiskPerTradePercent = MathMin(MAX_RISK_PER_TRADE, InpMaxRiskPerTrade);
    unifiedRiskConfig.maxDailyRiskPercent = InpMaxDailyRisk;
    unifiedRiskConfig.maxPortfolioRiskPercent = InpMaxPortfolioRisk;
    unifiedRiskConfig.correlationThreshold = CorrelationThreshold;
    unifiedRiskConfig.drawdownWarningPercent = MathMax(3.0, InpMaxDrawdown * 0.5);
    unifiedRiskConfig.drawdownCriticalPercent = InpMaxDrawdown;
    unifiedRiskConfig.adaptationMinTrades = 20;
    unifiedRiskConfig.enableAdaptiveSizing = InpUseEnhancedRisk;
    unifiedRiskConfig.enableAuditLogging = true;
    unifiedRiskConfig.auditLogFile = "UnifiedRiskValidation.log";

    if(!unifiedRiskManager.Initialize(unifiedRiskConfig, &performanceAnalytics))
    {
        Print("[CRITICAL] UnifiedRiskManager failed to initialize!");
        return INIT_FAILED;
    }
    Print("[INIT] UnifiedRiskManager initialized as single risk authority");

    // Initialize PositionSizer before enterprise managers
    SPositionSizingParams sizingParams;
    sizingParams.sizingMode       = POSITION_SIZE_RISK_PERCENT;
    sizingParams.fixedLotSize     = InpLotSize;
    sizingParams.riskPercent      = InpMaxRiskPerTrade;         // Now using consistent 0-100 scale (e.g., 2.0)
    sizingParams.atrPeriod        = 14;
    sizingParams.atrMultiplier    = 1.5;
    sizingParams.maxLotSize       = MAX_LOT_SIZE;
    sizingParams.minLotSize       = MIN_LOT_SIZE;
    sizingParams.correlationAdjustment  = 1.0;
    sizingParams.useVolatilityAdjustment = true;
    sizingParams.useCorrelationAdjustment = false;
    if(!positionSizer.SetParameters(sizingParams))
    {
        Print("[CRITICAL] PositionSizer initialization FAILED — will use min lot fallback!");
    }
    else
    {
        Print("[INIT] PositionSizer initialized — Mode: RISK_PERCENT, Risk: ",
              DoubleToString(sizingParams.riskPercent, 2), "%");
    }

    // Initialize AI Engine for Adaptation (only when AI mode is enabled)
    if(InpEnableAIMode)
    {
        if(g_AIEngine == NULL) g_AIEngine = new CAIEngine();

        SAIAdaptiveConfig aiConfig;
        aiConfig.enabled = true;
        aiConfig.learningRate = 0.1;
        aiConfig.adaptationInterval = 1; // Adapt every bar
        aiConfig.minConfidenceThreshold = InpAIConfidenceThreshold;

        if(g_AIEngine != NULL && g_AIEngine.Initialize(&aiOrchestrator, aiConfig))
        {
            Print("[INIT] AI Engine initialized in ADAPTIVE mode");
        }
        else
        {
            Print("[ERROR] Failed to initialize AI Engine");
        }
    }
    else
    {
        Print("[AI] AIEngine disabled (InpEnableAIMode=false)");
    }

    // Build strategy flags with optional curated production profile
    bool strategyFlags[];
    BuildStrategyFlags(strategyFlags);
    if(InpUseCuratedStrategySet)
    {
        Print("[CURATION] Strict curated active: manual strategy toggles outside curated set are ignored.");
        Print("[CURATION] Effective curated roster: ", BuildEnabledStrategyList(strategyFlags));
    }
    PrintFormat("[RUNTIME-FINGERPRINT] Runtime=%s | File=%s | TerminalBuild=%d | Curated=%s | RegistrySize=%d | ActiveProfile=%s",
                TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                __FILE__,
                (int)TerminalInfoInteger(TERMINAL_BUILD),
                InpUseCuratedStrategySet ? "true" : "false",
                ArraySize(strategyFlags),
                BuildEnabledStrategyList(strategyFlags));

    // Validate and process trading symbols
    string symbols[];
    StringSplit(InpSymbolsToTrade, ',', symbols);
    Print("[SYMBOLS] Processing ", ArraySize(symbols), " trading symbols");

    // Clear and populate active pairs array
    ArrayResize(g_activePairs, 0);

    for(int i = 0; i < ArraySize(symbols); i++)
    {
        string sym = symbols[i];
        StringTrimLeft(sym);
        StringTrimRight(sym);

        if(StringLen(sym) == 0)
        {
            Print("[SYMBOLS] Empty symbol token skipped at input index ", i);
            continue;
        }

        // Validate symbol exists
        if(!SymbolSelect(sym, true))
        {
            Print("[WARNING] Symbol ", sym, " not available - skipping");
            continue;
        }

        // Check if symbol is tradeable
        long symbolTradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
        if(symbolTradeMode == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("[WARNING] Symbol ", sym, " trading is disabled - skipping");
            continue;
        }

        bool alreadyAdded = false;
        for(int j = 0; j < ArraySize(g_activePairs); j++)
        {
            if(g_activePairs[j] == sym)
            {
                alreadyAdded = true;
                break;
            }
        }
        if(alreadyAdded)
        {
            Print("[SYMBOLS] Duplicate symbol skipped: ", sym);
            continue;
        }

        // Add to active pairs array
        int size = ArraySize(g_activePairs);
        ArrayResize(g_activePairs, size + 1);
        g_activePairs[size] = sym;

        // Display symbol specifications
        Print("[SYMBOL] ", sym, " - Configured for trading");
        Print("  - Spread: ", SymbolInfoInteger(sym, SYMBOL_SPREAD), " points");
        Print("  - Min Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN));
        Print("  - Max Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX));
        Print("  - Lot Step: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP));
        Print("  - Contract Size: ", SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE));
    }

    // Always include chart symbol in manager set for deterministic local chart behavior
    bool chartSymbolFound = false;
    for(int i = 0; i < ArraySize(g_activePairs); i++)
    {
        if(g_activePairs[i] == _Symbol)
        {
            chartSymbolFound = true;
            break;
        }
    }
    if(!chartSymbolFound && SymbolSelect(_Symbol, true))
    {
        int size = ArraySize(g_activePairs);
        ArrayResize(g_activePairs, size + 1);
        g_activePairs[size] = _Symbol;
        Print("[SYMBOLS] Added chart symbol to active set: ", _Symbol);
    }

    if(ArraySize(g_activePairs) <= 0)
    {
        Print("[CRITICAL] No valid trading symbols after validation.");
        return INIT_FAILED;
    }

    ArrayResize(g_lastIntrabarScanTime, ArraySize(g_activePairs));
    ArrayInitialize(g_lastIntrabarScanTime, 0);

    Print("[SYMBOLS] ", ArraySize(g_activePairs), " symbols validated and ready for trading");
    g_symbolsToTrade = InpSymbolsToTrade;

    // Initialize enterprise manager per symbol
    Print("[ENTERPRISE] Initializing per-symbol strategy managers...");
    ReleaseEnterpriseManagers();
    int managerInitCount = 0;
    for(int i = 0; i < ArraySize(g_activePairs); i++)
    {
        if(InitializeEnterpriseManagerForSymbol(g_activePairs[i], strategyFlags))
            managerInitCount++;
    }

    if(managerInitCount <= 0 || ArraySize(g_enterpriseManagers) <= 0)
    {
        Print("[CRITICAL] Failed to initialize any Enterprise Strategy Manager.");
        return INIT_FAILED;
    }

    if(g_enterpriseManager == NULL)
        g_enterpriseManager = g_enterpriseManagers[0];

    // Initialize Advanced Signal Validator (shared)
    g_signalValidator = new CAdvancedSignalValidator();
    if(g_signalValidator != NULL)
    {
        g_signalValidator.SetValidationProfiles(2, 0.68, 0.60, 1, 0.75, 0.70);
        g_signalValidator.SetMaxSpreadMultiplier(2.0);
        g_signalValidator.EnableTimeFilter(true, 1, 22);
        g_signalValidator.EnableSessionFilter(true, true, true, true);
        g_signalValidator.EnableVolatilityFilter(true, 0.0, 5.0);
        g_signalValidator.EnableSpreadFilter(true, 2.0);
        g_signalValidator.SetAllowSyntheticOffHours(InpAllowSyntheticOffHours);
        Print("[SIGNAL-VALIDATOR] Advanced signal validation enabled | Synthetic Off-Hours: ", InpAllowSyntheticOffHours);
    }

    // Initialize Advanced Position Manager (shared, magic scoped)
    g_positionManager = new CAdvancedPositionManager();
    if(g_positionManager != NULL)
    {
        SPositionManagementConfig posConfig;
        posConfig.enableTrailingStop = true;
        posConfig.trailingStartPips = 20.0;
        posConfig.trailingStepPips = 5.0;
        posConfig.trailingDistancePips = 15.0;
        posConfig.enableBreakeven = true;
        posConfig.breakevenTriggerPips = 15.0;
        posConfig.breakevenBufferPips = 5.0;
        posConfig.enablePartialClose = true;
        posConfig.partialClose1Pips = 30.0;
        posConfig.partialClose1Percent = 50.0;
        posConfig.partialClose2Pips = 60.0;
        posConfig.partialClose2Percent = 25.0;
        posConfig.enableTimeBasedExit = false;
        posConfig.maxPositionHours = 24;

        g_positionManager.SetConfig(posConfig);
        g_positionManager.SetTradeManager(&tradeManager);
        g_positionManager.SetManagedMagic((long)InpMagicNumber);
        Print("[POSITION-MANAGER] Advanced position management enabled (magic scoped)");
    }

    // Initialize Neural Network Strategy per active symbol
    if(InpEnableAIMode && InpEnableNeuralNetwork)
    {
        ReleaseNeuralNetStrategies();
        int nnInitCount = 0;
        for(int i = 0; i < ArraySize(g_activePairs); i++)
        {
            if(InitializeNeuralNetForSymbol(g_activePairs[i], (ENUM_TIMEFRAMES)Period()))
                nnInitCount++;
        }

        neuralNetStrategy = GetNeuralNetForSymbol(_Symbol);
        if(neuralNetStrategy == NULL && ArraySize(g_neuralNetStrategies) > 0)
            neuralNetStrategy = g_neuralNetStrategies[0];

        Print("[AI-MODE] AI Mode enabled | NN: ", InpEnableNeuralNetwork, " | Transformer: ", InpEnableTransformer, 
              " | Ensemble: ", InpEnableEnsemble, " | Threshold: ", InpAIConfidenceThreshold,
              " | NN Managers: ", nnInitCount);
    }
    else if(InpEnableAIMode)
    {
        ReleaseNeuralNetStrategies();
        Print("[AI-MODE] AI Mode enabled but Neural Network disabled");
    }

    if(GetTotalActiveStrategyCount() <= 0)
    {
        Print("[CRITICAL] No active strategies registered. Enable at least one strategy or neural AI mode.");
        return INIT_FAILED;
    }

    if(InpEnableNNAttributionDiagnostics)
    {
        g_nnDiagEntryMapCount = 0;
        g_nnDiagCloseByIdCount = 0;
        g_nnDiagCloseFallbackCount = 0;
        g_nnDiagCloseMissCount = 0;
        g_nnDiagPartialCloseCount = 0;
        g_nnDiagLastSummaryTime = TimeCurrent();
        NNDiagLog("NN attribution diagnostics enabled");
    }

    if(!RunNNAttributionSelfTest())
    {
        Print("[NN-DIAG] Self-test failed; initialization aborted by diagnostic gate");
        return INIT_FAILED;
    }

    // Final system initialization
    systemInitialized = true;
    tradingEnabled = true;

    g_hbScansAttempted = 0;
    g_hbIntrabarScansExecuted = 0;
    g_hbNoSignalCount = 0;
    g_hbValidatorRejects = 0;
    g_hbRiskRejects = 0;
    g_hbTradesOpened = 0;
    g_hbQuietNoNewBar = 0;
    g_lastHeartbeatLogTime = TimeCurrent();
    g_lastNNHealthLogTime = TimeCurrent();

    // Initialize Dashboard
    g_dashboard.Initialize();
    
    EventSetTimer(1);
    Print("[MULTI-STRATEGY-EA] Initialization complete - EA is READY;");
    Print("[MULTI-STRATEGY-EA] ========================================");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Advisor Deinitialization                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    systemInitialized = false;
    tradingEnabled = false;

    // Kill the timer
    EventKillTimer();

    // Properly delete all dynamic objects to prevent memory leaks
    ReleaseEnterpriseManagers();
    
    if(g_signalValidator != NULL)
    {
        delete g_signalValidator;
        g_signalValidator = NULL;
    }
    
    if(g_positionManager != NULL)
    {
        delete g_positionManager;
        g_positionManager = NULL;
    }

    NNDiagPrintSummary("deinit");
    
    ReleaseNeuralNetStrategies();
    
    if(g_AIEngine != NULL)
    {
        delete g_AIEngine;
        g_AIEngine = NULL;
    }

    // Clear chart
    Comment("");

    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Shutdown complete - Memory cleaned");
    Print("[MULTI-STRATEGY-EA] ========================================");
}

//+------------------------------------------------------------------+
//| Get deinitialization reason text                                 |
//+------------------------------------------------------------------+
string GetDeInitReasonText(int reasonCode)
{
    switch(reasonCode)
    {
        case REASON_PROGRAM: return "EA terminated";
        case REASON_REMOVE: return "EA removed from chart";
        case REASON_RECOMPILE: return "EA recompiled";
        case REASON_CHARTCHANGE: return "Symbol or period changed";
        case REASON_CHARTCLOSE: return "Chart closed";
        case REASON_PARAMETERS: return "Input parameters changed";
        case REASON_ACCOUNT: return "Account changed";
        case REASON_TEMPLATE: return "New template applied";
        case REASON_INITFAILED: return "Initialization failed";
        case REASON_CLOSE: return "Terminal closed";
        default: return "Unknown reason";
    }
}

//+------------------------------------------------------------------+
//| Timer Handler - Processes trades when chart symbol is closed     |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Process trading logic via timer (runs every 1 second)
    // This ensures EA runs even when chart symbol (e.g., XAUUSD) is closed
    ProcessTradingLogic(true);  // true = called from timer
}

//+------------------------------------------------------------------+
//| Expert Advisor Tick Handler                                      |
//+------------------------------------------------------------------+
void OnTick()
{
    // Process trading logic via tick
    ProcessTradingLogic(false);  // false = called from tick
}

//+------------------------------------------------------------------+
//| Main Trading Logic - Called from both OnTick and OnTimer         |
//+------------------------------------------------------------------+
void ProcessTradingLogic(bool fromTimer)
{
    // First tick/timer detection
    static bool firstCall = true;
    static int callCount = 0;
    callCount++;

    if(firstCall)
    {
        PrintFormat("[DEBUG-PROCESS] First call received! System initialized: %s, Trading enabled: %s, Source: %s",
                   systemInitialized ? "YES" : "NO",
                   tradingEnabled ? "YES" : "NO",
                   fromTimer ? "TIMER" : "TICK");
        firstCall = false;
    }

    // Enhanced logging every 50 calls to show pipeline activity
    if(callCount % 50 == 0)
    {
        PrintFormat("[DEBUG-PROCESS] Call #%d - EA is processing normally (Source: %s)", callCount, fromTimer ? "TIMER" : "TICK");
        Print("[DEBUG-PROCESS] Call #", callCount, " Time: ", TimeCurrent());
        Print("[DEBUG-STATUS] Current symbol: ", _Symbol);

        // Show Enterprise Manager status
        int activeStrats = 0;
        int eaPositions = 0;

        if(ArraySize(g_enterpriseManagers) > 0)
        {
            activeStrats = GetTotalActiveStrategyCount();
            int activeBrainStrats = GetTotalActiveBrainStrategyCount();
            int activeCoreStrats = MathMax(0, activeStrats - activeBrainStrats);
            eaPositions = GetEAPositionCount();  // Count only THIS EA's positions
            int cooldownSecs = g_lastTradeTime > 0 ? (int)(TimeCurrent() - g_lastTradeTime) : 0;
            int managerCount = ArraySize(g_enterpriseManagers);
            Print("[ENTERPRISE-STATUS] Active strategies: ", activeStrats,
                  " (Core: ", activeCoreStrats, ", AI: ", activeBrainStrats, ")",
                  " | Managers: ", managerCount,
                  " | Cooldown: ", cooldownSecs, "s / ", InpMinSecondsBetweenTrades, "s");
            Print("[ENTERPRISE-STATUS] EA Positions: ", eaPositions, " / ", InpMaxPositionsTotal,
                  " | Account Total: ", PositionsTotal(),
                  " | Last trade: ", g_lastTradeTime > 0 ? TimeToString(g_lastTradeTime) : "Never");
        }
        
        // --- Update Dashboard ---
        g_dashboard.Update(activeStrats, eaPositions, accountBalance, accountEquity, &aiNextGenBrain, neuralNetStrategy);
    }

    if(InpEnableNNAttributionDiagnostics)
    {
        bool timeDue = (g_nnDiagLastSummaryTime == 0 || (TimeCurrent() - g_nnDiagLastSummaryTime) >= 300);
        if(callCount % 200 == 0 || timeDue)
            NNDiagPrintSummary("periodic");
    }

    if(!systemInitialized || !tradingEnabled)
    {
        PrintFormat("[DEBUG-PROCESS] EA blocked: System initialized: %s, Trading enabled: %s",
                   systemInitialized ? "YES" : "NO",
                   tradingEnabled ? "YES" : "NO");
        return;
    }

    // Check if trading is still allowed
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Print("[DEBUG-PROCESS] Trading permissions check failed!");
        Comment("Trading is DISABLED - Waiting for permissions...");
        return;
    }

    currentTime = TimeCurrent();

    // Refresh unified risk state (daily reset + adaptive risk level)
    unifiedRiskManager.RefreshRuntimeState();

    currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    accountEquity = currentEquity;

    // Update peak equity and drawdown
    if(currentEquity > peakEquity)
        peakEquity = currentEquity;

    if(peakEquity > 0)
        currentDrawdown = ((peakEquity - currentEquity) / peakEquity) * 100.0; // Standardized to 0-100 scale

    // Run online NN learning maintenance regardless of trade signal frequency.
    if(InpEnableAIMode && InpEnableNeuralNetwork)
    {
        for(int nnIdx = 0; nnIdx < ArraySize(g_neuralNetStrategies); nnIdx++)
        {
            CNeuralNetworkStrategy* nnRuntime = g_neuralNetStrategies[nnIdx];
            if(nnRuntime != NULL)
                nnRuntime.TickOnlineLearning();
        }
    }

    // Multi-symbol new-bar processing: each symbol has a dedicated strategy manager.
    bool anyNewBarDetected = false;
    bool symbolHasNewBar[];
    ArrayResize(symbolHasNewBar, ArraySize(g_activePairs));
    for(int i = 0; i < ArraySize(symbolHasNewBar); i++)
        symbolHasNewBar[i] = false;

    if(ArraySize(g_enterpriseManagers) > 0 && ArraySize(g_activePairs) > 0)
    {
        if(ArraySize(g_lastSymbolBarTimes) != ArraySize(g_activePairs))
        {
            ArrayResize(g_lastSymbolBarTimes, ArraySize(g_activePairs));
            ArrayInitialize(g_lastSymbolBarTimes, 0);
            ArrayResize(g_lastIntrabarScanTime, ArraySize(g_activePairs));
            ArrayInitialize(g_lastIntrabarScanTime, 0);
            for(int i = 0; i < ArraySize(symbolHasNewBar); i++)
                symbolHasNewBar[i] = true; // First cycle after resize should evaluate immediately
        }

        for(int symIdx = 0; symIdx < ArraySize(g_activePairs); symIdx++)
        {
            string symbolForBar = g_activePairs[symIdx];
            datetime currentBarTime = iTime(symbolForBar, (ENUM_TIMEFRAMES)Period(), 0);
            if(currentBarTime <= 0)
                continue;

            if(currentBarTime != g_lastSymbolBarTimes[symIdx])
            {
                g_lastSymbolBarTimes[symIdx] = currentBarTime;
                anyNewBarDetected = true;
                symbolHasNewBar[symIdx] = true;

                CEnterpriseStrategyManager* barManager = GetEnterpriseManagerForSymbol(symbolForBar);
                if(barManager != NULL)
                    barManager.OnNewBar(symbolForBar, (ENUM_TIMEFRAMES)Period());
            }
        }
    }

    if(anyNewBarDetected)
    {
        if(InpEnableAIMode && g_AIEngine != NULL)
            g_AIEngine.ProcessAdaptation();

        if(callCount % 100 == 0)
            Print("[DRAWINGS] OnNewBar processed for all managed symbols");
    }

    // Enterprise Mode Multi-Symbol Signal Generation
    // UNIFIED PIPELINE - All strategies including AI now go through here
    if(ArraySize(g_enterpriseManagers) > 0 && ArraySize(g_activePairs) > 0)
    {
        // Check cooldown to prevent chain trading
        datetime tickTime = TimeCurrent();
        int secondsSinceLastTrade = (int)(tickTime - g_lastTradeTime);
        bool canOpenNewTrades = true;

        if(secondsSinceLastTrade < InpMinSecondsBetweenTrades && g_lastTradeTime > 0)
        {
            canOpenNewTrades = false;
            if(callCount % 100 == 0)
                Print("[ENTERPRISE-BLOCKED] Cooldown active: ", secondsSinceLastTrade, " / ", InpMinSecondsBetweenTrades, " seconds");
        }

        // Check position limit - count only THIS EA's positions by magic number
        int eaPositions = GetEAPositionCount();
        if(eaPositions >= InpMaxPositionsTotal)
        {
            canOpenNewTrades = false;
            if(callCount % 100 == 0)  // Log occasionally to avoid spam
                Print("[ENTERPRISE-BLOCKED] Position limit reached: ", eaPositions, " / ", InpMaxPositionsTotal);
        }

        if(canOpenNewTrades)
        {
            // Evaluate each active symbol through its own symbol-bound enterprise manager.
            for(int symIdx = 0; symIdx < ArraySize(g_activePairs); symIdx++)
            {
                string currentSymbol = g_activePairs[symIdx];
                CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(currentSymbol);
                if(symbolManager == NULL)
                    continue;

                bool hasNewBar = symbolHasNewBar[symIdx];
                bool runIntrabarScan = false;
                if(!hasNewBar && InpEnableHybridCadence)
                {
                    bool chartScopeAllows = (!InpIntrabarChartSymbolOnly || currentSymbol == _Symbol);
                    if(chartScopeAllows)
                    {
                        datetime lastIntrabar = (symIdx < ArraySize(g_lastIntrabarScanTime)) ? g_lastIntrabarScanTime[symIdx] : 0;
                        int intrabarInterval = MathMax(1, InpIntrabarScanSeconds);
                        if(lastIntrabar == 0 || (tickTime - lastIntrabar) >= intrabarInterval)
                        {
                            runIntrabarScan = true;
                            if(symIdx < ArraySize(g_lastIntrabarScanTime))
                                g_lastIntrabarScanTime[symIdx] = tickTime;
                            g_hbIntrabarScansExecuted++;
                        }
                    }
                }

                if(InpSignalScanOnNewBarOnly && !hasNewBar && !runIntrabarScan)
                {
                    g_hbQuietNoNewBar++;
                    continue;
                }

                ENUM_SIGNAL_EVAL_MODE evalMode = runIntrabarScan ? EVAL_MODE_INTRABAR : EVAL_MODE_NEW_BAR;
                ENUM_VALIDATION_PROFILE validationProfile = runIntrabarScan ? VALIDATION_PROFILE_INTRABAR : VALIDATION_PROFILE_NEW_BAR;
                g_hbScansAttempted++;

                if(InpPortfolioMaxPositionsPerSymbol > 0)
                {
                    int symbolPositionCount = GetOpenPositionCountForSymbol(currentSymbol, false);
                    if(symbolPositionCount >= InpPortfolioMaxPositionsPerSymbol)
                    {
                        if(callCount % 100 == 0)
                            PrintFormat("[ENTERPRISE-BLOCKED] %s symbol position cap reached: %d / %d",
                                        currentSymbol, symbolPositionCount, InpPortfolioMaxPositionsPerSymbol);
                        continue;
                    }
                }

                // Get signal with confluence tracking (per-symbol analysis)
                double confidence = 0;
                int confluence = 0;
                ENUM_TRADE_SIGNAL enterpriseSignal = symbolManager.GetConsensusSignalForSymbolWithConfluenceMode(
                    currentSymbol, confidence, confluence, evalMode);

                if(enterpriseSignal == TRADE_SIGNAL_NONE)
                {
                    g_hbNoSignalCount++;
                    continue;
                }

                // Advanced signal validation
                bool signalApproved = false;
                if(enterpriseSignal != TRADE_SIGNAL_NONE && g_signalValidator != NULL)
                {
                    // Get ATR for validation
                    CIndicatorManager* indManager = CIndicatorManager::Instance();
                    int atrHandle = INVALID_HANDLE;
                    double atrValue = 0.0;
                    if(indManager != NULL)
                    {
                        atrHandle = indManager.GetATRHandle(currentSymbol, (ENUM_TIMEFRAMES)Period(), 14);
                        double atr[];
                        ArraySetAsSeries(atr, true);
                        if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
                            atrValue = atr[0];
                    }

                    // Validate signal
                    SSignalValidationResult validation = g_signalValidator.ValidateSignal(
                        currentSymbol, enterpriseSignal, confidence, confluence, atrValue, validationProfile);

                    if(!validation.isValid)
                    {
                        g_hbValidatorRejects++;
                        // IMPROVED: Always log rejections for debugging (was only every 50 calls)
                        Print("[SIGNAL-REJECTED] ", currentSymbol, " | Reason: ", validation.reason,
                              " | Confluence: ", confluence, " | Quality: ", DoubleToString(validation.qualityScore, 2),
                              " | Conf: ", DoubleToString(confidence, 2));
                        continue;  // Skip this signal
                    }

                    // Signal passed validation - proceed with trade
                    string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
                    Print("[SIGNAL-VALIDATED] ", currentSymbol, " | Signal: ", signalType,
                          " | Confidence: ", confidence, " | Confluence: ", confluence,
                          " | Quality: ", validation.qualityScore);

                    // Use validated confidence
                    confidence = validation.qualityScore;  // Use quality score as final confidence
                    signalApproved = true;
                }
                else if(enterpriseSignal != TRADE_SIGNAL_NONE && confidence >= InpAIConfidenceThreshold)
                {
                    // Fallback if validator not initialized
                    string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
                    Print("[ENTERPRISE] ", currentSymbol, " | Signal: ", signalType, " | Confidence: ", confidence, " | Confluence: ", confluence);
                    signalApproved = true;
                }

                // Execute trade if signal was approved
                if(signalApproved && enterpriseSignal != TRADE_SIGNAL_NONE)
                {
                    // Execute trade if risk checks pass
                    ENUM_ORDER_TYPE orderType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                    string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";

                    // Get current price
                    double entryPrice = (enterpriseSignal == TRADE_SIGNAL_BUY) ?
                                       SymbolInfoDouble(currentSymbol, SYMBOL_ASK) :
                                       SymbolInfoDouble(currentSymbol, SYMBOL_BID);

                    // Calculate ATR for adaptive SL/TP using IndicatorManager
                    CIndicatorManager* indManager = CIndicatorManager::Instance();
                    int atrHandle = INVALID_HANDLE;
                    if(indManager != NULL)
                        atrHandle = indManager.GetATRHandle(currentSymbol, (ENUM_TIMEFRAMES)Period(), 14);

                    double atr[];
                    ArraySetAsSeries(atr, true);
                    if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
                    {
                        // Use ATR-based SL/TP calculation (adaptive)
                        double atrValue = atr[0];
                        double pointValue = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);

                        // Check if this is a synthetic index (different pip calculation)
                        bool isSynthetic = (StringFind(currentSymbol, "Volatility") >= 0 ||
                                           StringFind(currentSymbol, "Boom") >= 0 ||
                                           StringFind(currentSymbol, "Crash") >= 0 ||
                                           StringFind(currentSymbol, "Step") >= 0);

                        double stopLossPips = 0;
                        if(isSynthetic)
                        {
                            // For synthetics: ATR is already in price units, convert carefully
                            // Use 1.5x ATR as SL, but convert to pips properly
                            stopLossPips = (atrValue * 1.5) / pointValue;
                        }
                        else
                        {
                            // For regular pairs: standard calculation
                            stopLossPips = (atrValue / pointValue) * 2.0;
                        }

                        double takeProfitPips = stopLossPips * 2.0;  // 2:1 RR ratio

                        // Clamp SL/TP to reasonable bounds based on price percentage
                        // Min SL: 0.5% of price, Max SL: 3.0% of price (tighter for safety)
                        double minSlPips = (entryPrice * 0.005) / pointValue;
                        double maxSlPips = (entryPrice * 0.03) / pointValue;

                        stopLossPips = MathMax(minSlPips, MathMin(maxSlPips, stopLossPips));
                        takeProfitPips = MathMin(stopLossPips * 2.0, maxSlPips * 2.0);

                        double proposedRisk = unifiedRiskManager.GetActiveRiskPerTradePercent();
                        if(proposedRisk <= 0.0)
                            proposedRisk = InpMaxRiskPerTrade;
                        currentRiskPerTrade = proposedRisk;

                        // Unified risk manager is the only pre-trade veto contract.
                        STradeValidationRequest tradeReq;
                        tradeReq.symbol = currentSymbol;
                        tradeReq.orderType = orderType;
                        tradeReq.lotSize = 0.0; // Lot size not known yet, validation gate will validate prelim checks
                        tradeReq.stopLossPips = stopLossPips;
                        tradeReq.takeProfitPips = takeProfitPips;
                        tradeReq.confidence = confidence;
                        tradeReq.strategy = "Enterprise AI";
                        tradeReq.reasoning = "Orchestrator consensus signal";
                        
                        // Pre-check risk with 0.01 lot to validate trade parameters first
                        tradeReq.lotSize = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN); 
                        
                        SValidationResult riskResult;
                        if(ApproveTradeByUnifiedRisk(tradeReq, "pre-size", riskResult))
                        {
                            SPositionSizingParams currentSizingParams = positionSizer.GetParameters();
                            currentSizingParams.riskPercent = proposedRisk;
                            if(!positionSizer.SetParameters(currentSizingParams))
                            {
                                Print("[RISK] Failed to apply adaptive sizing params - trade skipped");
                                continue;
                            }

                            // Calculate optimal lot size
                            double lotSize = positionSizer.CalculateOptimalPositionSize(currentSymbol, orderType, stopLossPips, confidence);

                            // Update request with actual lot size and re-validate
                            tradeReq.lotSize = lotSize;
                            if(!ApproveTradeByUnifiedRisk(tradeReq, "post-size", riskResult))
                                continue;
                            
                            // Validate the lot size and final risk approval
                            if(lotSize > 0)
                            {
                                string predictionId = "";
                                CNeuralNetworkStrategy* symbolNet = GetNeuralNetForSymbol(currentSymbol);
                                if(symbolNet == NULL)
                                    symbolNet = neuralNetStrategy;

                                if(symbolNet != NULL && InpEnableAIMode && InpEnableNeuralNetwork)
                                    symbolNet.ReservePredictionForSignal(enterpriseSignal, predictionId, 600);

                                string tradeComment = BuildTradeCommentWithPrediction("Enterprise AI Signal", predictionId);

                                // Execute through TradeManager to keep one authoritative execution stack
                                bool tradeSuccess = tradeManager.OpenPosition(
                                    currentSymbol,
                                    orderType,
                                    lotSize,
                                    entryPrice,
                                    stopLossPips,
                                    takeProfitPips,
                                    tradeComment,
                                    (uint)InpMagicNumber
                                );

                                // Check trade result
                                if(!tradeSuccess)
                                {
                                    if(symbolNet != NULL && predictionId != "")
                                        symbolNet.ReleasePredictionReservation(predictionId);

                                    int errorCode = GetLastError();
                                    Print("[TRADE-ERROR] Failed to execute ", signalType, " order on ", currentSymbol,
                                          " | Lot Size: ", lotSize, " | Error Code: ", errorCode);
                                }
                                else
                                {
                                    ulong ticket = tradeManager.GetLastTicket();
                                    double slPrice = tradeManager.CalculateStopLoss(currentSymbol, orderType, entryPrice, stopLossPips);
                                    double tpPrice = tradeManager.CalculateTakeProfit(currentSymbol, orderType, entryPrice, takeProfitPips);
                                    g_hbTradesOpened++;
                                    
                                    // Register realized risk usage after successful execution.
                                    unifiedRiskManager.RegisterExecutedTradeRisk(riskResult);

                                    // Update last trade time for cooldown
                                    g_lastTradeTime = tickTime;

                                    Print("[TRADE-SUCCESS] ", signalType, " order executed on ", currentSymbol,
                                          " | Lot Size: ", lotSize,
                                          " | SL: ", slPrice, " (", (int)stopLossPips, " pips)",
                                          " | TP: ", tpPrice, " (", (int)takeProfitPips, " pips)",
                                          " | Ticket: ", ticket);

                                    // Stop after first successful trade to enforce cooldown while still
                                    // allowing the rest of runtime management below in this cycle.
                                    break;
                                }
                            }
                            else
                            {
                                Print("[AI-GLOBAL] Invalid lot size calculated for ", currentSymbol, " - trade skipped");
                            }
                        }
                    }
                    // FIX: Removed IndicatorRelease(atrHandle) because handles from CIndicatorManager are shared/cached.
                    // Releasing them here invalidates the handle for other parts of the EA.
                }
            }
        }
    }

    datetime heartbeatNow = TimeCurrent();
    if(g_lastHeartbeatLogTime == 0 || (heartbeatNow - g_lastHeartbeatLogTime) >= 60)
    {
        PrintFormat("[HEARTBEAT] scans=%I64u | intrabar=%I64u | no_signal=%I64u | validator_reject=%I64u | risk_reject=%I64u | trades_opened=%I64u",
                    g_hbScansAttempted, g_hbIntrabarScansExecuted, g_hbNoSignalCount,
                    g_hbValidatorRejects, g_hbRiskRejects, g_hbTradesOpened);
        PrintFormat("[QUIET-REASONS] no_new_bar=%I64u | no_signal=%I64u | validator=%I64u | risk=%I64u",
                    g_hbQuietNoNewBar, g_hbNoSignalCount, g_hbValidatorRejects, g_hbRiskRejects);

        CIndicatorManager* indicatorManager = CIndicatorManager::Instance();
        if(indicatorManager != NULL)
            indicatorManager.ReleaseUnused(300);

        g_lastHeartbeatLogTime = heartbeatNow;
    }

    if(InpEnableAIMode && InpEnableNeuralNetwork &&
       (g_lastNNHealthLogTime == 0 || (heartbeatNow - g_lastNNHealthLogTime) >= 60))
    {
        for(int nnIdx = 0; nnIdx < ArraySize(g_neuralNetStrategies); nnIdx++)
        {
            CNeuralNetworkStrategy* nnHealth = g_neuralNetStrategies[nnIdx];
            if(nnHealth == NULL)
                continue;

            int observations = 0;
            int tradeLinkedLabels = 0;
            int pseudoLabels = 0;
            int pendingLabels = 0;
            int trainingSteps = 0;
            int checkpointWrites = 0;
            int epoch = 0;
            double lastLoss = 0.0;
            nnHealth.GetModelHealthStats(observations, tradeLinkedLabels, pseudoLabels, pendingLabels,
                                         trainingSteps, checkpointWrites, epoch, lastLoss);

            string nnSymbol = (nnIdx < ArraySize(g_neuralNetStrategySymbols)) ? g_neuralNetStrategySymbols[nnIdx] : "?";
            PrintFormat("[NN-HEALTH] %s | obs=%d | trade_labels=%d | pseudo_labels=%d | pending=%d | train_steps=%d | checkpoints=%d | epoch=%d | loss=%.6f",
                        nnSymbol, observations, tradeLinkedLabels, pseudoLabels, pendingLabels,
                        trainingSteps, checkpointWrites, epoch, lastLoss);
        }

        g_lastNNHealthLogTime = heartbeatNow;
    }

    // Advanced Position Management (trailing stops, break-even, partial closes)
    if(g_positionManager != NULL && PositionsTotal() > 0)
    {
        g_positionManager.ManageAllPositions();
    }

    // Emergency stop on excessive drawdown
    if(currentDrawdown > InpMaxDrawdown)
    {
        tradingEnabled = false;
        Alert("[EMERGENCY] Maximum drawdown exceeded! Trading halted!");
        Comment("EMERGENCY STOP - Drawdown: ", NormalizeDouble(currentDrawdown, 2), "%");

        // Close all positions
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionGetTicket(i) > 0)
            {
                if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
                {
                    tradeManager.ClosePosition(PositionGetTicket(i), "Emergency Stop");
                }
            }
        }
        return;
    }

    // Collect market data for AI analysis from unified risk + performance snapshots
    SUnifiedRiskSnapshot riskSnapshot = unifiedRiskManager.GetSnapshot();
    SPerformanceMetrics perfMetrics = performanceAnalytics.GetPerformanceMetrics();
    double globalMarketData[20];
    globalMarketData[0] = currentEquity;
    globalMarketData[1] = accountBalance;
    globalMarketData[2] = currentDrawdown;
    globalMarketData[3] = (double)PositionsTotal();
    globalMarketData[4] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    globalMarketData[5] = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    globalMarketData[6] = riskSnapshot.currentDrawdownPercent;
    globalMarketData[7] = perfMetrics.totalProfit;
    globalMarketData[8] = MathMax(0.0, -perfMetrics.totalProfit);
    globalMarketData[9] = (double)perfMetrics.winningTrades;
    globalMarketData[10] = (double)perfMetrics.losingTrades;
    globalMarketData[11] = perfMetrics.maxDrawdown;
    globalMarketData[12] = perfMetrics.winRate;
    globalMarketData[13] = (double)perfMetrics.totalTrades;

    // AI Market Assessment (Heuristic IntegrationHub removed)
    double globalAIPrediction = 0.0;
    string aiReasoning = "AI Orchestrator Active";

    // Update performance tracking
    UpdatePerformanceTracking();
}

//+------------------------------------------------------------------+
//| Trade Transaction Event Handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    // Attribute only this EA's deals to neural training feedback
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
    {
        if(HistoryDealSelect(trans.deal))
        {
            long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
            if(dealMagic == InpMagicNumber)
            {
                ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
                ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
                string dealComment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
                datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

                // Keep trade-time state synchronized even for externally managed closes/partials.
                if(dealTime > g_lastTradeTime)
                    g_lastTradeTime = dealTime;

                // Capture entry-time mapping from comment to position for exact close labeling
                if((dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT) && positionId > 0)
                {
                    string openPredictionId = ExtractPredictionIdFromComment(dealComment);
                    if(openPredictionId != "")
                    {
                        UpsertPredictionPositionMap(positionId, openPredictionId);
                        g_nnDiagEntryMapCount++;
                        NNDiagLog(StringFormat("Entry mapped | Symbol=%s | PositionID=%I64u | PredictionID=%s",
                                               trans.symbol, positionId, openPredictionId));
                    }
                    else
                    {
                        NNDiagLog(StringFormat("Entry without prediction ID | Symbol=%s | PositionID=%I64u | Comment=%s",
                                               trans.symbol, positionId, dealComment));
                    }
                }

                if((dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY || dealEntry == DEAL_ENTRY_INOUT) &&
                   InpEnableAIMode &&
                   InpEnableNeuralNetwork)
                {
                    double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                    double dealSwap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
                    double dealCommission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
                    double netProfit = dealProfit + dealSwap + dealCommission;
                    bool positionStillOpen = (positionId > 0 && IsPositionIdStillOpen(positionId));
                    string predictionIdFromComment = ExtractPredictionIdFromComment(dealComment);
                    string predictionIdFromMap = (positionId > 0) ? GetPredictionIdForPosition(positionId) : "";
                    string resolvedPredictionId = (predictionIdFromComment != "") ? predictionIdFromComment : predictionIdFromMap;
                    bool hasPredictionContext = (resolvedPredictionId != "");

                    // Partial close: defer labeling until full position close so NN gets complete trade P/L.
                    if(positionStillOpen)
                    {
                        if(positionId > 0 && hasPredictionContext)
                        {
                            AccumulatePendingCloseProfit(positionId, netProfit);

                            g_nnDiagPartialCloseCount++;
                            NNDiagLog(StringFormat("Partial close deferred | Symbol=%s | PositionID=%I64u | DealNet=%.2f",
                                                   trans.symbol, positionId, netProfit));
                        }
                    }
                    else
                    {
                        double totalNetProfit = netProfit;
                        if(positionId > 0 && hasPredictionContext)
                            totalNetProfit += ConsumePendingCloseProfit(positionId);

                        CNeuralNetworkStrategy* symbolNet = GetNeuralNetForSymbol(trans.symbol);
                        if(symbolNet == NULL)
                            symbolNet = neuralNetStrategy;

                        if(symbolNet != NULL && hasPredictionContext)
                        {
                            bool updatedById = false;
                            updatedById = symbolNet.UpdateTradeResultByPredictionId(resolvedPredictionId, totalNetProfit);

                            bool updatedByFallback = false;
                            if(!updatedById)
                                updatedByFallback = symbolNet.UpdateTradeResult(dealTime, totalNetProfit);

                            if(updatedById)
                            {
                                g_nnDiagCloseByIdCount++;
                                NNDiagLog(StringFormat("Close labeled by ID | Symbol=%s | PositionID=%I64u | PredictionID=%s | Net=%.2f",
                                                       trans.symbol, positionId, resolvedPredictionId, totalNetProfit));
                            }
                            else if(updatedByFallback)
                            {
                                g_nnDiagCloseFallbackCount++;
                                NNDiagLog(StringFormat("Close labeled by fallback | Symbol=%s | PositionID=%I64u | Net=%.2f",
                                                       trans.symbol, positionId, totalNetProfit));
                            }
                            else
                            {
                                g_nnDiagCloseMissCount++;
                                NNDiagLog(StringFormat("Close label miss | Symbol=%s | PositionID=%I64u | PredictionID=%s | Net=%.2f",
                                                       trans.symbol, positionId, resolvedPredictionId, totalNetProfit));
                            }
                        }
                        else if(symbolNet == NULL && hasPredictionContext)
                        {
                            g_nnDiagCloseMissCount++;
                            NNDiagLog(StringFormat("Close label miss: no NN instance | Symbol=%s | PositionID=%I64u",
                                                   trans.symbol, positionId));
                        }
                        else if(!hasPredictionContext)
                        {
                            NNDiagLog(StringFormat("Close skipped: no prediction context | Symbol=%s | PositionID=%I64u",
                                                   trans.symbol, positionId));
                        }

                        if(positionId > 0 && !IsPositionIdStillOpen(positionId))
                        {
                            RemovePredictionPositionMap(positionId);
                            ClearPendingCloseProfit(positionId);
                            NNDiagLog(StringFormat("Position map cleared | Symbol=%s | PositionID=%I64u",
                                                   trans.symbol, positionId));
                        }
                    }
                }
            }
        }
    }

    // Forward trade events to symbol-specific manager to avoid duplicated attribution.
    string txSymbol = trans.symbol;
    if(txSymbol == "" && trans.deal > 0 && HistoryDealSelect(trans.deal))
        txSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

    CEnterpriseStrategyManager* txManager = GetEnterpriseManagerForSymbol(txSymbol);
    if(txManager != NULL)
    {
        txManager.OnTradeTransaction(trans, request, result);
    }
    else if(g_enterpriseManager != NULL)
    {
        g_enterpriseManager.OnTradeTransaction(trans, request, result);
    }
}
