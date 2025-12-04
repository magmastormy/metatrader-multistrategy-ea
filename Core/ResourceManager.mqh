//+------------------------------------------------------------------+
//| Resource Manager and Memory Protection System                 |
//| Comprehensive resource allocation and memory management       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_RESOURCE_MANAGER_MQH
#define CORE_RESOURCE_MANAGER_MQH

#include "Enums.mqh"
#include "ErrorHandling.mqh"

//+------------------------------------------------------------------+
//| Resource Types                                                 |
//+------------------------------------------------------------------+
enum ENUM_RESOURCE_TYPE
{
    RESOURCE_INDICATOR_HANDLE = 0,  // Indicator handles
    RESOURCE_FILE_HANDLE = 1,       // File handles
    RESOURCE_MEMORY_BLOCK = 2,      // Memory allocations
    RESOURCE_TIMER = 3,             // Timer resources
    RESOURCE_OBJECT = 4,            // Chart objects
    RESOURCE_CUSTOM = 5             // Custom resources
};

//+------------------------------------------------------------------+
//| Resource Status                                                |
//+------------------------------------------------------------------+
enum ENUM_RESOURCE_STATUS
{
    RESOURCE_ACTIVE = 0,            // Resource is active
    RESOURCE_IDLE = 1,              // Resource is idle
    RESOURCE_LEAKED = 2,            // Resource is leaked
    RESOURCE_RELEASED = 3           // Resource has been released
};

//+------------------------------------------------------------------+
//| Resource Information Structure                                 |
//+------------------------------------------------------------------+
struct SResourceInfo
{
    int resourceId;                 // Resource identifier
    ENUM_RESOURCE_TYPE type;        // Resource type
    ENUM_RESOURCE_STATUS status;    // Current status
    string description;             // Resource description
    datetime createdTime;           // Creation timestamp
    datetime lastAccessTime;        // Last access timestamp
    int accessCount;                // Number of accesses
    long memorySize;                // Memory size (if applicable)
    string owner;                   // Component that owns the resource
    bool autoCleanup;               // Auto cleanup enabled
};

//+------------------------------------------------------------------+
//| Memory Usage Statistics                                        |
//+------------------------------------------------------------------+
struct SMemoryStats
{
    long totalAllocated;            // Total allocated memory
    long totalReleased;             // Total released memory
    long currentUsage;              // Current memory usage
    long peakUsage;                 // Peak memory usage
    int activeAllocations;          // Number of active allocations
    int totalAllocations;           // Total allocations made
    int leakedAllocations;          // Number of leaked allocations
    datetime lastUpdate;            // Last update timestamp
};

//+------------------------------------------------------------------+
//| Resource Limits Configuration                                  |
//+------------------------------------------------------------------+
struct SResourceLimits
{
    int maxIndicatorHandles;        // Maximum indicator handles
    int maxFileHandles;             // Maximum file handles
    long maxMemoryUsage;            // Maximum memory usage in bytes
    int maxTimers;                  // Maximum timers
    int maxObjects;                 // Maximum chart objects
    int maxCustomResources;         // Maximum custom resources
    bool enforceStrictLimits;       // Enforce strict limits
    bool autoCleanupEnabled;        // Auto cleanup enabled
    int cleanupIntervalSeconds;     // Cleanup interval
};

//+------------------------------------------------------------------+
//| Resource Manager Class                                         |
//+------------------------------------------------------------------+
class CResourceManager
{
private:
    static SResourceInfo m_resources[];
    static int m_resourceCount;
    static SMemoryStats m_memoryStats;
    static SResourceLimits m_limits;
    static bool m_initialized;
    static datetime m_lastCleanup;
    static int m_nextResourceId;
    
    // Resource counters by type
    static int m_resourceCounters[6];
    
    // Handle tracking arrays
    static int m_indicatorHandles[];
    static int m_fileHandles[];
    static int m_timerIds[];

public:
    // Constructor
    CResourceManager(void);
    
    // Destructor
    ~CResourceManager(void);
    
    // Initialize resource management system
    static bool Initialize(const SResourceLimits &limits);
    
    // Resource allocation and tracking
    static int AllocateResource(const ENUM_RESOURCE_TYPE type, 
                               const string description, 
                               const string owner,
                               const long memorySize = 0);
    static bool ReleaseResource(const int resourceId);
    static bool ReleaseResourcesByOwner(const string owner);
    static bool ReleaseResourcesByType(const ENUM_RESOURCE_TYPE type);
    
