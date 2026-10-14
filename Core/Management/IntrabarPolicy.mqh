// Intrabar (within-bar) signal-handling policy: the per-slot default policy table, the
// slot -> default resolution used while auto-registering, and the registered-entry
// resolution with its legacy intrabarEligible fallback.
// MUTATES the manager, so the back-pointer is non-const and writes go through the
// manager's narrow per-field accessors.
// m_sparseIntrabar* stay in the manager despite the prefix: they are consensus QUORUM
// parameters read by CalculateEffectiveQuorumParamsInternal, not intrabar policy.
// Implementation detail of EnterpriseStrategyManager.mqh - included from there, not standalone.
#ifndef INTRABAR_POLICY_MQH
#define INTRABAR_POLICY_MQH

#include "../Utils/Enums.mqh"   // ENUM_INTRABAR_POLICY

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

//--- Capacity of the per-slot default policy table. Kept as a literal 32 in
//--- every bound check below so the relocated bodies stay byte-identical to
//--- the originals; the constant exists only to size the member.
#define INTRABAR_POLICY_CONFIG_SLOTS 32

// Intrabar policy facade over CEnterpriseStrategyManager
class CIntrabarPolicy
{
private:
    CEnterpriseStrategyManager* m_src;

    //--- L6-007: per-strategy-index intrabar policy configuration.
    //--- Moved verbatim from CEnterpriseStrategyManager::m_intrabarPolicyConfig,
    //--- including its "all slots default to OFF" initialisation (which used to
    //--- live in the manager's constructor).
    ENUM_INTRABAR_POLICY m_policyConfig[INTRABAR_POLICY_CONFIG_SLOTS];

public:
    CIntrabarPolicy();

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    void                 SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy);
    ENUM_INTRABAR_POLICY GetStrategyIntrabarPolicyConfig(int strategyIndex) const;
    ENUM_INTRABAR_POLICY GetIntrabarPolicyHelper(int idx);

    ENUM_INTRABAR_POLICY GetStrategyIntrabarPolicy(const int strategyIndex) const;
    bool                 IsStrategyIntrabarLiveEligible(const int strategyIndex) const;
    bool                 IsStrategyIntrabarProbeEligible(const int strategyIndex) const;

    bool SetStrategyIntrabarEligibilityByName(const string name, bool enabled);
    bool SetStrategyIntrabarPolicyByName(const string name, ENUM_INTRABAR_POLICY policy);
};

CIntrabarPolicy::CIntrabarPolicy() : m_src(NULL)
{
    for(int i = 0; i < INTRABAR_POLICY_CONFIG_SLOTS; i++)
    {
        m_policyConfig[i] = INTRABAR_POLICY_OFF;
    }
}

void CIntrabarPolicy::SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy)
{
    if(strategyIndex >= 0 && strategyIndex < 32)
    {
        m_policyConfig[strategyIndex] = policy;
    }
}

// Read the configured per-slot policy (OFF when out of range)
ENUM_INTRABAR_POLICY CIntrabarPolicy::GetStrategyIntrabarPolicyConfig(int strategyIndex) const
{
    if(strategyIndex >= 0 && strategyIndex < 32)
    {
        return m_policyConfig[strategyIndex];
    }
    return INTRABAR_POLICY_OFF;
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

// Resolved policy for a registered strategy entry
// Falls back to the legacy intrabarEligible flag when the stored
// raw policy ordinal is out of the enum range (verbatim).
ENUM_INTRABAR_POLICY CIntrabarPolicy::GetStrategyIntrabarPolicy(const int strategyIndex) const
{
    if(m_src == NULL)
        return INTRABAR_POLICY_OFF;

    if(strategyIndex < 0 || strategyIndex >= m_src.GetStrategyCount())
        return INTRABAR_POLICY_OFF;

    int rawPolicy = m_src.GetStrategyIntrabarPolicyRaw(strategyIndex);
    if(rawPolicy < (int)INTRABAR_POLICY_OFF || rawPolicy > (int)INTRABAR_POLICY_LIVE)
        return m_src.GetStrategyIntrabarEligible(strategyIndex) ? INTRABAR_POLICY_LIVE : INTRABAR_POLICY_OFF;

    return (ENUM_INTRABAR_POLICY)rawPolicy;
}

bool CIntrabarPolicy::IsStrategyIntrabarLiveEligible(const int strategyIndex) const
{
    return (GetStrategyIntrabarPolicy(strategyIndex) == INTRABAR_POLICY_LIVE);
}

bool CIntrabarPolicy::IsStrategyIntrabarProbeEligible(const int strategyIndex) const
{
    return (GetStrategyIntrabarPolicy(strategyIndex) == INTRABAR_POLICY_PROBE);
}

// By-name eligibility shim (LIVE when enabled, OFF otherwise)
bool CIntrabarPolicy::SetStrategyIntrabarEligibilityByName(const string name, bool enabled)
{
    return SetStrategyIntrabarPolicyByName(name, enabled ? INTRABAR_POLICY_LIVE : INTRABAR_POLICY_OFF);
}

bool CIntrabarPolicy::SetStrategyIntrabarPolicyByName(const string name, ENUM_INTRABAR_POLICY policy)
{
    if(m_src == NULL)
        return false;

    int index = m_src.GetStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_src.SetStrategyIntrabarPolicyRaw(index, (int)policy);
    m_src.SetStrategyIntrabarEligible(index, (policy == INTRABAR_POLICY_LIVE));
    PrintFormat("[EnterpriseStrategyManager] Intrabar policy updated: %s => %s",
                name, IntrabarPolicyToString(policy));
    return true;
}

#endif // INTRABAR_POLICY_MQH
