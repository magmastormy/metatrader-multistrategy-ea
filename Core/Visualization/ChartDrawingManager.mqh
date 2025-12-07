//+------------------------------------------------------------------+
//| ChartDrawingManager.mqh - Enterprise Chart Visualization         |
//| Professional, institutional-grade chart markup system            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property version   "1.00"
#property strict

#ifndef CHART_DRAWING_MANAGER_MQH
#define CHART_DRAWING_MANAGER_MQH

#include <ChartObjects\ChartObjectsLines.mqh>
#include <ChartObjects\ChartObjectsShapes.mqh>
#include <ChartObjects\ChartObjectsArrows.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>

//+------------------------------------------------------------------+
//| Color Palette - Professional & Consistent                        |
//+------------------------------------------------------------------+
enum ENUM_CHART_COLOR_SCHEME
{
    COLOR_SCHEME_BULLISH_PRIMARY = clrDodgerBlue,
    COLOR_SCHEME_BULLISH_SECONDARY = clrCornflowerBlue,
    COLOR_SCHEME_BEARISH_PRIMARY = clrCrimson,
    COLOR_SCHEME_BEARISH_SECONDARY = clrIndianRed,
    COLOR_SCHEME_NEUTRAL = clrGray,
    COLOR_SCHEME_SUPPLY = clrRed,
    COLOR_SCHEME_DEMAND = clrLime,
    COLOR_SCHEME_ORDERBLOCK_BULL = clrRoyalBlue,
    COLOR_SCHEME_ORDERBLOCK_BEAR = clrOrangeRed,
    COLOR_SCHEME_FVG_BULL = clrMediumSeaGreen,
    COLOR_SCHEME_FVG_BEAR = clrTomato,
    COLOR_SCHEME_LIQUIDITY = clrGold,
    COLOR_SCHEME_STRUCTURE_BOS = clrMagenta,
    COLOR_SCHEME_STRUCTURE_CHOCH = clrOrange,
    COLOR_SCHEME_ELLIOTT_IMPULSE = clrDeepSkyBlue,
    COLOR_SCHEME_ELLIOTT_CORRECTIVE = clrSalmon,
    COLOR_SCHEME_TEXT_LIGHT = clrWhite,
    COLOR_SCHEME_TEXT_DARK = clrBlack
};

//+------------------------------------------------------------------+
//| Drawing Configuration                                            |
//+------------------------------------------------------------------+
struct SDrawingConfig
{
    bool enableDrawing;           // Master switch
    bool enableStructure;         // HH/HL/LH/LL, BOS, CHOCH
    bool enableSupplyDemand;      // Supply/Demand zones
    bool enableOrderBlocks;       // Order blocks
    bool enableFVG;               // Fair Value Gaps
    bool enableLiquidity;         // Liquidity levels
    bool enableElliottWave;       // Elliott Wave counts
    bool enableTrendLines;        // Trend lines
    bool enableSignalMarkers;     // Entry/Exit markers
    bool enableDebugMode;         // Developer-level visuals
    bool cleanupOldObjects;       // Auto-cleanup obsolete objects
    int maxObjectAge;             // Max age in bars before cleanup
    
    SDrawingConfig()
    {
        enableDrawing = true;
        enableStructure = true;
        enableSupplyDemand = true;
        enableOrderBlocks = true;
        enableFVG = true;
        enableLiquidity = true;
        enableElliottWave = true;
        enableTrendLines = true;
        enableSignalMarkers = true;
        enableDebugMode = false;
        cleanupOldObjects = true;
        maxObjectAge = 500;
    }
};

//+------------------------------------------------------------------+
//| Object Naming Convention                                         |
//| Format: STRATEGY_OBJECTTYPE_UNIQUEID                            |
//+------------------------------------------------------------------+
class CChartDrawingManager
{
private:
    string m_prefix;                  // Object prefix for this manager
    SDrawingConfig m_config;          // Drawing configuration
    long m_chartID;                   // Chart ID
    string m_symbol;                  // Symbol
    ENUM_TIMEFRAMES m_timeframe;      // Timeframe
    
    // Statistics
    int m_objectsDrawn;
    int m_objectsDeleted;
    datetime m_lastCleanup;
    
