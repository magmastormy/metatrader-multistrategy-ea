// Strategy Manager Roster (Phase G - G4)
// Owns the registered-strategy roster that used to be loose state
// - StrategyEntry m_strategies[]  (the dynamic entry array)
// - int           m_strategyCount (live entry count)
// - int           m_maxStrategies (hard capacity gate, 25)
// together with EVERY narrow per-field accessor the Phase C slice
// modules already used (they keep calling the manager, whose
// accessors are now one-line forwarders into this object), the
// 35-field append block and the roster teardown loops.
// *** BEHAVIOUR CONTRACT ***
// Every body below is a byte-for-byte relocation of the manager's
// original inline body, including the bounds checks, the fallback
// return values and the deliberate "does NOT push to the IStrategy
// object" semantics of SetStrategyEnabledFlag. The ONLY signature
// adjustments are:
// - GetStrategyTimeframe() takes the manager's base timeframe as
// an explicit `fallback` argument (the roster does not own it);
// - AppendRegisteredStrategyEntry() takes the health monitor as
// an explicit argument so the original ordering
// (fill entry -> RegisterStrategy(weight) -> ++count) is
// preserved exactly.
// Neither is observable: both manager forwarders supply the value
// the original body read from its own member.
// This module deliberately has NO back-pointer to the manager: it
// is a leaf value object, held BY VALUE, and never observes manager
// state.
// NOTE: this header is an implementation detail of
// EnterpriseStrategyManager.mqh and is included from there (after
// the shared free helpers, before the manager class). It is not
// intended to be included standalone.
#ifndef STRATEGY_MGR_ROSTER_MQH
#define STRATEGY_MGR_ROSTER_MQH

#include "EntStrategyTypes.mqh"        // struct StrategyEntry (held BY VALUE in the array)
#include "StrategyHealthMonitor.mqh"   // CStrategyHealthMonitor::RegisterStrategy

//--- Fixed capacity of StrategyEntry::recentTrades[]. Kept as a literal 20 in
//--- every bound check below so the relocated bodies stay byte-identical to
//--- the originals.
#define STRATEGY_ROSTER_RECENT_TRADE_SLOTS 20

// Registered strategy roster (pure storage + narrow accessors)
class CStrategyMgrRoster
{
private:
    StrategyEntry m_strategies[];
    int           m_strategyCount;
    int           m_maxStrategies;   // Max strategy limit

public:
    CStrategyMgrRoster();

    //--- roster shape --------------------------------------------------------
    int  GetStrategyCount() const { return m_strategyCount; }
    int  GetMaxStrategies() const { return m_maxStrategies; }

    //--- name lookup ---------------------------------------------------------
    int  FindStrategyIndexByName(const string name) const;

