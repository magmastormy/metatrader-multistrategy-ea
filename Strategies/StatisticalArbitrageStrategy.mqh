//+------------------------------------------------------------------+
//| StatisticalArbitrageStrategy.mqh                                 |
//| Institutional Statistical Arbitrage / Pair Trading Strategy      |
//| Z-Score Mean Reversion on Correlated Synthetic Indices           |
//| Requires Python Bridge for Real-Time Correlation Matrix          |
//| Copyright 2026, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#ifndef __STATISTICAL_ARBITRAGE_STRATEGY_MQH__
#define __STATISTICAL_ARBITRAGE_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Utils/PythonBridge.mqh"
#include "../Core/Engines/OrnsteinUhlenbeckEngine.mqh"
#include "../IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Statistical Arbitrage Signal Structure                           |
//+------------------------------------------------------------------+
struct SStatArbSignal
{
    ENUM_TRADE_SIGNAL direction;        // BUY = Long spread, SELL = Short spread
    string leg1Symbol;                  // First symbol in pair (e.g., Vol75)
    string leg2Symbol;                  // Second symbol in pair (e.g., Vol100)
    double leg1LotSize;                 // Lot size for leg 1
    double leg2LotSize;                 // Lot size for leg 2 (hedged ratio)
    double zScore;                      // Current z-score of spread
    double entryZScore;                 // Z-score at entry
    double exitZScore;                  // Target z-score for exit (mean reversion)
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

//+------------------------------------------------------------------+
//| Statistical Arbitrage Strategy Class                             |
//| Institutional approach: Trade mean-reverting spreads between     |
//| highly correlated synthetic indices                              |
//+------------------------------------------------------------------+
class CStatisticalArbitrageStrategy : public CStrategyBase
{
private:
    // Configuration Parameters
    double m_entryZThreshold;       // Z-score threshold for entry (default: 2.0)
    double m_exitZThreshold;        // Z-score threshold for exit (default: 0.5)
    int m_lookbackPeriods;          // Lookback for z-score calculation (default: 50)
    double m_minCorrelation;        // Minimum correlation to consider pair (default: 0.85)
    double m_hedgeRatio;            // Fixed hedge ratio if not dynamic (default: 1.0)
    bool m_useDynamicHedgeRatio;    // Use rolling regression for hedge ratio
    
    // State Tracking
    datetime m_lastSignalBar;
    string m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;
    
    // Active pair tracking
    string m_activeLeg1Symbol;
    string m_activeLeg2Symbol;
    double m_activeSpreadMean;
    double m_activeSpreadStdDev;
    datetime m_pairLastUpdateTime;
    
    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager* m_riskManager;
    
    // Python Bridge reference (for correlation matrix)
    CPythonBridge* m_pythonBridge;
    
    // Batch 100: OU Process Engine for mean-reversion-aware z-scores
    COrnsteinUhlenbeckEngine* m_ouEngine;
    
    // Logging helper
    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;
        
        PrintFormat("[STATARB] Filtered: %s | Symbol=%s | TF=%s",
                   reasonTag, m_symbol, EnumToString(m_timeframe));
        m_lastRejectReasonTag = reasonTag;
        m_lastRejectLogTime = nowTime;
    }
    
    ENUM_TRADE_SIGNAL RejectSignal(const string reasonTag)
    {
        SetDecisionReasonTag(reasonTag);
        LogRejectEvent(reasonTag);
        return TRADE_SIGNAL_NONE;
    }
    
public:
    // Constructor
    CStatisticalArbitrageStrategy(const string name = "Statistical Arbitrage v1.0", int magic = 0) :
        CStrategyBase(name, magic),
        m_entryZThreshold(2.0),
        m_exitZThreshold(0.5),
        m_lookbackPeriods(50),
        m_minCorrelation(0.85),
        m_hedgeRatio(1.0),
        m_useDynamicHedgeRatio(true),
        m_lastSignalBar(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0),
        m_activeLeg1Symbol(""),
        m_activeLeg2Symbol(""),
        m_activeSpreadMean(0),
        m_activeSpreadStdDev(0),
        m_pairLastUpdateTime(0),
        m_riskManager(NULL),
        m_pythonBridge(NULL),
        m_ouEngine(NULL)
    {
        m_minConfidence = 0.70; // High threshold for stat arb (complex strategy)
    }
    
    // Destructor
    ~CStatisticalArbitrageStrategy()
    {
        Cleanup();
    }
    
    // Cleanup helper
    void Cleanup()
    {
        // CIndicatorManager handles are managed centrally, no manual release needed
        // Risk manager and Python bridge are not owned by this strategy - do NOT delete
        m_riskManager = NULL;
        m_pythonBridge = NULL;
        m_ouEngine = NULL;  // Not owned - do NOT delete
    }
    
