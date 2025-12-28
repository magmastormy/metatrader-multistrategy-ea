//+------------------------------------------------------------------+
//| StrategySMC.mqh                                                  |
//| Advanced Smart Money Concepts Strategy                           |
//| Implements: Order Blocks, FVG, Supply/Demand, Liquidity Sweeps   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced AI Coding Assistant"
#property version   "1.00"
#property strict

#include "../Core/Strategy/StrategyBase.mqh"
#include <Arrays/ArrayObj.mqh>
#include "../Core/Engines/ConfluenceEngine.mqh"
#include "../Core/Signals/SignalDiagnostics.mqh"
#include "../Core/Signals/TimeframeConsistency.mqh"
#include "../Core/Engines/StructureEngine.mqh"
#include "../Core/Engines/TrendEngine.mqh"
#include "../Core/Engines/LiquidityEngine.mqh"
#include "../Core/Engines/VolatilityEngine.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"

//+------------------------------------------------------------------+
//| SMC Zone Types                                                   |
//+------------------------------------------------------------------+
enum ENUM_SMC_ZONE_TYPE
{
    SMC_ZONE_ORDER_BLOCK,
    SMC_ZONE_FVG,
    SMC_ZONE_SUPPLY_DEMAND,
    SMC_ZONE_LIQUIDITY_SWEEP
};

//+------------------------------------------------------------------+
//| SMC Zone Class                                                   |
//+------------------------------------------------------------------+
class CSMCZone : public CObject
{
public:
    ENUM_SMC_ZONE_TYPE type;
    datetime           createdTime;
    double             top;
    double             bottom;
    bool               isBullish;
    bool               mitigated;
    double             score;
    int                rejections;
    string             id;

    CSMCZone() : type(SMC_ZONE_ORDER_BLOCK), createdTime(0), top(0), bottom(0), 
                 isBullish(false), mitigated(false), score(0), rejections(0) {}
                 
    CSMCZone(ENUM_SMC_ZONE_TYPE _type, datetime _time, double _top, double _bottom, bool _bullish) :
        type(_type), createdTime(_time), top(_top), bottom(_bottom), 
        isBullish(_bullish), mitigated(false), score(0), rejections(0) 
    {
        id = StringFormat("SMC_%d_%d", _type, _time);
    }
};

//+------------------------------------------------------------------+
//| Advanced SMC Strategy Class                                      |
//+------------------------------------------------------------------+
class CStrategySMC : public CStrategyBase
{
private:
    // Parameters
    double    m_obMomentumFactor;
    int       m_obMaxConsolidation;
    int       m_lookbackAvgBody;
    int       m_obMinDisplacement;
    int       m_zoneMaxAge;
    double    m_scoreThreshold;
    bool      m_useHTFBias;
    ENUM_TIMEFRAMES m_htfTimeframe;
    bool      m_entryAggressive;
    bool      m_considerFVG;
    int       m_fvgMinSize;
    double    m_spreadBuffer;
    
    // State
    CArrayObj m_zones;
    int       m_lastProcessedBar;
    ENUM_TRADING_MODE m_currentMode;
    CConfluenceEngine m_confluenceEngine;
    CSignalDiagnostics* m_diagnostics;
    CTimeframeConsistency* m_tfConsistency;
    CStructureEngine* m_structureEngine;
    CTrendEngine* m_trendEngine;
    CLiquidityEngine* m_liquidityEngine;
    CVolatilityEngine* m_volatilityEngine;
    CChartDrawingManager* m_drawer;  // Visualization manager
    
    // Statistics
    int       m_zonesDetected;
    int       m_signalsGenerated;
    int       m_mitigationsTracked;
    
    // Helper methods
    double    GetAvgBodySize(int bars);
    bool      IsDisplacement(int barIndex, double avgBody);
    void      ScanForOrderBlocks();
    void      ScanForFVG();
    void      ScanForSweeps();
    int       ComputeHTFBias();
    void      UpdateZoneScores();
    void      DrawZone(CSMCZone* zone);
    void      RemoveOldZones();
    
public:
    CStrategySMC();
    ~CStrategySMC();
    
