//+------------------------------------------------------------------+
//| Liquidity Detection Engine - Enterprise Grade                    |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef LIQUIDITY_ENGINE_MQH
#define LIQUIDITY_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/SignalDiagnostics.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

enum ENUM_LIQUIDITY_ENGINE_TYPE
{
    LIQ_ENG_NONE = 0,
    LIQ_ENG_BUY_STOPS,
    LIQ_ENG_SELL_STOPS,
    LIQ_ENG_EQUAL_HIGHS,
    LIQ_ENG_EQUAL_LOWS,
    LIQ_ENG_SWEPT,
    LIQ_ENG_VOID
};

struct LiquidityZone
{
    double priceLevel;
    double zoneTop;
    double zoneBottom;
    ENUM_LIQUIDITY_ENGINE_TYPE type;
    int touchCount;
    double strength;
    datetime created;
    bool isActive;
    bool isSwept;
};

class CLiquidityEngine
{
private:
    double m_minZoneSize;
    int m_minTouchCount;
    int m_lookbackPeriod;
    CSignalDiagnostics* m_diagnostics;
    string m_symbol;
    double m_symbolPoint;
    
    LiquidityZone m_buyZones[];
    LiquidityZone m_sellZones[];
    
    bool DetectEqualLevels(const MqlRates &rates[], int period);
    double CalculateZoneStrength(const LiquidityZone &zone);
    
public:
    CLiquidityEngine();
    ~CLiquidityEngine();
    
    bool Initialize(double minZoneSize = 10.0, int minTouches = 2, CSignalDiagnostics* diag = NULL);
    bool DetectLiquidityZones(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool HasLiquiditySweep(int barsAgo = 5);
    bool IsPriceNearLiquidity(double price, double threshold = 20.0);
    
    int GetBuyZoneCount() const { return ArraySize(m_buyZones); }
    int GetSellZoneCount() const { return ArraySize(m_sellZones); }
    void Reset();
};

CLiquidityEngine::CLiquidityEngine() : m_minZoneSize(10.0), m_minTouchCount(2), 
                                       m_lookbackPeriod(100), m_diagnostics(NULL),
                                       m_symbol(""), m_symbolPoint(0.0)
{
    ArrayResize(m_buyZones, 0);
    ArrayResize(m_sellZones, 0);
}

CLiquidityEngine::~CLiquidityEngine() 
{
    ArrayFree(m_buyZones);
    ArrayFree(m_sellZones);
}

bool CLiquidityEngine::Initialize(double minZoneSize, int minTouches, CSignalDiagnostics* diag)
{
    m_minZoneSize = minZoneSize;
    m_minTouchCount = minTouches;
    m_diagnostics = diag;
    Reset();
    return true;
}

bool CLiquidityEngine::DetectLiquidityZones(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);

    m_symbol = symbol;
    m_symbolPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(m_symbolPoint <= 0.0)
        m_symbolPoint = 0.00001;
    
    if(CopyRates(symbol, timeframe, 0, m_lookbackPeriod, rates) < m_lookbackPeriod)
    {
        Reset();
        return false;
    }
    
    ArrayResize(m_buyZones, 0);
    ArrayResize(m_sellZones, 0);
    
    DetectEqualLevels(rates, m_lookbackPeriod);
    
    if(m_diagnostics != NULL)
    {
        string msg = StringFormat("Liquidity zones: Buy=%d, Sell=%d", 
                                ArraySize(m_buyZones), ArraySize(m_sellZones));
        Print("[LiquidityEngine] ", msg);
    }
    
    return true;
}

bool CLiquidityEngine::DetectEqualLevels(const MqlRates &rates[], int period)
{
    double point = m_symbolPoint;
    if(point <= 0.0)
        point = 0.00001;
    double tolerance = m_minZoneSize * point;
    
    for(int i = 1; i < period - 1; i++)
    {
        int equalHighCount = 0;
        double avgHigh = rates[i].high;
        
        for(int j = i + 1; j < MathMin(i + 20, period); j++)
        {
            if(MathAbs(rates[j].high - rates[i].high) < tolerance)
            {
                equalHighCount++;
                avgHigh = (avgHigh + rates[j].high) / 2;
                
                if(equalHighCount >= m_minTouchCount - 1)
                {
                    LiquidityZone zone;
                    zone.priceLevel = avgHigh;
                    zone.zoneTop = avgHigh + tolerance;
                    zone.zoneBottom = avgHigh - tolerance;
                    zone.type = LIQ_ENG_EQUAL_HIGHS;
                    zone.touchCount = equalHighCount + 1;
                    zone.created = rates[i].time;
                    zone.isActive = true;
                    zone.strength = CalculateZoneStrength(zone);
                    
                    int size = ArraySize(m_buyZones);
                    ArrayResize(m_buyZones, size + 1);
                    m_buyZones[size] = zone;
                    break;
                }
            }
        }
    }
    return true;
}

double CLiquidityEngine::CalculateZoneStrength(const LiquidityZone &zone)
{
    return MathMin(100.0, 50.0 + zone.touchCount * 10);
}

bool CLiquidityEngine::HasLiquiditySweep(int barsAgo)
{
    for(int i = 0; i < ArraySize(m_buyZones); i++)
        if(m_buyZones[i].isSwept) return true;
    for(int i = 0; i < ArraySize(m_sellZones); i++)
        if(m_sellZones[i].isSwept) return true;
    return false;
}

bool CLiquidityEngine::IsPriceNearLiquidity(double price, double threshold)
{
    double point = m_symbolPoint;
    if(point <= 0.0)
        point = 0.00001;
    double dist = threshold * point;
    
    for(int i = 0; i < ArraySize(m_buyZones); i++)
        if(MathAbs(price - m_buyZones[i].priceLevel) < dist) return true;
    for(int i = 0; i < ArraySize(m_sellZones); i++)
        if(MathAbs(price - m_sellZones[i].priceLevel) < dist) return true;
    
    return false;
}

void CLiquidityEngine::Reset()
{
    ArrayResize(m_buyZones, 0);
    ArrayResize(m_sellZones, 0);
    m_symbolPoint = 0.0;
}

#endif // LIQUIDITY_ENGINE_MQH