    // Indicator handle management
    static int CreateIndicatorHandle(const string symbol, 
                                   const ENUM_TIMEFRAMES timeframe,
                                   const string indicatorName,
                                   const string owner);
    static bool ReleaseIndicatorHandle(const int handle);
    static void ReleaseAllIndicatorHandles(void);
    static int GetActiveIndicatorHandles(void);
    
    // File handle management
    static int CreateFileHandle(const string filename, 
                               const int flags,
                               const string owner);
    static bool ReleaseFileHandle(const int handle);
    static void ReleaseAllFileHandles(void);
    static int GetActiveFileHandles(void);
    
    // Memory management
    static bool AllocateMemory(const long size, 
                              const string description,
                              const string owner);
    static bool ReleaseMemory(const string description);
    static long GetMemoryUsage(void);
    static SMemoryStats GetMemoryStats(void);
    static bool IsMemoryLimitExceeded(void);
    
    // Timer management
    static int CreateTimer(const int periodMs, 
                          const string description,
                          const string owner);
    static bool ReleaseTimer(const int timerId);
    static void ReleaseAllTimers(void);
    
    // Object management
    static bool CreateObject(const string objectName, 
                            const string description,
                            const string owner);
    static bool ReleaseObject(const string objectName);
    static void ReleaseAllObjects(void);
    
    // Resource monitoring and cleanup
    static void PerformCleanup(void);
    static void PerformAutomaticCleanup(void);
    static void DetectLeaks(void);
    static void ForceCleanupAll(void);
    
    // Resource limits and enforcement
    static bool CheckResourceLimits(const ENUM_RESOURCE_TYPE type);
    static void SetResourceLimits(const SResourceLimits &limits);
    static SResourceLimits GetResourceLimits(void);
    static bool EnforceResourceLimits(const ENUM_RESOURCE_TYPE type);
    
    // Resource information and statistics
    static SResourceInfo GetResourceInfo(const int resourceId);
    static void GetResourcesByType(const ENUM_RESOURCE_TYPE type, 
                                  SResourceInfo &resources[], 
                                  int &count);
    static void GetResourcesByOwner(const string owner, 
                                   SResourceInfo &resources[], 
                                   int &count);
    static void GenerateResourceReport(string &report);
    static void LogResourceUsage(void);
    
    // Configuration
    static void SetAutoCleanup(const bool enabled);
    static void SetCleanupInterval(const int intervalSeconds);
    static bool IsAutoCleanupEnabled(void);
    
    // Utility functions
    static string GetResourceTypeString(const ENUM_RESOURCE_TYPE type);
    static string GetResourceStatusString(const ENUM_RESOURCE_STATUS status);
    static bool IsResourceActive(const int resourceId);
    
private:
    // Internal helper methods
    static int FindResourceIndex(const int resourceId);
    static int FindResourceByDescription(const string description);
    static void UpdateResourceAccess(const int resourceId);
    static void UpdateMemoryStats(void);
    static void CleanupIdleResources(void);
    static void CleanupLeakedResources(void);
    static bool IsResourceIdle(const int resourceId, const int idleTimeSeconds = 300);
    static void ResizeResourceArray(void);
};

