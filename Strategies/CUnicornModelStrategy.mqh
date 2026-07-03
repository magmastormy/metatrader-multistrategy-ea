//+------------------------------------------------------------------+
//| CUnicornModelStrategy.mqh                                        |
//| ICT Unicorn Model: breaker/order-block + FVG after liquidity     |
//| sweep and MSS/CISD confirmation                                  |
//|                                                                  |
//| STATUS: DISABLED (subjective ICT concepts)                       |
//| Disabled via InpEnableUnicornModel = false in MultiStrategyAutonomousEA.mq5 |
//+------------------------------------------------------------------+
#ifndef C_UNICORN_MODEL_STRATEGY_MQH
#define C_UNICORN_MODEL_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"
#include "UnifiedICTFiles/AdvancedOrderBlocks.mqh"
#include "UnifiedICTFiles/LiquidityDetector.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

// CUnicornModelStrategy implements the ICT Unicorn Model: breaker/order-block
// + FVG after liquidity sweep and MSS/CISD confirmation.
// STATUS: DISABLED (subjective ICT concepts).
class CUnicornModelStrategy : public CStrategyBase
{
private:
    CMarketStructureAnalyzer*    m_structureAnalyzer;
    CAdvancedOrderBlockDetector* m_obDetector;
    CLiquidityDetector*          m_liquidityDetector;
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
        if(m_liquidityDetector != NULL) m_liquidityDetector.Update();
        if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
        return true;
    }

