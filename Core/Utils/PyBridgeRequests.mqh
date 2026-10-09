// Request/response dispatch for the Python bridge: prediction
// endpoints and the correlation endpoints. Stateless - all state
// lives in CPyBridgeTransport / CPyBridgeHealth, supplied by ref.
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_PYBRIDGE_REQUESTS_MQH
#define CORE_PYBRIDGE_REQUESTS_MQH

#include "PyBridgeTypes.mqh"
#include "PyBridgeProtocol.mqh"
#include "PyBridgeTransport.mqh"
#include "PyBridgeHealth.mqh"

class CPyBridgeRequests
{
public:
   static SPythonBridgeResponse Predict(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                        const double &features[], int features_size,
                                        const string mode,
                                        int family_id,
                                        const string symbol,
                                        int asset_class,
                                        const string asset_class_name);
   static SPythonBridgeResponse PredictDoubleAdapt(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                                   const double &features[], int features_size);
   static SPythonBridgeResponse PredictMamlPpo(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                               const double &features[], int features_size);
   static SPythonBridgeResponse PredictFamily(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                              const double &features[], int features_size,
                                              int family_id, const string symbol);
   static SPythonBridgeResponse PredictMultiAsset(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                                  const double &features[], int features_size,
                                                  int asset_class, const string asset_class_name,
                                                  int family_id, const string symbol);

   static bool       GetCorrelationMatrix(CPyBridgeTransport &transport,
                                          double &corrMatrix[], int &size, string &symbols[]);
   static double     GetPairCorrelation(CPyBridgeTransport &transport,
                                        const string symbol1, const string symbol2);
   static bool       FindBestCorrelatedPair(CPyBridgeTransport &transport,
                                            const string symbol, string &bestPair, double &correlation);
};

SPythonBridgeResponse CPyBridgeRequests::Predict(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                                 const double &features[], int features_size,
                                                 const string mode,
                                                 int family_id,
                                                 const string symbol,
                                                 int asset_class,
                                                 const string asset_class_name)
{
   SPythonBridgeResponse result;
   
   if(transport.GetMode() == PYTHON_BRIDGE_OFF || !transport.IsInitialized())
   {
      result.success = false;
      result.error_message = "Python bridge disabled";
      return result;
   }
   
   if(!health.CheckHealth(transport))
   {
      result.success = false;
      result.error_message = "Python bridge not available";
      return result;
   }
   
   string json = CPyBridgeProtocol::BuildPredictRequest(features, features_size, mode,
                                                        family_id, symbol,
                                                        asset_class, asset_class_name);
   
   string response;
   string requestUrl = transport.GetEndpoint() + "/predict";
   if(transport.SendHttpRequest("POST", requestUrl, json, response))
   {
      result = CPyBridgeProtocol::ParsePredictionResponse(response);
      if(result.success)
         health.MarkHeartbeat(TimeCurrent());
   }
   else
   {
      result.success = false;
      result.error_message = "Failed to send prediction request";
      transport.SetState(PYTHON_BRIDGE_DISCONNECTED);
   }
   
   return result;
}

SPythonBridgeResponse CPyBridgeRequests::PredictDoubleAdapt(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                                            const double &features[], int features_size)
{
   return Predict(transport, health, features, features_size, "doubleadapt", -1, "", -1, "");
}

SPythonBridgeResponse CPyBridgeRequests::PredictMamlPpo(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                                        const double &features[], int features_size)
{
   return Predict(transport, health, features, features_size, "maml_ppo", -1, "", -1, "");
}

SPythonBridgeResponse CPyBridgeRequests::PredictFamily(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                                       const double &features[], int features_size,
                                                       int family_id, const string symbol)
{
   return Predict(transport, health, features, features_size, "ensemble", family_id, symbol, -1, "");
}

SPythonBridgeResponse CPyBridgeRequests::PredictMultiAsset(CPyBridgeTransport &transport, CPyBridgeHealth &health,
                                                           const double &features[], int features_size,
                                                           int asset_class, const string asset_class_name,
                                                           int family_id, const string symbol)
{
   return Predict(transport, health, features, features_size, "ensemble", family_id, symbol, asset_class, asset_class_name);
}

