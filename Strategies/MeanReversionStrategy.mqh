//+------------------------------------------------------------------+
//| MeanReversionStrategy.mqh                                        |
//| Institutional Mean Reversion Strategy                            |
//| Bollinger Bands + RSI + Volume Confirmation                      |
//| Copyright 2026, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#ifndef __MEAN_REVERSION_STRATEGY_MQH__
#define __MEAN_REVERSION_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"

//+------------------------------------------------------------------+
//| Mean Reversion Entry Types                                       |
//+------------------------------------------------------------------+
enum ENUM_MR_ENTRY_TYPE
{
    MR_ENTRY_NONE = 0,
    MR_ENTRY_BB_TOUCH,      // Price touches outer Bollinger Band
    MR_ENTRY_RSI_EXTREME,   // RSI overbought/oversold
    MR_ENTRY_DOUBLE_SIGNAL  // BB touch + RSI extreme (highest confidence)
};

//+------------------------------------------------------------------+
//| Mean Reversion Signal Structure                                  |
//+------------------------------------------------------------------+
struct SMeanReversionSignal
{
    ENUM_MR_ENTRY_TYPE entryType;
    ENUM_TRADE_SIGNAL direction;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double confidence;
    string reason;
    
    SMeanReversionSignal() : 
        entryType(MR_ENTRY_NONE),
        direction(TRADE_SIGNAL_NONE),
        entryPrice(0),
        stopLoss(0),
        takeProfit(0),
        confidence(0),
        reason("") {}
};

//+------------------------------------------------------------------+
//| Mean Reversion Strategy Class                                    |
//| Institutional approach: Fade extremes with confirmation          |
//+------------------------------------------------------------------+
class CMeanReversionStrategy : public CStrategyBase
{
private:
    // Indicator Handles
    int m_bbHandle;           // Bollinger Bands (20, 2.0)
    int m_rsiHandle;          // RSI (14)
    int m_volumeHandle;       // Volume for confirmation
    
    // Configuration Parameters
    int m_bbPeriod;           // Bollinger Bands period (default: 20)
    double m_bbDeviation;     // Standard deviations (default: 2.0)
    int m_rsiPeriod;          // RSI period (default: 14)
    double m_rsiOverbought;   // Overbought threshold (default: 70)
    double m_rsiOversold;     // Oversold threshold (default: 30)
    double m_minVolumeRatio;  // Minimum volume spike ratio (default: 1.2)
    
    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager* m_riskManager;
    
    // State Tracking
    datetime m_lastSignalBar;
    int m_signalsGenerated;
    string m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;
    
    // Logging helper
    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;
        
        PrintFormat("[MEANREV] Filtered: %s | Symbol=%s | TF=%s",
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
    CMeanReversionStrategy(const string name = "Mean Reversion v1.0", int magic = 0) :
        CStrategyBase(name, magic),
        m_bbHandle(INVALID_HANDLE),
        m_rsiHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE),
        m_bbPeriod(20),
        m_bbDeviation(2.0),
        m_rsiPeriod(14),
        m_rsiOverbought(70.0),
        m_rsiOversold(30.0),
        m_minVolumeRatio(1.2),
        m_riskManager(NULL),
        m_lastSignalBar(0),
        m_signalsGenerated(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0)
    {
        m_minConfidence = 0.60; // Higher threshold for mean reversion
    }
    
    // Destructor
    ~CMeanReversionStrategy()
    {
        Cleanup();
    }
    
    // Cleanup helper
    void Cleanup()
    {
        // Handles are managed by CIndicatorManager — no IndicatorRelease needed
        m_bbHandle = INVALID_HANDLE;
        m_rsiHandle = INVALID_HANDLE;
        m_volumeHandle = INVALID_HANDLE;
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
    }
    
    // Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;
        
