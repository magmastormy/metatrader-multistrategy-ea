//+------------------------------------------------------------------+
//| SymbolScanScheduler.mqh - Symbol scan scheduling & intrabar scoring |
//| Extracted from MultiStrategyAutonomousEA.mq5                     |
//+------------------------------------------------------------------+
#ifndef SYMBOL_SCAN_SCHEDULER_MQH
#define SYMBOL_SCAN_SCHEDULER_MQH

#include "..\Utils\Enums.mqh"

// Forward declaration for manager pointer storage
class CEnterpriseStrategyManager;

//+------------------------------------------------------------------+
//| Per-symbol scan state tracking                                    |
//+------------------------------------------------------------------+
struct SSymbolScanState
{
    int consecutiveRawNone;
    int consecutiveZeroVote;
    int consecutiveReadinessFault;
    int nearMissCount;
    datetime lastGeneratedTime;
    datetime lastNearMissTime;
    datetime nextEligibleIntrabarTime;
    int intrabarBackoffTier;

    void Reset()
    {
        consecutiveRawNone = 0;
        consecutiveZeroVote = 0;
        consecutiveReadinessFault = 0;
        nearMissCount = 0;
        lastGeneratedTime = 0;
        lastNearMissTime = 0;
        nextEligibleIntrabarTime = 0;
        intrabarBackoffTier = 0;
    }
};

//+------------------------------------------------------------------+
//| CSymbolScanScheduler - Symbol scan scheduling & intrabar scoring  |
//+------------------------------------------------------------------+
class CSymbolScanScheduler
{
private:
    // Encapsulated arrays (formerly g_lastSymbolBarTimes, g_lastIntrabarScanTime, etc.)
    datetime            m_lastSymbolBarTimes[];
    datetime            m_lastIntrabarScanTime[];
    bool                m_pendingNewBarScans[];
    SSymbolScanState    m_symbolScanStates[];

    // Encapsulated scalars (formerly g_symbolEvalStartIndex, etc.)
    int                 m_symbolEvalStartIndex;
    datetime            m_lastSignalEvalSecond;
    datetime            m_lastScalpFastPathSecond;
    datetime            m_lastExternalCapacityLogTime;

    // Manager references (set via SetManagers)
    CEnterpriseStrategyManager* m_managers[];
    string              m_symbols[];
    int                 m_managerCount;

    // Input parameter snapshots (set via SetInputParams)
    int                 m_intrabarScanSeconds;
    int                 m_intrabarBackoffMaxSeconds;

public:
    //--- Constructor / Destructor
    CSymbolScanScheduler() :
        m_symbolEvalStartIndex(0),
        m_lastSignalEvalSecond(0),
        m_lastScalpFastPathSecond(0),
        m_lastExternalCapacityLogTime(0),
        m_managerCount(0),
        m_intrabarScanSeconds(5),
        m_intrabarBackoffMaxSeconds(60)
    {
    }

    ~CSymbolScanScheduler()
    {
        ArrayResize(m_lastSymbolBarTimes, 0);
        ArrayResize(m_lastIntrabarScanTime, 0);
        ArrayResize(m_pendingNewBarScans, 0);
        ArrayResize(m_symbolScanStates, 0);
        ArrayResize(m_managers, 0);
        ArrayResize(m_symbols, 0);
    }

    //--- Initialization
    void SetManagers(CEnterpriseStrategyManager* &managers[], string &symbols[], int count)
    {
        ArrayResize(m_managers, count);
        ArrayResize(m_symbols, count);
        for(int i = 0; i < count; i++)
        {
            m_managers[i] = managers[i];
            m_symbols[i] = symbols[i];
        }
        m_managerCount = count;
    }

    void SetInputParams(int intrabarScanSeconds, int intrabarBackoffMaxSeconds)
    {
        m_intrabarScanSeconds = intrabarScanSeconds;
        m_intrabarBackoffMaxSeconds = intrabarBackoffMaxSeconds;
    }

