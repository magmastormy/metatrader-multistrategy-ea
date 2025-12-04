//+------------------------------------------------------------------+
//|                                                CBaseStrategy.mqh |
//|                                  Copyright 2025, Your Company Name |
//|                                             https://www.yoursite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#include <Object.mqh>
#include "IStrategy.mqh"

//+------------------------------------------------------------------+
//| Base Strategy Class                                              |
//+------------------------------------------------------------------+
class CBaseStrategy : public CObject
{
protected:
    string            m_name;           // Strategy name
    bool              m_enabled;        // Whether the strategy is enabled
    double            m_weight;         // Strategy weight for signal combination
    int               m_minBarsRequired;// Minimum bars required for calculation
    datetime          m_lastSignalTime; // Time of last signal
    double            m_lastSignalValue; // Value of last signal
    double            m_lastConfidence; // Confidence of last signal
    
public:
    //--- Constructor/Destructor
                     CBaseStrategy(string name, bool enabled = true, double weight = 1.0);
    virtual         ~CBaseStrategy();
    
    //--- Getters
    virtual string   Name() const { return m_name; }
    virtual bool     IsEnabled() const { return m_enabled; }
    virtual double   GetWeight() const { return m_weight; }
    virtual int      GetMinBarsRequired() const { return m_minBarsRequired; }
    
    //--- Setters
    virtual void     SetEnabled(bool enabled) { m_enabled = enabled; }
    virtual void     SetWeight(double weight) { m_weight = MathMax(0.0, MathMin(1.0, weight)); }
    
    //--- Signal generation (to be implemented by derived classes)
    virtual int      GetSignal(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence) = 0;
    
    //--- Common utility methods
    virtual double   CalculateRiskRewardRatio(double entry, double stopLoss, double takeProfit);
    virtual double   CalculatePositionSize(double riskAmount, double stopLossPips, const string symbol);
    virtual void     PrintInfo();
    
    //--- Virtual methods for strategy lifecycle
    virtual bool     Initialize() { return true; }
    virtual void     Deinitialize() {}
    virtual void     OnTick() {}
    virtual void     OnTimer() {}
    virtual void     OnTrade() {}
    
    //--- Helper methods
    virtual bool     IsNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual double   NormalizeSignal(double signal, double min = -1.0, double max = 1.0);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CBaseStrategy::CBaseStrategy(string name, bool enabled, double weight)
{
    m_name = name;
    m_enabled = enabled;
    m_weight = MathMax(0.0, MathMin(1.0, weight));
    m_minBarsRequired = 50; // Default value, can be overridden
    m_lastSignalTime = 0;
    m_lastSignalValue = 0.0;
    m_lastConfidence = 0.0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CBaseStrategy::~CBaseStrategy()
{
    Deinitialize();
}

//+------------------------------------------------------------------+
//| Calculate risk/reward ratio                                      |
//+------------------------------------------------------------------+
double CBaseStrategy::CalculateRiskRewardRatio(double entry, double stopLoss, double takeProfit)
{
    if (stopLoss == 0.0) return 0.0;
    
    double risk = MathAbs(entry - stopLoss);
    double reward = MathAbs(takeProfit - entry);
    
    if (risk > 0)
        return reward / risk;
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk amount                     |
//+------------------------------------------------------------------+
double CBaseStrategy::CalculatePositionSize(double riskAmount, double stopLossPips, const string symbol)
{
    if (stopLossPips <= 0) return 0.0;
    
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    if (tickSize <= 0 || tickValue <= 0 || lotStep <= 0) return 0.0;
    
    double pipValue = (tickValue / tickSize) * 10.0; // Assuming 5-digit broker
    double riskInAccountCurrency = riskAmount * AccountInfoDouble(ACCOUNT_BALANCE);
    double positionSize = riskInAccountCurrency / (stopLossPips * pipValue);
    
    // Normalize to lot step
    positionSize = MathFloor(positionSize / lotStep) * lotStep;
    
    // Ensure within min/max lots
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    return MathMin(maxLot, MathMax(minLot, positionSize));
}

//+------------------------------------------------------------------+
//| Print strategy information                                       |
//+------------------------------------------------------------------+
void CBaseStrategy::PrintInfo()
{
    Print("Strategy: ", m_name);
    Print("  Enabled: ", m_enabled ? "Yes" : "No");
    Print("  Weight: ", m_weight);
    Print("  Last Signal: ", m_lastSignalValue, " (Confidence: ", m_lastConfidence, ")");
    Print("  Last Signal Time: ", TimeToString(m_lastSignalTime));
}

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                   |
//+------------------------------------------------------------------+
bool CBaseStrategy::IsNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(symbol, timeframe, 0);
    
    if (lastBarTime != currentBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Normalize signal value to specified range                        |
//+------------------------------------------------------------------+
double CBaseStrategy::NormalizeSignal(double signal, double min, double max)
{
    if (signal > 0)
        return min + (max - min) * signal;
    else if (signal < 0)
        return -min + (max - min) * signal;
    
    return 0.0;
}
