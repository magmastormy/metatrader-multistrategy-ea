//+------------------------------------------------------------------+
//| VolatilityBreakoutStrategy.mqh                                   |
//| Institutional Volatility Breakout Strategy                       |
//| Bollinger Band Squeeze + Volume Surge + ATR Stops                |
//| Copyright 2026, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#ifndef __VOLATILITY_BREAKOUT_STRATEGY_MQH__
#define __VOLATILITY_BREAKOUT_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"

//+------------------------------------------------------------------+
//| Volatility Breakout Entry Types                                  |
//+------------------------------------------------------------------+
enum ENUM_VB_ENTRY_TYPE
{
    VB_ENTRY_NONE = 0,
    VB_ENTRY_SQUEEZE_BREAKOUT,     // Breakout from BB squeeze
    VB_ENTRY_ATR_EXPANSION,        // ATR expansion breakout
    VB_ENTRY_COMBINED_SIGNAL       // Squeeze + ATR + Volume (highest confidence)
};

//+------------------------------------------------------------------+
//| Volatility Breakout Signal Structure                             |
//+------------------------------------------------------------------+
struct SVolatilityBreakoutSignal
{
    ENUM_VB_ENTRY_TYPE entryType;
    ENUM_TRADE_SIGNAL direction;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double confidence;
    string reason;
    
    SVolatilityBreakoutSignal() : 
        entryType(VB_ENTRY_NONE),
        direction(TRADE_SIGNAL_NONE),
        entryPrice(0),
        stopLoss(0),
        takeProfit(0),
        confidence(0),
        reason("") {}
};

//+------------------------------------------------------------------+
//| Volatility Breakout Strategy Class                               |
//| Institutional approach: Trade explosive moves from contraction   |
//+------------------------------------------------------------------+
class CVolatilityBreakoutStrategy : public CStrategyBase
{
private:
    // Indicator Handles
    int m_bbHandle;           // Bollinger Bands for squeeze detection
    int m_atrHandle;          // ATR for volatility measurement
    int m_volumeHandle;       // Volume for confirmation
    
    // Configuration Parameters
    int m_bbPeriod;           // Bollinger Bands period (default: 20)
    double m_bbDeviation;     // Standard deviations (default: 2.0)
    int m_atrPeriod;          // ATR period (default: 14)
    double m_squeezeThreshold;// BB width percentile threshold (default: 0.20 = 20th percentile)
    double m_volumeMultiplier;// Volume surge multiplier (default: 1.5x average)
    double m_atrExpansionMult;// ATR expansion multiplier (default: 1.3x)
    int m_lookbackPeriods;    // Lookback for squeeze detection (default: 10)
    
    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager* m_riskManager;
    
    // State Tracking
    datetime m_lastSignalBar;
    int m_signalsGenerated;
    string m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;
    bool m_inSqueeze;         // Track if we're in a squeeze state
    
    // Logging helper
    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;
        
        PrintFormat("[VOLBREAK] Filtered: %s | Symbol=%s | TF=%s",
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
    CVolatilityBreakoutStrategy(const string name = "Volatility Breakout v1.0", int magic = 0) :
        CStrategyBase(name, magic),
        m_bbHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE),
        m_bbPeriod(20),
        m_bbDeviation(2.0),
        m_atrPeriod(14),
        m_squeezeThreshold(0.20),
        m_volumeMultiplier(1.5),
        m_atrExpansionMult(1.3),
        m_lookbackPeriods(10),
        m_riskManager(NULL),
        m_lastSignalBar(0),
        m_signalsGenerated(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0),
        m_inSqueeze(false)
    {
        m_minConfidence = 0.65; // Higher threshold for breakout trades
    }
    
    // Destructor
    ~CVolatilityBreakoutStrategy()
    {
        Cleanup();
    }
    
    // Cleanup helper
    void Cleanup()
    {
        // Handles are managed by CIndicatorManager — no IndicatorRelease needed
        m_bbHandle = INVALID_HANDLE;
        m_atrHandle = INVALID_HANDLE;
        m_volumeHandle = INVALID_HANDLE;
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
    }
    
    // Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;
        
