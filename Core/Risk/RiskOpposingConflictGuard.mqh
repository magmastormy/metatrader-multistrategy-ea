//+------------------------------------------------------------------+
//| RiskOpposingConflictGuard.mqh                                    |
//| Opposing same-symbol cluster conflict cooldown cache (Fix #9).   |
//|                                                                  |
//| Extracted verbatim from CUnifiedRiskManager (Phase E2, E-E):     |
//|   m_opposingConflictCooldownSec                                  |
//|   m_lastOpposingConflictTime / m_lastOpposingConflictSymbol      |
//|   cooldown short-circuit in ValidateClusterGovernance            |
//|       -> IsCooldownActive                                        |
//|   conflict-cache update in ValidateClusterGovernance             |
//|       -> RegisterConflict                                        |
//|   CUnifiedRiskManager::ClearOpposingConflictCache                |
//|       -> ClearOpposingConflictCache                              |
//|                                                                  |
//| Behaviour is byte-identical to the original inline code;         |
//| CUnifiedRiskManager keeps a thin forwarder with the original     |
//| signature so that all call sites remain unchanged.               |
//|                                                                  |
//| OWNERSHIP NOTE: the `m_clusterMutexEnabled` master switch stays  |
//| in CUnifiedRiskManager - the guard is only consulted while the   |
//| mutex feature is enabled, exactly as before.                     |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_RISK_OPPOSING_CONFLICT_GUARD_MQH
#define CORE_RISK_RISK_OPPOSING_CONFLICT_GUARD_MQH

//+------------------------------------------------------------------+
//| Opposing-signal conflict cooldown cache (stateful, owned by value)|
//+------------------------------------------------------------------+
class CRiskOpposingConflictGuard
{
private:
    int      m_opposingConflictCooldownSec;
    datetime m_lastOpposingConflictTime;
    string   m_lastOpposingConflictSymbol;

public:
    //--- Constructor performs the zero-init that used to live in the
    //--- CUnifiedRiskManager initialiser list (identical values).
    CRiskOpposingConflictGuard() :
        m_opposingConflictCooldownSec(120),
        m_lastOpposingConflictTime(0),
        m_lastOpposingConflictSymbol("")
    {
    }

    ~CRiskOpposingConflictGuard()
    {
        // No owned resources.
    }

    //--- Fix #9: Opposing conflict cooldown cache - skip full scan if
    //--- recently rejected for the same symbol.
    //--- Returns true when the cooldown is still active (caller must reject);
    //--- `message` is then filled with the original rejection text.
    bool IsCooldownActive(const string symbol, string &message)
    {
        if(m_lastOpposingConflictSymbol == symbol &&
           m_lastOpposingConflictTime > 0 &&
           (TimeCurrent() - m_lastOpposingConflictTime) < m_opposingConflictCooldownSec)
        {
            message = StringFormat("Opposing conflict cooldown active for %s (%ds remaining)",
                                   symbol,
                                   m_opposingConflictCooldownSec - (int)(TimeCurrent() - m_lastOpposingConflictTime));
            PrintFormat("[RISK-MUTEX-COOLDOWN] symbol=%s | cooldown_remaining=%ds | last_conflict=%s",
                        symbol,
                        m_opposingConflictCooldownSec - (int)(TimeCurrent() - m_lastOpposingConflictTime),
                        TimeToString(m_lastOpposingConflictTime, TIME_DATE | TIME_SECONDS));
            return true;
        }
        return false;
    }

    //--- Fix #9: Update cooldown cache when a new opposing conflict is detected.
    void RegisterConflict(const string symbol)
    {
        m_lastOpposingConflictTime = TimeCurrent();
        m_lastOpposingConflictSymbol = symbol;
    }

    //--- Drop the cached conflict for `symbol` (called after the blocking
    //--- position for that symbol has been closed).
    void ClearOpposingConflictCache(const string symbol)
    {
        if(m_lastOpposingConflictSymbol == symbol)
        {
            m_lastOpposingConflictTime = 0;
            m_lastOpposingConflictSymbol = "";
            PrintFormat("[RISK-MUTEX-COOLDOWN] cache cleared for symbol=%s", symbol);
        }
    }

    //--- Diagnostics / configuration accessors.
    int GetCooldownSeconds() const
    {
        return m_opposingConflictCooldownSec;
    }

    void SetCooldownSeconds(const int seconds)
    {
        m_opposingConflictCooldownSec = MathMax(0, seconds);
    }

    string GetLastConflictSymbol() const
    {
        return m_lastOpposingConflictSymbol;
    }

    datetime GetLastConflictTime() const
    {
        return m_lastOpposingConflictTime;
    }
};

#endif // CORE_RISK_RISK_OPPOSING_CONFLICT_GUARD_MQH
