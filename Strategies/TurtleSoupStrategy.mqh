//+------------------------------------------------------------------+
//| TurtleSoupStrategy.mqh                                           |
//| Turtle Soup: false breakout of liquidity + structure alignment   |
//| + FVG confluence bonus                                           |
//| Batch 103: New ICT/SMC strategy                                  |
//+------------------------------------------------------------------+
#ifndef __TURTLE_SOUP_STRATEGY_MQH__
#define __TURTLE_SOUP_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "UnifiedICTFiles/LiquidityDetector.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"

class CTurtleSoupStrategy : public CStrategyBase
{
private:
    CLiquidityDetector*       m_liquidityDetector;
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
        if(m_liquidityDetector != NULL) m_liquidityDetector.Update();
        if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
        if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
        return true;
    }

public:
    CTurtleSoupStrategy(const string name = "Turtle Soup") :
        CStrategyBase(name, 0),
        m_liquidityDetector(NULL),
        m_imbalanceDetector(NULL),
        m_structureAnalyzer(NULL),
        m_lastBarCount(0),
        m_riskManager(NULL)
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

        m_lastBarCount = 0;

        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[TURTLE-SOUP] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_liquidityDetector != NULL) { delete m_liquidityDetector; m_liquidityDetector = NULL; }
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

        // Step 1: Detect Turtle Soup signal (false breakout of liquidity)
        STurtleSoupSignal turtleSoup;
        if(!m_liquidityDetector.DetectTurtleSoup(turtleSoup, 4))
        {
            SetDecisionReasonTag("TURTLE_NO_SIGNAL");
            return TRADE_SIGNAL_NONE;
        }

        // Step 2: Determine direction from turtle soup
        bool bullish = turtleSoup.bullish;
        ENUM_TRADE_SIGNAL signal = bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

        // Step 3: Check structure alignment
        bool structureAligned = bullish ? m_structureAnalyzer.IsBullishStructure()
                                        : m_structureAnalyzer.IsBearishStructure();

        // Fast CHOCH (CISD) as alternative structure confirmation
        bool fastCHOCH = bullish ? m_structureAnalyzer.IsCISD(POSITION_TYPE_BUY, 1)
                                 : m_structureAnalyzer.IsCISD(POSITION_TYPE_SELL, 1);

        if(!structureAligned && !fastCHOCH)
        {
            SetDecisionReasonTag("TURTLE_STRUCTURE_NOT_ALIGNED");
            return TRADE_SIGNAL_NONE;
        }

        // Step 4: FVG confluence bonus
        int imbIdx = bullish ? m_imbalanceDetector.FindBestBullishImbalance()
                             : m_imbalanceDetector.FindBestBearishImbalance();
        bool hasFVGConfluence = (imbIdx >= 0);

        // Step 5: Build confidence score
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

        // Step 6: Calculate SL beyond false break extreme + 0.3*ATR, TP at 2R
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double atr = m_structureAnalyzer.GetATR(14);
        double slPrice, slDistance;

        if(bullish)
        {
            // Bullish turtle soup: SL below the sweep low + 0.3*ATR
            slPrice = turtleSoup.sweepPrice - 0.3 * atr;
            slDistance = MathAbs(currentPrice - slPrice);
        }
        else
        {
            // Bearish turtle soup: SL above the sweep high + 0.3*ATR
            slPrice = turtleSoup.sweepPrice + 0.3 * atr;
            slDistance = MathAbs(slPrice - currentPrice);
        }

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0;

        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = bullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            request.stopLossPips = slPips;
            request.takeProfitPips = slPips * 2.0; // 2R take profit
            request.confidence = confidence;
            request.strategy = GetName();
            request.clusterCode = "";

            CUnifiedRiskManager* riskMgr = m_riskManager;
            SValidationResult result;
            ZeroMemory(result);
            if(riskMgr != NULL)
                result = (*riskMgr).ValidateTradeRequest(request, "TURTLE-SOUP");
            if(!result.approved)
            {
                SetDecisionReasonTag("TURTLE_RISK_REJECTED");
                PrintFormat("[TURTLE-SOUP] Risk rejected %s at %.5f Conf=%.1f%%",
                           signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           currentPrice, confidence * 100);
                return TRADE_SIGNAL_NONE;
            }
            confidence *= result.confidenceMultiplier;
        }

        SetDecisionReasonTag(bullish ? "TURTLE_SIGNAL_BUY" : "TURTLE_SIGNAL_SELL");
        RecordSignal();

        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | TS-Conf: %.2f | Struct: %s | FVG: %s | CHOCH: %s | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   turtleSoup.confidence,
                   structureAligned ? "Yes" : "No",
                   hasFVGConfluence ? "Yes" : "No",
                   fastCHOCH ? "Yes" : "No",
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);

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
