//+------------------------------------------------------------------+
//| CUnicornModelStrategy.mqh                                        |
//| ICT Unicorn Model: breaker/order-block + FVG after liquidity     |
//| sweep and MSS/CISD confirmation                                  |
//+------------------------------------------------------------------+
#property strict

#ifndef __C_UNICORN_MODEL_STRATEGY_MQH__
#define __C_UNICORN_MODEL_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"
#include "UnifiedICTFiles/AdvancedOrderBlocks.mqh"
#include "UnifiedICTFiles/LiquidityDetector.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

class CUnicornModelStrategy : public CStrategyBase
{
private:
    CMarketStructureAnalyzer*    m_structureAnalyzer;
    CAdvancedOrderBlockDetector* m_obDetector;
    CLiquidityDetector*          m_liquidityDetector;
    CImbalanceDetector*          m_imbalanceDetector;
    int                          m_lastBarCount;

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
    CUnicornModelStrategy(const string name = "Unicorn Model") :
        CStrategyBase(name, 0),
        m_structureAnalyzer(NULL),
        m_obDetector(NULL),
        m_liquidityDetector(NULL),
        m_imbalanceDetector(NULL),
        m_lastBarCount(0)
    {
        OverrideMinConfidence(0.62);
    }

    virtual ~CUnicornModelStrategy()
    {
        Deinit();
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
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
        return true;
    }

    virtual void Deinit() override
    {
        if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
        if(m_obDetector != NULL) { delete m_obDetector; m_obDetector = NULL; }
        if(m_liquidityDetector != NULL) { delete m_liquidityDetector; m_liquidityDetector = NULL; }
        if(m_imbalanceDetector != NULL) { delete m_imbalanceDetector; m_imbalanceDetector = NULL; }
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
        if(!m_structureAnalyzer.IsHTFAligned(bullish))
        {
            SetDecisionReasonTag("UNICORN_HTF_NOT_ALIGNED");
            return TRADE_SIGNAL_NONE;
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

        if(bullish && !IsBullishOBType(ob.type))
        {
            SetDecisionReasonTag("UNICORN_OB_TYPE_MISMATCH");
            return TRADE_SIGNAL_NONE;
        }
        if(!bullish && !IsBearishOBType(ob.type))
        {
            SetDecisionReasonTag("UNICORN_OB_TYPE_MISMATCH");
            return TRADE_SIGNAL_NONE;
        }

        double overlapTop = MathMin(ob.top, imb.top);
        double overlapBottom = MathMax(ob.bottom, imb.bottom);
        if(overlapTop <= overlapBottom)
        {
            SetDecisionReasonTag("UNICORN_NO_OB_FVG_OVERLAP");
            return TRADE_SIGNAL_NONE;
        }

        double score = 0.62;
        score += MathMin(0.12, ob.strength * 0.10);
        score += MathMin(0.12, imb.strength * 0.10);
        score += cisdAligned ? 0.07 : 0.0;
        score += ltfAligned ? 0.04 : 0.0;
        score += (ob.type == OB_BREAKER_BULL || ob.type == OB_BREAKER_BEAR) ? 0.05 : 0.0;
        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("UNICORN_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        SetDecisionReasonTag(bullish ? "UNICORN_SIGNAL_BUY" : "UNICORN_SIGNAL_SELL");
        RecordSignal();
        return bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
    }

    virtual string GetName() const override { return "Unicorn Model"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_UNIFIED_ICT; }
};

#endif