    // IStrategy implementation
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    virtual void OnTick() override;
    virtual double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual string GetName() const override { return "Advanced SMC Strategy"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_SMC; }
    
    // Configuration
    void SetParameters(double momentum, int consolidation, int lookback, int displacement, 
                      int maxAge, double threshold, bool useHTF, ENUM_TIMEFRAMES htfTF);
                      
    void SetMode(ENUM_TRADING_MODE mode) { m_currentMode = mode; }
    
    // Additional methods
    double GetSignalValueInternal() const;
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategySMC::CStrategySMC() :
    CStrategyBase("Advanced SMC Strategy", 0),
    m_obMomentumFactor(2.0),
    m_obMaxConsolidation(3),
    m_lookbackAvgBody(20),
    m_obMinDisplacement(30),
    m_zoneMaxAge(500),
    m_scoreThreshold(40.0),
    m_useHTFBias(true),
    m_htfTimeframe(PERIOD_D1),
    m_entryAggressive(false),
    m_considerFVG(true),
    m_fvgMinSize(10),
    m_spreadBuffer(2.0),
    m_lastProcessedBar(-1),
    m_diagnostics(NULL),
    m_tfConsistency(NULL),
    m_structureEngine(NULL),
    m_trendEngine(NULL),
    m_liquidityEngine(NULL),
    m_volatilityEngine(NULL),
    m_zonesDetected(0),
    m_signalsGenerated(0),
    m_mitigationsTracked(0)
{
    m_zones.FreeMode(true);
    
    // Initialize diagnostics
    m_diagnostics = new CSignalDiagnostics();
    if(m_diagnostics != NULL)
        m_diagnostics.Initialize(1000, 3);
        
    // Initialize TF consistency
    m_tfConsistency = new CTimeframeConsistency();
    if(m_tfConsistency != NULL)
        m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false);
        
    // Initialize enterprise engines
    m_structureEngine = new CStructureEngine();
    if(m_structureEngine != NULL)
        m_structureEngine.Initialize(10, 10.0, true, m_diagnostics);
        
    m_trendEngine = new CTrendEngine();
    if(m_trendEngine != NULL)
        m_trendEngine.Initialize(20, 50, 200, 14, m_diagnostics);
        
    m_liquidityEngine = new CLiquidityEngine();
    if(m_liquidityEngine != NULL)
        m_liquidityEngine.Initialize(10.0, 2, m_diagnostics);
        
    m_volatilityEngine = new CVolatilityEngine();
    if(m_volatilityEngine != NULL)
        m_volatilityEngine.Initialize(14, 20, m_diagnostics);
    
