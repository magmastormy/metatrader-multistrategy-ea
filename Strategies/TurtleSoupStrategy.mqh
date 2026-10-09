#ifndef TURTLE_SOUP_STRATEGY_MQH
#define TURTLE_SOUP_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
// Mandatory: every entry gates through CUnifiedRiskManager
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "UnifiedICTFiles/LiquidityDetector.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"

// CTurtleSoupStrategy trades false breakouts of liquidity pools, confirmed by
// structure alignment and scored with an FVG confluence bonus.
class CTurtleSoupStrategy : public CStrategyBase
{
private:
    CLiquidityDetector*       m_liquidityDetector;
    CImbalanceDetector*       m_imbalanceDetector;
    CMarketStructureAnalyzer* m_structureAnalyzer;

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }
    virtual void OnRefreshComponents() override
    {
        if(m_liquidityDetector != NULL) m_liquidityDetector.Update();
        if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
        if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
    }

public:
    CTurtleSoupStrategy(const string name = "Turtle Soup") :
        CStrategyBase(name, 0),
        m_liquidityDetector(NULL),
        m_imbalanceDetector(NULL),
        m_structureAnalyzer(NULL)
    {
        OverrideMinConfidence(0.50);
    }

    virtual ~CTurtleSoupStrategy()
    {
        Deinit();
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_liquidityDetector = new CLiquidityDetector();
        m_imbalanceDetector = new CImbalanceDetector();
        m_structureAnalyzer = new CMarketStructureAnalyzer();
        if(m_liquidityDetector == NULL || m_imbalanceDetector == NULL || m_structureAnalyzer == NULL)
            return false;

        if(!m_liquidityDetector.Initialize(symbol, timeframe, 5.0) ||
           !m_imbalanceDetector.Initialize(symbol, timeframe) ||
           !m_structureAnalyzer.Initialize(symbol, timeframe, 3))
        {
            return false;
        }

        return true;
    }

    virtual void Deinit() override
    {
        if(m_liquidityDetector != NULL) { delete m_liquidityDetector; m_liquidityDetector = NULL; }
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
        SetDecisionReasonTag("TURTLE_UNSET");
        if(!IsEnabled() || !m_is_initialized)
        {
            SetDecisionReasonTag("TURTLE_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        RefreshForNewBar();
        if(m_liquidityDetector == NULL || m_imbalanceDetector == NULL || m_structureAnalyzer == NULL)
        {
            SetDecisionReasonTag("TURTLE_COMPONENTS_NOT_READY");
            return TRADE_SIGNAL_NONE;
        }

        STurtleSoupSignal turtleSoup;
        if(!m_liquidityDetector.DetectTurtleSoup(turtleSoup, 4))
        {
            SetDecisionReasonTag("TURTLE_NO_SIGNAL");
            return TRADE_SIGNAL_NONE;
        }

        bool bullish = turtleSoup.bullish;
        ENUM_TRADE_SIGNAL signal = bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

        bool structureAligned = bullish ? m_structureAnalyzer.IsBullishStructure()
                                        : m_structureAnalyzer.IsBearishStructure();

        // Either structure alignment or a fast CISD qualifies the reversal
        bool fastCHOCH = bullish ? m_structureAnalyzer.IsCISD(POSITION_TYPE_BUY, 1)
                                 : m_structureAnalyzer.IsCISD(POSITION_TYPE_SELL, 1);

        if(!structureAligned && !fastCHOCH)
        {
            SetDecisionReasonTag("TURTLE_STRUCTURE_NOT_ALIGNED");
            return TRADE_SIGNAL_NONE;
        }

        int imbIdx = bullish ? m_imbalanceDetector.FindBestBullishImbalance()
                             : m_imbalanceDetector.FindBestBearishImbalance();
        bool hasFVGConfluence = (imbIdx >= 0);

        double score = 0.50 + turtleSoup.confidence * 0.15;
        if(structureAligned) score += 0.10;
        if(hasFVGConfluence) score += 0.08;
        if(fastCHOCH) score += 0.07;
        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("TURTLE_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        // SL beyond the false-break extreme by 0.3*ATR, TP at 2R
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double atr = m_structureAnalyzer.GetATR(14);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double slPrice, slDistance, tpPrice;

        if(bullish)
        {
            slPrice = turtleSoup.sweepPrice - 0.3 * atr;
            slDistance = MathAbs(currentPrice - slPrice);
            tpPrice = currentPrice + 2.0 * slDistance;
        }
        else
        {
            slPrice = turtleSoup.sweepPrice + 0.3 * atr;
            slDistance = MathAbs(slPrice - currentPrice);
            tpPrice = currentPrice - 2.0 * slDistance;
        }

        // Unlike the ATR-multiple denominators in the ICT strategies, this one feeds the risk
        // pipeline real price points: distance / SYMBOL_POINT.
        double tpDistance = MathAbs(tpPrice - currentPrice);
        double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0;
        double tpPips = (point > 0 && tpDistance > 0) ? (tpDistance / point) : 0.0;

        STradeValidationRequest request;
        request.symbol = m_symbol;
        request.orderType = bullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        request.stopLossPips = slPips;
        request.takeProfitPips = tpPips;
        request.confidence = confidence;
        request.strategy = GetName();
        request.clusterCode = "";

        SetProposedStops(request.stopLossPips, request.takeProfitPips); // proposed stops must be published before risk gating
        if(!ValidateWithRiskManager(request, "TURTLE-SOUP", confidence))
            return TRADE_SIGNAL_NONE;

        SetDecisionReasonTag(bullish ? "TURTLE_SIGNAL_BUY" : "TURTLE_SIGNAL_SELL");
        RecordSignal();

        LogConsensusDiag(signal, StringFormat("TS-Conf: %.2f | Struct: %s | FVG: %s | CHOCH: %s", turtleSoup.confidence, structureAligned ? "Yes" : "No", hasFVGConfluence ? "Yes" : "No", fastCHOCH ? "Yes" : "No"), confidence);

        PrintFormat("[TURTLE-SOUP] %s: %s | Ref: %.5f | Sweep: %.5f | Conf: %.1f%% | Struct: %s | FVG: %s",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   turtleSoup.referencePrice,
                   turtleSoup.sweepPrice,
                   confidence * 100,
                   structureAligned ? "Yes" : "No",
                   hasFVGConfluence ? "Yes" : "No");

        return signal;
    }

    virtual string GetName() const override { return "Turtle Soup"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_TURTLE_SOUP; }
};

#endif
