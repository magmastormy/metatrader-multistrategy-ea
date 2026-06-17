//+------------------------------------------------------------------+
//| TrainingDataExporter.mq5                                          |
//| Enterprise training data exporter for ONNX/ML consensus models    |
//| Exports OHLCV + AI features + regime + strategy signals + labels  |
//+------------------------------------------------------------------+
#property strict
#property version "2.00"

//--- Core includes
#include "Core\Utils\Enums.mqh"
#include "Core\AI\AIFeatureVectorBuilder.mqh"
#include "IndicatorManager.mqh"

//--- Engine includes
#include "Core\Engines\RegimeEngine.mqh"
#include "Core\Engines\HurstEngine.mqh"
#include "Core\Engines\OrnsteinUhlenbeckEngine.mqh"
#include "Core\Engines\OrderFlowImbalanceEngine.mqh"
#include "Core\Risk\VPINFilter.mqh"

//--- Strategy includes
#include "Strategies\SimpleMomentumStrategy.mqh"
#include "Strategies\StrategyTrend.mqh"
#include "Strategies\StrategySupportResistance.mqh"
#include "Strategies\StrategyUnifiedICT.mqh"
#include "Strategies\StrategyCandlestick.mqh"
#include "Strategies\CUnicornModelStrategy.mqh"
#include "Strategies\CPowerOfThreeStrategy.mqh"
#include "Strategies\MeanReversionStrategy.mqh"
#include "Strategies\VolatilityBreakoutStrategy.mqh"

//--- Management includes
#include "Core\Management\EnterpriseStrategyManager.mqh"
#include "Core\Trading\TradeManager.mqh"
#include "Core\Risk\PositionSizer.mqh"
#include "Core\Risk\UnifiedRiskManager.mqh"

//--- Resolve extern from EnterpriseStrategyManager.mqh
CPythonBridge* g_pythonBridge = NULL;

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "Export Configuration"
input string          InpExportSymbols        = "EURUSD.0,GBPUSD.0,USDJPY.0,XAUUSD.0,BTCUSD.0,AUDUSD.0";
input ENUM_TIMEFRAMES InpExportTimeframe      = PERIOD_H1;
input datetime        InpFromDate             = D'2024.01.01 00:00:00';
input datetime        InpToDate               = D'2026.06.16 00:00:00';
input string          InpOutputFile           = "AITraining_Enterprise_H1.csv";

input group "Export Sections"
input bool            InpExportFeatureVectors = true;    // Include 57 AI features
input bool            InpExportRegimeData     = true;    // Hurst, VPIN, OU, OFI, Regime
input bool            InpExportStrategySignals = true;   // Per-strategy signal+confidence
input bool            InpExportConsensusData  = true;    // Consensus metrics
input bool            InpExportTargetLabels   = true;    // Triple-barrier labels

input group "Label Configuration"
input string          InpLabelHorizons        = "5,10,20"; // Comma-separated bar horizons
input double          InpLabelATRMultiplier   = 0.5;    // ATR multiplier for barrier distance

input group "Engine Configuration"
input int             InpHurstLookback        = 300;
input int             InpOULookback           = 100;
input int             InpVPINNumBuckets       = 50;
input double          InpVPINExtremeThreshold = 0.7;
input int             InpOFISlowWindow        = 100;

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define STRATEGY_COUNT 9
#define MAX_LABEL_HORIZONS 5

//+------------------------------------------------------------------+
//| Strategy name constants (must match registration order)           |
//+------------------------------------------------------------------+
const string STRATEGY_NAMES[STRATEGY_COUNT] =
{
    "Momentum",
    "Trend",
    "S/R",
    "ICT",
    "Candlestick",
    "Unicorn",
    "PO3",
    "MeanRev",
    "VolBreak"
};

//+------------------------------------------------------------------+
//| Per-symbol context holding all engines and strategies             |
//+------------------------------------------------------------------+
struct SSymbolExportContext
{
    string              symbol;

    // Regime engines
    CRegimeEngine*      regimeEngine;
    CHurstEngine*       hurstEngine;
    COrnsteinUhlenbeckEngine* ouEngine;
    COrderFlowImbalanceEngine* ofiEngine;
    CVPINFilter*        vpinFilter;

    // Strategies (owned separately, also registered in manager)
    IStrategy*          strategies[STRATEGY_COUNT];

