//+------------------------------------------------------------------+
//| Indicator Manager - Centralized indicator handle management       |
//+------------------------------------------------------------------+
#property strict

#ifndef INDICATOR_MANAGER_MQH
#define INDICATOR_MANAGER_MQH

#include <Object.mqh>
#include <Indicators\Indicator.mqh>

// Maximum number of indicator handles to prevent resource exhaustion
// Increased to 500 to support multi-symbol setups with multiple indicators per symbol
#define MAX_INDICATOR_HANDLES 500

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
   INDICATOR_CCI,        // CCI
   INDICATOR_VOLUMES,    // Volumes
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
      int            paramCount;    // Number of meaningful params
      int            parameters[5]; // Store common parameters
   };
   
   IndicatorHandle   m_handles[];   // Array of handles
   
                     CIndicatorManager() {}; // Private constructor
                     ~CIndicatorManager();  // Destructor
   
public:
   static CIndicatorManager *Instance();
   static void              DestroyInstance();
   
   // Get a handle for an indicator, creating it if needed
   int               GetRSIHandle(string symbol, ENUM_TIMEFRAMES tf, int period, ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE);
   int               GetMAHandle(string symbol, ENUM_TIMEFRAMES tf, int period, int ma_shift, ENUM_MA_METHOD ma_method, ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE);
   int               GetATRHandle(string symbol, ENUM_TIMEFRAMES tf, int period);
   int               GetMACDHandle(string symbol, ENUM_TIMEFRAMES tf, int fast_ema_period, int slow_ema_period, int signal_period, ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE);
   int               GetADXHandle(string symbol, ENUM_TIMEFRAMES tf, int period);
   int               GetBandsHandle(string symbol, ENUM_TIMEFRAMES tf, int period, int shift, double deviation, ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE);
   int               GetCCIHandle(string symbol, ENUM_TIMEFRAMES tf, int period, ENUM_APPLIED_PRICE applied_price = PRICE_CLOSE);
   int               GetVolumesHandle(string symbol, ENUM_TIMEFRAMES tf, ENUM_APPLIED_VOLUME applied_volume = VOLUME_TICK);
   int               GetStochasticHandle(string symbol, ENUM_TIMEFRAMES tf, int period_k, int period_d, int period_slow, ENUM_MA_METHOD ma_method, ENUM_STO_PRICE price_field);
   
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

   // Check if a symbol is available and has data
   bool              IsSymbolAvailable(string symbol, ENUM_TIMEFRAMES tf);
};

// Initialize static instance pointer
// NOTE: Singleton pattern is not thread-safe, but this is acceptable in MQL5's single-threaded context
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
//| Check if a symbol is available and has data                      |
//+------------------------------------------------------------------+
bool CIndicatorManager::IsSymbolAvailable(string symbol, ENUM_TIMEFRAMES tf)
{
   if(symbol == "")
      return false;

   // CRITICAL FIX: Resolve PERIOD_CURRENT (timeframe=0) to actual chart timeframe
   ENUM_TIMEFRAMES actualTimeframe = tf;
   if(tf == PERIOD_CURRENT || tf == 0)
   {
      actualTimeframe = Period();
      if(actualTimeframe == 0)
         actualTimeframe = PERIOD_M15; // Fallback to M15 if unable to resolve
   }

   // Validate timeframe parameter
   if(actualTimeframe < PERIOD_M1 || actualTimeframe > PERIOD_MN1)
   {
      PrintFormat("[INDICATOR-MANAGER] ERROR: Invalid timeframe %d (resolved from %d) for symbol %s", actualTimeframe, tf, symbol);
      return false;
   }

   // Check if symbol exists in Market Watch
   if(!SymbolInfoInteger(symbol, SYMBOL_VISIBLE))
   {
      if(!SymbolSelect(symbol, true))
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Symbol %s not available in Market Watch", symbol);
         return false;
      }
   }

   // Check if symbol has enough bars for the timeframe
   int bars = iBars(symbol, actualTimeframe);
   if(bars < 50)
   {
      PrintFormat("[INDICATOR-MANAGER] WARNING: Symbol %s %s has only %d bars (need at least 50)",
                  symbol, EnumToString(actualTimeframe), bars);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Destroy singleton instance explicitly                            |
//+------------------------------------------------------------------+
void CIndicatorManager::DestroyInstance()
{
   if(m_instance != NULL)
   {
      CIndicatorManager *instance = m_instance;
      m_instance = NULL;
      delete instance;
   }
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
         // AUDIT FIX: Actually compare indicator parameters to prevent returning wrong handle
         bool paramsMatch = true;
         // Use stored paramCount for comparison, not array size
         int paramCount = m_handles[i].paramCount;
         if(paramCount > ArraySize(params))
            paramsMatch = false;
         for(int p = 0; p < paramCount && paramsMatch; p++)
         {
            if(m_handles[i].parameters[p] != params[p])
            {
               paramsMatch = false;
            }
         }
         
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

   // Check symbol availability before creating indicator
   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   // Create new handle if not found
   handle = iRSI(symbol, tf, period, applied_price);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create RSI handle for %s %s period=%d err=%d",
                  symbol, EnumToString(tf), period, err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60); // Release handles not accessed in the last 60 seconds
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_RSI;
      m_handles[size].paramCount = 2;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = period;
      m_handles[size].parameters[1] = (int)applied_price;
      PrintFormat("[INDICATOR-MANAGER] Created RSI handle=%d for %s %s period=%d",
                  handle, symbol, EnumToString(tf), period);
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

   // Check symbol availability before creating indicator
   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   // Create new handle if not found
   handle = iMA(symbol, tf, period, ma_shift, ma_method, applied_price);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create MA handle for %s %s period=%d err=%d",
                  symbol, EnumToString(tf), period, err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60); // Release handles not accessed in the last 60 seconds
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_MA;
      m_handles[size].paramCount = 4;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = period;
      m_handles[size].parameters[1] = ma_shift;
      m_handles[size].parameters[2] = (int)ma_method;
      m_handles[size].parameters[3] = (int)applied_price;
      PrintFormat("[INDICATOR-MANAGER] Created MA handle=%d for %s %s period=%d",
                  handle, symbol, EnumToString(tf), period);
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

   // Check symbol availability before creating indicator
   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   // Create new handle if not found
   handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create ATR handle for %s %s period=%d err=%d",
                  symbol, EnumToString(tf), period, err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60); // Release handles not accessed in the last 60 seconds
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_ATR;
      m_handles[size].paramCount = 1;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = period;
      PrintFormat("[INDICATOR-MANAGER] Created ATR handle=%d for %s %s period=%d",
                  handle, symbol, EnumToString(tf), period);
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

   // Check symbol availability before creating indicator
   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   // Create new handle if not found
   handle = iMACD(symbol, tf, fast_ema_period, slow_ema_period, signal_period, applied_price);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create MACD handle for %s %s fast=%d slow=%d err=%d",
                  symbol, EnumToString(tf), fast_ema_period, slow_ema_period, err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60); // Release handles not accessed in the last 60 seconds
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_MACD;
      m_handles[size].paramCount = 4;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = fast_ema_period;
      m_handles[size].parameters[1] = slow_ema_period;
      m_handles[size].parameters[2] = signal_period;
      m_handles[size].parameters[3] = (int)applied_price;
      PrintFormat("[INDICATOR-MANAGER] Created MACD handle=%d for %s %s fast=%d slow=%d",
                  handle, symbol, EnumToString(tf), fast_ema_period, slow_ema_period);
   }

   return handle;
}

