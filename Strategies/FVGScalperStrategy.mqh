#ifndef FVG_SCALPER_STRATEGY_MQH
#define FVG_SCALPER_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

// CFVGScalperStrategy trades Fair Value Gap re-entries with rejection candle
// confirmation and structure context alignment.
class CFVGScalperStrategy : public CStrategyBase
{
private:
    CImbalanceDetector*       m_imbalanceDetector;
    CMarketStructureAnalyzer* m_structureAnalyzer;

    double m_baseScore;       // Base confidence (default: 0.55)
    double m_structureBonus;  // Structure alignment bonus (default: 0.08)
    double m_chochBonus;      // Fast CHOCH bonus (default: 0.07)
    double m_cisdBonus;       // CISD displacement bonus (default: 0.05)

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }
    virtual void OnRefreshComponents() override
    {
        if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
        if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
    }

public:
    CFVGScalperStrategy(const string name = "FVG Scalper") :
            CStrategyBase(name, 0),
            m_imbalanceDetector(NULL),
            m_structureAnalyzer(NULL),
            m_baseScore(0.55),
            m_structureBonus(0.08),
            m_chochBonus(0.07),
            m_cisdBonus(0.05)
    {
        OverrideMinConfidence(0.55);
    }

    void SetScoringWeights(double base, double structure, double choch, double cisd)
    {
        m_baseScore = MathMax(0.0, MathMin(1.0, base));
        m_structureBonus = MathMax(0.0, MathMin(0.3, structure));
        m_chochBonus = MathMax(0.0, MathMin(0.3, choch));
        m_cisdBonus = MathMax(0.0, MathMin(0.3, cisd));
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

                // Risk manager comes from the base class; without it trades skip validation
                if(GetUnifiedRiskManager() == NULL)
                    Print("[FVG-SCALPER] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

                return true;
    }

    virtual void Deinit() override
        {
            if(m_imbalanceDetector != NULL) { delete m_imbalanceDetector; m_imbalanceDetector = NULL; }
            if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
            CStrategyBase::Deinit();
        }

    virtual void OnTick() override
    {
        // Intentionally empty - strategy evaluates on new bar only via GetSignal()
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

        int bullIdx = m_imbalanceDetector.FindBestBullishImbalance();
        int bearIdx = m_imbalanceDetector.FindBestBearishImbalance();

        bool bullish = false;
        SImbalance fvg;
        bool foundFVG = false;

        // When both directions have an FVG, the stronger one wins
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

        // Price must sit inside the FVG zone; read bar 1 (last closed bar), not the forming bar
        double close1 = iClose(m_symbol, m_timeframe, 1);
        double open1  = iOpen(m_symbol, m_timeframe, 1);
        double high1  = iHigh(m_symbol, m_timeframe, 1);
        double low1   = iLow(m_symbol, m_timeframe, 1);

        if(close1 <= 0)
        {
            SetDecisionReasonTag("FVG_SCALPER_PRICE_UNAVAILABLE");
            return TRADE_SIGNAL_NONE;
        }

        bool priceInZone = (close1 >= fvg.bottom && close1 <= fvg.top);
        if(!priceInZone)
        {
            SetDecisionReasonTag("FVG_SCALPER_PRICE_OUTSIDE_FVG");
            return TRADE_SIGNAL_NONE;
        }

        // Rejection candle = body beyond open with the dominant wick at least 2x the opposite one
        bool bullishRejection = (close1 > open1) && ((close1 - low1) > 2.0 * (high1 - close1));
        bool bearishRejection = (close1 < open1) && ((high1 - close1) > 2.0 * (close1 - low1));

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

        ENUM_TRADE_SIGNAL signal = bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

        double score = m_baseScore;

        // Structure alignment bonus: FVG direction matches market structure
        bool structureAligned = bullish ? m_structureAnalyzer.IsBullishStructure()
                                        : m_structureAnalyzer.IsBearishStructure();
        if(structureAligned)
            score += m_structureBonus;

        bool fastCHOCH = m_structureAnalyzer.DetectFastCHOCH();
        if(fastCHOCH)
            score += m_chochBonus;

        bool cisdDisplacement = m_structureAnalyzer.DetectCISDDisplacement();
        if(cisdDisplacement)
            score += m_cisdBonus;

        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("FVG_SCALPER_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double atr = m_structureAnalyzer.GetATR(14);

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

        const double gatePoint = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double slPips = (gatePoint > 0 && slDistance > 0) ? (slDistance / gatePoint) : 0.0;
        double tpPips = (gatePoint > 0) ? (MathAbs(tpPrice - currentPrice) / gatePoint) : 0.0;

        STradeValidationRequest request;
        request.symbol = m_symbol;
        request.orderType = bullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        request.stopLossPips = slPips;
        request.takeProfitPips = tpPips;
        request.confidence = confidence;
        request.strategy = GetName();
        request.clusterCode = "";

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        double spreadPrice = (point > 0) ? (double)spreadPoints * point : 0.0;

        if(!CSignalGuards::IsSignalTradable(currentPrice, slPrice, tpPrice, spreadPrice))
        {
            SetDecisionReasonTag("FVG_SCALPER_NOT_TRADABLE");
            return TRADE_SIGNAL_NONE;
        }

        SetProposedStops(request.stopLossPips, request.takeProfitPips); // proposed stops must be published before risk gating
        if(!ValidateWithRiskManager(request, "FVG_SCALPER", confidence))
            return TRADE_SIGNAL_NONE;

        SetDecisionReasonTag(bullish ? "FVG_SCALPER_SIGNAL_BUY" : "FVG_SCALPER_SIGNAL_SELL");
        RecordSignal();

        LogConsensusDiag(signal, StringFormat("FVG: %s | Zone: %.5f-%.5f", fvg.isBullish ? "Bull" : "Bear", fvg.bottom, fvg.top), confidence);

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
