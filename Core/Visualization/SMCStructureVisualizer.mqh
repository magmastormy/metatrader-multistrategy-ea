//+------------------------------------------------------------------+
//| SMCStructureVisualizer.mqh - Smart Money Concepts Visualization  |
//| Draws market structure, BOS, CHOCH, swing points                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property version   "1.00"
#property strict

#ifndef SMC_STRUCTURE_VISUALIZER_MQH
#define SMC_STRUCTURE_VISUALIZER_MQH

#include "ChartDrawingManager.mqh"

//+------------------------------------------------------------------+
//| SMC Structure Data                                               |
//+------------------------------------------------------------------+
struct SSMCSwingPoint
{
    datetime time;
    double price;
    bool isHigh;
    string label;  // HH, HL, LH, LL
};

struct SSMCStructureBreak
{
    datetime time1;
    double price1;
    datetime time2;
    double price2;
    bool isBullish;
    bool isBOS;    // true = BOS, false = CHOCH
};

//+------------------------------------------------------------------+
//| SMC Structure Visualizer                                         |
//+------------------------------------------------------------------+
class CSMCStructureVisualizer
{
private:
    CChartDrawingManager* m_drawer;
    bool m_ownDrawer;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    
    // Structure tracking
    SSMCSwingPoint m_swingPoints[];
    SSMCStructureBreak m_structureBreaks[];
    int m_swingCount;
    int m_breakCount;
    
    // Last drawn objects to prevent redrawing
    datetime m_lastSwingTime;
    datetime m_lastBreakTime;
    
public:
    CSMCStructureVisualizer();
    ~CSMCStructureVisualizer();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES tf, CChartDrawingManager* drawer = NULL);
    
    // Draw swing points
    bool DrawSwingHigh(datetime time, double price, const string label = "HH");
    bool DrawSwingLow(datetime time, double price, const string label = "LL");
    
    // Draw structure breaks
    bool DrawBOS(datetime time1, double price1, datetime time2, double price2, bool isBullish);
    bool DrawCHOCH(datetime time1, double price1, datetime time2, double price2, bool isBullish);
    
    // Utility
    void ClearStructure();
    int GetSwingCount() const { return m_swingCount; }
    int GetBreakCount() const { return m_breakCount; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSMCStructureVisualizer::CSMCStructureVisualizer() :
    m_drawer(NULL),
    m_ownDrawer(false),
    m_swingCount(0),
    m_breakCount(0),
    m_lastSwingTime(0),
    m_lastBreakTime(0)
{
    ArrayResize(m_swingPoints, 0);
    ArrayResize(m_structureBreaks, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSMCStructureVisualizer::~CSMCStructureVisualizer()
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
bool CSMCStructureVisualizer::Initialize(const string symbol, ENUM_TIMEFRAMES tf, CChartDrawingManager* drawer)
{
    m_symbol = symbol;
    m_timeframe = tf;
    
    if(drawer == NULL)
    {
        m_drawer = new CChartDrawingManager();
        if(m_drawer == NULL)
            return false;
        
        m_drawer.Initialize(symbol, tf, "SMC");
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
//| Draw Swing High                                                 |
//+------------------------------------------------------------------+
bool CSMCStructureVisualizer::DrawSwingHigh(datetime time, double price, const string label)
{
    if(m_drawer == NULL)
        return false;
    
    // Prevent duplicate drawing
    if(time == m_lastSwingTime)
        return false;
    
    bool result = m_drawer.DrawSwingHigh(time, price, label);
    if(result)
    {
        // Store swing point
        int size = ArraySize(m_swingPoints);
        ArrayResize(m_swingPoints, size + 1);
        m_swingPoints[size].time = time;
        m_swingPoints[size].price = price;
        m_swingPoints[size].isHigh = true;
        m_swingPoints[size].label = label;
        m_swingCount++;
        m_lastSwingTime = time;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Draw Swing Low                                                  |
//+------------------------------------------------------------------+
bool CSMCStructureVisualizer::DrawSwingLow(datetime time, double price, const string label)
{
    if(m_drawer == NULL)
        return false;
    
    // Prevent duplicate drawing
    if(time == m_lastSwingTime)
        return false;
    
    bool result = m_drawer.DrawSwingLow(time, price, label);
    if(result)
    {
        // Store swing point
        int size = ArraySize(m_swingPoints);
        ArrayResize(m_swingPoints, size + 1);
        m_swingPoints[size].time = time;
        m_swingPoints[size].price = price;
        m_swingPoints[size].isHigh = false;
        m_swingPoints[size].label = label;
        m_swingCount++;
        m_lastSwingTime = time;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Draw Break of Structure (BOS)                                   |
//+------------------------------------------------------------------+
bool CSMCStructureVisualizer::DrawBOS(datetime time1, double price1, datetime time2, double price2, bool isBullish)
{
    if(m_drawer == NULL)
        return false;
    
    // Prevent duplicate drawing
    if(time2 == m_lastBreakTime)
        return false;
    
    bool result = m_drawer.DrawBOS(time1, price1, time2, price2, isBullish);
    if(result)
    {
        // Store structure break
        int size = ArraySize(m_structureBreaks);
        ArrayResize(m_structureBreaks, size + 1);
        m_structureBreaks[size].time1 = time1;
        m_structureBreaks[size].price1 = price1;
        m_structureBreaks[size].time2 = time2;
        m_structureBreaks[size].price2 = price2;
        m_structureBreaks[size].isBullish = isBullish;
        m_structureBreaks[size].isBOS = true;
        m_breakCount++;
        m_lastBreakTime = time2;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Draw Change of Character (CHOCH)                                |
//+------------------------------------------------------------------+
bool CSMCStructureVisualizer::DrawCHOCH(datetime time1, double price1, datetime time2, double price2, bool isBullish)
{
    if(m_drawer == NULL)
        return false;
    
    // Prevent duplicate drawing
    if(time2 == m_lastBreakTime)
        return false;
    
    bool result = m_drawer.DrawCHOCH(time1, price1, time2, price2, isBullish);
    if(result)
    {
        // Store structure break
        int size = ArraySize(m_structureBreaks);
        ArrayResize(m_structureBreaks, size + 1);
        m_structureBreaks[size].time1 = time1;
        m_structureBreaks[size].price1 = price1;
        m_structureBreaks[size].time2 = time2;
        m_structureBreaks[size].price2 = price2;
        m_structureBreaks[size].isBullish = isBullish;
        m_structureBreaks[size].isBOS = false;
        m_breakCount++;
        m_lastBreakTime = time2;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Clear Structure                                                  |
//+------------------------------------------------------------------+
void CSMCStructureVisualizer::ClearStructure()
{
    ArrayResize(m_swingPoints, 0);
    ArrayResize(m_structureBreaks, 0);
    m_swingCount = 0;
    m_breakCount = 0;
    m_lastSwingTime = 0;
    m_lastBreakTime = 0;
    
    if(m_drawer != NULL)
        m_drawer.CleanupByPrefix("SMC");
}

#endif // SMC_STRUCTURE_VISUALIZER_MQH
