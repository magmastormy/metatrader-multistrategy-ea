// DiagnosticsLogger.mqh - Off-Journal Diagnostic Logging
// Routes verbose/normal diagnostics to file instead of MT5 Journal
// Blueprint Section 3.6: Logging Throttle
// L9-007: Routes through CJsonLogger for unified correlation IDs
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef DIAGNOSTICS_LOGGER_MQH
#define DIAGNOSTICS_LOGGER_MQH

#include "JsonLogger.mqh"

// Writes level-gated diagnostic output to a dedicated log file
// so the MT5 Journal is not saturated by heartbeat/diagnostics.
// Routes through CJsonLogger for unified correlation IDs.
class CDiagnosticsLogger
{
private:
   // Rotation thresholds (enum for compile-time constants)
   enum {
       MAX_FILE_SIZE_BYTES = 10485760,  // 10MB
       MAX_LINES_PER_FILE = 5000,
       MAX_FILE_AGE_DAYS = 1,
       MAX_RETAINED_FILES = 7
   };

   int      m_fileHandle;
   string   m_filePath;
   string   m_component;         // Component name for structured logging
   bool     m_enabled;
   int      m_logLevel;          // 0=Silent, 1=Critical, 2=Normal, 3=Verbose
   datetime m_lastFlush;
   int      m_flushIntervalSec;  // default 5

   // Log rotation tracking
   long     m_fileSizeBytes;
   int      m_lineCount;
   datetime m_fileCreationTime;

   // Helper methods for rotation
   string GetBaseFileName() const;
   string GetRotatedFileName(int rotationIndex) const;
   void RotateIfNeeded();
   void CleanupOldFiles();

public:
   CDiagnosticsLogger();
   ~CDiagnosticsLogger();

   bool Initialize(string eaName, int logLevel, int flushIntervalSec = 5);
   bool InitializeEx(string eaName, string component, int logLevel, int flushIntervalSec = 5);
   void Deinit();

   // Level-gated logging - routes through CJsonLogger for correlation IDs
   void LogCritical(string message);
   void LogNormal(string message);
   void LogVerbose(string message);

   // Write to file (not journal) - also routes through CJsonLogger
   void WriteToFile(string message);

   // Flush buffer to disk
   void Flush();

   void SetFlushInterval(int flushIntervalSec) { m_flushIntervalSec = MathMax(1, flushIntervalSec); }

   int  GetLogLevel() const { return m_logLevel; }
   bool IsVerbose() const { return m_logLevel >= 3; }
   bool IsNormal() const { return m_logLevel >= 2; }
   string GetComponent() const { return m_component; }
};

// Constructor
CDiagnosticsLogger::CDiagnosticsLogger() :
   m_fileHandle(INVALID_HANDLE),
   m_filePath(""),
   m_component(""),
   m_enabled(false),
   m_logLevel(1),
   m_lastFlush(0),
   m_flushIntervalSec(5),
   m_fileSizeBytes(0),
   m_lineCount(0),
   m_fileCreationTime(0)
{}

// Destructor
CDiagnosticsLogger::~CDiagnosticsLogger()
{
   Deinit();
}

bool CDiagnosticsLogger::Initialize(string eaName, int logLevel, int flushIntervalSec)
{
   return InitializeEx(eaName, "", logLevel, flushIntervalSec);
}

bool CDiagnosticsLogger::InitializeEx(string eaName, string component, int logLevel, int flushIntervalSec)
{
   m_logLevel = MathMax(0, MathMin(4, logLevel));
   m_flushIntervalSec = MathMax(1, flushIntervalSec);
   m_filePath = eaName + "_diagnostics.log";
   m_component = component;

   m_fileHandle = FileOpen(m_filePath,
                           FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(m_fileHandle != INVALID_HANDLE)
   {
      FileSeek(m_fileHandle, 0, SEEK_END);
      m_enabled = true;
      m_fileSizeBytes = 0;
      m_lineCount = 0;
      m_fileCreationTime = TimeCurrent();
      WriteToFile("=== Diagnostics Logger Initialized | Component=" + m_component + " | Level=" + IntegerToString(m_logLevel) + " | FlushInterval=" + IntegerToString(m_flushIntervalSec) + "s ===");
   }
   else
   {
      m_enabled = false;
      Print("[DIAG-LOGGER] WARNING: Failed to open diagnostics file, falling back to journal");
   }

   return m_enabled;
}

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

// Log Critical (level >= 1)
void CDiagnosticsLogger::LogCritical(string message)
{
   if(m_logLevel < 1)
      return;
   
   // Route through CJsonLogger for structured JSON with correlation ID
   if(CJsonLogger::IsEnabled() && m_component != "")
   {
      CJsonLogger::LogError(m_component, message, "CRITICAL", CJsonLogger::GetCorrelationId(), "");
   }
   
   WriteToFile("[CRITICAL] " + message);
}

// Log Normal (level >= 2)
void CDiagnosticsLogger::LogNormal(string message)
{
   if(m_logLevel < 2)
      return;
   
   // Route through CJsonLogger for structured JSON with correlation ID
   if(CJsonLogger::IsEnabled() && m_component != "")
   {
      CJsonLogger::LogInfo(m_component, message, "NORMAL", CJsonLogger::GetCorrelationId(), "");
   }
   
   WriteToFile("[NORMAL] " + message);
}

// Log Verbose (level >= 3)
void CDiagnosticsLogger::LogVerbose(string message)
{
   if(m_logLevel < 3)
      return;
   
   // Route through CJsonLogger for structured JSON with correlation ID
   if(CJsonLogger::IsEnabled() && m_component != "")
   {
      CJsonLogger::LogDebug(m_component, message, "VERBOSE", CJsonLogger::GetCorrelationId(), "");
   }
   
   WriteToFile("[VERBOSE] " + message);
}

// Write to file (not journal)
// Falls back to Print if file handle is invalid
void CDiagnosticsLogger::WriteToFile(string message)
{
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   string fullMessage = "[" + timestamp + "] " + message;

   if(m_fileHandle != INVALID_HANDLE)
   {
      // Check rotation before writing
      RotateIfNeeded();
      
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileSeek(m_fileHandle, 0, SEEK_END);
         FileWriteString(m_fileHandle, fullMessage + "\r\n");
         Flush();
         m_lineCount++;
         m_fileSizeBytes = (long)FileSize(m_fileHandle);
      }
   }
   else
   {
      // Fallback to journal when file is unavailable
      Print(fullMessage);
   }
}

