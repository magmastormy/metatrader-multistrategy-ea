//+------------------------------------------------------------------+
//| Strategy Interface                                             |
//| Base interface for all trading strategies                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef INTERFACES_ISTRATEGY_MQH
#define INTERFACES_ISTRATEGY_MQH

#include "../Core/Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Strategy Interface                                             |
//+------------------------------------------------------------------+
class IStrategy
{
public:
    // Virtual destructor
    virtual ~IStrategy(void) {}
    
    // Initialize strategy
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                     void* tradeManager, void* positionSizer, void* unifiedRiskManager = NULL) = 0;
    
    // Deinitialize strategy
    virtual void Deinit(void) = 0;
    
    // Get trading signal
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) = 0;
    
    // Update strategy on new bar
    virtual void OnNewBar(void) = 0;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) = 0;
    
    // Get strategy name
    virtual string GetName(void) const = 0;
    
    // Get strategy type
    virtual ENUM_STRATEGY_TYPE GetType(void) const = 0;
    
    // Check if strategy is enabled
    virtual bool IsEnabled(void) const = 0;
    
    // Enable/disable strategy
    virtual void SetEnabled(const bool enabled) = 0;
    
    // Get strategy weight
    virtual double GetWeight(void) const = 0;
    
    // Set strategy weight
    virtual void SetWeight(const double weight) = 0;
    
    // Validate strategy parameters
    virtual bool ValidateParameters(void) = 0;
    
    // Get last signal time
    virtual datetime GetLastSignalTime(void) const = 0;
    
    // Get strategy statistics
    virtual void GetStatistics(int &signals, int &successful, double &accuracy) = 0;

    // Last cycle decision reason tag for telemetry attribution.
    // Empty string means strategy does not expose a reason.
    virtual string GetLastDecisionReasonTag(void) const { return ""; }

    // Set confidence threshold for the strategy
    virtual void SetConfidenceThreshold(double threshold) {}
};

#endif // INTERFACES_ISTRATEGY_MQH
