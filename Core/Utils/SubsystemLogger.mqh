//+------------------------------------------------------------------+
//| SubsystemLogger.mqh - Separated Log Files for Different Modules  |
//| Provides isolated logging for Drawing, AI, Trading, Risk, etc.   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property version   "1.00"
#property strict

#ifndef SUBSYSTEM_LOGGER_MQH
#define SUBSYSTEM_LOGGER_MQH

//+------------------------------------------------------------------+
//| Log File Types                                                   |
//+------------------------------------------------------------------+
enum ENUM_LOG_SUBSYSTEM
{
    LOG_DRAWING,      // Chart drawing operations
    LOG_AI,           // AI/ML predictions and features
    LOG_TRADING,      // Trade execution and signals
    LOG_RISK,         // Risk management decisions
    LOG_CONSENSUS,    // Strategy consensus and voting
    LOG_PERFORMANCE,  // Performance analytics
    LOG_DEBUG         // General debugging
};

//+------------------------------------------------------------------+
//| Subsystem Logger Class                                           |
//| Creates separate .log files for each subsystem                   |
//+------------------------------------------------------------------+
class CSubsystemLogger
{
private:
    string m_basePath;
    string m_symbol;
    datetime m_lastFlushTime;
    int m_flushIntervalSec;
    
    // File handles for each subsystem (use array indexed by ENUM)
    int m_fileHandles[];
    int m_lineCounts[];
    
    int MAX_LINES_PER_FILE; // Rotate after 5000 lines
    
    string GetLogFileName(ENUM_LOG_SUBSYSTEM subsystem);
    void OpenFileIfNeeded(ENUM_LOG_SUBSYSTEM subsystem);
    
public:
    CSubsystemLogger();
    ~CSubsystemLogger();
    
    bool Initialize(const string symbol, const string basePath = "");
    void Deinitialize();
    
    void Log(ENUM_LOG_SUBSYSTEM subsystem, const string message);
    
    void Flush();
    void CloseAll();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSubsystemLogger::CSubsystemLogger() :
    m_basePath(""),
    m_symbol(""),
    m_lastFlushTime(0),
    m_flushIntervalSec(60),
    MAX_LINES_PER_FILE(5000)
{
    // Initialize arrays for 7 subsystem types
    ArrayResize(m_fileHandles, 7);
    ArrayResize(m_lineCounts, 7);
    ArrayInitialize(m_fileHandles, INVALID_HANDLE);
    ArrayInitialize(m_lineCounts, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSubsystemLogger::~CSubsystemLogger()
{
    CloseAll();
}

//+------------------------------------------------------------------+
//| Get Log File Name                                                |
//+------------------------------------------------------------------+
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
        case LOG_PERFORMANCE: prefix = "performance_"; break;
        case LOG_DEBUG:       prefix = "debug_"; break;
        default:              prefix = "unknown_"; break;
    }
    
    string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
    StringReplace(dateStr, ".", "_");
    
    return m_basePath + prefix + m_symbol + "_" + dateStr + ".log";
}

//+------------------------------------------------------------------+
//| Open File If Needed                                              |
//+------------------------------------------------------------------+
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
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize Logger                                                |
//+------------------------------------------------------------------+
bool CSubsystemLogger::Initialize(const string symbol, const string basePath = "")
{
    m_symbol = symbol;
    m_basePath = (basePath == "") ? "" : basePath;
    
    // Ensure base path ends with backslash
    if(StringLen(m_basePath) > 0 && StringSubstr(m_basePath, StringLen(m_basePath) - 1, 1) != "\\")
        m_basePath += "\\";
    
    Print("[SUBSYSTEM-LOGGER] Initialized for ", symbol, " | BasePath=", m_basePath);
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Logger                                              |
//+------------------------------------------------------------------+
void CSubsystemLogger::Deinitialize()
{
    CloseAll();
    Print("[SUBSYSTEM-LOGGER] Deinitialized");
}

//+------------------------------------------------------------------+
//| Log Message                                                      |
//+------------------------------------------------------------------+
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
    if(m_lineCounts[idx] >= MAX_LINES_PER_FILE)
    {
        FileClose(m_fileHandles[idx]);
        m_fileHandles[idx] = INVALID_HANDLE;
        m_lineCounts[idx] = 0;
        OpenFileIfNeeded(subsystem);
        if(m_fileHandles[idx] == INVALID_HANDLE)
            return;
    }
    
    // Format message with timestamp
    string timestamp = TimeToString(TimeCurrent(), TIME_SECONDS);
    string fullMessage = "[" + timestamp + "] " + message;
    
    // Write to file
    FileSeek(m_fileHandles[idx], 0, SEEK_END);
    FileWriteString(m_fileHandles[idx], fullMessage + "\r\n");
    FileFlush(m_fileHandles[idx]);
    m_lineCounts[idx]++;
    
    // Also print to terminal for critical messages
    if(subsystem == LOG_TRADING || subsystem == LOG_RISK)
        Print(fullMessage);
}

//+------------------------------------------------------------------+
//| Flush All Logs                                                   |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Close All Log Files                                              |
//+------------------------------------------------------------------+
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
