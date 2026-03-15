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
input bool InpEnableTrend = true;            // Enable Trend Strategy
input bool InpEnableFibonacci = true;        // Enable Fibonacci Strategy
input bool InpEnableElliottWave = true;      // Enable Elliott Wave Enhanced Strategy
input bool InpEnableSupportResistance = true; // Enable Support/Resistance + Trendlines
input bool InpEnableUnifiedICT = true;         // Enable Unified ICT Strategy
input bool InpEnableCandlestick = true;       // Enable Candlestick Patterns Strategy
input bool InpUseCuratedStrategySet = true;    // Enable curated production strategy subset
input bool InpEnableSoftQuarantine = true;     // Keep weak strategies loaded as feature/shadow contributors

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
input bool InpIntrabarChartSymbolOnly = false;        // Restrict intrabar scans to chart symbol
input bool InpIntrabarDynamicQuorumEnabled = true;    // Intrabar quorum adapts to eligible contributors
input double InpPipelineMinConfidence = 0.40;         // Base confidence floor for non-AI pipeline signals (lowered from 0.50 to fix pipeline blocking)
input double InpValidatorNewBarMinConfidence = 0.50;  // Post-consensus confidence floor on new-bar scans
input double InpValidatorIntrabarMinConfidence = 0.55; // Post-consensus confidence floor on intrabar scans
input double InpIntrabarSingleVoterMinConfidence = 0.55; // Min confidence for single-voter intrabar consensus
input double InpPipelineIntrabarConfidenceCap = 0.05; // Max weak-regime intrabar confidence threshold uplift
input bool InpPipelineEnableRegimeCostGate = true;    // Enable regime + microstructure cost gate before validator
input double InpPipelineMaxSpreadToAtrRatio = 0.25;   // Max spread/ATR ratio allowed by cost gate
input int InpPipelineSpreadShockCooldownSec = 30;     // Spread shock cooldown window
input double InpPipelineLateEntryZScoreLimit = 2.50;  // Late-entry outlier z-score veto limit
input int  InpDeadlockAttributionIntervalSec = 60;    // Deadlock attribution diagnostics interval in seconds
input bool InpIntrabarEligibilityMomentum = true;     // Intrabar eligibility for Momentum strategy
input bool InpIntrabarEligibilityUnifiedICT = true;   // Intrabar eligibility for Unified ICT strategy
input bool InpShadowMode = true;                      // Shadow mode: log virtual trades without sending orders
input bool InpEnableNNOnlineTraining = false;         // Enable online NN observation/labeling loop
input bool InpEnableNNWeightMutation = false;         // Enable live NN weight mutation (institutional default OFF)
input bool InpEnableNNPseudoLabeling = false;         // Enable pseudo-labeling when no trade-linked label exists
input int  InpNNPseudoLabelBarsAhead = 1;             // Pseudo-label horizon in bars
input int  InpNNSampleIntervalSeconds = 30;           // Observation sampling interval (seconds)
input int  InpNNCheckpointEveryLabeled = 10;          // Checkpoint every N newly labeled samples

//--- Execution & Emergency Controls
input group "Execution Safety"
input ENUM_ORDER_TYPE_FILLING InpOrderFillingMode = ORDER_FILLING_IOC; // Preferred order filling policy
input int InpTradeSlippagePoints = 10;                                  // Max slippage in points
input int InpProtectiveModifyCooldownSec = 5;                           // Minimum seconds between routine stop modifications
input bool InpEmergencyFlattenAllAccountPositions = true;               // Flatten account-wide positions on emergency stop
input int InpUnprotectedRemediationIntervalSec = 15;                    // Seconds between unprotected-position remediation sweeps
input int InpUnprotectedMaxRestoreAttempts = 3;                         // Max stop-restore attempts before forced close
input bool InpCloseUnprotectedOnRemediationFailure = true;              // Force close own unprotected positions after max attempts

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
input bool InpEnableClusterRiskGovernance = true; // Enable cluster-aware risk mutex/caps in risk gate
input bool InpEnableClusterMutex = true;          // Block opposing-cluster same-symbol stacking
input int  InpRiskMaxConcurrentPerCluster = 3;    // Maximum concurrent open positions per cluster
input double InpRiskMaxClusterExposurePct = 5.0;  // Maximum projected risk per cluster (%)

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
#include "Core\Strategy\StrategyBase.mqh"
#include "Strategies\SimpleMomentumStrategy.mqh"
#include "Core\Utils\SymbolContext.mqh"
#include "Core\Strategy\StrategyWrapper.mqh"
#include "AIModules\NextGenStrategyBrain.mqh"
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

// Advanced Signal Validation and Position Management
#include "Core\Signals\AdvancedSignalValidator.mqh"
#include "Core\Trading\AdvancedPositionManager.mqh"
#include "Core\Strategy\AIStrategyAdapter.mqh"
#include "Core\Strategy\TransformerAIStrategyAdapter.mqh"
#include "Core\Strategy\EnsembleAIStrategyAdapter.mqh"
#include "Core\Visualization\VisualDashboard.mqh"

//+------------------------------------------------------------------+
//| Forward declarations
//+------------------------------------------------------------------+
// Classes now included from separate files

//--- Global variables
CSymbolInfo globalSymbol;
CAccountInfo account;
CEnhancedErrorHandler errorHandler;
CUnifiedRiskManager unifiedRiskManager;
CPerformanceAnalytics performanceAnalytics;
CAIPerformanceFeedback aiFeedback;
CAIStrategyOrchestrator aiOrchestrator;
CUtilities utilities;

CNextGenStrategyBrain aiNextGenBrain;
CNeuralNetworkStrategy* neuralNetStrategy = NULL;
CNeuralNetworkStrategy* g_neuralNetStrategies[];
string g_neuralNetStrategySymbols[];
ulong g_predictionPositionIds[];
string g_predictionIdsByPosition[];
ulong g_pendingClosePositionIds[];
double g_pendingCloseNetProfit[];
CPositionSizer positionSizer;
CMarketAnalysis marketAnalysis;
CInstrumentRegistry instrumentRegistry;

CTradeManager tradeManager;
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
ulong g_hbShadowTrades = 0;
ulong g_hbQuietNoNewBar = 0;
ulong g_hbSignalsGenerated = 0;
ulong g_hbSignalsAfterPipeline = 0;
ulong g_hbSignalsAfterQuorum = 0;
ulong g_hbSignalsValidated = 0;
ulong g_hbSignalsRiskApproved = 0;
ulong g_hbSignalsSent = 0;

// Previous heartbeat snapshots for windowed conversion-rate logging
ulong g_prevHbScansAttempted = 0;
ulong g_prevHbNoSignalCount = 0;
ulong g_prevHbSignalsGenerated = 0;
ulong g_prevHbSignalsAfterPipeline = 0;
ulong g_prevHbSignalsAfterQuorum = 0;
ulong g_prevHbSignalsValidated = 0;
ulong g_prevHbSignalsRiskApproved = 0;
ulong g_prevHbSignalsSent = 0;