    // Helper methods
    string GenerateObjectName(const string objectType, const string uniqueId);
    bool IsObjectOld(const string objName, int maxAge);
    void DeleteOldObjects(const string prefix, int maxAge);
    
public:
    CChartDrawingManager();
    ~CChartDrawingManager();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES tf, const string prefix = "");
    void SetConfiguration(const SDrawingConfig &config) { m_config = config; }
    SDrawingConfig GetConfiguration() const { return m_config; }
    
    // Structure Drawing (HH/HL/LH/LL, BOS, CHOCH)
    bool DrawSwingHigh(datetime time, double price, const string label = "HH");
    bool DrawSwingLow(datetime time, double price, const string label = "LL");
    bool DrawBOS(datetime time1, double price1, datetime time2, double price2, bool isBullish);
    bool DrawCHOCH(datetime time1, double price1, datetime time2, double price2, bool isBullish);
    
    // Zone Drawing (Supply/Demand, Order Blocks)
    bool DrawZone(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow, 
                  const string label, color zoneColor, bool isFilled = true, int transparency = 90);
    bool DrawOrderBlock(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                       bool isBullish, double strength = 1.0, const string uniqueId = "");
    
    // FVG Drawing
    bool DrawFVG(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                 bool isBullish, bool isFilled = false, const string uniqueId = "");
    
    // Liquidity Drawing
    bool DrawLiquidityLevel(datetime time1, datetime time2, double price, 
                           const string label, bool isSwept = false);
    bool DrawEqualHighs(datetime time1, datetime time2, datetime time3, double price);
    bool DrawEqualLows(datetime time1, datetime time2, datetime time3, double price);
    
    // Elliott Wave Drawing
    bool DrawWaveCount(datetime time, double price, int waveNumber, bool isImpulse = true);
    bool DrawWaveLabel(datetime time, double price, const string label, bool isImpulse = true);
    bool DrawFibProjection(datetime time1, double price1, datetime time2, double price2,
                          datetime time3, double price3);
    
    // Signal Markers
    bool DrawEntrySignal(datetime time, double price, bool isBuy, double confidence,
                        const string strategyName, const string reason = "");
    bool DrawExitSignal(datetime time, double price, bool wasProfit, 
                       const string reason = "");
    bool DrawStopLoss(datetime time, double price, bool isForBuy);
    bool DrawTakeProfit(datetime time, double price, bool isForBuy, int level = 1);
    
    // Trend Lines
    bool DrawTrendLine(datetime time1, double price1, datetime time2, double price2,
                      color lineColor = clrWhite, int width = 1, ENUM_LINE_STYLE style = STYLE_SOLID);
    
    // Text Labels
    bool DrawTextLabel(datetime time, double price, const string text,
                      color textColor = clrWhite, int fontSize = 10, ENUM_ANCHOR_POINT anchor = ANCHOR_CENTER);
    
    // Cleanup & Maintenance
    void CleanupOldObjects();
    void CleanupByPrefix(const string prefix);
    void CleanupAll();
    void DeleteObject(const string objName);
    
    // Statistics
    int GetObjectsDrawn() const { return m_objectsDrawn; }
    int GetObjectsDeleted() const { return m_objectsDeleted; }
    
    // Utility
    void EnableDebugMode(bool enable) { m_config.enableDebugMode = enable; }
    bool IsDebugMode() const { return m_config.enableDebugMode; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CChartDrawingManager::CChartDrawingManager() :
    m_chartID(0),
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_prefix("CHART_"),
    m_objectsDrawn(0),
    m_objectsDeleted(0),
    m_lastCleanup(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CChartDrawingManager::~CChartDrawingManager()
{
    if(m_config.cleanupOldObjects)
        CleanupAll();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CChartDrawingManager::Initialize(const string symbol, ENUM_TIMEFRAMES tf, const string prefix)
{
    m_symbol = symbol;
    m_timeframe = tf;
    m_chartID = ChartID();
    m_prefix = (prefix == "") ? "CHART_" : prefix + "_";
    m_lastCleanup = TimeCurrent();
    
    Print("[ChartDrawing] Initialized for ", symbol, " on ", EnumToString(tf));
    return true;
}

//+------------------------------------------------------------------+
//| Generate Object Name                                            |
//+------------------------------------------------------------------+
string CChartDrawingManager::GenerateObjectName(const string objectType, const string uniqueId)
{
    string objName = m_prefix + objectType;
    if(uniqueId != "")
        objName += "_" + uniqueId;
    else
        objName += "_" + IntegerToString(GetTickCount());
    
    return objName;
}

//+------------------------------------------------------------------+
//| Draw Swing High                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawSwingHigh(datetime time, double price, const string label)
{
    if(!m_config.enableDrawing || !m_config.enableStructure)
        return false;
    
    string objName = GenerateObjectName("SWING_HIGH", TimeToString(time));
    
    // Draw arrow
    ObjectCreate(m_chartID, objName, OBJ_ARROW_DOWN, 0, time, price);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, COLOR_SCHEME_BEARISH_PRIMARY);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, false);
    
    // Draw label
    string labelName = objName + "_LABEL";
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, time, price);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, label);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, COLOR_SCHEME_TEXT_LIGHT);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
    
    m_objectsDrawn += 2;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Swing Low                                                  |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawSwingLow(datetime time, double price, const string label)
{
    if(!m_config.enableDrawing || !m_config.enableStructure)
        return false;
    
    string objName = GenerateObjectName("SWING_LOW", TimeToString(time));
    
    // Draw arrow
    ObjectCreate(m_chartID, objName, OBJ_ARROW_UP, 0, time, price);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, COLOR_SCHEME_BULLISH_PRIMARY);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, false);
    
    // Draw label
    string labelName = objName + "_LABEL";
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, time, price);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, label);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, COLOR_SCHEME_TEXT_LIGHT);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_TOP);
    
    m_objectsDrawn += 2;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Break of Structure (BOS)                                   |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawBOS(datetime time1, double price1, datetime time2, double price2, bool isBullish)
{
    if(!m_config.enableDrawing || !m_config.enableStructure)
        return false;
    
    string objName = GenerateObjectName("BOS", TimeToString(time2));
    
    // Draw trend line
    ObjectCreate(m_chartID, objName, OBJ_TREND, 0, time1, price1, time2, price2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, COLOR_SCHEME_STRUCTURE_BOS);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(m_chartID, objName, OBJPROP_RAY_RIGHT, false);
    
    // Draw label
    string labelName = objName + "_LABEL";
    double midPrice = (price1 + price2) / 2;
    datetime midTime = (datetime)((time1 + time2) / 2);
    
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, midTime, midPrice);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, isBullish ? "BOS↑" : "BOS↓");
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, COLOR_SCHEME_STRUCTURE_BOS);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_CENTER);
    
    m_objectsDrawn += 2;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Change of Character (CHOCH)                                |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawCHOCH(datetime time1, double price1, datetime time2, double price2, bool isBullish)
{
    if(!m_config.enableDrawing || !m_config.enableStructure)
        return false;
    
    string objName = GenerateObjectName("CHOCH", TimeToString(time2));
    
    // Draw trend line
    ObjectCreate(m_chartID, objName, OBJ_TREND, 0, time1, price1, time2, price2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, COLOR_SCHEME_STRUCTURE_CHOCH);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(m_chartID, objName, OBJPROP_RAY_RIGHT, false);
    
    // Draw label
    string labelName = objName + "_LABEL";
    double midPrice = (price1 + price2) / 2;
    datetime midTime = (datetime)((time1 + time2) / 2);
    
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, midTime, midPrice);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, isBullish ? "CHOCH↑" : "CHOCH↓");
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, COLOR_SCHEME_STRUCTURE_CHOCH);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_CENTER);
    
    m_objectsDrawn += 2;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Zone (Supply/Demand/Order Block base)                      |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawZone(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                                   const string label, color zoneColor, bool isFilled, int transparency)
{
    if(!m_config.enableDrawing)
        return false;
    
    string objName = GenerateObjectName("ZONE", label + "_" + TimeToString(timeStart));
    
    // Draw rectangle
    ObjectCreate(m_chartID, objName, OBJ_RECTANGLE, 0, timeStart, priceHigh, timeEnd, priceLow);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, zoneColor);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(m_chartID, objName, OBJPROP_FILL, isFilled);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, true);
    
    if(isFilled && transparency > 0)
    {
        color transparentColor = zoneColor;
        ObjectSetInteger(m_chartID, objName, OBJPROP_BGCOLOR, transparentColor);
    }
    
    m_objectsDrawn++;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Order Block                                                |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawOrderBlock(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                                         bool isBullish, double strength, const string uniqueId)
{
    if(!m_config.enableDrawing || !m_config.enableOrderBlocks)
        return false;
    
    color obColor = isBullish ? COLOR_SCHEME_ORDERBLOCK_BULL : COLOR_SCHEME_ORDERBLOCK_BEAR;
    string label = isBullish ? "OB_BULL" : "OB_BEAR";
    if(uniqueId != "")
        label += "_" + uniqueId;
    
    return DrawZone(timeStart, timeEnd, priceHigh, priceLow, label, obColor, true, 85);
}

