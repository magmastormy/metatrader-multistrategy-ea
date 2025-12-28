//+------------------------------------------------------------------+
//| StrategyFunctions.mqh                                            |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __STRATEGY_FUNCTIONS_MQH__
#define __STRATEGY_FUNCTIONS_MQH__

//+------------------------------------------------------------------+
//| Strategy function declarations (implemented in individual files)  |
//+------------------------------------------------------------------+


// Import strategy implementations from their respective files
// Include strategy implementations from the project root Strategies directory
#include "..\..\Strategies\StrategyRSI.mqh"
#include "..\..\Strategies\StrategySwing.mqh"
#include "..\..\Strategies\StrategyVolatility.mqh"
#include "..\..\Strategies\StrategyTrend.mqh"
#include "..\..\Strategies\StrategyBreakout.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

#endif // __STRATEGY_FUNCTIONS_MQH__