datetime g_lastHeartbeatLogTime = 0;
datetime g_lastNNHealthLogTime = 0;
datetime g_lastSignalEvalSecond = 0;
int g_symbolEvalStartIndex = 0;
datetime g_lastExternalCapacityLogTime = 0;
datetime g_lastUnprotectedRemediationAttempt = 0;
datetime g_lastNoSignalAlertTime = 0;
ulong g_unprotectedPositionTickets[];
int g_unprotectedPositionAttempts[];

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
    static string barKeys[];
    static datetime lastBarTimes[];
    datetime currentBarTime = iTime(symbolParam, timeframe, 0);
    string key = symbolParam + "|" + IntegerToString((int)timeframe);

    int keyIndex = -1;
    for(int i = 0; i < ArraySize(barKeys); i++)
    {
        if(barKeys[i] == key)
        {
            keyIndex = i;
            break;
        }
    }

    if(keyIndex < 0)
    {
        keyIndex = ArraySize(barKeys);
        ArrayResize(barKeys, keyIndex + 1);
        ArrayResize(lastBarTimes, keyIndex + 1);
        barKeys[keyIndex] = key;
        lastBarTimes[keyIndex] = 0;
    }

    if(currentBarTime != lastBarTimes[keyIndex])
    {
        lastBarTimes[keyIndex] = currentBarTime;
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

int FindUnprotectedTrackerIndex(const ulong ticket)
{
    for(int i = 0; i < ArraySize(g_unprotectedPositionTickets); i++)
    {
        if(g_unprotectedPositionTickets[i] == ticket)
            return i;
    }
    return -1;
}

int GetUnprotectedTrackerAttempts(const ulong ticket)
{
    int idx = FindUnprotectedTrackerIndex(ticket);
    if(idx < 0 || idx >= ArraySize(g_unprotectedPositionAttempts))
        return 0;
    return g_unprotectedPositionAttempts[idx];
}

void SetUnprotectedTrackerAttempts(const ulong ticket, const int attempts)
{
    int idx = FindUnprotectedTrackerIndex(ticket);
    if(idx < 0)
    {
        int size = ArraySize(g_unprotectedPositionTickets);
        ArrayResize(g_unprotectedPositionTickets, size + 1);
        ArrayResize(g_unprotectedPositionAttempts, size + 1);
        g_unprotectedPositionTickets[size] = ticket;
        g_unprotectedPositionAttempts[size] = MathMax(0, attempts);
        return;
    }

    g_unprotectedPositionAttempts[idx] = MathMax(0, attempts);
}

void ClearUnprotectedTrackerTicket(const ulong ticket)
{
    int idx = FindUnprotectedTrackerIndex(ticket);
    if(idx < 0)
        return;

    int last = ArraySize(g_unprotectedPositionTickets) - 1;
    if(last < 0)
        return;

    g_unprotectedPositionTickets[idx] = g_unprotectedPositionTickets[last];
    g_unprotectedPositionAttempts[idx] = g_unprotectedPositionAttempts[last];
    ArrayResize(g_unprotectedPositionTickets, last);
    ArrayResize(g_unprotectedPositionAttempts, last);
}

void CleanupUnprotectedTracker()
{
    for(int i = ArraySize(g_unprotectedPositionTickets) - 1; i >= 0; i--)
    {
        ulong ticket = g_unprotectedPositionTickets[i];
        if(ticket == 0 || !PositionSelectByTicket(ticket) || PositionGetDouble(POSITION_SL) > 0.0)
            ClearUnprotectedTrackerTicket(ticket);
    }
}

double BuildUnprotectedFallbackStopPoints(const string symbol, const double referencePrice)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    int stopLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double fallbackByStops = MathMax(50.0, (double)stopLevelPts * 2.0);
    double fallbackByPrice = (referencePrice > 0.0) ? ((referencePrice * 0.01) / point) : fallbackByStops;
    return MathMax(fallbackByStops, fallbackByPrice);
}

