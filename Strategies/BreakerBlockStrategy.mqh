//+------------------------------------------------------------------+
//| BreakerBlockStrategy.mqh                                         |
//| ICT Breaker Block Strategy: breaker OB retest + FVG confluence   |
//| with structure alignment and CISD displacement confirmation      |
//|                                                                  |
//| Detects breaker blocks (OB_BREAKER_BULL/OB_BREAKER_BEAR), waits  |
//| for price retest of the breaker zone, and confirms with opposing |
//| FVG confluence, CISD displacement, and market structure context. |
//+------------------------------------------------------------------+
#ifndef __BREAKER_BLOCK_STRATEGY_MQH__
#define __BREAKER_BLOCK_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"
#include "UnifiedICTFiles/AdvancedOrderBlocks.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

class CBreakerBlockStrategy : public CStrategyBase
{
private:
    CMarketStructureAnalyzer*    m_structureAnalyzer;
    CAdvancedOrderBlockDetector* m_obDetector;
    CImbalanceDetector*          m_imbalanceDetector;
    int                          m_lastBarCount;

    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager*         m_riskManager;

    bool RefreshForNewBar()
    {
        int barCount = iBars(m_symbol, m_timeframe);
        if(barCount <= 0 || barCount == m_lastBarCount)
            return false;

        m_lastBarCount = barCount;
        if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
        if(m_obDetector != NULL) m_obDetector.Update();
        if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
        return true;
    }

    bool IsBullishOBType(const ENUM_ORDER_BLOCK_TYPE type) const
    {
        return (type == OB_BREAKER_BULL || type == OB_PROPULSION_BULL ||
                type == OB_REJECTION_BULL || type == OB_VACUUM_BULL ||
                type == OB_CONTINUATION_BULL || type == OB_SOURCE_BULLISH);
    }

    bool IsBearishOBType(const ENUM_ORDER_BLOCK_TYPE type) const
    {
        return (type == OB_BREAKER_BEAR || type == OB_PROPULSION_BEAR ||
                type == OB_REJECTION_BEAR || type == OB_VACUUM_BEAR ||
                type == OB_CONTINUATION_BEAR || type == OB_SOURCE_BEARISH);
    }

public:
    CBreakerBlockStrategy(const string name = "Breaker Block") :
        CStrategyBase(name, 0),
        m_structureAnalyzer(NULL),
        m_obDetector(NULL),
        m_imbalanceDetector(NULL),
        m_lastBarCount(0),
        m_riskManager(NULL)
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

        m_lastBarCount = 0;

        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[BREAKER-BLOCK] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
        if(m_obDetector != NULL) { delete m_obDetector; m_obDetector = NULL; }
        if(m_imbalanceDetector != NULL) { delete m_imbalanceDetector; m_imbalanceDetector = NULL; }
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

        // --- Step 1: Find breaker OBs that are NOT mitigated ---
        double currentClose = iClose(m_symbol, m_timeframe, 0);
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

            // Only consider breaker block types
            if(ob.type != OB_BREAKER_BULL && ob.type != OB_BREAKER_BEAR)
                continue;

            // Check if price is retesting the breaker zone
            // Price retest: current close is between ob.bottom and ob.top
            bool priceInZone = (currentClose >= ob.bottom && currentClose <= ob.top);
            if(!priceInZone)
                continue;

            // Pick the strongest breaker that price is retesting
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

        // --- Step 2: Determine direction from breaker type ---
        SAdvancedOrderBlock bestOB;
        if(!m_obDetector.GetOrderBlock(bestBreakerIdx, bestOB))
        {
            SetDecisionReasonTag("BREAKER_OB_LOOKUP_FAILED");
            return TRADE_SIGNAL_NONE;
        }

        bool bullish = (bestBreakerType == OB_BREAKER_BULL);

        // For bearish breaker (OB_BREAKER_BEAR): price retests → SELL
        // For bullish breaker (OB_BREAKER_BULL): price retests → BUY
        ENUM_TRADE_SIGNAL signal = bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

        // --- Step 3: Apply OB freshness weighting ---
        double freshness = m_obDetector.GetFreshness(bestBreakerIdx);

