// SubsystemLogger.mqh - Separated Log Files for Different Modules
// Provides isolated logging for Drawing, AI, Trading, Risk, etc.
// L9-007: Routes through CJsonLogger for unified correlation IDs
#property copyright "Copyright 2025, Advanced Trading Systems"
#property version   "1.00"
#property strict

#ifndef SUBSYSTEM_LOGGER_MQH
#define SUBSYSTEM_LOGGER_MQH

#include "JsonLogger.mqh"

// Log File Types
enum ENUM_LOG_SUBSYSTEM
{
    LOG_DRAWING,      // Chart drawing operations
    LOG_AI,           // AI/ML predictions and features
    LOG_TRADING,      // Trade execution and signals
    LOG_RISK,         // Risk management decisions
    LOG_CONSENSUS,    // Strategy consensus and voting
    LOG_PERF,  // Performance analytics
    LOG_DEBUG         // General debugging
};

// Creates separate .log files for each subsystem
// Routes through CJsonLogger for unified correlation IDs
class CSubsystemLogger
{
private:
    string m_basePath;
    string m_symbol;
    datetime m_lastFlushTime;
    int m_flushIntervalSec;
    bool m_initialized;
    
    // File handles for each subsystem (use array indexed by ENUM)
    int m_fileHandles[];
    int m_lineCounts[];
    long m_fileSizes[];
    datetime m_fileCreationTimes[];
    
    int MAX_LINES_PER_FILE;     // Rotate after 5000 lines
    long MAX_FILE_SIZE_BYTES;   // Rotate after 10MB
    int MAX_FILE_AGE_DAYS;      // Rotate after 1 day
    int MAX_RETAINED_FILES;     // Keep max 7 rotated files
    
    string GetLogFileName(ENUM_LOG_SUBSYSTEM subsystem);
    void OpenFileIfNeeded(ENUM_LOG_SUBSYSTEM subsystem);
    void RotateIfNeeded(ENUM_LOG_SUBSYSTEM subsystem);
    string GetRotatedFileName(ENUM_LOG_SUBSYSTEM subsystem, int rotationIndex);
    void CleanupOldFiles(ENUM_LOG_SUBSYSTEM subsystem);
    
    // Map subsystem enum to component string for CJsonLogger
    string SubsystemToComponent(ENUM_LOG_SUBSYSTEM subsystem);
    
public:
    CSubsystemLogger();
    ~CSubsystemLogger();
    
    bool Initialize(const string symbol, const string basePath = "");
    void Deinitialize();
    
    void Log(ENUM_LOG_SUBSYSTEM subsystem, const string message);
    
    void Flush();
    void CloseAll();
};

// Constructor
CSubsystemLogger::CSubsystemLogger() :
    m_basePath(""),
    m_symbol(""),
    m_lastFlushTime(0),
    m_flushIntervalSec(60),
    m_initialized(false),
    MAX_LINES_PER_FILE(5000),
    MAX_FILE_SIZE_BYTES(10485760),  // 10MB
    MAX_FILE_AGE_DAYS(1),
    MAX_RETAINED_FILES(7)
{
    // Initialize arrays for 7 subsystem types
    ArrayResize(m_fileHandles, 7);
    ArrayResize(m_lineCounts, 7);
    ArrayResize(m_fileSizes, 7);
    ArrayResize(m_fileCreationTimes, 7);
    ArrayInitialize(m_fileHandles, INVALID_HANDLE);
    ArrayInitialize(m_lineCounts, 0);
    ArrayInitialize(m_fileSizes, 0);
    ArrayInitialize(m_fileCreationTimes, 0);
}

// Destructor
CSubsystemLogger::~CSubsystemLogger()
{
    if(m_initialized)
    {
        CloseAll();
    }
}

// Map subsystem enum to component string for CJsonLogger
string CSubsystemLogger::SubsystemToComponent(ENUM_LOG_SUBSYSTEM subsystem)
{
    switch(subsystem)
    {
        case LOG_DRAWING:     return "DRAWING";
        case LOG_AI:          return "AI";
        case LOG_TRADING:     return "TRADING";
        case LOG_RISK:        return "RISK";
        case LOG_CONSENSUS:   return "CONSENSUS";
        case LOG_PERF: return "PERFORMANCE";
        case LOG_DEBUG:       return "DEBUG";
        default:              return "UNKNOWN";
    }
}

