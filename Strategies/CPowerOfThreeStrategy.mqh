//+------------------------------------------------------------------+
//| CPowerOfThreeStrategy.mqh                                        |
//| ICT Power of Three / ICT 2025 model                              |
//| Turtle Soup + OTE + FVG + SMT + AMD distribution                 |
//+------------------------------------------------------------------+
#property strict

#ifndef __C_POWER_OF_THREE_STRATEGY_MQH__
#define __C_POWER_OF_THREE_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include "UnifiedICTFiles/AMDDetector.mqh"
#include "UnifiedICTFiles/LiquidityDetector.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"
#include "UnifiedICTFiles/SMTDivergenceScanner.mqh"
#include "SMCFiles/PremiumDiscount.mqh"

class CPowerOfThreeStrategy : public CStrategyBase
{
private:
    CAMDDetector*             m_amdDetector;
    CLiquidityDetector*       m_liquidityDetector;
    CImbalanceDetector*       m_imbalanceDetector;
    CMarketStructureAnalyzer* m_structureAnalyzer;
    CSMCPremiumDiscount*      m_premiumDiscount;
    CSMTDivergenceScanner*    m_smtScanner;
    bool                      m_smtAvailable;
    int                       m_lastBarCount;

    bool RefreshForNewBar()
    {
        int barCount = iBars(m_symbol, m_timeframe);
        if(barCount <= 0 || barCount == m_lastBarCount)
            return false;

        m_lastBarCount = barCount;
        if(m_amdDetector != NULL) m_amdDetector.Update();
        if(m_liquidityDetector != NULL) m_liquidityDetector.Update();
        if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
        if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
        if(m_premiumDiscount != NULL) m_premiumDiscount.Update();
        return true;
    }

public:
    CPowerOfThreeStrategy(const string name = "Power of Three") :
        CStrategyBase(name, 0),
        m_amdDetector(NULL),
        m_liquidityDetector(NULL),
        m_imbalanceDetector(NULL),
        m_structureAnalyzer(NULL),
        m_premiumDiscount(NULL),
        m_smtScanner(NULL),
        m_smtAvailable(false),
        m_lastBarCount(0)
    {
        OverrideMinConfidence(0.64);
    }

    virtual ~CPowerOfThreeStrategy()
    {
        Deinit();
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;

        m_amdDetector = new CAMDDetector();
        m_liquidityDetector = new CLiquidityDetector();
        m_imbalanceDetector = new CImbalanceDetector();
        m_structureAnalyzer = new CMarketStructureAnalyzer();
        m_premiumDiscount = new CSMCPremiumDiscount();
        m_smtScanner = new CSMTDivergenceScanner();
        if(m_amdDetector == NULL || m_liquidityDetector == NULL || m_imbalanceDetector == NULL ||
           m_structureAnalyzer == NULL || m_premiumDiscount == NULL || m_smtScanner == NULL)
            return false;

        if(!m_amdDetector.Initialize(symbol, timeframe, 2) ||
           !m_liquidityDetector.Initialize(symbol, timeframe, 5.0) ||
           !m_imbalanceDetector.Initialize(symbol, timeframe) ||
           !m_structureAnalyzer.Initialize(symbol, timeframe, 3) ||
           !m_premiumDiscount.Initialize(symbol, timeframe, 100))
        {
            return false;
        }
        m_smtAvailable = m_smtScanner.Initialize(symbol, timeframe, 80);
        m_lastBarCount = 0;
        return true;
    }

