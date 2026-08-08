//+------------------------------------------------------------------+
//| Intrabar Policy (Phase C, Slice 4 - C6)                          |
//| Intrabar (within-bar) signal-handling policy extracted from       |
//| CEnterpriseStrategyManager:                                       |
//|   - the per-slot default policy table (L6-007), formerly          |
//|     CEnterpriseStrategyManager::m_intrabarPolicyConfig[32], whose |
//|     ownership moves here wholesale (same treatment C3 gave the    |
//|     post-consensus validator config block);                       |
//|   - SetStrategyIntrabarPolicyConfig / GetStrategyIntrabarPolicyConfig|
//|     (per-slot table accessors, driven by the orchestrator);       |
//|   - GetIntrabarPolicyHelper   (slot -> default policy resolution  |
//|     used while auto-registering strategies);                      |
//|   - GetStrategyIntrabarPolicy (registered-entry policy resolution |
//|     with the legacy intrabarEligible fallback);                   |
//|   - IsStrategyIntrabarLiveEligible / IsStrategyIntrabarProbeEligible|
//|     (LIVE / PROBE gating predicates);                             |
//|   - SetStrategyIntrabarPolicyByName / SetStrategyIntrabarEligibilityByName|
//|     (by-name policy mutators).                                    |
//|                                                                   |
//| Like C4/C5/C7 this module MUTATES the manager, so it holds a      |
//| NON-const back-pointer and writes through the manager's narrow    |
//| per-field accessors. It mirrors no injected manager pointer, so   |
//| (like Slice 2/3) it needs no re-sync on Deinit.                   |
//|                                                                   |
//| MOVED WHOLESALE, NO FORWARDER RETAINED:                           |
//|   GetStrategyIntrabarPolicy, IsStrategyIntrabarLiveEligible and   |
//|   IsStrategyIntrabarProbeEligible were PRIVATE manager helpers    |
//|   with zero call sites anywhere in the codebase (only each other),|
//|   so no forwarder is kept - identical to how Slice 2 treated the  |
//|   validator's internal leaf checks.                               |
//|                                                                   |
//| DELIBERATELY NOT MOVED:                                           |
//|   - m_intrabarMinQuorum / m_intrabarDynamicQuorumEnabled /        |
//|     m_intrabarSingleVoterMinConfidence / m_supportFloorIntrabar / |
//|     m_sparseIntrabar* and their setters. Despite the "intrabar"   |
//|     prefix these are consensus QUORUM parameters read by the C9   |
//|     core (CalculateEffectiveQuorumParamsInternal,                 |
//|     EvaluateConsensusProbeOnlyInternal) - C9 is a hard guard.     |
//|   - StrategyEntry::isProbeEligible. It is written and read only   |
//|     inside the C9 consensus bodies.                               |
//|                                                                   |
//| NOTE: this header is an implementation detail of                  |
//| EnterpriseStrategyManager.mqh and is included from there (after   |
//| the shared free helpers, before the manager class). It is not     |
//| intended to be included standalone.                               |
//+------------------------------------------------------------------+
#ifndef INTRABAR_POLICY_MQH
#define INTRABAR_POLICY_MQH

#include "../Utils/Enums.mqh"   // ENUM_INTRABAR_POLICY

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

//--- Capacity of the per-slot default policy table. Kept as a literal 32 in
//--- every bound check below so the relocated bodies stay byte-identical to
//--- the originals; the constant exists only to size the member.
#define INTRABAR_POLICY_CONFIG_SLOTS 32