    void ResetOnInit()
    {
        m_symbolEvalStartIndex = 0;
        m_lastSignalEvalSecond = 0;
        m_lastScalpFastPathSecond = 0;
        m_lastExternalCapacityLogTime = 0;
    }

    //--- Extracted functions

    void ResetSymbolScanStates(const int size)
    {
        ArrayResize(m_symbolScanStates, size);
        for(int i = 0; i < size; i++)
            m_symbolScanStates[i].Reset();

        ArrayResize(m_pendingNewBarScans, size);
        for(int i = 0; i < size; i++)
            m_pendingNewBarScans[i] = false;
    }

    bool IsSymbolSchedulerStateAligned()
    {
        int size = m_managerCount;
        return (ArraySize(m_lastSymbolBarTimes) == size &&
                ArraySize(m_lastIntrabarScanTime) == size &&
                ArraySize(m_pendingNewBarScans) == size &&
                ArraySize(m_symbolScanStates) == size);
    }

    void RebuildSymbolSchedulerState(const string reason)
    {
        int size = m_managerCount;
        ArrayResize(m_lastSymbolBarTimes, size);
        ArrayInitialize(m_lastSymbolBarTimes, 0);
        ArrayResize(m_lastIntrabarScanTime, size);
        ArrayInitialize(m_lastIntrabarScanTime, 0);
        ResetSymbolScanStates(size);

        // Prime pending scans inline
        if(ArraySize(m_pendingNewBarScans) != size)
            ArrayResize(m_pendingNewBarScans, size);

        for(int i = 0; i < size; i++)
        {
            m_pendingNewBarScans[i] = true;
            if(i < ArraySize(m_symbolScanStates))
            {
                m_symbolScanStates[i].intrabarBackoffTier = 0;
                m_symbolScanStates[i].nextEligibleIntrabarTime = 0;
            }
        }

        PrintFormat("[SCHEDULER-STATE] reason=%s | symbols=%d | last_bar=%d | intrabar=%d | pending=%d | scan_states=%d",
                    reason,
                    size,
                    ArraySize(m_lastSymbolBarTimes),
                    ArraySize(m_lastIntrabarScanTime),
                    ArraySize(m_pendingNewBarScans),
                    ArraySize(m_symbolScanStates));
    }

    int CountPendingNewBarScans()
    {
        int total = 0;
        for(int i = 0; i < ArraySize(m_pendingNewBarScans); i++)
        {
            if(m_pendingNewBarScans[i])
                total++;
        }
        return total;
    }

    bool IsReadinessRelatedVeto(const string vetoCode)
    {
        return (StringFind(vetoCode, "readiness") >= 0 ||
                vetoCode == "context_gate" ||
                vetoCode == "cost_gate");
    }

    int GetIntrabarBackoffSeconds(const int tier)
    {
        int baseInterval = MathMax(1, m_intrabarScanSeconds);
        int maxBackoff = MathMax(baseInterval, m_intrabarBackoffMaxSeconds);
        if(tier >= 2)
            return MathMin(maxBackoff, MathMax(60, baseInterval));
        if(tier == 1)
            return MathMin(maxBackoff, MathMax(30, baseInterval));
        return baseInterval;
    }

    double ScoreSymbolForIntrabar(const int symIdx, const datetime nowTime, const bool allowScheduledOverride = false)
    {
        if(symIdx < 0 || symIdx >= ArraySize(m_symbolScanStates))
            return -1000000.0;

        SSymbolScanState state = m_symbolScanStates[symIdx];
        if(state.intrabarBackoffTier >= 3 && !allowScheduledOverride)
            return -1000000.0;
        if(state.nextEligibleIntrabarTime > 0 && nowTime < state.nextEligibleIntrabarTime && !allowScheduledOverride)
            return -1000000.0;

        double score = 0.0;
        int recentNearMissAge = (state.lastNearMissTime > 0) ? (int)(nowTime - state.lastNearMissTime) : 999999;
        int recentGeneratedAge = (state.lastGeneratedTime > 0) ? (int)(nowTime - state.lastGeneratedTime) : 999999;

        if(recentNearMissAge <= 90)
            score += 4.0;
        if(recentGeneratedAge <= 120)
            score += 2.5;
        if(state.consecutiveReadinessFault == 0)
            score += 1.0;

        score += MathMin(3.0, (double)state.nearMissCount * 0.25);
        score -= MathMin(3.0, (double)state.consecutiveRawNone * 0.20);
        score -= MathMin(3.0, (double)state.consecutiveZeroVote * 0.25);
        score -= (double)state.intrabarBackoffTier * 0.50;
        if(allowScheduledOverride)
        {
            if(state.intrabarBackoffTier >= 3)
                score -= 1.25;
            if(state.nextEligibleIntrabarTime > 0 && nowTime < state.nextEligibleIntrabarTime)
                score -= 0.75;
        }

        return score;
    }