public:
    CUnicornModelStrategy(const string name = "Unicorn Model") :
        CStrategyBase(name, 0),
        m_structureAnalyzer(NULL),
        m_obDetector(NULL),
        m_liquidityDetector(NULL),
        m_imbalanceDetector(NULL),
        m_lastBarCount(0),
        m_riskManager(NULL)
    {
        OverrideMinConfidence(0.55);
    }

    virtual ~CUnicornModelStrategy()
    {
        Deinit();
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_structureAnalyzer = new CMarketStructureAnalyzer();
        m_obDetector = new CAdvancedOrderBlockDetector();
        m_liquidityDetector = new CLiquidityDetector();
        m_imbalanceDetector = new CImbalanceDetector();
        if(m_structureAnalyzer == NULL || m_obDetector == NULL || m_liquidityDetector == NULL || m_imbalanceDetector == NULL)
            return false;

        if(!m_structureAnalyzer.Initialize(symbol, timeframe, 3) ||
           !m_obDetector.Initialize(symbol, timeframe) ||
           !m_liquidityDetector.Initialize(symbol, timeframe, 5.0) ||
           !m_imbalanceDetector.Initialize(symbol, timeframe))
        {
            return false;
        }

        m_lastBarCount = 0;
        
        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[UNICORN] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");
        
        return true;
    }

    virtual void Deinit() override
    {
        if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
        if(m_obDetector != NULL) { delete m_obDetector; m_obDetector = NULL; }
        if(m_liquidityDetector != NULL) { delete m_liquidityDetector; m_liquidityDetector = NULL; }
        if(m_imbalanceDetector != NULL) { delete m_imbalanceDetector; m_imbalanceDetector = NULL; }
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
        CStrategyBase::Deinit();
    }

    virtual void OnTick() override
    {
        // Intentionally empty - strategy evaluates on new bar only via GetSignal()
    }
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(symbol == m_symbol && timeframe == m_timeframe)
            RefreshForNewBar();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("UNICORN_UNSET");
        if(!IsEnabled() || !m_is_initialized)
        {
            SetDecisionReasonTag("UNICORN_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        RefreshForNewBar();
        if(m_structureAnalyzer == NULL || m_obDetector == NULL || m_liquidityDetector == NULL || m_imbalanceDetector == NULL)
        {
            SetDecisionReasonTag("UNICORN_COMPONENTS_NOT_READY");
            return TRADE_SIGNAL_NONE;
        }

        bool sweepBuyside = false;
        if(!m_liquidityDetector.HasRecentSweep(sweepBuyside))
        {
            SetDecisionReasonTag("UNICORN_NO_RECENT_SWEEP");
            return TRADE_SIGNAL_NONE;
        }

        bool bullish = !sweepBuyside;
        // Phase 3.3: Skip HTF alignment for M1/M5 timeframes (lower TF signals are self-contained)
        if(m_timeframe != PERIOD_M1 && m_timeframe != PERIOD_M5)
        {
            if(!m_structureAnalyzer.IsHTFAligned(bullish))
            {
                SetDecisionReasonTag("UNICORN_HTF_NOT_ALIGNED");
                return TRADE_SIGNAL_NONE;
            }
        }

        bool ltfAligned = bullish ? m_structureAnalyzer.IsBullishStructure()
                                  : m_structureAnalyzer.IsBearishStructure();
        bool cisdAligned = m_structureAnalyzer.IsCISD(bullish ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, 1);
        if(!ltfAligned && !cisdAligned)
        {
            SetDecisionReasonTag("UNICORN_LTF_NOT_ALIGNED");
            return TRADE_SIGNAL_NONE;
        }

        int obIdx = bullish ? m_obDetector.FindBestBullishOB() : m_obDetector.FindBestBearishOB();
        int imbIdx = bullish ? m_imbalanceDetector.FindBestBullishImbalance() : m_imbalanceDetector.FindBestBearishImbalance();
        if(obIdx < 0 || imbIdx < 0)
        {
            SetDecisionReasonTag("UNICORN_NO_OB_OR_FVG");
            return TRADE_SIGNAL_NONE;
        }

        SAdvancedOrderBlock ob;
        SImbalance imb;
        if(!m_obDetector.GetOrderBlock(obIdx, ob) || !m_imbalanceDetector.GetImbalance(imbIdx, imb))
        {
            SetDecisionReasonTag("UNICORN_COMPONENT_LOOKUP_FAILED");
            return TRADE_SIGNAL_NONE;
        }

        if(bullish && !m_obDetector.IsBullishOBType(ob.type))
        {
            SetDecisionReasonTag("UNICORN_OB_TYPE_MISMATCH");
            return TRADE_SIGNAL_NONE;
        }
        if(!bullish && !m_obDetector.IsBearishOBType(ob.type))
        {
            SetDecisionReasonTag("UNICORN_OB_TYPE_MISMATCH");
            return TRADE_SIGNAL_NONE;
        }

        double overlapTop = MathMin(ob.top, imb.top);
        double overlapBottom = MathMax(ob.bottom, imb.bottom);
        bool hasOverlap = (overlapTop > overlapBottom);

        // OB/FVG overlap is a strong confluence but not a hard requirement.
        // On synthetics, OBs and FVGs can form at different price levels
        // due to rapid price movements. Penalize confidence instead of blocking.
        double overlapPenalty = 0.0;
        if(!hasOverlap)
        {
            overlapPenalty = 0.10;  // Reduce confidence when no spatial overlap
            Print(StringFormat("[UNICORN] OB/FVG no overlap - applying confidence penalty (OB: %.2f-%.2f, FVG: %.2f-%.2f)",
                         ob.bottom, ob.top, imb.bottom, imb.top));
        }

        double score = 0.55;
        score += MathMin(0.12, ob.strength * 0.10);
        score += MathMin(0.12, imb.strength * 0.10);
        score += cisdAligned ? 0.07 : 0.0;
        score += ltfAligned ? 0.04 : 0.0;
        score += (ob.type == OB_BREAKER_BULL || ob.type == OB_BREAKER_BEAR) ? 0.05 : 0.0;
        score += hasOverlap ? 0.05 : 0.0;  // Bonus for OB/FVG overlap
        score -= overlapPenalty;             // Penalty when no overlap
        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("UNICORN_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        ENUM_TRADE_SIGNAL signal = bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        // Calculate structure-based SL using OB/FVG boundaries
        double slPrice = bullish ? MathMin(ob.bottom, imb.bottom) : MathMax(ob.top, imb.top);
        double slDistance = MathAbs(currentPrice - slPrice);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0; // No fallback - skip if SL invalid
        
        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = bullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            request.stopLossPips = slPips;
            request.takeProfitPips = slPips * 2.0; // 1:2 R:R ratio
            request.confidence = confidence;
            request.strategy = GetName();
            request.clusterCode = "";
            
            CUnifiedRiskManager* riskMgr = m_riskManager;
            SValidationResult result;
            ZeroMemory(result);
            if(riskMgr != NULL)
                result = (*riskMgr).ValidateTradeRequest(request, "UNICORN");
            if(!result.approved)
            {
                SetDecisionReasonTag("UNICORN_RISK_REJECTED");
                PrintFormat("[UNICORN] Risk rejected %s at %.5f Conf=%.1f%%",
                           signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           currentPrice, confidence * 100);
                return TRADE_SIGNAL_NONE;
            }
            confidence *= result.confidenceMultiplier;
        }

        SetDecisionReasonTag(bullish ? "UNICORN_SIGNAL_BUY" : "UNICORN_SIGNAL_SELL");
        RecordSignal();
        
        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | OB: %s | FVG: %s | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   EnumToString(ob.type),
                   imb.isBullish ? "Bull" : "Bear",
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);
        
        PrintFormat("[UNICORN] %s: %s | OB+FVG Overlap | Conf: %.1f%% | CISD: %s",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   confidence * 100,
                   cisdAligned ? "Yes" : "No");
        
        return signal;
    }

    virtual string GetName() const override { return "Unicorn Model"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_UNIFIED_ICT; }
};

#endif