// Static member initialization
static SResourceInfo CResourceManager::m_resources[];
static int CResourceManager::m_resourceCount = 0;
static SMemoryStats CResourceManager::m_memoryStats;
static SResourceLimits CResourceManager::m_limits = {100, 50, 100*1024*1024, 10, 1000, 100, true, true, 60};
static bool CResourceManager::m_initialized = false;
static datetime CResourceManager::m_lastCleanup = 0;
static int CResourceManager::m_nextResourceId = 1;
static int CResourceManager::m_resourceCounters[6] = {0, 0, 0, 0, 0, 0};
static int CResourceManager::m_indicatorHandles[];
static int CResourceManager::m_fileHandles[];
static int CResourceManager::m_timerIds[];

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CResourceManager::CResourceManager(void)
{
    // Constructor implementation
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CResourceManager::~CResourceManager(void)
{
    if(m_initialized)
    {
        ForceCleanupAll();
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_INFO, "ResourceManager", 
                                       "Resource management system shutdown");
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize resource management system                          |
//+------------------------------------------------------------------+
bool CResourceManager::Initialize(const SResourceLimits &limits)
{
    m_limits = limits;
    m_initialized = true;
    m_resourceCount = 0;
    m_nextResourceId = 1;
    m_lastCleanup = TimeCurrent();
    
    // Initialize arrays
    ArrayResize(m_resources, 1000); // Initial capacity
    ArrayResize(m_indicatorHandles, m_limits.maxIndicatorHandles);
    ArrayResize(m_fileHandles, m_limits.maxFileHandles);
    ArrayResize(m_timerIds, m_limits.maxTimers);
    
    // Initialize counters
    for(int i = 0; i < 6; i++)
        m_resourceCounters[i] = 0;
    
    // Initialize memory stats
    m_memoryStats.totalAllocated = 0;
    m_memoryStats.totalReleased = 0;
    m_memoryStats.currentUsage = 0;
    m_memoryStats.peakUsage = 0;
    m_memoryStats.activeAllocations = 0;
    m_memoryStats.totalAllocations = 0;
    m_memoryStats.leakedAllocations = 0;
    m_memoryStats.lastUpdate = TimeCurrent();
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "ResourceManager", 
                                   "Resource management system initialized successfully");
    }
    
    return true;
}/
/+------------------------------------------------------------------+
//| Allocate and track resource                                   |
//+------------------------------------------------------------------+
int CResourceManager::AllocateResource(const ENUM_RESOURCE_TYPE type, 
                                      const string description, 
                                      const string owner,
                                      const long memorySize = 0)
{
    if(!m_initialized) return -1;
    
    // Check resource limits
    if(!CheckResourceLimits(type))
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_WARNING, "ResourceManager",
                                       StringFormat("Resource limit exceeded for type %s",
                                                   GetResourceTypeString(type)));
        }
        return -1;
    }
    
    // Resize array if needed
    if(m_resourceCount >= ArraySize(m_resources))
    {
        ResizeResourceArray();
    }
    
    // Create resource entry
    int resourceId = m_nextResourceId++;
    m_resources[m_resourceCount].resourceId = resourceId;
    m_resources[m_resourceCount].type = type;
    m_resources[m_resourceCount].status = RESOURCE_ACTIVE;
    m_resources[m_resourceCount].description = description;
    m_resources[m_resourceCount].createdTime = TimeCurrent();
    m_resources[m_resourceCount].lastAccessTime = TimeCurrent();
    m_resources[m_resourceCount].accessCount = 1;
    m_resources[m_resourceCount].memorySize = memorySize;
    m_resources[m_resourceCount].owner = owner;
    m_resources[m_resourceCount].autoCleanup = m_limits.autoCleanupEnabled;
    
    m_resourceCount++;
    m_resourceCounters[(int)type]++;
    
    // Update memory stats if applicable
    if(memorySize > 0)
    {
        m_memoryStats.totalAllocated += memorySize;
        m_memoryStats.currentUsage += memorySize;
        m_memoryStats.activeAllocations++;
        m_memoryStats.totalAllocations++;
        
        if(m_memoryStats.currentUsage > m_memoryStats.peakUsage)
            m_memoryStats.peakUsage = m_memoryStats.currentUsage;
    }
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "ResourceManager",
                                   StringFormat("Resource allocated: ID=%d, Type=%s, Owner=%s, Size=%d",
                                               resourceId, GetResourceTypeString(type), owner, memorySize));
    }
    
    return resourceId;
}

//+------------------------------------------------------------------+
//| Release resource                                               |
//+------------------------------------------------------------------+
bool CResourceManager::ReleaseResource(const int resourceId)
{
    if(!m_initialized) return false;
    
    int index = FindResourceIndex(resourceId);
    if(index < 0) return false;
    
    SResourceInfo &resource = m_resources[index];
    
    // Update memory stats if applicable
    if(resource.memorySize > 0)
    {
        m_memoryStats.totalReleased += resource.memorySize;
        m_memoryStats.currentUsage -= resource.memorySize;
        m_memoryStats.activeAllocations--;
    }
    
    // Update counters
    m_resourceCounters[(int)resource.type]--;
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "ResourceManager",
                                   StringFormat("Resource released: ID=%d, Type=%s, Owner=%s",
                                               resourceId, GetResourceTypeString(resource.type), resource.owner));
    }
    
    // Mark as released
    resource.status = RESOURCE_RELEASED;
    
    // Remove from array by shifting elements
    for(int i = index; i < m_resourceCount - 1; i++)
    {
        m_resources[i] = m_resources[i + 1];
    }
    m_resourceCount--;
    
    return true;
}

