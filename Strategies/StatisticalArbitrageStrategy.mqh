// Institutional Statistical Arbitrage / Pair Trading Strategy
// Z-Score Mean Reversion on Correlated Synthetic Indices
// Requires Python Bridge for Real-Time Correlation Matrix
// Copyright 2026, Multi-Strategy EA
#ifndef STATISTICAL_ARBITRAGE_STRATEGY_MQH
#define STATISTICAL_ARBITRAGE_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Utils/PythonBridge.mqh"
#include "../Core/Engines/OrnsteinUhlenbeckEngine.mqh"
#include "../IndicatorManager.mqh"

struct SStatArbSignal
{
    ENUM_TRADE_SIGNAL direction;        // BUY = long spread, SELL = short spread
    string leg1Symbol;                  // pair leg 1 (e.g. Vol75)
    string leg2Symbol;                  // pair leg 2, hedged against leg 1
    double leg1LotSize;
    double leg2LotSize;                 // hedge-ratio adjusted
    double zScore;                      // spread z-score, in sigma
    double entryZScore;
    double exitZScore;                  // exit target z-score (reversion to the mean)
    double confidence;
    string reason;
    
    SStatArbSignal() : 
        direction(TRADE_SIGNAL_NONE),
        leg1Symbol(""),
        leg2Symbol(""),
        leg1LotSize(0),
        leg2LotSize(0),
        zScore(0),
        entryZScore(0),
        exitZScore(0),
        confidence(0),
        reason("") {}
};

class CStatisticalArbitrageStrategy : public CStrategyBase
{
private:
    double m_entryZThreshold;       // entry |z| threshold
    double m_exitZThreshold;        // exit z threshold (reversion target)
    int m_lookbackPeriods;          // bars in the z-score window
    double m_minCorrelation;        // the pair must correlate at least this much
    double m_hedgeRatio;            // fixed: no dynamic hedge ratio is applied
    double m_slZBuffer;             // adverse SL distance in z (sigma)

    datetime m_lastSignalBar;
    
    string m_activeLeg1Symbol;
    string m_activeLeg2Symbol;
    double m_activeSpreadMean;
    double m_activeSpreadStdDev;
    datetime m_pairLastUpdateTime;
    
        CPythonBridge* m_pythonBridge;
    
        // OU engine: mean-reversion-aware z-scores
        COrnsteinUhlenbeckEngine* m_ouEngine;
    
    double GetValidatedMinLot(const string symbol)
    {
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(minLot <= 0.0 || !MathIsValidNumber(minLot))
        {
            PrintFormat("[STATARB] WARNING: Invalid SYMBOL_VOLUME_MIN for %s (returned %.6f), using fallback 0.01", 
                       symbol, minLot);
            minLot = 0.01;  // Safe fallback
        }
        return minLot;
    }
    
    double GetValidatedLotStep(const string symbol)
    {
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        if(lotStep <= 0.0 || !MathIsValidNumber(lotStep))
        {
            PrintFormat("[STATARB] WARNING: Invalid SYMBOL_VOLUME_STEP for %s (returned %.6f), using fallback 0.01", 
                       symbol, lotStep);
            lotStep = 0.01;  // Safe fallback
        }
        return lotStep;
    }
    
public:
    CStatisticalArbitrageStrategy(const string name = "Statistical Arbitrage v1.0", int magic = 0) :
        CStrategyBase(name, magic),
        m_entryZThreshold(2.0),
        m_exitZThreshold(0.5),
        m_lookbackPeriods(50),
        m_minCorrelation(0.85),
        m_hedgeRatio(1.0),
        m_slZBuffer(1.0),
        m_lastSignalBar(0),
        m_activeLeg1Symbol(""),
        m_activeLeg2Symbol(""),
        m_activeSpreadMean(0),
        m_activeSpreadStdDev(0),
        m_pairLastUpdateTime(0),
                m_pythonBridge(NULL),
                m_ouEngine(NULL)
    {
        m_strategyPrefix = "STATARB";
        m_minConfidence = 0.70; // High threshold for stat arb (complex strategy)
    }
    
    ~CStatisticalArbitrageStrategy()
    {
        Cleanup();
    }
    
        void Cleanup()
        {
            // CIndicatorManager owns the indicator handles centrally - no manual release
            // Risk manager, Python bridge and OU engine are not owned here: null the
            // references, never delete them.
            m_pythonBridge = NULL;
            m_ouEngine = NULL;
        }
    