    virtual void Deinit() override
    {
        if(m_amdDetector != NULL) { delete m_amdDetector; m_amdDetector = NULL; }
        if(m_liquidityDetector != NULL) { delete m_liquidityDetector; m_liquidityDetector = NULL; }
        if(m_imbalanceDetector != NULL) { delete m_imbalanceDetector; m_imbalanceDetector = NULL; }
        if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
        if(m_premiumDiscount != NULL) { delete m_premiumDiscount; m_premiumDiscount = NULL; }
        if(m_smtScanner != NULL) { delete m_smtScanner; m_smtScanner = NULL; }
        m_smtAvailable = false;
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
        SetDecisionReasonTag("PO3_UNSET");
        if(!IsEnabled() || !m_is_initialized)
        {
            SetDecisionReasonTag("PO3_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        RefreshForNewBar();
        if(m_amdDetector == NULL || m_liquidityDetector == NULL || m_imbalanceDetector == NULL ||
           m_structureAnalyzer == NULL || m_premiumDiscount == NULL || m_smtScanner == NULL)
        {
            SetDecisionReasonTag("PO3_COMPONENTS_NOT_READY");
            return TRADE_SIGNAL_NONE;
        }

        SAMDState state = m_amdDetector.GetState();
        if(!(state.phase == AMD_PHASE_DISTRIBUTION || state.phase == AMD_PHASE_POST_DISTRIBUTION))
        {
            SetDecisionReasonTag("PO3_NOT_IN_DISTRIBUTION");
            return TRADE_SIGNAL_NONE;
        }
        if(!state.liquiditySwept)
        {
            SetDecisionReasonTag("PO3_NO_LIQUIDITY_SWEEP");
            return TRADE_SIGNAL_NONE;
        }

        bool bullish = false;
        if(state.isBullishManipulation)
            bullish = true;
        else if(state.isBearishManipulation)
            bullish = false;
        else
        {
            SetDecisionReasonTag("PO3_DIRECTION_UNCLEAR");
            return TRADE_SIGNAL_NONE;
        }

        if(!m_structureAnalyzer.IsHTFAligned(bullish))
        {
            SetDecisionReasonTag("PO3_HTF_NOT_ALIGNED");
            return TRADE_SIGNAL_NONE;
        }

        STurtleSoupSignal turtleSoup;
        bool hasTurtleSoup = m_liquidityDetector.DetectTurtleSoup(turtleSoup, 4);
        if(hasTurtleSoup && turtleSoup.bullish != bullish)
            hasTurtleSoup = false;

        int imbIdx = bullish ? m_imbalanceDetector.FindBestBullishImbalance()
                             : m_imbalanceDetector.FindBestBearishImbalance();
        if(imbIdx < 0)
        {
            SetDecisionReasonTag("PO3_NO_FVG");
            return TRADE_SIGNAL_NONE;
        }

        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        bool oteAligned = bullish ? m_premiumDiscount.IsInBullishOTE(currentPrice)
                                  : m_premiumDiscount.IsInBearishOTE(currentPrice);
        if(!oteAligned)
        {
            SetDecisionReasonTag("PO3_OTE_NOT_ALIGNED");
            return TRADE_SIGNAL_NONE;
        }

        SSMTDivergence divergence;
        bool hasSMT = (m_smtAvailable && m_smtScanner != NULL && m_smtScanner.Scan(divergence));
        if(hasSMT && divergence.isBearish == bullish)
            hasSMT = false;

        bool cisdAligned = m_structureAnalyzer.IsCISD(bullish ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, 1);
        if(!cisdAligned && !state.chochAfterSweep)
        {
            SetDecisionReasonTag("PO3_NO_STRUCTURE_CONFIRMATION");
            return TRADE_SIGNAL_NONE;
        }

        double score = MathMax(0.55, state.confidence);
        score += hasTurtleSoup ? 0.10 : 0.0;
        score += oteAligned ? 0.08 : 0.0;
        score += hasSMT ? 0.07 : 0.0;
        score += cisdAligned ? 0.05 : 0.0;
        score += state.chochAfterSweep ? 0.05 : 0.0;
        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("PO3_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        SetDecisionReasonTag(bullish ? "PO3_SIGNAL_BUY" : "PO3_SIGNAL_SELL");
        RecordSignal();
        return bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
    }

    virtual string GetName() const override { return "Power of Three"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_UNIFIED_ICT; }
};

#endif