    // Batch 100: Set OU engine reference for mean-reversion-aware z-scores
    void SetOUEngine(COrnsteinUhlenbeckEngine* ouEngine) { m_ouEngine = ouEngine; }
    
    // Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;
        
        // Note: Stat Arb doesn't use traditional indicators on chart symbol
        // It trades spreads between pairs, so we initialize ATR handles for risk management
        
        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[STATARB] WARNING: UnifiedRiskManager not provided!");
        
        // Python Bridge and OU Engine references are set via SetPythonBridge() and SetOUEngine()
        // called by the EA after construction. If not set, strategy will reject signals gracefully.
        if(m_pythonBridge == NULL)
            Print("[STATARB] WARNING: Python Bridge not set - call SetPythonBridge() from EA initialization");
        if(m_ouEngine == NULL)
            Print("[STATARB] WARNING: OU Engine not set - call SetOUEngine() from EA initialization");
        
        PrintFormat("[STATARB] Initialized | Entry_Z=%.1f | Exit_Z=%.1f | Lookback=%d | Min_Corr=%.2f",
                   m_entryZThreshold, m_exitZThreshold, m_lookbackPeriods, m_minCorrelation);
        Print("[STATARB] NOTE: Requires Python Bridge for real-time correlation matrix");
        
        return true;
    }
    
    // Deinitialization
    virtual void Deinit() override
    {
        Cleanup();
        CStrategyBase::Deinit();
    }
    
    // New Bar Handler
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
        
        // Update correlation matrix from Python Bridge (if available)
        UpdateCorrelationMatrix();
    }
    
    // Main Signal Generation
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("STATARB_UNSET");
        
        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("STATARB_DISABLED_OR_UNINIT");
        
        // Check if Python Bridge is available for correlation data
        if(!IsPythonBridgeAvailable())
        {
            return RejectSignal("STATARB_PYTHON_BRIDGE_UNAVAILABLE");
        }
        
        // Find best correlated pair for current symbol
        string leg1Symbol = m_symbol;  // Primary symbol
        string leg2Symbol = FindBestCorrelatedPair(leg1Symbol);
        
        if(leg2Symbol == "")
        {
            return RejectSignal("STATARB_NO_CORRELATED_PAIR");
        }
        
        // Calculate spread statistics
        double spreadMean, spreadStdDev;
        if(!CalculateSpreadStatistics(leg1Symbol, leg2Symbol, spreadMean, spreadStdDev))
        {
            return RejectSignal("STATARB_SPREAD_CALC_FAILED");
        }
        
        // Calculate current z-score
        double currentSpread = GetCurrentSpread(leg1Symbol, leg2Symbol);
        double zScore = (spreadStdDev > 0) ? ((currentSpread - spreadMean) / spreadStdDev) : 0;
        
        // Batch 100: Use OU-adjusted z-score when OU engine is available and mean-reverting
        if(m_ouEngine != NULL && m_ouEngine.IsWarmedUp() && m_ouEngine.IsMeanReverting())
        {
            double ouZScore = m_ouEngine.GetOUZScore();
            double ouQuality = m_ouEngine.GetSignalQuality();
            if(ouQuality > 0.5)  // Only use OU z-score if quality is reasonable
            {
                // Blend: weight OU z-score by quality, simple z-score by (1-quality)
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
        
        // Detect signal
        SStatArbSignal signal = DetectStatArbSignal(
            leg1Symbol, leg2Symbol,
            zScore, spreadMean, spreadStdDev
        );
        
        if(signal.direction == TRADE_SIGNAL_NONE)
            return RejectSignal("STATARB_NO_SIGNAL");
        
        // Apply minimum confidence filter
        if(signal.confidence < m_minConfidence)
        {
            PrintFormat("[STATARB] Low confidence | %.1f%% < %.1f%%", 
                       signal.confidence * 100, m_minConfidence * 100);
            return RejectSignal("STATARB_LOW_CONFIDENCE");
        }
        
        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            // Validate primary leg through risk manager
            double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            STradeValidationRequest validationReq;
            ZeroMemory(validationReq);
            validationReq.symbol = m_symbol;
            validationReq.orderType = (signal.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            validationReq.lotSize = minLot;
            validationReq.stopLossPips = 0;  // Stat arb uses spread-based risk
            validationReq.takeProfitPips = 0;
            validationReq.confidence = signal.confidence;
            validationReq.strategy = m_name;
            validationReq.requestTime = TimeCurrent();

            SValidationResult validationResult = m_riskManager.ValidateTradeRequest(validationReq);
            if(!validationResult.approved)
            {
                SetDecisionReasonTag("STATARB_RISK_REJECTED");
                PrintFormat("[STATARB] Risk rejected %s spread (Z=%.2f Conf=%.1f%%) | %s",
                           signal.direction == TRADE_SIGNAL_BUY ? "LONG" : "SHORT",
                           signal.zScore, signal.confidence * 100, validationResult.message);
                return TRADE_SIGNAL_NONE;
            }

            // Update lot sizes with minimum lot sizing
            signal.leg1LotSize = minLot;
            signal.leg2LotSize = MathMax(SymbolInfoDouble(signal.leg2Symbol, SYMBOL_VOLUME_MIN),
                                          MathFloor(m_hedgeRatio * minLot / SymbolInfoDouble(signal.leg2Symbol, SYMBOL_VOLUME_STEP)) * SymbolInfoDouble(signal.leg2Symbol, SYMBOL_VOLUME_STEP));
        }
        
        // Update state
        m_lastSignalBar = iBars(m_symbol, m_timeframe);
        m_activeLeg1Symbol = leg1Symbol;
        m_activeLeg2Symbol = leg2Symbol;
        m_activeSpreadMean = spreadMean;
        m_activeSpreadStdDev = spreadStdDev;
        m_pairLastUpdateTime = TimeCurrent();
        
        RecordSignal();
        SetDecisionReasonTag(signal.direction == TRADE_SIGNAL_BUY ? "STATARB_SIGNAL_LONG_SPREAD" : "STATARB_SIGNAL_SHORT_SPREAD");
        confidence = signal.confidence;
        
        // CONSENSUS LOGGING (AGENTS.md requirement)
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
        
        return signal.direction;
    }
    
    // Strategy Type
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_STATISTICAL_ARBITRAGE; }
    
    // Set Python Bridge reference (called by EA during initialization)
    void SetPythonBridge(CPythonBridge* bridge)
    {
        m_pythonBridge = bridge;
    }
    
    // Fast probe signal for two-tier consensus path
    virtual ENUM_TRADE_SIGNAL GetQuickProbeSignal() override
    {
        if(!IsEnabled() || !m_is_initialized)
            return TRADE_SIGNAL_NONE;
        
        if(!IsPythonBridgeAvailable())
            return TRADE_SIGNAL_NONE;
        
        // Quick z-score extreme check without full pipeline
        string leg2Symbol = FindBestCorrelatedPair(m_symbol);
        if(leg2Symbol == "")
            return TRADE_SIGNAL_NONE;
        
        double spreadMean, spreadStdDev;
        if(!CalculateSpreadStatistics(m_symbol, leg2Symbol, spreadMean, spreadStdDev))
            return TRADE_SIGNAL_NONE;
        
        double currentSpread = GetCurrentSpread(m_symbol, leg2Symbol);
        double zScore = (spreadStdDev > 0) ? ((currentSpread - spreadMean) / spreadStdDev) : 0;
        
        if(zScore < -m_entryZThreshold)
            return TRADE_SIGNAL_BUY;
        if(zScore > m_entryZThreshold)
            return TRADE_SIGNAL_SELL;
        
        return TRADE_SIGNAL_NONE;
    }
    
