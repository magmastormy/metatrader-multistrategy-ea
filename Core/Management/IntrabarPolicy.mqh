// Per-slot registration config table and its resolvers: the intrabar policy and the strategy
// timeframe handed to AutoRegisterStrategies before each Init.
// MUTATES the manager: the back-pointer is non-const and writes go through its narrow per-field accessors.
// Implementation detail of EnterpriseStrategyManager.mqh; not standalone.
#ifndef INTRABAR_POLICY_MQH
#define INTRABAR_POLICY_MQH

#include "../Utils/Enums.mqh"   // ENUM_INTRABAR_POLICY, ENUM_TIMEFRAMES

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

//--- Capacity of the per-slot default policy table. Kept as a literal 32 in
//--- every bound check below so the relocated bodies stay byte-identical to
//--- the originals; the constant exists only to size the member.
#define INTRABAR_POLICY_CONFIG_SLOTS 32

// Registration-time config facade over CEnterpriseStrategyManager
class CIntrabarPolicy
{
private:
    CEnterpriseStrategyManager* m_src;

    //--- L6-007: per-strategy-index intrabar policy configuration.
    //--- Moved verbatim from CEnterpriseStrategyManager::m_intrabarPolicyConfig,
    //--- including its "all slots default to OFF" initialisation (which used to
    //--- live in the manager's constructor).
    ENUM_INTRABAR_POLICY m_policyConfig[INTRABAR_POLICY_CONFIG_SLOTS];
    ENUM_TIMEFRAMES      m_timeframeConfig[INTRABAR_POLICY_CONFIG_SLOTS];

public:
    CIntrabarPolicy();

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    void                 SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy);
    ENUM_INTRABAR_POLICY GetIntrabarPolicyHelper(int idx);

    void                 SetStrategyTimeframeConfig(int strategyIndex, ENUM_TIMEFRAMES tf);
    ENUM_TIMEFRAMES      GetStrategyTimeframeConfig(int idx);

};

CIntrabarPolicy::CIntrabarPolicy() : m_src(NULL)
{
    for(int i = 0; i < INTRABAR_POLICY_CONFIG_SLOTS; i++)
    {
        m_policyConfig[i] = INTRABAR_POLICY_OFF;
        m_timeframeConfig[i] = PERIOD_CURRENT;
    }
}

void CIntrabarPolicy::SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy)
{
    if(strategyIndex >= 0 && strategyIndex < 32)
    {
        m_policyConfig[strategyIndex] = policy;
    }
}

void CIntrabarPolicy::SetStrategyTimeframeConfig(int strategyIndex, ENUM_TIMEFRAMES tf)
{
    if(strategyIndex >= 0 && strategyIndex < 32)
        m_timeframeConfig[strategyIndex] = tf;
}

//--- PERIOD_CURRENT here means "no operator timeframe for this row", so the catalog row's own
//--- timeframe applies - and every catalog row carries PERIOD_CURRENT, i.e. the chart timeframe.
ENUM_TIMEFRAMES CIntrabarPolicy::GetStrategyTimeframeConfig(int idx)
{
    if(idx >= 0 && idx < 32)
        return m_timeframeConfig[idx];
    return PERIOD_CURRENT;
}

// Slot -> default policy used by auto-registration (C8)
ENUM_INTRABAR_POLICY CIntrabarPolicy::GetIntrabarPolicyHelper(int idx)
{
    if(idx >= 0 && idx < 32 && m_policyConfig[idx] != INTRABAR_POLICY_OFF)
        return m_policyConfig[idx];
    // Default policies per strategy (matching original hardcoded values).
    // Batch 147: the always-LIVE fallback is fixed to the semantic slots
    // 7 (Mean Reversion) / 8 (Volatility Breakout) - the StrategyConfigBuilder
    // rows those two strategies actually own. The legacy 9/10 literals were removed.
    if(idx == 7 || idx == 8) return INTRABAR_POLICY_LIVE;
    return INTRABAR_POLICY_OFF;
}

#endif // INTRABAR_POLICY_MQH
