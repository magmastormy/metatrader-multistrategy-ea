//+------------------------------------------------------------------+
//| StrategyUnifiedICT.mqh                                           |
//| Unified ICT Trading Strategy v1.0                                |
//| Combines Market Structure, Order Blocks, Supply/Demand,          |
//| Liquidity, Imbalance, and Institutional Order Flow               |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __STRATEGY_UNIFIED_ICT_MQH__
#define __STRATEGY_UNIFIED_ICT_MQH__

#include "../Core/Strategy/StrategyBase.mqh"

// Unified ICT Component Files
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"
#include "UnifiedICTFiles/AdvancedOrderBlocks.mqh"
#include "UnifiedICTFiles/LiquidityDetector.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

// Reuse ICT-specific confluence components
#include "SMCFiles/KillZones.mqh"
#include "SMCFiles/PremiumDiscount.mqh"

// Chart Visualization
#include "../Core/Visualization/ChartDrawingManager.mqh"

// P1-C, P2-A, P2-B: New ICT Modules
#include "UnifiedICTFiles/CICTPositionSizer.mqh"
#include "UnifiedICTFiles/SessionGapDetector.mqh"
#include "UnifiedICTFiles/AMDDetector.mqh"

//+------------------------------------------------------------------+
//| Entry Type Enum                                                  |
//+------------------------------------------------------------------+
enum ENUM_ICT_ENTRY_TYPE
{
    ICT_ENTRY_NONE = 0,
    ICT_ENTRY_RISK,
    ICT_ENTRY_JUSTIFICATION,
    ICT_ENTRY_RISK_WITH_JUST,
    ICT_ENTRY_FULL_JUSTIFICATION
};

//+------------------------------------------------------------------+
//| ICT Entry Setup Structure                                        |
//+------------------------------------------------------------------+
struct SICTEntrySetup
{
    ENUM_ICT_ENTRY_TYPE entryType;
    
    double aoiTop;
    double aoiBottom;
    double aoiMidpoint;
    
    ENUM_TIMEFRAMES htf;
    ENUM_TIMEFRAMES ltf;
    
    bool htfBMS;
    bool ltfBMS;
    bool htfTrendConfirmed;
    bool ltfTrendConfirmed;
    
    double entryPrice;
    double stopLoss;
    double takeProfit1;
    double takeProfit2;
    double takeProfit3;
    double riskReward;
    double confluenceScore;   // P3-A: 0-130 weighted score

    int confluenceCount;
    double confidence;
    string reason;

    // P1-B: CE-based entry tracking
    double ceLevelEntry;     // OB CE used for precision entry refinement
    double ceLevelTP1;       // Opposing FVG CE used as TP1 target

    // P1-D: Partial position management
    double lot1Pct;          // % of total position to close at TP1 (e.g., 0.50)
    double lot2Pct;          // % to close at TP2 (e.g., 0.30)
    double lot3Pct;          // % to run to TP3 (e.g., 0.20)
    double breakevenPrice;   // SL moves here after TP1 is hit

    SICTEntrySetup() : entryType(ICT_ENTRY_NONE), aoiTop(0), aoiBottom(0), aoiMidpoint(0),
                      htf(PERIOD_H4), ltf(PERIOD_M15), htfBMS(false), ltfBMS(false),
                      htfTrendConfirmed(false), ltfTrendConfirmed(false), entryPrice(0),
                      stopLoss(0), takeProfit1(0), takeProfit2(0), takeProfit3(0),
                      riskReward(0), confluenceScore(0), confluenceCount(0),
                      confidence(0), reason(""),
                      ceLevelEntry(0), ceLevelTP1(0),
                      lot1Pct(0.50), lot2Pct(0.30), lot3Pct(0.20),
                      breakevenPrice(0) {}
};

//+------------------------------------------------------------------+
//| Unified ICT Strategy Class                                       |
//+------------------------------------------------------------------+
class CStrategyUnifiedICT : public CStrategyBase
{
private:
    // Core Components
    CMarketStructureAnalyzer*   m_structureAnalyzer;
    CAdvancedOrderBlockDetector* m_obDetector;
    CLiquidityDetector*         m_liquidityDetector;
    CImbalanceDetector*         m_imbalanceDetector;
    CICTKillZones*              m_killZones;
    CSMCPremiumDiscount*        m_premiumDiscount;
    CChartDrawingManager*       m_drawingManager;

    // P1-C, P2-A, P2-B: New ICT Modules
    CICTPositionSizer*          m_ictPositionSizer;
    CSessionGapDetector*        m_gapDetector;
    CAMDDetector*               m_amdDetector;
    
    // Configuration
    double                      m_minConfluenceScore;
    int                         m_minConfluences;
    bool                        m_requireKillZone;
    bool                        m_requireOTE;
    bool                        m_allowCounterTrendScout;
    int                         m_lastBarProcessed;
    
    // Statistics
    int                         m_signalsGenerated;
    int                         m_obsDetected;
    int                         m_liquiditySweeps;
    int                         m_tradesInKillZone;
    string                      m_lastFilterLogMessage;
    datetime                    m_lastFilterLogTime;
    string                      m_drawPrefix;
    bool                        m_drawOnChartSymbolOnly;
    datetime                    m_lastDrawLogTime;
    datetime                    m_lastDrawRecoveryCheck;
    
public:
                                CStrategyUnifiedICT(const string name = "Unified ICT v1.0", int magic = 0);
    virtual                    ~CStrategyUnifiedICT();
    
    virtual bool                Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void                Deinit() override;
    virtual void                OnTick() override;
    virtual void                OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual ENUM_TRADE_SIGNAL   GetSignal(double &confidence) override;
    virtual string              GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE  GetType() const override { return STRATEGY_UNIFIED_ICT; }
    
    // Configuration
    void                        SetMinConfidence(double conf) { m_minConfidence = conf; }
    void                        SetMinConfluences(int count) { m_minConfluences = count; }
    void                        SetRequireKillZone(bool req) { m_requireKillZone = req; }
    void                        SetRequireOTE(bool req) { m_requireOTE = req; }
    void                        SetAllowCounterTrendScout(bool allow) { m_allowCounterTrendScout = allow; }
    
private:
    void                        Cleanup();
    void                        LogFilterEvent(const string message);
    ENUM_TRADE_SIGNAL           RejectSignal(const string reasonTag, const string filterMessage = "");
    void                        DrawElements();
    bool                        RefreshComponentsForCurrentBar();
    
    // Entry System
    SICTEntrySetup              CreateRiskEntry();
    SICTEntrySetup              CreateJustificationEntry();
    SICTEntrySetup              CreateRiskWithJustEntry();
    SICTEntrySetup              CreateFullJustificationEntry();
    
    // Confluence — P3-A weighted scoring
    double                      ScoreConfluences(double price, bool bullish);   // Returns 0-130 weighted score
    int                         CountConfluences(double price, bool bullish);   // Wrappper: score/15 approx
    bool                        HasOrderBlockConfluence(double price, bool bullish);
    bool                        HasLiquidityConfluence(double price);
    bool                        HasImbalanceConfluence(double price, bool bullish);
    bool                        HasPremiumDiscountConfluence(double price, bool bullish);
    bool                        HasGapConfluence(double price);                 // P2-A: NDOG/NWOG
    bool                        HasAMDPhaseConfluence(bool bullish);            // P2-B: AMD

    // P3-B: Dynamic confidence
    double                      ComputeEntryConfidence(const SICTEntrySetup &entry, bool bullish);
    
    // Validation
    bool                        IsAtInstitutionalLevel(double price);
    bool                        ValidateMarketMakerSetup(SICTEntrySetup &entry);
    bool                        IsPriceAtMajorPOI(double price);  // Anchor-based validation
    bool                        IsCounterTrendScoutValid(bool signalIsBullish);  // Counter-trend reversal check
    bool                        ValidatePriceRejection(ENUM_TRADE_SIGNAL signal); // Candle confirmation
    bool                        ResolveDirectionalBias(bool &bullish) const;
    string                      BuildDrawPrefix(const string symbol, const ENUM_TIMEFRAMES timeframe) const;
    
