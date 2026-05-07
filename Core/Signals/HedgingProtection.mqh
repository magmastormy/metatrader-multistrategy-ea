//+------------------------------------------------------------------+
//| HedgingProtection.mqh                                           |
//| Prevents accidental hedging and conflicting positions           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property version   "1.00"
#property strict

#ifndef HEDGING_PROTECTION_MQH
#define HEDGING_PROTECTION_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/SignalDiagnostics.mqh"
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;

//+------------------------------------------------------------------+
//| Position State Structure                                        |
//+------------------------------------------------------------------+
struct SPositionState
{
    string symbol;
    ENUM_POSITION_TYPE type;
    double volume;
    datetime openTime;
    int magic;
    
    SPositionState()
    {
        symbol = "";
        type = POSITION_TYPE_BUY;
        volume = 0.0;
        openTime = 0;
        magic = 0;
    }
};

//+------------------------------------------------------------------+
//| Hedging Protection Mode                                         |
//+------------------------------------------------------------------+
enum ENUM_HEDGING_MODE
{
    HEDGING_MODE_PREVENT,      // Prevent all hedging
    HEDGING_MODE_ALLOW,        // Allow hedging (if configured)
    HEDGING_MODE_PARTIAL,      // Allow partial hedging with limits
    HEDGING_MODE_SMART         // Smart hedging based on market conditions
};

//+------------------------------------------------------------------+
//| Hedging Protection Class                                        |
//+------------------------------------------------------------------+
class CHedgingProtection
{
private:
    ENUM_HEDGING_MODE m_mode;
    bool              m_enabled;
    CSignalDiagnostics* m_diagnostics;
    CPositionInfo     m_position;
    
    // Configuration
    bool              m_allowHedging;
    double            m_maxHedgeRatio;    // Max hedge volume ratio
    int               m_minHedgeDistance;  // Min distance in points
    double            m_hedgeCooldown;     // Cooldown period in seconds
    
    // State tracking
    SPositionState    m_currentPositions[];
    int               m_positionCount;
    datetime          m_lastHedgeAttempt;
    int               m_hedgesPrevented;
    int               m_hedgesAllowed;
    
public:
    CHedgingProtection();
    ~CHedgingProtection();
    
    // Initialize
    bool Initialize(ENUM_HEDGING_MODE mode = HEDGING_MODE_PREVENT,
                   bool allowHedging = false);
                   
    void SetDiagnostics(CSignalDiagnostics* diag) { m_diagnostics = diag; }
    
    // Check methods
    bool CanOpenPosition(const string symbol, 
                        ENUM_TRADE_SIGNAL signal,
                        double volume);
                        
    bool WouldCauseHedge(const string symbol,
                        ENUM_TRADE_SIGNAL signal);
                        
    bool HasOpenPosition(const string symbol,
                        ENUM_POSITION_TYPE &posType,
                        double &posVolume);
                        
    bool HasConflictingPosition(const string symbol,
                               ENUM_TRADE_SIGNAL signal);
    
    // Protection methods
    ENUM_TRADE_SIGNAL FilterSignal(const string symbol,
                                  ENUM_TRADE_SIGNAL signal,
                                  string &reason);
                                  
    bool ValidateTradeRequest(const string symbol,
                             ENUM_TRADE_SIGNAL signal,
                             double volume,
                             string &errorMsg);
    
    // Update state
    void UpdatePositions();
    void OnPositionOpened(const string symbol, 
                         ENUM_POSITION_TYPE type,
                         double volume);
    void OnPositionClosed(const string symbol);
    
    // Configuration
    void SetMode(ENUM_HEDGING_MODE mode) { m_mode = mode; }
    void SetMaxHedgeRatio(double ratio) { m_maxHedgeRatio = ratio; }
    void SetMinHedgeDistance(int points) { m_minHedgeDistance = points; }
    void SetHedgeCooldown(double seconds) { m_hedgeCooldown = seconds; }
    void EnableHedging(bool enable) { m_allowHedging = enable; }
    