//+------------------------------------------------------------------+
//| Draw Fair Value Gap                                             |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawFVG(datetime timeStart, datetime timeEnd, double priceHigh, double priceLow,
                                  bool isBullish, bool isFilled, const string uniqueId)
{
    if(!m_config.enableDrawing || !m_config.enableFVG)
        return false;
    
    color fvgColor = isBullish ? COLOR_SCHEME_FVG_BULL : COLOR_SCHEME_FVG_BEAR;
    string label = isBullish ? "FVG_BULL" : "FVG_BEAR";
    if(uniqueId != "")
        label += "_" + uniqueId;
    
    // Adjust transparency based on filled status
    int transparency = isFilled ? 50 : 85;
    
    return DrawZone(timeStart, timeEnd, priceHigh, priceLow, label, fvgColor, true, transparency);
}

//+------------------------------------------------------------------+
//| Draw Liquidity Level                                            |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawLiquidityLevel(datetime time1, datetime time2, double price,
                                              const string label, bool isSwept)
{
    if(!m_config.enableDrawing || !m_config.enableLiquidity)
        return false;
    
    string objName = GenerateObjectName("LIQUIDITY", label + "_" + TimeToString(time1));
    
    // Draw horizontal line
    ObjectCreate(m_chartID, objName, OBJ_TREND, 0, time1, price, time2, price);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, COLOR_SCHEME_LIQUIDITY);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, isSwept ? 1 : 2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, isSwept ? STYLE_DOT : STYLE_DASHDOT);
    ObjectSetInteger(m_chartID, objName, OBJPROP_RAY_RIGHT, !isSwept);
    
    // Draw label
    string labelName = objName + "_LABEL";
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, time2, price);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, label + (isSwept ? " [SWEPT]" : ""));
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, isSwept ? clrGray : COLOR_SCHEME_LIQUIDITY);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
    
    m_objectsDrawn += 2;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Entry Signal                                               |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawEntrySignal(datetime time, double price, bool isBuy, double confidence,
                                          const string strategyName, const string reason)
{
    if(!m_config.enableDrawing || !m_config.enableSignalMarkers)
        return false;
    
    string objName = GenerateObjectName("ENTRY", strategyName + "_" + TimeToString(time));
    
    // Draw arrow
    int arrowCode = isBuy ? 233 : 234;  // Up/Down arrows
    ObjectCreate(m_chartID, objName, OBJ_ARROW, 0, time, price);
    ObjectSetInteger(m_chartID, objName, OBJPROP_ARROWCODE, arrowCode);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, isBuy ? clrLime : clrRed);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 3);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, false);
    
    // Draw label with strategy and confidence
    string labelName = objName + "_LABEL";
    string labelText = StringFormat("%s\n%.0f%%", strategyName, confidence * 100);
    if(reason != "")
        labelText += "\n" + reason;
    
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, time, price);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, labelText);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 7);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, isBuy ? ANCHOR_BOTTOM : ANCHOR_TOP);
    
    m_objectsDrawn += 2;
    return true;
}