    // Trade Management
    double                      CalculateStopLoss(SICTEntrySetup &entry, ENUM_TRADE_SIGNAL signal);
    void                        CalculateTakeProfits(SICTEntrySetup &entry, ENUM_TRADE_SIGNAL signal);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyUnifiedICT::CStrategyUnifiedICT(const string name, int magic) :
    CStrategyBase(name, magic),
    m_structureAnalyzer(NULL),
    m_obDetector(NULL),
    m_liquidityDetector(NULL),
    m_imbalanceDetector(NULL),
    m_killZones(NULL),
    m_premiumDiscount(NULL),
    m_drawingManager(NULL),
    m_ictPositionSizer(NULL),
    m_gapDetector(NULL),
    m_amdDetector(NULL),
    m_minConfluenceScore(45.0),
    m_minConfluences(4),
    m_requireKillZone(false),
    m_requireOTE(false),
    m_allowCounterTrendScout(true),
    m_lastBarProcessed(0),
    m_signalsGenerated(0),
    m_obsDetected(0),
    m_liquiditySweeps(0),
    m_tradesInKillZone(0),
    m_lastFilterLogMessage(""),
    m_lastFilterLogTime(0),
    m_drawPrefix(""),
    m_drawOnChartSymbolOnly(false),
    m_lastDrawLogTime(0),
    m_lastDrawRecoveryCheck(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyUnifiedICT::~CStrategyUnifiedICT()
{
    Cleanup();
    if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; }
    Print("[UICT] Strategy deinitialized");
}

//+------------------------------------------------------------------+
//| Cleanup                                                          |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::Cleanup()
{
    if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
    if(m_obDetector != NULL) { delete m_obDetector; m_obDetector = NULL; }
    if(m_liquidityDetector != NULL) { delete m_liquidityDetector; m_liquidityDetector = NULL; }
    if(m_imbalanceDetector != NULL) { delete m_imbalanceDetector; m_imbalanceDetector = NULL; }
    if(m_killZones != NULL) { delete m_killZones; m_killZones = NULL; }
    if(m_premiumDiscount != NULL) { delete m_premiumDiscount; m_premiumDiscount = NULL; }
    if(m_ictPositionSizer != NULL) { delete m_ictPositionSizer; m_ictPositionSizer = NULL; }
    if(m_gapDetector != NULL)   { delete m_gapDetector;   m_gapDetector   = NULL; }
    if(m_amdDetector != NULL)   { delete m_amdDetector;   m_amdDetector   = NULL; }
}

string CStrategyUnifiedICT::BuildDrawPrefix(const string symbol, const ENUM_TIMEFRAMES timeframe) const
{
    string safeSymbol = symbol;
    StringReplace(safeSymbol, ".", "_");
    StringReplace(safeSymbol, " ", "_");
    StringReplace(safeSymbol, "/", "_");
    StringReplace(safeSymbol, "-", "_");
    return StringFormat("UICT_%s_%d_", safeSymbol, (int)timeframe);
}

bool CStrategyUnifiedICT::ResolveDirectionalBias(bool &bullish) const
{
    bullish = false;
    if(m_structureAnalyzer == NULL)
        return false;

    bool isBullish = m_structureAnalyzer.IsBullish();
    bool isBearish = m_structureAnalyzer.IsBearish();

    // Reject ambiguous/neutral states to avoid forcing bearish defaults.
    if(isBullish == isBearish)
        return false;

    bullish = isBullish;
    return true;
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;

    m_drawPrefix = BuildDrawPrefix(symbol, timeframe);
    m_drawOnChartSymbolOnly = (symbol == _Symbol && timeframe == (ENUM_TIMEFRAMES)Period());
    
    // Initialize Market Structure Analyzer
    m_structureAnalyzer = new CMarketStructureAnalyzer();
    if(m_structureAnalyzer == NULL || !m_structureAnalyzer.Initialize(symbol, timeframe, 3))
    {
        Print("[UICT v1.0] Failed to initialize Market Structure Analyzer");
        return false;
    }
    
    // Initialize Order Block Detector
    m_obDetector = new CAdvancedOrderBlockDetector();
    if(m_obDetector == NULL || !m_obDetector.Initialize(symbol, timeframe))
    {
        Print("[UICT v1.0] Failed to initialize Order Block Detector");
        return false;
    }
    
    // Initialize Liquidity Detector
    m_liquidityDetector = new CLiquidityDetector();
    if(m_liquidityDetector == NULL || !m_liquidityDetector.Initialize(symbol, timeframe, 5))
    {
        Print("[UICT v1.0] Failed to initialize Liquidity Detector");
        return false;
    }
    
    // Initialize Imbalance Detector
    m_imbalanceDetector = new CImbalanceDetector();
    if(m_imbalanceDetector == NULL || !m_imbalanceDetector.Initialize(symbol, timeframe))
    {
        Print("[UICT v1.0] Failed to initialize Imbalance Detector");
        return false;
    }
    
    // Initialize Kill Zones
    m_killZones = new CICTKillZones();
    if(m_killZones == NULL || !m_killZones.Initialize(2))
    {
        Print("[UICT v1.0] Failed to initialize Kill Zones");
        return false;
    }
    
    // Initialize Premium/Discount
    m_premiumDiscount = new CSMCPremiumDiscount();
    if(m_premiumDiscount != NULL)
        m_premiumDiscount.Initialize(symbol, timeframe);

    // P1-C: ICT Position Sizer
    m_ictPositionSizer = new CICTPositionSizer();
    if(m_ictPositionSizer != NULL)
        m_ictPositionSizer.Initialize(symbol, 1.0, 3.0, 6.0, 100.0);

    // P2-A: Session Gap Detector
    m_gapDetector = new CSessionGapDetector();
    if(m_gapDetector != NULL)
        m_gapDetector.Initialize(symbol, PERIOD_D1);

    // P2-B: AMD Phase Detector
    m_amdDetector = new CAMDDetector();
    if(m_amdDetector != NULL)
        m_amdDetector.Initialize(symbol, timeframe, 2);

    // Chart Drawing Manager - initialized but drawing done in DrawElements
    m_drawingManager = new CChartDrawingManager();
    if(m_drawingManager != NULL)
    {
        m_drawingManager.Initialize(symbol, timeframe, "UICT");
        m_drawPrefix = m_drawingManager.GetPrefix();
        Print("[UICT] Chart drawing manager ready | Symbol=", symbol,
              " | DrawOnChart=", m_drawOnChartSymbolOnly ? "true" : "false");
    }
    
    m_lastBarProcessed = 0;

    if(m_drawOnChartSymbolOnly && RefreshComponentsForCurrentBar())
        DrawElements();
    
    Print("[UICT v1.0] Strategy initialized for ", symbol, " on ", EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::Deinit()
{
    if(StringLen(m_drawPrefix) > 0)
        ObjectsDeleteAll(0, m_drawPrefix);
    Cleanup();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::OnTick()
{
    if(!m_is_enabled)
        return;

    if(!m_drawOnChartSymbolOnly || StringLen(m_drawPrefix) == 0)
        return;

    datetime nowTime = TimeCurrent();
    if((nowTime - m_lastDrawRecoveryCheck) < 10)
        return;

    m_lastDrawRecoveryCheck = nowTime;

    bool hasActiveObjects = false;
    int totalObjects = ObjectsTotal(0, 0, -1);
    for(int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, 0, -1);
        if(StringFind(objName, m_drawPrefix) == 0)
        {
            hasActiveObjects = true;
            break;
        }
    }

    if(!hasActiveObjects && m_lastBarProcessed > 0)
    {
        DrawElements();
        Print("[UICT-DRAW] Recovered missing drawings for ", m_symbol);
    }
}

//+------------------------------------------------------------------+
//| OnNewBar                                                         |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol != m_symbol || timeframe != m_timeframe)
        return;
    
    if(RefreshComponentsForCurrentBar() && m_drawOnChartSymbolOnly)
        DrawElements();
}

void CStrategyUnifiedICT::LogFilterEvent(const string message)
{
    datetime nowTime = TimeCurrent();
    bool isFilterMessage = (StringFind(message, "[UICT] Filtered:") == 0);

    // Avoid flooding logs with repeated filter reasons during fast-tick periods.
    if(isFilterMessage && (nowTime - m_lastFilterLogTime) < 2)
        return;
    if(message == m_lastFilterLogMessage && (nowTime - m_lastFilterLogTime) <= 10)
        return;

    Print(message);
    m_lastFilterLogMessage = message;
    m_lastFilterLogTime = nowTime;
}

ENUM_TRADE_SIGNAL CStrategyUnifiedICT::RejectSignal(const string reasonTag, const string filterMessage)
{
    SetDecisionReasonTag(reasonTag);
    if(filterMessage != "")
        LogFilterEvent(filterMessage);
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Draw Elements                                                    |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::DrawElements()
{
    if(!m_drawOnChartSymbolOnly || StringLen(m_drawPrefix) == 0)
        return;

    CDrawingCoordinator* drawingCoordinator = GetDrawingCoordinator();
    if(drawingCoordinator != NULL)
        drawingCoordinator.PreparePrefixForCurrentBar(ChartID(), m_symbol, m_timeframe, m_drawPrefix);
    else if(StringLen(m_drawPrefix) > 0)
        ObjectsDeleteAll(0, m_drawPrefix);

    int totalOb = 0;
    int drawnOb = 0;
    int totalFvg = 0;
    int drawnFvg = 0;
    
    // Draw Order Blocks
    if(m_obDetector != NULL)
    {
        for(int i = 0; i < m_obDetector.GetOBCount(); i++)
        {
            SAdvancedOrderBlock ob;
            if(!m_obDetector.GetOrderBlock(i, ob)) continue;
            if(ob.isMitigated) continue;
            totalOb++;
            
            string name = StringFormat("%sOB_%d", m_drawPrefix, i);
            color obColor = (ob.type == OB_SOURCE_BULLISH || ob.type == OB_CONTINUATION_BULL || ob.type == OB_BREAKER_BULL) 
                           ? clrDodgerBlue : clrCrimson;
            
            if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
            
            ObjectCreate(0, name, OBJ_RECTANGLE, 0, ob.time, ob.top, TimeCurrent(), ob.bottom);
            ObjectSetInteger(0, name, OBJPROP_COLOR, obColor);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, false);
            ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("%s | Str: %.0f%%", EnumToString(ob.type), ob.strength * 100));
            drawnOb++;
        }
    }
    
    // Draw Imbalances
    if(m_imbalanceDetector != NULL)
    {
        for(int i = 0; i < m_imbalanceDetector.GetImbalanceCount(); i++)
        {
            SImbalance imb;
            if(!m_imbalanceDetector.GetImbalance(i, imb)) continue;
            if(imb.hasRebalanced) continue;
            totalFvg++;
            
            string name = StringFormat("%sFVG_%d", m_drawPrefix, i);
            color fvgColor = imb.isBullish ? clrGreen : clrRed;
            
            if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
            
            ObjectCreate(0, name, OBJ_RECTANGLE, 0, imb.time, imb.top, TimeCurrent(), imb.bottom);
            ObjectSetInteger(0, name, OBJPROP_COLOR, fvgColor);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, false);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
            drawnFvg++;
        }
    }

