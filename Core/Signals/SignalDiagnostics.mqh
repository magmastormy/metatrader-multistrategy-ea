//+------------------------------------------------------------------+
//| SignalDiagnostics.mqh                                           |
//| Comprehensive Signal Diagnostic and Logging System              |
//| Forensic-level logging for all strategy signals                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property version   "1.00"
#property strict

#ifndef SIGNAL_DIAGNOSTICS_MQH
#define SIGNAL_DIAGNOSTICS_MQH

#include "../Utils/Enums.mqh"
#include <Arrays/ArrayObj.mqh>

// Global per-session sequence to keep diagnostic file names unique
int g_signalDiagnosticsFileSequence = 0;

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Signal Decision Record                                          |
//+------------------------------------------------------------------+
struct SSignalRecord
{
    datetime timestamp;
    string   strategyName;
    string   symbol;
    int      timeframe;
    ENUM_TRADE_SIGNAL signal;
    double   confidence;
    string   reasoning;
    bool     wasExecuted;
    
    // Detailed factors
    double   trendScore;
    double   volatilityLevel;
    double   regimeScore;
    double   spreadCost;
    int      conflictCount;
    string   conflictingStrategies;
    
    // Timeframe analysis
    bool     timeframeAligned;
    string   timeframeConflicts;
    
    SSignalRecord()
    {
        timestamp = 0;
        strategyName = "";
        symbol = "";
        timeframe = 0;
        signal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        reasoning = "";
        wasExecuted = false;
        trendScore = 0.0;
        volatilityLevel = 0.0;
        regimeScore = 0.0;
        spreadCost = 0.0;
        conflictCount = 0;
        conflictingStrategies = "";
        timeframeAligned = true;
        timeframeConflicts = "";
    }
};

//+------------------------------------------------------------------+
//| Signal Diagnostics Class                                        |
//+------------------------------------------------------------------+
class CSignalDiagnostics
{
private:
    SSignalRecord m_records[];
    int           m_maxRecords;
    int           m_currentIndex;
    bool          m_enabled;
    int           m_logLevel; // 0=Error, 1=Warning, 2=Info, 3=Debug, 4=Trace
    
    // Statistics
    int           m_totalSignals;
    int           m_buySignals;
    int           m_sellSignals;
    int           m_noSignals;
    int           m_conflicts;
    int           m_timeframeConflicts;
    
    // File logging
    int           m_fileHandle;
    string        m_logFileName;
    string        m_lastNoSignalKey;
    datetime      m_lastNoSignalTime;
    int           m_pendingFlushCount;
    
public:
    CSignalDiagnostics();
    ~CSignalDiagnostics();
    
    // Initialize
    bool Initialize(int maxRecords = 1000, int logLevel = 3);
    void Shutdown();
    
    // Main logging methods
    void LogSignalGeneration(const string strategyName, 
                           const string symbol,
                           const int timeframe,
                           const ENUM_TRADE_SIGNAL signal,
                           const double confidence,
                           const string reasoning);
                           
    void LogNoSignal(const string strategyName,
                    const string symbol,
                    const int timeframe,
                    const string reason);
                    
    void LogSignalConflict(const string &strategies[],
                          const ENUM_TRADE_SIGNAL &signals[],
                          const int count,
                          const string resolution);
                          
    void LogTimeframeConflict(const string strategy,
                             const int tf1, const ENUM_TRADE_SIGNAL signal1,
                             const int tf2, const ENUM_TRADE_SIGNAL signal2);
                             
    void LogStrategyError(const string strategyName,
                         const string errorType,
                         const string details);
                         
    void LogOrchestrationDecision(const string &selectedStrategies[],
                                 const double &weights[],
                                 const int count,
                                 const ENUM_TRADE_SIGNAL finalSignal,
                                 const double finalConfidence,
                                 const string reason = "");
                                 
    void LogHedgingPrevented(const string strategy,
                            ENUM_TRADE_SIGNAL attemptedSignal,
                            const string reason);
                         
    void LogStrategySelection(const string &selectedStrategies[], const double &weights[],
                               const string reason);
    
