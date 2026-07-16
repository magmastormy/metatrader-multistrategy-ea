//+------------------------------------------------------------------+
//| DiagnosticsLogger.mqh - Off-Journal Diagnostic Logging           |
//| Routes verbose/normal diagnostics to file instead of MT5 Journal |
//| Blueprint Section 3.6: Logging Throttle                          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef DIAGNOSTICS_LOGGER_MQH
#define DIAGNOSTICS_LOGGER_MQH

//+------------------------------------------------------------------+
//| Diagnostics Logger Class                                         |
//| Writes level-gated diagnostic output to a dedicated log file     |
//| so the MT5 Journal is not saturated by heartbeat/diagnostics.    |
//+------------------------------------------------------------------+
class CDiagnosticsLogger
{
private:
   int      m_fileHandle;
   string   m_filePath;
   bool     m_enabled;
   int      m_logLevel;        // 0=Silent, 1=Critical, 2=Normal, 3=Verbose
   datetime m_lastFlush;
   int      m_flushIntervalSec; // default 5

public:
   CDiagnosticsLogger();
   ~CDiagnosticsLogger();

   bool Initialize(string eaName, int logLevel, int flushIntervalSec = 5);
   void Deinit();

   // Level-gated logging
   void LogCritical(string message);
   void LogNormal(string message);
   void LogVerbose(string message);

   // Write to file (not journal)
   void WriteToFile(string message);

   // Flush buffer to disk
   void Flush();

   // Set flush interval
   void SetFlushInterval(int flushIntervalSec) { m_flushIntervalSec = MathMax(1, flushIntervalSec); }