//+------------------------------------------------------------------+
//| Create and track indicator handle                             |
//+------------------------------------------------------------------+
int CResourceManager::CreateIndicatorHandle(const string symbol, 
                                           const ENUM_TIMEFRAMES timeframe,
                                           const string indicatorName,
                                           const string owner)
{
    if(!CheckResourceLimits(RESOURCE_INDICATOR_HANDLE))
        return INVALID_HANDLE;
    
    // Create indicator handle (this would be replaced with actual indicator creation)
    int handle = INVALID_HANDLE;
    
    // Example for different indicators - this would need to be expanded
    if(indicatorName == "RSI")
    {
        handle = iRSI(symbol, timeframe, 14, PRICE_CLOSE);
    }
    else if(indicatorName == "MA")
    {
        handle = iMA(symbol, timeframe, 20, 0, MODE_SMA, PRICE_CLOSE);
    }
    else if(indicatorName == "MACD")
    {
        handle = iMACD(symbol, timeframe, 12, 26, 9, PRICE_CLOSE);
    }
    // Add more indicators as needed
    
    if(handle == INVALID_HANDLE)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_RECOVERABLE, "ResourceManager",
                                       StringFormat("Failed to create indicator handle: %s on %s %s",
                                                   indicatorName, symbol, EnumToString(timeframe)));
        }
        return INVALID_HANDLE;
    }
    
    // Track the handle
    int resourceId = AllocateResource(RESOURCE_INDICATOR_HANDLE, 
                                     StringFormat("%s_%s_%s", indicatorName, symbol, EnumToString(timeframe)), 
                                     owner);
    
    // Store handle in tracking array
    for(int i = 0; i < ArraySize(m_indicatorHandles); i++)
    {
        if(m_indicatorHandles[i] == 0)
        {
            m_indicatorHandles[i] = handle;
            break;
        }
    }
    
    return handle;
}

//+------------------------------------------------------------------+
//| Release indicator handle                                       |
//+------------------------------------------------------------------+
bool CResourceManager::ReleaseIndicatorHandle(const int handle)
{
    if(handle == INVALID_HANDLE) return false;
    
    // Release the actual handle
    bool released = IndicatorRelease(handle);
    
    if(released)
    {
        // Remove from tracking array
        for(int i = 0; i < ArraySize(m_indicatorHandles); i++)
        {
            if(m_indicatorHandles[i] == handle)
            {
                m_indicatorHandles[i] = 0;
                break;
            }
        }
        
        // Find and release resource entry
        for(int i = 0; i < m_resourceCount; i++)
        {
            if(m_resources[i].type == RESOURCE_INDICATOR_HANDLE && 
               StringFind(m_resources[i].description, IntegerToString(handle)) >= 0)
            {
                ReleaseResource(m_resources[i].resourceId);
                break;
            }
        }
        
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_INFO, "ResourceManager",
                                       "Indicator handle released: " + IntegerToString(handle));
        }
    }
    else
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_WARNING, "ResourceManager",
                                       "Failed to release indicator handle: " + IntegerToString(handle));
        }
    }
    
    return released;
}

//+------------------------------------------------------------------+
//| Release all indicator handles                                  |
//+------------------------------------------------------------------+
void CResourceManager::ReleaseAllIndicatorHandles(void)
{
    int releasedCount = 0;
    
    for(int i = 0; i < ArraySize(m_indicatorHandles); i++)
    {
        if(m_indicatorHandles[i] != 0)
        {
            if(ReleaseIndicatorHandle(m_indicatorHandles[i]))
                releasedCount++;
        }
    }
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "ResourceManager",
                                   StringFormat("Released %d indicator handles", releasedCount));
    }
}