    // Statistics
    int GetHedgesPrevented() const { return m_hedgesPrevented; }
    int GetHedgesAllowed() const { return m_hedgesAllowed; }
    double GetPreventionRate() const;
    
private:
    // Helper methods
    ENUM_POSITION_TYPE SignalToPositionType(ENUM_TRADE_SIGNAL signal);
    bool IsOppositePosition(ENUM_POSITION_TYPE pos1, ENUM_POSITION_TYPE pos2);
    bool IsWithinCooldown();
    double GetPositionDistance(const string symbol, ENUM_POSITION_TYPE type);
    void LogHedgingEvent(const string symbol, 
                        const string action,
                        const string reason);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CHedgingProtection::CHedgingProtection() :
    m_mode(HEDGING_MODE_PREVENT),
    m_enabled(true),
    m_diagnostics(NULL),
    m_allowHedging(false),
    m_maxHedgeRatio(0.5),
    m_minHedgeDistance(100),
    m_hedgeCooldown(60),
    m_positionCount(0),
    m_lastHedgeAttempt(0),
    m_hedgesPrevented(0),
    m_hedgesAllowed(0)
{
    ArrayResize(m_currentPositions, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CHedgingProtection::~CHedgingProtection()
{
    ArrayFree(m_currentPositions);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CHedgingProtection::Initialize(ENUM_HEDGING_MODE mode, bool allowHedging)
{
    m_mode = mode;
    m_allowHedging = allowHedging;
    
    // Check if account allows hedging
    ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    
    if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && allowHedging)
    {
        Print("[HedgingProtection] Account supports hedging, protection mode: ", EnumToString(mode));
    }
    else if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
    {
        Print("[HedgingProtection] Account uses netting, hedging not possible");
        m_allowHedging = false;
    }
    
    UpdatePositions();
    return true;
}

//+------------------------------------------------------------------+
//| Can Open Position                                               |
//+------------------------------------------------------------------+
bool CHedgingProtection::CanOpenPosition(const string symbol,
                                        ENUM_TRADE_SIGNAL signal,
                                        double volume)
{
    if(!m_enabled || signal == TRADE_SIGNAL_NONE)
        return false;
    
    // Update current positions
    UpdatePositions();
    
    // Check for conflicting positions
    if(HasConflictingPosition(symbol, signal))
    {
        if(m_mode == HEDGING_MODE_PREVENT)
        {
            LogHedgingEvent(symbol, "PREVENTED", "Conflicting position exists");
            m_hedgesPrevented++;
            return false;
        }
        else if(m_mode == HEDGING_MODE_SMART)
        {
            // Smart mode: check additional conditions
            if(IsWithinCooldown())
            {
                LogHedgingEvent(symbol, "PREVENTED", "Within cooldown period");
                m_hedgesPrevented++;
                return false;
            }
            
            double distance = GetPositionDistance(symbol, SignalToPositionType(signal));
            if(distance < m_minHedgeDistance)
            {
                LogHedgingEvent(symbol, "PREVENTED", "Insufficient distance");
                m_hedgesPrevented++;
                return false;
            }
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Would Cause Hedge                                               |
//+------------------------------------------------------------------+
bool CHedgingProtection::WouldCauseHedge(const string symbol,
                                        ENUM_TRADE_SIGNAL signal)
{
    ENUM_POSITION_TYPE posType;
    double posVolume;
    
    if(!HasOpenPosition(symbol, posType, posVolume))
        return false;
    
    ENUM_POSITION_TYPE newType = SignalToPositionType(signal);
    return IsOppositePosition(posType, newType);
}

//+------------------------------------------------------------------+
//| Has Open Position                                               |
//+------------------------------------------------------------------+
bool CHedgingProtection::HasOpenPosition(const string symbol,
                                        ENUM_POSITION_TYPE &posType,
                                        double &posVolume)
{
    UpdatePositions();
    
    for(int i = 0; i < m_positionCount; i++)
    {
        if(m_currentPositions[i].symbol == symbol)
        {
            posType = m_currentPositions[i].type;
            posVolume = m_currentPositions[i].volume;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Has Conflicting Position                                        |
//+------------------------------------------------------------------+
bool CHedgingProtection::HasConflictingPosition(const string symbol,
                                               ENUM_TRADE_SIGNAL signal)
{
    ENUM_POSITION_TYPE existingType;
    double existingVolume;
    
    if(!HasOpenPosition(symbol, existingType, existingVolume))
        return false;
    
    ENUM_POSITION_TYPE newType = SignalToPositionType(signal);
    return IsOppositePosition(existingType, newType);
}

//+------------------------------------------------------------------+
//| Filter Signal                                                   |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CHedgingProtection::FilterSignal(const string symbol,
                                                  ENUM_TRADE_SIGNAL signal,
                                                  string &reason)
{
    if(!m_enabled || signal == TRADE_SIGNAL_NONE)
    {
        reason = "Signal is NONE or protection disabled";
        return signal;
    }
    
    // 🔥 FIX: Only check for hedging on the SAME symbol (not across different symbols)
    // This allows EURUSD BUY + GBPUSD SELL (different symbols = valid diversification)
    // But prevents EURUSD BUY + EURUSD SELL (same symbol = hedging)
    if(WouldCauseHedge(symbol, signal))
    {
        if(m_mode == HEDGING_MODE_PREVENT)
        {
            m_hedgesPrevented++;
            reason = StringFormat("Signal would cause hedging on %s - neutralized", symbol);
            
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogHedgingPrevented(symbol, signal, 
                                                 StringFormat("Opposite position exists on %s", symbol));
            }
            
            Print("[HedgingProtection] BLOCKED: ", symbol, " already has opposite position");
            return TRADE_SIGNAL_NONE;
        }
        else if(m_mode == HEDGING_MODE_SMART)
        {
            // Apply smart filtering
            if(IsWithinCooldown())
            {
                m_hedgesPrevented++;
                reason = "Hedging cooldown active";
                return TRADE_SIGNAL_NONE;
            }
            
            double distance = GetPositionDistance(symbol, SignalToPositionType(signal));
            if(distance < m_minHedgeDistance)
            {
                m_hedgesPrevented++;
                reason = StringFormat("Insufficient distance: %.1f < %d points", 
                                    distance, m_minHedgeDistance);
                return TRADE_SIGNAL_NONE;
            }
        }
    }
    
    reason = "Signal approved";
    return signal;
}

//+------------------------------------------------------------------+
//| Validate Trade Request                                          |
//+------------------------------------------------------------------+
bool CHedgingProtection::ValidateTradeRequest(const string symbol,
                                             ENUM_TRADE_SIGNAL signal,
                                             double volume,
                                             string &errorMsg)
{
    if(!m_enabled)
    {
        errorMsg = "Hedging protection disabled";
        return true; // Allow if disabled
    }
    
    // Check basic validity
    if(signal == TRADE_SIGNAL_NONE)
    {
        errorMsg = "Invalid signal: NONE";
        return false;
    }
    
    if(volume <= 0)
    {
        errorMsg = "Invalid volume: " + DoubleToString(volume, 2);
        return false;
    }
    
    // Check for hedging
    if(HasConflictingPosition(symbol, signal))
    {
        if(m_mode == HEDGING_MODE_PREVENT)
        {
            errorMsg = "Trade would create hedge position";
            m_hedgesPrevented++;
            return false;
        }
        else if(m_mode == HEDGING_MODE_PARTIAL)
        {
            // Check volume ratio
            ENUM_POSITION_TYPE existingType;
            double existingVolume;
            HasOpenPosition(symbol, existingType, existingVolume);
            
            if(volume > existingVolume * m_maxHedgeRatio)
            {
                errorMsg = StringFormat("Hedge volume too large: %.2f > %.2f (max ratio: %.2f)",
                                      volume, existingVolume * m_maxHedgeRatio, m_maxHedgeRatio);
                m_hedgesPrevented++;
                return false;
            }
        }
    }
    
    errorMsg = "Trade validated";
    return true;
}

//+------------------------------------------------------------------+
//| Update Positions                                                |
//+------------------------------------------------------------------+
void CHedgingProtection::UpdatePositions()
{
    m_positionCount = 0;
    ArrayResize(m_currentPositions, 0);
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(m_position.SelectByIndex(i))
        {
            int newSize = m_positionCount + 1;
            ArrayResize(m_currentPositions, newSize);
            
            m_currentPositions[m_positionCount].symbol = m_position.Symbol();
            m_currentPositions[m_positionCount].type = m_position.PositionType();
            m_currentPositions[m_positionCount].volume = m_position.Volume();
            m_currentPositions[m_positionCount].openTime = m_position.Time();
            m_currentPositions[m_positionCount].magic = (int)m_position.Magic();
            
            m_positionCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| On Position Opened                                              |
//+------------------------------------------------------------------+
void CHedgingProtection::OnPositionOpened(const string symbol,
                                         ENUM_POSITION_TYPE type,
                                         double volume)
{
    UpdatePositions();
    
    // Check if this was a hedge
    bool isHedge = false;
    for(int i = 0; i < m_positionCount - 1; i++)
    {
        if(m_currentPositions[i].symbol == symbol &&
           IsOppositePosition(m_currentPositions[i].type, type))
        {
            isHedge = true;
            m_hedgesAllowed++;
            break;
        }
    }
    
    if(isHedge)
    {
        m_lastHedgeAttempt = TimeCurrent();
        LogHedgingEvent(symbol, "OPENED", "Hedge position created");
    }
}

//+------------------------------------------------------------------+
//| On Position Closed                                              |
//+------------------------------------------------------------------+
void CHedgingProtection::OnPositionClosed(const string symbol)
{
    UpdatePositions();
    LogHedgingEvent(symbol, "CLOSED", "Position closed");
}

//+------------------------------------------------------------------+
//| Get Prevention Rate                                             |
//+------------------------------------------------------------------+
double CHedgingProtection::GetPreventionRate() const
{
    int total = m_hedgesPrevented + m_hedgesAllowed;
    if(total == 0) return 0.0;
    return (double)m_hedgesPrevented / total;
}

//+------------------------------------------------------------------+
//| Signal to Position Type                                         |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE CHedgingProtection::SignalToPositionType(ENUM_TRADE_SIGNAL signal)
{
    return (signal == TRADE_SIGNAL_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
}

//+------------------------------------------------------------------+
//| Is Opposite Position                                            |
//+------------------------------------------------------------------+
bool CHedgingProtection::IsOppositePosition(ENUM_POSITION_TYPE pos1, 
                                           ENUM_POSITION_TYPE pos2)
{
    return ((pos1 == POSITION_TYPE_BUY && pos2 == POSITION_TYPE_SELL) ||
            (pos1 == POSITION_TYPE_SELL && pos2 == POSITION_TYPE_BUY));
}

//+------------------------------------------------------------------+
//| Is Within Cooldown                                              |
//+------------------------------------------------------------------+
bool CHedgingProtection::IsWithinCooldown()
{
    if(m_lastHedgeAttempt == 0) return false;
    
    datetime localCurrentTime = TimeCurrent();
    double elapsed = (double)(localCurrentTime - m_lastHedgeAttempt);
    
    return (elapsed < m_hedgeCooldown);
}

//+------------------------------------------------------------------+
//| Get Position Distance                                           |
//+------------------------------------------------------------------+
double CHedgingProtection::GetPositionDistance(const string symbol, 
                                              ENUM_POSITION_TYPE type)
{
    double localCurrentPrice = (type == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(symbol, SYMBOL_ASK) :
                         SymbolInfoDouble(symbol, SYMBOL_BID);
    
    double minDistance = DBL_MAX;
    
    for(int i = 0; i < m_positionCount; i++)
    {
        if(m_currentPositions[i].symbol == symbol)
        {
            if(m_position.SelectByTicket(m_position.Ticket()))
            {
                double openPrice = m_position.PriceOpen();
                double distance = MathAbs(localCurrentPrice - openPrice);
                double points = distance / SymbolInfoDouble(symbol, SYMBOL_POINT);
                
                if(points < minDistance)
                    minDistance = points;
            }
        }
    }
    
    return minDistance;
}

//+------------------------------------------------------------------+
//| Log Hedging Event                                               |
//+------------------------------------------------------------------+
void CHedgingProtection::LogHedgingEvent(const string symbol,
                                        const string action,
                                        const string reason)
{
    string msg = StringFormat("[HedgingProtection] %s | %s | %s",
                            symbol, action, reason);
    Print(msg);
    
    if(m_diagnostics != NULL)
    {
        // Log to diagnostics system
        if(action == "PREVENTED")
        {
            m_diagnostics.LogHedgingPrevented(symbol, 
                                             TRADE_SIGNAL_NONE, 
                                             reason);
        }
    }
}

#endif // HEDGING_PROTECTION_MQH
