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
    int m_globalMaxObjects; // Global object limit (default 900)
    
    // Global object counter with alert thresholds
    int m_globalObjectCount;           // Current total objects
    int m_lastAlertLevel;              // Last alert level triggered (0=none, 1=800, 2=900, 3=950)
    datetime m_lastCountLogTime;       // Last time we logged the count
    int m_lastBarLogged;               // Last bar number when we logged

    int FindPrefixState(const string key) const;
    datetime ResolveBarTime(const string symbol, ENUM_TIMEFRAMES timeframe) const;
    bool CheckGlobalObjectLimitAndCleanup(long chartId);
    void UpdateGlobalObjectCount(long chartId);
    bool CheckAlertThresholds(long chartId);
    int SafeObjectsDeleteAll(long chartId, const string prefix, bool verify = true);
    
public:
    void SetGlobalMaxObjects(int maxObjects) { m_globalMaxObjects = MathMax(100, maxObjects); }

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
    
    // Drawing statistics accessors
    int GetGlobalObjectCount() const { return m_globalObjectCount; }
    int GetAlertLevel() const { return m_lastAlertLevel; }
    int GetGlobalMaxObjects() const { return m_globalMaxObjects; }
};

CDrawingCoordinator::CDrawingCoordinator() :
    m_cycleSymbol(""),
    m_cycleTimeframe(PERIOD_CURRENT),
    m_cycleBarTime(0),
    m_cycleActive(false),
    m_cycleSnapshotCount(0),
    m_maxSnapshots(2000),
    m_globalMaxObjects(900), // Stay under MT5's 1000 limit
    m_globalObjectCount(0),
    m_lastAlertLevel(0),
    m_lastCountLogTime(0),
    m_lastBarLogged(-1)
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

bool CDrawingCoordinator::CheckGlobalObjectLimitAndCleanup(long chartId)
{
    int totalObjects = ObjectsTotal(chartId);
    if(totalObjects < m_globalMaxObjects)
        return true;
    
    // Need to clean up objects from all prefixes
    int objectsToDelete = totalObjects - (m_globalMaxObjects - 100); // Keep buffer of 100
    
    // Collect all objects from all prefixes
    struct ObjectInfo
    {
        string name;
        datetime time;
    };
    ObjectInfo objects[];
    int count = 0;
    
    for(int i = 0; i < ObjectsTotal(chartId); i++)
    {
        string name = ObjectName(chartId, i);
        // Check if it's one of our managed objects
        bool isManaged = false;
        for(int j = 0; j < ArraySize(m_prefixStates); j++)
        {
            if(StringFind(name, m_prefixStates[j].prefix) == 0)
            {
                isManaged = true;
                break;
            }
        }
        if(isManaged)
        {
            datetime time = (datetime)ObjectGetInteger(chartId, name, OBJPROP_TIME);
            ArrayResize(objects, count + 1);
            objects[count].name = name;
            objects[count].time = time;
            count++;
        }
    }
    
    // Sort by time (oldest first)
    for(int i = 0; i < count - 1; i++)
    {
        for(int j = i + 1; j < count; j++)
        {
            if(objects[i].time > objects[j].time)
            {
                ObjectInfo temp = objects[i];
                objects[i] = objects[j];
                objects[j] = temp;
            }
        }
    }
    
    // Delete oldest objects
    int deleted = 0;
    for(int i = 0; i < count && deleted < objectsToDelete; i++)
    {
        if(ObjectDelete(chartId, objects[i].name))
        {
            deleted++;
        }
    }
    
    return true;
}