    void LogEnsembleDecision(const string &strategies[], ENUM_TRADE_SIGNAL &signals[],
                             const string &selectedStrategies[], const double &weights[],
                             ENUM_TRADE_SIGNAL finalSignal, double finalConfidence,
                             const string reason);
    
    void LogMultiTimeframeAnalysis(const string &strategies[], ENUM_TRADE_SIGNAL &signals[],
                                   const double &confidences[], const ENUM_TIMEFRAMES &timeframes[]);
    
    // Unified ICT structure logging
    void LogSMCDetection(const string type,
                        const string symbol,
                        const double price,
                        const double top,
                        const double bottom,
                        const bool bullish,
                        const double score);
                        
    void LogSMCMitigation(const string type,
                         const double price,
                         const bool successful);
                         
    void LogBOSCHOCH(const bool isBOS, // true=BOS, false=CHOCH
                    const double level,
                    const bool bullish);
    
    // Analysis methods
    string GetDiagnosticSummary();
    string GetStrategyPerformance(const string strategyName);
    string GetConflictAnalysis();
    string GetTimeframeAnalysis();
    
    // Getters
    int GetTotalSignals() const { return m_totalSignals; }
    int GetConflictCount() const { return m_conflicts; }
    double GetConflictRate() const { return m_totalSignals > 0 ? (double)m_conflicts / m_totalSignals : 0.0; }
    
    // Configuration
    void SetLogLevel(int level) { m_logLevel = level; }
    void EnableDiagnostics(bool enable) { m_enabled = enable; }
    
