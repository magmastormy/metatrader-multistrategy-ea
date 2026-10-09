// Institutional Volatility Breakout Strategy
// Bollinger Band Squeeze + Volume Surge + ATR Stops
// Copyright 2026, Multi-Strategy EA
#ifndef VOLATILITY_BREAKOUT_STRATEGY_MQH
#define VOLATILITY_BREAKOUT_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Utilities/SafeCopyBuffer.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"

// Volatility Breakout Entry Types
enum ENUM_VB_ENTRY_TYPE
{
    VB_ENTRY_NONE = 0,
    VB_ENTRY_SQUEEZE_BREAKOUT,
    VB_ENTRY_ATR_EXPANSION,        // ATR expansion breakout
    VB_ENTRY_COMBINED_SIGNAL,       // Squeeze + ATR + Volume (highest confidence)
    VB_ENTRY_DOUBLE_SQUEEZE,       // BB + KC double squeeze (TTM Squeeze)
    VB_ENTRY_RETEST,               // Breakout + retest confirmation
    VB_ENTRY_FAILURE_REVERSAL      // Breakout failure reversal
};

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

// Institutional approach: Trade explosive moves from contraction
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
    double m_atrStopMult;      // ATR-based stop distance (default: 1.5) — F6: capital-efficient SL
    double m_atrTargetMult;    // ATR-based target distance (default: 3.0) — 2.0R designed profile
    
    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager* m_riskManager;
    
    // State Tracking
    datetime m_lastSignalBar;
    int m_signalsGenerated;
    bool m_inSqueeze;         // Track if we're in a squeeze state
    int     m_kcEmaHandle;        // Keltner Channel EMA midline (v2.0)
    int     m_adxHandle;          // ADX rising filter (v2.0)
    double  m_squeezeHighPrice;   // Price level when squeeze detected (for retest)
    double  m_squeezeLowPrice;    // Price level when squeeze detected (for retest)
    int     m_squeezeBar;         // Bar index when squeeze was detected
    bool    m_breakoutFailed;     // Breakout failure reversal flag
    ENUM_TRADE_SIGNAL m_breakoutFailedDirection; // Direction of failed breakout reversal
    
    // Fallback BB calculation from raw price data when indicator handle fails
    bool CalculateFallbackBB(double &outUpper, double &outMiddle, double &outLower)
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int needed = m_bbPeriod + 5;
        // Batch 169: copy from shift 1. Copying from 0 put the still-forming
        // bar in rates[0], so the band was stretched by a bar whose close had
        // not happened yet - the breakout level moved as the bar moved.
        int copied = CopyRates(m_symbol, m_timeframe, 1, needed, rates);
        if(copied < m_bbPeriod)
            return false;

        // Compute mean of close prices over bbPeriod closed bars
        double sum = 0;
        for(int i = 0; i < m_bbPeriod; i++)
            sum += rates[i].close;
        double mean = sum / m_bbPeriod;

        // Compute standard deviation
        double sumSqDiff = 0;
        for(int i = 0; i < m_bbPeriod; i++)
        {
            double diff = rates[i].close - mean;
            sumSqDiff += diff * diff;
        }
        double stdDev = MathSqrt(sumSqDiff / m_bbPeriod);

        outUpper  = mean + m_bbDeviation * stdDev;
        outMiddle = mean;
        outLower  = mean - m_bbDeviation * stdDev;
        return true;
    }

    // Fallback ATR calculation from raw price data when indicator handle fails
    bool CalculateFallbackATR(double &outATR)
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int needed = m_atrPeriod + 5;
        // Batch 169: shift 1 so the forming bar cannot inflate ATR - this
        // feeds the stop distance, so an inflated reading widened stops and
        // the risk charged for them.
        int copied = CopyRates(m_symbol, m_timeframe, 1, needed, rates);
        if(copied < m_atrPeriod + 1)  // Need prev close for True Range
            return false;

        // Compute True Range for each closed bar, then average over atrPeriod bars
        double sumTR = 0;
        for(int i = 0; i < m_atrPeriod; i++)
        {
            double highLow    = rates[i].high - rates[i].low;
            double highPrevCl = MathAbs(rates[i].high - rates[i + 1].close);
            double lowPrevCl  = MathAbs(rates[i].low  - rates[i + 1].close);
            double tr = MathMax(highLow, MathMax(highPrevCl, lowPrevCl));
            sumTR += tr;
        }
        outATR = sumTR / m_atrPeriod;
        return true;
    }

