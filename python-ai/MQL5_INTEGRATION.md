# MQL5 Integration Guide for Python AI Module

This guide demonstrates how to integrate the Python AI module with your MQL5 Expert Advisor using standard TCP Sockets.

## Prerequisites

1.  **Python Environment**: Ensure the Python AI module is running (`python main.py --bridge socket`).
2.  **Allow WebRequest**: In MetaTrader 5, go to `Tools -> Options -> Expert Advisors` and check "Allow WebRequest for listed URL". Add `http://localhost` (though we are using raw sockets, this is sometimes required for network permissions).

## MQL5 Code Snippet

Add this class to your EA to handle communication with the Python module.

```cpp
//+------------------------------------------------------------------+
//|                                              PythonBridge.mqh    |
//|                                                                  |
//+------------------------------------------------------------------+
#property strict

#include <ErrDescription.mqh>

class CPythonBridge
{
private:
   string            m_host;
   int               m_port;
   int               m_socket;
   bool              m_connected;

public:
                     CPythonBridge(string host="127.0.0.1", int port=8888);
                    ~CPythonBridge();

   bool              Connect();
   void              Disconnect();
   bool              Handshake();
   bool              Heartbeat();
   string            SendRequest(string type, string data_json);
   string            GetPrediction(string symbol, const MqlRates &rates[], int count);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPythonBridge::CPythonBridge(string host, int port)
   : m_host(host), m_port(port), m_socket(INVALID_HANDLE), m_connected(false)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPythonBridge::~CPythonBridge()
{
   Disconnect();
}

//+------------------------------------------------------------------+
//| Connect to Python Server                                         |
//+------------------------------------------------------------------+
bool CPythonBridge::Connect()
{
   if(m_connected) return true;

   m_socket = SocketCreate();
   if(m_socket == INVALID_HANDLE)
   {
      Print("Failed to create socket: ", ErrorDescription(GetLastError()));
      return false;
   }

   if(!SocketConnect(m_socket, m_host, m_port, 1000))
   {
      Print("Failed to connect to Python server: ", ErrorDescription(GetLastError()));
      SocketClose(m_socket);
      m_socket = INVALID_HANDLE;
      return false;
   }

   m_connected = true;
   return true;
}

//+------------------------------------------------------------------+
//| Disconnect from Python Server                                    |
//+------------------------------------------------------------------+
void CPythonBridge::Disconnect()
{
   if(m_socket != INVALID_HANDLE)
   {
      SocketClose(m_socket);
      m_socket = INVALID_HANDLE;
   }
   m_connected = false;
}

//+------------------------------------------------------------------+
//| Send Request and Get Response                                    |
//+------------------------------------------------------------------+
string CPythonBridge::SendRequest(string type, string data_json)
{
   // Note: The current Python SocketServer implementation closes connection after each request.
   // So we need to reconnect for each request if using that bridge.
   // For persistent connections, use ZMQ or modify SocketServer.
   
   if(!Connect()) return "";

   string request = StringFormat("{\"type\":\"%s\",\"data\":%s}", type, data_json);
   char req_data[];
   StringToCharArray(request, req_data);
   
   if(SocketSend(m_socket, req_data, ArraySize(req_data)-1) < 0)
   {
      Print("Failed to send data: ", ErrorDescription(GetLastError()));
      Disconnect();
      return "";
   }

   char rsp_data[];
   string response = "";
   int timeout = 5000;
   uint start = GetTickCount();
   
   while(GetTickCount() - start < timeout)
   {
      if(SocketIsReadable(m_socket))
      {
         int len = SocketRead(m_socket, rsp_data, 4096, 100);
         if(len > 0)
         {
            response += CharArrayToString(rsp_data, 0, len);
            // Check if full JSON received (simple check)
            if(StringFind(response, "}") > 0) break; 
         }
         else
         {
            break; 
         }
      }
      Sleep(10);
   }

   Disconnect(); // Close after request as per current server implementation
   return response;
}

//+------------------------------------------------------------------+
//| Perform Handshake                                                |
//+------------------------------------------------------------------+
bool CPythonBridge::Handshake()
{
   string response = SendRequest("handshake", "{\"version\":\"MQL5-1.0\"}");
   Print("Handshake Response: ", response);
   return (StringFind(response, "\"status\": \"ready\"") > 0);
}

//+------------------------------------------------------------------+
//| Get Prediction                                                   |
//+------------------------------------------------------------------+
string CPythonBridge::GetPrediction(string symbol, const MqlRates &rates[], int count)
{
   string market_data = "{";
   market_data += "\"symbol\":\"" + symbol + "\",";
   market_data += "\"close\":[";
   
   for(int i=0; i<count; i++)
   {
      market_data += DoubleToString(rates[i].close, 5);
      if(i < count-1) market_data += ",";
   }
   market_data += "]}";
   
   return SendRequest("signal_request", "{\"symbol\":\"" + symbol + "\",\"market_data\":" + market_data + "}");
}
```

## Usage in EA

```cpp
CPythonBridge *bridge;

int OnInit()
{
   bridge = new CPythonBridge("127.0.0.1", 8888);
   if(!bridge.Handshake())
   {
      Print("Failed to handshake with Python AI");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
   MqlRates rates[];
   CopyRates(_Symbol, PERIOD_CURRENT, 0, 100, rates);
   
   string prediction = bridge.GetPrediction(_Symbol, rates, 100);
   Print("AI Prediction: ", prediction);
}

void OnDeinit(const int reason)
{
   delete bridge;
}
```
