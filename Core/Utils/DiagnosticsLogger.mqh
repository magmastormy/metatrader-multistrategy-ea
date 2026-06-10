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

   bool Initialize(string eaName, int logLevel);
   void Deinit();

   // Level-gated logging
   void LogCritical(string message);
   void LogNormal(string message);
   void LogVerbose(string message);

   // Write to file (not journal)
   void WriteToFile(string message);

   // Flush buffer to disk
   void Flush();

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
bool CDiagnosticsLogger::Initialize(string eaName, int logLevel)
{
   m_logLevel = MathMax(0, MathMin(4, logLevel));
   m_filePath = eaName + "_diagnostics.log";

   m_fileHandle = FileOpen(m_filePath,
                           FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(m_fileHandle != INVALID_HANDLE)
   {
      FileSeek(m_fileHandle, 0, SEEK_END);
      m_enabled = true;
      WriteToFile("=== Diagnostics Logger Initialized | Level=" + IntegerToString(m_logLevel) + " ===");
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