    // Initialize visualization manager
    m_drawer = new CChartDrawingManager();
    if(m_drawer != NULL)
    {
        SDrawingConfig config;
        config.enableDrawing = true;
        config.enableOrderBlocks = true;
        config.enableFVG = true;
        config.enableSupplyDemand = true;
        m_drawer.SetConfiguration(config);
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategySMC::~CStrategySMC()
{
    Deinit();
    
    if(m_diagnostics != NULL)
    {
        delete m_diagnostics;
        m_diagnostics = NULL;
    }
    
    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }
    
    // Clean up enterprise engines
    if(m_structureEngine != NULL)
    {
        delete m_structureEngine;
        m_structureEngine = NULL;
    }
    
    if(m_trendEngine != NULL)
    {
        delete m_trendEngine;
        m_trendEngine = NULL;
    }
    
    if(m_liquidityEngine != NULL)
    {
        delete m_liquidityEngine;
        m_liquidityEngine = NULL;
    }
    
    if(m_volatilityEngine != NULL)
    {
        delete m_volatilityEngine;
        m_volatilityEngine = NULL;
    }
    
    if(m_drawer != NULL)
    {
        delete m_drawer;
        m_drawer = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategySMC::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;
        
    m_zones.Clear();
    m_lastProcessedBar = -1;
    
    // Initialize visualization manager
    if(m_drawer != NULL)
    {
        m_drawer.Initialize(symbol, timeframe, "SMC");
    }
    
    // Log initialization
    if(m_diagnostics != NULL)
    {
        string msg = StringFormat("SMC Strategy initialized for %s on %s", 
                                symbol, EnumToString(timeframe));
        Print("[SMC] ", msg);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategySMC::Deinit()
{
    ObjectsDeleteAll(0, "SMC_");
    m_zones.Clear();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| OnTick Processing                                                |
//+------------------------------------------------------------------+
void CStrategySMC::OnTick()
{
    if(!m_is_enabled) return;
    
    // Real-time zone interaction check could go here
    // For now, we rely on GetSignal called by the engine
}

//+------------------------------------------------------------------+
//| OnNewBar Processing                                              |
//+------------------------------------------------------------------+
void CStrategySMC::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol != m_symbol || timeframe != m_timeframe) return;
    
    // Log new bar processing
    if(m_diagnostics != NULL)
    {
        Print("[SMC] Processing new bar for ", symbol, " on ", EnumToString(timeframe));
    }
    
    int zonesBefore = m_zones.Total();
    
    ScanForOrderBlocks();
    if(m_considerFVG) ScanForFVG();
    ScanForSweeps();
    RemoveOldZones();
    
    int zonesAfter = m_zones.Total();
    
    if(m_diagnostics != NULL && zonesAfter != zonesBefore)
    {
        Print("[SMC] Zone count changed: ", zonesBefore, " -> ", zonesAfter);
    }
}

//+------------------------------------------------------------------+
//| Get Signal                                                       |
//+------------------------------------------------------------------+
double CStrategySMC::GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    // Update all engines first
    if(m_structureEngine != NULL)
        m_structureEngine.DetectSwingPoints(symbol, timeframe);
        
    if(m_trendEngine != NULL)
        m_trendEngine.UpdateTrend(symbol, timeframe);
        
    if(m_liquidityEngine != NULL)
        m_liquidityEngine.DetectLiquidityZones(symbol, timeframe);
        
    if(m_volatilityEngine != NULL)
        m_volatilityEngine.UpdateVolatility(symbol, timeframe);
        
    return GetSignalValueInternal();
}


//+------------------------------------------------------------------+
//| Helper: Get Average Body Size                                    |
//+------------------------------------------------------------------+
double CStrategySMC::GetAvgBodySize(int bars)
{
    double sum = 0;
    for(int i = 1; i <= bars; i++)
    {
        sum += MathAbs(iOpen(m_symbol, m_timeframe, i) - iClose(m_symbol, m_timeframe, i));
    }
    return sum / bars;
}

//+------------------------------------------------------------------+
//| Helper: Check for Displacement                                   |
//+------------------------------------------------------------------+
bool CStrategySMC::IsDisplacement(int barIndex, double avgBody)
{
    double body = MathAbs(iOpen(m_symbol, m_timeframe, barIndex) - iClose(m_symbol, m_timeframe, barIndex));
    return (body >= m_obMomentumFactor * avgBody);
}

//+------------------------------------------------------------------+
//| Scan for Order Blocks                                            |
//+------------------------------------------------------------------+
void CStrategySMC::ScanForOrderBlocks()
{
    int bars = iBars(m_symbol, m_timeframe);
    if(bars < m_lookbackAvgBody + 5)
    {
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("SMC", "INSUFFICIENT_BARS", 
                                          StringFormat("Need %d bars, have %d", m_lookbackAvgBody + 5, bars));
        return;
    }
    
    int startBar = (m_lastProcessedBar == -1) ? MathMin(50, bars - m_lookbackAvgBody - 1) : 1;
    int endBar = 1; // Only check recent closed bars
    
    double avgBody = GetAvgBodySize(m_lookbackAvgBody);
    if(avgBody <= 0)
    {
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("SMC", "INVALID_AVG_BODY", "Average body size is zero or negative");
        return;
    }
    
    int obDetected = 0;
    
    for(int i = startBar; i >= endBar; i--)
    {
        if(IsDisplacement(i, avgBody))
        {
            // Found displacement, look for consolidation before it
            bool isBullishDisplacement = (iClose(m_symbol, m_timeframe, i) > iOpen(m_symbol, m_timeframe, i));
            
            // Identify OB candle(s)
            int obIndex = i + 1;
            double obHigh = iHigh(m_symbol, m_timeframe, obIndex);
            double obLow = iLow(m_symbol, m_timeframe, obIndex);
            
            // Create OB Zone
            CSMCZone* zone = new CSMCZone(SMC_ZONE_ORDER_BLOCK, iTime(m_symbol, m_timeframe, obIndex), obHigh, obLow, isBullishDisplacement);
            
            // Initial Score
            zone.score = 50; // Base score
            
            // HTF Bias
            if(m_useHTFBias)
            {
                int bias = ComputeHTFBias();
                if((bias > 0 && zone.isBullish) || (bias < 0 && !zone.isBullish))
                    zone.score += 20;
            }
            
            // Enhanced Order Block detection with structure
            // Base scoring for order block
            zone.score += 30.0;
            
            // Extra points if structure confirms
            if(m_structureEngine != NULL && m_structureEngine.HasBullishBOS(3))
                zone.score += 15.0;
            
            m_zones.Add(zone);
            DrawZone(zone);
            obDetected++;
            
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection(
                    "ORDER_BLOCK",
                    m_symbol,
                    (obHigh + obLow) / 2.0,
                    obHigh,
                    obLow,
                    isBullishDisplacement,
                    zone.score
                );
            }
        }
    }
    
    if(m_diagnostics != NULL && obDetected > 0)
    {
        Print("[SMC] Detected ", obDetected, " new Order Blocks");
    }
}

//+------------------------------------------------------------------+
//| Scan for Fair Value Gaps                                         |
//+------------------------------------------------------------------+
void CStrategySMC::ScanForFVG()
{
    // 3-candle pattern
    // Bullish FVG: Low[i+1] > High[i-1] (Gap between 1st and 3rd candle)
    // Bearish FVG: High[i+1] < Low[i-1]
    
    int i = 1; // Current closed bar is i, previous is i+1, pre-previous is i+2
    
    double highA = iHigh(m_symbol, m_timeframe, i+2);
    double lowA = iLow(m_symbol, m_timeframe, i+2);
    double highC = iHigh(m_symbol, m_timeframe, i);
    double lowC = iLow(m_symbol, m_timeframe, i);
    
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) 
    {
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("SMC", "INVALID_POINT", "Point value is zero or negative");
        return;
    }
    