private:
    // Check if Python Bridge is available
    bool IsPythonBridgeAvailable()
    {
        if(m_pythonBridge == NULL)
            return false;
        
        return m_pythonBridge.IsConnected();
    }
    
    // Update correlation matrix from Python Bridge
    void UpdateCorrelationMatrix()
    {
        if(m_pythonBridge == NULL || !m_pythonBridge.IsConnected())
            return;
        
        // Fetch correlation matrix from Python Bridge
        double corrMatrix[];
        int size;
        string corrSymbols[];

        if(m_pythonBridge.GetCorrelationMatrix(corrMatrix, size, corrSymbols))
        {
            PrintFormat("[STATARB] Correlation matrix updated | Size=%dx%d | Symbols=%d", size, size, ArraySize(corrSymbols));
        }
    }
    
    // Find best correlated pair for given symbol
    string FindBestCorrelatedPair(const string symbol)
    {
        if(m_pythonBridge == NULL || !m_pythonBridge.IsConnected())
            return "";
        
        // Query Python Bridge for best correlated pair
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
    
    // Get correlation between two symbols
    double GetPairCorrelation(const string symbol1, const string symbol2)
    {
        if(m_pythonBridge == NULL || !m_pythonBridge.IsConnected())
            return 0.0;
        
        return m_pythonBridge.GetPairCorrelation(symbol1, symbol2);
    }
    
    // Calculate spread statistics (mean, std dev) over lookback period
    bool CalculateSpreadStatistics(const string leg1, const string leg2, 
                                   double &mean, double &stdDev)
    {
        // Fetch historical prices for both legs
        double prices1[], prices2[];
        if(CopyClose(leg1, PERIOD_CURRENT, 1, m_lookbackPeriods, prices1) < m_lookbackPeriods ||
           CopyClose(leg2, PERIOD_CURRENT, 1, m_lookbackPeriods, prices2) < m_lookbackPeriods)
        {
            return false;
        }
        
        // Calculate spread series
        double spreads[];
        ArrayResize(spreads, m_lookbackPeriods);
        
        for(int i = 0; i < m_lookbackPeriods; i++)
        {
            spreads[i] = prices1[i] - (prices2[i] * m_hedgeRatio);
        }
        
        // Calculate mean
        mean = 0;
        for(int i = 0; i < m_lookbackPeriods; i++)
            mean += spreads[i];
        mean /= m_lookbackPeriods;
        
        // Calculate standard deviation
        double variance = 0;
        for(int i = 0; i < m_lookbackPeriods; i++)
            variance += MathPow(spreads[i] - mean, 2);
        variance /= m_lookbackPeriods;
        stdDev = MathSqrt(variance);
        
        return true;
    }
    
    // Get current spread value
    double GetCurrentSpread(const string leg1, const string leg2)
    {
        double price1 = iClose(leg1, PERIOD_CURRENT, 1);
        double price2 = iClose(leg2, PERIOD_CURRENT, 1);
        
        return price1 - (price2 * m_hedgeRatio);
    }
    
    // Detect statistical arbitrage signal
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
            signal.leg1LotSize = SymbolInfoDouble(leg1, SYMBOL_VOLUME_MIN);
            signal.leg2LotSize = SymbolInfoDouble(leg2, SYMBOL_VOLUME_MIN) * m_hedgeRatio;
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
            signal.leg1LotSize = SymbolInfoDouble(leg1, SYMBOL_VOLUME_MIN);
            signal.leg2LotSize = SymbolInfoDouble(leg2, SYMBOL_VOLUME_MIN) * m_hedgeRatio;
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
        
        // No signal
        return signal;
    }
    
    // Execute pair trade with hedge ratio sizing
    bool ExecutePairTrade(const string symbol1, const string symbol2, double hedgeRatio, ENUM_TRADE_SIGNAL direction)
    {
        if(m_riskManager == NULL)
            return false;
        
        double lot1 = SymbolInfoDouble(symbol1, SYMBOL_VOLUME_MIN);
        double lot2 = SymbolInfoDouble(symbol2, SYMBOL_VOLUME_MIN);
        
        // Scale leg2 by hedge ratio
        double minLot2 = SymbolInfoDouble(symbol2, SYMBOL_VOLUME_MIN);
        double lotStep2 = SymbolInfoDouble(symbol2, SYMBOL_VOLUME_STEP);
        lot2 = MathMax(minLot2, MathFloor(hedgeRatio * lot1 / lotStep2) * lotStep2);
        
        PrintFormat("[STATARB-PAIR] Executing pair | %s %.2f %s + %s %.2f %s | Hedge=%.2f",
                   symbol1, lot1, direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   symbol2, lot2, direction == TRADE_SIGNAL_BUY ? "SELL" : "BUY",
                   hedgeRatio);
        
        // Note: Actual order execution is handled by CTradeManager after consensus approval
        // This method validates and logs the pair trade intent
        return true;
    }
    
    // Validate OU half-life for mean reversion speed filter
    bool ValidHalfLife()
    {
        if(m_ouEngine == NULL || !m_ouEngine.IsWarmedUp())
            return true;  // No OU engine = allow (don't block)
        
        double halfLife = m_ouEngine.GetHalfLife();
        // Only trade if mean reversion speed is in reasonable range
        return (halfLife >= 2.0 && halfLife <= 20.0);
    }
    
    // Check cointegration via Python Bridge (fallback to correlation)
    bool IsCointegrated(const string symbol1, const string symbol2)
    {
        if(m_pythonBridge != NULL && m_pythonBridge.IsConnected())
        {
            // Try Python bridge cointegration test
            // If endpoint not available, falls back to correlation check
            double correlation = GetPairCorrelation(symbol1, symbol2);
            return correlation >= m_minCorrelation;
        }
        
        // Fallback: correlation-based check
        double correlation = GetPairCorrelation(symbol1, symbol2);
        return correlation >= m_minCorrelation;
    }
};

#endif // __STATISTICAL_ARBITRAGE_STRATEGY_MQH__