   // Getters
   int  GetLogLevel() const { return m_logLevel; }
   bool IsVerbose() const { return m_logLevel >= 3; }
   bool IsNormal() const { return m_logLevel >= 2; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDiagnosticsLogger::CDiagnosticsLogger() :
   m_fileHandle(INVALID_HANDLE),
   m_filePath(""),
   m_enabled(false),
   m_logLevel(1),
   m_lastFlush(0),
   m_flushIntervalSec(5)
{}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CDiagnosticsLogger::~CDiagnosticsLogger()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CDiagnosticsLogger::Initialize(string eaName, int logLevel, int flushIntervalSec)
{
   m_logLevel = MathMax(0, MathMin(4, logLevel));
   m_flushIntervalSec = MathMax(1, flushIntervalSec);
   m_filePath = eaName + "_diagnostics.log";

   m_fileHandle = FileOpen(m_filePath,
                           FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(m_fileHandle != INVALID_HANDLE)
   {
      FileSeek(m_fileHandle, 0, SEEK_END);
      m_enabled = true;
      WriteToFile("=== Diagnostics Logger Initialized | Level=" + IntegerToString(m_logLevel) + " | FlushInterval=" + IntegerToString(m_flushIntervalSec) + "s ===");
   }
   else
   {
      m_enabled = false;
      Print("[DIAG-LOGGER] WARNING: Failed to open diagnostics file, falling back to journal");
   }

   return m_enabled;
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void CDiagnosticsLogger::Deinit()
{
   if(m_fileHandle != INVALID_HANDLE)
   {
      WriteToFile("=== Diagnostics Logger Shutdown ===");
      FileFlush(m_fileHandle);
      FileClose(m_fileHandle);
      m_fileHandle = INVALID_HANDLE;
   }
   m_enabled = false;
}

//+------------------------------------------------------------------+
//| Log Critical (level >= 1)                                        |
//+------------------------------------------------------------------+
void CDiagnosticsLogger::LogCritical(string message)
{
   if(m_logLevel < 1)
      return;
   WriteToFile("[CRITICAL] " + message);
}

//+------------------------------------------------------------------+
//| Log Normal (level >= 2)                                          |
//+------------------------------------------------------------------+
void CDiagnosticsLogger::LogNormal(string message)
{
   if(m_logLevel < 2)
      return;
   WriteToFile("[NORMAL] " + message);
}

//+------------------------------------------------------------------+
//| Log Verbose (level >= 3)                                         |
//+------------------------------------------------------------------+
void CDiagnosticsLogger::LogVerbose(string message)
{
   if(m_logLevel < 3)
      return;
   WriteToFile("[VERBOSE] " + message);
}

//+------------------------------------------------------------------+
//| Write to file (not journal)                                      |
//| Falls back to Print if file handle is invalid                    |
//+------------------------------------------------------------------+
void CDiagnosticsLogger::WriteToFile(string message)
{
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   string fullMessage = "[" + timestamp + "] " + message;

   if(m_fileHandle != INVALID_HANDLE)
   {
      FileSeek(m_fileHandle, 0, SEEK_END);
      FileWriteString(m_fileHandle, fullMessage + "\r\n");
      Flush();
   }
   else
   {
      // Fallback to journal when file is unavailable
      Print(fullMessage);
   }
}

//+------------------------------------------------------------------+
//| Flush buffer to disk (throttled to every m_flushIntervalSec)     |
//+------------------------------------------------------------------+
void CDiagnosticsLogger::Flush()
{
   datetime now = TimeCurrent();
   if(m_lastFlush == 0 || (now - m_lastFlush) >= m_flushIntervalSec)
   {
      if(m_fileHandle != INVALID_HANDLE)
         FileFlush(m_fileHandle);
      m_lastFlush = now;
   }
}

#endif // DIAGNOSTICS_LOGGER_MQH

//+------------------------------------------------------------------+
//| ErrorAggregator.mqh - Periodic Error Aggregate Logging           |
//| Aggregates errors by type and logs summary periodically          |
//+------------------------------------------------------------------+
#ifndef ERROR_AGGREGATOR_MQH
#define ERROR_AGGREGATOR_MQH

#include "DiagnosticsLogger.mqh"

struct SErrorAggregate
{
    string errorCode;
    int    count;
    datetime firstOccurrence;
    datetime lastOccurrence;
    string lastContext;

    SErrorAggregate() : count(0), firstOccurrence(0), lastOccurrence(0) {}
};

class CErrorAggregator
{
private:
    SErrorAggregate m_errors[];
    int m_errorCount;
    CDiagnosticsLogger* m_logger;
    datetime m_lastAggregateLog;
    int m_aggregateIntervalSec;

public:
    CErrorAggregator() : m_errorCount(0), m_logger(NULL), m_lastAggregateLog(0), m_aggregateIntervalSec(300) {}
    
    void Initialize(CDiagnosticsLogger* logger, int intervalSec = 300)
    {
        m_logger = logger;
        m_aggregateIntervalSec = MathMax(60, intervalSec);
        ArrayResize(m_errors, 50);
        // ArrayInitialize not supported for struct arrays in MQL5 - elements are default-initialized on resize
    }
    
    void RecordError(const string errorCode, const string context = "")
    {
        int idx = FindError(errorCode);
        if(idx < 0)
        {
            if(m_errorCount >= ArraySize(m_errors))
            {
                ArrayResize(m_errors, ArraySize(m_errors) + 20);
                // ArrayInitialize not supported for struct arrays in MQL5 - elements are default-initialized on resize
            }
            idx = m_errorCount;
            m_errors[idx].errorCode = errorCode;
            m_errors[idx].count = 0;
            m_errors[idx].firstOccurrence = TimeCurrent();
            m_errorCount++;
        }
        
        m_errors[idx].count++;
        m_errors[idx].lastOccurrence = TimeCurrent();
        if(StringLen(context) > 0)
            m_errors[idx].lastContext = context;
        
        // Check if we should log aggregate
        CheckAndLogAggregate();
    }
    
    int FindError(const string errorCode) const
    {
        for(int i = 0; i < m_errorCount; i++)
        {
            if(m_errors[i].errorCode == errorCode)
                return i;
        }
        return -1;
    }
    
    void CheckAndLogAggregate()
    {
        datetime now = TimeCurrent();
        if(m_lastAggregateLog == 0 || (now - m_lastAggregateLog) >= m_aggregateIntervalSec)
        {
            LogAggregate();
            m_lastAggregateLog = now;
        }
    }
    
    void LogAggregate()
    {
        if(m_logger == NULL || m_errorCount == 0)
            return;
        
        string summary = "[ERROR-AGGREGATE] Periodic error summary (last " + IntegerToString(m_aggregateIntervalSec) + "s):";
        for(int i = 0; i < m_errorCount; i++)
        {
            if(m_errors[i].count > 0)
            {
                summary += "\n  " + m_errors[i].errorCode + ": " + IntegerToString(m_errors[i].count) + " occurrences | First: " + TimeToString(m_errors[i].firstOccurrence, TIME_SECONDS) + " | Last: " + TimeToString(m_errors[i].lastOccurrence, TIME_SECONDS);
                if(StringLen(m_errors[i].lastContext) > 0)
                    summary += " | Context: " + m_errors[i].lastContext;
            }
        }
        
        m_logger.LogCritical(summary);
    }
    
    void Reset()
    {
        for(int i = 0; i < m_errorCount; i++)
        {
            m_errors[i].count = 0;
            m_errors[i].firstOccurrence = 0;
            m_errors[i].lastOccurrence = 0;
            m_errors[i].lastContext = "";
        }
        m_errorCount = 0;
    }
};

#endif // ERROR_AGGREGATOR_MQH
