//+------------------------------------------------------------------+
//| DrawingCoordinator.mqh                                           |
//| Centralized per-bar drawing lifecycle and analysis snapshots     |
//+------------------------------------------------------------------+
#property strict

#ifndef DRAWING_COORDINATOR_MQH
#define DRAWING_COORDINATOR_MQH

#include "../Utils/Enums.mqh"

struct SDrawingAnalysisSnapshot
{
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    datetime barTime;
    string strategyName;
    bool enabled;
    ENUM_TRADE_SIGNAL signal;
    double confidence;
    int totalSignals;
    int successfulSignals;
    double accuracy;
    datetime lastSignalTime;
};

struct SDrawingPrefixState
{
    string key;
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    string prefix;
    datetime lastPreparedBarTime;
    int lastCleanupCount;
};

class CDrawingCoordinator
{
private:
    SDrawingAnalysisSnapshot m_snapshots[];
    SDrawingPrefixState m_prefixStates[];

    string m_cycleSymbol;
    ENUM_TIMEFRAMES m_cycleTimeframe;
    datetime m_cycleBarTime;
    bool m_cycleActive;
    int m_cycleSnapshotCount;
    int m_maxSnapshots;

    int FindPrefixState(const string key) const;
    datetime ResolveBarTime(const string symbol, ENUM_TIMEFRAMES timeframe) const;

public:
    CDrawingCoordinator();

    void SetMaxSnapshots(const int value);
    void BeginBarCycle(const string symbol, ENUM_TIMEFRAMES timeframe, datetime barTime = 0);
    void RecordStrategySnapshot(const string strategyName,
                                const bool enabled,
                                const ENUM_TRADE_SIGNAL signal,
                                const double confidence,
                                const int totalSignals,
                                const int successfulSignals,
                                const double accuracy,
                                const datetime snapshotLastSignalTime);
    void EndBarCycle();

    bool PreparePrefixForCurrentBar(const long chartId,
                                    const string symbol,
                                    ENUM_TIMEFRAMES timeframe,
                                    const string prefix);

    int GetSnapshotCount() const;
    int GetCycleSnapshotCount() const;
    bool GetLatestSnapshot(SDrawingAnalysisSnapshot &snapshot) const;
};

CDrawingCoordinator::CDrawingCoordinator() :
    m_cycleSymbol(""),
    m_cycleTimeframe(PERIOD_CURRENT),
    m_cycleBarTime(0),
    m_cycleActive(false),
    m_cycleSnapshotCount(0),
    m_maxSnapshots(2000)
{
    ArrayResize(m_snapshots, 0);
    ArrayResize(m_prefixStates, 0);
}

void CDrawingCoordinator::SetMaxSnapshots(const int value)
{
    m_maxSnapshots = MathMax(100, value);
}

int CDrawingCoordinator::FindPrefixState(const string key) const
{
    int count = ArraySize(m_prefixStates);
    for(int i = 0; i < count; i++)
    {
        if(m_prefixStates[i].key == key)
            return i;
    }
    return -1;
}

datetime CDrawingCoordinator::ResolveBarTime(const string symbol, ENUM_TIMEFRAMES timeframe) const
{
    datetime barTime = iTime(symbol, timeframe, 0);
    return barTime;
}

void CDrawingCoordinator::BeginBarCycle(const string symbol, ENUM_TIMEFRAMES timeframe, datetime barTime)
{
    m_cycleSymbol = symbol;
    m_cycleTimeframe = timeframe;
    m_cycleBarTime = (barTime > 0) ? barTime : ResolveBarTime(symbol, timeframe);
    m_cycleActive = true;
    m_cycleSnapshotCount = 0;
}

void CDrawingCoordinator::RecordStrategySnapshot(const string strategyName,
                                                 const bool enabled,
                                                 const ENUM_TRADE_SIGNAL signal,
                                                 const double confidence,
                                                 const int totalSignals,
                                                 const int successfulSignals,
                                                 const double accuracy,
                                                 const datetime snapshotLastSignalTime)
{
    if(!m_cycleActive)
        return;

    SDrawingAnalysisSnapshot snapshot;
    snapshot.symbol = m_cycleSymbol;
    snapshot.timeframe = m_cycleTimeframe;
    snapshot.barTime = m_cycleBarTime;
    snapshot.strategyName = strategyName;
    snapshot.enabled = enabled;
    snapshot.signal = signal;
    snapshot.confidence = confidence;
    snapshot.totalSignals = totalSignals;
    snapshot.successfulSignals = successfulSignals;
    snapshot.accuracy = accuracy;
    snapshot.lastSignalTime = snapshotLastSignalTime;

    int oldSize = ArraySize(m_snapshots);
    int newSize = oldSize + 1;
    ArrayResize(m_snapshots, newSize);
    m_snapshots[newSize - 1] = snapshot;
    m_cycleSnapshotCount++;

    if(newSize > m_maxSnapshots)
    {
        int overflow = newSize - m_maxSnapshots;
        for(int i = 0; i < m_maxSnapshots; i++)
            m_snapshots[i] = m_snapshots[i + overflow];
        ArrayResize(m_snapshots, m_maxSnapshots);
    }
}

void CDrawingCoordinator::EndBarCycle()
{
    m_cycleActive = false;
}

bool CDrawingCoordinator::PreparePrefixForCurrentBar(const long chartId,
                                                     const string symbol,
                                                     ENUM_TIMEFRAMES timeframe,
                                                     const string prefix)
{
    if(prefix == "")
        return false;

    datetime barTime = ResolveBarTime(symbol, timeframe);
    string key = symbol + "|" + IntegerToString((int)timeframe) + "|" + prefix;

    int idx = FindPrefixState(key);
    if(idx < 0)
    {
        SDrawingPrefixState state;
        state.key = key;
        state.symbol = symbol;
        state.timeframe = timeframe;
        state.prefix = prefix;
        state.lastPreparedBarTime = 0;
        state.lastCleanupCount = 0;

        int newStateCount = ArraySize(m_prefixStates) + 1;
        ArrayResize(m_prefixStates, newStateCount);
        m_prefixStates[newStateCount - 1] = state;
        idx = newStateCount - 1;
    }

    if(barTime <= 0)
        return false;

    if(m_prefixStates[idx].lastPreparedBarTime == barTime)
        return false;

    int deleted = ObjectsDeleteAll(chartId, prefix);
    m_prefixStates[idx].lastPreparedBarTime = barTime;
    m_prefixStates[idx].lastCleanupCount = (deleted > 0) ? deleted : 0;
    return true;
}

int CDrawingCoordinator::GetSnapshotCount() const
{
    return ArraySize(m_snapshots);
}

int CDrawingCoordinator::GetCycleSnapshotCount() const
{
    return m_cycleSnapshotCount;
}

bool CDrawingCoordinator::GetLatestSnapshot(SDrawingAnalysisSnapshot &snapshot) const
{
    int count = ArraySize(m_snapshots);
    if(count <= 0)
        return false;

    snapshot = m_snapshots[count - 1];
    return true;
}

static CDrawingCoordinator g_drawingCoordinator;

CDrawingCoordinator* GetDrawingCoordinator()
{
    return &g_drawingCoordinator;
}

#endif // DRAWING_COORDINATOR_MQH
