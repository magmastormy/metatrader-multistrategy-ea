//+------------------------------------------------------------------+
//| PositionStateManager.mqh - Unified position state tracking
//| Copyright 2025, Your Company Name
//| https://www.yoursite.com
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __POSITION_STATE_MANAGER_MQH__
#define __POSITION_STATE_MANAGER_MQH__

#include <Object.mqh>
#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Unified Position State Structure
//+------------------------------------------------------------------+
struct SPositionState
{
    ulong positionId;           // Position ticket ID
    string predictionId;      // Prediction ID associated with position
    datetime aiPredictionTime; // AI prediction time
    ENUM_TRADE_SIGNAL aiPredictionSignal; // AI prediction signal
    
    SPositionState()
    {
        positionId = 0;
        predictionId = "";
        aiPredictionTime = 0;
        aiPredictionSignal = TRADE_SIGNAL_NONE;
    }
};

//+------------------------------------------------------------------+
//| Position State Manager Class
//+------------------------------------------------------------------+
class CPositionStateManager
{
private:
    SPositionState m_states[];   // Array of position states
    int m_count;                 // Number of active states
    static const int MAX_STATES;  // Maximum number of tracked states
    
public:
    CPositionStateManager();
    ~CPositionStateManager();
    
    // Find position state by ID
    int FindStateIndex(const ulong positionId);
    
    // Check if position is tracked
    bool HasPosition(const ulong positionId) { return FindStateIndex(positionId) >= 0; }
    
    // Upsert prediction ID for position
    void UpsertPredictionId(const ulong positionId, const string predictionId);
    
    // Get prediction ID for position
    string GetPredictionId(const ulong positionId);
    
    // Remove prediction mapping
    void RemovePrediction(const ulong positionId);
    
    // Upsert AI prediction data
    void UpsertAIPrediction(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal);
    
    // Get AI prediction time
    datetime GetAIPredictionTime(const ulong positionId);
    
    // Get AI prediction signal
    ENUM_TRADE_SIGNAL GetAIPredictionSignal(const ulong positionId);
    
    // Remove AI prediction mapping
    void RemoveAIPrediction(const ulong positionId);
    
    // Clear all states
    void ClearAll();
    
    // Remove stale states (positions that no longer exist)
    int RemoveStaleStates();
    
    // Get count of active states
    int GetCount() const { return m_count; }
    
    // Get state by index
    bool GetStateByIndex(const int index, SPositionState &state);
    
    // Check if manager is initialized
    bool IsInitialized() const { return true; }
    
    // Get all tracked position IDs
    int GetAllPositionIds(ulong &positionIds[]);
    
    // Print debug info
    void PrintDebugInfo();
};

//+------------------------------------------------------------------+
//| Static member definition                                         |
//+------------------------------------------------------------------+
const int CPositionStateManager::MAX_STATES = 500;

//+------------------------------------------------------------------+
//| Constructor
//+------------------------------------------------------------------+
CPositionStateManager::CPositionStateManager()
{
    m_count = 0;
    ArrayResize(m_states, 0);
}

//+------------------------------------------------------------------+
//| Destructor
//+------------------------------------------------------------------+
CPositionStateManager::~CPositionStateManager()
{
    ClearAll();
}