void AttemptUnprotectedPositionRemediation()
{
    int unprotectedDetected = unifiedRiskManager.GetUnprotectedPositionCount();
    if(unprotectedDetected <= 0)
    {
        CleanupUnprotectedTracker();
        return;
    }

    datetime nowTime = TimeCurrent();
    int remediationInterval = MathMax(5, InpUnprotectedRemediationIntervalSec);
    if(g_lastUnprotectedRemediationAttempt != 0 &&
       (nowTime - g_lastUnprotectedRemediationAttempt) < remediationInterval)
    {
        return;
    }
    g_lastUnprotectedRemediationAttempt = nowTime;
    CleanupUnprotectedTracker();

    int restoredCount = 0;
    int restoreFailedCount = 0;
    int forcedClosedCount = 0;
    int externalUnprotectedCount = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        if(PositionGetDouble(POSITION_SL) > 0.0)
        {
            ClearUnprotectedTrackerTicket(ticket);
            continue;
        }

        long positionMagic = PositionGetInteger(POSITION_MAGIC);
        if(positionMagic != InpMagicNumber)
        {
            externalUnprotectedCount++;
            continue;
        }

        string symbol = PositionGetString(POSITION_SYMBOL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        if(currentPrice <= 0.0)
        {
            currentPrice = (posType == POSITION_TYPE_BUY) ?
                           SymbolInfoDouble(symbol, SYMBOL_BID) :
                           SymbolInfoDouble(symbol, SYMBOL_ASK);
        }

        if(currentPrice <= 0.0)
        {
            restoreFailedCount++;
            SetUnprotectedTrackerAttempts(ticket, GetUnprotectedTrackerAttempts(ticket) + 1);
            continue;
        }

        double fallbackStopPoints = BuildUnprotectedFallbackStopPoints(symbol, currentPrice);
        double fallbackTakeProfitPoints = fallbackStopPoints * 2.0;
        ENUM_ORDER_TYPE syntheticOrderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        double newSL = tradeManager.CalculateStopLoss(symbol, syntheticOrderType, currentPrice, fallbackStopPoints);
        double newTP = tradeManager.CalculateTakeProfit(symbol, syntheticOrderType, currentPrice, fallbackTakeProfitPoints);

        if(newSL > 0.0 && tradeManager.ModifyPosition(ticket, newSL, newTP))
        {
            restoredCount++;
            ClearUnprotectedTrackerTicket(ticket);
            continue;
        }

        int attempts = GetUnprotectedTrackerAttempts(ticket) + 1;
        SetUnprotectedTrackerAttempts(ticket, attempts);
        restoreFailedCount++;

        int maxRestoreAttempts = MathMax(1, InpUnprotectedMaxRestoreAttempts);
        if(InpCloseUnprotectedOnRemediationFailure && attempts >= maxRestoreAttempts)
        {
            if(tradeManager.ClosePosition(ticket, "Unprotected SL remediation failure"))
            {
                forcedClosedCount++;
                ClearUnprotectedTrackerTicket(ticket);
            }
            else
            {
                PrintFormat("[RISK-UNPROTECTED] Forced close failed | ticket=%I64u | attempts=%d",
                            ticket, attempts);
            }
        }
    }

    int remainingUnprotected = unifiedRiskManager.GetUnprotectedPositionCount();
    PrintFormat("[RISK-UNPROTECTED] detected=%d | restored=%d | failed=%d | forced_closed=%d | external=%d | remaining=%d",
                unprotectedDetected, restoredCount, restoreFailedCount,
                forcedClosedCount, externalUnprotectedCount, remainingUnprotected);

    if(externalUnprotectedCount > 0)
    {
        PrintFormat("[RISK-UNPROTECTED] External unprotected positions are blocking entries (count=%d)",
                    externalUnprotectedCount);
    }
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

string NormalizeClusterCode(const string clusterCode)
{
    if(clusterCode == "T" || clusterCode == "R" || clusterCode == "S" || clusterCode == "N")
        return clusterCode;
    return "N";
}

string BuildClusterTaggedTradeComment(const string clusterCode, const string predictionId)
{
    string compactBase = "K:" + NormalizeClusterCode(clusterCode) + "|EA";
    return BuildTradeCommentWithPrediction(compactBase, predictionId);
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

    bool curatedMask[7];
    curatedMask[0] = true;  // Momentum
    curatedMask[1] = true;  // Trend
    curatedMask[2] = true;  // Fibonacci
    curatedMask[3] = true;  // Elliott Wave
    curatedMask[4] = true;  // Support/Resistance
    curatedMask[5] = true;  // Unified ICT
    curatedMask[6] = true;  // Candlestick

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

    if(InpEnableSoftQuarantine)
        PrintFormat("[CURATION] Soft-quarantine profile active (%d -> %d enabled, weak modules shadow/feature only)", enabledBefore, enabledAfter);
    else
        PrintFormat("[CURATION] Expanded primary profile active (%d -> %d enabled)", enabledBefore, enabledAfter);
    Print("[CURATION] Effective runtime strategy set: ", BuildEnabledStrategyList(strategyFlags));
}

void ApplyInstitutionalStrategyGovernance(CEnterpriseStrategyManager* manager,
                                          const string symbol,
                                          const bool &strategyFlags[])
{
    if(manager == NULL)
        return;

    // Primary live voters by policy
    if(ArraySize(strategyFlags) > 0 && strategyFlags[0])
        manager.SetStrategyGovernanceByName("Momentum", PRIMARY_ALPHA, TREND_CLUSTER, true, false);
    if(ArraySize(strategyFlags) > 1 && strategyFlags[1])
        manager.SetStrategyGovernanceByName("Trend", PRIMARY_ALPHA, TREND_CLUSTER, true, false);
    if(ArraySize(strategyFlags) > 5 && strategyFlags[5])
        manager.SetStrategyGovernanceByName("Unified ICT", PRIMARY_ALPHA, STRUCTURE_CLUSTER, true, false);

    // Soft-quarantined legacy pattern modules
    if(ArraySize(strategyFlags) > 2 && strategyFlags[2])
        manager.SetStrategyGovernanceByName("Fibonacci",
                                            CONTEXT_FEATURE,
                                            MEAN_REVERSION_CLUSTER,
                                            !InpEnableSoftQuarantine,
                                            InpEnableSoftQuarantine);
    if(ArraySize(strategyFlags) > 3 && strategyFlags[3])
        manager.SetStrategyGovernanceByName("Elliott Wave",
                                            SHADOW_RESEARCH,
                                            STRUCTURE_CLUSTER,
                                            !InpEnableSoftQuarantine,
                                            InpEnableSoftQuarantine);
    if(ArraySize(strategyFlags) > 4 && strategyFlags[4])
        manager.SetStrategyGovernanceByName("Support/Resistance",
                                            SHADOW_RESEARCH,
                                            MEAN_REVERSION_CLUSTER,
                                            !InpEnableSoftQuarantine,
                                            InpEnableSoftQuarantine);
    if(ArraySize(strategyFlags) > 6 && strategyFlags[6])
        manager.SetStrategyGovernanceByName("Candlestick",
                                            CONTEXT_FEATURE,
                                            STRUCTURE_CLUSTER,
                                            !InpEnableSoftQuarantine,
                                            InpEnableSoftQuarantine);

    // Intrabar eligibility only for explicitly approved low-latency contributors.
    if(ArraySize(strategyFlags) > 0 && strategyFlags[0])
        manager.SetStrategyIntrabarEligibilityByName("Momentum", InpIntrabarEligibilityMomentum);
    if(ArraySize(strategyFlags) > 1 && strategyFlags[1])
        manager.SetStrategyIntrabarEligibilityByName("Trend", false);
    if(ArraySize(strategyFlags) > 5 && strategyFlags[5])
        manager.SetStrategyIntrabarEligibilityByName("Unified ICT", InpIntrabarEligibilityUnifiedICT);

    PrintFormat("[STRATEGY-GOVERNANCE] %s | soft_quarantine=%s | primary_live={Momentum,Trend,Unified ICT}",
                symbol,
                InpEnableSoftQuarantine ? "true" : "false");
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

void GetAggregatedConsensusDiagnostics(ulong &rawNone,
                                       ulong &filteredOut,
                                       ulong &quorumFailed,
                                       ulong &intrabarNotEligible,
                                       ulong &signalsGenerated,
                                       ulong &signalsAfterPipeline,
                                       ulong &signalsAfterQuorum,
                                       ulong &momentumNone,
                                       ulong &momentumCooldown,
                                       ulong &momentumLowVolatility,
                                       ulong &momentumNoCrossover,
                                       ulong &momentumTrendMisaligned,
                                       ulong &momentumNotReady,
                                       ulong &uictNone,
                                       ulong &uictNeutralBias,
                                       ulong &uictOtherFilters,
                                       ulong &reasonTotal)
{
    rawNone = 0;
    filteredOut = 0;
    quorumFailed = 0;
    intrabarNotEligible = 0;
    signalsGenerated = 0;
    signalsAfterPipeline = 0;
    signalsAfterQuorum = 0;
    momentumNone = 0;
    momentumCooldown = 0;
    momentumLowVolatility = 0;
    momentumNoCrossover = 0;
    momentumTrendMisaligned = 0;
    momentumNotReady = 0;
    uictNone = 0;
    uictNeutralBias = 0;
    uictOtherFilters = 0;
    reasonTotal = 0;

    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        CEnterpriseStrategyManager* manager = g_enterpriseManagers[i];
        if(manager == NULL)
            continue;

        ulong managerRawNone = 0;
        ulong managerFilteredOut = 0;
        ulong managerQuorumFailed = 0;
        ulong managerIntrabarNotEligible = 0;
        ulong managerSignalsGenerated = 0;
        ulong managerSignalsAfterPipeline = 0;
        ulong managerSignalsAfterQuorum = 0;
        ulong managerMomentumNone = 0;
        ulong managerMomentumCooldown = 0;
        ulong managerMomentumLowVolatility = 0;
        ulong managerMomentumNoCrossover = 0;
        ulong managerMomentumTrendMisaligned = 0;
        ulong managerMomentumNotReady = 0;
        ulong managerUICTNone = 0;
        ulong managerUICTNeutralBias = 0;
        ulong managerUICTOtherFilters = 0;
        ulong managerReasonTotal = 0;
        manager.GetConsensusDiagnosticsSnapshot(managerRawNone,
                                               managerFilteredOut,
                                               managerQuorumFailed,
                                               managerIntrabarNotEligible,
                                               managerSignalsGenerated,
                                               managerSignalsAfterPipeline,
                                               managerSignalsAfterQuorum,
                                               managerMomentumNone,
                                               managerMomentumCooldown,
                                               managerMomentumLowVolatility,
                                               managerMomentumNoCrossover,
                                               managerMomentumTrendMisaligned,
                                               managerMomentumNotReady,
                                               managerUICTNone,
                                               managerUICTNeutralBias,
                                               managerUICTOtherFilters,
                                               managerReasonTotal);

        rawNone += managerRawNone;
        filteredOut += managerFilteredOut;
        quorumFailed += managerQuorumFailed;
        intrabarNotEligible += managerIntrabarNotEligible;
        signalsGenerated += managerSignalsGenerated;
        signalsAfterPipeline += managerSignalsAfterPipeline;
        signalsAfterQuorum += managerSignalsAfterQuorum;
        momentumNone += managerMomentumNone;
        momentumCooldown += managerMomentumCooldown;
        momentumLowVolatility += managerMomentumLowVolatility;
        momentumNoCrossover += managerMomentumNoCrossover;
        momentumTrendMisaligned += managerMomentumTrendMisaligned;
        momentumNotReady += managerMomentumNotReady;
        uictNone += managerUICTNone;
        uictNeutralBias += managerUICTNeutralBias;
        uictOtherFilters += managerUICTOtherFilters;
        reasonTotal += managerReasonTotal;
    }
}

void GetAggregatedRoleClusterDiagnostics(ulong &primarySignals,
                                         ulong &featureSignals,
                                         ulong &shadowSignals,
                                         ulong &voteSuppressed,
                                         ulong &trendClusterSignals,
                                         ulong &meanReversionClusterSignals,
                                         ulong &structureClusterSignals,
                                         ulong &noneClusterSignals)
{
    primarySignals = 0;
    featureSignals = 0;
    shadowSignals = 0;
    voteSuppressed = 0;
    trendClusterSignals = 0;
    meanReversionClusterSignals = 0;
    structureClusterSignals = 0;
    noneClusterSignals = 0;

    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        CEnterpriseStrategyManager* manager = g_enterpriseManagers[i];
        if(manager == NULL)
            continue;

        ulong managerPrimary = 0;
        ulong managerFeature = 0;
        ulong managerShadow = 0;
        ulong managerSuppressed = 0;
        ulong managerTrend = 0;
        ulong managerMeanRev = 0;
        ulong managerStructure = 0;
        ulong managerNone = 0;

        manager.GetRoleClusterDiagnosticsTotals(managerPrimary,
                                                managerFeature,
                                                managerShadow,
                                                managerSuppressed,
                                                managerTrend,
                                                managerMeanRev,
                                                managerStructure,
                                                managerNone);

        primarySignals += managerPrimary;
        featureSignals += managerFeature;
        shadowSignals += managerShadow;
        voteSuppressed += managerSuppressed;
        trendClusterSignals += managerTrend;
        meanReversionClusterSignals += managerMeanRev;
        structureClusterSignals += managerStructure;
        noneClusterSignals += managerNone;
    }
}

