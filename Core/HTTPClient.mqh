//+------------------------------------------------------------------+
//| HTTP Client for Python AI Server Communication                   |
//| Production-ready REST API client with fault tolerance            |
//+------------------------------------------------------------------+
#ifndef HTTP_CLIENT_MQH
#define HTTP_CLIENT_MQH

#include <Arrays\ArrayString.mqh>

//+------------------------------------------------------------------+
//| HTTP Response Structure                                          |
//+------------------------------------------------------------------+
struct SHTTPResponse
{
    int statusCode;            // HTTP status code
    string body;               // Response body
    bool success;              // Request succeeded
    string error;              // Error message
    double responseTimeMs;     // Response time in milliseconds
    
    SHTTPResponse() : statusCode(0), body(""), success(false), error(""), responseTimeMs(0.0) {}
};

//+------------------------------------------------------------------+
//| HTTP Client Class                                                |
//+------------------------------------------------------------------+
class CHTTPClient
{
private:
    string m_baseUrl;
    int m_timeout;
    int m_retryCount;
    int m_retryDelayMs;
    
    // Statistics
    int m_totalRequests;
    int m_successfulRequests;
    int m_failedRequests;
    
public:
    CHTTPClient(string baseUrl = "http://localhost:8000", int timeout = 5000);
    ~CHTTPClient();
    
    // Main methods
    bool POST(string endpoint, string jsonBody, SHTTPResponse &response);
    bool GET(string endpoint, SHTTPResponse &response);
    
    // Configuration
    void SetTimeout(int timeoutMs) { m_timeout = timeoutMs; }
    void SetRetryCount(int count) { m_retryCount = count; }
    void SetBaseUrl(string url) { m_baseUrl = url; }
    
    // Statistics
    int GetTotalRequests() const { return m_totalRequests; }
    int GetSuccessRate() const { return m_totalRequests > 0 ? (m_successfulRequests * 100 / m_totalRequests) : 0; }
    
private:
    bool ExecuteRequest(string method, string endpoint, string body, SHTTPResponse &response);
    string UrlEncode(string str);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CHTTPClient::CHTTPClient(string baseUrl, int timeout) :
    m_baseUrl(baseUrl),
    m_timeout(timeout),
    m_retryCount(2),
    m_retryDelayMs(100),
    m_totalRequests(0),
    m_successfulRequests(0),
    m_failedRequests(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CHTTPClient::~CHTTPClient()
{
}

//+------------------------------------------------------------------+
//| POST Request                                                      |
//+------------------------------------------------------------------+
bool CHTTPClient::POST(string endpoint, string jsonBody, SHTTPResponse &response)
{
    return ExecuteRequest("POST", endpoint, jsonBody, response);
}

//+------------------------------------------------------------------+
//| GET Request                                                       |
//+------------------------------------------------------------------+
bool CHTTPClient::GET(string endpoint, SHTTPResponse &response)
{
    return ExecuteRequest("GET", endpoint, "", response);
}

//+------------------------------------------------------------------+
//| Execute HTTP Request with Retry Logic                            |
//+------------------------------------------------------------------+
bool CHTTPClient::ExecuteRequest(string method, string endpoint, string body, SHTTPResponse &response)
{
    m_totalRequests++;
    datetime reqStartTime = GetTickCount();
    
    // Build full URL
    string fullUrl = m_baseUrl + endpoint;
    
    // MQL5 HTTP request parameters
    string headers = "Content-Type: application/json\r\n";
    char postData[];
    char resultData[];
    string resultHeaders;
    
    // Convert body to char array
    if(body != "")
        StringToCharArray(body, postData, 0, StringLen(body));
    
    // Retry logic
    for(int attempt = 0; attempt <= m_retryCount; attempt++)
    {
        if(attempt > 0)
        {
            Print("[HTTP-CLIENT] Retry attempt ", attempt, " for ", endpoint);
            Sleep(m_retryDelayMs * attempt);  // Exponential backoff
        }
        
        // Reset result array
        ArrayResize(resultData, 0);
        
        // Execute WebRequest
        int statusCode = WebRequest(
            method,
            fullUrl,
            headers,
            m_timeout,
            postData,
            resultData,
            resultHeaders
        );
        
        // Calculate response time
        response.responseTimeMs = (double)(GetTickCount() - reqStartTime);
        
        // Check for success
        if(statusCode >= 200 && statusCode < 300)
        {
            response.statusCode = statusCode;
            response.success = true;
            response.body = CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8);
            response.error = "";
            m_successfulRequests++;
            
            return true;
        }
        else if(statusCode == -1)
        {
            // Network error - worth retrying
            int errorCode = GetLastError();
            response.error = StringFormat("Network error: %d (GetLastError: %d)", statusCode, errorCode);
            PrintFormat("[HTTP-CLIENT] Network error on attempt %d: %s", attempt + 1, response.error);
            continue;  // Retry
        }
        else
        {
            // HTTP error (4xx, 5xx) - may not be worth retrying
            response.statusCode = statusCode;
            response.success = false;
            response.body = CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8);
            response.error = StringFormat("HTTP error %d", statusCode);
            
            if(statusCode >= 500)
            {
                // Server error - worth retrying
                PrintFormat("[HTTP-CLIENT] Server error %d on attempt %d, retrying...", statusCode, attempt + 1);
                continue;
            }
            else
            {
                // Client error (4xx) - don't retry
                break;
            }
        }
    }
    
    // All retries failed
    m_failedRequests++;
    response.success = false;
    
    if(response.error == "")
        response.error = StringFormat("Request failed after %d attempts", m_retryCount + 1);
    
    PrintFormat("[HTTP-CLIENT] Request failed: %s", response.error);
    return false;
}

//+------------------------------------------------------------------+
//| URL Encode                                                        |
//+------------------------------------------------------------------+
string CHTTPClient::UrlEncode(string str)
{
    string result = "";
    int len = StringLen(str);
    
    for(int i = 0; i < len; i++)
    {
        ushort ch = StringGetCharacter(str, i);
        
        if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || 
           (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || 
           ch == '.' || ch == '~')
        {
            result += ShortToString(ch);
        }
        else
        {
            result += StringFormat("%%%02X", ch);
        }
    }
    
    return result;
}

#endif // HTTP_CLIENT_MQH