// Returns flattened matrix (row-major order): matrix[i*size + j]
bool CPyBridgeRequests::GetCorrelationMatrix(CPyBridgeTransport &transport,
                                             double &corrMatrix[], int &size, string &symbols[])
{
   if(transport.GetMode() == PYTHON_BRIDGE_OFF || !transport.IsInitialized() || !transport.IsConnected())
      return false;
   
   string response;
   string corrUrl = transport.GetEndpoint() + "/correlation_matrix";
   
   if(!transport.SendHttpRequest("GET", corrUrl, "", response))
   {
      transport.SetLastError("Failed to fetch correlation matrix");
      transport.IncrementErrorCount();
      return false;
   }
   
   // Expected format: {"symbols": ["Vol75", "Vol100", ...], "matrix": [[1.0, 0.85, ...], ...]}
   if(StringFind(response, "\"matrix\"") != -1)
   {
      int symPos = StringFind(response, "\"symbols\"");
      if(symPos != -1)
      {
         // Count symbols by counting commas in the array
         int arrStart = StringFind(response, "[", symPos);
         int arrEnd = StringFind(response, "]", arrStart);
         if(arrStart != -1 && arrEnd != -1)
         {
            string arrStr = StringSubstr(response, arrStart + 1, arrEnd - arrStart - 1);
            int symCount = 1;
            for(int c = 0; c < StringLen(arrStr); c++)
               if(StringGetCharacter(arrStr, c) == ',') symCount++;

            PrintFormat("[PYTHON-BRIDGE] Correlation matrix received: %d symbols", symCount);
            // NOTE: success only means the endpoint answered. corrMatrix, size and symbols
            // are NOT populated by this call - never consume the out-params.
            transport.SetLastError("");
            return true;
         }
      }
   }

   transport.SetLastError("Correlation matrix endpoint returned no parseable data");
   return false;
}

double CPyBridgeRequests::GetPairCorrelation(CPyBridgeTransport &transport,
                                             const string symbol1, const string symbol2)
{
   if(transport.GetMode() == PYTHON_BRIDGE_OFF || !transport.IsInitialized() || !transport.IsConnected())
   {
      return 0.0;
   }
   
   string response;
   string corrUrl = transport.GetEndpoint() + "/correlation?symbol1=" + symbol1 + "&symbol2=" + symbol2;
   
   if(transport.SendHttpRequest("GET", corrUrl, "", response))
   {
      // Parse JSON response {"correlation": 0.85}
      if(StringFind(response, "\"correlation\":") != -1)
      {
         double corr = CPyBridgeProtocol::ParseJsonDouble(response, "correlation");
         if(corr >= -1.0 && corr <= 1.0)
         {
            PrintFormat("[PYTHON-BRIDGE] Pair correlation: %s/%s = %.4f", symbol1, symbol2, corr);
            return corr;
         }
      }
      if(StringFind(response, "\"error\"") != -1)
         PrintFormat("[PYTHON-BRIDGE] Pair correlation error for %s/%s", symbol1, symbol2);
   }
   
   return 0.0;
}

bool CPyBridgeRequests::FindBestCorrelatedPair(CPyBridgeTransport &transport,
                                               const string symbol, string &bestPair, double &correlation)
{
   if(transport.GetMode() == PYTHON_BRIDGE_OFF || !transport.IsInitialized() || !transport.IsConnected())
   {
      bestPair = "";
      correlation = 0.0;
      return false;
   }
   
   string response;
   string bestPairUrl = transport.GetEndpoint() + "/best_pair?symbol=" + symbol;
   
   if(transport.SendHttpRequest("GET", bestPairUrl, "", response))
   {
      // Parse JSON response {"best_pair": "Vol100", "correlation": 0.92}
      string foundPair = "";
      double foundCorr = 0.0;
      bool parsed = false;

      if(StringFind(response, "\"best_pair\":") != -1)
      {
         foundPair = CPyBridgeProtocol::ParseJsonString(response, "best_pair");
         if(StringLen(foundPair) > 0) parsed = true;
      }

      if(StringFind(response, "\"correlation\":") != -1)
         foundCorr = CPyBridgeProtocol::ParseJsonDouble(response, "correlation");

      if(parsed && StringLen(foundPair) > 0 && foundCorr >= -1.0 && foundCorr <= 1.0)
      {
         bestPair = foundPair;
         correlation = foundCorr;
         PrintFormat("[PYTHON-BRIDGE] Best pair for %s: %s (corr=%.4f)", symbol, bestPair, correlation);
         return true;
      }

      if(StringFind(response, "\"error\"") != -1)
         PrintFormat("[PYTHON-BRIDGE] Best pair error for %s", symbol);
   }
   
   bestPair = "";
   correlation = 0.0;
   return false;
}

#endif // CORE_PYBRIDGE_REQUESTS_MQH
