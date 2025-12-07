//+------------------------------------------------------------------+
//| Utilities Module                                                   |
//+------------------------------------------------------------------+
#ifndef __UTILITIES_MQH__
#define __UTILITIES_MQH__

// Include error handling utilities at global scope to avoid nesting within classes
#include "../Core/Utils/ErrorHandling.mqh"

// Pointer validation macros
#ifndef POINTER_VALID
#define POINTER_VALID(ptr) (CheckPointer(ptr) != POINTER_INVALID)
#endif

// Note: POINTER_DYNAMIC is a built-in MQL5 constant (ENUM_POINTER_TYPE)
// No need to redefine it

// Define error code constants
#define ERR_NO_ERROR 0
#define ERR_NO_RESULT 1
#define ERR_COMMON_ERROR 2
#define ERR_INVALID_TRADE_PARAMETERS 3
#define ERR_SERVER_BUSY 4
#define ERR_OLD_VERSION 5
#define ERR_NO_CONNECTION 6
#define ERR_NOT_ENOUGH_RIGHTS 7
#define ERR_TOO_FREQUENT_REQUESTS 8
#define ERR_MALFUNCTIONAL_TRADE 9
#define ERR_ACCOUNT_DISABLED 64
#define ERR_INVALID_ACCOUNT 65
#define ERR_TRADE_TIMEOUT 128
#define ERR_INVALID_PRICE 129
#define ERR_INVALID_STOPS 130
#define ERR_INVALID_TRADE_VOLUME 131
#define ERR_MARKET_CLOSED 132
// ERR_TRADE_DISABLED already defined in MQL5
#define ERR_NOT_ENOUGH_MONEY 134
#define ERR_PRICE_CHANGED 135
#define ERR_OFF_QUOTES 136
#define ERR_BROKER_BUSY 137
#define ERR_REQUOTE 138
#define ERR_ORDER_LOCKED 139
#define ERR_LONG_POSITIONS_ONLY_ALLOWED 140
#define ERR_TOO_MANY_REQUESTS 141

class CUtilities {
private:
    // Private members
    datetime lastAlert;
    datetime m_lastAlert;
    bool m_enableAlerts;
    bool m_enableEmailAlerts;
    bool m_enablePushNotifications;
    string m_botName;
    
    // Log levels
    enum ENUM_LOG_LEVEL {
        LOG_ERROR,
        LOG_WARNING,
        LOG_INFO,
        LOG_DEBUG
    };
    
    // Helper function to get timestamp
    string GetTimestamp() {
        return TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
    }
    
    // Internal logging function
    void LogMessage(ENUM_LOG_LEVEL level, const string &component, const string &message) {
        string levelStr;
        switch(level) {
            case LOG_ERROR:   levelStr = "ERROR"; break;
            case LOG_WARNING: levelStr = "WARNING"; break;
            case LOG_INFO:    levelStr = "INFO"; break;
            case LOG_DEBUG:   levelStr = "DEBUG"; break;
            default:          levelStr = "UNKNOWN";
        }
        
        string logMsg = StringFormat("[%s][%s][%s] %s", 
                                   GetTimestamp(), levelStr, component, message);
        Print(logMsg);
        
        // For errors and warnings, also write to separate log file
        if(level <= LOG_WARNING) {
            int handle = FileOpen(m_botName + "_errors.log", FILE_WRITE|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_TXT);
            if(handle != INVALID_HANDLE) {
                FileSeek(handle, 0, SEEK_END);
                FileWriteString(handle, logMsg + "\n");
                FileClose(handle);
            }
        }
    }
    
public:
    CUtilities():
        m_lastAlert(0),
        m_enableAlerts(true),
        m_enableEmailAlerts(false),
        m_enablePushNotifications(false),
        m_botName("MultiStrategyEA")
    {
    }
    
    void Initialize(bool enableAlerts, bool enableEmail, bool enablePush, string botName) {
        m_enableAlerts = enableAlerts;
        m_enableEmailAlerts = enableEmail;
        m_enablePushNotifications = enablePush;
        m_botName = botName;
    }
    
    // Error handling and logging
    void LogError(const string &component, const string &message, int errorCode = 0) {
        string errorMsg = message;
        if(errorCode != 0) {
            errorMsg += " Error code: " + IntegerToString(errorCode);
        }
        LogMessage(LOG_ERROR, component, errorMsg);
    }
    
    void LogWarning(const string &component, const string &message) {
        LogMessage(LOG_WARNING, component, message);
    }
    
    void LogInfo(const string &component, const string &message) {
        LogMessage(LOG_INFO, component, message);
    }
    
    void LogDebug(const string &component, const string &message) {
        LogMessage(LOG_DEBUG, component, message);
    }
    
    // Alert functions with rate limiting
    void AlertIfNeeded(const string &msg) {
        if(!m_enableAlerts) return;
        
        datetime now = TimeCurrent();
        if(now - m_lastAlert > 60) { // Rate limit: one alert per minute
            Alert(m_botName + ": " + msg);
            m_lastAlert = now;
        }
    }
    
    void NotifyPush(const string &msg) {
        if(!m_enablePushNotifications) return;
        
        datetime now = TimeCurrent();
        if(now - m_lastAlert > 60) { // Rate limit: one notification per minute
            SendNotification(m_botName + ": " + msg);
            m_lastAlert = now;
        }
    }
    
    void NotifyEmail(const string &subject, const string &body) {
        if(!m_enableEmailAlerts) return;
        
        datetime now = TimeCurrent();
        if(now - m_lastAlert > 60) { // Rate limit: one email per minute
            SendMail(m_botName + ": " + subject, body);
            m_lastAlert = now;
        }
    }
    
    // String manipulation utilities
    string StringTrim(string str) {
        StringTrimLeft(str);
        StringTrimRight(str);
        return str;
    }
    
    // Array utilities
    
    // File utilities
    bool IsFileValid(const string fileName) {
        if(!FileIsExist(fileName)) {
            string message = "File does not exist: " + fileName;
            LogWarning("FileCheck", message);
            return false;
        }
        return true;
    }
    
    // Performance monitoring
    class CPerformanceTimer {
    private:
        uint m_startTime;
        string m_operation;
        
    public:
        CPerformanceTimer(const string &operation): m_operation(operation) {
            m_startTime = GetTickCount();
        }
        
        ~CPerformanceTimer() {
            uint duration = GetTickCount() - m_startTime;
            if(duration > 100) { // Only log if operation took more than 100ms
                Print("[PERFORMANCE] ", m_operation, " took ", duration, " ms");
            }
        }
    };
};

// Moved to global scope to satisfy MQL5 restrictions on templates inside classes
template<typename T>
void ArrayPrint(const T &arr[], const string name = "") {
    string output = name + " Array contents:\n";
    for(int i = 0; i < ArraySize(arr); i++) {
        output += StringFormat("[%d] = %s\n", i, (string)arr[i]);
    }
    Print(output);
}

#endif

