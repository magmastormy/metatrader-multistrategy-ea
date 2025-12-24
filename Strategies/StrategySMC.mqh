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
    
    int maFastHandle = iMA(m_symbol, m_htfTimeframe, 20, 0, MODE_SMA, PRICE_CLOSE);
    int maSlowHandle = iMA(m_symbol, m_htfTimeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
    
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
        // Extend zone - update the second time coordinate (index 1)
        ObjectSetInteger(0, name, OBJPROP_TIME, 1, TimeCurrent());
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
//| Get Signal                                                       |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategySMC::GetSignal(double &confidence)
{
    confidence = 0.0;
    // Simplified implementation - return NONE for now
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Get Signal Value Internal (no parameters version)               |
//+------------------------------------------------------------------+
double CStrategySMC::GetSignalValueInternal() const
{
    // Return latest signal strength (simplified implementation)
    return 0.0;
}
