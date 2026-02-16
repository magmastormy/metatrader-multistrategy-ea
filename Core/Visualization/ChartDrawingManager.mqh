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
#include "DrawingCoordinator.mqh"

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
    bool enableSupportResistance; // Horizontal SR levels
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
        enableSupportResistance = true;
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
    string BuildScopedPrefix(const string basePrefix, const string symbol, ENUM_TIMEFRAMES tf);
    void PrepareSnapshotDraw();
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
    bool DrawHorizontalLevel(double price, color levelColor, const string label = "",
                             ENUM_LINE_STYLE style = STYLE_DOT, int width = 1, bool rayRight = true);
    
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
    string GetPrefix() const { return m_prefix; }
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
//| Draw Horizontal Support/Resistance Level                         |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawHorizontalLevel(double price, color levelColor, const string label,
                                              ENUM_LINE_STYLE style, int width, bool rayRight)
{
    if(!m_config.enableDrawing || !m_config.enableSupportResistance)
        return false;

    PrepareSnapshotDraw();
    
    int tfSeconds = PeriodSeconds(m_timeframe);
    if(tfSeconds <= 0)
        tfSeconds = 60;
    
    datetime timeEnd = TimeCurrent() + (datetime)(tfSeconds * 20);
    datetime timeStart = timeEnd - (datetime)(tfSeconds * 200);
    
    string objName = GenerateObjectName("SR_LEVEL", label);
    ObjectDelete(m_chartID, objName);
    
    if(!ObjectCreate(m_chartID, objName, OBJ_TREND, 0, timeStart, price, timeEnd, price))
        return false;
    
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, levelColor);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, width);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, style);
    ObjectSetInteger(m_chartID, objName, OBJPROP_RAY_RIGHT, rayRight);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, false);
    
    if(label != "")
    {
        string labelName = objName + "_LABEL";
        ObjectDelete(m_chartID, labelName);
        ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, timeEnd, price);
        ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, label);
        ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, levelColor);
        ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
        m_objectsDrawn += 2;
    }
    else
    {
        m_objectsDrawn++;
    }
    
    return true;
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
    m_prefix = BuildScopedPrefix(prefix, symbol, tf);
    m_lastCleanup = TimeCurrent();
    
    Print("[ChartDrawing] Initialized for ", symbol, " on ", EnumToString(tf));
    return true;
}

