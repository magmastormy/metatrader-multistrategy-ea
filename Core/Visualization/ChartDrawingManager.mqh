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
    COLOR_SCHEME_BULLISH_PRIMARY = clrLightSkyBlue,
    COLOR_SCHEME_BULLISH_SECONDARY = clrPowderBlue,
    COLOR_SCHEME_BEARISH_PRIMARY = clrLightCoral,
    COLOR_SCHEME_BEARISH_SECONDARY = clrMistyRose,
    COLOR_SCHEME_NEUTRAL = clrGainsboro,
    COLOR_SCHEME_SUPPLY = clrSalmon,
    COLOR_SCHEME_DEMAND = clrPaleGreen,
    COLOR_SCHEME_ORDERBLOCK_BULL = color(0xC8C8E8),  // Light periwinkle blue
    COLOR_SCHEME_ORDERBLOCK_BEAR = color(0xE8B8B8),  // Light dusty rose
    COLOR_SCHEME_FVG_BULL = color(0xB8E8D0),         // Light mint green
    COLOR_SCHEME_FVG_BEAR = color(0xE8C8B8),           // Light peach
    COLOR_SCHEME_LIQUIDITY = color(0xE8E0B8),          // Light cream/gold
    COLOR_SCHEME_STRUCTURE_BOS = color(0xE8C0E8),      // Light lavender
    COLOR_SCHEME_STRUCTURE_CHOCH = color(0xE8D0B8),    // Light apricot
    COLOR_SCHEME_ELLIOTT_IMPULSE = clrLightBlue,
    COLOR_SCHEME_ELLIOTT_CORRECTIVE = clrLightSalmon,
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
    // ELLIOTT WAVE REMOVED - Flag deleted
    bool enableTrendLines;        // Trend lines
    bool enableSignalMarkers;     // Entry/Exit markers
    bool enableDebugMode;         // Developer-level visuals
    bool cleanupOldObjects;       // Auto-cleanup obsolete objects
    int maxObjectAge;             // Max age in bars before cleanup
    int maxObjectsPerStrategy;    // Max objects allowed per strategy
    
    SDrawingConfig()
    {
        enableDrawing = true;
        enableStructure = true;
        enableSupportResistance = true;
        enableSupplyDemand = true;
        enableOrderBlocks = true;
        enableFVG = true;
        enableLiquidity = true;
        // ELLIOTT WAVE REMOVED - Initialization deleted
        enableTrendLines = true;
        enableSignalMarkers = true;
        enableDebugMode = false;
        cleanupOldObjects = true;
        maxObjectAge = 150; // Reduced from 500 to prevent excessive object retention
        maxObjectsPerStrategy = 150; // Max objects per strategy
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
    int m_maxObjects;                 // Max objects for this manager (default 900)
    
    // Statistics
    int m_objectsDrawn;
    int m_objectsDeleted;
    datetime m_lastCleanup;
    
    // Dirty flag optimization
    bool m_isDirty;                   // Flag indicating data has changed
    datetime m_lastDirtyTime;         // Last time dirty flag was set
    int m_lastBarDrawn;               // Last bar number when drawing occurred
    
    // Helper methods
    string GenerateObjectName(const string objectType, const string uniqueId);
    string BuildScopedPrefix(const string basePrefix, const string symbol, ENUM_TIMEFRAMES tf);
    bool PrepareSnapshotDraw();
    bool IsObjectOld(const string objName, int maxAge);
    void DeleteOldObjects(const string prefix, int maxAge);
    bool CheckObjectLimitAndCleanup();
    bool ValidateCoordinates(datetime time1, datetime time2, double price1, double price2);
    bool ValidateTime(datetime time);
    bool ValidatePrice(double price);
    
public:
    CChartDrawingManager();
    ~CChartDrawingManager();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES tf, const string prefix = "");
    void SetConfiguration(const SDrawingConfig &config) { m_config = config; }
    void SetMaxObjects(const int maxObjects) { m_maxObjects = MathMax(100, maxObjects); }
    SDrawingConfig GetConfiguration() const { return m_config; }
    
    // Structure Drawing (HH/HL/LH/LL, BOS, CHOCH)
    bool DrawSwingHigh(datetime time, double price, const string label = "HH");
    bool DrawSwingLow(datetime time, double price, const string label = "LL");
    bool DrawBOS(datetime time1, double price1, datetime time2, double price2, bool isBullish);
    bool DrawCHOCH(datetime time1, double price1, datetime time2, double price2, bool isBullish);
    
    // ICT-Specific Drawing Methods
    bool DrawICT_CHOCH(datetime time, double price, bool isBullish, const string htfLabel = "");
    bool DrawICT_SupplyZone(datetime timeStart, datetime timeEnd, double top, double bottom, 
                           const string label = "", int transparency = 85);
    bool DrawICT_DemandZone(datetime timeStart, datetime timeEnd, double top, double bottom,
                           const string label = "", int transparency = 85);
    
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
    
    // ELLIOTT WAVE REMOVED - Wave drawing methods deleted
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
    
    // Pattern Drawing
    bool DrawPattern(const string patternName, datetime &time[], double &price[], int pointCount, color patternColor, int width = 1);
    
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
    
    // Dirty flag optimization
    void SetDirty(bool dirty = true) { m_isDirty = dirty; m_lastDirtyTime = TimeCurrent(); }
    bool IsDirty() const { return m_isDirty; }
    bool ShouldRedraw();
    
    // Statistics logging
    void LogStatistics();
    
    // Object limit checking
    int GetCurrentObjectCount();
    bool IsObjectLimitReached();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CChartDrawingManager::CChartDrawingManager() :
    m_chartID(0),
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_prefix("CHART_"),
    m_maxObjects(450), // Stay under MT5's 500-object limit
    m_objectsDrawn(0),
    m_objectsDeleted(0),
    m_lastCleanup(0),
    m_isDirty(true),
    m_lastDirtyTime(0),
    m_lastBarDrawn(-1)
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

    ChartRedraw(m_chartID);
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
//|                                                                   |
//| LIFECYCLE DOCUMENTATION:                                         |
//| 1. Called at start of every drawing operation                     |
//| 2. Checks per-strategy object limits (maxObjectsPerStrategy)     |
//| 3. Enforces global MT5 1000-object limit via CheckObjectLimit    |
//| 4. Coordinates with DrawingCoordinator for prefix management      |
//|                                                                   |
//| IMPORTANT: This method MUST be called before ANY drawing.         |
//| Failure to call will bypass object limit enforcement.             |
//|                                                                   |
//| COORDINATOR BEHAVIOR:                                            |
//| - PreparePrefixForCurrentBar() deletes ALL objects with prefix  |
//| - This is INTENTIONALLY destructive - it's a per-bar snapshot    |
//| - Ensures no stale objects from previous bars remain              |
//| - Safe to call multiple times (deduplicates by bar time)          |
//+------------------------------------------------------------------+
bool CChartDrawingManager::PrepareSnapshotDraw()
{
    // Check per-strategy object limit before drawing
    if(IsObjectLimitReached())
    {
        // Limit reached - skip drawing and trigger cleanup
        CleanupOldObjects();
        if(m_config.enableDebugMode)
            PrintFormat("[ChartDrawing] Skipping draw - per-strategy limit reached (%s)", m_prefix);
        return false;
    }

    CheckObjectLimitAndCleanup();
    CDrawingCoordinator* coordPtr = GetDrawingCoordinator();
    if(coordPtr != NULL)
    {
        bool result = coordPtr.PreparePrefixForCurrentBar(m_chartID, m_symbol, m_timeframe, m_prefix);
        if(!result)
            return false;
    }
    return true;
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
    ChartRedraw(m_chartID);
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
    ChartRedraw(m_chartID);
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
    ChartRedraw(m_chartID);
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
    ChartRedraw(m_chartID);
    return true;
}