    // Validation
    bool ValidateAndLogConfidence(const string strategyName, const string symbol, const double confidence);
    
private:
    void WriteToFile(const string message);
    void AddRecord(const SSignalRecord &record);
    string SignalToString(ENUM_TRADE_SIGNAL signal);
    string TimeframeToString(int tf);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSignalDiagnostics::CSignalDiagnostics() :
    m_maxRecords(1000),
    m_currentIndex(0),
    m_enabled(true),
    m_logLevel(3),
    m_totalSignals(0),
    m_buySignals(0),
    m_sellSignals(0),
    m_noSignals(0),
    m_conflicts(0),
    m_timeframeConflicts(0),
    m_fileHandle(INVALID_HANDLE),
    m_lastNoSignalKey(""),
    m_lastNoSignalTime(0),
    m_pendingFlushCount(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSignalDiagnostics::~CSignalDiagnostics()
{
    Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSignalDiagnostics::Initialize(int maxRecords = 1000, int logLevel = 3)
{
    m_maxRecords = maxRecords;
    m_logLevel = logLevel;
    m_currentIndex = 0;
    m_lastNoSignalKey = "";
    m_lastNoSignalTime = 0;
    ArrayResize(m_records, m_maxRecords);
    
    // Create log file with proper directory
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
    StringReplace(timestamp, ":", "-");
    StringReplace(timestamp, " ", "_");
    g_signalDiagnosticsFileSequence++;
    string uniqueSuffix = IntegerToString((int)GetTickCount()) + "_" + IntegerToString(g_signalDiagnosticsFileSequence);
    
    // Use userReports directory (same as EA logs)
    string logDir = "userReports";
    ResetLastError();
    FolderCreate(logDir);
    m_logFileName = logDir + "\\SignalDiagnostics_" + timestamp + "_" + uniqueSuffix + ".log";
    
    // Try terminal-local file first
    m_fileHandle = FileOpen(m_logFileName, FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(m_fileHandle == INVALID_HANDLE)
    {
        // Fallback to terminal COMMON files to avoid path/permission collisions
        string commonFileName = "SignalDiagnostics_" + timestamp + "_" + uniqueSuffix + ".log";
        m_fileHandle = FileOpen(commonFileName, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
        if(m_fileHandle != INVALID_HANDLE)
        {
            m_logFileName = "COMMON\\" + commonFileName;
        }
        else
        {
            int error = GetLastError();
            Print("[SignalDiagnostics] Failed to create log file: ", m_logFileName, " Error: ", error);
            Print("[SignalDiagnostics] Will continue without file logging (console only)");
            // Don't fail initialization - just continue without file logging
            return true;
        }
    }
    
    WriteToFile("=== Signal Diagnostics System Initialized ===");
    WriteToFile("Max Records: " + IntegerToString(m_maxRecords));
    WriteToFile("Log Level: " + IntegerToString(m_logLevel));
    WriteToFile("Timestamp: " + TimeToString(TimeCurrent()));
    WriteToFile("==========================================\n");
    
    Print("[SignalDiagnostics] Initialized successfully. Log file: ", m_logFileName);
    return true;
}

//+------------------------------------------------------------------+
//| Shutdown                                                         |
//+------------------------------------------------------------------+
void CSignalDiagnostics::Shutdown()
{
    if(m_fileHandle != INVALID_HANDLE)
    {
        WriteToFile("\n=== Signal Diagnostics Summary ===");
        WriteToFile(GetDiagnosticSummary());
        WriteToFile("=== Shutdown at " + TimeToString(TimeCurrent()) + " ===");
        FileFlush(m_fileHandle);
        
        FileClose(m_fileHandle);
        m_fileHandle = INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Log Signal Generation                                           |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogSignalGeneration(const string strategyName, 
                                            const string symbol,
                                            const int timeframe,
                                            const ENUM_TRADE_SIGNAL signal,
                                            const double confidence,
                                            const string reasoning)
{
    if(!m_enabled) return;
    
    // Validate confidence
    ValidateAndLogConfidence(strategyName, symbol, confidence);
    
    SSignalRecord record;
    record.timestamp = TimeCurrent();
    record.strategyName = strategyName;
    record.symbol = symbol;
    record.timeframe = timeframe;
    record.signal = signal;
    record.confidence = confidence;
    record.reasoning = reasoning;
    
    AddRecord(record);
    m_totalSignals++;
    
    if(signal == TRADE_SIGNAL_BUY) m_buySignals++;
    else if(signal == TRADE_SIGNAL_SELL) m_sellSignals++;
    
    if(m_logLevel >= 2)
    {
        string msg = StringFormat("[SIGNAL] %s | %s | %s | Signal: %s | Confidence: %.2f%% | Reason: %s",
                                strategyName, symbol, TimeframeToString(timeframe),
                                SignalToString(signal), confidence * 100, reasoning);
        Print(msg);
        WriteToFile(msg);
    }
}

//+------------------------------------------------------------------+
//| Log No Signal                                                   |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogNoSignal(const string strategyName,
                                    const string symbol,
                                    const int timeframe,
                                    const string reason)
{
    if(!m_enabled || m_logLevel < 3) return;

    // Suppress duplicate no-signal spam occurring within the same second.
    string signalKey = strategyName + "|" + symbol + "|" + IntegerToString(timeframe) + "|" + reason;
    datetime nowTime = TimeCurrent();
    if(signalKey == m_lastNoSignalKey && nowTime == m_lastNoSignalTime)
        return;
    m_lastNoSignalKey = signalKey;
    m_lastNoSignalTime = nowTime;
    
    m_noSignals++;
    
    string msg = StringFormat("[NO_SIGNAL] %s | %s | %s | Reason: %s",
                            strategyName, symbol, TimeframeToString(timeframe), reason);
    
    if(m_logLevel >= 3)
    {
        Print(msg);
        WriteToFile(msg);
    }
}

//+------------------------------------------------------------------+
//| Log Signal Conflict                                             |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogSignalConflict(const string &strategies[],
                                          const ENUM_TRADE_SIGNAL &signals[],
                                          const int count,
                                          const string resolution)
{
    if(!m_enabled) return;
    
    m_conflicts++;
    
    string conflictDetails = "[CONFLICT] Strategies: ";
    for(int i = 0; i < count; i++)
    {
        conflictDetails += strategies[i] + "(" + SignalToString(signals[i]) + ")";
        if(i < count - 1) conflictDetails += " vs ";
    }
    conflictDetails += " | Resolution: " + resolution;
    
    Print(conflictDetails);
    WriteToFile(conflictDetails);
}

//+------------------------------------------------------------------+
//| Log Timeframe Conflict                                          |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogTimeframeConflict(const string strategy,
                                             const int tf1, const ENUM_TRADE_SIGNAL signal1,
                                             const int tf2, const ENUM_TRADE_SIGNAL signal2)
{
    if(!m_enabled) return;
    
    m_timeframeConflicts++;
    
    string msg = StringFormat("[TF_CONFLICT] %s | %s(%s) vs %s(%s)",
                            strategy,
                            TimeframeToString(tf1), SignalToString(signal1),
                            TimeframeToString(tf2), SignalToString(signal2));
    
    Print(msg);
    WriteToFile(msg);
}

//+------------------------------------------------------------------+
//| Log Strategy Error                                              |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogStrategyError(const string strategyName,
                                         const string errorType,
                                         const string details)
{
    if(!m_enabled) return;

    string normalizedType = errorType;
    StringToUpper(normalizedType);
    bool isDebug = (normalizedType == "DEBUG");
    bool isTrace = (normalizedType == "TRACE");

    if(isDebug && m_logLevel < 3) return;
    if(isTrace && m_logLevel < 4) return;

    string levelTag = "[ERROR]";
    if(isDebug) levelTag = "[DEBUG]";
    else if(isTrace) levelTag = "[TRACE]";

    string msg = StringFormat("%s %s | Type: %s | Details: %s",
                            levelTag, strategyName, errorType, details);
    
    Print(msg);
    WriteToFile(msg);
}

//+------------------------------------------------------------------+
//| Log Orchestration Decision                                      |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogOrchestrationDecision(const string &selectedStrategies[],
                                                 const double &weights[],
                                                 const int count,
                                                 const ENUM_TRADE_SIGNAL finalSignal,
                                                 const double finalConfidence,
                                                 const string reason = "")
{
    if(!m_enabled || m_logLevel < 2) return;
    
    string msg = "[ORCHESTRATOR] Selected: ";
    for(int i = 0; i < count; i++)
    {
        msg += StringFormat("%s(%.2f)", selectedStrategies[i], weights[i]);
        if(i < count - 1) msg += ", ";
    }
    msg += StringFormat(" | Final: %s (%.2f%%)", 
                       SignalToString(finalSignal), finalConfidence * 100);
    
    Print(msg);
    WriteToFile(msg);
}

//+------------------------------------------------------------------+
//| Log Hedging Prevented                                           |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogHedgingPrevented(const string strategy,
                                            ENUM_TRADE_SIGNAL attemptedSignal,
                                            const string reason)
{
    if(!m_enabled) return;
    
    string msg = StringFormat("[HEDGE_PREVENTED] Strategy: %s | Attempted: %s | Reason: %s",
                            strategy,
                            SignalToString(attemptedSignal),
                            reason);
    
    Print(msg);
    WriteToFile(msg);
}

//+------------------------------------------------------------------+
//| Log Unified ICT Structure Detection                             |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogSMCDetection(const string type,
                                        const string symbol,
                                        const double price,
                                        const double top,
                                        const double bottom,
                                        const bool bullish,
                                        const double score)
{
    if(!m_enabled || m_logLevel < 3) return;
    
    string msg = StringFormat("[ICT_STRUCT_%s] %s | Price: %.5f | Zone: %.5f-%.5f | %s | Score: %.1f",
                            type, symbol, price, bottom, top,
                            bullish ? "BULLISH" : "BEARISH",
                            score);
    
    if(m_logLevel >= 3)
    {
        Print(msg);
        WriteToFile(msg);
    }
}