//+------------------------------------------------------------------+
//| Find state index by position ID
//+------------------------------------------------------------------+
int CPositionStateManager::FindStateIndex(const ulong positionId)
{
    for(int i = 0; i < m_count; i++)
    {
        if(m_states[i].positionId == positionId)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Upsert prediction ID
//+------------------------------------------------------------------+
void CPositionStateManager::UpsertPredictionId(const ulong positionId, const string predictionId)
{
    if(positionId == 0 || predictionId == "")
        return;
        
    int idx = FindStateIndex(positionId);
    if(idx >= 0)
    {
        m_states[idx].predictionId = predictionId;
        return;
    }
    
    // Check bounds before adding new state
    if(m_count >= MAX_STATES)
    {
        // Remove oldest entry to make room
        for(int i = 0; i < m_count - 1; i++)
        {
            m_states[i] = m_states[i + 1];
        }
        m_count--;
        ArrayResize(m_states, m_count);
    }
    
    // Create new state
    ArrayResize(m_states, m_count + 1);
    m_states[m_count].positionId = positionId;
    m_states[m_count].predictionId = predictionId;
    m_states[m_count].aiPredictionTime = 0;
    m_states[m_count].aiPredictionSignal = TRADE_SIGNAL_NONE;
    m_count++;
}

//+------------------------------------------------------------------+
//| Get prediction ID
//+------------------------------------------------------------------+
string CPositionStateManager::GetPredictionId(const ulong positionId)
{
    int idx = FindStateIndex(positionId);
    if(idx < 0 || idx >= m_count)
        return "";
    return m_states[idx].predictionId;
}

//+------------------------------------------------------------------+
//| Remove prediction mapping
//+------------------------------------------------------------------+
void CPositionStateManager::RemovePrediction(const ulong positionId)
{
    int idx = FindStateIndex(positionId);
    if(idx < 0)
        return;
        
    // Shift elements
    for(int i = idx; i < m_count - 1; i++)
    {
        m_states[i] = m_states[i + 1];
    }
    
    m_count--;
    ArrayResize(m_states, m_count);
}

//+------------------------------------------------------------------+
//| Upsert AI prediction
//+------------------------------------------------------------------+
void CPositionStateManager::UpsertAIPrediction(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal)
{
    if(positionId == 0 || predictionTime <= 0 || predictionSignal == TRADE_SIGNAL_NONE)
        return;
        
    int idx = FindStateIndex(positionId);
    if(idx >= 0)
    {
        m_states[idx].aiPredictionTime = predictionTime;
        m_states[idx].aiPredictionSignal = predictionSignal;
        return;
    }
    
    // Check bounds before adding new state
    if(m_count >= MAX_STATES)
    {
        // Remove oldest entry to make room
        for(int i = 0; i < m_count - 1; i++)
        {
            m_states[i] = m_states[i + 1];
        }
        m_count--;
        ArrayResize(m_states, m_count);
    }
    
    // Create new state
    ArrayResize(m_states, m_count + 1);
    m_states[m_count].positionId = positionId;
    m_states[m_count].predictionId = "";
    m_states[m_count].aiPredictionTime = predictionTime;
    m_states[m_count].aiPredictionSignal = predictionSignal;
    m_count++;
}

//+------------------------------------------------------------------+
//| Get AI prediction time
//+------------------------------------------------------------------+
datetime CPositionStateManager::GetAIPredictionTime(const ulong positionId)
{
    int idx = FindStateIndex(positionId);
    if(idx < 0 || idx >= m_count)
        return 0;
    return m_states[idx].aiPredictionTime;
}

//+------------------------------------------------------------------+
//| Get AI prediction signal
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CPositionStateManager::GetAIPredictionSignal(const ulong positionId)
{
    int idx = FindStateIndex(positionId);
    if(idx < 0 || idx >= m_count)
        return TRADE_SIGNAL_NONE;
    return m_states[idx].aiPredictionSignal;
}

//+------------------------------------------------------------------+
//| Remove AI prediction mapping
//+------------------------------------------------------------------+
void CPositionStateManager::RemoveAIPrediction(const ulong positionId)
{
    int idx = FindStateIndex(positionId);
    if(idx < 0)
        return;
        
    // Shift elements
    for(int i = idx; i < m_count - 1; i++)
    {
        m_states[i] = m_states[i + 1];
    }
    
    m_count--;
    ArrayResize(m_states, m_count);
}

//+------------------------------------------------------------------+
//| Clear all states
//+------------------------------------------------------------------+
void CPositionStateManager::ClearAll()
{
    m_count = 0;
    ArrayResize(m_states, 0);
}

//+------------------------------------------------------------------+
//| Get state by index
//+------------------------------------------------------------------+
bool CPositionStateManager::GetStateByIndex(const int index, SPositionState &state)
{
    if(index < 0 || index >= m_count)
        return false;
    state = m_states[index];
    return true;
}

//+------------------------------------------------------------------+
//| Remove stale states (positions that no longer exist)
//+------------------------------------------------------------------+
int CPositionStateManager::RemoveStaleStates()
{
    int removed = 0;
    for(int i = m_count - 1; i >= 0; i--)
    {
        if(!PositionSelectByTicket(m_states[i].positionId))
        {
            // Position no longer exists, remove from tracking
            for(int j = i; j < m_count - 1; j++)
            {
                m_states[j] = m_states[j + 1];
            }
            m_count--;
            removed++;
        }
    }
    
    if(removed > 0)
    {
        ArrayResize(m_states, m_count);
    }
    
    return removed;
}

//+------------------------------------------------------------------+
//| Get all tracked position IDs
//+------------------------------------------------------------------+
int CPositionStateManager::GetAllPositionIds(ulong &positionIds[])
{
    ArrayResize(positionIds, m_count);
    for(int i = 0; i < m_count; i++)
    {
        positionIds[i] = m_states[i].positionId;
    }
    return m_count;
}

//+------------------------------------------------------------------+
//| Print debug info
//+------------------------------------------------------------------+
void CPositionStateManager::PrintDebugInfo()
{
    PrintFormat("[POSITION-STATE-MANAGER] Tracking %d positions (max: %d)", m_count, MAX_STATES);
    
    int withPrediction = 0;
    int withAIPrediction = 0;
    
    for(int i = 0; i < m_count; i++)
    {
        if(m_states[i].predictionId != "")
            withPrediction++;
        if(m_states[i].aiPredictionTime > 0)
            withAIPrediction++;
    }
    
    PrintFormat("[POSITION-STATE-MANAGER] With prediction ID: %d | With AI prediction: %d",
                withPrediction, withAIPrediction);
}

#endif // __POSITION_STATE_MANAGER_MQH__
