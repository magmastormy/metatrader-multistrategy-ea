// Shared enums and structures for the Python bridge.
// Extracted verbatim from PythonBridge.mqh (behaviour unchanged).
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_PYBRIDGE_TYPES_MQH
#define CORE_PYBRIDGE_TYPES_MQH

// Python Bridge Health State Enum
enum ENUM_PYTHON_BRIDGE_STATE
{
   PYTHON_BRIDGE_DISCONNECTED = 0,
   PYTHON_BRIDGE_CONNECTING   = 1,   // Attempting connection
   PYTHON_BRIDGE_CONNECTED    = 2,   // Connected and healthy
   PYTHON_BRIDGE_ERROR        = 3    // Error state
};

// Python Bridge Version Information
struct SPythonBridgeVersion
{
   string             version;         // Server version string
   int                major;           // Major version
   int                minor;           // Minor version
   int                patch;           // Patch version
   bool               compatible;      // Is compatible with this client
   
   SPythonBridgeVersion()
   {
      version = "";
      major = 0;
      minor = 0;
      patch = 0;
      compatible = false;
   }
};

struct SPythonBridgeHealthStatus
{
   ENUM_PYTHON_BRIDGE_STATE state;    // Connection state
   bool               connected;
   bool               healthy;
   datetime           last_heartbeat;  // Last successful heartbeat
   int                reconnect_attempts; // Number of reconnect attempts
   int                request_count;   // Total requests sent
   int                success_count;   // Successful requests
   int                error_count;     // Failed requests
   string             last_error;      // Last error message
   SPythonBridgeVersion version;       // Server version info
   
   SPythonBridgeHealthStatus()
   {
      state = PYTHON_BRIDGE_DISCONNECTED;
      connected = false;
      healthy = false;
      last_heartbeat = 0;
      reconnect_attempts = 0;
      request_count = 0;
      success_count = 0;
      error_count = 0;
      last_error = "";
   }
};

struct SPythonBridgeResponse
{
   bool               success;         // Request successful
   string             error_message;   // Error message if failed
   double             buy_prob;
   double             sell_prob;
   double             hold_prob;
   double             lgbm_buy;        // LGBM buy probability
   double             lgbm_sell;       // LGBM sell probability
   double             stacker_signal;
   string             ts;              // Timestamp
   string             mode;            // Response mode
   double             adapted_features[];
   int                family_id;       // Deriv family ID (-1 = universal)
   string             family_name;     // Family name from Python
   double             catboost_buy;    // CatBoost buy probability
   double             catboost_sell;   // CatBoost sell probability
   double             xgboost_buy;     // XGBoost buy probability
   double             xgboost_sell;    // XGBoost sell probability
   double             onnx_buy;        // ONNX buy probability (family-specific)
   double             onnx_sell;       // ONNX sell probability (family-specific)
   int                asset_class;     // Asset class ID (-1 = not specified)
   string             asset_class_name;

   SPythonBridgeResponse()
   {
      success = false;
      error_message = "";
      buy_prob = 0.0;
      sell_prob = 0.0;
      hold_prob = 0.0;
      lgbm_buy = 0.0;
      lgbm_sell = 0.0;
      stacker_signal = 0.0;
      ts = "";
      mode = "";
      ArrayResize(adapted_features, 0);
      family_id = -1;
      family_name = "";
      catboost_buy = 0.0;
      catboost_sell = 0.0;
      xgboost_buy = 0.0;
      xgboost_sell = 0.0;
      onnx_buy = 0.0;
      onnx_sell = 0.0;
      asset_class = -1;
      asset_class_name = "";
   }
};

#endif // CORE_PYBRIDGE_TYPES_MQH
