// Opposing same-symbol cluster conflict cooldown cache; consulted only while
// CUnifiedRiskManager's `m_clusterMutexEnabled` switch is on (that gate stays there).
#ifndef CORE_RISK_RISK_OPPOSING_CONFLICT_GUARD_MQH
#define CORE_RISK_RISK_OPPOSING_CONFLICT_GUARD_MQH

class CRiskOpposingConflictGuard
{
private:
    int      m_opposingConflictCooldownSec;
    datetime m_lastOpposingConflictTime;
    string   m_lastOpposingConflictSymbol;

public:
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

    //--- True while a conflict is still cooling down for `symbol`, so the caller can skip
    //--- the full opposing-position scan. True means reject; `message` carries the reason.
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

    //--- Stamp a conflict for `symbol`: restarts the cooldown. Single slot — a new symbol drops the previous one's.
    void RegisterConflict(const string symbol)
    {
        m_lastOpposingConflictTime = TimeCurrent();
        m_lastOpposingConflictSymbol = symbol;
    }

    //--- Drop the cached conflict once the blocking position for `symbol` has closed.
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
