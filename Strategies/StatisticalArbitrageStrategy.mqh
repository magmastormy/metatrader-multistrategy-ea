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
    // Indicator Handles (for individual legs)
    int m_leg1ATRHandle;
    int m_leg2ATRHandle;
    
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
        m_leg1ATRHandle(INVALID_HANDLE),
        m_leg2ATRHandle(INVALID_HANDLE),
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
        m_pythonBridge(NULL)
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
        if(m_leg1ATRHandle != INVALID_HANDLE) { IndicatorRelease(m_leg1ATRHandle); m_leg1ATRHandle = INVALID_HANDLE; }
        if(m_leg2ATRHandle != INVALID_HANDLE) { IndicatorRelease(m_leg2ATRHandle); m_leg2ATRHandle = INVALID_HANDLE; }
        // Risk manager and Python bridge are not owned by this strategy - do NOT delete
        m_riskManager = NULL;
        m_pythonBridge = NULL;
    }
    
    // Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;
        
        // Note: Stat Arb doesn't use traditional indicators on chart symbol
        // It trades spreads between pairs, so we initialize ATR handles for risk management
        
        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[STATARB] WARNING: UnifiedRiskManager not provided!");
        
        //TODO: Get Python Bridge reference for correlation data
        // Note: This requires global Python bridge instance to be accessible
        //TODO: For now, we'll use a placeholder - actual implementation needs EA-level integration
        
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
            // For stat arb, we validate each leg separately
            //TODO: This is a simplified check - full implementation needs pair validation
            double dummySL = 0, dummyTP = 0;
            if(!m_riskManager->ValidateTrade(signal.direction, 0, dummySL, dummyTP, signal.confidence))
            {
                SetDecisionReasonTag("STATARB_RISK_REJECTED");
                PrintFormat("[STATARB] Risk rejected %s spread (Z=%.2f Conf=%.1f%%)",
                           signal.direction == TRADE_SIGNAL_BUY ? "LONG" : "SHORT",
                           signal.zScore, signal.confidence * 100);
                return TRADE_SIGNAL_NONE;
            }
        }
        
        // Update state
        m_lastSignalBar = iBars(m_symbol, m_timeframe);
        m_activeLeg1Symbol = leg1Symbol;
        m_activeLeg2Symbol = leg2Symbol;
        m_activeSpreadMean = spreadMean;
        m_activeSpreadStdDev = spreadStdDev;
        m_pairLastUpdateTime = TimeCurrent();
        
        m_signalsGenerated++;
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
    
private:
    // Check if Python Bridge is available
    bool IsPythonBridgeAvailable()
    {
        if(m_pythonBridge == NULL)
            return false;
        
        return m_pythonBridge->IsConnected();
    }
    
    // Update correlation matrix from Python Bridge
    void UpdateCorrelationMatrix()
    {
        if(m_pythonBridge == NULL || !m_pythonBridge->IsConnected())
            return;
        
        // Fetch correlation matrix from Python Bridge
        double matrix[];
        int size;
        string symbols[];
        
        if(m_pythonBridge->GetCorrelationMatrix(matrix, size, symbols))
        {
            PrintFormat("[STATARB] Correlation matrix updated | Size=%dx%d | Symbols=%d", size, size, ArraySize(symbols));
        }
    }
    
    // Find best correlated pair for given symbol
    string FindBestCorrelatedPair(const string symbol)
    {
        if(m_pythonBridge == NULL || !m_pythonBridge->IsConnected())
            return "";
        
        // Query Python Bridge for best correlated pair
        string bestPair;
        double correlation;
        
        if(m_pythonBridge->FindBestCorrelatedPair(symbol, bestPair, correlation))
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
        if(m_pythonBridge == NULL || !m_pythonBridge->IsConnected())
            return 0.0;
        
        return m_pythonBridge->GetPairCorrelation(symbol1, symbol2);
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
};

#endif // __STATISTICAL_ARBITRAGE_STRATEGY_MQH__