string GetDominantConsensusCause(const ulong rawNone,
                                 const ulong filteredOut,
                                 const ulong quorumFailed,
                                 const ulong intrabarNotEligible)
{
    string dominant = "none";
    ulong maxCount = 0;

    if(intrabarNotEligible > maxCount)
    {
        maxCount = intrabarNotEligible;
        dominant = "intrabar_not_eligible";
    }
    if(quorumFailed > maxCount)
    {
        maxCount = quorumFailed;
        dominant = "quorum_failed";
    }
    if(filteredOut > maxCount)
    {
        maxCount = filteredOut;
        dominant = "filtered_out";
    }
    if(rawNone > maxCount)
    {
        maxCount = rawNone;
        dominant = "raw_none";
    }

    return dominant;
}

string BuildQualifiedStrategyName(const string symbol, const string strategyName)
{
    return symbol + "::" + strategyName;
}

void RegisterManagerStrategiesWithOrchestrator(const string symbol, CEnterpriseStrategyManager* manager)
{
    if(!InpEnableAIMode || manager == NULL)
        return;

    for(int i = 0; i < manager.GetRegisteredStrategyCount(); i++)
    {
        string strategyName = manager.GetRegisteredStrategyName(i);
        double strategyWeight = manager.GetRegisteredStrategyWeight(i);
        string qualifiedName = BuildQualifiedStrategyName(symbol, strategyName);
        if(!aiOrchestrator.AddStrategy(qualifiedName, strategyWeight))
        {
            Print("[AI-ORCH] AddStrategy skipped/failed for ", qualifiedName);
        }
    }
}

