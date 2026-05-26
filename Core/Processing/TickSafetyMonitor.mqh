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
    datetime m_emergencyStopTime;
    int m_emergencyStopDuration;
    datetime m_lastValidTickTime;
    int m_maxTickGapSeconds;
    
public:
    CTickSafetyMonitor() :
        m_maxSpreadPoints(50.0),
        m_minFreeMarginPercent(20.0),
        m_minMarginLevel(200.0),
        m_emergencyStop(false),
        m_emergencyStopTime(0),
        m_emergencyStopDuration(300), // 5 minutes default
        m_lastValidTickTime(0),
        m_maxTickGapSeconds(60) // 1 minute max gap
    {
    }
    
    ~CTickSafetyMonitor() {}
    
    // Configuration
    void SetMaxSpreadPoints(double spread) { m_maxSpreadPoints = spread; }
    void SetMinFreeMarginPercent(double percent) { m_minFreeMarginPercent = percent; }
    void SetMinMarginLevel(double level) { m_minMarginLevel = level; }
    void SetEmergencyStop(bool stop, int durationSeconds = 300);
    void SetMaxTickGapSeconds(int seconds) { m_maxTickGapSeconds = seconds; }
    
    // Safety checks
    bool IsSpreadAcceptable(const string symbol);
    bool IsMarginHealthy();
    bool IsTradingAllowed();
    bool IsEmergencyActive() const { return m_emergencyStop; }
    
    // Tick validation
    bool ValidateTick(const string symbol, MqlTick &tick);
    bool HasTickGap();
};

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                     |
//+------------------------------------------------------------------+
bool CTickSafetyMonitor::IsSpreadAcceptable(const string symbol)
{
    long spreadPoints = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    if(spreadPoints == -1)
        return false;
    
    return ((double)spreadPoints <= m_maxSpreadPoints);
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
    
    // Calculate used margin including pending orders
    double totalMarginUsed = accountInfo.Margin(); // Already includes pending orders
    double freeMarginAfterPending = equity - totalMarginUsed;
    
    double freeMarginPercent = (freeMarginAfterPending / equity) * 100.0;
    if(freeMarginPercent < m_minFreeMarginPercent)
        return false;
    
    double marginLevel = 0.0;
    if(totalMarginUsed > 0)
        marginLevel = (equity / totalMarginUsed) * 100.0;
    else
        marginLevel = accountInfo.MarginLevel();
    
    if(marginLevel < m_minMarginLevel)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                       |
//+------------------------------------------------------------------+
bool CTickSafetyMonitor::IsTradingAllowed()
{
    // Auto-reset emergency stop after duration
    if(m_emergencyStop && TimeCurrent() > m_emergencyStopTime + m_emergencyStopDuration)
    {
        m_emergencyStop = false;
        m_emergencyStopTime = 0;
        Print("[TickSafetyMonitor] Emergency stop auto-reset after ", m_emergencyStopDuration, " seconds");
    }
    
    if(m_emergencyStop)
        return false;
    
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        return false;
    
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Set emergency stop with duration                                  |
//+------------------------------------------------------------------+
void CTickSafetyMonitor::SetEmergencyStop(bool stop, int durationSeconds = 300)
{
    m_emergencyStop = stop;
    if(stop)
    {
        m_emergencyStopTime = TimeCurrent();
        m_emergencyStopDuration = durationSeconds;
        Print("[TickSafetyMonitor] Emergency stop activated for ", durationSeconds, " seconds");
    }
}

//+------------------------------------------------------------------+
//| Check for tick gap                                               |
//+------------------------------------------------------------------+
bool CTickSafetyMonitor::HasTickGap()
{
    if(m_lastValidTickTime == 0)
        return false;
    
    int gapSeconds = (int)(TimeCurrent() - m_lastValidTickTime);
    if(gapSeconds > m_maxTickGapSeconds)
    {
        PrintFormat("[TickSafetyMonitor] Tick gap detected: %d seconds > max allowed %d seconds",
                    gapSeconds, m_maxTickGapSeconds);
        return true;
    }
    
    return false;
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
    
    // Update last valid tick time
    m_lastValidTickTime = tickTime;
    
    return true;
}

#endif // __TICK_SAFETY_MONITOR_MQH__