//+------------------------------------------------------------------+
//| Intrabar policy facade over CEnterpriseStrategyManager            |
//+------------------------------------------------------------------+
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

    //--- per-slot default policy table (L6-007)
    void                 SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy);
    ENUM_INTRABAR_POLICY GetStrategyIntrabarPolicyConfig(int strategyIndex) const;
    ENUM_INTRABAR_POLICY GetIntrabarPolicyHelper(int idx);

    //--- resolved policy / gating predicates for a registered strategy entry
    ENUM_INTRABAR_POLICY GetStrategyIntrabarPolicy(const int strategyIndex) const;
    bool                 IsStrategyIntrabarLiveEligible(const int strategyIndex) const;
    bool                 IsStrategyIntrabarProbeEligible(const int strategyIndex) const;

    //--- by-name policy mutators
    bool SetStrategyIntrabarEligibilityByName(const string name, bool enabled);
    bool SetStrategyIntrabarPolicyByName(const string name, ENUM_INTRABAR_POLICY policy);
};

//+------------------------------------------------------------------+
//| Constructor - L6-007: initialise policy config with defaults      |
//+------------------------------------------------------------------+
CIntrabarPolicy::CIntrabarPolicy() : m_src(NULL)
{
    for(int i = 0; i < INTRABAR_POLICY_CONFIG_SLOTS; i++)
    {
        m_policyConfig[i] = INTRABAR_POLICY_OFF;
    }
}

//+------------------------------------------------------------------+
//| Intrabar policy configuration per strategy index (L6-007)         |
//+------------------------------------------------------------------+
void CIntrabarPolicy::SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy)
{
    if(strategyIndex >= 0 && strategyIndex < 32)
    {
        m_policyConfig[strategyIndex] = policy;
    }
}

//+------------------------------------------------------------------+
//| Read the configured per-slot policy (OFF when out of range)       |
//+------------------------------------------------------------------+
ENUM_INTRABAR_POLICY CIntrabarPolicy::GetStrategyIntrabarPolicyConfig(int strategyIndex) const
{
    if(strategyIndex >= 0 && strategyIndex < 32)
    {
        return m_policyConfig[strategyIndex];
    }
    return INTRABAR_POLICY_OFF;
}

//+------------------------------------------------------------------+
//| Slot -> default policy used by auto-registration (C8)             |
//+------------------------------------------------------------------+
ENUM_INTRABAR_POLICY CIntrabarPolicy::GetIntrabarPolicyHelper(int idx)
{
    if(idx >= 0 && idx < 32 && m_policyConfig[idx] != INTRABAR_POLICY_OFF)
        return m_policyConfig[idx];
    // Default policies per strategy (matching original hardcoded values)
    if(idx == 9 || idx == 10) return INTRABAR_POLICY_LIVE; // Mean Reversion, Volatility Breakout
    return INTRABAR_POLICY_OFF;
}

//+------------------------------------------------------------------+
//| Resolved policy for a registered strategy entry                   |
//| Falls back to the legacy intrabarEligible flag when the stored    |
//| raw policy ordinal is out of the enum range (verbatim).           |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| LIVE gating predicate                                             |
//+------------------------------------------------------------------+
bool CIntrabarPolicy::IsStrategyIntrabarLiveEligible(const int strategyIndex) const
{
    return (GetStrategyIntrabarPolicy(strategyIndex) == INTRABAR_POLICY_LIVE);
}

//+------------------------------------------------------------------+
//| PROBE gating predicate                                            |
//+------------------------------------------------------------------+
bool CIntrabarPolicy::IsStrategyIntrabarProbeEligible(const int strategyIndex) const
{
    return (GetStrategyIntrabarPolicy(strategyIndex) == INTRABAR_POLICY_PROBE);
}

//+------------------------------------------------------------------+
//| By-name eligibility shim (LIVE when enabled, OFF otherwise)       |
//+------------------------------------------------------------------+
bool CIntrabarPolicy::SetStrategyIntrabarEligibilityByName(const string name, bool enabled)
{
    return SetStrategyIntrabarPolicyByName(name, enabled ? INTRABAR_POLICY_LIVE : INTRABAR_POLICY_OFF);
}

//+------------------------------------------------------------------+
//| By-name policy mutator                                            |
//+------------------------------------------------------------------+
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