//+------------------------------------------------------------------+
//| Log Unified ICT Structure Mitigation                            |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogSMCMitigation(const string type,
                                         const double price,
                                         const bool successful)
{
    if(!m_enabled || m_logLevel < 3) return;
    
    string msg = StringFormat("[ICT_MITIGATED] %s | Price: %.5f | %s",
                            type, price,
                            successful ? "SUCCESS" : "FAILED");
    
    Print(msg);
    WriteToFile(msg);
}

//+------------------------------------------------------------------+
//| Log BOS/CHOCH                                                   |
//+------------------------------------------------------------------+
void CSignalDiagnostics::LogBOSCHOCH(const bool isBOS,
                                    const double level,
                                    const bool bullish)
{
    if(!m_enabled || m_logLevel < 3) return;
    
    string msg = StringFormat("[%s] Level: %.5f | Direction: %s",
                            isBOS ? "BOS" : "CHOCH",
                            level,
                            bullish ? "BULLISH" : "BEARISH");
    
    Print(msg);
    WriteToFile(msg);
}

//+------------------------------------------------------------------+
//| Get Diagnostic Summary                                          |
//+------------------------------------------------------------------+
string CSignalDiagnostics::GetDiagnosticSummary()
{
    string summary = "";
    summary += "Total Signals: " + IntegerToString(m_totalSignals) + "\n";
    summary += "Buy Signals: " + IntegerToString(m_buySignals) + "\n";
    summary += "Sell Signals: " + IntegerToString(m_sellSignals) + "\n";
    summary += "No Signals: " + IntegerToString(m_noSignals) + "\n";
    summary += "Conflicts: " + IntegerToString(m_conflicts) + "\n";
    summary += "Timeframe Conflicts: " + IntegerToString(m_timeframeConflicts) + "\n";
    summary += StringFormat("Conflict Rate: %.2f%%\n", GetConflictRate() * 100);
    
    return summary;
}

