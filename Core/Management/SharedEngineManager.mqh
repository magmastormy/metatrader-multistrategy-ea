//+------------------------------------------------------------------+
//| SharedEngineManager.mqh                                          |
//| Manages shared read-only engines for multi-symbol scalability    |
//+------------------------------------------------------------------+
#ifndef __SHARED_ENGINE_MANAGER_MQH__
#define __SHARED_ENGINE_MANAGER_MQH__

#include "../Utils/Enums.mqh"
#include "../Pipeline/TrendEngine.mqh"
#include "../Pipeline/VolatilityEngine.mqh"
#include "../Pipeline/RegimeEngine.mqh"

struct SSymbolPriority
{
    string symbol;
    int priority;
    double spread;
    double volume24h;
    datetime lastUpdate;
    bool isActive;
    
    SSymbolPriority() :
        symbol(""), priority(0), spread(0.0), volume24h(0.0),
        lastUpdate(0), isActive(true) {}
};

enum ENUM_ENGINE_SHARING_MODE
{
    SHARING_DISABLED = 0,
    SHARING_READONLY = 1,
    SHARING_FULL = 2
};

class CSharedEngineManager
{
private:
    static CSharedEngineManager* m_instance;
    
    CTrendEngine* m_sharedTrendEngine;
    CVolatilityEngine* m_sharedVolatilityEngine;
    CRegimeEngine* m_sharedRegimeEngine;
    
    ENUM_ENGINE_SHARING_MODE m_sharingMode;
    
    SSymbolPriority m_symbolPriorities[];
    int m_symbolCount;
    
    datetime m_lastRecalculation;
    int m_recalculationIntervalSeconds;
    
    bool m_initialized;
    
public:
    static CSharedEngineManager* GetInstance();
    
    CSharedEngineManager();
    ~CSharedEngineManager();
    
    bool Initialize(ENUM_ENGINE_SHARING_MODE mode = SHARING_READONLY);
    void Shutdown();
    
    void SetSharingMode(ENUM_ENGINE_SHARING_MODE mode);
    ENUM_ENGINE_SHARING_MODE GetSharingMode() const { return m_sharingMode; }
    
    CTrendEngine* GetSharedTrendEngine() { return m_sharedTrendEngine; }
    CVolatilityEngine* GetSharedVolatilityEngine() { return m_sharedVolatilityEngine; }
    CRegimeEngine* GetSharedRegimeEngine() { return m_sharedRegimeEngine; }
    
    bool RegisterSymbol(const string symbol, int initialPriority = 50);
    void UnregisterSymbol(const string symbol);
    void UpdateSymbolPriority(const string symbol, int priority);
    void UpdateSymbolMetrics(const string symbol, double spread, double volume24h);
    
    void RecalculatePriorities();
    SSymbolPriority GetSymbolPriority(const string symbol) const;
    string GetNextPrioritySymbol();
    
    int GetActiveSymbolCount() const;
    void SetSymbolActive(const string symbol, bool active);
    bool IsSymbolActive(const string symbol) const;
    
    bool IsInitialized() const { return m_initialized; }
    
    string GetSharingStatus() const;
};

CSharedEngineManager* CSharedEngineManager::m_instance = NULL;

CSharedEngineManager::CSharedEngineManager() :
    m_sharedTrendEngine(NULL),
    m_sharedVolatilityEngine(NULL),
    m_sharedRegimeEngine(NULL),
    m_sharingMode(SHARING_DISABLED),
    m_symbolCount(0),
    m_lastRecalculation(0),
    m_recalculationIntervalSeconds(60),
    m_initialized(false)
{
}

CSharedEngineManager::~CSharedEngineManager()
{
    Shutdown();
}

CSharedEngineManager* CSharedEngineManager::GetInstance()
{
    if(m_instance == NULL)
    {
        m_instance = new CSharedEngineManager();
    }
    return m_instance;
}

bool CSharedEngineManager::Initialize(ENUM_ENGINE_SHARING_MODE mode)
{
    if(m_initialized)
    {
        Print("[SharedEngineManager] Already initialized");
        return true;
    }
    
    m_sharingMode = mode;
    
    if(mode == SHARING_DISABLED)
    {
        Print("[SharedEngineManager] Sharing mode DISABLED - engines will not be shared");
        m_initialized = true;
        return true;
    }
    
    PrintFormat("[SharedEngineManager] Initializing with sharing mode: %d", mode);
    
    if(mode >= SHARING_READONLY)
    {
        m_sharedTrendEngine = new CTrendEngine();
        m_sharedVolatilityEngine = new CVolatilityEngine();
        m_sharedRegimeEngine = new CRegimeEngine();
        
        if(m_sharedTrendEngine != NULL)
            Print("[SharedEngineManager] Shared TrendEngine created");
        if(m_sharedVolatilityEngine != NULL)
            Print("[SharedEngineManager] Shared VolatilityEngine created");
        if(m_sharedRegimeEngine != NULL)
            Print("[SharedEngineManager] Shared RegimeEngine created");
    }
    
    m_initialized = true;
    Print("[SharedEngineManager] Initialization complete");
    return true;
}

void CSharedEngineManager::Shutdown()
{
    if(m_sharedTrendEngine != NULL)
    {
        delete m_sharedTrendEngine;
        m_sharedTrendEngine = NULL;
    }
    
    if(m_sharedVolatilityEngine != NULL)
    {
        delete m_sharedVolatilityEngine;
        m_sharedVolatilityEngine = NULL;
    }
    
    if(m_sharedRegimeEngine != NULL)
    {
        delete m_sharedRegimeEngine;
        m_sharedRegimeEngine = NULL;
    }
    
    ArrayResize(m_symbolPriorities, 0);
    m_symbolCount = 0;
    m_initialized = false;
    
    Print("[SharedEngineManager] Shutdown complete");
}

