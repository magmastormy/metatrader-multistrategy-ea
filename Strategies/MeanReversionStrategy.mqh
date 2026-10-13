// Fade Bollinger extremes with RSI/volume confirmation, gated by Hurst regime and the ADX trend lockout.
// Copyright 2026, Multi-Strategy EA
#ifndef MEAN_REVERSION_STRATEGY_MQH
#define MEAN_REVERSION_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
// Pre-trade gating: ValidateWithRiskManager() delegates to CUnifiedRiskManager. It returns true when
// none was injected, but registration refuses such a strategy (StrategyRegistryState.mqh:122).
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Utils/Instruments.mqh"
#include "../Core/Engines/HurstEngine.mqh"
#include "../Utilities/SafeCopyBuffer.mqh"

enum ENUM_MR_ENTRY_TYPE
{
    MR_ENTRY_NONE = 0,
    MR_ENTRY_BB_TOUCH,
    MR_ENTRY_RSI_EXTREME,
    MR_ENTRY_DOUBLE_SIGNAL  // BB touch + RSI extreme: highest confidence tier
};

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

class CMeanReversionStrategy : public CStrategyBase
{
private:
    int m_bbHandle;
    int m_rsiHandle;
    int m_volumeHandle;
    
    int m_bbPeriod;
    double m_bbDeviation;     // in standard deviations
    int m_rsiPeriod;
    double m_rsiOverbought;
    double m_rsiOversold;
    double m_minVolumeRatio;  // current volume vs 10-bar mean
    
    bool m_isSynthetic;
    double m_syntheticBbDeviation;
    int m_syntheticBbHandle;  // created directly, released in Cleanup
    
    int     m_stochHandle;
    int     m_adxHandle;        // gates entries out of trending markets
    CHurstEngine* m_hurstEngine;
    double  m_bbWidthLookback;    // in bars

    datetime m_lastSignalBar;
    int m_signalsGenerated;

public:
    CMeanReversionStrategy(const string name = "Mean Reversion v2.0", int magic = 0) :
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
        m_isSynthetic(false),
        m_syntheticBbDeviation(1.5),
        m_syntheticBbHandle(INVALID_HANDLE),
                m_stochHandle(INVALID_HANDLE),
                m_adxHandle(INVALID_HANDLE),
                m_hurstEngine(NULL),
                m_bbWidthLookback(50),
                m_lastSignalBar(0),
                m_signalsGenerated(0)
    {
        m_strategyPrefix = "MEANREV";
        m_minConfidence = 0.60; // Higher threshold for mean reversion
    }
    
    ~CMeanReversionStrategy()
    {
        Cleanup();
    }
    
    void Cleanup()
    {
        // CIndicatorManager owns these - never IndicatorRelease them here. The Stochastic handle
        // comes from that shared cache (Init, GetStochasticHandle), so releasing it here would also
        // kill it for every other holder and double-release at DestroyInstance.
        m_bbHandle = INVALID_HANDLE;
        m_rsiHandle = INVALID_HANDLE;
        m_volumeHandle = INVALID_HANDLE;
        m_stochHandle = INVALID_HANDLE;
        // Synthetic BB uses a custom deviation, so CIndicatorManager cannot own it: release it here.
                if(m_syntheticBbHandle != INVALID_HANDLE) { IndicatorRelease(m_syntheticBbHandle); m_syntheticBbHandle = INVALID_HANDLE; }
    }
    
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        // The synthetic branch (wider BB deviation, no RSI or volume filter) is a fact about the symbol,
        // not an operator preference, and nothing set it: every synthetic index ran the FX path.
        m_isSynthetic = IsSyntheticIndexSymbolName(symbol);
        
