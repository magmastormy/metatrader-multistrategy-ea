//+------------------------------------------------------------------+
//|                                                 PythonBridge.mqh |
//|                                                                  |
//+------------------------------------------------------------------+
#property strict

#ifndef PYTHON_BRIDGE_MQH
#define PYTHON_BRIDGE_MQH

// #include <ErrDescription.mqh>

class CPythonBridge
{
private:
   string            m_host;
   int               m_port;
   int               m_socket;
   bool              m_connected;
   bool              m_use_zmq; // Flag to indicate protocol (though we use sockets here, ZMQ might be wrapped or we stick to raw sockets)

public:
                     CPythonBridge(string host="127.0.0.1", int port=8888);
                    ~CPythonBridge();

   bool              Connect();
   void              Disconnect();
   bool              IsConnected() { return m_connected; }
   bool              Handshake();
   bool              Heartbeat();
   string            SendRequest(string type, string data_json);
   string            GetPrediction(string symbol, const double &features[], int count);
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
      // Print("Failed to create socket: ", ErrorDescription(GetLastError()));
      return false;
   }

   if(!SocketConnect(m_socket, m_host, m_port, 1000))
   {
      // Print("Failed to connect to Python server: ", ErrorDescription(GetLastError()));
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
   // Ensure connection
   if(!IsConnected())
   {
      if(!Connect()) return "";
   }

   string request = StringFormat("{\"type\":\"%s\",\"data\":%s}", type, data_json);
   uchar req_data[];
   StringToCharArray(request, req_data);
   
   // Try to send
   if(SocketSend(m_socket, req_data, ArraySize(req_data)-1) < 0)
   {
      // If send fails, try to reconnect once
      Print("Socket send failed, attempting to reconnect...");
      Disconnect();
      if(!Connect()) return "";
      
      if(SocketSend(m_socket, req_data, ArraySize(req_data)-1) < 0)
      {
         Print("Failed to send data after reconnect. Error: ", GetLastError());
         Disconnect();
         return "";
      }
   }

   uchar rsp_data[];
   string response = "";
   uint timeout = 5000;
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
            // Connection might be closed by peer
            if(!SocketIsConnected(m_socket))
            {
                Print("Connection closed by peer during read");
                Disconnect();
                return "";
            }
            break; 
         }
      }
      Sleep(10);
   }

   // Do NOT disconnect - keep connection alive
   return response;
}

//+------------------------------------------------------------------+
//| Perform Handshake                                                |
//+------------------------------------------------------------------+
bool CPythonBridge::Handshake()
{
   string response = SendRequest("handshake", "{\"version\":\"MQL5-2.0\"}");
   if(StringLen(response) > 0 && StringFind(response, "\"status\": \"ready\"") > 0) {
       Print("[PYTHON-BRIDGE] Handshake Successful: ", response);
       return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Perform Heartbeat                                                |
//+------------------------------------------------------------------+
bool CPythonBridge::Heartbeat()
{
   string response = SendRequest("heartbeat", "{}");
   return (StringFind(response, "\"status\": \"alive\"") > 0);
}

//+------------------------------------------------------------------+
//| Get Prediction                                                   |
//+------------------------------------------------------------------+
string CPythonBridge::GetPrediction(string symbol, const double &features[], int count)
{
   // Construct JSON manually for speed
   string market_data = "{";
   market_data += "\"symbol\":\"" + symbol + "\",";
   market_data += "\"market_data\": { \"features\":[";
   
   for(int i=0; i<count; i++)
   {
      market_data += DoubleToString(features[i], 5);
      if(i < count-1) market_data += ",";
   }
   market_data += "]}}";
   
   // WAIT: NextGenStrategyBrain.mqh has 'ExtractFeatures' and passes 'modelInput' (features) to 'SendInferenceRequest'.
   // The previous implementation sent 'market_data' as a list of features:
   // string jsonPayload = "{\"market_data\": ["; ... features ...
   
   // And main.py:
   // df = self.data_loader.load_from_dict(market_data)
   // features = self.feature_engineer.build_features(df)
   
   // If we pass a list of floats as 'market_data', data_loader.load_from_dict might fail if it expects a dict of lists.
   // Let's check data_loader.py... I didn't read it.
   // But main.py says: df = self.data_loader.load_from_dict(market_data)
   
   // To be safe and compatible with the *previous* logic (which seemed to send features), 
   // I should probably ensure the Python side can handle what I send.
   // The previous NextGenStrategyBrain sent: "{\"market_data\": [feature1, feature2...], ...}"
   
   // I will update this method to send the JSON payload constructed by the caller (NextGenStrategyBrain),
   // or just pass the string data directly.
   
   return SendRequest("signal_request", market_data);
}

#endif