    // Consensus manager
    CEnterpriseStrategyManager* strategyManager;

    // Stub dependencies (owned)
    CTradeManager*      tradeManager;
    CPositionSizer*     positionSizer;
    CUnifiedRiskManager* riskManager;

    SSymbolExportContext()
    {
        symbol = "";
        regimeEngine = NULL;
        hurstEngine = NULL;
        ouEngine = NULL;
        ofiEngine = NULL;
        vpinFilter = NULL;
        strategyManager = NULL;
        tradeManager = NULL;
        positionSizer = NULL;
        riskManager = NULL;
        for(int i = 0; i < STRATEGY_COUNT; i++)
            strategies[i] = NULL;
    }
};

//+------------------------------------------------------------------+
//| Global state                                                      |
//+------------------------------------------------------------------+
SSymbolExportContext g_contexts[];
int                 g_labelHorizons[];
int                 g_labelHorizonCount = 0;

//+------------------------------------------------------------------+
//| Utility: trim whitespace from string                              |
//+------------------------------------------------------------------+
string TrimString(string value)
{
    StringTrimLeft(value);
    StringTrimRight(value);
    return value;
}

//+------------------------------------------------------------------+
//| Parse comma-separated label horizons from input                   |
//+------------------------------------------------------------------+
void ParseLabelHorizons()
{
    string parts[];
    g_labelHorizonCount = StringSplit(InpLabelHorizons, ',', parts);
    if(g_labelHorizonCount > MAX_LABEL_HORIZONS)
        g_labelHorizonCount = MAX_LABEL_HORIZONS;

    for(int i = 0; i < g_labelHorizonCount; i++)
    {
        string trimmed = TrimString(parts[i]);
        g_labelHorizons[i] = (int)StringToInteger(trimmed);
        if(g_labelHorizons[i] < 1)
            g_labelHorizons[i] = 1;
    }

    PrintFormat("[TRAIN-EXPORT] Label horizons: %d values | %s",
                g_labelHorizonCount, InpLabelHorizons);
}