bool CDrawingCoordinator::PreparePrefixForCurrentBar(const long chartId,
                                                     const string symbol,
                                                     ENUM_TIMEFRAMES timeframe,
                                                     const string prefix)
{
    if(prefix == "")
        return false;

    // Check alert thresholds before drawing
    if(!CheckAlertThresholds(chartId))
    {
        // At emergency threshold - refuse new drawings
        PrintFormat("[DRAW-COORD] Refusing drawing request - emergency object limit reached");
        return false;
    }

    CheckGlobalObjectLimitAndCleanup(chartId);

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

    int deleted = SafeObjectsDeleteAll(chartId, prefix);
    m_prefixStates[idx].lastPreparedBarTime = barTime;
    m_prefixStates[idx].lastCleanupCount = deleted;
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

//+------------------------------------------------------------------+
//| Update global object count                                       |
//+------------------------------------------------------------------+
void CDrawingCoordinator::UpdateGlobalObjectCount(long chartId)
{
    m_globalObjectCount = ObjectsTotal(chartId);
}

//+------------------------------------------------------------------+
//| Check alert thresholds and log warnings                          |
//| Thresholds: 800 (warning), 900 (critical), 950 (emergency)      |
//+------------------------------------------------------------------+
bool CDrawingCoordinator::CheckAlertThresholds(long chartId)
{
    UpdateGlobalObjectCount(chartId);
    
    int currentBar = iBarShift(_Symbol, _Period, TimeCurrent());
    bool shouldLog = (currentBar != m_lastBarLogged) || (TimeCurrent() - m_lastCountLogTime >= 60);
    
    // Alert thresholds
    const int THRESHOLD_WARNING = 800;
    const int THRESHOLD_CRITICAL = 900;
    const int THRESHOLD_EMERGENCY = 950;
    
    int newAlertLevel = 0;
    if(m_globalObjectCount >= THRESHOLD_EMERGENCY)
        newAlertLevel = 3;
    else if(m_globalObjectCount >= THRESHOLD_CRITICAL)
        newAlertLevel = 2;
    else if(m_globalObjectCount >= THRESHOLD_WARNING)
        newAlertLevel = 1;
    
    // Log warning when crossing thresholds
    if(newAlertLevel > m_lastAlertLevel)
    {
        switch(newAlertLevel)
        {
            case 1:
                PrintFormat("[DRAW-COORD] WARNING: Chart objects at %d (800 threshold)", m_globalObjectCount);
                break;
            case 2:
                PrintFormat("[DRAW-COORD] CRITICAL: Chart objects at %d (900 threshold) - cleanup triggered", m_globalObjectCount);
                break;
            case 3:
                PrintFormat("[DRAW-COORD] EMERGENCY: Chart objects at %d (950 threshold) - aggressive cleanup", m_globalObjectCount);
                break;
        }
    }
    
    // Log periodically
    if(shouldLog)
    {
        PrintFormat("[DRAW-COORD] Object count: %d/%d | Alert Level: %d", 
                   m_globalObjectCount, m_globalMaxObjects, newAlertLevel);
        m_lastBarLogged = currentBar;
        m_lastCountLogTime = TimeCurrent();
    }
    
    m_lastAlertLevel = newAlertLevel;
    
    // Return false if at emergency threshold (should refuse new drawings)
    return (m_globalObjectCount < THRESHOLD_EMERGENCY);
}

//+------------------------------------------------------------------+
//| Safe ObjectsDeleteAll with verification and error handling       |
//+------------------------------------------------------------------+
int CDrawingCoordinator::SafeObjectsDeleteAll(long chartId, const string prefix, bool verify)
{
    if(prefix == "")
    {
        Print("[DRAW-COORD] SafeObjectsDeleteAll: Empty prefix not allowed");
        return 0;
    }

    int beforeCount = 0;
    if(verify)
    {
        // Count objects before deletion
        for(int i = 0; i < ObjectsTotal(chartId); i++)
        {
            string objName = ObjectName(chartId, i);
            if(StringFind(objName, prefix) == 0)
                beforeCount++;
        }
    }

    int deleted = ObjectsDeleteAll(chartId, prefix);

    if(verify)
    {
        // Verify deletion
        int afterCount = 0;
        for(int i = 0; i < ObjectsTotal(chartId); i++)
        {
            string objName = ObjectName(chartId, i);
            if(StringFind(objName, prefix) == 0)
                afterCount++;
        }

        int actualDeleted = beforeCount - afterCount;
        if(actualDeleted != deleted)
        {
            PrintFormat("[DRAW-COORD] WARNING: ObjectsDeleteAll reported %d deleted, but %d were actually deleted (prefix: %s)",
                       deleted, actualDeleted, prefix);
            deleted = actualDeleted;
        }

        if(afterCount > 0)
        {
            PrintFormat("[DRAW-COORD] WARNING: %d objects with prefix '%s' remain after cleanup",
                       afterCount, prefix);
        }
    }

    return deleted;
}

CDrawingCoordinator g_drawingCoordinator;

CDrawingCoordinator* GetDrawingCoordinator()
{
    return &g_drawingCoordinator;
}

#endif // DRAWING_COORDINATOR_MQH
