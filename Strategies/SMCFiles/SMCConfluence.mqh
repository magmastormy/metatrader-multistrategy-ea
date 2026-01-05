//+------------------------------------------------------------------+
//| SMCConfluence.mqh                                                |
//| Multi-Factor Confluence Scoring for SMC/ICT Strategy             |
//| Combines all SMC components for entry validation                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __SMC_CONFLUENCE_MQH__
#define __SMC_CONFLUENCE_MQH__

#include "MarketStructure.mqh"
#include "KillZones.mqh"
#include "OrderBlocks.mqh"
#include "FairValueGap.mqh"
#include "LiquiditySweep.mqh"
#include "PremiumDiscount.mqh"

//+------------------------------------------------------------------+
//| Confluence Factor Weights                                        |
//+------------------------------------------------------------------+
struct SSMCWeights
{
    double      structureWeight;     // BOS/CHoCH weight (35%)
    double      orderBlockWeight;    // OB zone weight (25%)
    double      fvgWeight;           // FVG weight (15%)
    double      liquidityWeight;     // Sweep weight (15%)
    double      killZoneWeight;      // Time filter weight (10%)
    double      premiumDiscountWeight; // P/D bonus
    double      oteWeight;           // OTE bonus
    double      htfWeight;           // HTF alignment bonus
    
    SSMCWeights() : structureWeight(0.35), orderBlockWeight(0.25),
                    fvgWeight(0.15), liquidityWeight(0.15), killZoneWeight(0.10),
                    premiumDiscountWeight(0.05), oteWeight(0.05), htfWeight(0.10) {}
};

//+------------------------------------------------------------------+
//| Confluence Result                                                |
//+------------------------------------------------------------------+
struct SSMCConfluenceResult
{
    double      totalScore;
    int         factorCount;
    bool        hasStructure;
    bool        hasOrderBlock;
    bool        hasFVG;
    bool        hasLiquiditySweep;
    bool        inKillZone;
    bool        inPremiumDiscount;
    bool        inOTE;
    bool        htfAligned;
    
    // Details
    string      structureType;
    string      obInfo;
    string      fvgInfo;
    string      sweepInfo;
    string      killZoneName;
    
    SSMCConfluenceResult() : totalScore(0), factorCount(0), hasStructure(false),
                             hasOrderBlock(false), hasFVG(false), hasLiquiditySweep(false),
                             inKillZone(false), inPremiumDiscount(false), inOTE(false),
                             htfAligned(false), structureType(""), obInfo(""), fvgInfo(""),
                             sweepInfo(""), killZoneName("") {}
};

//+------------------------------------------------------------------+
//| SMC Confluence Engine                                            |
//+------------------------------------------------------------------+
class CSMCConfluenceEngine
{
private:
    string                  m_symbol;
    ENUM_TIMEFRAMES         m_timeframe;
    
    // Component references
    CSMCMarketStructure*    m_structure;
    CICTKillZones*          m_killZones;
    CSMCOrderBlocks*        m_orderBlocks;
    CSMCFairValueGap*       m_fvg;
    CSMCLiquiditySweep*     m_liquiditySweep;
    CSMCPremiumDiscount*    m_premiumDiscount;
    
    // Weights
    SSMCWeights             m_weights;
    
    // Configuration
    double                  m_minConfluenceScore;
    int                     m_minFactors;
    
    // HTF check
    bool                    m_useHTF;
    ENUM_TIMEFRAMES         m_htfTimeframe;
    
public:
                            CSMCConfluenceEngine();
                           ~CSMCConfluenceEngine();
    
    // Initialization
    bool                    Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    void                    SetHTFTimeframe(ENUM_TIMEFRAMES htf) { m_htfTimeframe = htf; m_useHTF = true; }
    void                    SetMinConfluenceScore(double score) { m_minConfluenceScore = score; }
    void                    SetMinFactors(int factors) { m_minFactors = factors; }
    void                    SetWeights(const SSMCWeights &weights) { m_weights = weights; }
    
    // Update all components
    void                    UpdateAll();
    
    // Calculate confluence
    SSMCConfluenceResult    CalculateBullishConfluence();
    SSMCConfluenceResult    CalculateBearishConfluence();
    
    // Quick checks
    bool                    HasValidBullishSetup();
    bool                    HasValidBearishSetup();
    