string CSubsystemLogger::GetLogFileName(ENUM_LOG_SUBSYSTEM subsystem)
{
    string prefix = "";
    switch(subsystem)
    {
        case LOG_DRAWING:     prefix = "drawing_"; break;
        case LOG_AI:          prefix = "ai_"; break;
        case LOG_TRADING:     prefix = "trading_"; break;
        case LOG_RISK:        prefix = "risk_"; break;
        case LOG_CONSENSUS:   prefix = "consensus_"; break;
        case LOG_PERF: prefix = "performance_"; break;
        case LOG_DEBUG:       prefix = "debug_"; break;
        default:              prefix = "unknown_"; break;
    }
    
    string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
    StringReplace(dateStr, ".", "_");
    
    return m_basePath + prefix + m_symbol + "_" + dateStr + ".log";
}

string CSubsystemLogger::GetRotatedFileName(ENUM_LOG_SUBSYSTEM subsystem, int rotationIndex)
{
    string prefix = "";
    switch(subsystem)
    {
        case LOG_DRAWING:     prefix = "drawing_"; break;
        case LOG_AI:          prefix = "ai_"; break;
        case LOG_TRADING:     prefix = "trading_"; break;
        case LOG_RISK:        prefix = "risk_"; break;
        case LOG_CONSENSUS:   prefix = "consensus_"; break;
        case LOG_PERF: prefix = "performance_"; break;
        case LOG_DEBUG:       prefix = "debug_"; break;
        default:              prefix = "unknown_"; break;
    }
    
    string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
    StringReplace(dateStr, ".", "_");
    
    return m_basePath + prefix + m_symbol + "_" + dateStr + "_" + IntegerToString(rotationIndex) + ".log";
}

void CSubsystemLogger::OpenFileIfNeeded(ENUM_LOG_SUBSYSTEM subsystem)
{
    int idx = (int)subsystem;
    if(idx < 0 || idx >= ArraySize(m_fileHandles))
        return;
    
    if(m_fileHandles[idx] == INVALID_HANDLE)
    {
        string fileName = GetLogFileName(subsystem);
        m_fileHandles[idx] = FileOpen(fileName, FILE_WRITE | FILE_READ | FILE_TXT | FILE_COMMON);
        if(m_fileHandles[idx] != INVALID_HANDLE)
        {
            FileSeek(m_fileHandles[idx], 0, SEEK_END);
            m_fileCreationTimes[idx] = TimeCurrent();
            m_fileSizes[idx] = 0;
        }
    }
}

void CSubsystemLogger::RotateIfNeeded(ENUM_LOG_SUBSYSTEM subsystem)
{
    int idx = (int)subsystem;
    if(idx < 0 || idx >= ArraySize(m_fileHandles))
        return;
    
    bool needRotate = false;
    
    if(m_lineCounts[idx] >= MAX_LINES_PER_FILE)
        needRotate = true;
    
    if(m_fileSizes[idx] >= MAX_FILE_SIZE_BYTES)
        needRotate = true;
    
    // Check file age
    datetime now = TimeCurrent();
    if(m_fileCreationTimes[idx] > 0 && (now - m_fileCreationTimes[idx]) >= (MAX_FILE_AGE_DAYS * 86400))
        needRotate = true;
    
    if(needRotate && m_fileHandles[idx] != INVALID_HANDLE)
    {
        // Find next rotation index
        int rotationIdx = 1;
        while(rotationIdx <= MAX_RETAINED_FILES)
        {
            string rotatedName = GetRotatedFileName(subsystem, rotationIdx);
            int handle = FileOpen(rotatedName, FILE_READ | FILE_COMMON);
            if(handle == INVALID_HANDLE)
                break;
            FileClose(handle);
            rotationIdx++;
        }
        
        // Close current file
        FileClose(m_fileHandles[idx]);
        
        // Rename current to rotated
        string currentName = GetLogFileName(subsystem);
        string rotatedName = GetRotatedFileName(subsystem, rotationIdx);
        FileMove(currentName, FILE_COMMON, rotatedName, FILE_COMMON);
        
        // Reopen with fresh file
        m_fileHandles[idx] = INVALID_HANDLE;
        m_lineCounts[idx] = 0;
        m_fileSizes[idx] = 0;
        m_fileCreationTimes[idx] = 0;
        
        OpenFileIfNeeded(subsystem);
    }
}

// Cleanup Old Rotated Files
void CSubsystemLogger::CleanupOldFiles(ENUM_LOG_SUBSYSTEM subsystem)
{
    // Find and delete files beyond MAX_RETAINED_FILES
    int idx = MAX_RETAINED_FILES + 1;
    while(idx <= MAX_RETAINED_FILES + 10)  // safety limit
    {
        string rotatedName = GetRotatedFileName(subsystem, idx);
        int handle = FileOpen(rotatedName, FILE_READ | FILE_COMMON);
        if(handle == INVALID_HANDLE)
            break;
        FileClose(handle);
        FileDelete(rotatedName);
        idx++;
    }
}

