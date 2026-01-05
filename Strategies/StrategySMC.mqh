//+------------------------------------------------------------------+
//| StrategySMC.mqh                                                  |
//| Advanced Smart Money Concepts Strategy v2.0                      |
//| Full ICT Methodology: Market Structure, Kill Zones, OB, FVG,     |
//| Liquidity Sweeps, Premium/Discount, Multi-Factor Confluence      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced AI Coding Assistant"
#property version   "2.00"
#property strict

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"

// Enhanced SMC Component Files
#include "SMCFiles/MarketStructure.mqh"
#include "SMCFiles/KillZones.mqh"
#include "SMCFiles/OrderBlocks.mqh"
#include "SMCFiles/FairValueGap.mqh"
#include "SMCFiles/LiquiditySweep.mqh"
#include "SMCFiles/PremiumDiscount.mqh"
#include "SMCFiles/SMCConfluence.mqh"

//+------------------------------------------------------------------+
//| Advanced SMC Strategy Class v2.0                                 |
//+------------------------------------------------------------------+
class CStrategySMC : public CStrategyBase
{
private:
    // Enhanced Components (using correct class names from component files)
    CSMCMarketStructure*    m_marketStructure;
    CICTKillZones*          m_killZones;
    CSMCOrderBlocks*        m_orderBlocks;
    CSMCFairValueGap*       m_fvgDetector;
    CSMCLiquiditySweep*     m_liquiditySweep;
    CSMCPremiumDiscount*    m_premiumDiscount;
    CSMCConfluenceEngine*   m_confluence;
    
    // Visualization
    CChartDrawingManager*   m_drawer;
    
    // Configuration
    double    m_minConfluenceScore;
    bool      m_requireKillZone;
    bool      m_requireOTE;
    int       m_lastBarProcessed;
    
    // Statistics
    int       m_signalsGenerated;
    int       m_tradesInKillZone;
    int       m_tradesInOTE;
    
public:
    CStrategySMC();
    ~CStrategySMC();
    
    // IStrategy implementation
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    virtual void OnTick() override;
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual string GetName() const override { return "SMC Strategy v2.0"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_SMC; }
    
    // Configuration
    void SetMinConfidence(double conf) { m_minConfidence = conf; }
    void SetRequireKillZone(bool req) { m_requireKillZone = req; }
    void SetRequireOTE(bool req) { m_requireOTE = req; }
    
