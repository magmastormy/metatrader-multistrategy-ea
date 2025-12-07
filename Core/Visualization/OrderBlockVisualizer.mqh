//+------------------------------------------------------------------+
//| OrderBlockVisualizer.mqh - Order Block Visualization            |
//| Professional order block drawing with strength indication        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property version   "1.00"
#property strict

#ifndef ORDER_BLOCK_VISUALIZER_MQH
#define ORDER_BLOCK_VISUALIZER_MQH

#include "ChartDrawingManager.mqh"

//+------------------------------------------------------------------+
//| Order Block Data                                                 |
//+------------------------------------------------------------------+
struct SOrderBlockData
{
    datetime timeStart;
    datetime timeEnd;
    double priceHigh;
    double priceLow;
    bool isBullish;
    double strength;     // 0.0 to 1.0
    bool isMitigated;
    datetime creationTime;
    int touchCount;
    string uniqueId;
};

//+------------------------------------------------------------------+
//| Order Block Visualizer                                          |
//+------------------------------------------------------------------+
class COrderBlockVisualizer
{
private:
    CChartDrawingManager* m_drawer;
    bool m_ownDrawer;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    
    // Order block tracking
    SOrderBlockData m_orderBlocks[];
    int m_blockCount;
    
    // Helper methods
    color GetColorByStrength(bool isBullish, double strength);
    
public:
    COrderBlockVisualizer();
    ~COrderBlockVisualizer();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES tf, CChartDrawingManager* drawer = NULL);
    
    // Draw order blocks
    bool DrawOrderBlock(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                       bool isBullish, double strength = 1.0, const string uniqueId = "");
    bool DrawBreakerBlock(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                         bool wasBreaker);
    bool MarkBlockMitigation(const string uniqueId, datetime mitigationTime);
    
    // Update blocks
    bool UpdateBlockTouch(const string uniqueId);
    bool RefreshBlock(const string uniqueId);
    
    // Utility
    void ClearAllBlocks();
    int GetActiveBlockCount() const;
    SOrderBlockData GetBlock(int index) const;
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
COrderBlockVisualizer::COrderBlockVisualizer() :
    m_drawer(NULL),
    m_ownDrawer(false),
    m_blockCount(0)
{
    ArrayResize(m_orderBlocks, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
COrderBlockVisualizer::~COrderBlockVisualizer()
{
    if(m_ownDrawer && m_drawer != NULL)
    {
        delete m_drawer;
        m_drawer = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool COrderBlockVisualizer::Initialize(const string symbol, ENUM_TIMEFRAMES tf, CChartDrawingManager* drawer)
{
    m_symbol = symbol;
    m_timeframe = tf;
    
    if(drawer == NULL)
    {
        m_drawer = new CChartDrawingManager();
        if(m_drawer == NULL)
            return false;
        
        m_drawer.Initialize(symbol, tf, "OB");
        m_ownDrawer = true;
    }
    else
    {
        m_drawer = drawer;
        m_ownDrawer = false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Color by Strength                                           |
//+------------------------------------------------------------------+
color COrderBlockVisualizer::GetColorByStrength(bool isBullish, double strength)
{
    if(isBullish)
    {
        // Bullish blocks: light blue to deep blue
        if(strength > 0.8)
            return clrRoyalBlue;
        else if(strength > 0.6)
            return clrDodgerBlue;
        else
            return clrCornflowerBlue;
    }
    else
    {
        // Bearish blocks: light red to deep red
        if(strength > 0.8)
            return clrCrimson;
        else if(strength > 0.6)
            return clrOrangeRed;
        else
            return clrIndianRed;
    }
}

//+------------------------------------------------------------------+
//| Draw Order Block                                                |
//+------------------------------------------------------------------+
bool COrderBlockVisualizer::DrawOrderBlock(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                                          bool isBullish, double strength, const string uniqueId)
{
    if(m_drawer == NULL)
        return false;
    
    string blockId = uniqueId;
    if(blockId == "")
        blockId = IntegerToString(m_blockCount) + "_" + TimeToString(timeStart);
    
    bool result = m_drawer.DrawOrderBlock(timeStart, timeEnd, priceHigh, priceLow, isBullish, strength, blockId);
    
    if(result)
    {
        // Store order block data
        int size = ArraySize(m_orderBlocks);
        ArrayResize(m_orderBlocks, size + 1);
        
        m_orderBlocks[size].timeStart = timeStart;
        m_orderBlocks[size].timeEnd = timeEnd;
        m_orderBlocks[size].priceHigh = priceHigh;
        m_orderBlocks[size].priceLow = priceLow;
        m_orderBlocks[size].isBullish = isBullish;
        m_orderBlocks[size].strength = strength;
        m_orderBlocks[size].isMitigated = false;
        m_orderBlocks[size].creationTime = TimeCurrent();
        m_orderBlocks[size].touchCount = 0;
        m_orderBlocks[size].uniqueId = blockId;
        
        m_blockCount++;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Draw Breaker Block                                              |
//+------------------------------------------------------------------+
bool COrderBlockVisualizer::DrawBreakerBlock(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                                             bool wasBreaker)
{
    if(m_drawer == NULL)
        return false;
    
    // Breaker blocks use different styling
    color breakerColor = wasBreaker ? clrGold : clrSilver;
    
    return m_drawer.DrawZone(timeStart, timeEnd, priceHigh, priceLow, "BREAKER", breakerColor, true, 70);
}

//+------------------------------------------------------------------+
//| Mark Block Mitigation                                           |
//+------------------------------------------------------------------+
bool COrderBlockVisualizer::MarkBlockMitigation(const string uniqueId, datetime mitigationTime)
{
    for(int i = 0; i < ArraySize(m_orderBlocks); i++)
    {
        if(m_orderBlocks[i].uniqueId == uniqueId)
        {
            m_orderBlocks[i].isMitigated = true;
            
            // Redraw with faded color or strikethrough
            // Implementation depends on requirements
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Update Block Touch                                              |
//+------------------------------------------------------------------+
bool COrderBlockVisualizer::UpdateBlockTouch(const string uniqueId)
{
    for(int i = 0; i < ArraySize(m_orderBlocks); i++)
    {
        if(m_orderBlocks[i].uniqueId == uniqueId)
        {
            m_orderBlocks[i].touchCount++;
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Clear All Blocks                                                 |
//+------------------------------------------------------------------+
void COrderBlockVisualizer::ClearAllBlocks()
{
    ArrayResize(m_orderBlocks, 0);
    m_blockCount = 0;
    
    if(m_drawer != NULL)
        m_drawer.CleanupByPrefix("OB");
}

//+------------------------------------------------------------------+
//| Get Active Block Count                                          |
//+------------------------------------------------------------------+
int COrderBlockVisualizer::GetActiveBlockCount() const
{
    int count = 0;
    for(int i = 0; i < ArraySize(m_orderBlocks); i++)
    {
        if(!m_orderBlocks[i].isMitigated)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get Block                                                        |
//+------------------------------------------------------------------+
SOrderBlockData COrderBlockVisualizer::GetBlock(int index) const
{
    SOrderBlockData empty;
    if(index < 0 || index >= ArraySize(m_orderBlocks))
        return empty;
    
    return m_orderBlocks[index];
}

#endif // ORDER_BLOCK_VISUALIZER_MQH