// Flush buffer to disk (throttled to every m_flushIntervalSec)
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

// Get base file name without rotation suffix
string CDiagnosticsLogger::GetBaseFileName() const
{
   if(m_filePath == "") return "";
   int lastDot = StringFind(m_filePath, ".log");
   if(lastDot < 0) return m_filePath;
   return StringSubstr(m_filePath, 0, lastDot + 4);
}

string CDiagnosticsLogger::GetRotatedFileName(int rotationIndex) const
{
   string base = GetBaseFileName();
   if(base == "") return "";
   string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
   StringReplace(dateStr, ".", "_");
   return base + "_" + dateStr + "_" + IntegerToString(rotationIndex) + ".log";
}

// Rotate log file if needed
void CDiagnosticsLogger::RotateIfNeeded()
{
   if(!m_enabled || m_fileHandle == INVALID_HANDLE)
      return;
   
   bool needRotate = false;
   
   if(m_lineCount >= MAX_LINES_PER_FILE)
      needRotate = true;
   
   if(m_fileSizeBytes >= MAX_FILE_SIZE_BYTES)
      needRotate = true;
   
   datetime now = TimeCurrent();
   if(m_fileCreationTime > 0 && (now - m_fileCreationTime) >= (MAX_FILE_AGE_DAYS * 86400))
      needRotate = true;
   
   if(needRotate)
   {
      // Find next rotation index
      int rotationIdx = 1;
      while(rotationIdx <= MAX_RETAINED_FILES)
      {
         string rotatedName = GetRotatedFileName(rotationIdx);
         int handle = FileOpen(rotatedName, FILE_READ | FILE_COMMON);
         if(handle == INVALID_HANDLE)
            break;
         FileClose(handle);
         rotationIdx++;
      }
      
      // Close current file
      FileClose(m_fileHandle);
      
      // Rename current to rotated
      string currentName = m_filePath;
      string rotatedName = GetRotatedFileName(rotationIdx);
      FileMove(currentName, FILE_COMMON, rotatedName, FILE_COMMON);
      
      // Reopen with fresh file
      m_fileHandle = FileOpen(m_filePath,
                              FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileSeek(m_fileHandle, 0, SEEK_END);
         m_lineCount = 0;
         m_fileSizeBytes = 0;
         m_fileCreationTime = TimeCurrent();
         WriteToFile("=== Diagnostics Logger Rotated ===");
      }
      else
      {
         m_enabled = false;
         Print("[DIAG-LOGGER] ERROR: Failed to reopen log file after rotation");
      }
      
      CleanupOldFiles();
   }
}

// Clean up old rotated files
void CDiagnosticsLogger::CleanupOldFiles()
{
   for(int i = MAX_RETAINED_FILES + 1; i <= MAX_RETAINED_FILES + 10; i++)
   {
      string rotatedName = GetRotatedFileName(i);
      int handle = FileOpen(rotatedName, FILE_READ | FILE_COMMON);
      if(handle == INVALID_HANDLE)
         break;
      FileClose(handle);
      FileDelete(rotatedName);
   }
}

#endif // DIAGNOSTICS_LOGGER_MQH

// ErrorAggregator.mqh - Periodic Error Aggregate Logging
// Aggregates errors by type and logs summary periodically
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
        
            // Route through CJsonLogger for structured JSON output (L9-011)
            CJsonLogger::LogError("ERROR-AGGREGATOR", summary, "ERROR_AGGREGATE", CJsonLogger::GetCorrelationId(), "");
        
            // Also log to DiagnosticsLogger for backwards compatibility
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