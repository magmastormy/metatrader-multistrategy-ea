//+------------------------------------------------------------------+
//| TradeExecutor.mqh                                                |
//| Core trade execution engine - handles order placement,           |
//| position opening/closing, and basic trade operations             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#ifndef CORE_TRADE_EXECUTOR_MQH
#define CORE_TRADE_EXECUTOR_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/HistoryOrderInfo.mqh>
#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Utils/Instruments.mqh"
#include "../Cache/ATRCache.mqh"
#include "TradeTypes.mqh"

#define MAX_TRADE_RETRIES 4
#define TRADE_RETRY_DELAY 150
#define ORDER_TIMEOUT_SECONDS 30
#define MAX_ORDERS_PER_SYMBOL 5

class CTradeExecutor
{
private:
    CTrade m_trade;
    CPositionInfo m_positionInfo;
    CSymbolInfo m_symbolInfo;
    CHistoryOrderInfo m_historyOrderInfo;
    CATRCache m_atrCache;

    uint m_slippage;
    long m_magicNumber;
    long m_magicRangeMax;
    string m_expertName;
    bool m_useAsyncMode;
    ENUM_ORDER_TYPE_FILLING m_orderFillMode;
    int m_logLevel;
    bool m_emergencyStop;

    struct ExecutionQualityMetrics {
        int totalOrders;
        int filledOrders;
        int partialFills;
        int rejectedOrders;
        double totalSlippagePoints;
        double totalSpreadCost;
        double totalLatencyMs;
        double maxSlippagePoints;
        double maxLatencyMs;
        datetime lastUpdateTime;
    } m_execMetrics;

    // Execution settings
    double m_maxEntrySpreadPoints;
    double m_maxEntryDriftPoints;

    // Dynamic slippage settings
    bool m_enableDynamicSlippage;
    double m_dynamicSlippageAtrPercent;
    uint m_dynamicSlippageMinPoints;
    uint m_dynamicSlippageMaxMultiplier;
    int m_dynamicSlippageAtrPeriod;
    uint m_baseSlippage;

    // Smart order routing
    struct SSmartOrderParams
    {
        bool shouldTrade;
        uint recommendedSlippage;
        ENUM_ORDER_TYPE_FILLING recommendedFillMode;
        string reason;

        SSmartOrderParams() : shouldTrade(true), recommendedSlippage(0), recommendedFillMode(ORDER_FILLING_FOK) {}
    };

public:
    struct STradeStats
    {
        int totalTrades;
        int successfulTrades;
        int winningTrades;
        uint failedTrades;
        double totalProfit;
        double totalLoss;
        datetime lastTradeTime;
    };

    CTradeExecutor() : m_slippage(20), m_magicNumber(0), m_magicRangeMax(0), m_expertName(""),
                       m_useAsyncMode(false), m_orderFillMode(ORDER_FILLING_FOK), m_logLevel(2),
                       m_emergencyStop(false), m_maxEntrySpreadPoints(0), m_maxEntryDriftPoints(0),
                       m_enableDynamicSlippage(false), m_dynamicSlippageAtrPercent(0.1),
                       m_dynamicSlippageMinPoints(5), m_dynamicSlippageMaxMultiplier(3),
                       m_dynamicSlippageAtrPeriod(14), m_baseSlippage(20)
    {
        ResetMetrics();
    }

    ~CTradeExecutor() {}

    // Initialization
    bool Initialize(const string expertName, const long magicNumber, const long magicRangeMax = 0,
                   const uint slippage = 20, const ENUM_ORDER_TYPE_FILLING fillMode = ORDER_FILLING_FOK)
    {
        m_expertName = expertName;
        m_magicNumber = magicNumber;
        m_magicRangeMax = (magicRangeMax > 0 ? magicRangeMax : magicNumber);
        m_slippage = slippage;
        m_orderFillMode = fillMode;
        m_baseSlippage = slippage;

        m_trade.SetExpertMagicNumber(m_magicNumber);
        m_trade.SetDeviationInPoints(m_slippage);
        m_trade.SetTypeFilling(m_orderFillMode);

        return true;
    }

    // Dependencies
    void SetDependencies(CPerformanceAnalytics* perf, CPortfolioRiskManager* risk, 
                         CPositionSizer* sizer, CMarketAnalysis* market)
    {
        // Dependencies handled externally
    }

    void SetErrorHandler(CEnhancedErrorHandler* handler) { /* external */ }

    // Core trade execution
    bool OpenPosition(const string symbol, const ENUM_ORDER_TYPE orderType,
                     const double volume, const double requestedPrice,
                     const double stopLossPips, const double takeProfitPips,
                     const string comment, STradeExecutionReceipt &receipt);

    bool ClosePosition(const string symbol, const ulong ticket, 
                       const double volume, const string comment, 
                       STradeExecutionReceipt &receipt);

    bool ClosePositionByTicket(const ulong ticket, const double volume,
                               STradeExecutionReceipt &receipt);