void CSharedEngineManager::SetSharingMode(ENUM_ENGINE_SHARING_MODE mode)
{
    if(mode == m_sharingMode)
        return;
    
    PrintFormat("[SharedEngineManager] Changing sharing mode from %d to %d", m_sharingMode, mode);
    
    Shutdown();
    Initialize(mode);
}

bool CSharedEngineManager::RegisterSymbol(const string symbol, int initialPriority)
{
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].symbol == symbol)
        {
            PrintFormat("[SharedEngineManager] Symbol %s already registered", symbol);
            return false;
        }
    }
    
    int index = m_symbolCount;
    ArrayResize(m_symbolPriorities, m_symbolCount + 1);
    m_symbolPriorities[index].symbol = symbol;
    m_symbolPriorities[index].priority = initialPriority;
    m_symbolPriorities[index].lastUpdate = TimeCurrent();
    m_symbolPriorities[index].isActive = true;
    m_symbolCount++;
    
    PrintFormat("[SharedEngineManager] Symbol %s registered with priority %d", symbol, initialPriority);
    return true;
}

void CSharedEngineManager::UnregisterSymbol(const string symbol)
{
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].symbol == symbol)
        {
            for(int j = i; j < m_symbolCount - 1; j++)
            {
                m_symbolPriorities[j] = m_symbolPriorities[j + 1];
            }
            m_symbolCount--;
            ArrayResize(m_symbolPriorities, m_symbolCount);
            
            PrintFormat("[SharedEngineManager] Symbol %s unregistered", symbol);
            return;
        }
    }
}

void CSharedEngineManager::UpdateSymbolPriority(const string symbol, int priority)
{
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].symbol == symbol)
        {
            m_symbolPriorities[i].priority = priority;
            m_symbolPriorities[i].lastUpdate = TimeCurrent();
            return;
        }
    }
}

void CSharedEngineManager::UpdateSymbolMetrics(const string symbol, double spread, double volume24h)
{
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].symbol == symbol)
        {
            m_symbolPriorities[i].spread = spread;
            m_symbolPriorities[i].volume24h = volume24h;
            m_symbolPriorities[i].lastUpdate = TimeCurrent();
            return;
        }
    }
}

void CSharedEngineManager::RecalculatePriorities()
{
    datetime currentTime = TimeCurrent();
    
    if(currentTime - m_lastRecalculation < m_recalculationIntervalSeconds)
        return;
    
    for(int i = 0; i < m_symbolCount; i++)
    {
        double spreadScore = MathMax(0, 100 - m_symbolPriorities[i].spread);
        double volumeScore = MathMin(100.0, m_symbolPriorities[i].volume24h / 100.0);
        
        double newPriority = (spreadScore * 0.4 + volumeScore * 0.4 + m_symbolPriorities[i].priority * 0.2);
        m_symbolPriorities[i].priority = (int)MathRound(newPriority);
        m_symbolPriorities[i].lastUpdate = currentTime;
    }
    
    for(int i = 0; i < m_symbolCount - 1; i++)
    {
        for(int j = i + 1; j < m_symbolCount; j++)
        {
            if(m_symbolPriorities[j].priority > m_symbolPriorities[i].priority)
            {
                SSymbolPriority temp = m_symbolPriorities[i];
                m_symbolPriorities[i] = m_symbolPriorities[j];
                m_symbolPriorities[j] = temp;
            }
        }
    }
    
    m_lastRecalculation = currentTime;
}

SSymbolPriority CSharedEngineManager::GetSymbolPriority(const string symbol) const
{
    SSymbolPriority empty;
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].symbol == symbol)
            return m_symbolPriorities[i];
    }
    return empty;
}

string CSharedEngineManager::GetNextPrioritySymbol()
{
    RecalculatePriorities();
    
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].isActive)
            return m_symbolPriorities[i].symbol;
    }
    
    return "";
}

int CSharedEngineManager::GetActiveSymbolCount() const
{
    int count = 0;
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].isActive)
            count++;
    }
    return count;
}

void CSharedEngineManager::SetSymbolActive(const string symbol, bool active)
{
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].symbol == symbol)
        {
            m_symbolPriorities[i].isActive = active;
            PrintFormat("[SharedEngineManager] Symbol %s set to %s", 
                       symbol, active ? "ACTIVE" : "INACTIVE");
            return;
        }
    }
}

bool CSharedEngineManager::IsSymbolActive(const string symbol) const
{
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbolPriorities[i].symbol == symbol)
            return m_symbolPriorities[i].isActive;
    }
    return false;
}

string CSharedEngineManager::GetSharingStatus() const
{
    string status;
    
    switch(m_sharingMode)
    {
        case SHARING_DISABLED: status = "DISABLED"; break;
        case SHARING_READONLY: status = "READONLY"; break;
        case SHARING_FULL: status = "FULL"; break;
        default: status = "UNKNOWN"; break;
    }
    
    return StringFormat("Sharing: %s | Symbols: %d/%d | Trend: %s | Volatility: %s | Regime: %s",
                       status,
                       GetActiveSymbolCount(),
                       m_symbolCount,
                       m_sharedTrendEngine != NULL ? "SHARED" : "NULL",
                       m_sharedVolatilityEngine != NULL ? "SHARED" : "NULL",
                       m_sharedRegimeEngine != NULL ? "SHARED" : "NULL");
}

#endif // __SHARED_ENGINE_MANAGER_MQH__