//+------------------------------------------------------------------+
//| Draw ICT Change of Character (CHOCH) - Enhanced Version         |
//| Single-point CHOCH marker with HTF context label                |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawICT_CHOCH(datetime time, double price, bool isBullish, const string htfLabel)
{
    if(!m_config.enableDrawing || !m_config.enableStructure)
        return false;

    PrepareSnapshotDraw();
    
    // Generate unique object name
    string objName = GenerateObjectName("ICT_CHOCH", TimeToString(time));
    
    // Draw arrow marker at CHOCH point
    int arrowCode = isBullish ? 233 : 234;  // Up/Down arrows
    ObjectCreate(m_chartID, objName, OBJ_ARROW, 0, time, price);
    ObjectSetInteger(m_chartID, objName, OBJPROP_ARROWCODE, arrowCode);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, COLOR_SCHEME_STRUCTURE_CHOCH);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 4);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, false);
    
    // Draw CHOCH label with optional HTF context
    string labelName = objName + "_LABEL";
    string labelText = isBullish ? "CHOCH↑" : "CHOCH↓";
    if(htfLabel != "")
        labelText += " [" + htfLabel + "]";
    
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, time, price);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, labelText);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, COLOR_SCHEME_STRUCTURE_CHOCH);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 10);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, isBullish ? ANCHOR_BOTTOM : ANCHOR_TOP);

    m_objectsDrawn += 2;
    ChartRedraw(m_chartID);
    return true;
}