    ChartRedraw(0);

    datetime nowTime = TimeCurrent();
    if(nowTime - m_lastDrawLogTime >= 60)
    {
        PrintFormat("[UICT-DRAW] %s | OB: %d/%d | FVG: %d/%d | Prefix: %s",
                    m_symbol, drawnOb, totalOb, drawnFvg, totalFvg, m_drawPrefix);
        m_lastDrawLogTime = nowTime;
    }
}

//+------------------------------------------------------------------+
//| Get Signal                                                       |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyUnifiedICT::GetSignal(double &confidence)
{
    confidence = 0.0;
    SetDecisionReasonTag("UICT_UNSET");
    
    if(!m_is_enabled || !m_is_initialized)
        return RejectSignal("UICT_DISABLED_OR_UNINIT");
    
    // Ensure heavy component updates run once per bar across OnNewBar/GetSignal
    RefreshComponentsForCurrentBar();
    
    // Check Kill Zone requirement
    if(m_requireKillZone && m_killZones != NULL)
    {
        if(!m_killZones.IsInKillZone())
            return RejectSignal("UICT_KILLZONE_INACTIVE");
    }

    bool isBullish = false;
    if(!ResolveDirectionalBias(isBullish))
    {
        return RejectSignal("UICT_NEUTRAL_BIAS", "[UICT] Filtered: Ambiguous or neutral structure bias");
    }

    // Compact falsifiable event tuple:
    // 1) structure break, 2) displacement impulse, 3) mitigation/retest.
    ENUM_BMS_TYPE structureBreak = m_structureAnalyzer != NULL ? m_structureAnalyzer.DetectBMS() : BMS_NONE;
    bool hasStructureBreakEvent = (structureBreak != BMS_NONE);
    bool hasDisplacementEvent = false;
    if(m_imbalanceDetector != NULL)
        hasDisplacementEvent = (m_imbalanceDetector.GetImbalanceCount() > 0);

    bool hasMitigationRetestEvent = false;
    double eventReferencePrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    if(m_obDetector != NULL)
    {
        int bestObIdx = isBullish ? m_obDetector.FindBestBullishOB() : m_obDetector.FindBestBearishOB();
        if(bestObIdx >= 0)
        {
            SAdvancedOrderBlock eventOb;
            if(m_obDetector.GetOrderBlock(bestObIdx, eventOb))
            {
                eventReferencePrice = eventOb.midpoint;
                double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                if(point <= 0.0)
                    point = 0.00001;
                double atr = (m_structureAnalyzer != NULL) ? m_structureAnalyzer.GetATR(14) : 0.0;
                double tolerance = (atr > 0.0) ? (atr * 0.25) : (point * 25.0);
                hasMitigationRetestEvent = (MathAbs(SymbolInfoDouble(m_symbol, SYMBOL_BID) - eventOb.midpoint) <= tolerance);
            }
        }
    }

    if(!hasStructureBreakEvent)
        return RejectSignal("UICT_EVENT_NO_STRUCTURE_BREAK",
                            "[UICT] Filtered: Event tuple missing structure break");
    if(!(hasDisplacementEvent && hasMitigationRetestEvent))
        return RejectSignal("UICT_EVENT_TUPLE_INCOMPLETE",
                            StringFormat("[UICT] Filtered: Event tuple incomplete (disp=%s, retest=%s)",
                                         hasDisplacementEvent ? "true" : "false",
                                         hasMitigationRetestEvent ? "true" : "false"));
    
    // Get best entry setup
    SICTEntrySetup bestEntry;
    bestEntry.entryType = ICT_ENTRY_NONE;
    bestEntry.confidence = 0;
    
    // Try Full Justification entry first (highest probability)
    SICTEntrySetup fullJust = CreateFullJustificationEntry();
    if(fullJust.entryType != ICT_ENTRY_NONE && fullJust.confidence > bestEntry.confidence)
        bestEntry = fullJust;
    
    // Try Risk + Justification
    SICTEntrySetup riskJust = CreateRiskWithJustEntry();
    if(riskJust.entryType != ICT_ENTRY_NONE && riskJust.confidence > bestEntry.confidence)
        bestEntry = riskJust;
    
    // Try Justification entry
    SICTEntrySetup justEntry = CreateJustificationEntry();
    if(justEntry.entryType != ICT_ENTRY_NONE && justEntry.confidence > bestEntry.confidence)
        bestEntry = justEntry;
    
    // Try Risk entry
    SICTEntrySetup riskEntry = CreateRiskEntry();
    if(riskEntry.entryType != ICT_ENTRY_NONE && riskEntry.confidence > bestEntry.confidence)
        bestEntry = riskEntry;
    
    // Check if we have a valid entry
    if(bestEntry.entryType == ICT_ENTRY_NONE || bestEntry.confidence < m_minConfidence)
        return RejectSignal("UICT_NO_ENTRY_SETUP");

    // P3-A: Use weighted confluence score (0-130) as gate instead of raw count
    double currentPrice2 = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double gateScore = bestEntry.confluenceScore;  // set by entry creator via ScoreConfluences
    double gateScorePct = (gateScore / 130.0) * 100.0;  // normalise to %
    if(bestEntry.confluenceCount < m_minConfluences || gateScorePct < m_minConfluenceScore)
    {
        return RejectSignal("UICT_CONFLUENCE_GATE",
                            StringFormat("[UICT] Filtered: Confluence gate failed (cnt=%d, score=%.1f/130 = %.1f%%)",
                                         bestEntry.confluenceCount, gateScore, gateScorePct));
    }
    
    // Validate Market Maker setup
    if(!ValidateMarketMakerSetup(bestEntry))
        return RejectSignal("UICT_MARKET_MAKER_INVALID");
    
    // Determine signal direction from validated structure bias
    ENUM_TRADE_SIGNAL result = isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

    // ANCHOR-BASED REVERSAL: Require price to be at a major POI
    double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    if(!IsPriceAtMajorPOI(currentPrice))
    {
        return RejectSignal("UICT_NOT_AT_MAJOR_POI",
                            StringFormat("[UICT] Filtered: Price %.5f not at major POI", currentPrice));
    }

    // COUNTER-TREND SCOUT: Allow reversals targeting HTF zones
    bool htfAligned = m_structureAnalyzer.IsHTFAligned(isBullish);

    if(!htfAligned)
    {
        bool rangeRegime = (m_structureAnalyzer != NULL && !m_structureAnalyzer.IsTrendConfirmed());
        if(!rangeRegime)
        {
            return RejectSignal("UICT_COUNTERTREND_NON_RANGE",
                                "[UICT] Filtered: Counter-trend logic restricted to range regime");
        }

        if(!m_allowCounterTrendScout)
        {
            return RejectSignal("UICT_COUNTERTREND_BLOCKED_PRODUCTION",
                                "[UICT] Filtered: Counter-trend setup blocked (production mode)");
        }

        bool aggressiveCounterTrend = (bestEntry.entryType == ICT_ENTRY_RISK ||
                                       bestEntry.entryType == ICT_ENTRY_RISK_WITH_JUST);
        if(aggressiveCounterTrend)
        {
            return RejectSignal("UICT_COUNTERTREND_AGGRESSIVE_BLOCK",
                                "[UICT] Filtered: Counter-trend blocked for aggressive entry type");
        }

        int requiredCounterConfluence = (int)MathMax((double)(m_minConfluences + 1), 5.0);
        if(bestEntry.confluenceCount < requiredCounterConfluence)
        {
            return RejectSignal("UICT_COUNTERTREND_CONFLUENCE_LOW",
                                StringFormat("[UICT] Filtered: Counter-trend confluence too low (%d < %d)",
                                             bestEntry.confluenceCount, requiredCounterConfluence));
        }

        // Check if counter-trend is valid (targeting opposing HTF zone)
        if(!IsCounterTrendScoutValid(isBullish))
        {
            return RejectSignal("UICT_COUNTERTREND_INVALID_TARGET",
                                "[UICT] Filtered: No HTF alignment and no valid counter-trend target");
        }

        bool inKillZone = (m_killZones != NULL && m_killZones.IsInKillZone());
        if(!inKillZone)
        {
            return RejectSignal("UICT_COUNTERTREND_KILLZONE_REQUIRED",
                                "[UICT] Filtered: Counter-trend requires active kill-zone");
        }

        bool hasOteAlignment = false;
        if(m_premiumDiscount != NULL)
        {
            if(result == TRADE_SIGNAL_BUY)
                hasOteAlignment = m_premiumDiscount.IsInBullishOTE(currentPrice);
            else if(result == TRADE_SIGNAL_SELL)
                hasOteAlignment = m_premiumDiscount.IsInBearishOTE(currentPrice);
        }
        if(!hasOteAlignment)
        {
            return RejectSignal("UICT_COUNTERTREND_OTE_REQUIRED",
                                "[UICT] Filtered: Counter-trend requires OTE alignment");
        }

        // Counter-trend is valid, reduce confidence but allow signal
        bestEntry.confidence *= 0.75;
        bestEntry.reason += " (Counter-Trend Scout)";
    }
    
    // CANDLESTICK CONFIRMATION: Validate price rejection at POI
    if(!ValidatePriceRejection(result))
    {
        return RejectSignal("UICT_NO_REJECTION_CONFIRMATION",
                            "[UICT] Filtered: No candlestick rejection confirmation at POI");
    }
    
    double eventQuality = 0.40;
    if(hasStructureBreakEvent)
        eventQuality += 0.20;
    if(hasDisplacementEvent)
        eventQuality += 0.20;
    if(hasMitigationRetestEvent)
        eventQuality += 0.20;
    eventQuality += MathMin(0.15, ((double)bestEntry.confluenceCount / 10.0));
    eventQuality = MathMin(0.95, MathMax(0.0, eventQuality));

    confidence = MathMin(0.95, (bestEntry.confidence * 0.70) + (eventQuality * 0.30));
    
    // Kill zone is conditioning only; bounded additive contribution.
    double confidenceBonus = 0.0;
    if(m_killZones != NULL)
    {
        if(m_killZones.IsInKillZone())
        {
            confidenceBonus += 0.03;
            m_tradesInKillZone++;
        }
    }
    
    // OTE is conditioning only; bounded additive contribution.
    if(m_premiumDiscount != NULL)
    {
        double currentBid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if((result == TRADE_SIGNAL_BUY && m_premiumDiscount.IsInBullishOTE(currentBid)) ||
           (result == TRADE_SIGNAL_SELL && m_premiumDiscount.IsInBearishOTE(currentBid)))
        {
            confidenceBonus += 0.04;
        }
    }
    confidence = MathMin(0.95, confidence + confidenceBonus);
    
    if(result != TRADE_SIGNAL_NONE)
    {
        m_signalsGenerated++;
        RecordSignal();
        SetDecisionReasonTag(result == TRADE_SIGNAL_BUY ? "UICT_SIGNAL_BUY" : "UICT_SIGNAL_SELL");
        
        PrintFormat("[UICT-EVENT] %s | structure_break=%s | displacement=%s | mitigation=%s | ref=%.5f | event_quality=%.2f",
                   m_symbol,
                   hasStructureBreakEvent ? "true" : "false",
                   hasDisplacementEvent ? "true" : "false",
                   hasMitigationRetestEvent ? "true" : "false",
                   eventReferencePrice,
                   eventQuality);
        PrintFormat("[UICT v1.0] %s: %s | Entry: %s | Conf: %.1f%% | Confluences: %d | EventQ: %.2f | %s",
                   m_symbol,
                   result == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   EnumToString(bestEntry.entryType),
                   confidence * 100,
                   bestEntry.confluenceCount,
                   eventQuality,
                   bestEntry.reason);
    }
    
    return result;
}