        m_bbHandle = CIndicatorManager::Instance().GetBandsHandle(symbol, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
        m_rsiHandle = CIndicatorManager::Instance().GetRSIHandle(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
        m_volumeHandle = CIndicatorManager::Instance().GetVolumesHandle(symbol, timeframe, VOLUME_TICK);

        m_stochHandle = CIndicatorManager::Instance().GetStochasticHandle(m_symbol, m_timeframe, 14, 3, 3, MODE_SMA, STO_LOWHIGH);

        m_adxHandle = CIndicatorManager::Instance().GetADXHandle(m_symbol, m_timeframe, 14);

        if(m_bbHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE || m_volumeHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE)
                {
                    Print("[MEANREV] Failed to create indicator handles");
                    return false;
                }
        
                PrintFormat("[MEANREV] Initialized | BB(%d,%.1f) | RSI(%d) | OB=%.1f | OS=%.1f | path=%s",
                           m_bbPeriod, m_bbDeviation, m_rsiPeriod, m_rsiOverbought, m_rsiOversold,
                           m_isSynthetic ? "synthetic(1.5sigma+spike)" : "fx(bands+rsi+volume)");
        
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
    }
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("MEANREV_UNSET");
        
        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("MEANREV_DISABLED_OR_UNINIT");
        
        if(m_isSynthetic)
            return GetSignalSynthetic(confidence);
        
        double bbUpper[2], bbMiddle[2], bbLower[2];
        double rsiBuffer[2];
        double volumeBuffer[11];
        
        if(!SafeCopyBuffer(m_bbHandle, 1, 1, 2, bbUpper) ||  // Upper band
           !SafeCopyBuffer(m_bbHandle, 0, 1, 2, bbMiddle) || // Middle band
           !SafeCopyBuffer(m_bbHandle, 2, 1, 2, bbLower) ||  // Lower band
           !SafeCopyBuffer(m_rsiHandle, 0, 1, 2, rsiBuffer) ||
           !SafeCopyBuffer(m_volumeHandle, 0, 1, 11, volumeBuffer))
        {
            return RejectSignal("MEANREV_DATA_UNAVAILABLE");
        }
        
        double currentPrice = iClose(m_symbol, m_timeframe, 1);
        double prevPrice = iClose(m_symbol, m_timeframe, 2);
        
        // Static-array CopyBuffer is NOT as-series: [0] is oldest, so shift 1 (newest) lands on the last index.
        double currentVol = volumeBuffer[10];
        double avgVol = 0;
        for(int i = 0; i < 10; i++)
            avgVol += volumeBuffer[i];
        avgVol /= 10.0;

        double volRatio = (avgVol > 0) ? (currentVol / avgVol) : 1.0;

        if(volRatio < m_minVolumeRatio)
        {
            PrintFormat("[MEANREV-VOL] Low volume | Ratio=%.2f < %.2f", volRatio, m_minVolumeRatio);
            return RejectSignal("MEANREV_LOW_VOLUME");
        }

        // bb/rsi buffers: count=2, start=1 -> newest closed bar is index 1
        SMeanReversionSignal signal = DetectMeanReversionSignal(
            currentPrice, prevPrice,
            bbUpper[1], bbMiddle[1], bbLower[1],
            rsiBuffer[1],
            volRatio
        );
        
        if(signal.direction == TRADE_SIGNAL_NONE)
            return RejectSignal("MEANREV_NO_SIGNAL");
        
        if(signal.confidence < m_minConfidence)
        {
            PrintFormat("[MEANREV] Low confidence | %.1f%% < %.1f%%", 
                       signal.confidence * 100, m_minConfidence * 100);
            return RejectSignal("MEANREV_LOW_CONFIDENCE");
        }
        
        // Hurst regime lockout: only fade extremes in a mean-reverting regime
        if(!MeanRevertingRegime())
        {
            return RejectSignal("MEANREV_HURST_NOT_MEANREVERTING");
        }
        
        // Trending market (ADX above 25) must stand aside instead of fading
        double adx = GetADX(14);
        // ADX unknown (-1) blocks rather than passes: "not trending" cannot be asserted unevaluated.
        if(adx < 0.0)
        {
            SetDecisionReasonTag("MEANREV_ADX_UNAVAILABLE");
            return RejectSignal("MEANREV_ADX_UNAVAILABLE");
        }
        if(adx > 25.0)
        {
            SetDecisionReasonTag("MEANREV_TRENDING_MARKET");
            PrintFormat("[MEANREV] Market trending (ADX=%.1f), blocking mean reversion", adx);
            return RejectSignal("MEANREV_TRENDING_MARKET");
        }
        
        // Band width filter: skip when bands are narrower than their recent average
        if(!SufficientBandWidth())
        {
            return RejectSignal("MEANREV_BAND_WIDTH_INSUFFICIENT");
        }
        
        // Divergence filter: don't fade while price and RSI diverge
        if(!NoDivergence(signal.direction))
        {
            return RejectSignal("MEANREV_DIVERGENCE_DETECTED");
        }
        
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double slDistance = MathAbs(signal.entryPrice - signal.stopLoss);
        double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0; // no fallback: unmeasurable SL stays 0 pips
        double tpDistance = MathAbs(signal.takeProfit - signal.entryPrice);
        double tpPips = (point > 0 && tpDistance > 0) ? (tpDistance / point) : slPips * 2.0;

        double dynamicTP = GetDynamicTP(signal.direction);
        // dynamicTP is never sent: the request's TP is signal.takeProfit (BB middle)

        STradeValidationRequest request;
        request.symbol = m_symbol;
        request.orderType = (signal.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        request.stopLossPips = slPips;
        request.takeProfitPips = tpPips;
        request.confidence = signal.confidence;
        request.strategy = GetName();
        request.clusterCode = "";

        SetProposedStops(request.stopLossPips, request.takeProfitPips);
        if(!ValidateWithRiskManager(request, "MEANREV", confidence))
            return TRADE_SIGNAL_NONE;
        
        m_lastSignalBar = iBars(m_symbol, m_timeframe);
        m_signalsGenerated++;
        RecordSignal();
        SetDecisionReasonTag(signal.direction == TRADE_SIGNAL_BUY ? "MEANREV_SIGNAL_BUY" : "MEANREV_SIGNAL_SELL");
        confidence = signal.confidence;
        
        // [CONSENSUS-DIAG] log required by AGENTS.md §6
        LogConsensusDiag(signal.direction, StringFormat("Type: %s | Z: %.2f | Stoch: %s | BW: %s", signal.entryType == MR_ENTRY_DOUBLE_SIGNAL ? "DOUBLE" : signal.entryType == MR_ENTRY_BB_TOUCH ? "BB" : "RSI", signal.confidence, StochasticExtreme(signal.direction) ? "EXT" : "NORM", SufficientBandWidth() ? "OK" : "NARROW"), confidence);
        
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
    
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_MEAN_REVERSION; }

    void SetHurstEngine(CHurstEngine* engine) { m_hurstEngine = engine; }
    
    void SetSyntheticMode(bool enabled) { m_isSynthetic = enabled; }

    // Synthetic-indices path: 1.5σ BB touch + spike only, no RSI or volume filters
    ENUM_TRADE_SIGNAL GetSignalSynthetic(double &confidence)
    {
        confidence = 0.0;
        SetDecisionReasonTag("MEANREV_SYNTHETIC");
        
        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("MEANREV_DISABLED_OR_UNINIT");
        
        if(m_syntheticBbHandle == INVALID_HANDLE)
        {
            m_syntheticBbHandle = iBands(m_symbol, m_timeframe, m_bbPeriod, 0, m_syntheticBbDeviation, PRICE_CLOSE);
            if(m_syntheticBbHandle == INVALID_HANDLE)
            {
                Print("[MEANREV-SYN] Failed to create synthetic BB handle");
                return RejectSignal("MEANREV_SYN_BB_HANDLE");
            }
        }
        
        double bbUpper[2], bbMiddle[2], bbLower[2];
        if(!SafeCopyBuffer(m_syntheticBbHandle, 1, 1, 2, bbUpper) ||
           !SafeCopyBuffer(m_syntheticBbHandle, 0, 1, 2, bbMiddle) ||
           !SafeCopyBuffer(m_syntheticBbHandle, 2, 1, 2, bbLower))
        {
            return RejectSignal("MEANREV_SYN_DATA_UNAVAILABLE");
        }
        
        double currentPrice = iClose(m_symbol, m_timeframe, 1);
        double prevPrice = iClose(m_symbol, m_timeframe, 2);
        
        // ATR(14) via CIndicatorManager - do not release the handle per call
        int atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
        if(atrHandle == INVALID_HANDLE)
            return RejectSignal("MEANREV_SYN_ATR_HANDLE");
        
        double atrBuffer[1];
        bool atrOk = SafeCopyBuffer(atrHandle, 0, 1, 1, atrBuffer);
        
        if(!atrOk || atrBuffer[0] <= 0.0)
            return RejectSignal("MEANREV_SYN_ATR_DATA");
        
        double atr14 = atrBuffer[0];
        
        // Spike detection: price moved > 2×ATR in last 5 bars
        double price5BarsAgo = iClose(m_symbol, m_timeframe, 6);
        bool spiked = MathAbs(currentPrice - price5BarsAgo) > 2.0 * atr14;
        
        // 1.5σ BB touch (primary signal). Oldest-first layout: [1] newest closed bar, [0] is shift 2.
        bool touchLower = currentPrice <= bbLower[1];
        bool touchUpper = currentPrice >= bbUpper[1];

        SMeanReversionSignal signal;
        signal.direction = TRADE_SIGNAL_NONE;

        if(touchLower && spiked)
        {
            signal.entryType = MR_ENTRY_BB_TOUCH;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.entryPrice = currentPrice;
            signal.stopLoss = bbLower[1] - (bbUpper[1] - bbLower[1]) * 0.3;
            signal.takeProfit = bbMiddle[1];
            signal.confidence = 0.65;
            signal.reason = "Synthetic: BB lower touch + spike detected";
        }

        else if(touchUpper && spiked)
        {
            signal.entryType = MR_ENTRY_BB_TOUCH;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.entryPrice = currentPrice;
            signal.stopLoss = bbUpper[1] + (bbUpper[1] - bbLower[1]) * 0.3;
            signal.takeProfit = bbMiddle[1];
            signal.confidence = 0.65;
            signal.reason = "Synthetic: BB upper touch + spike detected";
        }

        if(signal.direction == TRADE_SIGNAL_NONE)
            return RejectSignal("MEANREV_SYN_NO_SIGNAL");
        
        // Synthetic path fails closed: with no risk manager injected it returns no signal.
                CUnifiedRiskManager* riskMgr = GetUnifiedRiskManager();
                if(riskMgr != NULL)
                {
                    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                    double slDistance = MathAbs(signal.entryPrice - signal.stopLoss);
                    double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0;
                    double tpDistance = MathAbs(signal.takeProfit - signal.entryPrice);
                    double tpPips = (point > 0 && tpDistance > 0) ? (tpDistance / point) : slPips * 1.5;
            
                    STradeValidationRequest request;
                    request.symbol = m_symbol;
                    request.orderType = (signal.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                    request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
                    request.stopLossPips = slPips;
                    request.takeProfitPips = tpPips;
                    request.confidence = signal.confidence;
                    request.strategy = GetName();
                    request.clusterCode = "";
            
                    SValidationResult result;
                    ZeroMemory(result);
                    if(riskMgr.ValidateTradeRequest(request, "MEANREV_SYN").approved)
                    {
                        m_lastSignalBar = iBars(m_symbol, m_timeframe);
                        m_signalsGenerated++;
                        RecordSignal();
                        SetDecisionReasonTag(signal.direction == TRADE_SIGNAL_BUY ? "MEANREV_SYN_BUY" : "MEANREV_SYN_SELL");
                        confidence = signal.confidence;
                
                        PrintFormat("[MEANREV-SYN] %s: %s | Entry: %.5f | SL: %.5f | TP: %.5f | Conf: %.1f%% | %s",
                                   m_symbol,
                                   signal.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                                   signal.entryPrice,
                                   signal.stopLoss,
                                   signal.takeProfit,
                                   confidence * 100,
                                   signal.reason);
                
                        return signal.direction;
                    }
                    else
                    {
                        SetDecisionReasonTag("MEANREV_SYN_RISK_REJECTED");
                        return TRADE_SIGNAL_NONE;
                    }
                }
        
        return TRADE_SIGNAL_NONE;
    }

private:
    bool StochasticExtreme(ENUM_TRADE_SIGNAL direction)
    {
        // Fail closed: missing evidence can neither grant the +0.05 boost nor bypass the x0.90 penalty.
        if(m_stochHandle == INVALID_HANDLE)
            return false;
        
        double stochK[1];
        if(CopyBuffer(m_stochHandle, 0, 1, 1, stochK) <= 0)
            return false;
        
        if(direction == TRADE_SIGNAL_BUY)
            return stochK[0] < 20.0;  // Oversold
        else
            return stochK[0] > 80.0;  // Overbought
    }
    
    // True when NO divergence is present (safe to fade)
    bool NoDivergence(ENUM_TRADE_SIGNAL direction)
    {
        // Fail closed: missing data cannot prove the absence of divergence, and this gates entries.
        if(m_rsiHandle == INVALID_HANDLE)
            return false;
        
        double priceLow[11], priceHigh[11], rsi[11];
        if(CopyLow(m_symbol, m_timeframe, 1, 11, priceLow) < 11 ||
           CopyHigh(m_symbol, m_timeframe, 1, 11, priceHigh) < 11 ||
           CopyBuffer(m_rsiHandle, 0, 1, 11, rsi) < 11)
            return false;
        
        // Divergence over the last 5-10 bars. Non-series copies are OLDEST-first, so the newest
        // closed bar is [10] and the reference is [10 - lookback].
        for(int lookback = 5; lookback <= 10; lookback++)
        {
            if(direction == TRADE_SIGNAL_BUY)
            {
                // Bullish divergence: price lower low + RSI higher low = NOT mean reversion
                bool priceLowerLow = (priceLow[10] < priceLow[10 - lookback]);
                bool rsiHigherLow = (rsi[10] > rsi[10 - lookback]);
                if(priceLowerLow && rsiHigherLow)
                    return false;
            }
            else
            {
                // Bearish divergence: price higher high + RSI lower high
                bool priceHigherHigh = (priceHigh[10] > priceHigh[10 - lookback]);
                bool rsiLowerHigh = (rsi[10] < rsi[10 - lookback]);
                if(priceHigherHigh && rsiLowerHigh)
                    return false;
            }
        }
        
        return true;
    }
    
    // True only in a mean-reverting regime (Hurst < 0.45)
    bool MeanRevertingRegime()
    {
        if(m_hurstEngine == NULL)
            return true;  // engine not wired for this roster: no regime gate applies here
        // Wired but not warmed up: no regime opinion, so the lockout fails closed during warmup.
        if(!m_hurstEngine.IsWarmedUp())
            return false;
        return m_hurstEngine.GetRegime() == HURST_MEAN_REVERTING;
    }
    
    // True when the current BB width exceeds its m_bbWidthLookback average
    bool SufficientBandWidth()
    {
        if(m_bbHandle == INVALID_HANDLE)
            return false;  // fail closed: BB width is this strategy's premise
        
        double bbUpper[1], bbLower[1];
        if(CopyBuffer(m_bbHandle, 1, 1, 1, bbUpper) <= 0 ||
           CopyBuffer(m_bbHandle, 2, 1, 1, bbLower) <= 0)
            return false;
        
        double currentWidth = bbUpper[0] - bbLower[0];
        
        double avgWidth = 0;
        int validBars = 0;
        for(int i = 1; i <= (int)m_bbWidthLookback; i++)
        {
            double bbU[1], bbL[1];
            if(CopyBuffer(m_bbHandle, 1, i, 1, bbU) > 0 &&
               CopyBuffer(m_bbHandle, 2, i, 1, bbL) > 0)
            {
                avgWidth += (bbU[0] - bbL[0]);
                validBars++;
            }
        }
        
        if(validBars < 10) return false;  // not enough history to judge the width
        avgWidth /= validBars;
        
        return currentWidth > avgWidth;
    }
    
    // Dynamic TP target: the BB middle line.
    double GetDynamicTP(ENUM_TRADE_SIGNAL direction)
    {
        if(m_bbHandle == INVALID_HANDLE)
            return 0.0;
        
        double bbMiddle[1];
        if(CopyBuffer(m_bbHandle, 0, 1, 1, bbMiddle) <= 0)
            return 0.0;
        
        return bbMiddle[0];
    }
    
    // ADX for the trend lockout: -1 when unavailable, and the caller must block on -1 - a 0.0 sentinel
    // would silently pass the adx > 25 gate during an outage. Reads shift 1, never the forming bar.
    double GetADX(int period)
    {
        if(m_adxHandle == INVALID_HANDLE)
            return -1.0;

        double adxBuffer[1];
        if(CopyBuffer(m_adxHandle, 0, 1, 1, adxBuffer) > 0 && adxBuffer[0] > 0.0)
            return adxBuffer[0];

        return -1.0;
    }
    
    SMeanReversionSignal DetectMeanReversionSignal(
        double price, double prevPrice,
        double bbUpper, double bbMiddle, double bbLower,
        double rsi,
        double volRatio)  // Renamed to avoid shadowing global 'volumeRatio'
    {
        SMeanReversionSignal signal;
        
        bool priceAtLowerBB = (price <= bbLower);
        bool rsiOversold = (rsi <= m_rsiOversold);
        
        if(priceAtLowerBB && rsiOversold)
        {
            signal.entryType = MR_ENTRY_DOUBLE_SIGNAL;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.entryPrice = price;
            signal.stopLoss = bbLower - (bbUpper - bbLower) * 0.5; // 0.5 band-width below the lower band
            signal.takeProfit = bbMiddle;
            signal.confidence = 0.75 + (volRatio - 1.0) * 0.1;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "Double signal: BB lower + RSI oversold";
            
            if(StochasticExtreme(signal.direction))
            {
                signal.confidence += 0.05;
                signal.reason += " +Stoch";
            }
            
            PrintFormat("[MEANREV-SIGNAL] BUY double signal | Price=%.5f <= BB_Lower=%.5f | RSI=%.1f <= %.1f",
                       price, bbLower, rsi, m_rsiOversold);
            
            return signal;
        }
        
        if(priceAtLowerBB)
        {
            // 0.70 base so the x0.90 no-Stochastic tier still clears the 0.60 confidence floor.
            signal.entryType = MR_ENTRY_BB_TOUCH;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.entryPrice = price;
            signal.stopLoss = bbLower - (bbUpper - bbLower) * 0.5;
            signal.takeProfit = bbMiddle;
            signal.confidence = 0.70 + (volRatio - 1.0) * 0.08;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "BB lower band touch";

            // A BB-only entry without a Stochastic extreme is weakened x0.90, not rejected.
            if(!StochasticExtreme(signal.direction))
            {
                signal.confidence *= 0.90;
                signal.reason += " (no Stoch confirm)";
            }

            return signal;
        }

        if(rsiOversold)
        {
            // RSI oversold only: 0.65 is the weakest tier that still clears the 0.60 floor
            signal.entryType = MR_ENTRY_RSI_EXTREME;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.entryPrice = price;
            signal.stopLoss = price - (bbUpper - bbLower) * 0.3;
            signal.takeProfit = bbMiddle;
            signal.confidence = 0.65 + (volRatio - 1.0) * 0.07;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "RSI oversold";

            return signal;
        }
        
        bool priceAtUpperBB = (price >= bbUpper);
        bool rsiOverbought = (rsi >= m_rsiOverbought);
        
        if(priceAtUpperBB && rsiOverbought)
        {
            signal.entryType = MR_ENTRY_DOUBLE_SIGNAL;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.entryPrice = price;
            signal.stopLoss = bbUpper + (bbUpper - bbLower) * 0.5; // 0.5 band-width above the upper band
            signal.takeProfit = bbMiddle;
            signal.confidence = 0.75 + (volRatio - 1.0) * 0.1;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "Double signal: BB upper + RSI overbought";
            
            if(StochasticExtreme(signal.direction))
            {
                signal.confidence += 0.05;
                signal.reason += " +Stoch";
            }

            PrintFormat("[MEANREV-SIGNAL] SELL double signal | Price=%.5f >= BB_Upper=%.5f | RSI=%.1f >= %.1f",
                       price, bbUpper, rsi, m_rsiOverbought);

            return signal;
        }

        if(priceAtUpperBB)
        {
            // BB touch only: rebased like the BUY side so the weakened tier clears 0.60
            signal.entryType = MR_ENTRY_BB_TOUCH;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.entryPrice = price;
            signal.stopLoss = bbUpper + (bbUpper - bbLower) * 0.5;
            signal.takeProfit = bbMiddle;
            signal.confidence = 0.70 + (volRatio - 1.0) * 0.08;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "BB upper band touch";

            // A BB-only entry without a Stochastic extreme is weakened x0.90, not rejected.
            if(!StochasticExtreme(signal.direction))
            {
                signal.confidence *= 0.90;
                signal.reason += " (no Stoch confirm)";
            }

            return signal;
        }

        if(rsiOverbought)
        {
            // RSI overbought only: weakest tier that still clears the 0.60 floor
            signal.entryType = MR_ENTRY_RSI_EXTREME;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.entryPrice = price;
            signal.stopLoss = price + (bbUpper - bbLower) * 0.3;
            signal.takeProfit = bbMiddle;
            signal.confidence = 0.65 + (volRatio - 1.0) * 0.07;
            signal.confidence = MathMin(1.0, signal.confidence);
            signal.reason = "RSI overbought";

            return signal;
        }
        
        return signal;
    }
};

#endif