    // Injects the OU engine used for mean-reversion-aware z-scores
    void SetOUEngine(COrnsteinUhlenbeckEngine* ouEngine) { m_ouEngine = ouEngine; }
    
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;
        
        // Stat arb trades spreads between two instruments: it holds no indicator handles
        // on the chart symbol.
        
        // Python Bridge and OU engine are injected by the EA after construction via
        // SetPythonBridge() / SetOUEngine(); without them the strategy rejects signals.
                if(m_pythonBridge == NULL)
                    Print("[STATARB] WARNING: Python Bridge not set - call SetPythonBridge() from EA initialization");
                if(m_ouEngine == NULL)
                    Print("[STATARB] WARNING: OU Engine not set - call SetOUEngine() from EA initialization");
        
        PrintFormat("[STATARB] Initialized | Entry_Z=%.1f | Exit_Z=%.1f | Lookback=%d | Min_Corr=%.2f",
                   m_entryZThreshold, m_exitZThreshold, m_lookbackPeriods, m_minCorrelation);
        Print("[STATARB] NOTE: Requires Python Bridge for real-time correlation matrix");
        
        return true;
    }
    
    virtual void Deinit() override
    {
        Cleanup();
        CStrategyBase::Deinit();
    }
    
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(!IsEnabled() || !m_is_initialized)
            return;
        if(symbol != m_symbol || timeframe != m_timeframe)
            return;
        
        int currentBar = iBars(m_symbol, m_timeframe);
        if(currentBar == m_lastSignalBar)
            return;
        m_lastSignalBar = currentBar;
        
        UpdateCorrelationMatrix();
    }
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("STATARB_UNSET");
        
        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("STATARB_DISABLED_OR_UNINIT");
        
        if(!IsPythonBridgeAvailable())
        {
            return RejectSignal("STATARB_PYTHON_BRIDGE_UNAVAILABLE");
        }
        
        string leg1Symbol = m_symbol;
        string leg2Symbol = FindBestCorrelatedPair(leg1Symbol);
        
        if(leg2Symbol == "")
        {
            return RejectSignal("STATARB_NO_CORRELATED_PAIR");
        }
        
        double spreadMean, spreadStdDev;
        if(!CalculateSpreadStatistics(leg1Symbol, leg2Symbol, spreadMean, spreadStdDev))
        {
            return RejectSignal("STATARB_SPREAD_CALC_FAILED");
        }
        
        double currentSpread = GetCurrentSpread(leg1Symbol, leg2Symbol);
        double zScore = (spreadStdDev > 0) ? ((currentSpread - spreadMean) / spreadStdDev) : 0;
        
        // OU-adjusted z-score only when the engine is warmed up and sees mean reversion
        if(m_ouEngine != NULL && m_ouEngine.IsWarmedUp() && m_ouEngine.IsMeanReverting())
        {
            double ouZScore = m_ouEngine.GetOUZScore();
            double ouQuality = m_ouEngine.GetSignalQuality();
            if(ouQuality > 0.5)  // Only use OU z-score if quality is reasonable
            {
                // OU z takes at most 60% of the weight, scaled by quality
                zScore = zScore * (1.0 - ouQuality * 0.6) + ouZScore * (ouQuality * 0.6);
                PrintFormat("[STATARB-OU] %s | simple_z=%.2f ou_z=%.2f quality=%.2f blended_z=%.2f",
                           m_symbol, (spreadStdDev > 0) ? ((currentSpread - spreadMean) / spreadStdDev) : 0,
                           ouZScore, ouQuality, zScore);
            }
        }
        
        // OU half-life filter: only trade if mean reversion speed is reasonable
        if(!ValidHalfLife())
        {
            return RejectSignal("STATARB_HALF_LIFE_INVALID");
        }
        
        SStatArbSignal signal = DetectStatArbSignal(
            leg1Symbol, leg2Symbol,
            zScore, spreadMean, spreadStdDev
        );
        
        if(signal.direction == TRADE_SIGNAL_NONE)
            return RejectSignal("STATARB_NO_SIGNAL");
        
        if(signal.confidence < m_minConfidence)
        {
            PrintFormat("[STATARB] Low confidence | %.1f%% < %.1f%%", 
                       signal.confidence * 100, m_minConfidence * 100);
            return RejectSignal("STATARB_LOW_CONFIDENCE");
        }
        
        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
                CUnifiedRiskManager* riskMgr = GetUnifiedRiskManager();
                if(riskMgr != NULL)
                {
                    // Validate primary leg through risk manager
                    double minLot = GetValidatedMinLot(m_symbol);
                    STradeValidationRequest validationReq;
                    ZeroMemory(validationReq);
                    validationReq.symbol = m_symbol;
                    validationReq.orderType = (signal.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                    validationReq.lotSize = minLot;
                    // These proposed stops reach the execution path. SL/TP are derived from the
                    // spread's own sigma, not fixed pips: adverse move = m_slZBuffer sigma,
                    // target = reversion to the exit z-threshold, so R:R stays above the
                    // mean-reversion floor.
                    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                    if(point <= 0) point = 0.00001;
                    double spreadStdDevPips = (spreadStdDev > 0) ? (spreadStdDev / point) : 0.0;
                    if(spreadStdDevPips <= 0) spreadStdDevPips = 50.0;  // fallback if sigma unknown
                    double tpZ = MathAbs(zScore) - m_exitZThreshold;    // reversion distance to exit
                    if(tpZ < 0.5) tpZ = 0.5;
                    validationReq.stopLossPips = m_slZBuffer * spreadStdDevPips;
                    validationReq.takeProfitPips = tpZ * spreadStdDevPips;
                    validationReq.confidence = signal.confidence;
                    validationReq.strategy = m_name;
                    validationReq.requestTime = TimeCurrent();

                    SetProposedStops(validationReq.stopLossPips, validationReq.takeProfitPips);
                    SValidationResult validationResult = riskMgr.ValidateTradeRequest(validationReq, "STATARB", "", false);
                    if(!validationResult.approved)
                    {
                        SetDecisionReasonTag("STATARB_RISK_REJECTED");
                        PrintFormat("[STATARB] Risk rejected %s spread (Z=%.2f Conf=%.1f%%) | %s",
                                   signal.direction == TRADE_SIGNAL_BUY ? "LONG" : "SHORT",
                                   signal.zScore, signal.confidence * 100, validationResult.message);
                        return TRADE_SIGNAL_NONE;
                    }

                    double minLot2 = GetValidatedMinLot(signal.leg2Symbol);
                    double lotStep2 = GetValidatedLotStep(signal.leg2Symbol);
                    signal.leg1LotSize = minLot;
                    signal.leg2LotSize = MathMax(minLot2,
                                                  MathFloor(m_hedgeRatio * minLot / lotStep2) * lotStep2);
                }
        
        m_lastSignalBar = iBars(m_symbol, m_timeframe);
        m_activeLeg1Symbol = leg1Symbol;
        m_activeLeg2Symbol = leg2Symbol;
        m_activeSpreadMean = spreadMean;
        m_activeSpreadStdDev = spreadStdDev;
        m_pairLastUpdateTime = TimeCurrent();
        
        RecordSignal();
        SetDecisionReasonTag(signal.direction == TRADE_SIGNAL_BUY ? "STATARB_SIGNAL_LONG_SPREAD" : "STATARB_SIGNAL_SHORT_SPREAD");
        confidence = signal.confidence;
        
        // [CONSENSUS-DIAG] log required by AGENTS.md §6
        PrintFormat("[CONSENSUS-DIAG] %s+%s | %s Spread | Z=%.2f | Corr=%.2f | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   leg1Symbol, leg2Symbol,
                   signal.direction == TRADE_SIGNAL_BUY ? "LONG" : "SHORT",
                   signal.zScore,
                   GetPairCorrelation(leg1Symbol, leg2Symbol),
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);
        
        PrintFormat("[STATARB] %s+%s: %s Spread | Z=%.2f | Mean=%.5f | StdDev=%.5f | Conf: %.1f%% | %s",
                   leg1Symbol, leg2Symbol,
                   signal.direction == TRADE_SIGNAL_BUY ? "LONG" : "SHORT",
                   signal.zScore,
                   spreadMean, spreadStdDev,
                   confidence * 100,
                   signal.reason);
        
        // The edge is the spread, but only m_symbol can be sent: leg2 is computed and
        // discarded, so voting direction would book an unhedged leg with a two-leg stop.
        PrintFormat("[STATARB-UNHEDGED] %s+%s | signal valid (Z=%.2f Conf=%.1f%%) but leg2 is never sent - abstaining instead of voting a naked %s on %s",
                   leg1Symbol, leg2Symbol, zScore, confidence * 100,
                   signal.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL", m_symbol);
        SetDecisionReasonTag("STATARB_NAKED_LEG");
        return TRADE_SIGNAL_NONE;
    }
    
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_STATISTICAL_ARBITRAGE; }
    
    // Set Python Bridge reference (called by EA during initialization)
    void SetPythonBridge(CPythonBridge* bridge)
    {
        m_pythonBridge = bridge;
    }
    