        // Create indicator handles via CIndicatorManager
        m_bbHandle = CIndicatorManager::Instance().GetBandsHandle(symbol, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
        m_rsiHandle = CIndicatorManager::Instance().GetRSIHandle(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
        m_volumeHandle = CIndicatorManager::Instance().GetVolumesHandle(symbol, timeframe, VOLUME_TICK);
        
        if(m_bbHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE || m_volumeHandle == INVALID_HANDLE)
        {
            Print("[MEANREV] Failed to create indicator handles");
            return false;
        }
        
        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[MEANREV] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");
        
        PrintFormat("[MEANREV] Initialized | BB(%d,%.1f) | RSI(%d) | OB=%.1f | OS=%.1f",
                   m_bbPeriod, m_bbDeviation, m_rsiPeriod, m_rsiOverbought, m_rsiOversold);
        
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
    }
    
    // Main Signal Generation
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("MEANREV_UNSET");
        
        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("MEANREV_DISABLED_OR_UNINIT");
        
        // Fetch indicator data
        double bbUpper[2], bbMiddle[2], bbLower[2];
        double rsiBuffer[2];
        double volumeBuffer[11];
        
        if(CopyBuffer(m_bbHandle, 1, 1, 2, bbUpper) < 2 ||  // Upper band
           CopyBuffer(m_bbHandle, 0, 1, 2, bbMiddle) < 2 || // Middle band
           CopyBuffer(m_bbHandle, 2, 1, 2, bbLower) < 2 ||  // Lower band
           CopyBuffer(m_rsiHandle, 0, 1, 2, rsiBuffer) < 2 ||
           CopyBuffer(m_volumeHandle, 0, 1, 11, volumeBuffer) < 11)
        {
            return RejectSignal("MEANREV_DATA_UNAVAILABLE");
        }
        
        double currentPrice = iClose(m_symbol, m_timeframe, 1);
        double prevPrice = iClose(m_symbol, m_timeframe, 2);
        
        // --- VOLUME CONFIRMATION ---
        // Current volume vs average of last 10 bars
        double currentVol = volumeBuffer[0];
        double avgVol = 0;
        for(int i = 1; i < 11; i++)
            avgVol += volumeBuffer[i];
        avgVol /= 10.0;
        
        double volRatio = (avgVol > 0) ? (currentVol / avgVol) : 1.0;
        
        if(volRatio < m_minVolumeRatio)
        {
            PrintFormat("[MEANREV-VOL] Low volume | Ratio=%.2f < %.2f", volRatio, m_minVolumeRatio);
            return RejectSignal("MEANREV_LOW_VOLUME");
        }
        
        // --- SIGNAL DETECTION ---
        SMeanReversionSignal signal = DetectMeanReversionSignal(
            currentPrice, prevPrice,
            bbUpper[0], bbMiddle[0], bbLower[0],
            rsiBuffer[0],
            volRatio
        );
        
        if(signal.direction == TRADE_SIGNAL_NONE)
            return RejectSignal("MEANREV_NO_SIGNAL");
        
        // Apply minimum confidence filter
        if(signal.confidence < m_minConfidence)
        {
            PrintFormat("[MEANREV] Low confidence | %.1f%% < %.1f%%", 
                       signal.confidence * 100, m_minConfidence * 100);
            return RejectSignal("MEANREV_LOW_CONFIDENCE");
        }
        
        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            // Calculate volatility-based SL from signal structure
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double slDistance = MathAbs(signal.entryPrice - signal.stopLoss);
            double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 50.0; // Fallback to 50 pips
            double tpDistance = MathAbs(signal.takeProfit - signal.entryPrice);
            double tpPips = (point > 0 && tpDistance > 0) ? (tpDistance / point) : slPips * 2.0;
            
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = (signal.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = 0.01;  // Placeholder - will be sized by PositionSizer
            request.stopLossPips = slPips;
            request.takeProfitPips = tpPips;
            request.confidence = signal.confidence;
            request.strategy = GetName();
            request.clusterCode = "";
            
            CUnifiedRiskManager* riskMgr = m_riskManager;
            SValidationResult result;
            ZeroMemory(result);
            if(riskMgr != NULL)
                result = (*riskMgr).ValidateTradeRequest(request, "MEANREV");
            if(!result.approved)
            {
                SetDecisionReasonTag("MEANREV_RISK_REJECTED");
                PrintFormat("[MEANREV] Risk rejected %s at %.5f (SL=%.5f TP=%.5f Conf=%.1f%%) Reason=%s",
                           signal.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           signal.entryPrice, signal.stopLoss, signal.takeProfit, signal.confidence * 100,
                           result.message);
                return TRADE_SIGNAL_NONE;
            }
        }
        
        // Update state
        m_lastSignalBar = iBars(m_symbol, m_timeframe);
        m_signalsGenerated++;
        RecordSignal();
        SetDecisionReasonTag(signal.direction == TRADE_SIGNAL_BUY ? "MEANREV_SIGNAL_BUY" : "MEANREV_SIGNAL_SELL");
        confidence = signal.confidence;
        
        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | Type: %s | BB: %.5f-%.5f | RSI: %.1f | Vol: %.2fx | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   m_symbol,
                   signal.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   EnumToString(signal.entryType),
                   bbLower[0], bbUpper[0],
                   rsiBuffer[0],
                   volRatio,
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);
        
        PrintFormat("[MEANREV] %s: %s | Entry: %.5f | SL: %.5f | TP: %.5f | Conf: %.1f%% | %s",
                   m_symbol,
                   signal.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   signal.entryPrice,
                   signal.stopLoss,
                   signal.takeProfit,
                   confidence * 100,
                   signal.reason);
        
