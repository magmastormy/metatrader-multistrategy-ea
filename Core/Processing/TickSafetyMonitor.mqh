//+------------------------------------------------------------------+
//| TickSafetyMonitor.mqh - Tick-level safety checks                  |
//| Spread check, margin check, tick-level monitoring for OnTick       |
//+------------------------------------------------------------------+
#ifndef __TICK_SAFETY_MONITOR_MQH__
#define __TICK_SAFETY_MONITOR_MQH__

#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Tick Safety Monitor Class                                         |
//+------------------------------------------------------------------+
class CTickSafetyMonitor
{
private:
    double m_maxSpreadPoints;
    double m_minFreeMarginPercent;
    double m_minMarginLevel;
    bool m_emergencyStop;
    
public:
    CTickSafetyMonitor() :
        m_maxSpreadPoints(50.0),
        m_minFreeMarginPercent(20.0),
        m_minMarginLevel(200.0),
        m_emergencyStop(false)
    {
    }
    
    ~CTickSafetyMonitor() {}
    
    // Configuration
    void SetMaxSpreadPoints(double spread) { m_maxSpreadPoints = spread; }
    void SetMinFreeMarginPercent(double percent) { m_minFreeMarginPercent = percent; }
    void SetMinMarginLevel(double level) { m_minMarginLevel = level; }
    void SetEmergencyStop(bool stop) { m_emergencyStop = stop; }
    
    // Safety checks
    bool IsSpreadAcceptable(const string symbol);
    bool IsMarginHealthy();
    bool IsTradingAllowed();
    bool IsEmergencyActive() const { return m_emergencyStop; }
    
    // Tick validation
    bool ValidateTick(const string symbol, MqlTick &tick);
};

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                     |
//+------------------------------------------------------------------+
bool CTickSafetyMonitor::IsSpreadAcceptable(const string symbol)
{
    CSymbolInfo symbolInfo;
    if(!symbolInfo.Name(symbol))
        return false;
    
    symbolInfo.RefreshRates();
    double spread = symbolInfo.Spread();
    double point = symbolInfo.Point();
    
    if(point <= 0)
        return false;
    
    double spreadPoints = spread / point;
    return (spreadPoints <= m_maxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Check if margin is healthy                                        |
//+------------------------------------------------------------------+
bool CTickSafetyMonitor::IsMarginHealthy()
{
    CAccountInfo accountInfo;
    double freeMargin = accountInfo.FreeMargin();
    double equity = accountInfo.Equity();
    
    if(equity <= 0)
        return false;
    
    double freeMarginPercent = (freeMargin / equity) * 100.0;
    if(freeMarginPercent < m_minFreeMarginPercent)
        return false;
    
    double marginLevel = accountInfo.MarginLevel();
    if(marginLevel < m_minMarginLevel)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                       |
//+------------------------------------------------------------------+
bool CTickSafetyMonitor::IsTradingAllowed()
{
    if(m_emergencyStop)
        return false;
    
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        return false;
    
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate tick data                                               |
//+------------------------------------------------------------------+
bool CTickSafetyMonitor::ValidateTick(const string symbol, MqlTick &tick)
{
    if(!SymbolInfoTick(symbol, tick))
        return false;
    
    if(tick.bid <= 0 || tick.ask <= 0)
        return false;
    
    if(tick.ask < tick.bid)
        return false;
    
    datetime tickTime = (tick.time > 0) ? (datetime)tick.time : TimeCurrent();
    int tickAgeSeconds = (int)MathMax(0, TimeCurrent() - tickTime);
    if(tickAgeSeconds > 30)
        return false;
    
    return true;
}

#endif // __TICK_SAFETY_MONITOR_MQH__