bool CSubsystemLogger::Initialize(const string symbol, const string basePath = "")
{
    m_symbol = symbol;
    m_basePath = (basePath == "") ? "" : basePath;
    
    // Ensure base path ends with backslash
    if(StringLen(m_basePath) > 0 && StringSubstr(m_basePath, StringLen(m_basePath) - 1, 1) != "\\")
        m_basePath += "\\";
    
    m_initialized = true;
    
    Print("[SUBSYSTEM-LOGGER] Initialized for ", symbol, " | BasePath=", m_basePath);
    return true;
}

void CSubsystemLogger::Deinitialize()
{
    if(m_initialized)
    {
        CloseAll();
        m_initialized = false;
    }
    Print("[SUBSYSTEM-LOGGER] Deinitialized");
}

void CSubsystemLogger::Log(ENUM_LOG_SUBSYSTEM subsystem, const string message)
{
    int idx = (int)subsystem;
    if(idx < 0 || idx >= ArraySize(m_fileHandles))
        return;
    
    // Open file if not already open
    OpenFileIfNeeded(subsystem);
    
    if(m_fileHandles[idx] == INVALID_HANDLE)
        return;
    
    // Check rotation
    RotateIfNeeded(subsystem);
    
    if(m_fileHandles[idx] == INVALID_HANDLE)
        return;
    
    // Format message with timestamp
    string timestamp = TimeToString(TimeCurrent(), TIME_SECONDS);
    string fullMessage = "[" + timestamp + "] " + message;
    
    // Write to file
    FileSeek(m_fileHandles[idx], 0, SEEK_END);
    FileWriteString(m_fileHandles[idx], fullMessage + "\r\n");
    FileFlush(m_fileHandles[idx]);
    m_lineCounts[idx]++;
    
    // Update file size tracking
    m_fileSizes[idx] = (long)FileSize(m_fileHandles[idx]);
    
    // Route through CJsonLogger for structured JSON with correlation ID
    if(CJsonLogger::IsEnabled())
    {
        string component = SubsystemToComponent(subsystem);
        string correlationId = CJsonLogger::GetCorrelationId();
        
        // Map subsystem to log level
        // TRADING, RISK, CONSENSUS -> INFO level
        // AI, PERFORMANCE -> DEBUG level (verbose)
        // DRAWING, DEBUG -> DEBUG level
        string eventType = "";
        switch(subsystem)
        {
            case LOG_TRADING:    eventType = "TRADE"; break;
            case LOG_RISK:       eventType = "RISK_EVENT"; break;
            case LOG_CONSENSUS:  eventType = "CONSENSUS"; break;
            case LOG_AI:         eventType = "AI_EVENT"; break;
            case LOG_PERF: eventType = "PERFORMANCE"; break;
            case LOG_DRAWING:    eventType = "DRAWING"; break;
            case LOG_DEBUG:      eventType = "DEBUG"; break;
        }
        
        // Determine level based on subsystem
        if(subsystem == LOG_TRADING || subsystem == LOG_RISK || subsystem == LOG_CONSENSUS)
        {
            CJsonLogger::LogInfo(component, message, eventType, m_symbol, correlationId, "");
        }
        else
        {
            CJsonLogger::LogDebug(component, message, eventType, m_symbol, correlationId, "");
        }
    }
    
    // Also print to terminal for critical messages
    if(subsystem == LOG_TRADING || subsystem == LOG_RISK)
        Print(fullMessage);
}

// Flush All Logs
void CSubsystemLogger::Flush()
{
    datetime now = TimeCurrent();
    if(m_lastFlushTime == 0 || (now - m_lastFlushTime) >= m_flushIntervalSec)
    {
        for(int i = 0; i < ArraySize(m_fileHandles); i++)
        {
            if(m_fileHandles[i] != INVALID_HANDLE)
                FileFlush(m_fileHandles[i]);
        }
        m_lastFlushTime = now;
    }
}

// Close All Log Files
void CSubsystemLogger::CloseAll()
{
    for(int i = 0; i < ArraySize(m_fileHandles); i++)
    {
        if(m_fileHandles[i] != INVALID_HANDLE)
        {
            FileClose(m_fileHandles[i]);
            m_fileHandles[i] = INVALID_HANDLE;
        }
    }
}

#endif // SUBSYSTEM_LOGGER_MQH