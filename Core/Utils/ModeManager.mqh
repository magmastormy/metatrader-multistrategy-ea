//+------------------------------------------------------------------+
//| ModeManager.mqh                                                  |
//| Manages switching between Killer Scalper and HTF Follower modes  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced AI Coding Assistant"
#property version   "1.00"
#property strict

#include "../Utils/Enums.mqh"
#include <Trade\SymbolInfo.mqh>

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

//+------------------------------------------------------------------+
//| Mode Manager Class                                               |
//+------------------------------------------------------------------+
class CModeManager : public CObject
{
private:
    // Parameters
    double           m_volHTFThreshold;   // Volatility threshold for HTF mode
    double           m_volLow;            // Min volatility for Scalp
    double           m_volScalpHigh;      // Max volatility for Scalp
    double           m_spreadMaxScalp;    // Max spread for Scalp (pips)
    ENUM_TIMEFRAMES  m_htfTimeframe;      // Timeframe for HTF analysis
    
    // State
    ENUM_TRADING_MODE m_currentMode;
    datetime          m_lastUpdate;
    
    // Helpers
    double CalculateVolatilityIndex(const string symbol);
    int    CalculateHTFTrend(const string symbol);
    bool   IsDerivSymbol(const string symbol);
    
public:
    CModeManager();
    ~CModeManager();
    
    void Init(double volHTF, double volLow, double volScalpHigh, double spreadMax, ENUM_TIMEFRAMES htfTF);
    void UpdateMode(const string symbol);
    ENUM_TRADING_MODE GetCurrentMode() const { return m_currentMode; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CModeManager::CModeManager() :
    m_volHTFThreshold(0.18),
    m_volLow(0.02),
    m_volScalpHigh(0.08),
    m_spreadMaxScalp(1.5),
    m_htfTimeframe(PERIOD_H1),
    m_currentMode(TRADING_MODE_NO_TRADE),
    m_lastUpdate(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CModeManager::~CModeManager()
{
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
void CModeManager::Init(double volHTF, double volLow, double volScalpHigh, double spreadMax, ENUM_TIMEFRAMES htfTF)
{
    m_volHTFThreshold = volHTF;
    m_volLow = volLow;
    m_volScalpHigh = volScalpHigh;
    m_spreadMaxScalp = spreadMax;
    m_htfTimeframe = htfTF;
}

//+------------------------------------------------------------------+
//| Update Trading Mode                                              |
//+------------------------------------------------------------------+
void CModeManager::UpdateMode(const string symbol)
{
    // Only update on new HTF bar or sufficient time elapsed
    // For responsiveness, we check every tick but rely on HTF data
    
    double volatility = CalculateVolatilityIndex(symbol);
    int htfTrend = CalculateHTFTrend(symbol);
    
    double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5)
        spread *= 0.1; // Convert to pips if needed, but better to use raw points comparison if consistent
        
    // Normalize spread to pips for comparison
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double spreadPips = spread / point;
    if(point == 0.001 || point == 0.00001) spreadPips /= 10; // Standard pip conversion
    
    // Logic Rule 1: HTF Follower
    // Strong Trend + High Volatility
    if(MathAbs(htfTrend) == 1 && volatility >= m_volHTFThreshold)
    {
        m_currentMode = TRADING_MODE_HTF_FOLLOWER;
        return;
    }
    
    // Logic Rule 2: Killer Scalper
    // Moderate Volatility + Low Spread + Neutral/Weak Trend
    if(volatility >= m_volLow && volatility <= m_volScalpHigh && 
       spreadPips <= m_spreadMaxScalp)
    {
        m_currentMode = TRADING_MODE_KILLER_SCALPER;
        return;
    }
    
    // Default
    m_currentMode = TRADING_MODE_NO_TRADE;
}

//+------------------------------------------------------------------+
//| Calculate Volatility Index (ATR / Price)                         |
//+------------------------------------------------------------------+
double CModeManager::CalculateVolatilityIndex(const string symbol)
{
    // Use ATR(20) on HTF
    int atrHandle = iATR(symbol, m_htfTimeframe, 20);
    if(atrHandle == INVALID_HANDLE) return 0.0;
    
    double atrVal[];
    ArraySetAsSeries(atrVal, true);
    if(CopyBuffer(atrHandle, 0, 0, 1, atrVal) <= 0)
    {
        IndicatorRelease(atrHandle);
        return 0.0;
    }
    
    double bidPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    double volIndex = (bidPrice > 0) ? (atrVal[0] / bidPrice) * 100.0 : 0.0; // Percentage
    
    IndicatorRelease(atrHandle);
    return volIndex;
}

//+------------------------------------------------------------------+
//| Calculate HTF Trend (+1 Up, -1 Down, 0 Neutral)                  |
//+------------------------------------------------------------------+
int CModeManager::CalculateHTFTrend(const string symbol)
{
    // Simple Structure: Higher Highs + Higher Lows = Up
    // Using last 2 swings or MA
    
    // For robustness, use MA slope + Price position
    int maHandle = iMA(symbol, m_htfTimeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
    if(maHandle == INVALID_HANDLE) return 0;
    
    double maVal[];
    ArraySetAsSeries(maVal, true);
    if(CopyBuffer(maHandle, 0, 0, 3, maVal) <= 0)
    {
        IndicatorRelease(maHandle);
        return 0;
    }
    
    double close = iClose(symbol, m_htfTimeframe, 0);
    
    int trend = 0;
    if(close > maVal[0] && maVal[0] > maVal[2]) trend = 1;       // Price above rising MA
    else if(close < maVal[0] && maVal[0] < maVal[2]) trend = -1; // Price below falling MA
    
    IndicatorRelease(maHandle);
    return trend;
}

//+------------------------------------------------------------------+
//| Check if symbol is Deriv Synthetic                               |
//+------------------------------------------------------------------+
bool CModeManager::IsDerivSymbol(const string symbol)
{
    // Simple check for common Deriv names
    if(StringFind(symbol, "Vol") >= 0 || StringFind(symbol, "Step") >= 0 || 
       StringFind(symbol, "Boom") >= 0 || StringFind(symbol, "Crash") >= 0 ||
       StringFind(symbol, "Jump") >= 0)
    {
        return true;
    }
    return false;
}