    int fvgDetected = 0;
    
    // Bullish FVG
    if(lowA > highC)
    {
        double gapSize = (lowA - highC) / point;
        if(gapSize >= m_fvgMinSize)
        {
            CSMCZone* zone = new CSMCZone(SMC_ZONE_FVG, iTime(m_symbol, m_timeframe, i+1), lowA, highC, true);
            zone.score = 40;
            m_zones.Add(zone);
            DrawZone(zone);
            fvgDetected++;
            
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection(
                    "FVG",
                    m_symbol,
                    (lowA + highC) / 2.0,
                    lowA,
                    highC,
                    true,
                    zone.score
                );
            }
        }
    }
    
    // Bearish FVG
    if(highA < lowC)
    {
        double gapSize = (lowC - highA) / point;
        if(gapSize >= m_fvgMinSize)
        {
            CSMCZone* zone = new CSMCZone(SMC_ZONE_FVG, iTime(m_symbol, m_timeframe, i+1), highA, lowC, false);
            zone.score = 40;
            m_zones.Add(zone);
            DrawZone(zone);
            fvgDetected++;
            
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection(
                    "FVG",
                    m_symbol,
                    (highA + lowC) / 2.0,
                    highA,
                    lowC,
                    false,
                    zone.score
                );
            }
        }
    }
    
    if(m_diagnostics != NULL && fvgDetected > 0)
    {
        Print("[SMC] Detected ", fvgDetected, " new Fair Value Gaps");
    }
}

