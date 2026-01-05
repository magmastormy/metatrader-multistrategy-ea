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
    
    // Configuration
    double                      m_minConfluenceScore;
    int                         m_minConfluences;
    bool                        m_requireKillZone;
    bool                        m_requireOTE;
    int                         m_lastBarProcessed;
    
    // Statistics
    int                         m_signalsGenerated;
    int                         m_obsDetected;
    int                         m_liquiditySweeps;
    int                         m_tradesInKillZone;
    
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
    
private:
    void                        Cleanup();
    void                        DrawElements();
    
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
    m_minConfluenceScore(50.0),
    m_minConfluences(3),
    m_requireKillZone(false),
    m_requireOTE(false),
    m_lastBarProcessed(0),
    m_signalsGenerated(0),
    m_obsDetected(0),
    m_liquiditySweeps(0),
    m_tradesInKillZone(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyUnifiedICT::~CStrategyUnifiedICT()
{
    Cleanup();
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

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategyUnifiedICT::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;
    
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
    if(m_premiumDiscount == NULL || !m_premiumDiscount.Initialize(symbol, timeframe))
    {
        Print("[UICT v1.0] Failed to initialize Premium/Discount");
        return false;
    }
    
    PrintFormat("[UICT v1.0] Strategy initialized for %s on %s", symbol, EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::Deinit()
{
    ObjectsDeleteAll(0, "UICT_");
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
    
    int currentBar = iBars(m_symbol, m_timeframe);
    if(currentBar == m_lastBarProcessed)
        return;
    m_lastBarProcessed = currentBar;
    
    // Update all components
    if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
    if(m_obDetector != NULL) m_obDetector.Update();
    if(m_liquidityDetector != NULL) m_liquidityDetector.Update();
    if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
    if(m_premiumDiscount != NULL) m_premiumDiscount.Update();
    
    m_obsDetected = m_obDetector.GetOBCount();
    
    // Draw elements
    DrawElements();
}

//+------------------------------------------------------------------+
//| Draw Elements                                                    |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::DrawElements()
{
    ObjectsDeleteAll(0, "UICT_");
    
    // Draw Order Blocks
    if(m_obDetector != NULL)
    {
        for(int i = 0; i < m_obDetector.GetOBCount(); i++)
        {
            SAdvancedOrderBlock ob;
            if(!m_obDetector.GetOrderBlock(i, ob)) continue;
            if(ob.isMitigated) continue;
            
            string name = StringFormat("UICT_OB_%d", i);
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
            
            string name = StringFormat("UICT_FVG_%d", i);
            color fvgColor = imb.isBullish ? clrLimeGreen : clrOrangeRed;
            
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
    
    // Update all components
    if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
    if(m_obDetector != NULL) m_obDetector.Update();
    if(m_liquidityDetector != NULL) m_liquidityDetector.Update();
    if(m_imbalanceDetector != NULL) m_imbalanceDetector.Update();
    if(m_premiumDiscount != NULL) m_premiumDiscount.Update();
    
    // Check Kill Zone requirement
    if(m_requireKillZone && m_killZones != NULL)
    {
        if(!m_killZones.IsInKillZone())
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
    
    // Validate Market Maker setup
    if(!ValidateMarketMakerSetup(bestEntry))
        return TRADE_SIGNAL_NONE;
    
    // Determine signal direction
    ENUM_TRADE_SIGNAL result = TRADE_SIGNAL_NONE;
    
    if(m_structureAnalyzer != NULL && m_structureAnalyzer.IsBullish())
        result = TRADE_SIGNAL_BUY;
    else if(m_structureAnalyzer != NULL && m_structureAnalyzer.IsBearish())
        result = TRADE_SIGNAL_SELL;
    else
        return TRADE_SIGNAL_NONE;
    
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
    
    // Apply OTE bonus (disabled due to pointer access issues)
    /*if(m_premiumDiscount != NULL)
    {
        double currentBid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(m_premiumDiscount->IsInOTE(currentBid))
        {
            confidence = MathMin(1.0, confidence * 1.08);
        }
    }*/
    
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

//+------------------------------------------------------------------+
//| Create Risk Entry                                                |
//+------------------------------------------------------------------+
SICTEntrySetup CStrategyUnifiedICT::CreateRiskEntry()
{
    SICTEntrySetup entry;
    
    if(m_structureAnalyzer == NULL || m_obDetector == NULL)
        return entry;
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    bool bullish = m_structureAnalyzer.IsBullish();
    
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
    bool bullish = m_structureAnalyzer.IsBullish();
    
    // Find active Order Block
    int obIdx = bullish ? m_obDetector.FindBestBullishOB() : m_obDetector.FindBestBearishOB();
    if(obIdx < 0) return entry;
    
    SAdvancedOrderBlock ob;
    if(!m_obDetector.GetOrderBlock(obIdx, ob)) return entry;
    
    // Check if price is near AOI
    double tolerance = 15 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(MathAbs(price - ob.midpoint) > tolerance * 5)
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
    
    if(m_structureAnalyzer == NULL)
        return entry;
    
    // Check for first BMS but trend not confirmed
    ENUM_BMS_TYPE bms = m_structureAnalyzer.DetectBMS();
    if(bms == BMS_NONE)
        return entry;
    
    if(m_structureAnalyzer.IsTrendConfirmed())
        return entry;
    
    // Get LTF confirmation
    bool bullish = m_structureAnalyzer.IsBullish();
    
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
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
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
    
    if(m_structureAnalyzer == NULL)
        return entry;
    
    // HTF trend must be confirmed (2+ BMS)
    if(!m_structureAnalyzer.IsTrendConfirmed())
        return entry;
    
    if(m_structureAnalyzer.GetConsecutiveBMS() < 2)
        return entry;
    
    bool bullish = m_structureAnalyzer.IsBullish();
    
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
    
    // Check if liquidity was recently swept
    bool isBuyside;
    return m_liquidityDetector.HasRecentSweep(isBuyside);
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
    int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
    
    if(digits == 5)
    {
        double normalized = MathRound(price * 10000) / 10000;
        double fraction = normalized - MathFloor(normalized);
        
        // Major: .xx00, .xx50
        if(MathAbs(fraction - 0.0000) < 0.0003) return true;
        if(MathAbs(fraction - 0.0050) < 0.0003) return true;
        
        // Minor: .xx20, .xx80
        if(MathAbs(fraction - 0.0020) < 0.0003) return true;
        if(MathAbs(fraction - 0.0080) < 0.0003) return true;
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
    double buffer = 5 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double stopLoss = 0;
    
    if(signal == TRADE_SIGNAL_BUY)
    {
        if(entry.aoiBottom > 0)
            stopLoss = entry.aoiBottom - buffer;
        else
            stopLoss = entry.entryPrice - (30 * SymbolInfoDouble(m_symbol, SYMBOL_POINT));
    }
    else
    {
        if(entry.aoiTop > 0)
            stopLoss = entry.aoiTop + buffer;
        else
            stopLoss = entry.entryPrice + (30 * SymbolInfoDouble(m_symbol, SYMBOL_POINT));
    }
    
    return stopLoss;
}

//+------------------------------------------------------------------+
//| Calculate Take Profits                                           |
//+------------------------------------------------------------------+
void CStrategyUnifiedICT::CalculateTakeProfits(SICTEntrySetup &entry, ENUM_TRADE_SIGNAL signal)
{
    double risk = MathAbs(entry.entryPrice - entry.stopLoss);
    
    if(signal == TRADE_SIGNAL_BUY)
    {
        entry.takeProfit1 = entry.entryPrice + (risk * 2.0);
        entry.takeProfit2 = entry.entryPrice + (risk * 3.0);
        entry.takeProfit3 = entry.entryPrice + (risk * 5.0);
    }
    else
    {
        entry.takeProfit1 = entry.entryPrice - (risk * 2.0);
        entry.takeProfit2 = entry.entryPrice - (risk * 3.0);
        entry.takeProfit3 = entry.entryPrice - (risk * 5.0);
    }
    
    entry.riskReward = 2.0; // Minimum RR at TP1
}

#endif // __STRATEGY_UNIFIED_ICT_MQH__