bool CStrategyUnifiedICT::RefreshComponentsForCurrentBar()
{
    int currentBar = iBars(m_symbol, m_timeframe);
    if(currentBar <= 0)
        return false;

    if(currentBar == m_lastBarProcessed)
        return false;

    m_lastBarProcessed = currentBar;

    if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
    if(m_obDetector != NULL) m_obDetector.Update();
    if(m_liquidityDetector != NULL) m_liquidityDetector.Update();
    if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
    if(m_premiumDiscount != NULL) m_premiumDiscount.Update();
    if(m_gapDetector != NULL)  m_gapDetector.Update();
    if(m_amdDetector != NULL)  m_amdDetector.Update();
    if(m_ictPositionSizer != NULL) m_ictPositionSizer.Update();

    // P0-C: Pass current swing anchor to PremiumDiscount for accurate OTE
    if(m_structureAnalyzer != NULL && m_premiumDiscount != NULL)
    {
        SStructuralPoint swingH, swingL;
        bool hasH = m_structureAnalyzer.GetLastSwingHigh(swingH);
        bool hasL = m_structureAnalyzer.GetLastSwingLow(swingL);
        if(hasH && hasL && swingH.price > swingL.price)
        {
            bool bullishLeg = (swingL.barIndex > swingH.barIndex); // low older = bullish leg up
            m_premiumDiscount.SetSwingAnchor(swingH.price, swingL.price, bullishLeg);
        }
    }

    if(m_obDetector != NULL)
        m_obsDetected = m_obDetector.GetOBCount();

    return true;
}