    // Accessors for components
    CSMCMarketStructure* GetMarketStructure() { return m_marketStructure; }
    CICTKillZones* GetKillZones() { return m_killZones; }
    CSMCConfluenceEngine* GetConfluence() { return m_confluence; }
    
private:
    void Cleanup();
    void DrawSMCElements();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategySMC::CStrategySMC() :
    CStrategyBase("SMC Strategy v2.0", 0),
    m_marketStructure(NULL),
    m_killZones(NULL),
    m_orderBlocks(NULL),
    m_fvgDetector(NULL),
    m_liquiditySweep(NULL),
    m_premiumDiscount(NULL),
    m_confluence(NULL),
    m_drawer(NULL),
    m_minConfluenceScore(60.0),
    m_requireKillZone(false),
    m_requireOTE(false),
    m_lastBarProcessed(0),
    m_signalsGenerated(0),
    m_tradesInKillZone(0),
    m_tradesInOTE(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategySMC::~CStrategySMC()
{
    Cleanup();
}

//+------------------------------------------------------------------+
//| Cleanup helper                                                   |
//+------------------------------------------------------------------+
void CStrategySMC::Cleanup()
{
    if(m_marketStructure != NULL) { delete m_marketStructure; m_marketStructure = NULL; }
    if(m_killZones != NULL) { delete m_killZones; m_killZones = NULL; }
    if(m_orderBlocks != NULL) { delete m_orderBlocks; m_orderBlocks = NULL; }
    if(m_fvgDetector != NULL) { delete m_fvgDetector; m_fvgDetector = NULL; }
    if(m_liquiditySweep != NULL) { delete m_liquiditySweep; m_liquiditySweep = NULL; }
    if(m_premiumDiscount != NULL) { delete m_premiumDiscount; m_premiumDiscount = NULL; }
    if(m_confluence != NULL) { delete m_confluence; m_confluence = NULL; }
    if(m_drawer != NULL) { delete m_drawer; m_drawer = NULL; }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategySMC::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;

    // Initialize Market Structure Engine
    m_marketStructure = new CSMCMarketStructure();
    if(m_marketStructure == NULL || !m_marketStructure.Initialize(symbol, timeframe))
    {
        Print("[SMC v2.0] Failed to initialize Market Structure");
        return false;
    }

    // Initialize Kill Zones
    m_killZones = new CICTKillZones();
    if(m_killZones == NULL || !m_killZones.Initialize(2))
    {
        Print("[SMC v2.0] Failed to initialize Kill Zones");
        return false;
    }

    // Initialize Order Blocks Detector
    m_orderBlocks = new CSMCOrderBlocks();
    if(m_orderBlocks == NULL || !m_orderBlocks.Initialize(symbol, timeframe))
    {
        Print("[SMC v2.0] Failed to initialize Order Blocks");
        return false;
    }

    // Initialize FVG Detector
    m_fvgDetector = new CSMCFairValueGap();
    if(m_fvgDetector == NULL || !m_fvgDetector.Initialize(symbol, timeframe))
    {
        Print("[SMC v2.0] Failed to initialize FVG Detector");
        return false;
    }

    // Initialize Liquidity Sweep Detector
    m_liquiditySweep = new CSMCLiquiditySweep();
    if(m_liquiditySweep == NULL || !m_liquiditySweep.Initialize(symbol, timeframe))
    {
        Print("[SMC v2.0] Failed to initialize Liquidity Sweep");
        return false;
    }

    // Initialize Premium/Discount Calculator
    m_premiumDiscount = new CSMCPremiumDiscount();
    if(m_premiumDiscount == NULL || !m_premiumDiscount.Initialize(symbol, timeframe))
    {
        Print("[SMC v2.0] Failed to initialize Premium/Discount");
        return false;
    }

    // Initialize Confluence Engine
    m_confluence = new CSMCConfluenceEngine();
    if(m_confluence == NULL || !m_confluence.Initialize(symbol, timeframe))
    {
        Print("[SMC v2.0] Failed to initialize Confluence Engine");
        return false;
    }

    // Initialize Visualization
    m_drawer = new CChartDrawingManager();
    if(m_drawer != NULL)
    {
        SDrawingConfig config;
        config.enableDrawing = true;
        config.enableOrderBlocks = true;
        config.enableFVG = true;
        config.enableSupplyDemand = true;
        m_drawer.SetConfiguration(config);
        m_drawer.Initialize(symbol, timeframe, "SMC");
    }

    PrintFormat("[SMC v2.0] Strategy initialized for %s on %s", symbol, EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategySMC::Deinit()
{
    ObjectsDeleteAll(0, "SMC_");
    Cleanup();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| OnTick Processing                                                |
//+------------------------------------------------------------------+
void CStrategySMC::OnTick()
{
    if(!m_is_enabled) return;
}

//+------------------------------------------------------------------+
//| OnNewBar Processing                                              |
//+------------------------------------------------------------------+
void CStrategySMC::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol != m_symbol || timeframe != m_timeframe)
        return;

    int currentBar = iBars(m_symbol, m_timeframe);
    if(currentBar == m_lastBarProcessed)
        return;
    m_lastBarProcessed = currentBar;

    // Update all components on new bar
    if(m_marketStructure != NULL) m_marketStructure.DetectSwingPoints(100);
    if(m_orderBlocks != NULL) m_orderBlocks.UpdateOrderBlocks();
    if(m_fvgDetector != NULL) m_fvgDetector.UpdateFVGs();
    if(m_liquiditySweep != NULL) m_liquiditySweep.UpdateSweeps();
    if(m_premiumDiscount != NULL) m_premiumDiscount.Update();

    // Draw SMC elements
    DrawSMCElements();
}

//+------------------------------------------------------------------+
//| Draw SMC Elements on Chart                                       |
//+------------------------------------------------------------------+
void CStrategySMC::DrawSMCElements()
{
    if(m_drawer == NULL) return;

    // Draw Order Blocks
    if(m_orderBlocks != NULL)
    {
        int obCount = m_orderBlocks.GetOrderBlockCount();
        for(int i = 0; i < obCount; i++)
        {
            SOrderBlock ob;
            if(m_orderBlocks.GetOrderBlockAt(i, ob) && !ob.mitigated)
            {
                m_drawer.DrawOrderBlock(ob.time, TimeCurrent(),
                    ob.top, ob.bottom, ob.isBullish, ob.score / 100.0,
                    StringFormat("SMC_OB_%d", i));
            }
        }
    }

    // Draw FVGs
    if(m_fvgDetector != NULL)
    {
        int fvgCount = m_fvgDetector.GetFVGCount();
        for(int i = 0; i < fvgCount; i++)
        {
            SFairValueGap fvg;
            if(m_fvgDetector.GetFVGAt(i, fvg) && !fvg.mitigated)
            {
                m_drawer.DrawFVG(fvg.time, TimeCurrent(),
                    fvg.top, fvg.bottom, fvg.isBullish, true,
                    StringFormat("SMC_FVG_%d", i));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get Signal - Full ICT Confluence                                 |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategySMC::GetSignal(double &confidence)
{
    confidence = 0.0;

    if(!m_is_enabled)
        return TRADE_SIGNAL_NONE;

    if(m_confluence == NULL)
        return TRADE_SIGNAL_NONE;

    // Update all components
    if(m_marketStructure != NULL) m_marketStructure.DetectSwingPoints(100);
    if(m_orderBlocks != NULL) m_orderBlocks.UpdateOrderBlocks();
    if(m_fvgDetector != NULL) m_fvgDetector.UpdateFVGs();
    if(m_liquiditySweep != NULL) m_liquiditySweep.UpdateSweeps();
    if(m_premiumDiscount != NULL) m_premiumDiscount.Update();

    // Check Kill Zone requirement
    if(m_requireKillZone && m_killZones != NULL)
    {
        if(!m_killZones.IsInKillZone())
            return TRADE_SIGNAL_NONE;
    }

    // Update confluence engine
    m_confluence.UpdateAll();

    // Get both bullish and bearish confluence
    SSMCConfluenceResult bullishResult = m_confluence.CalculateBullishConfluence();
    SSMCConfluenceResult bearishResult = m_confluence.CalculateBearishConfluence();

    // Determine which signal is stronger
    SSMCConfluenceResult signal;
    ENUM_TRADE_SIGNAL result = TRADE_SIGNAL_NONE;

    if(bullishResult.totalScore > bearishResult.totalScore && bullishResult.totalScore >= m_minConfluenceScore)
    {
        signal = bullishResult;
        result = TRADE_SIGNAL_BUY;
    }
    else if(bearishResult.totalScore > bullishResult.totalScore && bearishResult.totalScore >= m_minConfluenceScore)
    {
        signal = bearishResult;
        result = TRADE_SIGNAL_SELL;
    }
    else
    {
        return TRADE_SIGNAL_NONE;
    }

    // Check OTE requirement
    double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    bool inOteZone = false;
    if(m_premiumDiscount != NULL)
    {
        if(result == TRADE_SIGNAL_BUY)
            inOteZone = m_premiumDiscount.IsInBullishOTE(bid);
        else if(result == TRADE_SIGNAL_SELL)
            inOteZone = m_premiumDiscount.IsInBearishOTE(bid);
    }

    if(m_requireOTE && !inOteZone)
        return TRADE_SIGNAL_NONE;

    // Convert score to confidence (0-1 range)
    confidence = MathMin(1.0, signal.totalScore / 100.0);

    // Apply Kill Zone bonus
    if(m_killZones != NULL && m_killZones.IsInKillZone())
    {
        confidence = MathMin(1.0, confidence * 1.1);
        m_tradesInKillZone++;
    }

    // Apply OTE bonus
    if(inOteZone)
    {
        confidence = MathMin(1.0, confidence * 1.08);
        m_tradesInOTE++;
    }

    // Minimum confidence filter
    if(confidence < m_minConfidence)
        return TRADE_SIGNAL_NONE;

    if(result != TRADE_SIGNAL_NONE)
    {
        m_signalsGenerated++;

        // Get market structure info
        string structureInfo = "";
        if(m_marketStructure != NULL)
        {
            ENUM_SMC_TREND_DIRECTION trend = m_marketStructure.GetTrend();
            structureInfo = (trend == SMC_TREND_BULLISH) ? "Bullish" :
                           (trend == SMC_TREND_BEARISH) ? "Bearish" : "Neutral";
        }

        // Get kill zone info
        string kzInfo = "";
        if(m_killZones != NULL && m_killZones.IsInKillZone())
        {
            kzInfo = " | KZ: " + m_killZones.GetKillZoneName();
        }

        // Get premium/discount info
        string pdInfo = "";
        if(m_premiumDiscount != NULL)
        {
            if(m_premiumDiscount.IsPremium(bid))
                pdInfo = " | Premium Zone";
            else if(m_premiumDiscount.IsDiscount(bid))
                pdInfo = " | Discount Zone";
            if(inOteZone)
                pdInfo += " (OTE)";
        }

        PrintFormat("[SMC v2.0] %s: %s | Conf: %.1f%% | Score: %.0f | %s%s%s",
                   m_symbol,
                   result == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   confidence * 100,
                   signal.totalScore,
                   structureInfo,
                   kzInfo,
                   pdInfo);
    }

    return result;
}