        // Create indicator handles via CIndicatorManager
        m_bbHandle = CIndicatorManager::Instance().GetBandsHandle(symbol, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
        m_atrHandle = CIndicatorManager::Instance().GetATRHandle(symbol, timeframe, m_atrPeriod);
        m_volumeHandle = CIndicatorManager::Instance().GetVolumesHandle(symbol, timeframe, VOLUME_TICK);
        
        if(m_bbHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE || m_volumeHandle == INVALID_HANDLE)
        {
            Print("[VOLBREAK] Failed to create indicator handles");
            return false;
        }
        
        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[VOLBREAK] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");
        
        PrintFormat("[VOLBREAK] Initialized | BB(%d,%.1f) | ATR(%d) | Squeeze=%.0f%% | Vol=%.1fx | ATR_Exp=%.1fx",
                   m_bbPeriod, m_bbDeviation, m_atrPeriod, 
                   m_squeezeThreshold * 100, m_volumeMultiplier, m_atrExpansionMult);
        
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
        SetDecisionReasonTag("VOLBREAK_UNSET");
        
        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("VOLBREAK_DISABLED_OR_UNINIT");
        
        // Fetch indicator data
        double bbUpper[2], bbMiddle[2], bbLower[2];
        double atrBuffer[12];  // Current + lookback for comparison
        double volumeBuffer[11];
        
        if(CopyBuffer(m_bbHandle, 1, 1, 2, bbUpper) < 2 ||  // Upper band
           CopyBuffer(m_bbHandle, 0, 1, 2, bbMiddle) < 2 || // Middle band
           CopyBuffer(m_bbHandle, 2, 1, 2, bbLower) < 2 ||  // Lower band
           CopyBuffer(m_atrHandle, 0, 1, 12, atrBuffer) < 12 ||
           CopyBuffer(m_volumeHandle, 0, 1, 11, volumeBuffer) < 11)
        {
            return RejectSignal("VOLBREAK_DATA_UNAVAILABLE");
        }
        
        double currentPrice = iClose(m_symbol, m_timeframe, 1);
        double prevPrice = iClose(m_symbol, m_timeframe, 2);
        
        // --- VOLUME CONFIRMATION ---
        double currentVol = volumeBuffer[0];
        double avgVol = 0;
        for(int i = 1; i < 11; i++)
            avgVol += volumeBuffer[i];
        avgVol /= 10.0;
        
        double volRatio = (avgVol > 0) ? (currentVol / avgVol) : 1.0;
        
        // --- VOLATILITY ANALYSIS ---
        double curATR = atrBuffer[0];
        double avgATR = 0;
        for(int i = 1; i < 11; i++)
            avgATR += atrBuffer[i];
        avgATR /= 10.0;
        
        double atrRatio = (avgATR > 0) ? (curATR / avgATR) : 1.0;
        
        // Calculate BB width for squeeze detection
        double bbWidth = bbUpper[0] - bbLower[0];
        double bbWidthPercent = (bbMiddle[0] > 0) ? (bbWidth / bbMiddle[0]) : 0;
        
        // Detect squeeze state
        bool isInSqueeze = DetectSqueezeState(bbWidthPercent);
        
        // --- SIGNAL DETECTION ---
        SVolatilityBreakoutSignal signal = DetectBreakoutSignal(
            currentPrice, prevPrice,
            bbUpper[0], bbMiddle[0], bbLower[0],
            curATR, atrRatio,
            volRatio,
            isInSqueeze
        );
        
        if(signal.direction == TRADE_SIGNAL_NONE)
            return RejectSignal("VOLBREAK_NO_SIGNAL");
        
        // Apply minimum confidence filter
        if(signal.confidence < m_minConfidence)
        {
            PrintFormat("[VOLBREAK] Low confidence | %.1f%% < %.1f%%", 
                       signal.confidence * 100, m_minConfidence * 100);
            return RejectSignal("VOLBREAK_LOW_CONFIDENCE");
        }
        
        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = (signal.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = 0.01;
            request.stopLossPips = (signal.stopLoss > 0) ? MathAbs(signal.entryPrice - signal.stopLoss) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.takeProfitPips = (signal.takeProfit > 0) ? MathAbs(signal.takeProfit - signal.entryPrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.confidence = signal.confidence;
            request.strategy = GetName();
            request.clusterCode = "";
            
            CUnifiedRiskManager* riskMgr = m_riskManager;
            SValidationResult result;
            ZeroMemory(result);
            if(riskMgr != NULL)
                result = (*riskMgr).ValidateTradeRequest(request, "VOLBREAK");
            if(!result.approved)
            {
                SetDecisionReasonTag("VOLBREAK_RISK_REJECTED");
                PrintFormat("[VOLBREAK] Risk rejected %s at %.5f (SL=%.5f TP=%.5f Conf=%.1f%%) Reason=%s",
                           signal.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           signal.entryPrice, signal.stopLoss, signal.takeProfit, signal.confidence * 100,
                           result.message);
                return TRADE_SIGNAL_NONE;
            }
        }
        
        // Update state
        m_lastSignalBar = iBars(m_symbol, m_timeframe);
        m_inSqueeze = isInSqueeze;
        m_signalsGenerated++;
        RecordSignal();
        SetDecisionReasonTag(signal.direction == TRADE_SIGNAL_BUY ? "VOLBREAK_SIGNAL_BUY" : "VOLBREAK_SIGNAL_SELL");
        confidence = signal.confidence;
        
        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | Type: %s | BB_Width=%.4f%% | ATR_Ratio=%.2f | Vol=%.2fx | Squeeze=%s | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   m_symbol,
                   signal.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   EnumToString(signal.entryType),
                   bbWidthPercent * 100,
                   atrRatio,
                   volRatio,
                   isInSqueeze ? "YES" : "NO",
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);
        
        PrintFormat("[VOLBREAK] %s: %s | Entry: %.5f | SL: %.5f | TP: %.5f | Conf: %.1f%% | %s",
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
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_VOLATILITY_BREAKOUT; }
    
private:
    // Detect if market is in squeeze state
    bool DetectSqueezeState(double currentBBWidthPercent)
    {
        // Fetch historical BB widths
        double bbUpperHist[], bbLowerHist[], bbMiddleHist[];
        int historySize = m_lookbackPeriods + 2;
        
        if(CopyBuffer(m_bbHandle, 1, 1, historySize, bbUpperHist) < historySize ||
           CopyBuffer(m_bbHandle, 2, 1, historySize, bbLowerHist) < historySize ||
           CopyBuffer(m_bbHandle, 0, 1, historySize, bbMiddleHist) < historySize)
        {
            return false; // Cannot determine
        }
        
        // Calculate BB width percentiles
        double widths[];
        ArrayResize(widths, m_lookbackPeriods);
        
        for(int i = 0; i < m_lookbackPeriods; i++)
        {
            double width = bbUpperHist[i] - bbLowerHist[i];
            double widthPct = (bbMiddleHist[i] > 0) ? (width / bbMiddleHist[i]) : 0;
            widths[i] = widthPct;
        }
        
        // Sort to find percentile
        ArraySort(widths);
        
        // Find 20th percentile threshold
        int percentileIndex = (int)(m_lookbackPeriods * m_squeezeThreshold);
        percentileIndex = MathMax(0, MathMin(percentileIndex, m_lookbackPeriods - 1));
        double squeezeThreshold = widths[percentileIndex];
        
        // Current width below threshold = squeeze
        bool inSqueeze = (currentBBWidthPercent <= squeezeThreshold);
        
        if(inSqueeze && !m_inSqueeze)
        {
            PrintFormat("[VOLBREAK-SQUEEZE] Squeeze detected | Width=%.4f%% <= Threshold=%.4f%%",
                       currentBBWidthPercent * 100, squeezeThreshold * 100);
        }
        
        return inSqueeze;
    }
    
    // Detect breakout signal
    SVolatilityBreakoutSignal DetectBreakoutSignal(
        double price, double prevPrice,
        double bbUpper, double bbMiddle, double bbLower,
        double curATR, double atrRatio,
        double volRatio,
        bool isInSqueeze)
    {
        SVolatilityBreakoutSignal signal;
        
        // Check for bullish breakout
        bool brokeAboveBB = (price > bbUpper && prevPrice <= bbUpper);
        bool atrExpanding = (atrRatio >= m_atrExpansionMult);
        bool volumeSurge = (volRatio >= m_volumeMultiplier);
        
        if(brokeAboveBB)
        {
            if(isInSqueeze && atrExpanding && volumeSurge)
            {
                // COMBINED SIGNAL: Highest confidence
                signal.entryType = VB_ENTRY_COMBINED_SIGNAL;
                signal.direction = TRADE_SIGNAL_BUY;
                signal.entryPrice = price;
                signal.stopLoss = bbMiddle; // Below middle band
                signal.takeProfit = price + (curATR * 2.5); // 2.5x ATR target
                signal.confidence = 0.80 + (volRatio - 1.0) * 0.05; // Boost with volume
                signal.confidence = MathMin(1.0, signal.confidence);
                signal.reason = "Combined: Squeeze breakout + ATR expansion + Volume surge";
                
                PrintFormat("[VOLBREAK-SIGNAL] BUY combined signal | Price=%.5f > BB_Upper=%.5f | ATR_Ratio=%.2f | Vol=%.2fx",
                           price, bbUpper, atrRatio, volRatio);
                
                return signal;
            }
            
            if(isInSqueeze || atrExpanding)
            {
                // Squeeze or ATR breakout
                signal.entryType = VB_ENTRY_SQUEEZE_BREAKOUT;
                signal.direction = TRADE_SIGNAL_BUY;
                signal.entryPrice = price;
                signal.stopLoss = bbMiddle;
                signal.takeProfit = price + (curATR * 2.0); // 2x ATR target
                signal.confidence = 0.70 + (volRatio - 1.0) * 0.05;
                signal.confidence = MathMin(1.0, signal.confidence);
                signal.reason = isInSqueeze ? "Squeeze breakout" : "ATR expansion breakout";
                
                return signal;
            }
            
            // Simple BB breakout
            if(volumeSurge)
            {
                signal.entryType = VB_ENTRY_ATR_EXPANSION;
                signal.direction = TRADE_SIGNAL_BUY;
                signal.entryPrice = price;
                signal.stopLoss = bbMiddle;
                signal.takeProfit = price + (curATR * 1.8);
                signal.confidence = 0.65;
                signal.reason = "BB breakout with volume";
                
                return signal;
            }
        }
        
        // Check for bearish breakout
        bool brokeBelowBB = (price < bbLower && prevPrice >= bbLower);
        
        if(brokeBelowBB)
        {
            if(isInSqueeze && atrExpanding && volumeSurge)
            {
                // COMBINED SIGNAL: Highest confidence
                signal.entryType = VB_ENTRY_COMBINED_SIGNAL;
                signal.direction = TRADE_SIGNAL_SELL;
                signal.entryPrice = price;
                signal.stopLoss = bbMiddle; // Above middle band
                signal.takeProfit = price - (curATR * 2.5);
                signal.confidence = 0.80 + (volRatio - 1.0) * 0.05;
                signal.confidence = MathMin(1.0, signal.confidence);
                signal.reason = "Combined: Squeeze breakout + ATR expansion + Volume surge";
                
                PrintFormat("[VOLBREAK-SIGNAL] SELL combined signal | Price=%.5f < BB_Lower=%.5f | ATR_Ratio=%.2f | Vol=%.2fx",
                           price, bbLower, atrRatio, volRatio);
                
                return signal;
            }
            
            if(isInSqueeze || atrExpanding)
            {
                // Squeeze or ATR breakout
                signal.entryType = VB_ENTRY_SQUEEZE_BREAKOUT;
                signal.direction = TRADE_SIGNAL_SELL;
                signal.entryPrice = price;
                signal.stopLoss = bbMiddle;
                signal.takeProfit = price - (curATR * 2.0);
                signal.confidence = 0.70 + (volRatio - 1.0) * 0.05;
                signal.confidence = MathMin(1.0, signal.confidence);
                signal.reason = isInSqueeze ? "Squeeze breakout" : "ATR expansion breakout";
                
                return signal;
            }
            
            // Simple BB breakout
            if(volumeSurge)
            {
                signal.entryType = VB_ENTRY_ATR_EXPANSION;
                signal.direction = TRADE_SIGNAL_SELL;
                signal.entryPrice = price;
                signal.stopLoss = bbMiddle;
                signal.takeProfit = price - (curATR * 1.8);
                signal.confidence = 0.65;
                signal.reason = "BB breakout with volume";
                
                return signal;
            }
        }
        
        // No signal
        return signal;
    }
};

#endif // __VOLATILITY_BREAKOUT_STRATEGY_MQH__