//+------------------------------------------------------------------+
//| Create Risk Entry                                                |
//+------------------------------------------------------------------+
SICTEntrySetup CStrategyUnifiedICT::CreateRiskEntry()
{
    SICTEntrySetup entry;
    
    if(m_structureAnalyzer == NULL || m_obDetector == NULL)
        return entry;
    
    bool bullish = false;
    if(!ResolveDirectionalBias(bullish))
        return entry;
    
    // Find active Order Block
    int obIdx = bullish ? m_obDetector.FindBestBullishOB() : m_obDetector.FindBestBearishOB();
    if(obIdx < 0) return entry;
    
    SAdvancedOrderBlock ob;
    if(!m_obDetector.GetOrderBlock(obIdx, ob)) return entry;

    // P3-A: Weighted confluence score
    double score = ScoreConfluences(ob.midpoint, bullish);
    int confluences = CountConfluences(ob.midpoint, bullish);
    if(confluences < m_minConfluences)
        return entry;
    
    // P1-B: Use OB CE as precision entry
    double entryPx = (ob.ce > 0) ? ob.ce : ob.midpoint;

    entry.entryType       = ICT_ENTRY_RISK;
    entry.aoiTop          = ob.top;
    entry.aoiBottom       = ob.bottom;
    entry.aoiMidpoint     = ob.midpoint;
    entry.ceLevelEntry    = ob.ce > 0 ? ob.ce : ob.midpoint;
    entry.entryPrice      = entryPx;
    entry.confluenceCount = confluences;
    entry.confluenceScore = score;
    entry.reason          = "Risk entry at OB CE";

    // P3-B: Dynamic confidence
    entry.confidence = ComputeEntryConfidence(entry, bullish);
    
    // Calculate SL/TP
    entry.stopLoss = CalculateStopLoss(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    CalculateTakeProfits(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    
    return entry;
}

//+------------------------------------------------------------------+
//| Create Justification Entry                                       |
//+------------------------------------------------------------------+
SICTEntrySetup CStrategyUnifiedICT::CreateJustificationEntry()
{
    SICTEntrySetup entry;
    
    if(m_structureAnalyzer == NULL || m_obDetector == NULL)
        return entry;
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    bool bullish = false;
    if(!ResolveDirectionalBias(bullish))
        return entry;
    
    // Find active Order Block
    int obIdx = bullish ? m_obDetector.FindBestBullishOB() : m_obDetector.FindBestBearishOB();
    if(obIdx < 0) return entry;
    
    SAdvancedOrderBlock ob;
    if(!m_obDetector.GetOrderBlock(obIdx, ob)) return entry;
    
    // Check if price is near AOI using ATR-based tolerance
    double atr = m_structureAnalyzer.GetATR(14);
    double tolerance = (atr > 0) ? atr * 0.2 : 15 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    if(MathAbs(price - ob.midpoint) > tolerance)
        return entry;
    
    // Check for BMS confirmation
    ENUM_BMS_TYPE bms = m_structureAnalyzer.DetectBMS();
    if(bms == BMS_NONE)
        return entry;

    double score = ScoreConfluences(price, bullish);
    int confluences = CountConfluences(price, bullish);

    entry.entryType       = ICT_ENTRY_JUSTIFICATION;
    entry.aoiTop          = ob.top;
    entry.aoiBottom       = ob.bottom;
    entry.aoiMidpoint     = ob.midpoint;
    entry.ceLevelEntry    = ob.ce > 0 ? ob.ce : ob.midpoint;
    entry.ltfBMS          = true;
    entry.entryPrice      = price;
    entry.confluenceCount = confluences;
    entry.confluenceScore = score;
    entry.reason          = "Justification entry with BMS confirmation";
    entry.confidence      = ComputeEntryConfidence(entry, bullish);
    
    entry.stopLoss = CalculateStopLoss(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    CalculateTakeProfits(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    
    return entry;
}

//+------------------------------------------------------------------+
//| Create Risk + Justification Entry                                |
//+------------------------------------------------------------------+
SICTEntrySetup CStrategyUnifiedICT::CreateRiskWithJustEntry()
{
    SICTEntrySetup entry;
    
    if(m_structureAnalyzer == NULL || m_obDetector == NULL)
        return entry;
    
    // Check for first BMS but trend not confirmed
    ENUM_BMS_TYPE bms = m_structureAnalyzer.DetectBMS();
    if(bms == BMS_NONE)
        return entry;
    
    if(m_structureAnalyzer.IsTrendConfirmed())
        return entry;
    
    bool bullish = false;
    if(!ResolveDirectionalBias(bullish))
        return entry;
    
    int obIdx = bullish ? m_obDetector.FindBestBullishOB() : m_obDetector.FindBestBearishOB();
    if(obIdx < 0) return entry;
    
    SAdvancedOrderBlock ob;
    if(!m_obDetector.GetOrderBlock(obIdx, ob)) return entry;

    double entryPx = (ob.ce > 0) ? ob.ce : ob.midpoint;
    double score   = ScoreConfluences(entryPx, bullish);
    int confluences = CountConfluences(entryPx, bullish);

    entry.entryType       = ICT_ENTRY_RISK_WITH_JUST;
    entry.htfBMS          = true;
    entry.htfTrendConfirmed = false;
    entry.aoiTop          = ob.top;
    entry.aoiBottom       = ob.bottom;
    entry.aoiMidpoint     = ob.midpoint;
    entry.ceLevelEntry    = ob.ce > 0 ? ob.ce : ob.midpoint;
    entry.entryPrice      = entryPx;
    entry.confluenceCount = confluences;
    entry.confluenceScore = score;
    entry.reason          = "Risk + Justification after first BMS";
    entry.confidence      = ComputeEntryConfidence(entry, bullish);
    
    entry.stopLoss = CalculateStopLoss(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    CalculateTakeProfits(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    
    return entry;
}

//+------------------------------------------------------------------+
//| Create Full Justification Entry                                  |
//+------------------------------------------------------------------+
SICTEntrySetup CStrategyUnifiedICT::CreateFullJustificationEntry()
{
    SICTEntrySetup entry;
    
    if(m_structureAnalyzer == NULL || m_obDetector == NULL)
        return entry;
    
    // HTF trend must be confirmed (2+ BMS)
    if(!m_structureAnalyzer.IsTrendConfirmed())
        return entry;
    
    if(m_structureAnalyzer.GetConsecutiveBMS() < 2)
        return entry;
    
    bool bullish = false;
    if(!ResolveDirectionalBias(bullish))
        return entry;
    
    int obIdx = bullish ? m_obDetector.FindBestBullishOB() : m_obDetector.FindBestBearishOB();
    if(obIdx < 0) return entry;
    
    SAdvancedOrderBlock ob;
    if(!m_obDetector.GetOrderBlock(obIdx, ob)) return entry;
    
    // Check for LTF BMS
    ENUM_BMS_TYPE ltfBMS = m_structureAnalyzer.DetectBMS();

    double entryPx     = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double score       = ScoreConfluences(entryPx, bullish);
    int    confluences = CountConfluences(entryPx, bullish);

    entry.entryType         = ICT_ENTRY_FULL_JUSTIFICATION;
    entry.htfTrendConfirmed = true;
    entry.ltfBMS            = (ltfBMS != BMS_NONE);
    entry.aoiTop            = ob.top;
    entry.aoiBottom         = ob.bottom;
    entry.aoiMidpoint       = ob.midpoint;
    entry.ceLevelEntry      = ob.ce > 0 ? ob.ce : ob.midpoint;
    entry.entryPrice        = entryPx;
    entry.confluenceCount   = confluences;
    entry.confluenceScore   = score;
    entry.reason            = "Full Justification - HTF trend confirmed";

    // P3-B: Dynamic confidence
    entry.confidence = ComputeEntryConfidence(entry, bullish);
    
    entry.stopLoss = CalculateStopLoss(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    CalculateTakeProfits(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    
    return entry;
}

//+------------------------------------------------------------------+
//| Score Confluences — P3-A Weighted Scoring                        |
//+------------------------------------------------------------------+
// Max possible score = 30+20+20+15+15+10+10+10 = 130 points
double CStrategyUnifiedICT::ScoreConfluences(double price, bool bullish)
{
    double score = 0;

    // 1. Order Block at price — 30 pts (ICT primary entry vehicle)
    if(HasOrderBlockConfluence(price, bullish))
        score += 30.0;

    // 2. FVG/Imbalance at price — 20 pts (displacement evidence)
    if(HasImbalanceConfluence(price, bullish))
        score += 20.0;

    // 3. Liquidity sweep confirmed — 20 pts (market maker pattern)
    if(HasLiquidityConfluence(price))
        score += 20.0;

    // 4. OTE zone — 15 pts (Fibonacci entry precision)
    if(m_premiumDiscount != NULL)
    {
        if(bullish && m_premiumDiscount.IsInBullishOTE(price))  score += 15.0;
        if(!bullish && m_premiumDiscount.IsInBearishOTE(price)) score += 15.0;
    }

    // 5. Kill Zone (or Silver Bullet) — 15 pts (time-based probability)
    if(m_killZones != NULL)
    {
        if(m_killZones.IsSilverBullet())    score += 15.0;  // Silver Bullet = max
        else if(m_killZones.IsInKillZone()) score += 10.0;  // Regular kill zone
    }

    // 6. Premium/Discount zone alignment — 10 pts
    if(HasPremiumDiscountConfluence(price, bullish))
        score += 10.0;

    // 7. NDOG/NWOG gap zone — 10 pts (P2-A)
    if(HasGapConfluence(price))
        score += 10.0;

    // 8. AMD phase alignment — 10 pts (P2-B)
    if(HasAMDPhaseConfluence(bullish))
        score += 10.0;

    return score;  // 0-130
}

//+------------------------------------------------------------------+
//| Count Confluences (count wrapper around ScoreConfluences)        |
//+------------------------------------------------------------------+
int CStrategyUnifiedICT::CountConfluences(double price, bool bullish)
{
    double score = ScoreConfluences(price, bullish);
    // Estimate count: each confluence averages ~16.25 pts, so /16 gives rough count
    int count = (int)MathFloor(score / 16.0);
    return MathMax(0, MathMin(count, 8));
}

//+------------------------------------------------------------------+
//| Has Gap Confluence — P2-A                                        |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::HasGapConfluence(double price)
{
    if(m_gapDetector == NULL) return false;
    return m_gapDetector.IsInAnyGap(price) || m_gapDetector.IsNearGapMidpoint(price, 0.15);
}

//+------------------------------------------------------------------+
//| Has AMD Phase Confluence — P2-B                                  |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::HasAMDPhaseConfluence(bool bullish)
{
    if(m_amdDetector == NULL) return false;
    if(!m_amdDetector.IsDistribution()) return false;
    if(bullish)  return m_amdDetector.IsSweepBullish();   // Fake down, true UP
    else         return m_amdDetector.IsSweepBearish();   // Fake up, true DOWN
}

//+------------------------------------------------------------------+
//| Compute Entry Confidence — P3-B Dynamic Confidence Model        |
//+------------------------------------------------------------------+
double CStrategyUnifiedICT::ComputeEntryConfidence(const SICTEntrySetup &entry, bool bullish)
{
    double conf = 0.35;  // Base

    // Structure break type bonus
    if(m_structureAnalyzer != NULL)
    {
        if(m_structureAnalyzer.WasLastBreakCHoCH())
            conf += 0.20;  // CHoCH = reversal signal = higher confidence for entries
        else if(m_structureAnalyzer.WasLastBreakBOS())
            conf += 0.12;  // BOS = continuation
    }

    // Confluence score contribution (max 0.25 from score)
    double scoreNorm = MathMin(1.0, entry.confluenceScore / 130.0);
    conf += scoreNorm * 0.25;

    // Entry type bonus
    switch(entry.entryType)
    {
        case ICT_ENTRY_FULL_JUSTIFICATION: conf += 0.10; break;
        case ICT_ENTRY_RISK_WITH_JUST:     conf += 0.06; break;
        case ICT_ENTRY_JUSTIFICATION:      conf += 0.04; break;
        default: break;
    }

    // Kill zone / Silver Bullet bonus
    if(m_killZones != NULL)
    {
        if(m_killZones.IsSilverBullet())    conf += 0.06;
        else if(m_killZones.IsInKillZone()) conf += 0.03;
    }

    // AMD Distribution phase bonus
    if(HasAMDPhaseConfluence(bullish)) conf += 0.05;

    // CHoCH with AMD sweep = highest-confidence ICT setup
    bool choch = (m_structureAnalyzer != NULL && m_structureAnalyzer.WasLastBreakCHoCH());
    bool amd   = HasAMDPhaseConfluence(bullish);
    if(choch && amd) conf += 0.05;  // Bonus for full AMD + CHoCH confirmation

    return MathMin(0.95, MathMax(0.0, conf));
}

//+------------------------------------------------------------------+
//| Has Order Block Confluence                                       |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::HasOrderBlockConfluence(double price, bool bullish)
{
    if(m_obDetector == NULL) return false;
    
    double tolerance = 20 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    int obIdx = m_obDetector.FindActiveOBAtPrice(price, tolerance);
    
    if(obIdx < 0) return false;
    
    SAdvancedOrderBlock ob;
    if(!m_obDetector.GetOrderBlock(obIdx, ob)) return false;
    
    if(bullish)
        return (ob.type == OB_SOURCE_BULLISH || ob.type == OB_CONTINUATION_BULL || ob.type == OB_BREAKER_BULL);
    else
        return (ob.type == OB_SOURCE_BEARISH || ob.type == OB_CONTINUATION_BEAR || ob.type == OB_BREAKER_BEAR);
}

//+------------------------------------------------------------------+
//| Has Liquidity Confluence                                         |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::HasLiquidityConfluence(double price)
{
    if(m_liquidityDetector == NULL) return false;
    
    bool isBuyside;
    if(!m_liquidityDetector.HasRecentSweep(isBuyside))
        return false;

    // Require price proximity to active liquidity to avoid distant, stale sweeps.
    return m_liquidityDetector.IsNearLiquidity(price, 30);
}

//+------------------------------------------------------------------+
//| Has Imbalance Confluence                                         |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::HasImbalanceConfluence(double price, bool bullish)
{
    if(m_imbalanceDetector == NULL) return false;
    
    int imbIdx = m_imbalanceDetector.FindActiveImbalanceAtPrice(price);
    if(imbIdx < 0) return false;
    
    SImbalance imb;
    if(!m_imbalanceDetector.GetImbalance(imbIdx, imb)) return false;
    
    return (imb.isBullish == bullish);
}

//+------------------------------------------------------------------+
//| Has Premium/Discount Confluence                                  |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::HasPremiumDiscountConfluence(double price, bool bullish)
{
    if(m_premiumDiscount == NULL) return false;
    
    if(bullish)
        return m_premiumDiscount.IsDiscount(price);
    else
        return m_premiumDiscount.IsPremium(price);
}

//+------------------------------------------------------------------+
//| Is At Institutional Level                                        |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::IsAtInstitutionalLevel(double price)
{
    // FIX: Scale-aware institutional level detection using Point and price units
    double roundLevel = 0;
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    // Calculate distance to nearest "round" level
    // Round levels are usually 500, 1000, 2000 points depending on instrument
    double step = (StringFind(m_symbol, "Volatility") >= 0) ? 10.0 : 0.0050; // Dynamic step
    
    // For Synthetic Indices like Volatility 75, we look at integer levels
    if(StringFind(m_symbol, "Volatility") >= 0)
    {
        double remainder = MathMod(price, 1000.0);
        if(remainder < 50.0 || remainder > 950.0) return true; // Triple zero
        if(MathAbs(remainder - 500.0) < 50.0) return true; // 500 level
    }
    else
    {
        // For Forex: 00, 50, 20, 80 levels
        int intPrice = (int)MathRound(price / point);
        int pips = intPrice % 100;
        if(pips == 0 || pips == 50 || pips == 20 || pips == 80) return true;
        
        // Check with small tolerance
        if(MathAbs(pips - 0) <= 2 || MathAbs(pips - 50) <= 2 || 
           MathAbs(pips - 20) <= 2 || MathAbs(pips - 80) <= 2) return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Validate Market Maker Setup                                      |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::ValidateMarketMakerSetup(SICTEntrySetup &entry)
{
    int validationScore = 0;
    
    // Check 1: At institutional level
    if(IsAtInstitutionalLevel(entry.entryPrice))
        validationScore += 2;
    
    // Check 2: Liquidity swept
    bool isBuyside;
    if(m_liquidityDetector != NULL && m_liquidityDetector.HasRecentSweep(isBuyside))
        validationScore += 3;
    
    // Check 3: Aligns with structure
    if(m_structureAnalyzer != NULL && m_structureAnalyzer.IsTrendConfirmed())
        validationScore += 3;
    
    // Check 4: Has Order Block
    if(HasOrderBlockConfluence(entry.entryPrice, m_structureAnalyzer.IsBullish()))
        validationScore += 2;
    
    // Need 5+ points for valid setup (relaxed from 7)
    return (validationScore >= 5);
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss                                              |
//+------------------------------------------------------------------+
double CStrategyUnifiedICT::CalculateStopLoss(SICTEntrySetup &entry, ENUM_TRADE_SIGNAL signal)
{
    double atr = m_structureAnalyzer.GetATR(14);
    double buffer = (atr > 0) ? atr * 0.1 : 5 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double defaultSl = (atr > 0) ? atr * 1.5 : 30 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double stopLoss = 0;
    
    if(signal == TRADE_SIGNAL_BUY)
    {
        if(entry.aoiBottom > 0)
            stopLoss = entry.aoiBottom - buffer;
        else
            stopLoss = entry.entryPrice - defaultSl;
    }
    else
    {
        if(entry.aoiTop > 0)
            stopLoss = entry.aoiTop + buffer;
        else
            stopLoss = entry.entryPrice + defaultSl;
    }
    
    return stopLoss;
}

//+------------------------------------------------------------------+
//| Calculate Take Profits — P3-C ICT TP Hierarchy                  |
//+------------------------------------------------------------------+
// TP Hierarchy (in priority order):
//   TP1 = Opposing FVG CE (consequent encroachment of next unfilled imbalance)
//   TP2 = Opposing OB CE  (midpoint of nearest opposing order block)
//   TP3 = Structural liquidity target (swing high/low or unswept liquidity pool)
//   Fallback: fixed RR if structural targets not found (2R / 3R / 5R)
void CStrategyUnifiedICT::CalculateTakeProfits(SICTEntrySetup &entry, ENUM_TRADE_SIGNAL signal)
{
    bool isBuy = (signal == TRADE_SIGNAL_BUY);
    double risk = MathAbs(entry.entryPrice - entry.stopLoss);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(risk <= 0) risk = point * 25;  // fallback guard

    // Fixed-RR fallback targets
    double target1 = isBuy ? entry.entryPrice + (risk * 2.0) : entry.entryPrice - (risk * 2.0);
    double target2 = isBuy ? entry.entryPrice + (risk * 3.0) : entry.entryPrice - (risk * 3.0);
    double target3 = isBuy ? entry.entryPrice + (risk * 5.0) : entry.entryPrice - (risk * 5.0);

    // --- TP1: Opposing FVG CE ---
    // For a BUY: find the nearest BEARISH unfilled FVG above entry price — target its CE
    // For a SELL: find the nearest BULLISH unfilled FVG below entry price — target its CE
    if(m_imbalanceDetector != NULL)
    {
        double bestFvgCE = 0;
        double bestFvgDist = DBL_MAX;

        for(int i = 0; i < m_imbalanceDetector.GetImbalanceCount(); i++)
        {
            SImbalance fvg;
            if(!m_imbalanceDetector.GetImbalance(i, fvg)) continue;
            if(fvg.hasRebalanced) continue;
            if(fvg.isInverse)     continue;  // Skip IFVGs for TP targeting

            bool isOpposing = (isBuy ? !fvg.isBullish : fvg.isBullish);
            if(!isOpposing) continue;

            // Must be on the correct side of entry
            bool correctSide = (isBuy ? fvg.ce > entry.entryPrice : fvg.ce < entry.entryPrice);
            if(!correctSide) continue;

            double dist = MathAbs(fvg.ce - entry.entryPrice);
            if(dist < bestFvgDist)
            {
                bestFvgDist = dist;
                bestFvgCE  = fvg.ce;
            }
        }

        if(bestFvgCE > 0)
        {
            double rrFvg = bestFvgDist / risk;
            if(rrFvg >= 1.2)  // Minimum 1.2:1 RR for TP1
            {
                target1 = bestFvgCE;
                entry.ceLevelTP1 = bestFvgCE;
                PrintFormat("[UICT-TP] TP1=FVG CE at %.5f (RR: %.2f)", bestFvgCE, rrFvg);
            }
        }
    }

    // --- TP2: Opposing OB CE ---
    if(m_obDetector != NULL)
    {
        double bestObCE   = 0;
        double bestObDist = DBL_MAX;

        for(int i = 0; i < m_obDetector.GetOBCount(); i++)
        {
            SAdvancedOrderBlock ob;
            if(!m_obDetector.GetOrderBlock(i, ob)) continue;
            if(ob.isMitigated) continue;

            bool isBullishOB = (ob.type == OB_SOURCE_BULLISH ||
                                ob.type == OB_CONTINUATION_BULL ||
                                ob.type == OB_BREAKER_BULL);
            bool isOpposing  = (isBuy ? !isBullishOB : isBullishOB);
            if(!isOpposing) continue;

            double obCE   = ob.ce > 0 ? ob.ce : ob.midpoint;
            bool correctSide = (isBuy ? obCE > entry.entryPrice : obCE < entry.entryPrice);
            if(!correctSide) continue;

            // TP2 OB must be BEYOND TP1 to preserve TP order
            if(isBuy  && obCE <= target1) continue;
            if(!isBuy && obCE >= target1) continue;

            double dist = MathAbs(obCE - entry.entryPrice);
            if(dist < bestObDist)
            {
                bestObDist = dist;
                bestObCE   = obCE;
            }
        }

        if(bestObCE > 0)
        {
            double rrOb = bestObDist / risk;
            if(rrOb >= 2.5)  // TP2 needs at least 2.5:1
            {
                target2 = bestObCE;
                PrintFormat("[UICT-TP] TP2=OB CE at %.5f (RR: %.2f)", bestObCE, rrOb);
            }
        }
    }

    // --- TP3: Structural Liquidity / Swing Extreme ---
    if(m_liquidityDetector != NULL)
    {
        int poolIdx = m_liquidityDetector.FindNearestLiquidity(entry.entryPrice, isBuy);
        if(poolIdx >= 0)
        {
            SLiquidityPool pool;
            if(m_liquidityDetector.GetPool(poolIdx, pool) && !pool.isSwept)
            {
                bool correctSide = (isBuy ? pool.price > entry.entryPrice : pool.price < entry.entryPrice);
                // TP3 must be beyond TP2
                bool beyondTP2   = (isBuy ? pool.price > target2 : pool.price < target2);
                double rrPool    = MathAbs(pool.price - entry.entryPrice) / risk;

                if(correctSide && beyondTP2 && rrPool >= 4.0)
                {
                    target3 = pool.price;
                    PrintFormat("[UICT-TP] TP3=Liquidity at %.5f (RR: %.2f)", pool.price, rrPool);
                }
            }
        }
    }

    // Ensure TP ordering is preserved (ascending for buy, descending for sell)
    if(isBuy)
    {
        if(target2 <= target1) target2 = target1 + (risk * 1.0);
        if(target3 <= target2) target3 = target2 + (risk * 2.0);
    }
    else
    {
        if(target2 >= target1) target2 = target1 - (risk * 1.0);
        if(target3 >= target2) target3 = target2 - (risk * 2.0);
    }

    entry.takeProfit1    = target1;
    entry.takeProfit2    = target2;
    entry.takeProfit3    = target3;
    entry.breakevenPrice = entry.entryPrice;  // P1-D: move SL to entry after TP1 is hit
    entry.riskReward     = MathAbs(target1 - entry.entryPrice) / MathMax(point, risk);

    // P1-D: Default partial close ratios (50% / 30% / 20%)
    entry.lot1Pct = 0.50;
    entry.lot2Pct = 0.30;
    entry.lot3Pct = 0.20;
}


//+------------------------------------------------------------------+
//| Check if Price is at a Major POI (Anchor-Based Validation)       |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::IsPriceAtMajorPOI(double price)
{
    double tolerance = 20 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    // Check Order Blocks
    if(m_obDetector != NULL)
    {
        int obIdx = m_obDetector.FindActiveOBAtPrice(price, tolerance);
        if(obIdx >= 0)
            return true;
    }
    
    // Check Liquidity Pools
    if(m_liquidityDetector != NULL)
    {
        if(m_liquidityDetector.IsNearLiquidity(price, 20))
            return true;
    }
    
    // Check Imbalances (FVGs)
    if(m_imbalanceDetector != NULL)
    {
        // Check if price is inside an active imbalance
        for(int i = 0; i < m_imbalanceDetector.GetImbalanceCount(); i++)
        {
            SImbalance imb;
            if(m_imbalanceDetector.GetImbalance(i, imb))
            {
                if(!imb.hasRebalanced && price >= imb.bottom && price <= imb.top)
                    return true;
            }
        }
    }
    
    // Check Premium/Discount zone
    if(m_premiumDiscount != NULL)
    {
        if(m_premiumDiscount.IsInBullishOTE(price) || m_premiumDiscount.IsInBearishOTE(price))
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Counter-Trend Scout is Valid                            |
//| Allows reversals when targeting an opposing HTF zone             |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::IsCounterTrendScoutValid(bool signalIsBullish)
{
    if(m_liquidityDetector == NULL)
        return false;
    
    double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // For bullish counter-trend (selling into buy zone):
    // Check if there's unswept sellside liquidity (target for shorts)
    if(!signalIsBullish)
    {
        // Looking for sellside liquidity below current price
        int targetPoolIdx = m_liquidityDetector.FindNearestLiquidity(currentPrice, false);
        if(targetPoolIdx >= 0)
        {
            SLiquidityPool pool;
            if(m_liquidityDetector.GetPool(targetPoolIdx, pool))
            {
                // Target must be unswept and significant
                if(!pool.isSwept && pool.strength >= 0.7)
                {
                    LogFilterEvent(StringFormat("[UICT] Counter-Trend Scout: Sellside target at %.5f (strength: %.2f)", 
                                               pool.price, pool.strength));
                    return true;
                }
            }
        }
    }
    else
    {
        // For bearish counter-trend (buying into sell zone):
        // Looking for buyside liquidity above current price
        int targetPoolIdx = m_liquidityDetector.FindNearestLiquidity(currentPrice, true);
        if(targetPoolIdx >= 0)
        {
            SLiquidityPool pool;
            if(m_liquidityDetector.GetPool(targetPoolIdx, pool))
            {
                if(!pool.isSwept && pool.strength >= 0.7)
                {
                    LogFilterEvent(StringFormat("[UICT] Counter-Trend Scout: Buyside target at %.5f (strength: %.2f)", 
                                               pool.price, pool.strength));
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Validate Price Rejection at POI (Candlestick Confirmation)      |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::ValidatePriceRejection(ENUM_TRADE_SIGNAL signal)
{
    // Need at least 2 bars for confirmation
    if(Bars(m_symbol, m_timeframe) < 5) return true;
    
    double open1 = iOpen(m_symbol, m_timeframe, 1);
    double close1 = iClose(m_symbol, m_timeframe, 1);
    double high1 = iHigh(m_symbol, m_timeframe, 1);
    double low1 = iLow(m_symbol, m_timeframe, 1);
    
    double body = MathAbs(close1 - open1);
    double range = high1 - low1;
    if(range <= 0) return false;
    
    if(signal == TRADE_SIGNAL_BUY)
    {
        // Bullish Rejection: Bullish Pin Bar or Bullish Engulfing or long lower wick
        bool isBullishPin = (close1 > open1) && ((open1 - low1) > body * 2.0);
        bool isBullishEngulfing = (close1 > open1) && (iClose(m_symbol, m_timeframe, 2) < iOpen(m_symbol, m_timeframe, 2)) && (close1 > iHigh(m_symbol, m_timeframe, 2));
        double lowerWick = (open1 > close1) ? open1 - low1 : close1 - low1;
        bool strongLowerWick = lowerWick > (range * 0.4); 
        
        return isBullishPin || isBullishEngulfing || strongLowerWick;
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        // Bearish Rejection: Bearish Pin Bar or Bearish Engulfing or long upper wick
        bool isBearishPin = (close1 < open1) && ((high1 - open1) > body * 2.0);
        bool isBearishEngulfing = (close1 < open1) && (iClose(m_symbol, m_timeframe, 2) > iOpen(m_symbol, m_timeframe, 2)) && (close1 < iLow(m_symbol, m_timeframe, 2));
        double upperWick = (open1 < close1) ? high1 - open1 : high1 - close1;
        bool strongUpperWick = upperWick > (range * 0.4);
        
        return isBearishPin || isBearishEngulfing || strongUpperWick;
    }
    
    return false;
}

#endif // __STRATEGY_UNIFIED_ICT_MQH__
