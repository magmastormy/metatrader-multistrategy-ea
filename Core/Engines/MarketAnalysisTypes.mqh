//+------------------------------------------------------------------+
//| MarketAnalysisTypes.mqh - Shared market analysis constants       |
//| Extracted verbatim from MarketAnalysis.mqh (no behavior change)  |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef MARKET_ANALYSIS_TYPES_MQH
#define MARKET_ANALYSIS_TYPES_MQH

//+------------------------------------------------------------------+
//| Default indicator periods.                                       |
//| These macros were previously written inside the CMarketAnalysis  |
//| class body; preprocessor scope was already global, so the values |
//| and their visibility are unchanged.                              |
//+------------------------------------------------------------------+
#define ADX_PERIOD 14
#define ATR_PERIOD 14
#define BB_PERIOD 20
#define BB_DEVIATION 2.0
#define MACD_FAST 12
#define MACD_SLOW 26
#define MACD_SIGNAL 9
#define RSI_PERIOD 14
#define MA_FAST 50
#define MA_SLOW 200

#endif // MARKET_ANALYSIS_TYPES_MQH