    void UpdateSymbolScanStateAfterDecision(const string symbol,
                                            const ulong cycleId,
                                            const int symIdx,
                                            const bool intrabarMode,
                                            const int cycleSignalsGenerated,
                                            const int cycleSignalsAfterPipeline,
                                            const SConsensusDecisionContext &context,
                                            const datetime nowTime)
    {
        if(symIdx < 0 || symIdx >= ArraySize(m_symbolScanStates))
            return;

        SSymbolScanState state = m_symbolScanStates[symIdx];
        if(context.signal != TRADE_SIGNAL_NONE || cycleSignalsGenerated > 0)
            state.lastGeneratedTime = nowTime;

        if(!intrabarMode)
        {
            state.nextEligibleIntrabarTime = nowTime;
            state.intrabarBackoffTier = 0;
            if(context.signal != TRADE_SIGNAL_NONE)
            {
                state.consecutiveRawNone = 0;
                state.consecutiveZeroVote = 0;
                state.consecutiveReadinessFault = 0;
                state.nearMissCount = 0;
            }
            m_symbolScanStates[symIdx] = state;
            return;
        }

        if(context.signal != TRADE_SIGNAL_NONE)
        {
            state.consecutiveRawNone = 0;
            state.consecutiveZeroVote = 0;
            state.consecutiveReadinessFault = 0;
            state.nearMissCount = 0;
            state.intrabarBackoffTier = 0;
            state.nextEligibleIntrabarTime = nowTime + GetIntrabarBackoffSeconds(0);
            m_symbolScanStates[symIdx] = state;
            return;
        }

        if(cycleSignalsGenerated <= 0)
            state.consecutiveRawNone++;
        else
            state.consecutiveRawNone = 0;

        if(context.vetoCode == "zero_voter")
            state.consecutiveZeroVote++;
        else if(cycleSignalsAfterPipeline > 0)
            state.consecutiveZeroVote = 0;

        if(IsReadinessRelatedVeto(context.vetoCode))
            state.consecutiveReadinessFault++;
        else if(context.vetoCode != "")
            state.consecutiveReadinessFault = 0;

        bool nearMiss = (context.quorumGap > 0.0 && context.quorumGap <= 0.20) ||
                        context.vetoCode == "single_voter_confidence" ||
                        context.vetoCode == "sparse_support";
        if(nearMiss)
        {
            state.nearMissCount++;
            state.lastNearMissTime = nowTime;
        }
        else if(context.vetoCode != "")
        {
            state.nearMissCount = 0;
        }

        // Relaxed backoff tiers to prevent hours of inactivity
        // Old: 3/8/15 cycles → tier 1/2/3; tier 3 skipped for 5+ min
        // New: 5/10/20 cycles → tier 1/2/3; tier 3 skipped for 2 min
        int nextTier = 0;
        if(state.consecutiveRawNone >= 20 || state.consecutiveZeroVote >= 20)
            nextTier = 3;
        else if(state.consecutiveRawNone >= 10 || state.consecutiveZeroVote >= 10)
            nextTier = 2;
        else if(state.consecutiveRawNone >= 5 || state.consecutiveZeroVote >= 5)
            nextTier = 1;

        if(nextTier != state.intrabarBackoffTier)
        {
            PrintFormat("[INTRABAR-BACKOFF] cycle=%I64u | %s | tier=%d | raw_none=%d | zero_vote=%d | readiness=%d | veto=%s",
                        cycleId,
                        symbol,
                        nextTier,
                        state.consecutiveRawNone,
                        state.consecutiveZeroVote,
                        state.consecutiveReadinessFault,
                        context.vetoCode);
            state.intrabarBackoffTier = nextTier;
        }

        if(state.intrabarBackoffTier >= 3)
            state.nextEligibleIntrabarTime = nowTime + MathMax(120, GetIntrabarBackoffSeconds(2));
        else
            state.nextEligibleIntrabarTime = nowTime + GetIntrabarBackoffSeconds(state.intrabarBackoffTier);

        m_symbolScanStates[symIdx] = state;
    }