//+------------------------------------------------------------------+
//| Draw ICT Supply Zone - Bearish Rejection Area                   |
//| Visual: Salmon-colored rectangle with transparency              |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawICT_SupplyZone(datetime timeStart, datetime timeEnd, double top, double bottom,
                                             const string label, int transparency)
{
    if(!m_config.enableDrawing || !m_config.enableSupplyDemand)
        return false;
    
    // Validate coordinates
    if(!ValidateCoordinates(timeStart, timeEnd, bottom, top))
        return false;
    
    PrepareSnapshotDraw();
    
    string zoneLabel = (label != "") ? "SUPPLY_" + label : "SUPPLY";
    string objName = GenerateObjectName("SUPPLY", zoneLabel + "_" + TimeToString(timeStart));
    
    // Draw supply zone rectangle
    ObjectCreate(m_chartID, objName, OBJ_RECTANGLE, 0, timeStart, top, timeEnd, bottom);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, COLOR_SCHEME_SUPPLY);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(m_chartID, objName, OBJPROP_FILL, true);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, true);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BGCOLOR, COLOR_SCHEME_SUPPLY);
    
    // Add zone label
    string labelName = objName + "_LABEL";
    datetime midTime = (datetime)((timeStart + timeEnd) / 2);
    double midPrice = (top + bottom) / 2;
    
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, midTime, midPrice);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, "SUPPLY");
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_CENTER);
    
    m_objectsDrawn += 2;
    ChartRedraw(m_chartID);
    return true;
}