private:
    bool IsPythonBridgeAvailable()
    {
        if(m_pythonBridge == NULL)
            return false;
        
        return m_pythonBridge.IsConnected();
    }
    
    void UpdateCorrelationMatrix()
    {
        if(m_pythonBridge == NULL || !m_pythonBridge.IsConnected())
            return;
        
        double corrMatrix[];
        int size;
        string corrSymbols[];

        if(m_pythonBridge.GetCorrelationMatrix(corrMatrix, size, corrSymbols))
        {
            PrintFormat("[STATARB] Correlation matrix updated | Size=%dx%d | Symbols=%d", size, size, ArraySize(corrSymbols));
        }
    }
    
    // Returns "" unless a pair correlates at least m_minCorrelation
    string FindBestCorrelatedPair(const string symbol)
    {
        if(m_pythonBridge == NULL || !m_pythonBridge.IsConnected())
            return "";
        
        string bestPair;
        double correlation;
        
        if(m_pythonBridge.FindBestCorrelatedPair(symbol, bestPair, correlation))
        {
            if(correlation >= m_minCorrelation)
            {
                PrintFormat("[STATARB-PAIR] Best pair for %s: %s (Corr=%.2f)", symbol, bestPair, correlation);
                return bestPair;
            }
        }
        
        return "";
    }
    
    double GetPairCorrelation(const string symbol1, const string symbol2)
    {
        if(m_pythonBridge == NULL || !m_pythonBridge.IsConnected())
            return 0.0;
        
        return m_pythonBridge.GetPairCorrelation(symbol1, symbol2);
    }
    
    bool CalculateSpreadStatistics(const string leg1, const string leg2, 
                                   double &mean, double &stdDev)
    {
        // CopyClose into a static array fills OLDEST-first ([0]=oldest); dynamic arrays +
        // ArraySetAsSeries(true) make [0] the newest closed bar.
        double prices1[], prices2[];
        ArraySetAsSeries(prices1, true);
        ArraySetAsSeries(prices2, true);
        if(CopyClose(leg1, PERIOD_CURRENT, 1, m_lookbackPeriods, prices1) < m_lookbackPeriods ||
           CopyClose(leg2, PERIOD_CURRENT, 1, m_lookbackPeriods, prices2) < m_lookbackPeriods)
        {
            return false;
        }
        
        double spreads[];
        ArrayResize(spreads, m_lookbackPeriods);
        
        for(int i = 0; i < m_lookbackPeriods; i++)
        {
            // With AS_SERIES=true, [i] = i bars ago from the last closed bar
            spreads[i] = prices1[i] - (prices2[i] * m_hedgeRatio);
        }
        
        mean = 0;
        for(int i = 0; i < m_lookbackPeriods; i++)
            mean += spreads[i];
        mean /= m_lookbackPeriods;
        
        double variance = 0;
        for(int i = 0; i < m_lookbackPeriods; i++)
            variance += MathPow(spreads[i] - mean, 2);
        variance /= m_lookbackPeriods;
        stdDev = MathSqrt(variance);
        
        return true;
    }
    
    double GetCurrentSpread(const string leg1, const string leg2)
    {
        double price1 = iClose(leg1, PERIOD_CURRENT, 1);
        double price2 = iClose(leg2, PERIOD_CURRENT, 1);
        
        return price1 - (price2 * m_hedgeRatio);
    }
    
    SStatArbSignal DetectStatArbSignal(
        const string leg1, const string leg2,
        double zScore, double spreadMean, double spreadStdDev)
    {
        SStatArbSignal signal;
        
        // Long spread: Z-score < -entry threshold (spread is too low, expect mean reversion up)
        if(zScore < -m_entryZThreshold)
        {
            signal.direction = TRADE_SIGNAL_BUY;  // Buy spread (long leg1, short leg2)
            signal.leg1Symbol = leg1;
            signal.leg2Symbol = leg2;
            signal.leg1LotSize = GetValidatedMinLot(leg1);
            signal.leg2LotSize = GetValidatedMinLot(leg2) * m_hedgeRatio;
            signal.zScore = zScore;
            signal.entryZScore = zScore;
            signal.exitZScore = -m_exitZThreshold;  // Exit when z-score returns to -0.5
            signal.confidence = 0.70 + MathAbs(zScore + m_entryZThreshold) * 0.05;
            signal.confidence = MathMin(0.95, signal.confidence);
            signal.reason = StringFormat("Spread undervalued | Z=%.2f < -%.1f", zScore, m_entryZThreshold);
            
            PrintFormat("[STATARB-SIGNAL] LONG spread | %s-%s | Z=%.2f < -%.1f",
                       leg1, leg2, zScore, m_entryZThreshold);
            
            return signal;
        }
        
        // Short spread: Z-score > +entry threshold (spread is too high, expect mean reversion down)
        if(zScore > m_entryZThreshold)
        {
            signal.direction = TRADE_SIGNAL_SELL;  // Sell spread (short leg1, long leg2)
            signal.leg1Symbol = leg1;
            signal.leg2Symbol = leg2;
            signal.leg1LotSize = GetValidatedMinLot(leg1);
            signal.leg2LotSize = GetValidatedMinLot(leg2) * m_hedgeRatio;
            signal.zScore = zScore;
            signal.entryZScore = zScore;
            signal.exitZScore = m_exitZThreshold;  // Exit when z-score returns to +0.5
            signal.confidence = 0.70 + MathAbs(zScore - m_entryZThreshold) * 0.05;
            signal.confidence = MathMin(0.95, signal.confidence);
            signal.reason = StringFormat("Spread overvalued | Z=%.2f > +%.1f", zScore, m_entryZThreshold);
            
            PrintFormat("[STATARB-SIGNAL] SHORT spread | %s-%s | Z=%.2f > +%.1f",
                       leg1, leg2, zScore, m_entryZThreshold);
            
            return signal;
        }
        
        return signal;
    }
    
    // Validates and logs the pair intent only - CTradeManager owns order execution
        bool ExecutePairTrade(const string symbol1, const string symbol2, double hedgeRatio, ENUM_TRADE_SIGNAL direction)
        {
            CUnifiedRiskManager* riskMgr = GetUnifiedRiskManager();
            if(riskMgr == NULL)
                return false;
        
            double lot1 = GetValidatedMinLot(symbol1);
            double minLot2 = GetValidatedMinLot(symbol2);
            double lotStep2 = GetValidatedLotStep(symbol2);
            double lot2 = MathMax(minLot2, MathFloor(hedgeRatio * lot1 / lotStep2) * lotStep2);
        
            PrintFormat("[STATARB-PAIR] Executing pair | %s %.2f %s + %s %.2f %s | Hedge=%.2f",
                       symbol1, lot1, direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                       symbol2, lot2, direction == TRADE_SIGNAL_BUY ? "SELL" : "BUY",
                       hedgeRatio);
        
            return true;
        }
    
    // OU half-life filter: reversion speed must sit inside the 2.0 - 20.0 band
    bool ValidHalfLife()
    {
        // No engine = the filter is not wired, so don't block. An engine that exists but
        // has not warmed up has no half-life estimate, so it cannot clear this gate:
        // the filter fails closed during warmup.
        if(m_ouEngine == NULL)
            return true;
        if(!m_ouEngine.IsWarmedUp())
            return false;
        
        double halfLife = m_ouEngine.GetHalfLife();
        return (halfLife >= 2.0 && halfLife <= 20.0);
    }
    
    // Cointegration stand-in: both paths gate on the Python correlation matrix, so a pair
    // needs correlation >= m_minCorrelation. No cointegration test is actually run here.
    bool IsCointegrated(const string symbol1, const string symbol2)
    {
        if(m_pythonBridge != NULL && m_pythonBridge.IsConnected())
        {
            double correlation = GetPairCorrelation(symbol1, symbol2);
            return correlation >= m_minCorrelation;
        }
        
        double correlation = GetPairCorrelation(symbol1, symbol2);
        return correlation >= m_minCorrelation;
    }
};

#endif