        return signal.direction;
    }
    
    // Strategy Type
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_MEAN_REVERSION; }

    //+------------------------------------------------------------------+
    //| Quick-probe signal: fast BB + RSI extreme check (O(1) cached)   |
    //| Tier 1 fast-path for two-tier consensus evaluation.              |
    //| Uses already-cached indicator handles — no new handle creation,   |
    //| no volume confirmation, no full confidence pipeline, no risk gate.|
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetQuickProbeSignal() override
    {
        if(!m_is_enabled || !m_is_initialized)
            return TRADE_SIGNAL_NONE;

        if(m_bbHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE)
            return TRADE_SIGNAL_NONE;

        // Fetch 1 bar of BB bands and RSI (closed-bar, shift 1)
        double bbUpper[1], bbLower[1];
        double rsiBuffer[1];

        if(CopyBuffer(m_bbHandle, 1, 1, 1, bbUpper) < 1 ||
           CopyBuffer(m_bbHandle, 2, 1, 1, bbLower) < 1 ||
           CopyBuffer(m_rsiHandle, 0, 1, 1, rsiBuffer) < 1)
            return TRADE_SIGNAL_NONE;

        double currentPrice = iClose(m_symbol, m_timeframe, 1);
        double rsi = rsiBuffer[0];

        // Quick double-signal check: price at BB extreme + RSI extreme
        if(currentPrice <= bbLower[0] && rsi <= m_rsiOversold)
            return TRADE_SIGNAL_BUY;
        if(currentPrice >= bbUpper[0] && rsi >= m_rsiOverbought)
            return TRADE_SIGNAL_SELL;

        return TRADE_SIGNAL_NONE;
    }

private:
    // Detect mean reversion signal
    SMeanReversionSignal DetectMeanReversionSignal(
        double price, double prevPrice,
        double bbUpper, double bbMiddle, double bbLower,
        double rsi,
        double volRatio)  // Renamed to avoid shadowing global 'volumeRatio'
    {
        SMeanReversionSignal signal;
        
        // Check for bullish mean reversion (price oversold)
        bool priceAtLowerBB = (price <= bbLower);
        bool rsiOversold = (rsi <= m_rsiOversold);
        
        if(priceAtLowerBB && rsiOversold)
        {
            // DOUBLE SIGNAL: Highest confidence
            signal.entryType = MR_ENTRY_DOUBLE_SIGNAL;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.entryPrice = price;
            signal.stopLoss = bbLower - (bbUpper - bbLower) * 0.5; // Below lower band
            signal.takeProfit = bbMiddle; // Target middle band
            signal.confidence = 0.75 + (volRatio - 1.0) * 0.1; // Boost with volume
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "Double signal: BB lower + RSI oversold";
            
            PrintFormat("[MEANREV-SIGNAL] BUY double signal | Price=%.5f <= BB_Lower=%.5f | RSI=%.1f <= %.1f",
                       price, bbLower, rsi, m_rsiOversold);
            
            return signal;
        }
        
        if(priceAtLowerBB)
        {
            // Single signal: BB touch only
            signal.entryType = MR_ENTRY_BB_TOUCH;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.entryPrice = price;
            signal.stopLoss = bbLower - (bbUpper - bbLower) * 0.5;
            signal.takeProfit = bbMiddle; // Target middle band
            signal.confidence = 0.60 + (volRatio - 1.0) * 0.08;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "BB lower band touch";
            
            return signal;
        }
        
        if(rsiOversold)
        {
            // Single signal: RSI oversold only
            signal.entryType = MR_ENTRY_RSI_EXTREME;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.entryPrice = price;
            signal.stopLoss = price - (bbUpper - bbLower) * 0.3; // ATR-based SL
            signal.takeProfit = bbMiddle;
            signal.confidence = 0.58 + (volRatio - 1.0) * 0.07;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "RSI oversold";
            
            return signal;
        }
        
        // Check for bearish mean reversion (price overbought)
        bool priceAtUpperBB = (price >= bbUpper);
        bool rsiOverbought = (rsi >= m_rsiOverbought);
        
        if(priceAtUpperBB && rsiOverbought)
        {
            // DOUBLE SIGNAL: Highest confidence
            signal.entryType = MR_ENTRY_DOUBLE_SIGNAL;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.entryPrice = price;
            signal.stopLoss = bbUpper + (bbUpper - bbLower) * 0.5; // Above upper band
            signal.takeProfit = bbMiddle; // Target middle band
            signal.confidence = 0.75 + (volRatio - 1.0) * 0.1;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "Double signal: BB upper + RSI overbought";
            
            PrintFormat("[MEANREV-SIGNAL] SELL double signal | Price=%.5f >= BB_Upper=%.5f | RSI=%.1f >= %.1f",
                       price, bbUpper, rsi, m_rsiOverbought);
            
            return signal;
        }
        
        if(priceAtUpperBB)
        {
            // Single signal: BB touch only
            signal.entryType = MR_ENTRY_BB_TOUCH;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.entryPrice = price;
            signal.stopLoss = bbUpper + (bbUpper - bbLower) * 0.5;
            signal.takeProfit = bbMiddle; // Target middle band
            signal.confidence = 0.60 + (volRatio - 1.0) * 0.08;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "BB upper band touch";
            
            return signal;
        }
        
        if(rsiOverbought)
        {
            // Single signal: RSI overbought only
            signal.entryType = MR_ENTRY_RSI_EXTREME;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.entryPrice = price;
            signal.stopLoss = price + (bbUpper - bbLower) * 0.3;
            signal.takeProfit = bbMiddle;
            signal.confidence = 0.58 + (volRatio - 1.0) * 0.07;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "RSI overbought";
            
            return signal;
        }
        
        // No signal
        return signal;
    }
};

#endif // __MEAN_REVERSION_STRATEGY_MQH__