//+------------------------------------------------------------------+
//| Draw ICT Demand Zone - Bullish Support Area                     |
//| Visual: Pale green-colored rectangle with transparency          |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawICT_DemandZone(datetime timeStart, datetime timeEnd, double top, double bottom,
                                             const string label, int transparency)
{
    if(!m_config.enableDrawing || !m_config.enableSupplyDemand)
        return false;
    
    // Validate coordinates
    if(!ValidateCoordinates(timeStart, timeEnd, bottom, top))
        return false;
    
    PrepareSnapshotDraw();
    
    string zoneLabel = (label != "") ? "DEMAND_" + label : "DEMAND";
    string objName = GenerateObjectName("DEMAND", zoneLabel + "_" + TimeToString(timeStart));
    
    // Draw demand zone rectangle
    ObjectCreate(m_chartID, objName, OBJ_RECTANGLE, 0, timeStart, top, timeEnd, bottom);
    ObjectSetInteger(m_chartID, objName, OBJPROP_COLOR, COLOR_SCHEME_DEMAND);
    ObjectSetInteger(m_chartID, objName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(m_chartID, objName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(m_chartID, objName, OBJPROP_FILL, true);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BACK, true);
    ObjectSetInteger(m_chartID, objName, OBJPROP_BGCOLOR, COLOR_SCHEME_DEMAND);
    
    // Add zone label
    string labelName = objName + "_LABEL";
    datetime midTime = (datetime)((timeStart + timeEnd) / 2);
    double midPrice = (top + bottom) / 2;
    
    ObjectCreate(m_chartID, labelName, OBJ_TEXT, 0, midTime, midPrice);
    ObjectSetString(m_chartID, labelName, OBJPROP_TEXT, "DEMAND");
    ObjectSetInteger(m_chartID, labelName, OBJPROP_COLOR, clrBlack);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_FONTSIZE, 9);
    ObjectSetInteger(m_chartID, labelName, OBJPROP_ANCHOR, ANCHOR_CENTER);
    
    m_objectsDrawn += 2;
    ChartRedraw(m_chartID);
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
        if(m_config.enableDebugMode)
            Print("[ChartDrawing] Drawing disabled - skipping zone: ", label);
        return false;
    }

    // Validate coordinates
    if(!ValidateCoordinates(timeStart, timeEnd, priceLow, priceHigh))
    {
        if(m_config.enableDebugMode)
            Print("[ChartDrawing] Invalid coordinates for zone: ", label);
        return false;
    }

    PrepareSnapshotDraw();
    
    string objName = GenerateObjectName("ZONE", label + "_" + TimeToString(timeStart));
    if(m_config.enableDebugMode)
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
    ChartRedraw(m_chartID);
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
    ChartRedraw(m_chartID);
    return true;
}