//+------------------------------------------------------------------+
//| Get ADX handle                                                   |
//+------------------------------------------------------------------+
int CIndicatorManager::GetADXHandle(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   int params[5] = {period};
   int handle = FindHandle(INDICATOR_ADX, symbol, tf, params);

   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }

   // Check symbol availability before creating indicator
   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   handle = iADX(symbol, tf, period);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create ADX handle for %s %s period=%d err=%d",
                  symbol, EnumToString(tf), period, err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60); // Release handles not accessed in the last 60 seconds
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_ADX;
      m_handles[size].paramCount = 1;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = period;
      PrintFormat("[INDICATOR-MANAGER] Created ADX handle=%d for %s %s period=%d",
                  handle, symbol, EnumToString(tf), period);
   }

   return handle;
}

//+------------------------------------------------------------------+
//| Get Stochastic handle                                             |
//+------------------------------------------------------------------+
int CIndicatorManager::GetStochasticHandle(string symbol, ENUM_TIMEFRAMES tf, int period_k, int period_d, int period_slow, ENUM_MA_METHOD ma_method, ENUM_STO_PRICE price_field)
{
   int params[5] = {period_k, period_d, period_slow, (int)ma_method, (int)price_field};
   int handle = FindHandle(INDICATOR_STOCH, symbol, tf, params);

   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }

   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   handle = iStochastic(symbol, tf, period_k, period_d, period_slow, ma_method, price_field);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create Stochastic handle for %s %s k=%d d=%d slow=%d err=%d",
                  symbol, EnumToString(tf), period_k, period_d, period_slow, err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60);
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_STOCH;
      m_handles[size].paramCount = 5;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = period_k;
      m_handles[size].parameters[1] = period_d;
      m_handles[size].parameters[2] = period_slow;
      m_handles[size].parameters[3] = (int)ma_method;
      m_handles[size].parameters[4] = (int)price_field;
      PrintFormat("[INDICATOR-MANAGER] Created Stochastic handle=%d for %s %s k=%d d=%d slow=%d",
                  handle, symbol, EnumToString(tf), period_k, period_d, period_slow);
   }

   return handle;
}