    //=== read half (each accessor exposes exactly one field, verbatim) =======
    bool   IsStrategyEnabled(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].enabled : false; }
    IStrategy* GetStrategyPtr(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].strategy : NULL; }
    string GetStrategyName(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].name : ""; }
    double GetStrategyWeight(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].weight : 0.0; }
    int    GetStrategyRole(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].role : 0; }
    int    GetStrategyCluster(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].cluster : 0; }
    bool   IsStrategyLiveVotingEnabled(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].liveVotingEnabled : false; }
    int    GetStrategySuccessCount(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].successCount : 0; }
    int    GetStrategyFailCount(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].failCount : 0; }
    double GetStrategyAvgConfidence(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].avgConfidence : 0.0; }
    double GetStrategyParticipationScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].participationScore : 0.0; }
    double GetStrategyHealthScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].healthScore : 0.0; }
    double GetStrategyRecentWinRate(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].recentWinRate : 0.0; }
    double GetStrategyAvgProfit(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].avgProfit : 0.0; }
    double GetStrategyOriginalWeight(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].originalWeight : 0.0; }
    int      GetStrategyTotalTrades(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].totalTrades : 0; }
    int      GetStrategyWinningTrades(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].winningTrades : 0; }
    double   GetStrategyWinRate(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].winRate : 0.0; }
    double   GetStrategyAvgLoss(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].avgLoss : 0.0; }
    int      GetStrategyConsecutiveWins(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].consecutiveWins : 0; }
    int      GetStrategyConsecutiveLosses(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].consecutiveLosses : 0; }
    int      GetStrategyMaxConsecutiveLosses(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].maxConsecutiveLosses : 0; }
    int      GetStrategyRecentTradeIndex(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].recentTradeIndex : 0; }
    int      GetStrategyRecentTradeCount(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].recentTradeCount : 0; }
    double   GetStrategyRecentTrade(const int index, const int slot) const
             { return (index >= 0 && index < m_strategyCount && slot >= 0 && slot < 20)
                      ? m_strategies[index].recentTrades[slot] : 0.0; }
    bool     IsStrategyTemporarilyDisabled(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].temporarilyDisabled : false; }
    datetime GetStrategyDisabledUntil(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].disabledUntil : 0; }
    //--- `fallback` is the manager's m_baseTimeframe (see BEHAVIOUR CONTRACT)
    ENUM_TIMEFRAMES GetStrategyTimeframe(const int index, const ENUM_TIMEFRAMES fallback) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].timeframe : fallback; }
    int    GetStrategyIntrabarPolicyRaw(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].intrabarPolicy : (int)INTRABAR_POLICY_OFF; }
    bool   GetStrategyIntrabarEligible(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].intrabarEligible : false; }
    bool   IsStrategyProbeEligible(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].isProbeEligible : false; }
    double GetStrategyReadinessScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].readinessScore : 0.0; }
    double GetStrategyContextScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].contextScore : 0.0; }
    double GetStrategyCostScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].costScore : 0.0; }

    //=== write half (dumb field writers, all bounds-checked) =================
    //--- Mirrors exactly what UpdateStrategyWeights() used to do inline: write
    //--- the entry weight and push it to the strategy object, WITHOUT touching
    //--- the health monitor.
    void ApplyRawStrategyWeight(const int index, const double weight);

    void SetStrategyTotalTrades(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].totalTrades = value; }
    void SetStrategySuccessCount(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].successCount = value; }
    void SetStrategyFailCount(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].failCount = value; }
    void SetStrategyWinningTrades(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].winningTrades = value; }
    void SetStrategyConsecutiveWins(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].consecutiveWins = value; }
    void SetStrategyConsecutiveLosses(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].consecutiveLosses = value; }
    void SetStrategyMaxConsecutiveLosses(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].maxConsecutiveLosses = value; }
    void SetStrategyAvgProfit(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].avgProfit = value; }
    void SetStrategyAvgLoss(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].avgLoss = value; }
    void SetStrategyWinRate(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].winRate = value; }
    void SetStrategyProfitFactor(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].profitFactor = value; }
    void SetStrategySharpeRatio(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].sharpeRatio = value; }
    void SetStrategyRecentWinRate(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].recentWinRate = value; }
    void SetStrategyHealthScore(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].healthScore = value; }
    void SetStrategyLastUpdate(const int index, const datetime value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].lastUpdate = value; }
    void SetStrategyTemporarilyDisabled(const int index, const bool value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].temporarilyDisabled = value; }
    void SetStrategyDisabledUntil(const int index, const datetime value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].disabledUntil = value; }
    //--- Writes ONLY the entry flag. It deliberately does NOT push the value to
    //--- the IStrategy object: CheckStrategyDisabling/ReEnabling never did, and
    //--- EnableStrategy/DisableStrategy push it themselves via GetStrategyPtr().
    void SetStrategyEnabledFlag(const int index, const bool value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].enabled = value; }
    //--- slot bound is the fixed recentTrades[20] capacity; unreachable in
    //--- practice because m_rollingWindowSize is fixed at 20 (no setter).
    void SetStrategyRecentTrade(const int index, const int slot, const double value)
         { if(index >= 0 && index < m_strategyCount && slot >= 0 && slot < 20)
               m_strategies[index].recentTrades[slot] = value; }
    void SetStrategyRecentTradeIndex(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].recentTradeIndex = value; }
    void SetStrategyRecentTradeCount(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].recentTradeCount = value; }
    void SetStrategyLastSignal(const int index, const ENUM_TRADE_SIGNAL value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].lastSignal = value; }
    void SetStrategyLastSignalConfidence(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].lastSignalConfidence = value; }
    void SetStrategyRole(const int index, const int role)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].role = role; }
    void SetStrategyCluster(const int index, const int cluster)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].cluster = cluster; }
    void SetStrategyLiveVotingEnabled(const int index, const bool enabled)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].liveVotingEnabled = enabled; }
    void SetStrategyIntrabarPolicyRaw(const int index, const int policy)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].intrabarPolicy = policy; }
    void SetStrategyIntrabarEligible(const int index, const bool eligible)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].intrabarEligible = eligible; }

    //=== roster mutation ====================================================
    //--- 35-field StrategyEntry append. Mirrors the original RegisterStrategy
    //--- append block byte-for-byte (no registry/logic changes).
    void AppendRegisteredStrategyEntry(IStrategy* strategy, const string name, bool enabled,
                                       double weight, ENUM_STRATEGY_TIER tier,
                                       ENUM_TIMEFRAMES resolvedTf,
                                       ENUM_INTRABAR_POLICY intrabarPolicy,
                                       ENUM_STRATEGY_ROLE role,
                                       ENUM_STRATEGY_CLUSTER cluster,
                                       bool liveVotingEnabled,
                                       CStrategyHealthMonitor* healthMonitor);

    //--- By-name weight mutator. Kept here (not in C4) because its body writes
    //--- the roster array directly AND pushes to the health monitor, which the
    //--- logic-free ApplyRawStrategyWeight() deliberately does not do. The
    //--- health monitor is passed in because the roster does not own it.
    bool UpdateStrategyWeightByName(const string name, const double weight,
                                    CStrategyHealthMonitor* healthMonitor);

    //--- By-name confidence-threshold mutator (writes through the IStrategy
    //--- object held in the roster entry; no roster field is modified).
    bool SetStrategyConfidenceThresholdByName(const string name, const double threshold);

    //--- Deinit()/destructor teardown loop (identical in both call sites).
    void DeleteAllStrategies();
    //--- Deinit()-only roster reset (the destructor deliberately did NOT do it).
    void ClearRoster();
};

