//+------------------------------------------------------------------+
//| FVGScalperStrategy.mqh                                           |
//| FVG Scalper: Fair Value Gap re-entry with rejection candle       |
//| confirmation and structure context alignment                      |
//+------------------------------------------------------------------+
#ifndef __FVG_SCALPER_STRATEGY_MQH__
#define __FVG_SCALPER_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

class CFVGScalperStrategy : public CStrategyBase
{
private:
    CImbalanceDetector*       m_imbalanceDetector;
    CMarketStructureAnalyzer* m_structureAnalyzer;
    int                       m_lastBarCount;

    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager*      m_riskManager;

    bool RefreshForNewBar()
    {
        int barCount = iBars(m_symbol, m_timeframe);
        if(barCount <= 0 || barCount == m_lastBarCount)
            return false;

        m_lastBarCount = barCount;
        if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
        if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
        return true;
    }

public:
    CFVGScalperStrategy(const string name = "FVG Scalper") :
        CStrategyBase(name, 0),
        m_imbalanceDetector(NULL),
        m_structureAnalyzer(NULL),
        m_lastBarCount(0),
        m_riskManager(NULL)
    {
        OverrideMinConfidence(0.55);
    }

    virtual ~CFVGScalperStrategy()
    {
        Deinit();
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_imbalanceDetector = new CImbalanceDetector();
        m_structureAnalyzer = new CMarketStructureAnalyzer();
        if(m_imbalanceDetector == NULL || m_structureAnalyzer == NULL)
            return false;

        if(!m_imbalanceDetector.Initialize(symbol, timeframe) ||
           !m_structureAnalyzer.Initialize(symbol, timeframe, 3))
        {
            return false;
        }

        m_lastBarCount = 0;

        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[FVG-SCALPER] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_imbalanceDetector != NULL) { delete m_imbalanceDetector; m_imbalanceDetector = NULL; }
        if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
        CStrategyBase::Deinit();
    }

    virtual void OnTick() override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(symbol == m_symbol && timeframe == m_timeframe)
            RefreshForNewBar();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("FVG_SCALPER_UNSET");
        if(!IsEnabled() || !m_is_initialized)
        {
            SetDecisionReasonTag("FVG_SCALPER_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        RefreshForNewBar();
        if(m_imbalanceDetector == NULL || m_structureAnalyzer == NULL)
        {
            SetDecisionReasonTag("FVG_SCALPER_COMPONENTS_NOT_READY");
            return TRADE_SIGNAL_NONE;
        }

        // --- Step 1: Find nearest FVG ---
        int bullIdx = m_imbalanceDetector.FindBestBullishImbalance();
        int bearIdx = m_imbalanceDetector.FindBestBearishImbalance();

        bool bullish = false;
        SImbalance fvg;
        bool foundFVG = false;

        // Prefer the strongest FVG; if both exist, pick the stronger one
        if(bullIdx >= 0 && bearIdx >= 0)
        {
            SImbalance bullFVG, bearFVG;
            m_imbalanceDetector.GetImbalance(bullIdx, bullFVG);
            m_imbalanceDetector.GetImbalance(bearIdx, bearFVG);
            if(bullFVG.strength >= bearFVG.strength)
            {
                fvg = bullFVG;
                bullish = true;
                foundFVG = true;
            }
            else
            {
                fvg = bearFVG;
                bullish = false;
                foundFVG = true;
            }
        }
        else if(bullIdx >= 0)
        {
            m_imbalanceDetector.GetImbalance(bullIdx, fvg);
            bullish = true;
            foundFVG = true;
        }
        else if(bearIdx >= 0)
        {
            m_imbalanceDetector.GetImbalance(bearIdx, fvg);
            bullish = false;
            foundFVG = true;
        }

        if(!foundFVG)
        {
            SetDecisionReasonTag("FVG_SCALPER_NO_FVG_FOUND");
            return TRADE_SIGNAL_NONE;
        }

        // --- Step 2: Check if current price is inside the FVG zone ---
        double close0 = iClose(m_symbol, m_timeframe, 0);
        double open0  = iOpen(m_symbol, m_timeframe, 0);
        double high0  = iHigh(m_symbol, m_timeframe, 0);
        double low0   = iLow(m_symbol, m_timeframe, 0);

        if(close0 <= 0)
        {
            SetDecisionReasonTag("FVG_SCALPER_PRICE_UNAVAILABLE");
            return TRADE_SIGNAL_NONE;
        }

        bool priceInZone = (close0 >= fvg.bottom && close0 <= fvg.top);
        if(!priceInZone)
        {
            SetDecisionReasonTag("FVG_SCALPER_PRICE_OUTSIDE_FVG");
            return TRADE_SIGNAL_NONE;
        }

        // --- Step 3: Check for rejection candle pattern ---
        // Bullish rejection: close > open AND (close - low) > 2 * (high - close)
        // Bearish rejection: close < open AND (high - close) > 2 * (close - low)
        bool bullishRejection = (close0 > open0) && ((close0 - low0) > 2.0 * (high0 - close0));
        bool bearishRejection = (close0 < open0) && ((high0 - close0) > 2.0 * (close0 - low0));

        if(bullish && !bullishRejection)
        {
            SetDecisionReasonTag("FVG_SCALPER_NO_BULL_REJECTION");
            return TRADE_SIGNAL_NONE;
        }
        if(!bullish && !bearishRejection)
        {
            SetDecisionReasonTag("FVG_SCALPER_NO_BEAR_REJECTION");
            return TRADE_SIGNAL_NONE;
        }

        // --- Step 4: Signal direction ---
        ENUM_TRADE_SIGNAL signal = bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

        // --- Step 5: Build confidence score ---
        double score = 0.55;  // Base confidence from OverrideMinConfidence

        // Structure alignment bonus: FVG direction matches market structure
        bool structureAligned = bullish ? m_structureAnalyzer.IsBullishStructure()
                                        : m_structureAnalyzer.IsBearishStructure();
        if(structureAligned)
            score += 0.08;

        // Fast CHOCH confirmation bonus
        bool fastCHOCH = m_structureAnalyzer.DetectFastCHOCH();
        if(fastCHOCH)
            score += 0.07;

        // CISD displacement bonus
        bool cisdDisplacement = m_structureAnalyzer.DetectCISDDisplacement();
        if(cisdDisplacement)
            score += 0.05;

        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("FVG_SCALPER_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        // --- Step 6: Calculate SL/TP ---
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double atr = m_structureAnalyzer.GetATR(14);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

        double slPrice, tpPrice, slDistance;
        if(bullish)
        {
            slPrice = fvg.bottom - 0.5 * atr;
            slDistance = MathAbs(currentPrice - slPrice);
            tpPrice = currentPrice + 1.5 * slDistance;  // 1.5R
        }
        else
        {
            slPrice = fvg.top + 0.5 * atr;
            slDistance = MathAbs(slPrice - currentPrice);
            tpPrice = currentPrice - 1.5 * slDistance;  // 1.5R
        }

        double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0;
        double tpPips = (point > 0 && slDistance > 0) ? (1.5 * slDistance / point) : 0.0;

        // --- Step 7: Risk validation through CUnifiedRiskManager (AGENTS.md invariant #1) ---
        if(m_riskManager != NULL)
        {
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = bullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            request.stopLossPips = slPips;
            request.takeProfitPips = tpPips;
            request.confidence = confidence;
            request.strategy = GetName();
            request.clusterCode = "";

            CUnifiedRiskManager* riskMgr = m_riskManager;
            SValidationResult result;
            ZeroMemory(result);
            if(riskMgr != NULL)
                result = (*riskMgr).ValidateTradeRequest(request, "FVG_SCALPER");
            if(!result.approved)
            {
                SetDecisionReasonTag("FVG_SCALPER_RISK_REJECTED");
                PrintFormat("[FVG-SCALPER] Risk rejected %s at %.5f Conf=%.1f%%",
                           signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           currentPrice, confidence * 100);
                return TRADE_SIGNAL_NONE;
            }
            confidence *= result.confidenceMultiplier;
        }

        SetDecisionReasonTag(bullish ? "FVG_SCALPER_SIGNAL_BUY" : "FVG_SCALPER_SIGNAL_SELL");
        RecordSignal();

        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | FVG: %s | Zone: %.5f-%.5f | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   fvg.isBullish ? "Bull" : "Bear",
                   fvg.bottom, fvg.top,
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);

        PrintFormat("[FVG-SCALPER] %s: %s | FVG Zone: %.5f-%.5f | Entry: %.5f | SL: %.5f | Conf: %.1f%% | Struct: %s | CHOCH: %s | CISD: %s",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   fvg.bottom, fvg.top,
                   fvg.midpoint,
                   slPrice,
                   confidence * 100,
                   structureAligned ? "Yes" : "No",
                   fastCHOCH ? "Yes" : "No",
                   cisdDisplacement ? "Yes" : "No");

        return signal;
    }

    virtual string GetName() const override { return "FVG Scalper"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_FVG_SCALPER; }
};

#endif