//+------------------------------------------------------------------+
//| Helper: Write to File                                           |
//+------------------------------------------------------------------+
void CSignalDiagnostics::WriteToFile(const string message)
{
    if(m_fileHandle != INVALID_HANDLE)
    {
        string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
        FileWriteString(m_fileHandle, timestamp + " | " + message + "\n");
        m_pendingFlushCount++;
        if(m_pendingFlushCount >= 25)
        {
            FileFlush(m_fileHandle);
            m_pendingFlushCount = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| Helper: Add Record                                              |
//+------------------------------------------------------------------+
void CSignalDiagnostics::AddRecord(const SSignalRecord &record)
{
    if(m_currentIndex >= m_maxRecords)
        m_currentIndex = 0;
        
    m_records[m_currentIndex] = record;
    m_currentIndex++;
}

//+------------------------------------------------------------------+
//| Helper: Signal to String                                        |
//+------------------------------------------------------------------+
string CSignalDiagnostics::SignalToString(ENUM_TRADE_SIGNAL signal)
{
    switch(signal)
    {
        case TRADE_SIGNAL_BUY: return "BUY";
        case TRADE_SIGNAL_SELL: return "SELL";
        case TRADE_SIGNAL_NONE: return "NONE";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Helper: Timeframe to String                                     |
//+------------------------------------------------------------------+
string CSignalDiagnostics::TimeframeToString(int tf)
{
    switch(tf)
    {
        case PERIOD_M1: return "M1";
        case PERIOD_M5: return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1: return "H1";
        case PERIOD_H4: return "H4";
        case PERIOD_D1: return "D1";
        case PERIOD_W1: return "W1";
        case PERIOD_MN1: return "MN1";
        default: return "TF" + IntegerToString(tf);
    }
}


// Duplicate methods removed - already defined above

//+------------------------------------------------------------------+
//| Validate and Log Confidence                                     |
//+------------------------------------------------------------------+
bool CSignalDiagnostics::ValidateAndLogConfidence(const string strategyName, const string symbol, const double confidence)
{
    if(confidence < 0.0 || confidence > 1.0)
    {
        string msg = StringFormat("[CRITICAL_ALERT] INVALID_CONFIDENCE | %s | %s | Value: %.4f | Range: [0.0, 1.0]",
                                strategyName, symbol, confidence);
        
        Print(msg);
        WriteToFile(msg);
        
        // Also log to error handler if available
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID)
        {
            localErrorHandler.LogError(ERROR_CRITICAL, "SignalDiagnostics", 
                                "Confidence out of bounds: " + DoubleToString(confidence, 4));
        }
        
        return false;
    }
    return true;
}

#endif // SIGNAL_DIAGNOSTICS_MQH
