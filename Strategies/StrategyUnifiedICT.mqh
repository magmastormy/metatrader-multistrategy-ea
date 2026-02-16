//+------------------------------------------------------------------+
//| StrategyUnifiedICT.mqh                                           |
//| Unified ICT/SMC Trading Strategy v1.0                            |
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

// Reuse existing SMC components where appropriate
#include "SMCFiles/KillZones.mqh"
#include "SMCFiles/PremiumDiscount.mqh"

// Chart Visualization
#include "../Core/Visualization/ChartDrawingManager.mqh"

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
    
    int confluenceCount;
    double confidence;
    string reason;
    
    SICTEntrySetup() : entryType(ICT_ENTRY_NONE), aoiTop(0), aoiBottom(0), aoiMidpoint(0),
                      htf(PERIOD_H4), ltf(PERIOD_M15), htfBMS(false), ltfBMS(false),
                      htfTrendConfirmed(false), ltfTrendConfirmed(false), entryPrice(0),
                      stopLoss(0), takeProfit1(0), takeProfit2(0), takeProfit3(0),
                      riskReward(0), confluenceCount(0), confidence(0), reason("") {}
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
    void                        DrawElements();
    bool                        RefreshComponentsForCurrentBar();
    
    // Entry System
    SICTEntrySetup              CreateRiskEntry();
    SICTEntrySetup              CreateJustificationEntry();
    SICTEntrySetup              CreateRiskWithJustEntry();
    SICTEntrySetup              CreateFullJustificationEntry();
    
    // Confluence
    int                         CountConfluences(double price, bool bullish);
    bool                        HasOrderBlockConfluence(double price, bool bullish);
    bool                        HasLiquidityConfluence(double price);
    bool                        HasImbalanceConfluence(double price, bool bullish);
    bool                        HasPremiumDiscountConfluence(double price, bool bullish);
    
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
    m_drawPrefix("UICT_")
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
    
    // Chart Drawing Manager - initialized but drawing done in DrawElements
    m_drawingManager = new CChartDrawingManager();
    if(m_drawingManager != NULL)
    {
        m_drawingManager.Initialize(symbol, timeframe, "UICT");
        m_drawPrefix = m_drawingManager.GetPrefix();
        Print("[UICT] Chart drawing manager ready");
    }
    
    m_lastBarProcessed = 0;
    
    Print("[UICT v1.0] Strategy initialized for ", symbol, " on ", EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::Deinit()
{
    ObjectsDeleteAll(0, m_drawPrefix);
    Cleanup();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::OnTick()
{
    if(!m_is_enabled) return;
}

//+------------------------------------------------------------------+
//| OnNewBar                                                         |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol != m_symbol || timeframe != m_timeframe)
        return;
    
    if(RefreshComponentsForCurrentBar())
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

//+------------------------------------------------------------------+
//| Draw Elements                                                    |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::DrawElements()
{
    CDrawingCoordinator* drawingCoordinator = GetDrawingCoordinator();
    if(drawingCoordinator != NULL)
        drawingCoordinator.PreparePrefixForCurrentBar(ChartID(), m_symbol, m_timeframe, m_drawPrefix);
    else
        ObjectsDeleteAll(0, m_drawPrefix);
    
    // Draw Order Blocks
    if(m_obDetector != NULL)
    {
        for(int i = 0; i < m_obDetector.GetOBCount(); i++)
        {
            SAdvancedOrderBlock ob;
            if(!m_obDetector.GetOrderBlock(i, ob)) continue;
            if(ob.isMitigated) continue;
            
            string name = StringFormat("%sOB_%d", m_drawPrefix, i);
            color obColor = (ob.type == OB_SOURCE_BULLISH || ob.type == OB_CONTINUATION_BULL || ob.type == OB_BREAKER_BULL) 
                           ? clrDodgerBlue : clrCrimson;
            
            if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
            
            ObjectCreate(0, name, OBJ_RECTANGLE, 0, ob.time, ob.top, TimeCurrent(), ob.bottom);
            ObjectSetInteger(0, name, OBJPROP_COLOR, obColor);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
            ObjectSetString(0, name, OBJPROP_TOOLTIP, StringFormat("%s | Str: %.0f%%", EnumToString(ob.type), ob.strength * 100));
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
            
            string name = StringFormat("%sFVG_%d", m_drawPrefix, i);
            color fvgColor = imb.isBullish ? clrGreen : clrRed;
            
            if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
            
            ObjectCreate(0, name, OBJ_RECTANGLE, 0, imb.time, imb.top, TimeCurrent(), imb.bottom);
            ObjectSetInteger(0, name, OBJPROP_COLOR, fvgColor);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
        }
    }
}

//+------------------------------------------------------------------+
//| Get Signal                                                       |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyUnifiedICT::GetSignal(double &confidence)
{
    confidence = 0.0;
    
    if(!m_is_enabled || !m_is_initialized)
        return TRADE_SIGNAL_NONE;
    
    // Ensure heavy component updates run once per bar across OnNewBar/GetSignal
    RefreshComponentsForCurrentBar();
    
    // Check Kill Zone requirement
    if(m_requireKillZone && m_killZones != NULL)
    {
        if(!m_killZones.IsInKillZone())
            return TRADE_SIGNAL_NONE;
    }

    bool isBullish = false;
    if(!ResolveDirectionalBias(isBullish))
    {
        LogFilterEvent("[UICT] Filtered: Ambiguous or neutral structure bias");
        return TRADE_SIGNAL_NONE;
    }
    
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
        return TRADE_SIGNAL_NONE;

    double entryConfluenceScore = ((double)bestEntry.confluenceCount / 6.0) * 100.0;
    if(bestEntry.confluenceCount < m_minConfluences || entryConfluenceScore < m_minConfluenceScore)
    {
        LogFilterEvent(StringFormat("[UICT] Filtered: Confluence gate failed (%d / %.1f%%)",
                                    bestEntry.confluenceCount, entryConfluenceScore));
        return TRADE_SIGNAL_NONE;
    }
    
    // Validate Market Maker setup
    if(!ValidateMarketMakerSetup(bestEntry))
        return TRADE_SIGNAL_NONE;
    
    // Determine signal direction from validated structure bias
    ENUM_TRADE_SIGNAL result = isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

    // ANCHOR-BASED REVERSAL: Require price to be at a major POI
    double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    if(!IsPriceAtMajorPOI(currentPrice))
    {
        LogFilterEvent(StringFormat("[UICT] Filtered: Price %.5f not at major POI", currentPrice));
        return TRADE_SIGNAL_NONE;
    }

    // COUNTER-TREND SCOUT: Allow reversals targeting HTF zones
    bool htfAligned = m_structureAnalyzer.IsHTFAligned(isBullish);

    if(!htfAligned)
    {
        if(!m_allowCounterTrendScout)
        {
            LogFilterEvent("[UICT] Filtered: Counter-trend setup blocked (production mode)");
            return TRADE_SIGNAL_NONE;
        }

        bool aggressiveCounterTrend = (bestEntry.entryType == ICT_ENTRY_RISK ||
                                       bestEntry.entryType == ICT_ENTRY_RISK_WITH_JUST);
        if(aggressiveCounterTrend)
        {
            LogFilterEvent("[UICT] Filtered: Counter-trend blocked for aggressive entry type");
            return TRADE_SIGNAL_NONE;
        }

        int requiredCounterConfluence = (int)MathMax((double)(m_minConfluences + 1), 5.0);
        if(bestEntry.confluenceCount < requiredCounterConfluence)
        {
            LogFilterEvent(StringFormat("[UICT] Filtered: Counter-trend confluence too low (%d < %d)",
                                        bestEntry.confluenceCount, requiredCounterConfluence));
            return TRADE_SIGNAL_NONE;
        }

        // Check if counter-trend is valid (targeting opposing HTF zone)
        if(!IsCounterTrendScoutValid(isBullish))
        {
            LogFilterEvent("[UICT] Filtered: No HTF alignment and no valid counter-trend target");
            return TRADE_SIGNAL_NONE;
        }

        bool inKillZone = (m_killZones != NULL && m_killZones.IsInKillZone());
        if(!inKillZone)
        {
            LogFilterEvent("[UICT] Filtered: Counter-trend requires active kill-zone");
            return TRADE_SIGNAL_NONE;
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
            LogFilterEvent("[UICT] Filtered: Counter-trend requires OTE alignment");
            return TRADE_SIGNAL_NONE;
        }

        // Counter-trend is valid, reduce confidence but allow signal
        bestEntry.confidence *= 0.65;
        bestEntry.reason += " (Counter-Trend Scout)";
    }
    
    // CANDLESTICK CONFIRMATION: Validate price rejection at POI
    if(!ValidatePriceRejection(result))
    {
        LogFilterEvent("[UICT] Filtered: No candlestick rejection confirmation at POI");
        return TRADE_SIGNAL_NONE;
    }
    
    confidence = bestEntry.confidence;
    
    // Apply Kill Zone bonus
    if(m_killZones != NULL)
    {
        if(m_killZones.IsInKillZone())
        {
            confidence = MathMin(1.0, confidence * 1.1);
            m_tradesInKillZone++;
        }
    }
    
    // Apply OTE bonus (fixed method calls and null check)
    if(m_premiumDiscount != NULL)
    {
        double currentBid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if((result == TRADE_SIGNAL_BUY && m_premiumDiscount.IsInBullishOTE(currentBid)) ||
           (result == TRADE_SIGNAL_SELL && m_premiumDiscount.IsInBearishOTE(currentBid)))
        {
            confidence = MathMin(1.0, confidence * 1.15); // Increased bonus to 15% for OTE
        }
    }
    
    if(result != TRADE_SIGNAL_NONE)
    {
        m_signalsGenerated++;
        
        PrintFormat("[UICT v1.0] %s: %s | Entry: %s | Conf: %.1f%% | Confluences: %d | %s",
                   m_symbol,
                   result == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   EnumToString(bestEntry.entryType),
                   confidence * 100,
                   bestEntry.confluenceCount,
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
    
    // Check confluences
    int confluences = CountConfluences(ob.midpoint, bullish);
    if(confluences < m_minConfluences)
        return entry;
    
    entry.entryType = ICT_ENTRY_RISK;
    entry.aoiTop = ob.top;
    entry.aoiBottom = ob.bottom;
    entry.aoiMidpoint = ob.midpoint;
    entry.entryPrice = ob.midpoint;
    entry.confluenceCount = confluences;
    entry.confidence = 0.60 + (confluences * 0.05);
    entry.reason = "Risk entry at OB";
    
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
    
    entry.entryType = ICT_ENTRY_JUSTIFICATION;
    entry.aoiTop = ob.top;
    entry.aoiBottom = ob.bottom;
    entry.aoiMidpoint = ob.midpoint;
    entry.ltfBMS = true;
    entry.entryPrice = price;
    entry.confluenceCount = CountConfluences(price, bullish);
    entry.confidence = 0.70;
    entry.reason = "Justification entry with BMS confirmation";
    
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
    
    entry.entryType = ICT_ENTRY_RISK_WITH_JUST;
    entry.htfBMS = true;
    entry.htfTrendConfirmed = false;
    entry.aoiTop = ob.top;
    entry.aoiBottom = ob.bottom;
    entry.aoiMidpoint = ob.midpoint;
    entry.entryPrice = ob.midpoint;
    entry.confluenceCount = CountConfluences(ob.midpoint, bullish);
    entry.confidence = 0.72;
    entry.reason = "Risk + Justification after first BMS";
    
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
    
    entry.entryType = ICT_ENTRY_FULL_JUSTIFICATION;
    entry.htfTrendConfirmed = true;
    entry.ltfBMS = (ltfBMS != BMS_NONE);
    entry.aoiTop = ob.top;
    entry.aoiBottom = ob.bottom;
    entry.aoiMidpoint = ob.midpoint;
    entry.entryPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    entry.confluenceCount = CountConfluences(entry.entryPrice, bullish);
    
    // Highest confidence
    entry.confidence = entry.ltfBMS ? 0.85 : 0.75;
    entry.reason = "Full Justification - HTF trend confirmed";
    
    entry.stopLoss = CalculateStopLoss(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    CalculateTakeProfits(entry, bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    
    return entry;
}

//+------------------------------------------------------------------+
//| Count Confluences                                                |
//+------------------------------------------------------------------+
int CStrategyUnifiedICT::CountConfluences(double price, bool bullish)
{
    int count = 0;
    
    // 1. Order Block
    if(HasOrderBlockConfluence(price, bullish))
        count++;
    
    // 2. Liquidity
    if(HasLiquidityConfluence(price))
        count++;
    
    // 3. Imbalance
    if(HasImbalanceConfluence(price, bullish))
        count++;
    
    // 4. Premium/Discount
    if(HasPremiumDiscountConfluence(price, bullish))
        count++;
    
    // 5. Institutional Level
    if(IsAtInstitutionalLevel(price))
        count++;
    
    // 6. Kill Zone
    if(m_killZones != NULL && m_killZones.IsInKillZone())
        count++;
    
    return count;
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
//| Calculate Take Profits                                           |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::CalculateTakeProfits(SICTEntrySetup &entry, ENUM_TRADE_SIGNAL signal)
{
    double risk = MathAbs(entry.entryPrice - entry.stopLoss);
    double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // Default fixed-RR values in case structural targets fail
    double target1 = (signal == TRADE_SIGNAL_BUY) ? entry.entryPrice + (risk * 2.0) : entry.entryPrice - (risk * 2.0);
    double target2 = (signal == TRADE_SIGNAL_BUY) ? entry.entryPrice + (risk * 3.0) : entry.entryPrice - (risk * 3.0);
    double target3 = (signal == TRADE_SIGNAL_BUY) ? entry.entryPrice + (risk * 5.0) : entry.entryPrice - (risk * 5.0);
    
    // Attempt to find structural targets (Liquidity Pools or Swing Points)
    if(m_liquidityDetector != NULL)
    {
        bool lookingForBuyside = (signal == TRADE_SIGNAL_BUY); // If we bought, TP is at buyside liquidity
        int poolIdx = m_liquidityDetector.FindNearestLiquidity(currentPrice, lookingForBuyside);
        if(poolIdx >= 0)
        {
            SLiquidityPool pool;
            if(m_liquidityDetector.GetPool(poolIdx, pool))
            {
                // Target the structural level if it provides at least 1.5:1 RR
                double potentialRR = MathAbs(pool.price - entry.entryPrice) / MathMax(SymbolInfoDouble(m_symbol, SYMBOL_POINT), risk);
                if(potentialRR >= 1.5)
                {
                    target1 = pool.price;
                    PrintFormat("[UICT] Structural TP1 set at Liquidity Pool: %.5f (RR: %.2f)", pool.price, potentialRR);
                }
            }
        }
    }
    
    entry.takeProfit1 = target1;
    entry.takeProfit2 = target2;
    entry.takeProfit3 = target3;
    entry.riskReward = MathAbs(target1 - entry.entryPrice) / MathMax(SymbolInfoDouble(m_symbol, SYMBOL_POINT), risk);
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