//+------------------------------------------------------------------+
//| Create and track file handle                                  |
//+------------------------------------------------------------------+
int CResourceManager::CreateFileHandle(const string filename, 
                                      const int flags,
                                      const string owner)
{
    if(!CheckResourceLimits(RESOURCE_FILE_HANDLE))
        return INVALID_HANDLE;
    
    int handle = FileOpen(filename, flags);
    
    if(handle == INVALID_HANDLE)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_RECOVERABLE, "ResourceManager",
                                       "Failed to create file handle: " + filename, GetLastError());
        }
        return INVALID_HANDLE;
    }
    
    // Track the handle
    int resourceId = AllocateResource(RESOURCE_FILE_HANDLE, filename, owner);
    
    // Store handle in tracking array
    for(int i = 0; i < ArraySize(m_fileHandles); i++)
    {
        if(m_fileHandles[i] == 0)
        {
            m_fileHandles[i] = handle;
            break;
        }
    }
    
    return handle;
}

//+------------------------------------------------------------------+
//| Release file handle                                            |
//+------------------------------------------------------------------+
bool CResourceManager::ReleaseFileHandle(const int handle)
{
    if(handle == INVALID_HANDLE) return false;
    
    FileClose(handle);
    
    // Remove from tracking array
    for(int i = 0; i < ArraySize(m_fileHandles); i++)
    {
        if(m_fileHandles[i] == handle)
        {
            m_fileHandles[i] = 0;
            break;
        }
    }
    
    // Find and release resource entry
    for(int i = 0; i < m_resourceCount; i++)
    {
        if(m_resources[i].type == RESOURCE_FILE_HANDLE)
        {
            ReleaseResource(m_resources[i].resourceId);
            break;
        }
    }
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "ResourceManager",
                                   "File handle released: " + IntegerToString(handle));
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Allocate memory block                                          |
//+------------------------------------------------------------------+
bool CResourceManager::AllocateMemory(const long size, 
                                     const string description,
                                     const string owner)
{
    if(!m_initialized) return false;
    
    // Check memory limits
    if(m_memoryStats.currentUsage + size > m_limits.maxMemoryUsage)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_WARNING, "ResourceManager",
                                       StringFormat("Memory limit would be exceeded: Current=%d, Requested=%d, Limit=%d",
                                                   m_memoryStats.currentUsage, size, m_limits.maxMemoryUsage));
        }
        return false;
    }
    
    // Allocate resource entry
    int resourceId = AllocateResource(RESOURCE_MEMORY_BLOCK, description, owner, size);
    
    return (resourceId > 0);
}

//+------------------------------------------------------------------+
//| Release memory block                                           |
//+------------------------------------------------------------------+
bool CResourceManager::ReleaseMemory(const string description)
{
    int index = FindResourceByDescription(description);
    if(index < 0) return false;
    
    return ReleaseResource(m_resources[index].resourceId);
}

//+------------------------------------------------------------------+
//| Get current memory usage                                       |
//+------------------------------------------------------------------+
long CResourceManager::GetMemoryUsage(void)
{
    UpdateMemoryStats();
    return m_memoryStats.currentUsage;
}

//+------------------------------------------------------------------+
//| Get memory statistics                                          |
//+------------------------------------------------------------------+
SMemoryStats CResourceManager::GetMemoryStats(void)
{
    UpdateMemoryStats();
    return m_memoryStats;
}

//+------------------------------------------------------------------+
//| Check if memory limit is exceeded                             |
//+------------------------------------------------------------------+
bool CResourceManager::IsMemoryLimitExceeded(void)
{
    return (m_memoryStats.currentUsage > m_limits.maxMemoryUsage);
}//+--
----------------------------------------------------------------+
//| Perform resource cleanup                                       |
//+------------------------------------------------------------------+
void CResourceManager::PerformCleanup(void)
{
    if(!m_initialized) return;
    
    datetime now = TimeCurrent();
    m_lastCleanup = now;
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "ResourceManager", "Starting resource cleanup");
    }
    
    // Clean up idle resources
    CleanupIdleResources();
    
    // Clean up leaked resources
    CleanupLeakedResources();
    
    // Update memory statistics
    UpdateMemoryStats();
    
    // Log resource usage
    LogResourceUsage();
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "ResourceManager", "Resource cleanup completed");
    }
}

//+------------------------------------------------------------------+
//| Perform automatic cleanup                                      |
//+------------------------------------------------------------------+
void CResourceManager::PerformAutomaticCleanup(void)
{
    if(!m_limits.autoCleanupEnabled) return;
    
    datetime now = TimeCurrent();
    if(now - m_lastCleanup >= m_limits.cleanupIntervalSeconds)
    {
        PerformCleanup();
    }
}