//+------------------------------------------------------------------+
//| Get Bollinger Bands handle                                       |
//+------------------------------------------------------------------+
int CIndicatorManager::GetBandsHandle(string symbol, ENUM_TIMEFRAMES tf, int period, int shift, double deviation, ENUM_APPLIED_PRICE applied_price)
{
   int scaledDeviation = (int)MathRound(deviation * 1000.0);
   int params[5] = {period, shift, scaledDeviation, (int)applied_price};
   int handle = FindHandle(INDICATOR_BB, symbol, tf, params);

   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }

   // Check symbol availability before creating indicator
   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   handle = iBands(symbol, tf, period, shift, deviation, applied_price);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create Bands handle for %s %s period=%d err=%d",
                  symbol, EnumToString(tf), period, err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60); // Release handles not accessed in the last 60 seconds
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_BB;
      m_handles[size].paramCount = 4;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = period;
      m_handles[size].parameters[1] = shift;
      m_handles[size].parameters[2] = scaledDeviation;
      m_handles[size].parameters[3] = (int)applied_price;
      PrintFormat("[INDICATOR-MANAGER] Created Bands handle=%d for %s %s period=%d",
                  handle, symbol, EnumToString(tf), period);
   }

   return handle;
}

//+------------------------------------------------------------------+
//| Get CCI handle                                                   |
//+------------------------------------------------------------------+
int CIndicatorManager::GetCCIHandle(string symbol, ENUM_TIMEFRAMES tf, int period, ENUM_APPLIED_PRICE applied_price)
{
   int params[5] = {period, (int)applied_price};
   int handle = FindHandle(INDICATOR_CCI, symbol, tf, params);

   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }

   // Check symbol availability before creating indicator
   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   handle = iCCI(symbol, tf, period, applied_price);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create CCI handle for %s %s period=%d err=%d",
                  symbol, EnumToString(tf), period, err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60); // Release handles not accessed in the last 60 seconds
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_CCI;
      m_handles[size].paramCount = 2;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = period;
      m_handles[size].parameters[1] = (int)applied_price;
      PrintFormat("[INDICATOR-MANAGER] Created CCI handle=%d for %s %s period=%d",
                  handle, symbol, EnumToString(tf), period);
   }

   return handle;
}

//+------------------------------------------------------------------+
//| Get Volumes handle                                               |
//+------------------------------------------------------------------+
int CIndicatorManager::GetVolumesHandle(string symbol, ENUM_TIMEFRAMES tf, ENUM_APPLIED_VOLUME applied_volume)
{
   int params[5] = {(int)applied_volume};
   int handle = FindHandle(INDICATOR_VOLUMES, symbol, tf, params);

   if(handle != INVALID_HANDLE)
   {
      AccessHandle(handle);
      return handle;
   }

   // Check symbol availability before creating indicator
   if(!IsSymbolAvailable(symbol, tf))
      return INVALID_HANDLE;

   handle = iVolumes(symbol, tf, applied_volume);
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("[INDICATOR-MANAGER] ERROR: Failed to create Volumes handle for %s %s err=%d",
                  symbol, EnumToString(tf), err);
   }
   if(handle != INVALID_HANDLE)
   {
      int size = ArraySize(m_handles);
      if(size >= MAX_INDICATOR_HANDLES)
      {
         PrintFormat("[INDICATOR-MANAGER] WARNING: Maximum indicator handles reached (%d), releasing oldest handles", MAX_INDICATOR_HANDLES);
         ReleaseUnused(60);
         size = ArraySize(m_handles);
         if(size >= MAX_INDICATOR_HANDLES)
         {
            PrintFormat("[INDICATOR-MANAGER] ERROR: Cannot create more indicator handles, limit reached (%d)", MAX_INDICATOR_HANDLES);
            IndicatorRelease(handle);
            return INVALID_HANDLE;
         }
      }
      ArrayResize(m_handles, size + 1);
      m_handles[size].handle = handle;
      m_handles[size].lastAccess = TimeCurrent();
      m_handles[size].symbol = symbol;
      m_handles[size].timeframe = tf;
      m_handles[size].type = INDICATOR_VOLUMES;
      m_handles[size].paramCount = 1;
      ArrayInitialize(m_handles[size].parameters, 0);
      m_handles[size].parameters[0] = (int)applied_volume;
      PrintFormat("[INDICATOR-MANAGER] Created Volumes handle=%d for %s %s",
                  handle, symbol, EnumToString(tf));
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

      case INDICATOR_ADX:
         if(ArraySize(params) >= 1)
            return GetADXHandle(symbol, tf, params[0]);
         break;

      case INDICATOR_BB:
         if(ArraySize(params) >= 4)
            return GetBandsHandle(symbol, tf, params[0], params[1], params[2] / 1000.0, (ENUM_APPLIED_PRICE)params[3]);
         break;

      case INDICATOR_CCI:
         if(ArraySize(params) >= 2)
            return GetCCIHandle(symbol, tf, params[0], (ENUM_APPLIED_PRICE)params[1]);
         break;

      case INDICATOR_VOLUMES:
         if(ArraySize(params) >= 1)
            return GetVolumesHandle(symbol, tf, (ENUM_APPLIED_VOLUME)params[0]);
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
   // AUDIT FIX: Removed 'delete m_instance' — destructor must not delete itself (double-free / UB)
   m_instance = NULL;
}

#endif // __INDICATOR_MANAGER_MQH__