    // Component access
    CSMCMarketStructure*    GetStructure() { return m_structure; }
    CICTKillZones*          GetKillZones() { return m_killZones; }
    CSMCOrderBlocks*        GetOrderBlocks() { return m_orderBlocks; }
    CSMCFairValueGap*       GetFVG() { return m_fvg; }
    CSMCLiquiditySweep*     GetLiquiditySweep() { return m_liquiditySweep; }
    CSMCPremiumDiscount*    GetPremiumDiscount() { return m_premiumDiscount; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSMCConfluenceEngine::CSMCConfluenceEngine() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_structure(NULL),
    m_killZones(NULL),
    m_orderBlocks(NULL),
    m_fvg(NULL),
    m_liquiditySweep(NULL),
    m_premiumDiscount(NULL),
    m_minConfluenceScore(0.65),
    m_minFactors(3),
    m_useHTF(false),
    m_htfTimeframe(PERIOD_H4)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSMCConfluenceEngine::~CSMCConfluenceEngine()
{
    if(m_structure != NULL) { delete m_structure; m_structure = NULL; }
    if(m_killZones != NULL) { delete m_killZones; m_killZones = NULL; }
    if(m_orderBlocks != NULL) { delete m_orderBlocks; m_orderBlocks = NULL; }
    if(m_fvg != NULL) { delete m_fvg; m_fvg = NULL; }
    if(m_liquiditySweep != NULL) { delete m_liquiditySweep; m_liquiditySweep = NULL; }
    if(m_premiumDiscount != NULL) { delete m_premiumDiscount; m_premiumDiscount = NULL; }
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSMCConfluenceEngine::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    // Create and initialize all components
    m_structure = new CSMCMarketStructure();
    if(m_structure != NULL)
        m_structure.Initialize(symbol, timeframe);
    
    m_killZones = new CICTKillZones();
    if(m_killZones != NULL)
        m_killZones.Initialize(2, true); // GMT+2 broker
    
    m_orderBlocks = new CSMCOrderBlocks();
    if(m_orderBlocks != NULL)
        m_orderBlocks.Initialize(symbol, timeframe);
    
    m_fvg = new CSMCFairValueGap();
    if(m_fvg != NULL)
        m_fvg.Initialize(symbol, timeframe);
    
    m_liquiditySweep = new CSMCLiquiditySweep();
    if(m_liquiditySweep != NULL)
        m_liquiditySweep.Initialize(symbol, timeframe);
    
    m_premiumDiscount = new CSMCPremiumDiscount();
    if(m_premiumDiscount != NULL)
        m_premiumDiscount.Initialize(symbol, timeframe);
    
    return true;
}

//+------------------------------------------------------------------+
//| Update All Components                                            |
//+------------------------------------------------------------------+
void CSMCConfluenceEngine::UpdateAll()
{
    if(m_structure != NULL)
        m_structure.DetectSwingPoints(100);
    
    if(m_orderBlocks != NULL)
    {
        m_orderBlocks.ScanForOrderBlocks(50);
        m_orderBlocks.UpdateOrderBlocks();
        m_orderBlocks.RemoveOldBlocks();
    }
    
    if(m_fvg != NULL)
    {
        m_fvg.ScanForFVGs(50);
        m_fvg.UpdateFVGs();
        m_fvg.RemoveOldFVGs();
    }
    
    if(m_liquiditySweep != NULL)
    {
        m_liquiditySweep.ScanForSweeps(5);
        m_liquiditySweep.UpdateSweeps();
    }
    
    if(m_premiumDiscount != NULL)
        m_premiumDiscount.Update();
}

//+------------------------------------------------------------------+
//| Calculate Bullish Confluence                                     |
//+------------------------------------------------------------------+
SSMCConfluenceResult CSMCConfluenceEngine::CalculateBullishConfluence()
{
    SSMCConfluenceResult result;
    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // 1. Market Structure (35% weight)
    if(m_structure != NULL)
    {
        if(m_structure.HasBullishBOS())
        {
            result.hasStructure = true;
            result.structureType = "Bullish BOS";
            result.totalScore += m_weights.structureWeight;
            result.factorCount++;
        }
        else if(m_structure.HasBullishCHoCH())
        {
            result.hasStructure = true;
            result.structureType = "Bullish CHoCH";
            result.totalScore += m_weights.structureWeight * 0.8; // Slightly less for CHoCH
            result.factorCount++;
        }
    }
    
    // 2. Order Block (25% weight)
    if(m_orderBlocks != NULL)
    {
        SOrderBlock ob;
        if(m_orderBlocks.IsPriceInBullishOB(lastPrice))
        {
            result.hasOrderBlock = true;
            result.totalScore += m_weights.orderBlockWeight;
            result.factorCount++;
            
            m_orderBlocks.GetBestBullishOB(ob);
            result.obInfo = StringFormat("Bullish OB | Score: %.1f | Touches: %d",
                                         ob.score, ob.touches);
            
            // Untested OB bonus
            if(ob.touches == 0)
                result.totalScore += 0.05;
        }
    }
    
    // 3. Fair Value Gap (15% weight)
    if(m_fvg != NULL)
    {
        SFairValueGap fvg;
        if(m_fvg.IsPriceInBullishFVG(lastPrice))
        {
            result.hasFVG = true;
            result.totalScore += m_weights.fvgWeight;
            result.factorCount++;
            
            m_fvg.GetBestBullishFVG(fvg);
            result.fvgInfo = StringFormat("Bullish FVG | Size: %.2f ATR", fvg.size);
        }
    }
    
    // 4. Liquidity Sweep (15% weight)
    if(m_liquiditySweep != NULL)
    {
        if(m_liquiditySweep.HasRecentBullishSweep(5))
        {
            result.hasLiquiditySweep = true;
            result.totalScore += m_weights.liquidityWeight;
            result.factorCount++;
            
            SLiquiditySweep sweep;
            m_liquiditySweep.GetLatestBullishSweep(sweep);
            result.sweepInfo = StringFormat("Sellside Sweep | Score: %.1f", sweep.score);
        }
    }
    
    // 5. Kill Zone (10% weight)
    if(m_killZones != NULL)
    {
        if(m_killZones.IsInKillZone())
        {
            result.inKillZone = true;
            result.totalScore += m_weights.killZoneWeight * m_killZones.GetKillZoneWeight();
            result.factorCount++;
            result.killZoneName = m_killZones.GetKillZoneName();
        }
    }
    
    // 6. Premium/Discount (bonus)
    if(m_premiumDiscount != NULL)
    {
        if(m_premiumDiscount.IsDiscount(lastPrice))
        {
            result.inPremiumDiscount = true;
            result.totalScore += m_weights.premiumDiscountWeight;
        }
        
        if(m_premiumDiscount.IsInBullishOTE(lastPrice))
        {
            result.inOTE = true;
            result.totalScore += m_weights.oteWeight;
        }
    }
    
    // 7. HTF Alignment (bonus)
    if(m_useHTF)
    {
        // Check HTF trend using MAs
        int maFast = iMA(m_symbol, m_htfTimeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
        int maSlow = iMA(m_symbol, m_htfTimeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
        
        double fastVal[], slowVal[];
        ArraySetAsSeries(fastVal, true);
        ArraySetAsSeries(slowVal, true);
        
        if(CopyBuffer(maFast, 0, 0, 1, fastVal) > 0 && CopyBuffer(maSlow, 0, 0, 1, slowVal) > 0)
        {
            if(fastVal[0] > slowVal[0] && lastPrice > fastVal[0])
            {
                result.htfAligned = true;
                result.totalScore += m_weights.htfWeight;
            }
        }
        
        IndicatorRelease(maFast);
        IndicatorRelease(maSlow);
    }
    
    // Cap score at 1.0
    result.totalScore = MathMin(1.0, result.totalScore);
    
    return result;
}

//+------------------------------------------------------------------+
//| Calculate Bearish Confluence                                     |
//+------------------------------------------------------------------+
SSMCConfluenceResult CSMCConfluenceEngine::CalculateBearishConfluence()
{
    SSMCConfluenceResult result;
    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // 1. Market Structure (35% weight)
    if(m_structure != NULL)
    {
        if(m_structure.HasBearishBOS())
        {
            result.hasStructure = true;
            result.structureType = "Bearish BOS";
            result.totalScore += m_weights.structureWeight;
            result.factorCount++;
        }
        else if(m_structure.HasBearishCHoCH())
        {
            result.hasStructure = true;
            result.structureType = "Bearish CHoCH";
            result.totalScore += m_weights.structureWeight * 0.8;
            result.factorCount++;
        }
    }
    
    // 2. Order Block (25% weight)
    if(m_orderBlocks != NULL)
    {
        SOrderBlock ob;
        if(m_orderBlocks.IsPriceInBearishOB(lastPrice))
        {
            result.hasOrderBlock = true;
            result.totalScore += m_weights.orderBlockWeight;
            result.factorCount++;
            
            m_orderBlocks.GetBestBearishOB(ob);
            result.obInfo = StringFormat("Bearish OB | Score: %.1f | Touches: %d",
                                         ob.score, ob.touches);
            
            if(ob.touches == 0)
                result.totalScore += 0.05;
        }
    }
    
    // 3. Fair Value Gap (15% weight)
    if(m_fvg != NULL)
    {
        SFairValueGap fvg;
        if(m_fvg.IsPriceInBearishFVG(lastPrice))
        {
            result.hasFVG = true;
            result.totalScore += m_weights.fvgWeight;
            result.factorCount++;
            
            m_fvg.GetBestBearishFVG(fvg);
            result.fvgInfo = StringFormat("Bearish FVG | Size: %.2f ATR", fvg.size);
        }
    }
    
    // 4. Liquidity Sweep (15% weight)
    if(m_liquiditySweep != NULL)
    {
        if(m_liquiditySweep.HasRecentBearishSweep(5))
        {
            result.hasLiquiditySweep = true;
            result.totalScore += m_weights.liquidityWeight;
            result.factorCount++;
            
            SLiquiditySweep sweep;
            m_liquiditySweep.GetLatestBearishSweep(sweep);
            result.sweepInfo = StringFormat("Buyside Sweep | Score: %.1f", sweep.score);
        }
    }
    
    // 5. Kill Zone (10% weight)
    if(m_killZones != NULL)
    {
        if(m_killZones.IsInKillZone())
        {
            result.inKillZone = true;
            result.totalScore += m_weights.killZoneWeight * m_killZones.GetKillZoneWeight();
            result.factorCount++;
            result.killZoneName = m_killZones.GetKillZoneName();
        }
    }
    
    // 6. Premium/Discount (bonus)
    if(m_premiumDiscount != NULL)
    {
        if(m_premiumDiscount.IsPremium(lastPrice))
        {
            result.inPremiumDiscount = true;
            result.totalScore += m_weights.premiumDiscountWeight;
        }
        
        if(m_premiumDiscount.IsInBearishOTE(lastPrice))
        {
            result.inOTE = true;
            result.totalScore += m_weights.oteWeight;
        }
    }
    
    // 7. HTF Alignment (bonus)
    if(m_useHTF)
    {
        int maFast = iMA(m_symbol, m_htfTimeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
        int maSlow = iMA(m_symbol, m_htfTimeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
        
        double fastVal[], slowVal[];
        ArraySetAsSeries(fastVal, true);
        ArraySetAsSeries(slowVal, true);
        
        if(CopyBuffer(maFast, 0, 0, 1, fastVal) > 0 && CopyBuffer(maSlow, 0, 0, 1, slowVal) > 0)
        {
            if(fastVal[0] < slowVal[0] && lastPrice < fastVal[0])
            {
                result.htfAligned = true;
                result.totalScore += m_weights.htfWeight;
            }
        }
        
        IndicatorRelease(maFast);
        IndicatorRelease(maSlow);
    }
    
    result.totalScore = MathMin(1.0, result.totalScore);
    
    return result;
}

//+------------------------------------------------------------------+
//| Has Valid Bullish Setup                                          |
//+------------------------------------------------------------------+
bool CSMCConfluenceEngine::HasValidBullishSetup()
{
    SSMCConfluenceResult result = CalculateBullishConfluence();
    return (result.totalScore >= m_minConfluenceScore && result.factorCount >= m_minFactors);
}

//+------------------------------------------------------------------+
//| Has Valid Bearish Setup                                          |
//+------------------------------------------------------------------+
bool CSMCConfluenceEngine::HasValidBearishSetup()
{
    SSMCConfluenceResult result = CalculateBearishConfluence();
    return (result.totalScore >= m_minConfluenceScore && result.factorCount >= m_minFactors);
}

#endif // __SMC_CONFLUENCE_MQH__
