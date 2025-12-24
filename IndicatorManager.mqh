//+------------------------------------------------------------------+
//| Indicator Manager - Centralized indicator handle management       |
//+------------------------------------------------------------------+
#property strict

#ifndef __INDICATOR_MANAGER_MQH__
#define __INDICATOR_MANAGER_MQH__

#include <Object.mqh>
#include <Indicators\Indicator.mqh>

// Define indicator types for easier reference
enum ENUM_INDICATOR_TYPE
{
   INDICATOR_RSI,        // Relative Strength Index
   INDICATOR_MA,         // Moving Average
   INDICATOR_MACD,       // MACD
   INDICATOR_ATR,        // Average True Range
   INDICATOR_BB,         // Bollinger Bands
   INDICATOR_STOCH,      // Stochastic
   INDICATOR_ICHIMOKU,   // Ichimoku Cloud
   INDICATOR_ADX,        // ADX
   INDICATOR_CUSTOM      // Custom indicator
};

//+------------------------------------------------------------------+
//| Indicator Manager - Singleton Pattern                             |
//+------------------------------------------------------------------+
class CIndicatorManager
{
private:
   // Singleton instance
   static CIndicatorManager *m_instance;
   
   // Structure to hold indicator handle information
   struct IndicatorHandle
   {
      int            handle;        // Indicator handle
      datetime       lastAccess;    // Last time this handle was accessed
      string         symbol;        // Symbol
      ENUM_TIMEFRAMES timeframe;    // Timeframe
      ENUM_INDICATOR_TYPE type;     // Indicator type
      int            parameters[5]; // Store common parameters
   };
   
   IndicatorHandle   m_handles[];   // Array of handles
   
                     CIndicatorManager() {}; // Private constructor
                     ~CIndicatorManager();  // Destructor
   
public:
   static CIndicatorManager *Instance();
   
   // Get a handle for an indicator, creating it if needed
   int               GetRSIHandle(string symbol, ENUM_TIMEFRAMES tf, int period, ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE);
   int               GetMAHandle(string symbol, ENUM_TIMEFRAMES tf, int period, int ma_shift, ENUM_MA_METHOD ma_method, ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE);
   int               GetATRHandle(string symbol, ENUM_TIMEFRAMES tf, int period);
   int               GetMACDHandle(string symbol, ENUM_TIMEFRAMES tf, int fast_ema_period, int slow_ema_period, int signal_period, ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE);
   
   // General method to access a handle
   int               GetHandle(ENUM_INDICATOR_TYPE type, string symbol, ENUM_TIMEFRAMES tf, const int &params[]);
   
   // Mark a handle as accessed
   void              AccessHandle(int handle);
   
   // Release handles that haven't been accessed for a while
   void              ReleaseUnused(int maxAge = 300); // 5 minutes
   
   // Release all handles for cleanup
   void              ReleaseAll();
   
   // Find an existing handle
   int               FindHandle(ENUM_INDICATOR_TYPE type, string symbol, ENUM_TIMEFRAMES tf, const int &params[]);
};

// Initialize static instance pointer
CIndicatorManager *CIndicatorManager::m_instance = NULL;

//+------------------------------------------------------------------+
//| Get the singleton instance                                        |
//+------------------------------------------------------------------+
CIndicatorManager *CIndicatorManager::Instance()
{
   if(m_instance == NULL)
      m_instance = new CIndicatorManager();
      
   return m_instance;
}

//+------------------------------------------------------------------+
//| Find an existing handle                                           |
//+------------------------------------------------------------------+
int CIndicatorManager::FindHandle(ENUM_INDICATOR_TYPE type, string symbol, ENUM_TIMEFRAMES tf, const int &params[])
{
   for(int i = 0; i < ArraySize(m_handles); i++)
   {
      if(m_handles[i].type == type &&
         m_handles[i].symbol == symbol &&
         m_handles[i].timeframe == tf)
      {
         // Compare parameters if needed
         bool paramsMatch = true;
         // Add parameter comparison logic here if needed
         
         if(paramsMatch)
            return m_handles[i].handle;
      }
   }
   return INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Release all indicator handles                                    |
//+------------------------------------------------------------------+
void CIndicatorManager::ReleaseAll()
{
   for(int i = ArraySize(m_handles) - 1; i >= 0; i--)
   {
      if(m_handles[i].handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_handles[i].handle);
      }
   }
   ArrayFree(m_handles);
}