// Constructor - relocated from the manager's initialiser list
CStrategyMgrRoster::CStrategyMgrRoster() :
    m_strategyCount(0),
    m_maxStrategies(25)
{
    ArrayResize(m_strategies, 0);
}

// Name -> index lookup (-1 when absent)
int CStrategyMgrRoster::FindStrategyIndexByName(const string name) const
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].name == name)
            return i;
    }
    return -1;
}

// Narrow raw weight mutator (C4)
void CStrategyMgrRoster::ApplyRawStrategyWeight(const int index, const double weight)
{
    if(index < 0 || index >= m_strategyCount)
        return;
    m_strategies[index].weight = weight;
    if(m_strategies[index].strategy != NULL)
        m_strategies[index].strategy.SetWeight(weight);
}

// 35-field StrategyEntry append
// Mirrors the original RegisterStrategy append block exactly.
void CStrategyMgrRoster::AppendRegisteredStrategyEntry(IStrategy* strategy, const string name, bool enabled,
                                                       double weight, ENUM_STRATEGY_TIER tier,
                                                       ENUM_TIMEFRAMES resolvedTf,
                                                       ENUM_INTRABAR_POLICY intrabarPolicy,
                                                       ENUM_STRATEGY_ROLE role,
                                                       ENUM_STRATEGY_CLUSTER cluster,
                                                       bool liveVotingEnabled,
                                                       CStrategyHealthMonitor* healthMonitor)
{
    int newSize = m_strategyCount + 1;
    ArrayResize(m_strategies, newSize);

    m_strategies[m_strategyCount].strategy = strategy;
    m_strategies[m_strategyCount].name = name;
    m_strategies[m_strategyCount].enabled = enabled;
    m_strategies[m_strategyCount].intrabarEligible = (intrabarPolicy == INTRABAR_POLICY_LIVE);
    m_strategies[m_strategyCount].intrabarPolicy = (int)intrabarPolicy;
    m_strategies[m_strategyCount].liveVotingEnabled = liveVotingEnabled;
    m_strategies[m_strategyCount].role = (int)role;
    m_strategies[m_strategyCount].cluster = (int)cluster;
    m_strategies[m_strategyCount].tier = tier;
    m_strategies[m_strategyCount].weight = weight;
    m_strategies[m_strategyCount].originalWeight = weight;
    m_strategies[m_strategyCount].timeframe = resolvedTf;
    m_strategies[m_strategyCount].successCount = 0;
    m_strategies[m_strategyCount].failCount = 0;
    m_strategies[m_strategyCount].healthScore = 0.75;
    m_strategies[m_strategyCount].participationScore = 0.90;
    m_strategies[m_strategyCount].avgConfidence = 0;
    m_strategies[m_strategyCount].lastSignal = TRADE_SIGNAL_NONE;
    m_strategies[m_strategyCount].lastSignalConfidence = 0.0;
    m_strategies[m_strategyCount].lastEvaluationTime = 0;
    m_strategies[m_strategyCount].consecutiveFilterCount = 0;

    m_strategies[m_strategyCount].totalTrades = 0;
    m_strategies[m_strategyCount].winningTrades = 0;
    m_strategies[m_strategyCount].winRate = 0.0;
    m_strategies[m_strategyCount].avgProfit = 0.0;
    m_strategies[m_strategyCount].avgLoss = 0.0;
    m_strategies[m_strategyCount].profitFactor = 0.0;
    m_strategies[m_strategyCount].sharpeRatio = 0.0;
    m_strategies[m_strategyCount].recentTradeIndex = 0;
    m_strategies[m_strategyCount].recentTradeCount = 0;
    m_strategies[m_strategyCount].recentWinRate = 0.0;
    m_strategies[m_strategyCount].consecutiveLosses = 0;
    m_strategies[m_strategyCount].maxConsecutiveLosses = 0;
    m_strategies[m_strategyCount].consecutiveWins = 0;
    m_strategies[m_strategyCount].temporarilyDisabled = false;
    m_strategies[m_strategyCount].disabledUntil = 0;
    m_strategies[m_strategyCount].lastUpdate = 0;

    ArrayInitialize(m_strategies[m_strategyCount].recentTrades, 0.0);
    ArrayInitialize(m_strategies[m_strategyCount].regimePerformance, 0.0);
    ArrayInitialize(m_strategies[m_strategyCount].regimeTrades, 0);

    if(healthMonitor != NULL)
        healthMonitor.RegisterStrategy(weight);

    m_strategyCount++;
}