//+------------------------------------------------------------------+
//| Cleanup Old Objects                                             |
//|                                                                   |
//| WHEN TO CALL:                                                    |
//| - In OnNewBar() for regular incremental cleanup                  |
//| - In OnTick() for time-based cleanup (e.g., every 5 minutes)     |
//| - In Deinit() for complete cleanup                               |
//|                                                                   |
//| BEHAVIOR:                                                        |
//| - Only runs if cleanupOldObjects config is enabled                |
//| - Rate-limited to once per minute (prevents excessive calls)      |
//| - Deletes objects older than maxObjectAge bars                    |
//| - Uses prefix to scope cleanup to this manager's objects          |
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

    for(int i = totalObjects - 1; i >= 0; i--)
    {
        string objName = ObjectName(m_chartID, i);
        if(StringFind(objName, prefix) == 0)  // Starts with prefix
        {
            if(maxAge > 0)
            {
                datetime objTime = (datetime)ObjectGetInteger(m_chartID, objName, OBJPROP_TIME);
                int objBar = iBarShift(m_symbol, m_timeframe, objTime);
                if(objBar > maxAge)
                {
                    ObjectDelete(m_chartID, objName);
                    m_objectsDeleted++;
                }
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
bool CChartDrawingManager::CheckObjectLimitAndCleanup()
{
    int totalObjects = ObjectsTotal(m_chartID);
    if(totalObjects < m_maxObjects)
        return true;
    
    // Need to clean up oldest objects
    int objectsToDelete = totalObjects - (m_maxObjects - 100); // Keep buffer of 100
    
    // Collect objects by time (oldest first)
    struct ObjectInfo
    {
        string name;
        datetime time;
    };
    ObjectInfo objects[];
    int count = 0;
    
    for(int i = 0; i < ObjectsTotal(m_chartID); i++)
    {
        string name = ObjectName(m_chartID, i);
        if(StringFind(name, m_prefix) == 0)
        {
            datetime time = (datetime)ObjectGetInteger(m_chartID, name, OBJPROP_TIME);
            ArrayResize(objects, count + 1);
            objects[count].name = name;
            objects[count].time = time;
            count++;
        }
    }
    
    // Sort by time (oldest first)
    for(int i = 0; i < count - 1; i++)
    {
        for(int j = i + 1; j < count; j++)
        {
            if(objects[i].time > objects[j].time)
            {
                ObjectInfo temp = objects[i];
                objects[i] = objects[j];
                objects[j] = temp;
            }
        }
    }
    
    // Delete oldest objects
    int deleted = 0;
    for(int i = 0; i < count && deleted < objectsToDelete; i++)
    {
        if(ObjectDelete(m_chartID, objects[i].name))
        {
            m_objectsDeleted++;
            deleted++;
        }
    }
    
    return true;
}

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

    ChartRedraw(m_chartID);
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

    ChartRedraw(m_chartID);
    return true;
}

//+------------------------------------------------------------------+
//| Draw Wave Count                                                 |
// ELLIOTT WAVE REMOVED - Method deleted
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawWaveCount(datetime time, double price, int waveNumber, bool isImpulse)
{
    // ELLIOTT WAVE REMOVED - Returns false
    return false;
}

//+------------------------------------------------------------------+
//| Draw Wave Label                                                 |
// ELLIOTT WAVE REMOVED - Method deleted
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawWaveLabel(datetime time, double price, const string label, bool isImpulse)
{
    // ELLIOTT WAVE REMOVED - Returns false
    return false;
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Projection                                       |
// ELLIOTT WAVE REMOVED - Method deleted
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawFibProjection(datetime time1, double price1, datetime time2, double price2, datetime time3, double price3)
{
    // ELLIOTT WAVE REMOVED - Returns false
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
    ChartRedraw(m_chartID);
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
    ChartRedraw(m_chartID);
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
    ChartRedraw(m_chartID);
    return true;
}

//+------------------------------------------------------------------+
//| Draw Pattern (Generic polyline for sketches/diagrams)           |
//+------------------------------------------------------------------+
bool CChartDrawingManager::DrawPattern(const string patternName, datetime &time[], double &price[], int pointCount, color patternColor, int width)
{
    if(!m_config.enableDrawing || pointCount < 2)
        return false;

    PrepareSnapshotDraw();
    
    bool success = true;
    for(int i = 0; i < pointCount - 1; i++)
    {
        string segName = GenerateObjectName(patternName, IntegerToString(i));
        if(!ObjectCreate(m_chartID, segName, OBJ_TREND, 0, time[i], price[i], time[i+1], price[i+1]))
        {
            success = false;
            continue;
        }
        
        ObjectSetInteger(m_chartID, segName, OBJPROP_COLOR, patternColor);
        ObjectSetInteger(m_chartID, segName, OBJPROP_WIDTH, width);
        ObjectSetInteger(m_chartID, segName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(m_chartID, segName, OBJPROP_RAY_RIGHT, false);
        m_objectsDrawn++;
    }

    ChartRedraw(m_chartID);
    return success;
}

//+------------------------------------------------------------------+
//| Validate time value                                              |
//+------------------------------------------------------------------+
bool CChartDrawingManager::ValidateTime(datetime time)
{
    return (time > 0 && time <= TimeCurrent() + 86400); // Valid time range
}

//+------------------------------------------------------------------+
//| Validate price value                                             |
//+------------------------------------------------------------------+
bool CChartDrawingManager::ValidatePrice(double price)
{
    if(price <= 0)
        return false;
    
    // Check for NaN or infinity using MQL5 built-in checks
    if(price != price || MathAbs(price) > 1e308)
        return false;
    
    // Check for reasonable price range (0.00001 to 1000000)
    return (price >= 0.00001 && price <= 1000000.0);
}

//+------------------------------------------------------------------+
//| Validate coordinates for drawing                                 |
//+------------------------------------------------------------------+
bool CChartDrawingManager::ValidateCoordinates(datetime time1, datetime time2, double price1, double price2)
{
    if(!ValidateTime(time1))
    {
        if(m_config.enableDebugMode)
            Print("[ChartDrawing] Invalid time1: ", time1);
        return false;
    }
    
    if(!ValidateTime(time2))
    {
        if(m_config.enableDebugMode)
            Print("[ChartDrawing] Invalid time2: ", time2);
        return false;
    }
    
    if(!ValidatePrice(price1))
    {
        if(m_config.enableDebugMode)
            Print("[ChartDrawing] Invalid price1: ", price1);
        return false;
    }
    
    if(!ValidatePrice(price2))
    {
        if(m_config.enableDebugMode)
            Print("[ChartDrawing] Invalid price2: ", price2);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if redraw is needed (dirty flag optimization)              |
//+------------------------------------------------------------------+
bool CChartDrawingManager::ShouldRedraw()
{
    if(!m_config.enableDrawing)
        return false;
    
    int currentBar = iBarShift(m_symbol, m_timeframe, TimeCurrent());
    
    // Force redraw if dirty flag is set
    if(m_isDirty)
    {
        m_isDirty = false;
        m_lastBarDrawn = currentBar;
        return true;
    }
    
    // Force redraw if bar has changed since last draw
    if(currentBar != m_lastBarDrawn)
    {
        m_lastBarDrawn = currentBar;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Log drawing statistics                                           |
//+------------------------------------------------------------------+
void CChartDrawingManager::LogStatistics()
{
    int currentObjects = ObjectsTotal(m_chartID);
    int ourObjects = 0;
    
    // Count objects with our prefix
    for(int i = 0; i < currentObjects; i++)
    {
        string objName = ObjectName(m_chartID, i);
        if(StringFind(objName, m_prefix) == 0)
            ourObjects++;
    }
    
    PrintFormat("[ChartDrawing] Stats | Symbol: %s | TF: %s | Prefix: %s",
                m_symbol, EnumToString(m_timeframe), m_prefix);
    PrintFormat("[ChartDrawing] Stats | Objects Drawn: %d | Objects Deleted: %d",
                m_objectsDrawn, m_objectsDeleted);
    PrintFormat("[ChartDrawing] Stats | Current Managed Objects: %d | Total Chart Objects: %d",
                ourObjects, currentObjects);
    PrintFormat("[ChartDrawing] Stats | Max Age: %d bars | Dirty: %s | Last Cleanup: %s",
                m_config.maxObjectAge, m_isDirty ? "Yes" : "No", TimeToString(m_lastCleanup));
}

//+------------------------------------------------------------------+
//| Get current count of objects managed by this manager             |
//+------------------------------------------------------------------+
int CChartDrawingManager::GetCurrentObjectCount()
{
    int count = 0;
    int totalObjects = ObjectsTotal(m_chartID);
    
    for(int i = 0; i < totalObjects; i++)
    {
        string objName = ObjectName(m_chartID, i);
        if(StringFind(objName, m_prefix) == 0)
            count++;
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Check if per-strategy object limit is reached                    |
//+------------------------------------------------------------------+
bool CChartDrawingManager::IsObjectLimitReached()
{
    int currentCount = GetCurrentObjectCount();
    
    if(currentCount >= m_config.maxObjectsPerStrategy)
    {
        if(m_config.enableDebugMode)
            PrintFormat("[ChartDrawing] Object limit reached: %d/%d (strategy: %s)",
                       currentCount, m_config.maxObjectsPerStrategy, m_prefix);
        return true;
    }
    
    // Warn at 80% of limit
    if(currentCount >= m_config.maxObjectsPerStrategy * 0.8)
    {
        if(m_config.enableDebugMode)
            PrintFormat("[ChartDrawing] Object limit approaching: %d/%d (strategy: %s)",
                       currentCount, m_config.maxObjectsPerStrategy, m_prefix);
    }
    
    return false;
}

#endif // CHART_DRAWING_MANAGER_MQH