void SyncOrchestratorWeightsToManagers()
{
    if(!InpEnableAIMode)
        return;

    int updates = 0;
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        CEnterpriseStrategyManager* manager = g_enterpriseManagers[i];
        if(manager == NULL)
            continue;

        string symbol = (i < ArraySize(g_enterpriseManagerSymbols)) ? g_enterpriseManagerSymbols[i] : "";
        if(symbol == "")
            continue;

        for(int s = 0; s < manager.GetRegisteredStrategyCount(); s++)
        {
            string localName = manager.GetRegisteredStrategyName(s);
            string qualifiedName = BuildQualifiedStrategyName(symbol, localName);

            SStrategyPerformance perf;
            if(aiOrchestrator.GetStrategyPerformance(qualifiedName, perf))
            {
                if(manager.UpdateStrategyWeightByName(localName, perf.weight))
                    updates++;
            }
        }
    }

    if(updates > 0)
        Print("[AI-ORCH] Synced adapted weights to enterprise managers: ", updates);
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

    nn.SetOnlineTrainingEnabled(InpEnableNNOnlineTraining);
    nn.SetWeightMutationEnabled(InpEnableNNWeightMutation);

    if(!nn.Initialize(symbol, timeframe))
    {
        Print("[AI-MODE] Neural Network initialization failed for ", symbol);
        delete nn;
        return false;
    }

    nn.ConfigureOnlineLearning(InpEnableNNOnlineTraining && InpEnableNNPseudoLabeling,
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
        else if(InpEnableAIMode)
        {
            string qualified = BuildQualifiedStrategyName(symbol, "Neural Network AI");
            if(!aiOrchestrator.AddStrategy(qualified, aiWeight))
                Print("[AI-ORCH] AddStrategy skipped/failed for ", qualified);
        }
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
        filters.minConfidence = MathMax(0.0, MathMin(1.0, InpPipelineMinConfidence));
        filters.intrabarConfidenceCap = MathMax(0.0, InpPipelineIntrabarConfidenceCap);
        filters.enableRegimeCostGate = InpPipelineEnableRegimeCostGate;
        filters.maxSpreadToAtrRatio = MathMax(0.01, InpPipelineMaxSpreadToAtrRatio);
        filters.spreadShockCooldownSeconds = MathMax(5, InpPipelineSpreadShockCooldownSec);
        filters.maxEntryRangeZScore = MathMax(0.5, InpPipelineLateEntryZScoreLimit);
        filters.maxVolatility = InpMaxVolatility;
        filters.minTrendStrength = (int)InpMinTrendStrength;
        manager.SetPipelineFilters(filters);
    }

    manager.SetMinQuorum(2);
    manager.SetIntrabarMinQuorum(2);
    manager.SetIntrabarDynamicQuorumEnabled(InpIntrabarDynamicQuorumEnabled);
    manager.SetIntrabarSingleVoterMinConfidence(InpIntrabarSingleVoterMinConfidence);
    manager.SetConsensusDiagnosticsIntervalSeconds(InpDeadlockAttributionIntervalSec);
    PrintFormat("[ENTERPRISE-CONFIG] %s | intrabar_dynamic_quorum=%s | single_voter_min_conf=%.2f | pipeline_min_conf=%.2f | validator_newbar_conf=%.2f | validator_intrabar_conf=%.2f | deadlock_diag_interval=%ds | intrabar_conf_cap=%.2f",
                symbol,
                InpIntrabarDynamicQuorumEnabled ? "true" : "false",
                InpIntrabarSingleVoterMinConfidence,
                MathMax(0.0, MathMin(1.0, InpPipelineMinConfidence)),
                MathMax(0.0, MathMin(1.0, InpValidatorNewBarMinConfidence)),
                MathMax(0.0, MathMin(1.0, InpValidatorIntrabarMinConfidence)),
                MathMax(10, InpDeadlockAttributionIntervalSec),
                MathMax(0.0, InpPipelineIntrabarConfidenceCap));
    Print("[CURATION] Effective strategy set for ", symbol, ": ", BuildEnabledStrategyList(strategyFlags));
    manager.AutoRegisterStrategies(strategyFlags);
    ApplyInstitutionalStrategyGovernance(manager, symbol, strategyFlags);

    if(InpEnableAIMode && InpEnableTransformer)
    {
        if(!manager.RegisterStrategy(new CTransformerAIStrategyAdapter(), "Transformer AI", true, 1.1, PERIOD_CURRENT, true))
            Print("[AI-MODE] WARNING: Failed to register Transformer adapter for ", symbol);
    }

    if(InpEnableAIMode && InpEnableEnsemble)
    {
        if(!manager.RegisterStrategy(new CEnsembleAIStrategyAdapter(), "Ensemble AI", true, 1.2, PERIOD_CURRENT, true))
            Print("[AI-MODE] WARNING: Failed to register Ensemble adapter for ", symbol);
    }

    RegisterManagerStrategiesWithOrchestrator(symbol, manager);

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

    tradeManager.SetOrderFillMode(InpOrderFillingMode);
    tradeManager.SetSlippage((uint)MathMax(1, InpTradeSlippagePoints));
    tradeManager.SetProtectiveModifyCooldownSeconds(InpProtectiveModifyCooldownSec);
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

    ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    if(marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
    {
        PrintFormat("[CRITICAL] Unsupported account margin mode: %s | EA requires hedging account semantics for magic-scoped lifecycle management",
                    EnumToString(marginMode));
        return INIT_FAILED;
    }
    PrintFormat("[EXECUTION-MODE] mode=%s | shadow_mode=%s | note=%s",
                InpShadowMode ? "SHADOW_ONLY" : "LIVE_SEND",
                InpShadowMode ? "true" : "false",
                InpShadowMode ? "orders will be simulated only" : "orders will be sent to broker");

    // AUDIT FIX: Gate AI subsystem initialization behind InpEnableAIMode
    if(InpEnableAIMode)
    {
        Print("[AI] Initializing AI subsystems...");

        if(!aiNextGenBrain.Initialize(Symbol(), Period()))
        {
            Print("[ERROR] Failed to initialize NextGen AI Brain");
            return INIT_FAILED;
        }
        Print("[AI] Runtime AI voters are adapter-owned and registered per symbol");
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

    if(!performanceAnalytics.Initialize())
    {
        Print("[CRITICAL] PerformanceAnalytics failed to initialize!");
        return INIT_FAILED;
    }
    Print("[INIT] PerformanceAnalytics initialized");

    if(!unifiedRiskManager.Initialize(unifiedRiskConfig, &performanceAnalytics))
    {
        Print("[CRITICAL] UnifiedRiskManager failed to initialize!");
        return INIT_FAILED;
    }
    unifiedRiskManager.ConfigureClusterGovernance(InpEnableClusterRiskGovernance,
                                                  MathMax(1, InpRiskMaxConcurrentPerCluster),
                                                  MathMax(0.1, InpRiskMaxClusterExposurePct),
                                                  InpEnableClusterMutex);
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
        if(symbolTradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
        {
            Print("[WARNING] Symbol ", sym, " is close-only - skipping");
            continue;
        }
        if(SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP) <= 0.0)
        {
            Print("[WARNING] Symbol ", sym, " has invalid volume step - skipping");
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
        g_signalValidator.SetValidationProfiles(2,
                                                0.68,
                                                MathMax(0.0, MathMin(1.0, InpValidatorNewBarMinConfidence)),
                                                1,
                                                0.75,
                                                MathMax(0.0, MathMin(1.0, InpValidatorIntrabarMinConfidence)));
        g_signalValidator.SetMaxSpreadMultiplier(2.0);
        g_signalValidator.EnableTimeFilter(true, 1, 22);
        g_signalValidator.EnableSessionFilter(true, true, true, true);
        g_signalValidator.EnableVolatilityFilter(true, 0.0, 5.0);
        g_signalValidator.EnableSpreadFilter(true, 2.0);
        g_signalValidator.ConfigureCostViability(MathMax(0.01, InpPipelineMaxSpreadToAtrRatio),
                                                 true,
                                                 2.5,
                                                 MathMax(5, InpPipelineSpreadShockCooldownSec));
        g_signalValidator.SetAllowSyntheticOffHours(InpAllowSyntheticOffHours);
        PrintFormat("[SIGNAL-VALIDATOR] Advanced signal validation enabled | Synthetic Off-Hours: %s | NewBarConf: %.2f | IntrabarConf: %.2f",
                    InpAllowSyntheticOffHours ? "true" : "false",
                    MathMax(0.0, MathMin(1.0, InpValidatorNewBarMinConfidence)),
                    MathMax(0.0, MathMin(1.0, InpValidatorIntrabarMinConfidence)));
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
              " | NN Managers: ", nnInitCount,
              " | NN Online: ", InpEnableNNOnlineTraining,
              " | NN WeightMutation: ", InpEnableNNWeightMutation,
              " | NN Pseudo: ", InpEnableNNPseudoLabeling);
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
    g_hbShadowTrades = 0;
    g_hbQuietNoNewBar = 0;
    g_hbSignalsGenerated = 0;
    g_hbSignalsAfterPipeline = 0;
    g_hbSignalsAfterQuorum = 0;
    g_hbSignalsValidated = 0;
    g_hbSignalsRiskApproved = 0;
    g_hbSignalsSent = 0;
    g_prevHbScansAttempted = 0;
    g_prevHbNoSignalCount = 0;
    g_prevHbSignalsGenerated = 0;
    g_prevHbSignalsAfterPipeline = 0;
    g_prevHbSignalsAfterQuorum = 0;
    g_prevHbSignalsValidated = 0;
    g_prevHbSignalsRiskApproved = 0;
    g_prevHbSignalsSent = 0;
    g_lastHeartbeatLogTime = TimeCurrent();
    g_lastNNHealthLogTime = TimeCurrent();
    g_lastSignalEvalSecond = 0;
    g_symbolEvalStartIndex = 0;
    g_lastExternalCapacityLogTime = 0;
    g_lastUnprotectedRemediationAttempt = 0;
    g_lastNoSignalAlertTime = 0;
    ArrayResize(g_unprotectedPositionTickets, 0);
    ArrayResize(g_unprotectedPositionAttempts, 0);

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
    ArrayResize(g_unprotectedPositionTickets, 0);
    ArrayResize(g_unprotectedPositionAttempts, 0);
    
    if(g_AIEngine != NULL)
    {
        delete g_AIEngine;
        g_AIEngine = NULL;
    }

    CIndicatorManager::DestroyInstance();

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
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        Print("[DEBUG-PROCESS] Terminal disconnected - postponing signal evaluation");
        Comment("Terminal disconnected - waiting for reconnect...");
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

    // Deterministic remediation loop for unprotected-position veto states.
    AttemptUnprotectedPositionRemediation();
    bool unprotectedPositionsActive = unifiedRiskManager.HasUnprotectedPositions();
    if(unprotectedPositionsActive && callCount % 50 == 0)
    {
        Print("[RISK-UNPROTECTED] New entries paused until stop protection is restored");
    }

    // Run online NN learning maintenance regardless of trade signal frequency.
    if(InpEnableAIMode && InpEnableNeuralNetwork && InpEnableNNOnlineTraining)
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
        {
            g_AIEngine.ProcessAdaptation();
            SyncOrchestratorWeightsToManagers();
        }

        if(callCount % 100 == 0)
            Print("[DRAWINGS] OnNewBar processed for all managed symbols");
    }

    // Deterministic event separation: run signal generation at most once per second
    // even when both OnTick and OnTimer are active.
    bool allowSignalEvaluation = true;
    datetime signalEvalNow = TimeCurrent();
    if(g_lastSignalEvalSecond == signalEvalNow)
        allowSignalEvaluation = false;
    else
        g_lastSignalEvalSecond = signalEvalNow;
    if(!allowSignalEvaluation)
        g_hbQuietNoNewBar++;

    // Enterprise Mode Multi-Symbol Signal Generation
    // UNIFIED PIPELINE - All strategies including AI now go through here
    if(allowSignalEvaluation && ArraySize(g_enterpriseManagers) > 0 && ArraySize(g_activePairs) > 0)
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

        if(unprotectedPositionsActive)
            canOpenNewTrades = false;

        if(canOpenNewTrades)
        {
            // Evaluate each active symbol through its own symbol-bound enterprise manager.
            int symbolCount = ArraySize(g_activePairs);
            int rotationStart = 0;
            if(symbolCount > 0)
            {
                if(g_symbolEvalStartIndex < 0)
                    g_symbolEvalStartIndex = 0;
                rotationStart = g_symbolEvalStartIndex % symbolCount;
                g_symbolEvalStartIndex = (g_symbolEvalStartIndex + 1) % symbolCount;
            }

            for(int scanOffset = 0; scanOffset < symbolCount; scanOffset++)
            {
                int symIdx = (rotationStart + scanOffset) % symbolCount;
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
                        int eaSymbolPositionCount = GetOpenPositionCountForSymbol(currentSymbol, true);
                        int externalSymbolPositions = MathMax(0, symbolPositionCount - eaSymbolPositionCount);
                        if(callCount % 100 == 0)
                            PrintFormat("[ENTERPRISE-BLOCKED] %s symbol position cap reached: total=%d / %d | ea=%d | external=%d",
                                        currentSymbol, symbolPositionCount, InpPortfolioMaxPositionsPerSymbol,
                                        eaSymbolPositionCount, externalSymbolPositions);

                        if(externalSymbolPositions > 0)
                        {
                            datetime capLogNow = TimeCurrent();
                            if(g_lastExternalCapacityLogTime == 0 || (capLogNow - g_lastExternalCapacityLogTime) >= 60)
                            {
                                PrintFormat("[CAPACITY-EXTERNAL] %s blocked by non-EA positions | external=%d | ea=%d | total=%d | cap=%d | magic=%d",
                                            currentSymbol, externalSymbolPositions, eaSymbolPositionCount,
                                            symbolPositionCount, InpPortfolioMaxPositionsPerSymbol, InpMagicNumber);
                                g_lastExternalCapacityLogTime = capLogNow;
                            }
                        }
                        continue;
                    }
                }

                // Get signal with confluence tracking (per-symbol analysis)
                double confidence = 0;
                int confluence = 0;
                ENUM_TRADE_SIGNAL enterpriseSignal = symbolManager.GetConsensusSignalForSymbolWithConfluenceMode(
                    currentSymbol, confidence, confluence, evalMode);

                int cycleSignalsGenerated = 0;
                int cycleSignalsAfterPipeline = 0;
                bool cycleSignalAfterQuorum = false;
                symbolManager.GetLastCycleFunnel(cycleSignalsGenerated, cycleSignalsAfterPipeline, cycleSignalAfterQuorum);
                g_hbSignalsGenerated += (ulong)MathMax(0, cycleSignalsGenerated);
                g_hbSignalsAfterPipeline += (ulong)MathMax(0, cycleSignalsAfterPipeline);
                if(cycleSignalAfterQuorum)
                    g_hbSignalsAfterQuorum++;

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
                    g_hbSignalsValidated++;

                    // Use validated confidence
                    confidence = validation.qualityScore;  // Use quality score as final confidence
                    signalApproved = true;
                }
                else if(enterpriseSignal != TRADE_SIGNAL_NONE)
                {
                    double fallbackMinConfidence = (validationProfile == VALIDATION_PROFILE_INTRABAR)
                                                  ? MathMax(0.0, MathMin(1.0, InpValidatorIntrabarMinConfidence))
                                                  : MathMax(0.0, MathMin(1.0, InpValidatorNewBarMinConfidence));
                    if(confidence >= fallbackMinConfidence)
                    {
                        // Fallback if validator not initialized
                        string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
                        Print("[ENTERPRISE] ", currentSymbol, " | Signal: ", signalType,
                              " | Confidence: ", confidence,
                              " | Confluence: ", confluence,
                              " | FallbackMinConf: ", DoubleToString(fallbackMinConfidence, 2));
                        g_hbSignalsValidated++;
                        signalApproved = true;
                    }
                    else
                    {
                        Print("[SIGNAL-REJECTED] ", currentSymbol,
                              " | Reason: Validator unavailable and confidence below fallback threshold",
                              " | Confluence: ", confluence,
                              " | Conf: ", DoubleToString(confidence, 2),
                              " | Required: ", DoubleToString(fallbackMinConfidence, 2));
                    }
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
                    double atrValue = 0.0;
                    bool atrReady = (atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atr) > 0 && atr[0] > 0.0);
                    if(atrReady)
                        atrValue = atr[0];

                    double pointValue = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);
                    if(pointValue <= 0.0)
                        pointValue = 0.00001;

                    // Check if this is a synthetic index (different pip calculation)
                    bool isSynthetic = (StringFind(currentSymbol, "Volatility") >= 0 ||
                                       StringFind(currentSymbol, "Boom") >= 0 ||
                                       StringFind(currentSymbol, "Crash") >= 0 ||
                                       StringFind(currentSymbol, "Step") >= 0);

                    double stopLossPips = 0.0;
                    if(atrReady)
                    {
                        // Use ATR-based SL/TP calculation (adaptive)
                        if(isSynthetic)
                        {
                            // For synthetics: ATR is already in price units, convert carefully
                            stopLossPips = (atrValue * 1.5) / pointValue;
                        }
                        else
                        {
                            // For regular pairs: standard calculation
                            stopLossPips = (atrValue / pointValue) * 2.0;
                        }
                    }
                    else
                    {
                        // Gap/stress fallback: derive a deterministic stop distance from broker constraints + price percent.
                        int stopLevelPts = (int)SymbolInfoInteger(currentSymbol, SYMBOL_TRADE_STOPS_LEVEL);
                        double fallbackByStopLevel = MathMax(30.0, (double)stopLevelPts * 2.0);
                        double fallbackByPrice = (entryPrice * (isSynthetic ? 0.003 : 0.01)) / pointValue;
                        stopLossPips = MathMax(fallbackByStopLevel, fallbackByPrice);
                        PrintFormat("[RISK-FALLBACK] ATR unavailable for %s | using fallback stop distance %.1f points",
                                    currentSymbol, stopLossPips);
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

                    string contributorSummary = "";
                    string strategyRoleTag = "PRIMARY_ALPHA";
                    string strategyClusterTag = "NONE";
                    string strategyClusterCode = "N";
                    if(!symbolManager.GetLastSignalExecutionContext(strategyRoleTag,
                                                                    strategyClusterTag,
                                                                    strategyClusterCode,
                                                                    contributorSummary))
                    {
                        strategyRoleTag = "PRIMARY_ALPHA";
                        strategyClusterTag = "NONE";
                        strategyClusterCode = "N";
                    }

                    if(contributorSummary == "")
                    {
                        string contributorsFallback[];
                        symbolManager.GetLastSignalContributors(contributorsFallback);
                        for(int c = 0; c < ArraySize(contributorsFallback); c++)
                        {
                            if(contributorsFallback[c] == "")
                                continue;
                            if(StringLen(contributorSummary) > 0)
                                contributorSummary += ",";
                            contributorSummary += contributorsFallback[c];
                        }
                    }

                    // Unified risk manager is the only pre-trade veto contract.
                    STradeValidationRequest tradeReq;
                    tradeReq.symbol = currentSymbol;
                    tradeReq.orderType = orderType;
                    tradeReq.lotSize = 0.0; // Lot size not known yet, validation gate will validate prelim checks
                    tradeReq.stopLossPips = stopLossPips;
                    tradeReq.takeProfitPips = takeProfitPips;
                    tradeReq.confidence = confidence;
                    tradeReq.strategy = "EnterpriseConsensus";
                    tradeReq.reasoning = StringFormat("role=%s | cluster=%s | contributors=%s",
                                                      strategyRoleTag,
                                                      strategyClusterTag,
                                                      contributorSummary);
                    tradeReq.strategyRole = strategyRoleTag;
                    tradeReq.strategyCluster = strategyClusterTag;
                    tradeReq.contributorContext = contributorSummary;
                    tradeReq.clusterCode = strategyClusterCode;
                    tradeReq.requestTime = TimeCurrent();
                    
                    // Pre-check risk with minimum lot to validate trade parameters first
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
                            g_hbSignalsRiskApproved++;
                            
                            // Validate the lot size and final risk approval
                            if(lotSize > 0)
                            {
                                double slPrice = tradeManager.CalculateStopLoss(currentSymbol, orderType, entryPrice, stopLossPips);
                                double tpPrice = tradeManager.CalculateTakeProfit(currentSymbol, orderType, entryPrice, takeProfitPips);

                                if(InpShadowMode)
                                {
                                    g_hbShadowTrades++;
                                    g_hbSignalsSent++;
                                    g_lastTradeTime = tickTime;
                                    PrintFormat("[SHADOW-TRADE] %s | %s | lot=%.2f | conf=%.2f | confluence=%d | role=%s | cluster=%s | contributors=%s | SL=%.5f | TP=%.5f",
                                                currentSymbol, signalType, lotSize, confidence, confluence,
                                                strategyRoleTag, strategyClusterTag, contributorSummary, slPrice, tpPrice);

                                    // Stop after first shadow trade to preserve cooldown semantics.
                                    break;
                                }

                                string predictionId = "";
                                CNeuralNetworkStrategy* symbolNet = GetNeuralNetForSymbol(currentSymbol);
                                if(symbolNet == NULL)
                                    symbolNet = neuralNetStrategy;

                                if(symbolNet != NULL && InpEnableAIMode && InpEnableNeuralNetwork && InpEnableNNOnlineTraining)
                                    symbolNet.ReservePredictionForSignal(enterpriseSignal, predictionId, 600);

                                string tradeComment = BuildClusterTaggedTradeComment(strategyClusterCode, predictionId);

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
                                    uint brokerRetcode = tradeManager.GetLastRetcode();
                                    uint requestId = tradeManager.GetLastRequestId();
                                    Print("[TRADE-ERROR] Failed to execute ", signalType, " order on ", currentSymbol,
                                          " | Lot Size: ", lotSize,
                                          " | Error Code: ", errorCode,
                                          " | Retcode: ", brokerRetcode,
                                          " | RequestID: ", requestId);
                                }
                                else
                                {
                                    ulong ticket = tradeManager.GetLastTicket();
                                    double brokerPrice = tradeManager.GetLastRequestedPrice();
                                    double brokerSL = tradeManager.GetLastRequestedStopLoss();
                                    double brokerTP = tradeManager.GetLastRequestedTakeProfit();
                                    uint requestId = tradeManager.GetLastRequestId();
                                    g_hbTradesOpened++;
                                    g_hbSignalsSent++;
                                    
                                    // Register realized risk usage after successful execution.
                                    unifiedRiskManager.RegisterExecutedTradeRisk(riskResult);

                                    // Update last trade time for cooldown
                                    g_lastTradeTime = tickTime;

                                    Print("[TRADE-SUCCESS] ", signalType, " order executed on ", currentSymbol,
                                          " | Lot Size: ", lotSize,
                                          " | Price: ", brokerPrice,
                                          " | SL: ", brokerSL, " (", (int)stopLossPips, " pips)",
                                          " | TP: ", brokerTP, " (", (int)takeProfitPips, " pips)",
                                          " | Ticket: ", ticket,
                                          " | RequestID: ", requestId,
                                          " | Role: ", strategyRoleTag,
                                          " | Cluster: ", strategyClusterTag,
                                          " | Contributors: ", contributorSummary);

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
                    // FIX: Removed IndicatorRelease(atrHandle) because handles from CIndicatorManager are shared/cached.
                    // Releasing them here invalidates the handle for other parts of the EA.
                }
            }
        }
    }

    datetime heartbeatNow = TimeCurrent();
    int heartbeatIntervalSec = MathMax(10, InpDeadlockAttributionIntervalSec);
    if(g_lastHeartbeatLogTime == 0 || (heartbeatNow - g_lastHeartbeatLogTime) >= heartbeatIntervalSec)
    {
        ulong diagRawNone = 0;
        ulong diagFilteredOut = 0;
        ulong diagQuorumFailed = 0;
        ulong diagIntrabarNotEligible = 0;
        ulong diagSignalsGenerated = 0;
        ulong diagSignalsAfterPipeline = 0;
        ulong diagSignalsAfterQuorum = 0;
        ulong diagMomentumNone = 0;
        ulong diagMomentumCooldown = 0;
        ulong diagMomentumLowVolatility = 0;
        ulong diagMomentumNoCrossover = 0;
        ulong diagMomentumTrendMisaligned = 0;
        ulong diagMomentumNotReady = 0;
        ulong diagUICTNone = 0;
        ulong diagUICTNeutralBias = 0;
        ulong diagUICTOtherFilters = 0;
        ulong diagReasonTotal = 0;
        ulong rolePrimarySignals = 0;
        ulong roleFeatureSignals = 0;
        ulong roleShadowSignals = 0;
        ulong roleVoteSuppressed = 0;
        ulong clusterTrendSignals = 0;
        ulong clusterMeanReversionSignals = 0;
        ulong clusterStructureSignals = 0;
        ulong clusterNoneSignals = 0;
        GetAggregatedConsensusDiagnostics(diagRawNone,
                                          diagFilteredOut,
                                          diagQuorumFailed,
                                          diagIntrabarNotEligible,
                                          diagSignalsGenerated,
                                          diagSignalsAfterPipeline,
                                          diagSignalsAfterQuorum,
                                          diagMomentumNone,
                                          diagMomentumCooldown,
                                          diagMomentumLowVolatility,
                                          diagMomentumNoCrossover,
                                          diagMomentumTrendMisaligned,
                                          diagMomentumNotReady,
                                          diagUICTNone,
                                          diagUICTNeutralBias,
                                          diagUICTOtherFilters,
                                          diagReasonTotal);
        GetAggregatedRoleClusterDiagnostics(rolePrimarySignals,
                                            roleFeatureSignals,
                                            roleShadowSignals,
                                            roleVoteSuppressed,
                                            clusterTrendSignals,
                                            clusterMeanReversionSignals,
                                            clusterStructureSignals,
                                            clusterNoneSignals);

        PrintFormat("[HEARTBEAT] scans=%I64u | intrabar=%I64u | no_signal=%I64u | validator_reject=%I64u | risk_reject=%I64u | trades_opened=%I64u | shadow_trades=%I64u",
                    g_hbScansAttempted, g_hbIntrabarScansExecuted, g_hbNoSignalCount,
                    g_hbValidatorRejects, g_hbRiskRejects, g_hbTradesOpened, g_hbShadowTrades);
        PrintFormat("[HEARTBEAT-FUNNEL] signals_generated=%I64u | signals_after_pipeline=%I64u | signals_after_quorum=%I64u | signals_validated=%I64u | signals_risk_approved=%I64u | shadow_or_live_sent=%I64u",
                    g_hbSignalsGenerated,
                    g_hbSignalsAfterPipeline,
                    g_hbSignalsAfterQuorum,
                    g_hbSignalsValidated,
                    g_hbSignalsRiskApproved,
                    g_hbSignalsSent);
        PrintFormat("[CONSENSUS-SNAPSHOT] generated=%I64u | after_pipeline=%I64u | after_quorum=%I64u | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u | reason_total=%I64u",
                    diagSignalsGenerated,
                    diagSignalsAfterPipeline,
                    diagSignalsAfterQuorum,
                    diagRawNone,
                    diagFilteredOut,
                    diagQuorumFailed,
                    diagIntrabarNotEligible,
                    diagReasonTotal);
        PrintFormat("[STRATEGY-REJECTS] momentum_none=%I64u | momentum_cooldown=%I64u | momentum_low_vol=%I64u | momentum_no_crossover=%I64u | momentum_trend_misaligned=%I64u | momentum_not_ready=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u | uict_other_filters=%I64u",
                    diagMomentumNone,
                    diagMomentumCooldown,
                    diagMomentumLowVolatility,
                    diagMomentumNoCrossover,
                    diagMomentumTrendMisaligned,
                    diagMomentumNotReady,
                    diagUICTNone,
                    diagUICTNeutralBias,
                    diagUICTOtherFilters);
        PrintFormat("[ROLE-CLUSTER] primary=%I64u | feature=%I64u | shadow=%I64u | suppressed=%I64u | trend=%I64u | mean_reversion=%I64u | structure=%I64u | none=%I64u",
                    rolePrimarySignals,
                    roleFeatureSignals,
                    roleShadowSignals,
                    roleVoteSuppressed,
                    clusterTrendSignals,
                    clusterMeanReversionSignals,
                    clusterStructureSignals,
                    clusterNoneSignals);
        PrintFormat("[QUIET-REASONS] no_new_bar=%I64u | no_signal=%I64u | validator=%I64u | risk=%I64u",
                    g_hbQuietNoNewBar, g_hbNoSignalCount, g_hbValidatorRejects, g_hbRiskRejects);

        ulong windowScans = g_hbScansAttempted - g_prevHbScansAttempted;
        ulong windowNoSignal = g_hbNoSignalCount - g_prevHbNoSignalCount;
        ulong windowGenerated = g_hbSignalsGenerated - g_prevHbSignalsGenerated;
        ulong windowAfterPipeline = g_hbSignalsAfterPipeline - g_prevHbSignalsAfterPipeline;
        ulong windowAfterQuorum = g_hbSignalsAfterQuorum - g_prevHbSignalsAfterQuorum;
        ulong windowValidated = g_hbSignalsValidated - g_prevHbSignalsValidated;
        ulong windowRiskApproved = g_hbSignalsRiskApproved - g_prevHbSignalsRiskApproved;
        ulong windowSent = g_hbSignalsSent - g_prevHbSignalsSent;

        double rateAfterPipeline = (windowGenerated > 0) ? (100.0 * (double)windowAfterPipeline / (double)windowGenerated) : 0.0;
        double rateAfterQuorum = (windowAfterPipeline > 0) ? (100.0 * (double)windowAfterQuorum / (double)windowAfterPipeline) : 0.0;
        double rateValidated = (windowAfterQuorum > 0) ? (100.0 * (double)windowValidated / (double)windowAfterQuorum) : 0.0;
        double rateRiskApproved = (windowValidated > 0) ? (100.0 * (double)windowRiskApproved / (double)windowValidated) : 0.0;
        double rateSent = (windowRiskApproved > 0) ? (100.0 * (double)windowSent / (double)windowRiskApproved) : 0.0;
        double noSignalRate = (windowScans > 0) ? (100.0 * (double)windowNoSignal / (double)windowScans) : 0.0;
        PrintFormat("[CONVERSION-RATES] window_scans=%I64u | generated=%I64u | after_pipeline=%.1f%% | after_quorum=%.1f%% | validated=%.1f%% | risk_approved=%.1f%% | sent=%.1f%% | no_signal=%.1f%%",
                    windowScans,
                    windowGenerated,
                    rateAfterPipeline,
                    rateAfterQuorum,
                    rateValidated,
                    rateRiskApproved,
                    rateSent,
                    noSignalRate);

        string dominantConsensusCause = GetDominantConsensusCause(diagRawNone,
                                                                  diagFilteredOut,
                                                                  diagQuorumFailed,
                                                                  diagIntrabarNotEligible);
        if(windowScans >= 20 &&
           noSignalRate >= 80.0 &&
           (g_lastNoSignalAlertTime == 0 || (heartbeatNow - g_lastNoSignalAlertTime) >= heartbeatIntervalSec))
        {
            PrintFormat("[NO-SIGNAL-ALERT] window_scans=%I64u | no_signal=%I64u (%.1f%%) | dominant=%s | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u | reason_total=%I64u | momentum_none=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u",
                        windowScans,
                        windowNoSignal,
                        noSignalRate,
                        dominantConsensusCause,
                        diagRawNone,
                        diagFilteredOut,
                        diagQuorumFailed,
                        diagIntrabarNotEligible,
                        diagReasonTotal,
                        diagMomentumNone,
                        diagUICTNone,
                        diagUICTNeutralBias);
            g_lastNoSignalAlertTime = heartbeatNow;
        }

        SUnifiedRiskSnapshot heartbeatRisk = unifiedRiskManager.GetSnapshot();
        PrintFormat("[RISK-BUDGET] effective=%.2f/%.2f | entry=%.2f | mtm=%.2f | open_exposure=%.2f | conservative=%s | emergency=%s",
                    heartbeatRisk.dailyRiskUsedPercent,
                    heartbeatRisk.maxDailyRiskPercent,
                    heartbeatRisk.dailyEntryRiskUsedPercent,
                    heartbeatRisk.dailyMarkToMarketLossPercent,
                    heartbeatRisk.openExposureRiskPercent,
                    heartbeatRisk.conservativeMode ? "true" : "false",
                    heartbeatRisk.emergencyMode ? "true" : "false");

        CIndicatorManager* indicatorManager = CIndicatorManager::Instance();
        if(indicatorManager != NULL)
            indicatorManager.ReleaseUnused(300);

        g_prevHbScansAttempted = g_hbScansAttempted;
        g_prevHbNoSignalCount = g_hbNoSignalCount;
        g_prevHbSignalsGenerated = g_hbSignalsGenerated;
        g_prevHbSignalsAfterPipeline = g_hbSignalsAfterPipeline;
        g_prevHbSignalsAfterQuorum = g_hbSignalsAfterQuorum;
        g_prevHbSignalsValidated = g_hbSignalsValidated;
        g_prevHbSignalsRiskApproved = g_hbSignalsRiskApproved;
        g_prevHbSignalsSent = g_hbSignalsSent;
        g_lastHeartbeatLogTime = heartbeatNow;
    }

    if(InpEnableAIMode && InpEnableNeuralNetwork && InpEnableNNOnlineTraining &&
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
        static datetime s_lastPositionManageTime = 0;
        datetime nowManage = TimeCurrent();
        if(s_lastPositionManageTime == 0 || (nowManage - s_lastPositionManageTime) >= 1)
        {
            g_positionManager.ManageAllPositions();
            s_lastPositionManageTime = nowManage;
        }
    }

    // Emergency stop on excessive drawdown
    if(currentDrawdown > InpMaxDrawdown)
    {
        tradingEnabled = false;
        Alert("[EMERGENCY] Maximum drawdown exceeded! Trading halted!");
        Comment("EMERGENCY STOP - Drawdown: ", NormalizeDouble(currentDrawdown, 2), "%");

        // Emergency flatten according to configured scope.
        int closedCount = 0;
        int skippedCount = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionGetTicket(i) > 0)
            {
                bool shouldClose = InpEmergencyFlattenAllAccountPositions ||
                                   (PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
                if(shouldClose)
                {
                    if(tradeManager.ClosePosition(PositionGetTicket(i), "Emergency Stop"))
                        closedCount++;
                }
                else
                {
                    skippedCount++;
                }
            }
        }
        PrintFormat("[EMERGENCY] Flatten completed | closed=%d | skipped=%d | account_wide=%s",
                    closedCount, skippedCount,
                    InpEmergencyFlattenAllAccountPositions ? "true" : "false");
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

                    PrintFormat("[TRADE-CONFIRMED] %s | entry=%s | deal=%I64u | position_id=%I64u | price=%.5f | volume=%.2f | request_id=%u",
                                trans.symbol,
                                EnumToString(dealEntry),
                                trans.deal,
                                positionId,
                                trans.price,
                                trans.volume,
                                result.request_id);
                }

                if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY || dealEntry == DEAL_ENTRY_INOUT)
                {
                    double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                    double dealSwap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
                    double dealCommission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
                    double netProfit = dealProfit + dealSwap + dealCommission;
                    bool positionStillOpen = (positionId > 0 && IsPositionIdStillOpen(positionId));
                    double totalNetProfit = netProfit;
                    bool finalCloseRecorded = false;

                    if(positionStillOpen)
                    {
                        if(positionId > 0)
                        {
                            AccumulatePendingCloseProfit(positionId, netProfit);
                        }
                    }
                    else
                    {
                        if(positionId > 0)
                            totalNetProfit += ConsumePendingCloseProfit(positionId);

                        performanceAnalytics.RecordClosedTrade((positionId > 0) ? positionId : trans.deal,
                                                               totalNetProfit);
                        finalCloseRecorded = true;
                        PrintFormat("[TRADE-CONFIRMED] %s | entry=%s | deal=%I64u | position_id=%I64u | price=%.5f | volume=%.2f | net=%.2f | request_id=%u",
                                    trans.symbol,
                                    EnumToString(dealEntry),
                                    trans.deal,
                                    positionId,
                                    trans.price,
                                    trans.volume,
                                    totalNetProfit,
                                    result.request_id);
                    }

                    if(InpEnableAIMode &&
                       InpEnableNeuralNetwork &&
                       InpEnableNNOnlineTraining)
                    {
                        string predictionIdFromComment = ExtractPredictionIdFromComment(dealComment);
                        string predictionIdFromMap = (positionId > 0) ? GetPredictionIdForPosition(positionId) : "";
                        string resolvedPredictionId = (predictionIdFromComment != "") ? predictionIdFromComment : predictionIdFromMap;
                        bool hasPredictionContext = (resolvedPredictionId != "");

                        if(positionStillOpen)
                        {
                            if(positionId > 0 && hasPredictionContext)
                            {
                                g_nnDiagPartialCloseCount++;
                                NNDiagLog(StringFormat("Partial close deferred | Symbol=%s | PositionID=%I64u | DealNet=%.2f",
                                                       trans.symbol, positionId, netProfit));
                            }
                        }
                        else
                        {
                            CNeuralNetworkStrategy* symbolNet = GetNeuralNetForSymbol(trans.symbol);
                            if(symbolNet == NULL)
                                symbolNet = neuralNetStrategy;

                            if(symbolNet != NULL && hasPredictionContext)
                            {
                                bool updatedById = symbolNet.UpdateTradeResultByPredictionId(resolvedPredictionId, totalNetProfit);
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
                        }
                    }

                    if(positionId > 0 && !IsPositionIdStillOpen(positionId))
                    {
                        RemovePredictionPositionMap(positionId);
                        ClearPendingCloseProfit(positionId);
                        if(finalCloseRecorded)
                        {
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
    CEnterpriseStrategyManager* attributionManager = NULL;
    string feedbackSymbol = txSymbol;
    if(txManager != NULL)
    {
        txManager.OnTradeTransaction(trans, request, result);
        attributionManager = txManager;
    }
    else if(g_enterpriseManager != NULL)
    {
        g_enterpriseManager.OnTradeTransaction(trans, request, result);
        attributionManager = g_enterpriseManager;
        if(feedbackSymbol == "" && ArraySize(g_enterpriseManagerSymbols) > 0)
            feedbackSymbol = g_enterpriseManagerSymbols[0];
    }

    if(InpEnableAIMode && attributionManager != NULL)
    {
        if(feedbackSymbol == "")
            feedbackSymbol = _Symbol;

        string contributors[];
        double tradeNetProfit = 0.0;
        if(attributionManager.PopClosedTradeAttribution(contributors, tradeNetProfit))
        {
            int updates = 0;
            for(int i = 0; i < ArraySize(contributors); i++)
            {
                if(contributors[i] == "")
                    continue;

                string qualified = BuildQualifiedStrategyName(feedbackSymbol, contributors[i]);
                if(aiOrchestrator.UpdateStrategyPerformance(qualified, tradeNetProfit))
                    updates++;
            }

            if(updates > 0)
                PrintFormat("[AI-ORCH] Applied closed-trade feedback | Symbol=%s | Contributors=%d | Net=%.2f",
                            feedbackSymbol, updates, tradeNetProfit);
        }
    }
}