//+------------------------------------------------------------------+
//| Detect resource leaks                                          |
//+------------------------------------------------------------------+
void CResourceManager::DetectLeaks(void)
{
    int leakCount = 0;
    datetime now = TimeCurrent();
    
    for(int i = 0; i < m_resourceCount; i++)
    {
        // Consider resource leaked if not accessed for more than 1 hour
        if(now - m_resources[i].lastAccessTime > 3600)
        {
            m_resources[i].status = RESOURCE_LEAKED;
            leakCount++;
            
            CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
            if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
                localErrorHandler.LogError(ERROR_WARNING, "ResourceManager",
                                           StringFormat("Resource leak detected: ID=%d, Type=%s, Owner=%s, Age=%d seconds",
                                                       m_resources[i].resourceId,
                                                       GetResourceTypeString(m_resources[i].type),
                                                       m_resources[i].owner,
                                                       (int)(now - m_resources[i].createdTime)));
            }
        }
    }
    
    if(leakCount > 0)
    {
        m_memoryStats.leakedAllocations = leakCount;
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_WARNING, "ResourceManager",
                                       StringFormat("Total resource leaks detected: %d", leakCount));
        }
    }
}

//+------------------------------------------------------------------+
//| Check resource limits                                          |
//+------------------------------------------------------------------+
bool CResourceManager::CheckResourceLimits(const ENUM_RESOURCE_TYPE type)
{
    if(!m_limits.enforceStrictLimits) return true;
    
    switch(type)
    {
        case RESOURCE_INDICATOR_HANDLE:
            return (m_resourceCounters[(int)type] < m_limits.maxIndicatorHandles);
        case RESOURCE_FILE_HANDLE:
            return (m_resourceCounters[(int)type] < m_limits.maxFileHandles);
        case RESOURCE_MEMORY_BLOCK:
            return (m_memoryStats.currentUsage < m_limits.maxMemoryUsage);
        case RESOURCE_TIMER:
            return (m_resourceCounters[(int)type] < m_limits.maxTimers);
        case RESOURCE_OBJECT:
            return (m_resourceCounters[(int)type] < m_limits.maxObjects);
        case RESOURCE_CUSTOM:
            return (m_resourceCounters[(int)type] < m_limits.maxCustomResources);
        default:
            return true;
    }
}

//+------------------------------------------------------------------+
//| Generate resource report                                       |
//+------------------------------------------------------------------+
void CResourceManager::GenerateResourceReport(string &report)
{
    UpdateMemoryStats();
    
    report = "=== RESOURCE MANAGEMENT REPORT ===\n";
    report += "Generated: " + TimeToString(TimeCurrent()) + "\n";
    report += "Status: " + (m_initialized ? "INITIALIZED" : "NOT INITIALIZED") + "\n\n";
    
    // Resource limits
    report += "RESOURCE LIMITS:\n";
    report += StringFormat("Indicator Handles: %d / %d\n", m_resourceCounters[0], m_limits.maxIndicatorHandles);
    report += StringFormat("File Handles: %d / %d\n", m_resourceCounters[1], m_limits.maxFileHandles);
    report += StringFormat("Memory Usage: %d / %d bytes\n", m_memoryStats.currentUsage, m_limits.maxMemoryUsage);
    report += StringFormat("Timers: %d / %d\n", m_resourceCounters[3], m_limits.maxTimers);
    report += StringFormat("Objects: %d / %d\n", m_resourceCounters[4], m_limits.maxObjects);
    report += StringFormat("Custom Resources: %d / %d\n", m_resourceCounters[5], m_limits.maxCustomResources);
    report += StringFormat("Strict Limits: %s\n", m_limits.enforceStrictLimits ? "ENABLED" : "DISABLED");
    report += StringFormat("Auto Cleanup: %s\n\n", m_limits.autoCleanupEnabled ? "ENABLED" : "DISABLED");
    
    // Memory statistics
    report += "MEMORY STATISTICS:\n";
    report += StringFormat("Total Allocated: %d bytes\n", m_memoryStats.totalAllocated);
    report += StringFormat("Total Released: %d bytes\n", m_memoryStats.totalReleased);
    report += StringFormat("Current Usage: %d bytes\n", m_memoryStats.currentUsage);
    report += StringFormat("Peak Usage: %d bytes\n", m_memoryStats.peakUsage);
    report += StringFormat("Active Allocations: %d\n", m_memoryStats.activeAllocations);
    report += StringFormat("Total Allocations: %d\n", m_memoryStats.totalAllocations);
    report += StringFormat("Leaked Allocations: %d\n\n", m_memoryStats.leakedAllocations);
    
    // Active resources
    report += "ACTIVE RESOURCES:\n";
    for(int i = 0; i < m_resourceCount; i++)
    {
        if(m_resources[i].status == RESOURCE_ACTIVE)
        {
            report += StringFormat("ID: %d, Type: %s, Owner: %s, Size: %d, Age: %d sec\n",
                                  m_resources[i].resourceId,
                                  GetResourceTypeString(m_resources[i].type),
                                  m_resources[i].owner,
                                  m_resources[i].memorySize,
                                  (int)(TimeCurrent() - m_resources[i].createdTime));
        }
    }
    
    report += "\n=== END REPORT ===";
}

