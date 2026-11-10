#ifndef BREAKER_BLOCK_STRATEGY_MQH
#define BREAKER_BLOCK_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
// Mandatory: every entry gates through CUnifiedRiskManager
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"
#include "UnifiedICTFiles/AdvancedOrderBlocks.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

// CBreakerBlockStrategy detects breaker order blocks, waits for price retest,
// and confirms with FVG confluence, CISD displacement, and market structure.
class CBreakerBlockStrategy : public CStrategyBase
{
private:
    CMarketStructureAnalyzer*    m_structureAnalyzer;
    CAdvancedOrderBlockDetector* m_obDetector;
    CImbalanceDetector*          m_imbalanceDetector;

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }
    virtual void OnRefreshComponents() override
    {
        if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
        if(m_obDetector != NULL) m_obDetector.Update();
        if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
    }

public:
    CBreakerBlockStrategy(const string name = "Breaker Block") :
        CStrategyBase(name, 0),
        m_structureAnalyzer(NULL),
        m_obDetector(NULL),
        m_imbalanceDetector(NULL)
    {
        OverrideMinConfidence(0.55);
    }

    virtual ~CBreakerBlockStrategy()
    {
        Deinit();
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_structureAnalyzer = new CMarketStructureAnalyzer();
        m_obDetector = new CAdvancedOrderBlockDetector();
        m_imbalanceDetector = new CImbalanceDetector();
        if(m_structureAnalyzer == NULL || m_obDetector == NULL || m_imbalanceDetector == NULL)
            return false;

        if(!m_structureAnalyzer.Initialize(symbol, timeframe, 3) ||
           !m_obDetector.Initialize(symbol, timeframe) ||
           !m_imbalanceDetector.Initialize(symbol, timeframe))
        {
            return false;
        }

        return true;
    }

    virtual void Deinit() override
    {
        if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
        if(m_obDetector != NULL) { delete m_obDetector; m_obDetector = NULL; }
        if(m_imbalanceDetector != NULL) { delete m_imbalanceDetector; m_imbalanceDetector = NULL; }
        CStrategyBase::Deinit();
    }

    virtual void OnTick() override
    {
        // Intentionally empty - strategy evaluates on new bar only via GetSignal()
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("BREAKER_UNSET");
        if(!IsEnabled() || !m_is_initialized)
        {
            SetDecisionReasonTag("BREAKER_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        RefreshForNewBar();
        if(m_structureAnalyzer == NULL || m_obDetector == NULL || m_imbalanceDetector == NULL)
        {
            SetDecisionReasonTag("BREAKER_COMPONENTS_NOT_READY");
            return TRADE_SIGNAL_NONE;
        }

        // Unmitigated breaker OBs only; price reads bar 1 (last closed bar), not the forming bar
        double currentClose = iClose(m_symbol, m_timeframe, 1);
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        int bestBreakerIdx = -1;
        ENUM_ORDER_BLOCK_TYPE bestBreakerType = OB_NONE;
        double bestBreakerStrength = 0.0;

        int obCount = m_obDetector.GetOBCount();
        for(int i = 0; i < obCount; i++)
        {
            SAdvancedOrderBlock ob;
            if(!m_obDetector.GetOrderBlock(i, ob))
                continue;
            if(ob.isMitigated)
                continue;

            if(ob.type != OB_BREAKER_BULL && ob.type != OB_BREAKER_BEAR)
                continue;

            // Retest = current close inside ob.bottom..ob.top
            bool priceInZone = (currentClose >= ob.bottom && currentClose <= ob.top);
            if(!priceInZone)
                continue;

            if(ob.strength > bestBreakerStrength)
            {
                bestBreakerStrength = ob.strength;
                bestBreakerIdx = i;
                bestBreakerType = ob.type;
            }
        }

        if(bestBreakerIdx < 0)
        {
            SetDecisionReasonTag("BREAKER_NO_BREAKER_RETEST");
            return TRADE_SIGNAL_NONE;
        }

        SAdvancedOrderBlock bestOB;
        if(!m_obDetector.GetOrderBlock(bestBreakerIdx, bestOB))
        {
            SetDecisionReasonTag("BREAKER_OB_LOOKUP_FAILED");
            return TRADE_SIGNAL_NONE;
        }

        bool bullish = (bestBreakerType == OB_BREAKER_BULL);

        // Bullish breaker retest = BUY, bearish breaker retest = SELL
        ENUM_TRADE_SIGNAL signal = bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

        double freshness = m_obDetector.GetFreshness(bestBreakerIdx);

        // FVG confluence means an imbalance in the breaker's own direction
        int imbIdx = bullish ? m_imbalanceDetector.FindBestBullishImbalance()
                             : m_imbalanceDetector.FindBestBearishImbalance();
        bool hasFVGConfluence = (imbIdx >= 0);

        SImbalance confluenceImb;
        if(hasFVGConfluence)
        {
            if(!m_imbalanceDetector.GetImbalance(imbIdx, confluenceImb))
                hasFVGConfluence = false;
        }

        // CISD displacement within the last 3 bars
        bool hasCISD = m_structureAnalyzer.HasRecentBullishCISD(3);
        if(!bullish)
            hasCISD = m_structureAnalyzer.HasRecentBearishCISD(3);

        bool structureAligned = bullish ? m_structureAnalyzer.IsBullishStructure()
                                        : m_structureAnalyzer.IsBearishStructure();

        double score = 0.55;  // Base confidence

        // Freshness boost: fresh OBs (> 0.7) get +0.08
        if(freshness > 0.7)
            score += 0.08;

        // FVG confluence: +0.10
        if(hasFVGConfluence)
            score += 0.10;

        // CISD displacement: +0.05
        if(hasCISD)
            score += 0.05;

        // Structure alignment: +0.07
        if(structureAligned)
            score += 0.07;

        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("BREAKER_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        // SL beyond the breaker boundary by 0.5*ATR, TP at 2R. Stops are ATR-denominated, not
        // SYMBOL_POINT pips: points are FX-calibrated and break on synthetics (point=0.01, prices in 1000s).
        double atr = m_structureAnalyzer.GetATR(14);
        double slPrice, tpPrice, slDistance;

        if(bullish)
        {
            slPrice = bestOB.bottom - 0.5 * atr;
            slDistance = MathAbs(currentPrice - slPrice);
            tpPrice = currentPrice + 2.0 * slDistance;  // 2R
        }
        else
        {
            slPrice = bestOB.top + 0.5 * atr;
            slDistance = MathAbs(slPrice - currentPrice);
            tpPrice = currentPrice - 2.0 * slDistance;  // 2R
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

        SetProposedStops(request.stopLossPips, request.takeProfitPips); // proposed stops must be published before risk gating
        if(!ValidateWithRiskManager(request, "BREAKER-BLOCK", confidence))
            return TRADE_SIGNAL_NONE;

        SetDecisionReasonTag(bullish ? "BREAKER_SIGNAL_BUY" : "BREAKER_SIGNAL_SELL");
        RecordSignal();

        LogConsensusDiag(signal, StringFormat("Breaker: %s | FVG: %s | Fresh: %.2f | CISD: %s | Struct: %s", EnumToString(bestBreakerType), hasFVGConfluence ? "Yes" : "No", freshness, hasCISD ? "Yes" : "No", structureAligned ? "Yes" : "No"), confidence);

        PrintFormat("[BREAKER-BLOCK] %s: %s | Zone: %.5f-%.5f | Freshness: %.2f | FVG: %s | CISD: %s | Conf: %.1f%%",
                   m_symbol,
                   bullish ? "BUY" : "SELL",
                   bestOB.bottom, bestOB.top,
                   freshness,
                   hasFVGConfluence ? "Yes" : "No",
                   hasCISD ? "Yes" : "No",
                   confidence * 100);

        return signal;
    }

    virtual string GetName() const override { return "Breaker Block"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_BREAKER_BLOCK; }
};

#endif
