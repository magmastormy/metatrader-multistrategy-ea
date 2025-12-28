//+------------------------------------------------------------------+
//| Volatility Analysis Engine - Enterprise Grade                    |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef VOLATILITY_ENGINE_MQH
#define VOLATILITY_ENGINE_MQH

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

enum ENUM_VOLATILITY_STATE
{
    VOLATILITY_LOW = 0,
    VOLATILITY_NORMAL,
    VOLATILITY_HIGH,
    VOLATILITY_EXTREME
};

struct VolatilityMetrics
{
    double atr;
    double atrPercent;
    double bollinger_width;
    double historical_volatility;
    double relative_volatility;
    ENUM_VOLATILITY_STATE state;
    bool isExpanding;
    bool isContracting;
    datetime lastUpdate;
};

class CVolatilityEngine
{
private:
    int m_atrPeriod;
    int m_bbPeriod;
    double m_bbDeviation;
    int m_hvPeriod;
    
    int m_handleATR;
    int m_handleBB;
    int m_handleStdDev;
    
    VolatilityMetrics m_metrics;
    CSignalDiagnostics* m_diagnostics;
    
    ENUM_VOLATILITY_STATE DetermineState(double atrPercent);
    double CalculateHistoricalVolatility(const string symbol, ENUM_TIMEFRAMES tf);
    
public:
    CVolatilityEngine();
    ~CVolatilityEngine();
    
    bool Initialize(int atrPeriod = 14, int bbPeriod = 20, CSignalDiagnostics* diag = NULL);
    bool UpdateVolatility(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Getters
    ENUM_VOLATILITY_STATE GetVolatilityState() const { return m_metrics.state; }
    double GetATR() const { return m_metrics.atr; }
    double GetATRPercent() const { return m_metrics.atrPercent; }
    bool IsVolatilityHigh() const { return m_metrics.state >= VOLATILITY_HIGH; }
    bool IsVolatilityExpanding() const { return m_metrics.isExpanding; }
    
    // Filters
    bool ShouldTradeInCurrentVolatility(double maxVolatility = 3.0);
    double GetVolatilityAdjustedStopLoss(double baseStop);
    double GetVolatilityAdjustedTakeProfit(double baseTp);
    
    void Reset();
};

CVolatilityEngine::CVolatilityEngine() : 
    m_atrPeriod(14), m_bbPeriod(20), m_bbDeviation(2.0), m_hvPeriod(20),
    m_handleATR(INVALID_HANDLE), m_handleBB(INVALID_HANDLE), m_handleStdDev(INVALID_HANDLE),
    m_diagnostics(NULL)
{
}

CVolatilityEngine::~CVolatilityEngine()
{
    if(m_handleATR != INVALID_HANDLE) IndicatorRelease(m_handleATR);
    if(m_handleBB != INVALID_HANDLE) IndicatorRelease(m_handleBB);
    if(m_handleStdDev != INVALID_HANDLE) IndicatorRelease(m_handleStdDev);
}

bool CVolatilityEngine::Initialize(int atrPeriod, int bbPeriod, CSignalDiagnostics* diag)
{
    m_atrPeriod = atrPeriod;
    m_bbPeriod = bbPeriod;
    m_diagnostics = diag;
    Reset();
    return true;
}

bool CVolatilityEngine::UpdateVolatility(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    // Release old handles
    if(m_handleATR != INVALID_HANDLE) { IndicatorRelease(m_handleATR); m_handleATR = INVALID_HANDLE; }
    if(m_handleBB != INVALID_HANDLE) { IndicatorRelease(m_handleBB); m_handleBB = INVALID_HANDLE; }
    if(m_handleStdDev != INVALID_HANDLE) { IndicatorRelease(m_handleStdDev); m_handleStdDev = INVALID_HANDLE; }
    
    // Create indicators
    m_handleATR = iATR(symbol, timeframe, m_atrPeriod);
    m_handleBB = iBands(symbol, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
    m_handleStdDev = iStdDev(symbol, timeframe, m_hvPeriod, 0, MODE_EMA, PRICE_CLOSE);
    
    if(m_handleATR == INVALID_HANDLE || m_handleBB == INVALID_HANDLE || m_handleStdDev == INVALID_HANDLE)
        return false;
    
    // Get values
    double atr[2];
    double bb_upper[1], bb_lower[1], bb_middle[1];
    double stddev[1];
    
    if(CopyBuffer(m_handleATR, 0, 0, 2, atr) != 2) return false;
    if(CopyBuffer(m_handleBB, 1, 0, 1, bb_upper) != 1) return false;
    if(CopyBuffer(m_handleBB, 2, 0, 1, bb_lower) != 1) return false;
    if(CopyBuffer(m_handleBB, 0, 0, 1, bb_middle) != 1) return false;
    if(CopyBuffer(m_handleStdDev, 0, 0, 1, stddev) != 1) return false;
    
    // Calculate metrics
    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    m_metrics.atr = atr[0];
    m_metrics.atrPercent = (atr[0] / price) * 100;
    m_metrics.bollinger_width = bb_upper[0] - bb_lower[0];
    m_metrics.historical_volatility = stddev[0];
    m_metrics.relative_volatility = m_metrics.atr / m_metrics.historical_volatility;
    
    // Determine state
    m_metrics.state = DetermineState(m_metrics.atrPercent);
    
    // Check expansion/contraction
    m_metrics.isExpanding = atr[0] > atr[1] * 1.1;
    m_metrics.isContracting = atr[0] < atr[1] * 0.9;
    
    m_metrics.lastUpdate = TimeCurrent();
    
    if(m_diagnostics != NULL)
    {
        string msg = StringFormat("Volatility: %s | ATR: %.5f (%.2f%%) | BB Width: %.5f",
                                EnumToString(m_metrics.state), m_metrics.atr, 
                                m_metrics.atrPercent, m_metrics.bollinger_width);
        Print("[VolatilityEngine] ", msg);
    }
    
    return true;
}

ENUM_VOLATILITY_STATE CVolatilityEngine::DetermineState(double atrPercent)
{
    if(atrPercent < 0.5) return VOLATILITY_LOW;
    else if(atrPercent < 1.5) return VOLATILITY_NORMAL;
    else if(atrPercent < 3.0) return VOLATILITY_HIGH;
    else return VOLATILITY_EXTREME;
}

bool CVolatilityEngine::ShouldTradeInCurrentVolatility(double maxVolatility)
{
    return m_metrics.atrPercent <= maxVolatility;
}

double CVolatilityEngine::GetVolatilityAdjustedStopLoss(double baseStop)
{
    double multiplier = 1.0;
    if(m_metrics.state == VOLATILITY_HIGH) multiplier = 1.5;
    else if(m_metrics.state == VOLATILITY_EXTREME) multiplier = 2.0;
    return baseStop * multiplier;
}

double CVolatilityEngine::GetVolatilityAdjustedTakeProfit(double baseTp)
{
    double multiplier = 1.0;
    if(m_metrics.state == VOLATILITY_HIGH) multiplier = 1.25;
    else if(m_metrics.state == VOLATILITY_EXTREME) multiplier = 1.5;
    return baseTp * multiplier;
}

void CVolatilityEngine::Reset()
{
    m_metrics = VolatilityMetrics();
}

#endif // VOLATILITY_ENGINE_MQH