        // --- Step 4: Check for opposing FVG confluence ---
        // For bearish breaker, find bearish FVG; for bullish breaker, find bullish FVG
        int imbIdx = bullish ? m_imbalanceDetector.FindBestBullishImbalance()
                             : m_imbalanceDetector.FindBestBearishImbalance();
        bool hasFVGConfluence = (imbIdx >= 0);

        SImbalance confluenceImb;
        if(hasFVGConfluence)
        {
            if(!m_imbalanceDetector.GetImbalance(imbIdx, confluenceImb))
                hasFVGConfluence = false;
        }

        // --- Step 5: CISD displacement check ---
        bool hasCISD = m_structureAnalyzer.HasRecentBullishCISD(3);
        if(!bullish)
            hasCISD = m_structureAnalyzer.HasRecentBearishCISD(3);

        // --- Step 6: Structure alignment ---
        bool structureAligned = bullish ? m_structureAnalyzer.IsBullishStructure()
                                        : m_structureAnalyzer.IsBearishStructure();

        // --- Step 7: Build confidence score ---
        double score = 0.55;  // Base confidence

        // Freshness boost: fresh OBs (> 0.7) get +0.08
        if(freshness > 0.7)
            score += 0.08;

        // Opposing FVG confluence: +0.10
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

        // --- Step 8: Calculate SL/TP ---
        // SL beyond breaker boundary + 0.5*ATR, TP at 2R
        double atr = m_structureAnalyzer.GetATR(14);
        double slPrice;
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

        if(bullish)
        {
            // For BUY: SL below breaker bottom - 0.5*ATR
            slPrice = bestOB.bottom - 0.5 * atr;
            double slDistance = MathAbs(currentPrice - slPrice);
            double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0;
            double tpPips = slPips * 2.0;  // 2R

            // Risk validation (AGENTS.md invariant #1)
            if(m_riskManager != NULL)
            {
                STradeValidationRequest request;
                request.symbol = m_symbol;
                request.orderType = ORDER_TYPE_BUY;
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
                    result = (*riskMgr).ValidateTradeRequest(request, "BREAKER-BLOCK");
                if(!result.approved)
                {
                    SetDecisionReasonTag("BREAKER_RISK_REJECTED");
                    PrintFormat("[BREAKER-BLOCK] Risk rejected BUY at %.5f Conf=%.1f%%",
                               currentPrice, confidence * 100);
                    return TRADE_SIGNAL_NONE;
                }
                confidence *= result.confidenceMultiplier;
            }
        }
        else
        {
            // For SELL: SL above breaker top + 0.5*ATR
            slPrice = bestOB.top + 0.5 * atr;
            double slDistance = MathAbs(slPrice - currentPrice);
            double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0;
            double tpPips = slPips * 2.0;  // 2R

            // Risk validation (AGENTS.md invariant #1)
            if(m_riskManager != NULL)
            {
                STradeValidationRequest request;
                request.symbol = m_symbol;
                request.orderType = ORDER_TYPE_SELL;
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
                    result = (*riskMgr).ValidateTradeRequest(request, "BREAKER-BLOCK");
                if(!result.approved)
                {
                    SetDecisionReasonTag("BREAKER_RISK_REJECTED");
                    PrintFormat("[BREAKER-BLOCK] Risk rejected SELL at %.5f Conf=%.1f%%",
                               currentPrice, confidence * 100);
                    return TRADE_SIGNAL_NONE;
                }
                confidence *= result.confidenceMultiplier;
            }
        }

        SetDecisionReasonTag(bullish ? "BREAKER_SIGNAL_BUY" : "BREAKER_SIGNAL_SELL");
        RecordSignal();

        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | Breaker: %s | FVG: %s | Fresh: %.2f | CISD: %s | Struct: %s | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   m_symbol,
                   bullish ? "BUY" : "SELL",
                   EnumToString(bestBreakerType),
                   hasFVGConfluence ? "Yes" : "No",
                   freshness,
                   hasCISD ? "Yes" : "No",
                   structureAligned ? "Yes" : "No",
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);

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