//+------------------------------------------------------------------+
//| Cleanup Old Objects                                             |
//+------------------------------------------------------------------+
void CChartDrawingManager::CleanupOldObjects()
{
    if(!m_config.cleanupOldObjects)
        return;
    
    datetime currentTime = TimeCurrent();
    if(currentTime - m_lastCleanup < 60)  // Cleanup every minute
        return;
    
    DeleteOldObjects(m_prefix, m_config.maxObjectAge);
    m_lastCleanup = currentTime;
}

//+------------------------------------------------------------------+
//| Delete Old Objects by Prefix                                    |
//+------------------------------------------------------------------+
void CChartDrawingManager::DeleteOldObjects(const string prefix, int maxAge)
{
    int totalObjects = ObjectsTotal(m_chartID);
    datetime currentTime = TimeCurrent();
    
    for(int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(m_chartID, i);
        if(StringFind(objName, prefix) == 0)  // Starts with prefix
        {
            if(IsObjectOld(objName, maxAge))
            {
                ObjectDelete(m_chartID, objName);
                m_objectsDeleted++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if Object is Old                                          |
//+------------------------------------------------------------------+
bool CChartDrawingManager::IsObjectOld(const string objName, int maxAge)
{
    datetime objTime = (datetime)ObjectGetInteger(m_chartID, objName, OBJPROP_TIME);
    if(objTime == 0)
        return false;
    
    int objBar = iBarShift(m_symbol, m_timeframe, objTime);
    return (objBar > maxAge);
}

//+------------------------------------------------------------------+
//| Cleanup All Objects                                             |
//+------------------------------------------------------------------+
void CChartDrawingManager::CleanupAll()
{
    CleanupByPrefix(m_prefix);
}

//+------------------------------------------------------------------+
//| Cleanup by Prefix                                               |
//+------------------------------------------------------------------+
void CChartDrawingManager::CleanupByPrefix(const string prefix)
{
    int totalObjects = ObjectsTotal(m_chartID);
    for(int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(m_chartID, i);
        if(StringFind(objName, prefix) == 0)
        {
            ObjectDelete(m_chartID, objName);
            m_objectsDeleted++;
        }
    }
}

//+------------------------------------------------------------------+
//| Delete Object                                                    |
//+------------------------------------------------------------------+
void CChartDrawingManager::DeleteObject(const string objName)
{
    if(ObjectFind(m_chartID, objName) >= 0)
    {
        ObjectDelete(m_chartID, objName);
        m_objectsDeleted++;
    }
}

#endif // CHART_DRAWING_MANAGER_MQH