// By-name weight mutator (relocated verbatim)
// Original: CEnterpriseStrategyManager::UpdateStrategyWeightByName
// The health monitor is supplied by the caller because the roster
// does not own it; everything else is byte-identical.
bool CStrategyMgrRoster::UpdateStrategyWeightByName(const string name, const double weight,
                                                    CStrategyHealthMonitor* healthMonitor)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    double sanitizedWeight = MathMax(0.0, MathMin(10.0, weight));
    m_strategies[index].weight = sanitizedWeight;
    if(m_strategies[index].strategy != NULL)
        m_strategies[index].strategy.SetWeight(sanitizedWeight);

    // L1-007: Update health monitor
    if(healthMonitor != NULL)
        healthMonitor.SetStrategyWeight(index, sanitizedWeight);

    return true;
}

// By-name confidence threshold mutator (relocated verbatim)
// Original: CEnterpriseStrategyManager::
bool CStrategyMgrRoster::SetStrategyConfidenceThresholdByName(const string name, const double threshold)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    if(m_strategies[index].strategy == NULL)
        return false;

    m_strategies[index].strategy.SetConfidenceThreshold(threshold);
    return true;
}

// Clean up strategies with explicit Deinit call
void CStrategyMgrRoster::DeleteAllStrategies()
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].strategy != NULL)
        {
            m_strategies[i].strategy.Deinit();
            delete m_strategies[i].strategy;
            m_strategies[i].strategy = NULL;
        }
    }
}

// Reset the roster (Deinit only)
void CStrategyMgrRoster::ClearRoster()
{
    m_strategyCount = 0;
    ArrayResize(m_strategies, 0);
}

#endif // STRATEGY_MGR_ROSTER_MQH