//+------------------------------------------------------------------+
//| Initialize engines for a symbol (by context index)                |
//+------------------------------------------------------------------+
bool InitializeEngines(const int ctxIdx, const ENUM_TIMEFRAMES timeframe)
{
    // Regime engine
    g_contexts[ctxIdx].regimeEngine = new CRegimeEngine();
    if(g_contexts[ctxIdx].regimeEngine == NULL)
    {
        PrintFormat("[TRAIN-EXPORT] Failed to create RegimeEngine for %s", g_contexts[ctxIdx].symbol);
        return false;
    }
    g_contexts[ctxIdx].regimeEngine.Initialize();

    // Hurst engine
    g_contexts[ctxIdx].hurstEngine = new CHurstEngine(g_contexts[ctxIdx].symbol, timeframe, InpHurstLookback);
    if(g_contexts[ctxIdx].hurstEngine == NULL)
    {
        PrintFormat("[TRAIN-EXPORT] Failed to create HurstEngine for %s", g_contexts[ctxIdx].symbol);
        return false;
    }

    // OU engine
    g_contexts[ctxIdx].ouEngine = new COrnsteinUhlenbeckEngine(g_contexts[ctxIdx].symbol, timeframe, InpOULookback);
    if(g_contexts[ctxIdx].ouEngine == NULL)
    {
        PrintFormat("[TRAIN-EXPORT] Failed to create OUEngine for %s", g_contexts[ctxIdx].symbol);
        return false;
    }

    // OFI engine
    g_contexts[ctxIdx].ofiEngine = new COrderFlowImbalanceEngine();
    if(g_contexts[ctxIdx].ofiEngine == NULL)
    {
        PrintFormat("[TRAIN-EXPORT] Failed to create OFIEngine for %s", g_contexts[ctxIdx].symbol);
        return false;
    }
    g_contexts[ctxIdx].ofiEngine.Init(g_contexts[ctxIdx].symbol, 5, 20, InpOFISlowWindow);

    // VPIN filter
    g_contexts[ctxIdx].vpinFilter = new CVPINFilter(g_contexts[ctxIdx].symbol, 0, InpVPINNumBuckets, InpVPINExtremeThreshold);
    if(g_contexts[ctxIdx].vpinFilter == NULL)
    {
        PrintFormat("[TRAIN-EXPORT] Failed to create VPINFilter for %s", g_contexts[ctxIdx].symbol);
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Initialize strategies and consensus manager for a symbol          |
//+------------------------------------------------------------------+
bool InitializeStrategies(const int ctxIdx, const ENUM_TIMEFRAMES timeframe)
{
    // Create stub dependencies (no actual trading)
    g_contexts[ctxIdx].tradeManager = new CTradeManager();
    if(g_contexts[ctxIdx].tradeManager == NULL)
        return false;
    g_contexts[ctxIdx].tradeManager.Initialize(999999, "TrainingExporter");

    g_contexts[ctxIdx].positionSizer = new CPositionSizer();
    if(g_contexts[ctxIdx].positionSizer == NULL)
        return false;

    g_contexts[ctxIdx].riskManager = new CUnifiedRiskManager();
    if(g_contexts[ctxIdx].riskManager == NULL)
        return false;
    SUnifiedRiskConfig riskConfig;
    g_contexts[ctxIdx].riskManager.Initialize(riskConfig);

    // Create strategy instances
    g_contexts[ctxIdx].strategies[0] = new CSimpleMomentumStrategy();
    g_contexts[ctxIdx].strategies[1] = new CStrategyTrend();
    g_contexts[ctxIdx].strategies[2] = new CStrategySupportResistance();
    g_contexts[ctxIdx].strategies[3] = new CStrategyUnifiedICT();
    g_contexts[ctxIdx].strategies[4] = new CStrategyCandlestick();
    g_contexts[ctxIdx].strategies[5] = new CUnicornModelStrategy();
    g_contexts[ctxIdx].strategies[6] = new CPowerOfThreeStrategy();
    g_contexts[ctxIdx].strategies[7] = new CMeanReversionStrategy();
    g_contexts[ctxIdx].strategies[8] = new CVolatilityBreakoutStrategy();

    // Initialize each strategy
    for(int i = 0; i < STRATEGY_COUNT; i++)
    {
        if(g_contexts[ctxIdx].strategies[i] == NULL)
        {
            PrintFormat("[TRAIN-EXPORT] Failed to create strategy %d for %s", i, g_contexts[ctxIdx].symbol);
            return false;
        }
        g_contexts[ctxIdx].strategies[i].Init(g_contexts[ctxIdx].symbol, timeframe,
                                               g_contexts[ctxIdx].tradeManager,
                                               g_contexts[ctxIdx].positionSizer,
                                               g_contexts[ctxIdx].riskManager);
        // Set cluster assignments for regime-aware confidence
        CStrategyBase* basePtr = dynamic_cast<CStrategyBase*>(g_contexts[ctxIdx].strategies[i]);
        if(basePtr != NULL)
        {
            switch(i)
            {
                case 0: basePtr.SetStrategyCluster(TREND_CLUSTER); break;          // Momentum
                case 1: basePtr.SetStrategyCluster(TREND_CLUSTER); break;          // Trend
                case 2: basePtr.SetStrategyCluster(STRUCTURE_CLUSTER); break;      // S/R
                case 3: basePtr.SetStrategyCluster(STRUCTURE_CLUSTER); break;      // ICT
                case 4: basePtr.SetStrategyCluster(STRUCTURE_CLUSTER); break;      // Candlestick
                case 5: basePtr.SetStrategyCluster(TREND_CLUSTER); break;          // Unicorn
                case 6: basePtr.SetStrategyCluster(STRUCTURE_CLUSTER); break;      // PO3
                case 7: basePtr.SetStrategyCluster(MEAN_REVERSION_CLUSTER); break; // MeanRev
                case 8: basePtr.SetStrategyCluster(TREND_CLUSTER); break;          // VolBreak
            }
        }
    }

    // Create consensus manager and register strategies
    g_contexts[ctxIdx].strategyManager = new CEnterpriseStrategyManager();
    if(g_contexts[ctxIdx].strategyManager == NULL)
        return false;

    g_contexts[ctxIdx].strategyManager.Initialize(g_contexts[ctxIdx].symbol, timeframe, false,
                                                   g_contexts[ctxIdx].tradeManager,
                                                   g_contexts[ctxIdx].positionSizer,
                                                   g_contexts[ctxIdx].riskManager, 999999);

    // Register each strategy with appropriate weight and tier
    double weights[STRATEGY_COUNT] = {1.0, 1.2, 1.8, 1.2, 1.5, 1.2, 1.2, 1.8, 2.0};
    ENUM_STRATEGY_TIER tiers[STRATEGY_COUNT] =
    {
        STRATEGY_TIER_3,  // Momentum
        STRATEGY_TIER_2,  // Trend
        STRATEGY_TIER_1,  // S/R
        STRATEGY_TIER_2,  // ICT
        STRATEGY_TIER_2,  // Candlestick
        STRATEGY_TIER_2,  // Unicorn
        STRATEGY_TIER_2,  // PO3
        STRATEGY_TIER_1,  // MeanRev
        STRATEGY_TIER_1   // VolBreak
    };
    ENUM_STRATEGY_CLUSTER clusters[STRATEGY_COUNT] =
    {
        TREND_CLUSTER,           // Momentum
        TREND_CLUSTER,           // Trend
        STRUCTURE_CLUSTER,       // S/R
        STRUCTURE_CLUSTER,       // ICT
        STRUCTURE_CLUSTER,       // Candlestick
        TREND_CLUSTER,           // Unicorn
        STRUCTURE_CLUSTER,       // PO3
        MEAN_REVERSION_CLUSTER,  // MeanRev
        TREND_CLUSTER            // VolBreak
    };

    for(int i = 0; i < STRATEGY_COUNT; i++)
    {
        g_contexts[ctxIdx].strategyManager.RegisterStrategy(
            g_contexts[ctxIdx].strategies[i],
            STRATEGY_NAMES[i],
            true,                       // enabled
            weights[i],                 // weight
            tiers[i],                   // tier
            timeframe,                  // tf
            false,                      // intrabarEligible
            PRIMARY_ALPHA,              // role
            clusters[i],                // cluster
            true,                       // liveVotingEnabled
            false                       // shadowOnly
        );
    }

    return true;
}

//+------------------------------------------------------------------+
//| Build CSV header based on enabled export flags                    |
//+------------------------------------------------------------------+
string BuildCSVHeader()
{
    string header = "symbol,timestamp,open,high,low,close,tick_volume,spread";

    // Section 2: AI Feature Vector
    if(InpExportFeatureVectors)
    {
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            header += StringFormat(",feature_%02d", i);
    }

    // Section 3: Regime Features
    if(InpExportRegimeData)
    {
        header += ",regime_state,regime_detailed,regime_confidence,regime_stability";
        header += ",trend_strength,volatility_percentile,compression,spread_shock";
        header += ",hurst_value,hurst_regime,hurst_confidence";
        header += ",ou_theta,ou_mu,ou_sigma,ou_half_life,ou_zscore,ou_signal_quality";
        header += ",vpin_value,vpin_toxicity_regime,vpin_position_size_mult";
        header += ",ofi_composite,ofi_buy_pressure_ratio";
    }

    // Section 4: Strategy Signals
    if(InpExportStrategySignals)
    {
        for(int i = 0; i < STRATEGY_COUNT; i++)
        {
            string name = STRATEGY_NAMES[i];
            header += StringFormat(",%s_signal,%s_confidence", name, name);
        }
    }

    // Section 5: Consensus Metrics
    if(InpExportConsensusData)
    {
        header += ",consensus_signal,consensus_confidence,consensus_confluence";
        header += ",consensus_buy_score,consensus_sell_score";
        header += ",consensus_eligible_voters,consensus_decision_class";
        header += ",consensus_conviction,consensus_directional_quality";
        header += ",consensus_dominant_cluster";
    }

    // Section 6: Target Labels
    if(InpExportTargetLabels)
    {
        for(int i = 0; i < g_labelHorizonCount; i++)
            header += StringFormat(",label_%dbar", g_labelHorizons[i]);
    }

    return header;
}

//+------------------------------------------------------------------+
//| Compute triple-barrier label for a bar                            |
//| Returns: 1 = up barrier hit first, -1 = down first, 0 = timeout  |
//+------------------------------------------------------------------+
int ComputeTripleBarrierLabel(const MqlRates &rates[],
                              const int barIndex,
                              const int totalBars,
                              const double atrValue,
                              const int horizon)
{
    if(barIndex + horizon >= totalBars || atrValue <= 0)
        return 0;

    double closePrice = rates[barIndex].close;
    double upBarrier   = closePrice + atrValue * InpLabelATRMultiplier;
    double downBarrier = closePrice - atrValue * InpLabelATRMultiplier;

    for(int j = barIndex + 1; j <= barIndex + horizon && j < totalBars; j++)
    {
        if(rates[j].high >= upBarrier)
            return 1;
        if(rates[j].low <= downBarrier)
            return -1;
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Get ATR value at a specific bar index from rates array            |
//+------------------------------------------------------------------+
double GetATRAtBar(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barShift)
{
    int atrHandle = CIndicatorManager::Instance().GetATRHandle(symbol, timeframe, 14);
    if(atrHandle == INVALID_HANDLE)
        return 0.0;

    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    if(CopyBuffer(atrHandle, 0, barShift, 1, atrBuffer) <= 0)
        return 0.0;

    return atrBuffer[0];
}

//+------------------------------------------------------------------+
//| Check if all engines are warmed up (by context index)             |
//+------------------------------------------------------------------+
bool AllEnginesWarmedUp(const int ctxIdx)
{
    if(InpExportRegimeData)
    {
        if(g_contexts[ctxIdx].hurstEngine != NULL && !g_contexts[ctxIdx].hurstEngine.IsWarmedUp())
            return false;
        if(g_contexts[ctxIdx].ouEngine != NULL && !g_contexts[ctxIdx].ouEngine.IsWarmedUp())
            return false;
        if(g_contexts[ctxIdx].ofiEngine != NULL && !g_contexts[ctxIdx].ofiEngine.IsWarmedUp())
            return false;
        if(g_contexts[ctxIdx].vpinFilter != NULL && !g_contexts[ctxIdx].vpinFilter.IsWarmedUp())
            return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Export training data for a single symbol (by context index)       |
//+------------------------------------------------------------------+
bool ExportSymbolTrainingData(const int fileHandle,
                              const int ctxIdx,
                              const ENUM_TIMEFRAMES timeframe,
                              const datetime fromDate,
                              const datetime toDate,
                              int &rowsWritten)
{
    if(g_contexts[ctxIdx].symbol == "")
        return false;

    SymbolSelect(g_contexts[ctxIdx].symbol, true);

    // Copy full OHLCV history
    MqlRates rates[];
    ArraySetAsSeries(rates, false);
    ResetLastError();
    int copied = CopyRates(g_contexts[ctxIdx].symbol, timeframe, fromDate, toDate, rates);
    if(copied <= 0)
    {
        PrintFormat("[TRAIN-EXPORT] No rates for %s %s | err=%d",
                    g_contexts[ctxIdx].symbol, EnumToString(timeframe), GetLastError());
        return false;
    }

    int digits = (int)SymbolInfoInteger(g_contexts[ctxIdx].symbol, SYMBOL_DIGITS);
    int warmupSkipped = 0;
    bool warmedUp = false;

    PrintFormat("[TRAIN-EXPORT] Processing %s | bars=%d | building engines...",
                g_contexts[ctxIdx].symbol, copied);

    // Forward-iterate bars to warm up engines and export data
    for(int i = 0; i < copied; i++)
    {
        // --- Update engines at each bar ---

        // Regime engine
        if(InpExportRegimeData && g_contexts[ctxIdx].regimeEngine != NULL)
            g_contexts[ctxIdx].regimeEngine.Update(g_contexts[ctxIdx].symbol, timeframe);

        // Hurst engine
        if(InpExportRegimeData && g_contexts[ctxIdx].hurstEngine != NULL)
            g_contexts[ctxIdx].hurstEngine.Update();

        // OU engine
        if(InpExportRegimeData && g_contexts[ctxIdx].ouEngine != NULL)
            g_contexts[ctxIdx].ouEngine.Update();

        // OFI engine - simulate tick from bar data
        if(InpExportRegimeData && g_contexts[ctxIdx].ofiEngine != NULL)
        {
            double midPrice = (rates[i].high + rates[i].low) / 2.0;
            double tickVol = (double)rates[i].tick_volume;
            double bid = rates[i].close;
            double ask = rates[i].close;
            if(rates[i].close > rates[i].open)
                ask = rates[i].high;
            else
                bid = rates[i].low;
            g_contexts[ctxIdx].ofiEngine.OnTick(midPrice, tickVol, bid, ask);
        }

        // VPIN filter - simulate tick from bar data
        if(InpExportRegimeData && g_contexts[ctxIdx].vpinFilter != NULL)
        {
            double tickPrice = rates[i].close;
            double tickVol = (double)rates[i].tick_volume;
            g_contexts[ctxIdx].vpinFilter.OnTick(tickPrice, tickVol);
        }

        // Strategy evaluation on new bar
        if(InpExportStrategySignals || InpExportConsensusData)
        {
            if(g_contexts[ctxIdx].strategyManager != NULL)
                g_contexts[ctxIdx].strategyManager.OnNewBar(g_contexts[ctxIdx].symbol, timeframe);
        }

        // Check warm-up
        if(!warmedUp)
        {
            if(!AllEnginesWarmedUp(ctxIdx))
            {
                warmupSkipped++;
                continue;
            }
            warmedUp = true;
            PrintFormat("[TRAIN-EXPORT] %s warmed up after %d bars", g_contexts[ctxIdx].symbol, warmupSkipped);
        }

        // --- Build CSV row ---

        // Section 1: Core OHLCV
        int shift = iBarShift(g_contexts[ctxIdx].symbol, timeframe, rates[i].time, false);
        long spreadVal = SymbolInfoInteger(g_contexts[ctxIdx].symbol, SYMBOL_SPREAD);

        string row = StringFormat("%s,%s,%s,%s,%s,%s,%I64d,%I64d",
                                  g_contexts[ctxIdx].symbol,
                                  TimeToString(rates[i].time, TIME_DATE | TIME_SECONDS),
                                  DoubleToString(rates[i].open, digits),
                                  DoubleToString(rates[i].high, digits),
                                  DoubleToString(rates[i].low, digits),
                                  DoubleToString(rates[i].close, digits),
                                  (long)rates[i].tick_volume,
                                  spreadVal);

        // Section 2: AI Feature Vector
        if(InpExportFeatureVectors)
        {
            double features[];
            if(shift < 1 || !CAIFeatureVectorBuilder::BuildNNFeatureVector(g_contexts[ctxIdx].symbol, timeframe, features, shift))
            {
                // Fill with empty placeholder if feature extraction fails
                for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                    row += ",";
                rowsWritten++;
                FileWriteString(fileHandle, row + "\r\n");
                continue;
            }
            for(int f = 0; f < ArraySize(features); f++)
                row += StringFormat(",%.10f", features[f]);
        }

        // Section 3: Regime Features
        if(InpExportRegimeData)
        {
            // Regime engine snapshot
            SRegimeSnapshot regSnap;
            if(g_contexts[ctxIdx].regimeEngine != NULL)
                regSnap = g_contexts[ctxIdx].regimeEngine.GetSnapshot();

            row += StringFormat(",%d,%d,%.6f,%d",
                                (int)regSnap.state,
                                (int)regSnap.detailedRegime,
                                regSnap.regimeConfidence,
                                regSnap.regimeStabilityBars);
            row += StringFormat(",%.6f,%.6f,%d,%d",
                                regSnap.trendStrength,
                                regSnap.volatilityPercentile,
                                regSnap.compression ? 1 : 0,
                                regSnap.spreadShock ? 1 : 0);

            // Hurst snapshot
            SHurstSnapshot hurstSnap;
            if(g_contexts[ctxIdx].hurstEngine != NULL)
                hurstSnap = g_contexts[ctxIdx].hurstEngine.GetSnapshot();

            row += StringFormat(",%.6f,%d,%.6f",
                                hurstSnap.hurstValue,
                                (int)hurstSnap.regime,
                                hurstSnap.confidence);

            // OU snapshot
            SOUSnapshot ouSnap;
            if(g_contexts[ctxIdx].ouEngine != NULL)
                ouSnap = g_contexts[ctxIdx].ouEngine.GetSnapshot();

            row += StringFormat(",%.10f,%.6f,%.10f,%.2f,%.6f,%.6f",
                                ouSnap.theta,
                                ouSnap.mu,
                                ouSnap.sigma,
                                ouSnap.halfLife,
                                ouSnap.ouZScore,
                                ouSnap.signalQuality);

            // VPIN snapshot
            SVPINSnapshot vpinSnap;
            if(g_contexts[ctxIdx].vpinFilter != NULL)
                vpinSnap = g_contexts[ctxIdx].vpinFilter.GetSnapshot();

            row += StringFormat(",%.6f,%d,%.4f",
                                vpinSnap.vpinValue,
                                (int)vpinSnap.toxicityRegime,
                                vpinSnap.positionSizeMultiplier);

            // OFI snapshot
            SOFISnapshot ofiSnap;
            if(g_contexts[ctxIdx].ofiEngine != NULL)
                g_contexts[ctxIdx].ofiEngine.GetSnapshot(ofiSnap);

            row += StringFormat(",%.6f,%.6f",
                                ofiSnap.compositeOFI,
                                ofiSnap.buyPressureRatio);
        }

        // Section 4: Strategy Signals
        if(InpExportStrategySignals)
        {
            for(int s = 0; s < STRATEGY_COUNT; s++)
            {
                double conf = 0.0;
                int signal = 0;
                if(g_contexts[ctxIdx].strategies[s] != NULL)
                {
                    ENUM_TRADE_SIGNAL sig = g_contexts[ctxIdx].strategies[s].GetSignal(conf);
                    signal = (int)sig;
                }
                row += StringFormat(",%d,%.6f", signal, conf);
            }
        }

        // Section 5: Consensus Metrics
        if(InpExportConsensusData)
        {
            double consensusConf = 0.0;
            int confluence = 0;
            int consensusSignal = 0;
            double buyScore = 0.0, sellScore = 0.0;
            int eligibleVoters = 0, decisionClass = 0;
            double conviction = 0.0, dirQuality = 0.0;
            int dominantCluster = 0;

            if(g_contexts[ctxIdx].strategyManager != NULL)
            {
                ENUM_TRADE_SIGNAL sig = g_contexts[ctxIdx].strategyManager.GetConsensusSignalForSymbolWithConfluenceMode(
                    g_contexts[ctxIdx].symbol, consensusConf, confluence, EVAL_MODE_NEW_BAR);
                consensusSignal = (int)sig;

                SConsensusDecisionContext decCtx;
                if(g_contexts[ctxIdx].strategyManager.GetLastDecisionContext(decCtx))
                {
                    buyScore = decCtx.buyScore;
                    sellScore = decCtx.sellScore;
                    eligibleVoters = decCtx.eligibleLiveVoterCount;
                    decisionClass = decCtx.decisionClass;
                    conviction = decCtx.convictionScore;
                    dirQuality = decCtx.directionalQuality;
                    dominantCluster = (int)decCtx.dominantCluster;
                }
            }

            row += StringFormat(",%d,%.6f,%d", consensusSignal, consensusConf, confluence);
            row += StringFormat(",%.6f,%.6f", buyScore, sellScore);
            row += StringFormat(",%d,%d", eligibleVoters, decisionClass);
            row += StringFormat(",%.6f,%.6f,%d", conviction, dirQuality, dominantCluster);
        }

        // Section 6: Target Labels
        if(InpExportTargetLabels)
        {
            double atrVal = GetATRAtBar(g_contexts[ctxIdx].symbol, timeframe, shift);
            for(int h = 0; h < g_labelHorizonCount; h++)
            {
                int label = ComputeTripleBarrierLabel(rates, i, copied, atrVal, g_labelHorizons[h]);
                row += StringFormat(",%d", label);
            }
        }

        FileWriteString(fileHandle, row + "\r\n");
        rowsWritten++;
    }

    PrintFormat("[TRAIN-EXPORT] %s %s | total_bars=%d | warmup_skipped=%d | rows_exported=%d",
                g_contexts[ctxIdx].symbol, EnumToString(timeframe), copied, warmupSkipped, copied - warmupSkipped);
    return true;
}

//+------------------------------------------------------------------+
//| Cleanup all allocated objects                                     |
//+------------------------------------------------------------------+
void Cleanup()
{
    for(int i = 0; i < ArraySize(g_contexts); i++)
    {
        // Delete strategies first (before manager, since manager references them)
        for(int s = 0; s < STRATEGY_COUNT; s++)
        {
            if(g_contexts[i].strategies[s] != NULL)
            {
                delete g_contexts[i].strategies[s];
                g_contexts[i].strategies[s] = NULL;
            }
        }

        // Delete manager
        if(g_contexts[i].strategyManager != NULL)
        {
            delete g_contexts[i].strategyManager;
            g_contexts[i].strategyManager = NULL;
        }

        // Delete engines
        if(g_contexts[i].regimeEngine != NULL)  { delete g_contexts[i].regimeEngine;  g_contexts[i].regimeEngine = NULL;  }
        if(g_contexts[i].hurstEngine != NULL)   { delete g_contexts[i].hurstEngine;   g_contexts[i].hurstEngine = NULL;   }
        if(g_contexts[i].ouEngine != NULL)      { delete g_contexts[i].ouEngine;      g_contexts[i].ouEngine = NULL;      }
        if(g_contexts[i].ofiEngine != NULL)     { delete g_contexts[i].ofiEngine;     g_contexts[i].ofiEngine = NULL;     }
        if(g_contexts[i].vpinFilter != NULL)    { delete g_contexts[i].vpinFilter;    g_contexts[i].vpinFilter = NULL;    }

        // Delete stub dependencies
        if(g_contexts[i].tradeManager != NULL)  { delete g_contexts[i].tradeManager;  g_contexts[i].tradeManager = NULL;  }
        if(g_contexts[i].positionSizer != NULL) { delete g_contexts[i].positionSizer; g_contexts[i].positionSizer = NULL; }
        if(g_contexts[i].riskManager != NULL)   { delete g_contexts[i].riskManager;   g_contexts[i].riskManager = NULL;   }
    }

    ArrayResize(g_contexts, 0);
    CIndicatorManager::DestroyInstance();
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    datetime toDate = (InpToDate > 0) ? InpToDate : TimeCurrent();
    if(toDate <= InpFromDate)
    {
        Print("[TRAIN-EXPORT] Invalid date window");
        ExpertRemove();
        return INIT_FAILED;
    }

    // Parse label horizons
    if(InpExportTargetLabels)
        ParseLabelHorizons();

    // Open output file
    int fileHandle = FileOpen(InpOutputFile, FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
    if(fileHandle == INVALID_HANDLE)
    {
        PrintFormat("[TRAIN-EXPORT] Failed to open output file %s | err=%d", InpOutputFile, GetLastError());
        ExpertRemove();
        return INIT_FAILED;
    }

    // Write CSV header
    string header = BuildCSVHeader();
    FileWriteString(fileHandle, header + "\r\n");

    // Parse symbols
    string rawSymbols[];
    int symbolCount = StringSplit(InpExportSymbols, ',', rawSymbols);
    ArrayResize(g_contexts, symbolCount);

    // Initialize per-symbol contexts
    int activeSymbols = 0;
    for(int i = 0; i < symbolCount; i++)
    {
        string symbol = TrimString(rawSymbols[i]);
        if(symbol == "")
            continue;

        g_contexts[activeSymbols].symbol = symbol;
        SymbolSelect(symbol, true);

        PrintFormat("[TRAIN-EXPORT] Initializing %s ...", symbol);

        if(!InitializeEngines(activeSymbols, InpExportTimeframe))
        {
            PrintFormat("[TRAIN-EXPORT] Engine init failed for %s — skipping", symbol);
            continue;
        }

        if(InpExportStrategySignals || InpExportConsensusData)
        {
            if(!InitializeStrategies(activeSymbols, InpExportTimeframe))
            {
                PrintFormat("[TRAIN-EXPORT] Strategy init failed for %s — skipping", symbol);
                continue;
            }
        }

        activeSymbols++;
    }

    // Export data for each symbol
    int rowsWritten = 0;
    for(int i = 0; i < activeSymbols; i++)
    {
        ExportSymbolTrainingData(fileHandle, i, InpExportTimeframe,
                                 InpFromDate, toDate, rowsWritten);
    }

    // Cleanup
    FileClose(fileHandle);
    Cleanup();

    PrintFormat("[TRAIN-EXPORT] Completed | symbols=%d | rows=%d | file=%s",
                activeSymbols, rowsWritten, InpOutputFile);
    PrintFormat("[TRAIN-EXPORT] Common files root: %s",
                TerminalInfoString(TERMINAL_COMMONDATA_PATH));

    ExpertRemove();
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Cleanup();
}

//+------------------------------------------------------------------+
//| Tick handler (unused — one-shot exporter)                         |
//+------------------------------------------------------------------+
void OnTick()
{
}