    //--- Direct array access for call-site compatibility

    // Last symbol bar times
    datetime GetLastSymbolBarTime(const int idx) const
    {
        if(idx < 0 || idx >= ArraySize(m_lastSymbolBarTimes)) return 0;
        return m_lastSymbolBarTimes[idx];
    }

    void SetLastSymbolBarTime(const int idx, const datetime val)
    {
        if(idx >= 0 && idx < ArraySize(m_lastSymbolBarTimes))
            m_lastSymbolBarTimes[idx] = val;
    }

    // Last intrabar scan time
    datetime GetLastIntrabarScanTime(const int idx) const
    {
        if(idx < 0 || idx >= ArraySize(m_lastIntrabarScanTime)) return 0;
        return m_lastIntrabarScanTime[idx];
    }

    void SetLastIntrabarScanTime(const int idx, const datetime val)
    {
        if(idx >= 0 && idx < ArraySize(m_lastIntrabarScanTime))
            m_lastIntrabarScanTime[idx] = val;
    }

    // Pending new bar scans
    bool IsPendingNewBarScan(const int idx) const
    {
        if(idx < 0 || idx >= ArraySize(m_pendingNewBarScans)) return false;
        return m_pendingNewBarScans[idx];
    }

    void SetPendingNewBarScan(const int idx, const bool val)
    {
        if(idx >= 0 && idx < ArraySize(m_pendingNewBarScans))
            m_pendingNewBarScans[idx] = val;
    }

    // Symbol scan states (index-based access for MQL5 compatibility)
    int GetScanStateIndex(const int idx) const
    {
        if(idx < 0 || idx >= ArraySize(m_symbolScanStates)) return -1;
        return idx;
    }

    void ResetIntrabarBackoff(const int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_symbolScanStates)) return;
        m_symbolScanStates[idx].intrabarBackoffTier = 0;
        m_symbolScanStates[idx].nextEligibleIntrabarTime = 0;
    }

    int GetScanStateCount() const { return ArraySize(m_symbolScanStates); }

    // Symbol eval start index
    int GetSymbolEvalStartIndex() const { return m_symbolEvalStartIndex; }
    void SetSymbolEvalStartIndex(const int val) { m_symbolEvalStartIndex = val; }

    // Last signal eval second
    datetime GetLastSignalEvalSecond() const { return m_lastSignalEvalSecond; }
    void SetLastSignalEvalSecond(const datetime val) { m_lastSignalEvalSecond = val; }

    // Last scalp fast path second
    datetime GetLastScalpFastPathSecond() const { return m_lastScalpFastPathSecond; }
    void SetLastScalpFastPathSecond(const datetime val) { m_lastScalpFastPathSecond = val; }

    // Last external capacity log time
    datetime GetLastExternalCapacityLogTime() const { return m_lastExternalCapacityLogTime; }
    void SetLastExternalCapacityLogTime(const datetime val) { m_lastExternalCapacityLogTime = val; }

    // Deinit cleanup
    void Cleanup()
    {
        ArrayResize(m_lastSymbolBarTimes, 0);
        ArrayResize(m_lastIntrabarScanTime, 0);
        ArrayResize(m_pendingNewBarScans, 0);
        ArrayResize(m_symbolScanStates, 0);
    }
};

#endif // __SYMBOL_SCAN_SCHEDULER_MQH__