//+------------------------------------------------------------------+
//| Release unused handles                                           |
//+------------------------------------------------------------------+
void CIndicatorManager::ReleaseUnused(int maxAge)
{
   datetime now = TimeCurrent();
   for(int i = ArraySize(m_handles) - 1; i >= 0; i--)
   {
      if(now - m_handles[i].lastAccess > maxAge)
      {
         if(m_handles[i].handle != INVALID_HANDLE)
         {
            IndicatorRelease(m_handles[i].handle);
         }
         ArrayRemove(m_handles, i, 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Mark a handle as accessed                                        |
//+------------------------------------------------------------------+
void CIndicatorManager::AccessHandle(int handle)
{
   for(int i = 0; i < ArraySize(m_handles); i++)
   {
      if(m_handles[i].handle == handle)
      {
         m_handles[i].lastAccess = TimeCurrent();
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Get RSI handle                                                  |
//+------------------------------------------------------------------+
int CIndicatorManager::GetRSIHandle(string symbol, ENUM_TIMEFRAMES tf, int period, ENUM_APPLIED_PRICE applied_price)
{
   int params[5] = {period, applied_price};
   int handle = FindHandle(INDICATOR_RSI, symbol, tf, params);
   
   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }
   
   // Create new handle if not found
   handle = iRSI(symbol, tf, period, applied_price);
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_RSI;
      m_handles[size].parameters[0] = period;
      m_handles[size].parameters[1] = (int)applied_price;
   }
   
   return handle;
}

//+------------------------------------------------------------------+
//| Get Moving Average handle                                        |
//+------------------------------------------------------------------+
int CIndicatorManager::GetMAHandle(string symbol, ENUM_TIMEFRAMES tf, int period, int ma_shift, ENUM_MA_METHOD ma_method, ENUM_APPLIED_PRICE applied_price)
{
   int params[5] = {period, ma_shift, ma_method, applied_price};
   int handle = FindHandle(INDICATOR_MA, symbol, tf, params);
   
   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }
   
   // Create new handle if not found
   handle = iMA(symbol, tf, period, ma_shift, ma_method, applied_price);
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_MA;
      m_handles[size].parameters[0] = period;
      m_handles[size].parameters[1] = ma_shift;
      m_handles[size].parameters[2] = (int)ma_method;
      m_handles[size].parameters[3] = (int)applied_price;
   }
   
   return handle;
}

//+------------------------------------------------------------------+
//| Get ATR handle                                                   |
//+------------------------------------------------------------------+
int CIndicatorManager::GetATRHandle(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   int params[5] = {period};
   int handle = FindHandle(INDICATOR_ATR, symbol, tf, params);
   
   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }
   
   // Create new handle if not found
   handle = iATR(symbol, tf, period);
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_ATR;
      m_handles[size].parameters[0] = period;
   }
   
   return handle;
}

//+------------------------------------------------------------------+
//| Get MACD handle                                                  |
//+------------------------------------------------------------------+
int CIndicatorManager::GetMACDHandle(string symbol, ENUM_TIMEFRAMES tf, int fast_ema_period, int slow_ema_period, int signal_period, ENUM_APPLIED_PRICE applied_price)
{
   int params[5] = {fast_ema_period, slow_ema_period, signal_period, applied_price};
   int handle = FindHandle(INDICATOR_MACD, symbol, tf, params);
   
   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }
   
   // Create new handle if not found
   handle = iMACD(symbol, tf, fast_ema_period, slow_ema_period, signal_period, applied_price);
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_MACD;
      m_handles[size].parameters[0] = fast_ema_period;
      m_handles[size].parameters[1] = slow_ema_period;
      m_handles[size].parameters[2] = signal_period;
      m_handles[size].parameters[3] = (int)applied_price;
   }
   
   return handle;
}

//+------------------------------------------------------------------+
//| General method to get a handle                                   |
//+------------------------------------------------------------------+
int CIndicatorManager::GetHandle(ENUM_INDICATOR_TYPE type, string symbol, ENUM_TIMEFRAMES tf, const int &params[])
{
   switch(type)
   {
      case INDICATOR_RSI:
         if(ArraySize(params) >= 2)
            return GetRSIHandle(symbol, tf, params[0], (ENUM_APPLIED_PRICE)params[1]);
         break;
         
      case INDICATOR_MA:
         if(ArraySize(params) >= 4)
            return GetMAHandle(symbol, tf, params[0], params[1], (ENUM_MA_METHOD)params[2], (ENUM_APPLIED_PRICE)params[3]);
         break;
         
      case INDICATOR_ATR:
         if(ArraySize(params) >= 1)
            return GetATRHandle(symbol, tf, params[0]);
         break;
         
      case INDICATOR_MACD:
         if(ArraySize(params) >= 4)
            return GetMACDHandle(symbol, tf, params[0], params[1], params[2], (ENUM_APPLIED_PRICE)params[3]);
         break;
         
      // Add other indicator types as needed
   }
   
   return INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CIndicatorManager::~CIndicatorManager()
{
   ReleaseAll();
   if(CheckPointer(m_instance) == POINTER_DYNAMIC)
      delete m_instance;
   m_instance = NULL;
}

#endif // __INDICATOR_MANAGER_MQH__