//+------------------------------------------------------------------+
//| Build scoped drawing prefix (symbol + timeframe isolated)        |
//+------------------------------------------------------------------+
string CChartDrawingManager::BuildScopedPrefix(const string basePrefix,
                                               const string symbol,
                                               ENUM_TIMEFRAMES tf)
{
    string root = (basePrefix == "") ? "CHART" : basePrefix;

    // Sanitize symbol for object names
    string safeSymbol = symbol;
    StringReplace(safeSymbol, ".", "_");
    StringReplace(safeSymbol, " ", "_");
    StringReplace(safeSymbol, "/", "_");
    StringReplace(safeSymbol, "-", "_");

    return StringFormat("%s_%s_%d_", root, safeSymbol, (int)tf);
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
//| Enforce per-bar immutable snapshot lifecycle by prefix           |
//+------------------------------------------------------------------+
void CChartDrawingManager::PrepareSnapshotDraw()
{
    CDrawingCoordinator* coordinator = GetDrawingCoordinator();
    if(coordinator != NULL)
        coordinator.PreparePrefixForCurrentBar(m_chartID, m_symbol, m_timeframe, m_prefix);
}

//+------------------------------------------------------------------+
//| Draw Swing High                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawSwingHigh(datetime time, double price, const string label)
{
    if(!m_config.enableDrawing || !m_config.enableStructure)
        return false;

    PrepareSnapshotDraw();
    
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

    PrepareSnapshotDraw();
    
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

    PrepareSnapshotDraw();
    
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

    PrepareSnapshotDraw();
    
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
    {
        Print("[ChartDrawing] Drawing disabled - skipping zone: ", label);
        return false;
    }

    PrepareSnapshotDraw();
    
    string objName = GenerateObjectName("ZONE", label + "_" + TimeToString(timeStart));
    Print("[ChartDrawing] Drawing zone: ", objName, " | Price: ", priceLow, "-", priceHigh);
    
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
    ChartRedraw(m_chartID);
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
    
    color obColor = isBullish ? (color)COLOR_SCHEME_ORDERBLOCK_BULL : (color)COLOR_SCHEME_ORDERBLOCK_BEAR;
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
    
    color fvgColor = isBullish ? (color)COLOR_SCHEME_FVG_BULL : (color)COLOR_SCHEME_FVG_BEAR;
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

    PrepareSnapshotDraw();
    
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

    PrepareSnapshotDraw();
    
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
    
    datetime cleanupTime = TimeCurrent();
    if(cleanupTime - m_lastCleanup < 60)  // Cleanup every minute
        return;
    
    DeleteOldObjects(m_prefix, m_config.maxObjectAge);
    m_lastCleanup = cleanupTime;
}

//+------------------------------------------------------------------+
//| Delete Old Objects by Prefix                                    |
//+------------------------------------------------------------------+
void CChartDrawingManager::DeleteOldObjects(const string prefix, int maxAge)
{
    int totalObjects = ObjectsTotal(m_chartID);
    datetime localCurrentTime = TimeCurrent();
    
    for(int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(m_chartID, i);
        if(StringFind(objName, prefix) == 0)  // Starts with prefix
        {
            if(maxAge > 0 && (localCurrentTime - (datetime)ObjectGetInteger(m_chartID, objName, OBJPROP_TIME)) > maxAge)
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

//+------------------------------------------------------------------+
//| Draw Equal Highs                                                |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawEqualHighs(datetime time1, datetime time2, datetime time3, double price)
{
    PrepareSnapshotDraw();

    // Draw liquidity line
    if(!DrawLiquidityLevel(time1, time3, price, "EQH", false))
        return false;
    
    // Draw markers
    string objName1 = GenerateObjectName("EQH_M1", TimeToString(time1));
    ObjectCreate(m_chartID, objName1, OBJ_ARROW_STOP, 0, time1, price);
    
    string objName2 = GenerateObjectName("EQH_M2", TimeToString(time2));
    ObjectCreate(m_chartID, objName2, OBJ_ARROW_STOP, 0, time2, price);
    
    if(time3 > time2)
    {
        string objName3 = GenerateObjectName("EQH_M3", TimeToString(time3));
        ObjectCreate(m_chartID, objName3, OBJ_ARROW_STOP, 0, time3, price);
    }
        
    return true;
}

//+------------------------------------------------------------------+
//| Draw Equal Lows                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawEqualLows(datetime time1, datetime time2, datetime time3, double price)
{
    PrepareSnapshotDraw();

    // Draw liquidity line
    if(!DrawLiquidityLevel(time1, time3, price, "EQL", false))
        return false;
    
    // Draw markers
    string objName1 = GenerateObjectName("EQL_M1", TimeToString(time1));
    ObjectCreate(m_chartID, objName1, OBJ_ARROW_CHECK, 0, time1, price);
    
    string objName2 = GenerateObjectName("EQL_M2", TimeToString(time2));
    ObjectCreate(m_chartID, objName2, OBJ_ARROW_CHECK, 0, time2, price);
    
    if(time3 > time2)
    {
        string objName3 = GenerateObjectName("EQL_M3", TimeToString(time3));
        ObjectCreate(m_chartID, objName3, OBJ_ARROW_CHECK, 0, time3, price);
    }
        
    return true;
}

//+------------------------------------------------------------------+
//| Draw Wave Count                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawWaveCount(datetime time, double price, int waveNumber, bool isImpulse)
{
    if(!m_config.enableDrawing || !m_config.enableElliottWave)
        return false;
        
    string label = IntegerToString(waveNumber);
    return DrawWaveLabel(time, price, label, isImpulse);
}

//+------------------------------------------------------------------+
//| Draw Wave Label                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawWaveLabel(datetime time, double price, const string label, bool isImpulse)
{
    if(!m_config.enableDrawing || !m_config.enableElliottWave)
        return false;
    
    // Check for "Debug" label if not in debug mode
    if(StringFind(label, "Debug") >= 0 && !m_config.enableDebugMode)
        return false;

    PrepareSnapshotDraw();
        
    string objName = GenerateObjectName("WAVE", label + "_" + TimeToString(time));
    
    ObjectCreate(m_chartID, objName, OBJ_TEXT, 0, time, price);
    ObjectSetString(m_chartID, objName, OBJPROP_TEXT, label);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, isImpulse ? COLOR_SCHEME_ELLIOTT_IMPULSE : COLOR_SCHEME_ELLIOTT_CORRECTIVE);
    ObjectSetInteger(m_chartID, objName, OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(m_chartID, objName, OBJPROP_ANCHOR, ANCHOR_CENTER);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, false);
    
    m_objectsDrawn++;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Projection                                       |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawFibProjection(datetime time1, double price1, datetime time2, double price2, datetime time3, double price3)
{
    if(!m_config.enableDrawing || !m_config.enableElliottWave)
        return false;

    PrepareSnapshotDraw();
        
    string objName = GenerateObjectName("FIB_EXP", TimeToString(time3));
    
    if(ObjectCreate(m_chartID, objName, OBJ_EXPANSION, 0, time1, price1, time2, price2))
    {
        ObjectSetInteger(m_chartID, objName, OBJPROP_TIME, 2, time3);
        ObjectSetDouble(m_chartID, objName, OBJPROP_PRICE, 2, price3);
        ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, clrDarkGray);
        ObjectSetInteger(m_chartID, objName, OBJPROP_LEVELS, 3);
        ObjectSetDouble(m_chartID, objName, OBJPROP_LEVELVALUE, 0, 0.618);
        ObjectSetDouble(m_chartID, objName, OBJPROP_LEVELVALUE, 1, 1.0);
        ObjectSetDouble(m_chartID, objName, OBJPROP_LEVELVALUE, 2, 1.618);
        
        m_objectsDrawn++;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Draw Exit Signal                                                |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawExitSignal(datetime time, double price, bool wasProfit, const string reason)
{
    if(!m_config.enableDrawing || !m_config.enableSignalMarkers)
        return false;

    PrepareSnapshotDraw();
        
    string objName = GenerateObjectName("EXIT", TimeToString(time));
    
    ObjectCreate(m_chartID, objName, OBJ_ARROW, 0, time, price);
    ObjectSetInteger(m_chartID, objName, OBJPROP_ARROWCODE, 251); // X sign
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, wasProfit ? clrLime : clrRed);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    
    if(reason != "")
    {
        string labelName = objName + "_LABEL";
        ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, time, price);
        ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, reason);
        ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_TOP);
        ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 8);
    }
    
    m_objectsDrawn++;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Stop Loss Level                                            |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawStopLoss(datetime time, double price, bool isForBuy)
{
    return DrawHorizontalLevel(price, clrRed, "SL", STYLE_SOLID, 1, true);
}

//+------------------------------------------------------------------+
//| Draw Take Profit Level                                          |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawTakeProfit(datetime time, double price, bool isForBuy, int level)
{
    return DrawHorizontalLevel(price, clrGreen, "TP" + IntegerToString(level), STYLE_DASH, 1, true);
}

//+------------------------------------------------------------------+
//| Draw Trend Line                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawTrendLine(datetime time1, double price1, datetime time2, double price2,
                      color lineColor, int width, ENUM_LINE_STYLE style)
{
    if(!m_config.enableDrawing || !m_config.enableTrendLines)
        return false;

    PrepareSnapshotDraw();
        
    string objName = GenerateObjectName("TL", TimeToString(time2));
    
    ObjectCreate(m_chartID, objName, OBJ_TREND, 0, time1, price1, time2, price2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, width);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, style);
    ObjectSetInteger(m_chartID, objName, OBJPROP_RAY_RIGHT, true);
    
    m_objectsDrawn++;
    return true;
}

//+------------------------------------------------------------------+
//| Draw Text Label                                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawTextLabel(datetime time, double price, const string text,
                      color textColor, int fontSize, ENUM_ANCHOR_POINT anchor)
{
    if(!m_config.enableDrawing)
        return false;

    PrepareSnapshotDraw();
        
    string objName = GenerateObjectName("TXT", text + "_" + TimeToString(time));
    
    ObjectCreate(m_chartID, objName, OBJ_TEXT, 0, time, price);
    ObjectSetString(m_chartID, objName, OBJPROP_TEXT, text);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, textColor);
    ObjectSetInteger(m_chartID, objName, OBJPROP_FONTSIZE, fontSize);
    ObjectSetInteger(m_chartID, objName, OBJPROP_ANCHOR, anchor);
    
    m_objectsDrawn++;
    return true;
}

#endif // CHART_DRAWING_MANAGER_MQH