//+------------------------------------------------------------------+
//| Scan for Liquidity Sweeps                                        |
//+------------------------------------------------------------------+
void CStrategySMC::ScanForSweeps()
{
    // Look for liquidity sweeps
    int lookback = 20;
    int bars = iBars(m_symbol, m_timeframe);
    
    if(bars < lookback + 2)
    {
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("SMC", "INSUFFICIENT_BARS_SWEEP", "Not enough bars for sweep detection");
        return;
    }
    
    // Find recent swing highs/lows
    for(int i = 2; i < lookback && i < bars - 1; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double high1 = iHigh(m_symbol, m_timeframe, 1);
        double low1 = iLow(m_symbol, m_timeframe, 1);
        double close1 = iClose(m_symbol, m_timeframe, 1);
        
        // Check for sweep of previous high
        bool isSwingHigh = (high > iHigh(m_symbol, m_timeframe, i-1) && high > iHigh(m_symbol, m_timeframe, i+1));
        if(isSwingHigh && high1 > high && close1 < high)
        {
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection(
                    "LIQUIDITY_SWEEP",
                    m_symbol,
                    high,
                    high1,
                    high,
                    false,
                    60
                );
            }
        }
        
        // Check for sweep of previous low
        bool isSwingLow = (low < iLow(m_symbol, m_timeframe, i-1) && low < iLow(m_symbol, m_timeframe, i+1));
        if(isSwingLow && low1 < low && close1 > low)
        {
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection(
                    "LIQUIDITY_SWEEP",
                    m_symbol,
                    low,
                    low,
                    low1,
                    true,
                    60
                );
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Compute HTF Bias                                                 |
//+------------------------------------------------------------------+
int CStrategySMC::ComputeHTFBias()
{
    // Simple MA cross on HTF
    // Note: In MQL5 iMA returns a handle, we need to use CopyBuffer
    // For simplicity in this strategy, we'll use iMA on the current symbol/htf
    // But iMA returns a handle, so we need to get the values
    
    int maFastHandle = iMA(m_symbol, m_htfTimeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
    int maSlowHandle = iMA(m_symbol, m_htfTimeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
    
    double fastVal[], slowVal[];
    ArraySetAsSeries(fastVal, true);
    ArraySetAsSeries(slowVal, true);
    
    if(CopyBuffer(maFastHandle, 0, 0, 1, fastVal) <= 0 || CopyBuffer(maSlowHandle, 0, 0, 1, slowVal) <= 0)
    {
        IndicatorRelease(maFastHandle);
        IndicatorRelease(maSlowHandle);
        return 0;
    }
    
    double maFast = fastVal[0];
    double maSlow = slowVal[0];
    
    IndicatorRelease(maFastHandle);
    IndicatorRelease(maSlowHandle);
    
    if(maFast > maSlow) return 1;
    if(maFast < maSlow) return -1;
    return 0;
}

//+------------------------------------------------------------------+
//| Draw Zone on Chart                                               |
//+------------------------------------------------------------------+
void CStrategySMC::DrawZone(CSMCZone* zone)
{
    if(zone == NULL) return;
    
    // Use ChartDrawingManager if available
    if(m_drawer != NULL)
    {
        datetime timeEnd = TimeCurrent();
        string label = zone.id;
        color zoneColor = zone.isBullish ? (color)COLOR_SCHEME_ORDERBLOCK_BULL : (color)COLOR_SCHEME_ORDERBLOCK_BEAR;
        
        if(zone.type == SMC_ZONE_ORDER_BLOCK)
        {
            m_drawer.DrawOrderBlock(zone.createdTime, timeEnd, zone.top, zone.bottom, 
                                   zone.isBullish, zone.score / 100.0, zone.id);
        }
        else if(zone.type == SMC_ZONE_FVG)
        {
            m_drawer.DrawFVG(zone.createdTime, timeEnd, zone.top, zone.bottom, 
                           zone.isBullish, true, zone.id);
        }
        else
        {
            m_drawer.DrawZone(zone.createdTime, timeEnd, zone.top, zone.bottom, 
                            label, zoneColor, true, 85);
        }
    }
    else
    {
        // Fallback to direct object creation
        string name = zone.id;
        color zoneColor = zone.isBullish ? clrGreen : clrRed;
        
        if(ObjectFind(0, name) < 0)
        {
            ObjectCreate(0, name, OBJ_RECTANGLE, 0, zone.createdTime, zone.top, TimeCurrent(), zone.bottom);
            ObjectSetInteger(0, name, OBJPROP_COLOR, zoneColor);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
        }
        else
        {
            ObjectSetInteger(0, name, OBJPROP_TIME, 1, TimeCurrent());
        }
    }
}

//+------------------------------------------------------------------+
//| Remove Old Zones                                                 |
//+------------------------------------------------------------------+
void CStrategySMC::RemoveOldZones()
{
    int total = m_zones.Total();
    for(int i = total - 1; i >= 0; i--)
    {
        CSMCZone* zone = (CSMCZone*)m_zones.At(i);
        // Correct iBars signature: iBars(symbol, timeframe) returns total bars
        // To get bars between times, we use Bars(symbol, timeframe, start, end)
        int age = Bars(m_symbol, m_timeframe, zone.createdTime, TimeCurrent());
        
        if(age > m_zoneMaxAge || zone.mitigated)
        {
            ObjectDelete(0, zone.id);
            m_zones.Delete(i);
        }
    }
}

//+------------------------------------------------------------------+
//| Configuration                                                    |
//+------------------------------------------------------------------+
void CStrategySMC::SetParameters(double momentum, int consolidation, int lookback, int displacement, 
                                int maxAge, double threshold, bool useHTF, ENUM_TIMEFRAMES htfTF)
{
    m_obMomentumFactor = momentum;
    m_obMaxConsolidation = consolidation;
    m_lookbackAvgBody = lookback;
    m_obMinDisplacement = displacement;
    m_zoneMaxAge = maxAge;
    m_scoreThreshold = threshold;
    m_useHTFBias = useHTF;
    m_htfTimeframe = htfTF;
}

//+------------------------------------------------------------------+
//| Get Signal - PROPER SMC LOGIC                                    |
//| Bullish OB (Demand): Price retraces DOWN into zone, then BUY     |
//| Bearish OB (Supply): Price retraces UP into zone, then SELL      |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategySMC::GetSignal(double &confidence)
{
    confidence = 0.0;
    
    if(!m_is_enabled || m_zones.Total() == 0)
        return TRADE_SIGNAL_NONE;
    
    double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    // Get ATR for calculations
    int atrHandle = iATR(m_symbol, m_timeframe, 14);
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    double atr = 0.0;
    if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
        atr = atrBuffer[0];
    if(atr <= 0) atr = (ask - bid) * 100;
    IndicatorRelease(atrHandle);
    
    // Get recent price action for direction and confirmation analysis
    double close0 = iClose(m_symbol, m_timeframe, 0); // Current
    double close1 = iClose(m_symbol, m_timeframe, 1); // Last closed
    double close2 = iClose(m_symbol, m_timeframe, 2);
    double open1 = iOpen(m_symbol, m_timeframe, 1);
    double high1 = iHigh(m_symbol, m_timeframe, 1);
    double low1 = iLow(m_symbol, m_timeframe, 1);
    double high2 = iHigh(m_symbol, m_timeframe, 2);
    double low2 = iLow(m_symbol, m_timeframe, 2);
    double open2 = iOpen(m_symbol, m_timeframe, 2);
    double close3 = iClose(m_symbol, m_timeframe, 3);
    
    // Determine recent price direction (is price falling or rising into potential zones?)
    bool priceWasFalling = (close2 > close1) || (close3 > close2 && close2 > close1);
    bool priceWasRising = (close2 < close1) || (close3 < close2 && close2 < close1);
    
    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    double bestConfidence = 0.0;
    string bestZoneInfo = "";
    
    // Process each zone
    for(int i = 0; i < m_zones.Total(); i++)
    {
        CSMCZone* zone = (CSMCZone*)m_zones.At(i);
        if(zone == NULL) continue;
        
        // Skip already mitigated zones
        if(zone.mitigated) continue;
        
        double zoneMid = (zone.top + zone.bottom) / 2.0;
        double zoneSize = zone.top - zone.bottom;
        
        // === CHECK FOR ZONE MITIGATION (price passed completely through) ===
        // Bullish zone mitigated if price closed below zone.bottom
        if(zone.isBullish && close1 < zone.bottom && close2 < zone.bottom)
        {
            zone.mitigated = true;
            if(m_diagnostics != NULL)
                PrintFormat("[SMC] Zone MITIGATED (price broke below): %s", zone.id);
            continue;
        }
        // Bearish zone mitigated if price closed above zone.top
        if(!zone.isBullish && close1 > zone.top && close2 > zone.top)
        {
            zone.mitigated = true;
            if(m_diagnostics != NULL)
                PrintFormat("[SMC] Zone MITIGATED (price broke above): %s", zone.id);
            continue;
        }
        
        // === PROPER SMC ENTRY LOGIC ===
        // Bullish OB (Demand Zone): Price must RETRACE DOWN into zone, then show REJECTION
        // Bearish OB (Supply Zone): Price must RETRACE UP into zone, then show REJECTION
        
        bool validEntry = false;
        ENUM_TRADE_SIGNAL zoneSignal = TRADE_SIGNAL_NONE;
        double zoneConfidence = zone.score / 100.0;
        string entryReason = "";
        
        if(zone.isBullish)
        {
            // === BULLISH ZONE (DEMAND) - Looking for BUY ===
            // Condition 1: Price must have been FALLING (retracing) into the zone
            // Condition 2: Price touched/entered the zone
            // Condition 3: Price showed REJECTION (closed back above zone or bullish candle)
            
            bool priceTouchedZone = (low1 <= zone.top && low1 >= zone.bottom) ||
                                    (low2 <= zone.top && low2 >= zone.bottom) ||
                                    (bid <= zone.top && bid >= zone.bottom);
            
            bool priceRejectedUp = false;
            
            // Check for rejection patterns:
            // 1. Pin bar rejection (wick into zone, close above)
            bool pinBarRejection = (low1 <= zone.top && low1 >= zone.bottom) && 
                                   (close1 > zone.top) &&
                                   ((close1 - low1) > (high1 - close1) * 1.5); // Long lower wick
            
            // 2. Bullish engulfing at zone
            bool bullishEngulfing = (low2 <= zone.top && low2 >= zone.bottom) &&
                                    (close1 > open1) && // Bullish candle
                                    (close1 > close2) && // Closed higher
                                    (open1 <= close2);   // Opened at or below previous close
            
            // 3. Close back above zone after touching
            bool closedAboveZone = (low1 <= zone.top || low2 <= zone.top) && 
                                   (close1 > zone.top) && (close0 > zone.top);
            
            priceRejectedUp = pinBarRejection || bullishEngulfing || closedAboveZone;
            
            // Valid BUY entry: Price was falling, touched zone, and rejected upward
            if(priceWasFalling && priceTouchedZone && priceRejectedUp)
            {
                validEntry = true;
                zoneSignal = TRADE_SIGNAL_BUY;
                entryReason = pinBarRejection ? "Pin Bar" : (bullishEngulfing ? "Engulfing" : "Zone Rejection");
                zoneConfidence += 0.15; // Bonus for proper SMC entry
            }
            // Alternative: Price currently IN zone and showing bullish momentum
            else if(bid >= zone.bottom && bid <= zone.top && close1 > open1 && priceWasFalling)
            {
                validEntry = true;
                zoneSignal = TRADE_SIGNAL_BUY;
                entryReason = "In-Zone Bullish Momentum";
                zoneConfidence += 0.08;
            }
        }
        else // !zone.isBullish
        {
            // === BEARISH ZONE (SUPPLY) - Looking for SELL ===
            // Condition 1: Price must have been RISING (retracing) into the zone
            // Condition 2: Price touched/entered the zone
            // Condition 3: Price showed REJECTION (closed back below zone or bearish candle)
            
            bool priceTouchedZone = (high1 >= zone.bottom && high1 <= zone.top) ||
                                    (high2 >= zone.bottom && high2 <= zone.top) ||
                                    (bid >= zone.bottom && bid <= zone.top);
            
            bool priceRejectedDown = false;
            
            // Check for rejection patterns:
            // 1. Pin bar rejection (wick into zone, close below)
            bool pinBarRejection = (high1 >= zone.bottom && high1 <= zone.top) && 
                                   (close1 < zone.bottom) &&
                                   ((high1 - close1) > (close1 - low1) * 1.5); // Long upper wick
            
            // 2. Bearish engulfing at zone
            bool bearishEngulfing = (high2 >= zone.bottom && high2 <= zone.top) &&
                                    (close1 < open1) && // Bearish candle
                                    (close1 < close2) && // Closed lower
                                    (open1 >= close2);   // Opened at or above previous close
            
            // 3. Close back below zone after touching
            bool closedBelowZone = (high1 >= zone.bottom || high2 >= zone.bottom) && 
                                   (close1 < zone.bottom) && (close0 < zone.bottom);
            
            priceRejectedDown = pinBarRejection || bearishEngulfing || closedBelowZone;
            
            // Valid SELL entry: Price was rising, touched zone, and rejected downward
            if(priceWasRising && priceTouchedZone && priceRejectedDown)
            {
                validEntry = true;
                zoneSignal = TRADE_SIGNAL_SELL;
                entryReason = pinBarRejection ? "Pin Bar" : (bearishEngulfing ? "Engulfing" : "Zone Rejection");
                zoneConfidence += 0.15; // Bonus for proper SMC entry
            }
            // Alternative: Price currently IN zone and showing bearish momentum
            else if(bid >= zone.bottom && bid <= zone.top && close1 < open1 && priceWasRising)
            {
                validEntry = true;
                zoneSignal = TRADE_SIGNAL_SELL;
                entryReason = "In-Zone Bearish Momentum";
                zoneConfidence += 0.08;
            }
        }
        
        if(!validEntry) continue;
        
        // === CONFIDENCE SCORING ===
        
        // Zone type boost
        if(zone.type == SMC_ZONE_ORDER_BLOCK)
            zoneConfidence += 0.12;
        else if(zone.type == SMC_ZONE_FVG)
            zoneConfidence += 0.08;
        
        // HTF bias alignment
        if(m_useHTFBias)
        {
            int bias = ComputeHTFBias();
            if((bias > 0 && zone.isBullish) || (bias < 0 && !zone.isBullish))
                zoneConfidence += 0.10; // Aligned with HTF
            else if((bias < 0 && zone.isBullish) || (bias > 0 && !zone.isBullish))
                zoneConfidence -= 0.20; // Counter-trend - heavy penalty
        }
        
        // Structure confirmation
        if(m_structureEngine != NULL)
        {
            m_structureEngine.DetectSwingPoints(m_symbol, m_timeframe);
            if(zone.isBullish && m_structureEngine.IsBullishStructure())
                zoneConfidence += 0.08;
            else if(!zone.isBullish && m_structureEngine.IsBearishStructure())
                zoneConfidence += 0.08;
        }
        
        // Zone freshness (unmitigated, untested zones are best)
        int zoneAge = Bars(m_symbol, m_timeframe, zone.createdTime, TimeCurrent());
        if(zoneAge < 30)
            zoneConfidence += 0.05; // Fresh zone
        else if(zoneAge > 150)
            zoneConfidence -= 0.08; // Old zone
        
        // First touch bonus (untested zones)
        if(zone.rejections == 0)
            zoneConfidence += 0.06; // First time testing this zone
        
        zoneConfidence = MathMin(1.0, MathMax(0.0, zoneConfidence));
        
        // Minimum confidence threshold
        if(zoneConfidence < 0.40)
            continue;
        
        // Track best signal
        if(zoneConfidence > bestConfidence)
        {
            bestSignal = zoneSignal;
            bestConfidence = zoneConfidence;
            bestZoneInfo = StringFormat("%s | %s | Age:%d bars", 
                                       zone.isBullish ? "DEMAND" : "SUPPLY",
                                       entryReason, zoneAge);
        }
        
        // Mark zone as tested
        zone.rejections++;
    }
    
    confidence = bestConfidence;
    
    if(bestSignal != TRADE_SIGNAL_NONE)
    {
        m_signalsGenerated++;
        if(m_diagnostics != NULL)
        {
            PrintFormat("[SMC] SIGNAL: %s | Confidence: %.1f%% | %s", 
                       bestSignal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                       bestConfidence * 100,
                       bestZoneInfo);
        }
    }
    
    return bestSignal;
}

//+------------------------------------------------------------------+
//| Get Signal Value Internal (no parameters version)               |
//+------------------------------------------------------------------+
double CStrategySMC::GetSignalValueInternal() const
{
    // Return latest signal strength (simplified implementation)
    return 0.0;
}