//+------------------------------------------------------------------+
//| Private helper methods                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Find resource index by ID                                     |
//+------------------------------------------------------------------+
int CResourceManager::FindResourceIndex(const int resourceId)
{
    for(int i = 0; i < m_resourceCount; i++)
    {
        if(m_resources[i].resourceId == resourceId)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Update memory statistics                                       |
//+------------------------------------------------------------------+
void CResourceManager::UpdateMemoryStats(void)
{
    m_memoryStats.lastUpdate = TimeCurrent();
    
    // Recalculate current usage from active resources
    long currentUsage = 0;
    int activeCount = 0;
    
    for(int i = 0; i < m_resourceCount; i++)
    {
        if(m_resources[i].status == RESOURCE_ACTIVE && m_resources[i].type == RESOURCE_MEMORY_BLOCK)
        {
            currentUsage += m_resources[i].memorySize;
            activeCount++;
        }
    }
    
    m_memoryStats.currentUsage = currentUsage;
    m_memoryStats.activeAllocations = activeCount;
}

//+------------------------------------------------------------------+
//| Get resource type string                                       |
//+------------------------------------------------------------------+
string CResourceManager::GetResourceTypeString(const ENUM_RESOURCE_TYPE type)
{
    switch(type)
    {
        case RESOURCE_INDICATOR_HANDLE: return "INDICATOR_HANDLE";
        case RESOURCE_FILE_HANDLE: return "FILE_HANDLE";
        case RESOURCE_MEMORY_BLOCK: return "MEMORY_BLOCK";
        case RESOURCE_TIMER: return "TIMER";
        case RESOURCE_OBJECT: return "OBJECT";
        case RESOURCE_CUSTOM: return "CUSTOM";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Cleanup idle resources                                         |
//+------------------------------------------------------------------+
void CResourceManager::CleanupIdleResources(void)
{
    int cleanedCount = 0;
    
    for(int i = m_resourceCount - 1; i >= 0; i--)
    {
        if(IsResourceIdle(m_resources[i].resourceId) && m_resources[i].autoCleanup)
        {
            ReleaseResource(m_resources[i].resourceId);
            cleanedCount++;
        }
    }
    
    if(cleanedCount > 0)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_INFO, "ResourceManager",
                                       StringFormat("Cleaned up %d idle resources", cleanedCount));
        }
    }
}

//+------------------------------------------------------------------+
//| Force cleanup all resources                                    |
//+------------------------------------------------------------------+
void CResourceManager::ForceCleanupAll(void)
{
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "ResourceManager", "Force cleanup all resources");
    }
    
    // Release all indicator handles
    ReleaseAllIndicatorHandles();
    
    // Release all file handles
    ReleaseAllFileHandles();
    
    // Release all timers
    ReleaseAllTimers();
    
    // Release all objects
    ReleaseAllObjects();
    
    // Clear all resource entries
    m_resourceCount = 0;
    for(int i = 0; i < 6; i++)
        m_resourceCounters[i] = 0;
    
    // Reset memory stats
    m_memoryStats.currentUsage = 0;
    m_memoryStats.activeAllocations = 0;
}

#endif // CORE_RESOURCE_MANAGER_MQH