public:
    CVolatilityBreakoutStrategy(const string name = "Volatility Breakout v2.0", int magic = 0) :
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
        m_atrStopMult(1.5),
        m_atrTargetMult(3.0),
        m_riskManager(NULL),
        m_lastSignalBar(0),
        m_signalsGenerated(0),
        m_inSqueeze(false),
        m_kcEmaHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_squeezeHighPrice(0),
        m_squeezeLowPrice(0),
        m_squeezeBar(0),
        m_breakoutFailed(false),
        m_breakoutFailedDirection(TRADE_SIGNAL_NONE)
    {
        m_strategyPrefix = "VOLBREAK";
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
        m_kcEmaHandle = INVALID_HANDLE;
        m_adxHandle = INVALID_HANDLE;
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
    }
    
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;
        
        // Create indicator handles via CIndicatorManager
        m_bbHandle = CIndicatorManager::Instance().GetBandsHandle(symbol, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
        m_atrHandle = CIndicatorManager::Instance().GetATRHandle(symbol, timeframe, m_atrPeriod);
        m_volumeHandle = CIndicatorManager::Instance().GetVolumesHandle(symbol, timeframe, VOLUME_TICK);

        // v2.0: Keltner Channel EMA and ADX handles
        m_kcEmaHandle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
        m_adxHandle = CIndicatorManager::Instance().GetADXHandle(m_symbol, m_timeframe, 14);
        
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
        
        // Fetch BB indicator data (with fallback)
        double bbUpper[2], bbMiddle[2], bbLower[2];
        bool bbFromFallback = false;
        if(!SafeCopyBuffer(m_bbHandle, 1, 1, 2, bbUpper) ||  // Upper band
           !SafeCopyBuffer(m_bbHandle, 0, 1, 2, bbMiddle) || // Middle band
           !SafeCopyBuffer(m_bbHandle, 2, 1, 2, bbLower))    // Lower band
        {
            // Fallback: compute BB from raw price data
            double fbUpper, fbMiddle, fbLower;
            if(CalculateFallbackBB(fbUpper, fbMiddle, fbLower))
            {
                bbUpper[0]  = fbUpper;
                bbUpper[1]  = fbUpper;
                bbMiddle[0] = fbMiddle;
                bbMiddle[1] = fbMiddle;
                bbLower[0]  = fbLower;
                bbLower[1]  = fbLower;
                bbFromFallback = true;
                PrintFormat("[VOLBREAK-FALLBACK] BB calculated from raw rates | Upper=%.5f Middle=%.5f Lower=%.5f | Symbol=%s TF=%s",
                           fbUpper, fbMiddle, fbLower, m_symbol, EnumToString(m_timeframe));
            }
            else
            {
                return RejectSignal("VOLBREAK_DATA_UNAVAILABLE");
            }
        }

        // Fetch ATR indicator data (with fallback)
        double atrBuffer[12];  // Current + lookback for comparison
        bool atrFromFallback = false;
        if(!SafeCopyBuffer(m_atrHandle, 0, 1, 12, atrBuffer))
        {
            // Fallback: compute ATR from raw price data
            double fbATR;
            if(CalculateFallbackATR(fbATR))
            {
                // Fill buffer with fallback value for current and historical comparison
                for(int i = 0; i < 12; i++)
                    atrBuffer[i] = fbATR;
                atrFromFallback = true;
                PrintFormat("[VOLBREAK-FALLBACK] ATR calculated from raw rates | ATR=%.5f | Symbol=%s TF=%s",
                           fbATR, m_symbol, EnumToString(m_timeframe));
            }
            else
            {
                return RejectSignal("VOLBREAK_DATA_UNAVAILABLE");
            }
        }

        // Fetch volume data (confirmation-only — treat failure as volume unavailable)
        double volumeBuffer[11];
        bool volumeAvailable = SafeCopyBuffer(m_volumeHandle, 0, 1, 11, volumeBuffer);
        
        double currentPrice = iClose(m_symbol, m_timeframe, 1);
        double prevPrice = iClose(m_symbol, m_timeframe, 2);
        
        // --- VOLUME CONFIRMATION ---
        // Batch 150: static arrays are NOT as-series - [0] is the OLDEST of the
        // copied window. count=11,start=1 -> newest (shift 1) is index 10.
        double volRatio = 1.0;
        if(volumeAvailable)
        {
            double currentVol = volumeBuffer[10];
            double avgVol = 0;
            for(int i = 0; i < 10; i++)
                avgVol += volumeBuffer[i];
            avgVol /= 10.0;
            volRatio = (avgVol > 0) ? (currentVol / avgVol) : 1.0;
        }

        // --- VOLATILITY ANALYSIS --- (same ordering rule: newest ATR = index 11)
        double curATR = atrBuffer[11];
        double avgATR = 0;
        for(int i = 1; i < 11; i++)
            avgATR += atrBuffer[i];
        avgATR /= 10.0;

        double atrRatio = (avgATR > 0) ? (curATR / avgATR) : 1.0;

        // Calculate BB width for squeeze detection (bb buffers: count=2,start=1 -> newest = [1])
        double bbWidth = bbUpper[1] - bbLower[1];
        double bbWidthPercent = (bbMiddle[1] > 0) ? (bbWidth / bbMiddle[1]) : 0;
        
        bool isInSqueeze = DetectSqueezeState(bbWidthPercent);
        
        // --- SIGNAL DETECTION ---
        // Batch 155: pass the newest closed-bar bands ([1]); [0] is shift-2
        // under SafeCopyBuffer's oldest-first layout, which fed two-bars-old
        // levels into the breach test and missed real breakouts.
        SVolatilityBreakoutSignal signal = DetectBreakoutSignal(
            currentPrice, prevPrice,
            bbUpper[1], bbMiddle[1], bbLower[1],
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
        
        // v2.0: ADX rising filter for breakout entries
        if(signal.entryType != VB_ENTRY_FAILURE_REVERSAL && !ADXRising())
        {
            // ADX not rising = volatility not expanding, skip breakout entries
            // Exception: failure reversals don't need ADX rising
            return RejectSignal("VOLBREAK_ADX_NOT_RISING");
        }
        
        STradeValidationRequest request;
        request.symbol = m_symbol;
        request.orderType = (signal.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        request.stopLossPips = (signal.stopLoss > 0) ? MathAbs(signal.entryPrice - signal.stopLoss) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
        request.takeProfitPips = (signal.takeProfit > 0) ? MathAbs(signal.takeProfit - signal.entryPrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
        request.confidence = signal.confidence;
        request.strategy = GetName();
        request.clusterCode = "";

        SetProposedStops(request.stopLossPips, request.takeProfitPips); // FINDING 0
        if(!ValidateWithRiskManager(request, "VOLBREAK", confidence))
            return TRADE_SIGNAL_NONE;
        
        // Update state
        m_lastSignalBar = iBars(m_symbol, m_timeframe);
        m_inSqueeze = isInSqueeze;
        m_signalsGenerated++;
        RecordSignal();
        SetDecisionReasonTag(signal.direction == TRADE_SIGNAL_BUY ? "VOLBREAK_SIGNAL_BUY" : "VOLBREAK_SIGNAL_SELL");
        confidence = signal.confidence;
        
        // CONSENSUS LOGGING (AGENTS.md requirement)
        LogConsensusDiag(signal.direction, StringFormat("Type: %s | BB_Width=%.4f%% | ATR_Ratio=%.2f | Vol=%.2fx | Squeeze=%s", EnumToString(signal.entryType), bbWidthPercent * 100, atrRatio, volRatio, isInSqueeze ? "YES" : "NO"), confidence);
        
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
    
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_VOLATILITY_BREAKOUT; }
    
private:
    // Detect if market is in squeeze state
    bool DetectSqueezeState(double currentBBWidthPercent)
    {
        // Fetch historical BB widths
        double bbUpperHist[], bbLowerHist[], bbMiddleHist[];
        int historySize = m_lookbackPeriods + 2;
        
        if(!SafeCopyBuffer(m_bbHandle, 1, 1, historySize, bbUpperHist) ||
           !SafeCopyBuffer(m_bbHandle, 2, 1, historySize, bbLowerHist) ||
           !SafeCopyBuffer(m_bbHandle, 0, 1, historySize, bbMiddleHist))
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
    
    SVolatilityBreakoutSignal DetectBreakoutSignal(
        double price, double prevPrice,
        double bbUpper, double bbMiddle, double bbLower,
        double curATR, double atrRatio,
        double volRatio,
        bool isInSqueeze)
    {
        SVolatilityBreakoutSignal signal;

        // v2.0: Breakout Failure Reversal
        ENUM_TRADE_SIGNAL failureDirection;
        if(DetectBreakoutFailure(failureDirection))
        {
            signal.entryType = VB_ENTRY_FAILURE_REVERSAL;
            signal.direction = failureDirection;
            signal.entryPrice = price;
            signal.stopLoss = (failureDirection == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR);
            signal.takeProfit = (failureDirection == TRADE_SIGNAL_BUY) ? (price + m_atrTargetMult * curATR) : (price - m_atrTargetMult * curATR);
            signal.confidence = 0.70;
            signal.reason = "Breakout failure reversal";
            PrintFormat("[VOL-BREAKOUT] Breakout failure reversal | Direction=%s",
                       failureDirection == TRADE_SIGNAL_BUY ? "BUY" : "SELL");
            return signal;
        }

        // v2.0: Retest entry after breakout
        ENUM_TRADE_SIGNAL retestDirection = (m_squeezeBar > 0 && price >= m_squeezeHighPrice) ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
        if(BreakoutWithRetest(retestDirection))
        {
            signal.entryType = VB_ENTRY_RETEST;
            signal.direction = retestDirection;
            signal.entryPrice = price;
            signal.stopLoss = (retestDirection == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR);
            signal.takeProfit = (retestDirection == TRADE_SIGNAL_BUY) ? (price + m_atrTargetMult * curATR) : (price - m_atrTargetMult * curATR);
            signal.confidence = 0.78;
            signal.reason = "Breakout + retest confirmation";
            PrintFormat("[VOL-BREAKOUT] Retest entry | Direction=%s",
                       retestDirection == TRADE_SIGNAL_BUY ? "BUY" : "SELL");
            return signal;
        }

        // Check for bullish breakout
        bool brokeAboveBB = (price > bbUpper && prevPrice <= bbUpper);
        bool atrExpanding = (atrRatio >= m_atrExpansionMult);
        bool volumeSurge = (volRatio >= m_volumeMultiplier);
        
        if(brokeAboveBB)
        {
            // v2.0: Double Squeeze (BB + KC) - highest confidence
            if(DoubleSqueeze() && isInSqueeze)
            {
                signal.entryType = VB_ENTRY_DOUBLE_SQUEEZE;
                signal.direction = TRADE_SIGNAL_BUY;
                signal.entryPrice = price;
                signal.stopLoss = (signal.direction == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR);
                signal.takeProfit = price + m_atrTargetMult * curATR;
                signal.confidence = 0.85;
                signal.reason = "BB+KC Double Squeeze (TTM Squeeze)";

                // Store squeeze levels for retest/failure detection
                m_squeezeHighPrice = iHigh(m_symbol, m_timeframe, 1);
                m_squeezeLowPrice = iLow(m_symbol, m_timeframe, 1);
                m_squeezeBar = iBars(m_symbol, m_timeframe);

                PrintFormat("[VOL-BREAKOUT] Double Squeeze detected | BB inside KC | Conf=%.2f", signal.confidence);
                return signal;
            }
            else if(isInSqueeze && atrExpanding && volumeSurge)
            {
                // COMBINED SIGNAL: Highest confidence
                signal.entryType = VB_ENTRY_COMBINED_SIGNAL;
                signal.direction = TRADE_SIGNAL_BUY;
                signal.entryPrice = price;
                signal.stopLoss = (signal.direction == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR); // Below middle band
                signal.takeProfit = price + m_atrTargetMult * curATR;
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
                signal.stopLoss = (signal.direction == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR);
                signal.takeProfit = price + m_atrTargetMult * curATR;
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
                signal.stopLoss = (signal.direction == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR);
                signal.takeProfit = price + m_atrTargetMult * curATR;
                signal.confidence = 0.65;
                signal.reason = "BB breakout with volume";
                
                return signal;
            }
        }
        
        // Check for bearish breakout
        bool brokeBelowBB = (price < bbLower && prevPrice >= bbLower);
        
        if(brokeBelowBB)
        {
            // v2.0: Double Squeeze (BB + KC) - highest confidence
            if(DoubleSqueeze() && isInSqueeze)
            {
                signal.entryType = VB_ENTRY_DOUBLE_SQUEEZE;
                signal.direction = TRADE_SIGNAL_SELL;
                signal.entryPrice = price;
                signal.stopLoss = (signal.direction == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR);
                signal.takeProfit = price - m_atrTargetMult * curATR;
                signal.confidence = 0.85;
                signal.reason = "BB+KC Double Squeeze (TTM Squeeze)";

                // Store squeeze levels for retest/failure detection
                m_squeezeHighPrice = iHigh(m_symbol, m_timeframe, 1);
                m_squeezeLowPrice = iLow(m_symbol, m_timeframe, 1);
                m_squeezeBar = iBars(m_symbol, m_timeframe);

                PrintFormat("[VOL-BREAKOUT] Double Squeeze detected | BB inside KC | Conf=%.2f", signal.confidence);
                return signal;
            }
            else if(isInSqueeze && atrExpanding && volumeSurge)
            {
                // COMBINED SIGNAL: Highest confidence
                signal.entryType = VB_ENTRY_COMBINED_SIGNAL;
                signal.direction = TRADE_SIGNAL_SELL;
                signal.entryPrice = price;
                signal.stopLoss = (signal.direction == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR); // Above middle band
                signal.takeProfit = price - m_atrTargetMult * curATR;
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
                signal.stopLoss = (signal.direction == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR);
                signal.takeProfit = price - m_atrTargetMult * curATR;
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
                signal.stopLoss = (signal.direction == TRADE_SIGNAL_BUY) ? (price - m_atrStopMult * curATR) : (price + m_atrStopMult * curATR);
                signal.takeProfit = price - m_atrTargetMult * curATR;
                signal.confidence = 0.65;
                signal.reason = "BB breakout with volume";
                
                return signal;
            }
        }
        
        return signal;
    }

    // Double Squeeze Detection: BB inside KC = TTM Squeeze (v2.0)
    bool DoubleSqueeze()
    {
        if(m_bbHandle == INVALID_HANDLE || m_kcEmaHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
            return false;

        double bbUpper[1], bbLower[1], kcEma[1], atr[1];
        if(!SafeCopyBuffer(m_bbHandle, 1, 1, 1, bbUpper) ||  // Upper band
           !SafeCopyBuffer(m_bbHandle, 2, 1, 1, bbLower) ||  // Lower band
           !SafeCopyBuffer(m_kcEmaHandle, 0, 1, 1, kcEma) ||
           !SafeCopyBuffer(m_atrHandle, 0, 1, 1, atr))
            return false;

        // Keltner Channels: EMA ± 2*ATR
        double kcUpper = kcEma[0] + 2.0 * atr[0];
        double kcLower = kcEma[0] - 2.0 * atr[0];

        // BB inside KC = strong squeeze
        return (bbUpper[0] < kcUpper && bbLower[0] > kcLower);
    }

    // ADX Rising Filter (v2.0)
    bool ADXRising()
    {
        // Batch 169: fail closed - missing ADX is not "expanding volatility".
        if(m_adxHandle == INVALID_HANDLE)
            return false;

        double adx[2];
        if(!SafeCopyBuffer(m_adxHandle, 0, 1, 2, adx))
            return false;

        // Batch 155: SafeCopyBuffer lands oldest-first ([0]=shift 2, [1]=shift 1),
        // so the old "adx[0] > adx[1]" tested ADX FALLING and blocked every
        // breakout entry. Rising = newer above older.
        return adx[1] > adx[0];  // ADX increasing = volatility expanding
    }

    // Breakout with Retest Confirmation (v2.0)
    bool BreakoutWithRetest(ENUM_TRADE_SIGNAL direction)
    {
        // Check if we recently detected a squeeze and price broke out
        if(m_squeezeBar == 0) return false;

        int barsSinceSqueeze = iBars(m_symbol, m_timeframe) - m_squeezeBar;
        if(barsSinceSqueeze > 5 || barsSinceSqueeze < 1) return false;  // Must be 1-5 bars ago

        double close1 = iClose(m_symbol, m_timeframe, 1);
        double low1 = iLow(m_symbol, m_timeframe, 1);
        double high1 = iHigh(m_symbol, m_timeframe, 1);

        if(direction == TRADE_SIGNAL_BUY)
        {
            // Broke above squeeze high, now retesting (price near squeeze high)
            return (close1 > m_squeezeHighPrice && low1 <= m_squeezeHighPrice * 1.002);
        }
        else
        {
            // Broke below squeeze low, now retesting
            return (close1 < m_squeezeLowPrice && high1 >= m_squeezeLowPrice * 0.998);
        }
    }

    // Breakout Failure Reversal Detection (v2.0)
    bool DetectBreakoutFailure(ENUM_TRADE_SIGNAL &outDirection)
    {
        if(m_squeezeBar == 0) return false;

        int barsSinceSqueeze = iBars(m_symbol, m_timeframe) - m_squeezeBar;
        if(barsSinceSqueeze > 5 || barsSinceSqueeze < 2) return false;

        double close1 = iClose(m_symbol, m_timeframe, 1);
        double high1 = iHigh(m_symbol, m_timeframe, 1);
        double low1 = iLow(m_symbol, m_timeframe, 1);

        // Broke up, then closed back inside = bearish reversal
        if(high1 > m_squeezeHighPrice && close1 < m_squeezeHighPrice)
        {
            outDirection = TRADE_SIGNAL_SELL;
            m_breakoutFailed = true;
            m_breakoutFailedDirection = TRADE_SIGNAL_SELL;
            return true;
        }

        // Broke down, then closed back inside = bullish reversal
        if(low1 < m_squeezeLowPrice && close1 > m_squeezeLowPrice)
        {
            outDirection = TRADE_SIGNAL_BUY;
            m_breakoutFailed = true;
            m_breakoutFailedDirection = TRADE_SIGNAL_BUY;
            return true;
        }

        return false;
    }
};

#endif // __VOLATILITY_BREAKOUT_STRATEGY_MQH__