    bool ModifyPosition(const ulong ticket, const double newSL, const double newTP,
                        STradeExecutionReceipt &receipt);

    // Validation
    bool NormalizeAndValidateStops(const string symbol, const ENUM_ORDER_TYPE orderType,
                                   const double price, const double tp, double &slOut, double &tpOut,
                                   string &errorMsg);

    bool IsOrderTypeAllowedForSymbol(const string symbolName, const ENUM_ORDER_TYPE orderType, string &reason);

    double CalculatePositionRisk(const string symbolParam, const double volume, const double stopLossPips);

    double GetCurrentExecutionPrice(const string symbolName, const ENUM_ORDER_TYPE orderType);

    double GetMinimumStopDistance(const string symbolName);

    int GetMinimumStopPoints(const string symbolName);

    // Dynamic slippage
    void EnableDynamicSlippage(bool enable, double atrPercent = 0.1, uint minPoints = 5,
                               uint maxMultiplier = 3, int atrPeriod = 14)
    {
        m_enableDynamicSlippage = enable;
        m_dynamicSlippageAtrPercent = atrPercent;
        m_dynamicSlippageMinPoints = minPoints;
        m_dynamicSlippageMaxMultiplier = maxMultiplier;
        m_dynamicSlippageAtrPeriod = atrPeriod;
    }

    uint CalculateDynamicSlippage(const string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT);

    // Smart order routing
    SSmartOrderParams AnalyzeAndRecommendOrderParams(const string symbol);

    bool ApplySmartOrderRouting(const string symbol);

    // Metrics
    void ResetMetrics()
    {
        m_execMetrics.totalOrders = 0;
        m_execMetrics.filledOrders = 0;
        m_execMetrics.partialFills = 0;
        m_execMetrics.rejectedOrders = 0;
        m_execMetrics.totalSlippagePoints = 0.0;
        m_execMetrics.totalSpreadCost = 0.0;
        m_execMetrics.totalLatencyMs = 0.0;
        m_execMetrics.maxSlippagePoints = 0.0;
        m_execMetrics.maxLatencyMs = 0.0;
        m_execMetrics.lastUpdateTime = 0;
    }

    void UpdateExecutionMetrics(const STradeExecutionReceipt &receipt);

    double GetAverageSlippage() const
    {
        return (m_execMetrics.filledOrders > 0) ? 
               m_execMetrics.totalSlippagePoints / m_execMetrics.filledOrders : 0.0;
    }

    double GetFillRate() const
    {
        return (m_execMetrics.totalOrders > 0) ? 
               (double)m_execMetrics.filledOrders / m_execMetrics.totalOrders : 0.0;
    }

    // Settings
    void SetSlippage(uint slippage) { m_slippage = slippage; m_trade.SetDeviationInPoints(slippage); }
    void SetMagicNumber(long magic) { m_magicNumber = magic; m_trade.SetExpertMagicNumber(magic); }
    void SetMagicRangeMax(long max) { m_magicRangeMax = (max > 0 ? max : m_magicNumber); }
    void SetOrderFillMode(ENUM_ORDER_TYPE_FILLING mode) { m_orderFillMode = mode; m_trade.SetTypeFilling(mode); }
    void SetLogLevel(int level) { m_logLevel = level; }
    void SetEmergencyStop(bool stop) { m_emergencyStop = stop; }
    void SetMaxEntrySpreadPoints(double points) { m_maxEntrySpreadPoints = points; }
    void SetMaxEntryDriftPoints(double points) { m_maxEntryDriftPoints = points; }
    void SetAsyncMode(bool async) { m_useAsyncMode = async; }

    // Accessors
    uint GetSlippage() const { return m_slippage; }
    long GetMagicNumber() const { return m_magicNumber; }
    long GetMagicRangeMax() const { return m_magicRangeMax; }
    bool IsEmergencyStop() const { return m_emergencyStop; }
    void GetLastExecutionReceipt(STradeExecutionReceipt &receipt) const { receipt = m_lastExecutionReceipt; }
    bool IsAsyncModeEnabled() const { return m_useAsyncMode; }
    ENUM_ORDER_TYPE_FILLING GetOrderFillMode() const { return m_orderFillMode; }

private:
    STradeExecutionReceipt m_lastExecutionReceipt;

    // Internal helpers
    bool ValidateTradeParameters(const string symbol, const ENUM_ORDER_TYPE orderType,
                                 const double volume, const double price,
                                 const double sl, const double tp, string &errorMsg);

    bool CheckSpreadGate(const string symbol, const double requestedPrice);

    bool CheckDriftGate(const string symbol, const double requestedPrice, const double signalPrice);

    int GetPrecision(const string symbol);

    double NormalizePrice(const string symbol, const double price);

    double NormalizeVolume(const string symbol, const double volume);

    void LogTradeOperation(const string operation, const string symbolName, 
                           const ENUM_ORDER_TYPE orderType, const double volume, 
                           const bool success, const string details = "");
};

#endif // CORE_TRADE_EXECUTOR_MQH