// Safe Trade Execution Engine
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#ifndef CORE_TRADE_MANAGER_MQH
#define CORE_TRADE_MANAGER_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/HistoryOrderInfo.mqh>

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Utils/SessionManager.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/PortfolioRiskManager.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"
#include "../Engines/MarketAnalysis.mqh"
#include "../../IndicatorManager.mqh"
#include "../Cache/ATRCache.mqh"
#include "../Utils/Instruments.mqh"
#include "../Utils/MagicRange.mqh"
#include "../Utils/TradeJournal.mqh"
#include "TradeTypes.mqh"
#include "TradeRetcodeClassifier.mqh"
#include "TradeSpreadCostModel.mqh"
#include "TradeDescriptor.mqh"
#include "ExecutionQualityTracker.mqh"
#include "TradeStatsTracker.mqh"
#include "PositionStateTracker.mqh"
// Included ABOVE the class body because CTradeManager holds the stateful modules BY VALUE and needs their complete types.
#include "TradeMgrPricing.mqh"
#include "TradeMgrSymbolTradeRegistry.mqh"
#include "TradeMgrConfirmationQueue.mqh"
#include "TradeMgrPreflight.mqh"
#include "TradeMgrAsyncExecutor.mqh"


class CEnhancedErrorHandler;
class CMarketAnalysis;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;


#define MAX_TRADE_RETRIES 4
#define TRADE_RETRY_DELAY 150 // ms
#define MAX_ORDERS_PER_SYMBOL 5
#define ORDER_TIMEOUT_SECONDS 30


class CTradeManager
{
private:
    CTrade m_trade;                          // MT5 trade object (fallback/default)
    CPositionInfo m_positionInfo;            // Position info object
    CSymbolInfo m_symbolInfo;                // Symbol info object
    CHistoryOrderInfo m_historyOrderInfo;
    CSessionManager m_sessionManager;        // Session manager object

    // Per-symbol CTrade instances avoid multi-symbol send races: one pooled CTrade is used per symbol.
    // The registry also owns the magic-offset table and the EA-owned position ticket cache.
    CTradeMgrSymbolTradeRegistry m_symbolRegistry;

    // Dependencies (owned externally)
    CPerformanceAnalytics* m_perfAnalytics;
    CPortfolioRiskManager* m_riskManager;
    CPositionSizer* m_positionSizer;
    CMarketAnalysis* m_marketAnalysis;
    CEnhancedErrorHandler* m_errorHandler;

    uint m_slippage;                         // Maximum slippage (in points)
    long m_magicNumber;                      // Magic number for trades (base) â€?changed from uint to long for 64-bit support
    long m_magicRangeMax;                    // Max magic number for EA ownership range check â€?changed from uint to long
    string m_expertName;                     // Expert advisor name
    bool m_useAsyncMode;                     // Use asynchronous order execution
    ENUM_ORDER_TYPE_FILLING m_orderFillMode; // Preferred broker fill policy
    ulong m_pendingExplicitMagic;            // Batch 152 (T-01): absolute magic for the next send (0 = derive base+offset)
    int m_minModifyIntervalSec;              // Minimum interval between routine stop updates
    double m_maxEntrySpreadPoints;           // Hard quote-spread gate before market send
    double m_maxEntryDriftPoints;            // Hard drift gate between signal price and send price

    bool m_enableDynamicSlippage;            // Enable ATR-based dynamic slippage
    double m_dynamicSlippageAtrPercent;
    uint m_dynamicSlippageMinPoints;
    uint m_dynamicSlippageMaxMultiplier;     // Maximum slippage as multiplier of base
    int m_dynamicSlippageAtrPeriod;          // ATR period for volatility calculation
    uint m_baseSlippage;                     // Base slippage before dynamic adjustment

    // Execution quality metrics â€?state owned by CExecutionQualityTracker
    CExecutionQualityTracker m_execQuality;

    // Trade tracking and statistics â€?state owned by CTradeStatsTracker
    CTradeStatsTracker m_tradeStats;

    int m_totalTrades;
    int m_successfulTrades;
    uint m_failedTrades;
    datetime m_lastTradeTime;

    bool m_emergencyStop;                    // Emergency stop flag
    int m_logLevel;                          // Log verbosity: 0=Silent, 1=Critical, 2=Normal, 3=Verbose, 4=Debug

    // ATR value cache to avoid redundant indicator reads per bar
    CATRCache m_atrCache;

    // Pending confirmation tracking for non-blocking execution (CTradeMgrConfirmationQueue)
    CTradeMgrConfirmationQueue m_confirmationQueue;

    // Async trade execution tracking â€?state owned by CTradeMgrAsyncExecutor
    CTradeMgrAsyncExecutor m_asyncExecutor;

    MqlTradeResult m_lastTradeResult;        // Result of the last trade operation
    MqlTick m_lastTick;                      // Last tick data for symbol validation
    datetime m_lastOrderCheckTime;           // Last time orders were checked
    double m_lastRequestedPrice;             // Last market price used for submit
    double m_lastRequestedStopLoss;          // Last SL sent to broker
    double m_lastRequestedTakeProfit;        // Last TP sent to broker
    STradeExecutionReceipt m_lastExecutionReceipt;


    struct PendingOrder {
        ulong ticket;
        datetime openTime;
        string symbol;
        ENUM_ORDER_TYPE type;
        double volume;
        double openPrice;
        double stopLoss;
        double takeProfit;
    };
    PendingOrder m_pendingOrders[100];       // Track pending orders
    int m_pendingOrderCount;

    // State tracking to prevent redundant modifications â€?owned by CPositionStateTracker
    CPositionStateTracker m_positionStateTracker;


        // Account margin mode cached once at Initialize() for hedging/netting compliance.
        ENUM_ACCOUNT_MARGIN_MODE m_accountMarginMode;
        bool m_marginModeInitialized;

        void InitializeMarginMode()
        {
           if(!m_marginModeInitialized)
           {
              m_accountMarginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
              m_marginModeInitialized = true;
              PrintFormat("[TRADE-MGR] Account margin mode: %s", EnumToString(m_accountMarginMode));
           }
        }

// Refuses a non-hedging account: the EA keeps per-strategy books, and on netting a second
// signal nets against the first, so SL/TP, risk accounting and attribution all describe a
// position that is no longer the one any single strategy opened.
        bool IsHedgingAllowed(const string symbol) const
        {
           return m_accountMarginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
        }

            double GetNetPositionVolume(const string symbol, ENUM_POSITION_TYPE type) const { return CTradeMgrPricing::GetNetPositionVolume(symbol, type, m_accountMarginMode); }

// Position state registry â€?thin forwarders onto CPositionStateTracker.
    void UpdatePositionState(ulong ticket, double sl, double tp) { m_positionStateTracker.UpdatePositionState(ticket, sl, tp); }

    void CleanupPositionStates() { m_positionStateTracker.CleanupPositionStates(); }

    bool IsModificationNeeded(ulong ticket, double newSL, double newTP) { return m_positionStateTracker.IsModificationNeeded(ticket, newSL, newTP, m_minModifyIntervalSec); }

// EA-owned position ticket cache helpers - forwarders onto CTradeMgrSymbolTradeRegistry.
    void AddEAOwnedPosition(ulong ticket) { m_symbolRegistry.AddEAOwnedPosition(ticket); }

    void RemoveEAOwnedPosition(ulong ticket) { m_symbolRegistry.RemoveEAOwnedPosition(ticket); }

    void ClearEAOwnedPositions() { m_symbolRegistry.ClearEAOwnedPositions(); }

    int GetEAOwnedPositionCount() const { return m_symbolRegistry.GetEAOwnedPositionCount(); }

    ulong GetEAOwnedPositionTicket(int index) const { return m_symbolRegistry.GetEAOwnedPositionTicket(index); }

    bool DoubleEquals(double a, double b, double epsilon = 0.00001) { return CTradeMgrPricing::DoubleEquals(a, b, epsilon); }

    void LogError(const string message, const string symbolParam = "", int errorCode = 0)
    {
        if(m_errorHandler != NULL)
        {
            SErrorContext context;
            context.component = "TradeManager";
            context.symbol = (symbolParam != "") ? symbolParam : m_symbolInfo.Name();
            context.errorCode = errorCode;
            context.additionalInfo = message;

            CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
            if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
                localErrorHandler.LogError(ERROR_RECOVERABLE, context);
            }
        }
        else
        {
            Print("[ERROR] ", message, " (Symbol: ", symbolParam, ")");
        }
    }

    void LogError(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(severity, context);
        }
    }

    void LogError(const SErrorContext &context)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(context);
        }
    }

    double CalculateATR(const string symbolParam, ENUM_TIMEFRAMES timeframe, int period) { return CTradeMgrPricing::CalculateATR(symbolParam, timeframe, period); }

    void LogTradeError(const MqlTradeResult &result, const string operation = "TradeOperation");

    string GetTradeErrorDescription(int errorCode) { return CTradeDescriptor::GetTradeErrorDescription(errorCode); }

    bool IsMarketOpen(const string symbolParam)
    {
        return m_sessionManager.IsMarketOpen(symbolParam);
    }

    bool IsTransientTradeRetcode(const uint retcode) const { return CTradeRetcodeClassifier::IsTransientTradeRetcode(retcode); }

    bool IsLimitedRetryRetcode(const uint retcode) const { return CTradeRetcodeClassifier::IsLimitedRetryRetcode(retcode); }

    bool IsSuccessfulFillRetcode(const uint retcode) const { return CTradeRetcodeClassifier::IsSuccessfulFillRetcode(retcode); }

    // Takes the CTrade that will actually send; configuring only m_trade never reached the pooled instance.
    void ApplyFillingModeForSymbol(const string symbolParam, CTrade* targetTrade = NULL)
    {
        // MQL5 cannot bind a reference from a conditional expression (error 229): dispatch both cases separately.
        if(targetTrade != NULL)
            CTradeMgrPreflight::ApplyFillingModeForSymbol(symbolParam, *targetTrade, m_marketAnalysis, m_orderFillMode);
        else
            CTradeMgrPreflight::ApplyFillingModeForSymbol(symbolParam, m_trade, m_marketAnalysis, m_orderFillMode);
    }

    void ResetExecutionReceipt(const string symbolParam, const double requestedVolume)
    {
        m_lastExecutionReceipt = STradeExecutionReceipt();
        m_lastExecutionReceipt.symbol = symbolParam;
        m_lastExecutionReceipt.requestedVolume = requestedVolume;
    }

    bool ValidateExecutionPreflight(const string symbolName,
                                    const ENUM_ORDER_TYPE orderType,
                                    const double executionPrice,
                                    const double requestedPrice,
                                    string &reason)
    {
        return CTradeMgrPreflight::ValidateExecutionPreflight(symbolName, orderType, executionPrice, requestedPrice,
                                                              m_sessionManager, m_atrCache,
                                                              m_maxEntrySpreadPoints, m_maxEntryDriftPoints,
                                                              m_dynamicSlippageAtrPeriod, reason);
    }

    bool ConfirmExecutionReceipt(const string symbolName,
                                 const ENUM_ORDER_TYPE orderType,
                                 const double requestedVolume,
                                 const double fallbackPrice,
                                 const MqlTradeResult &tradeResult)
    {
        return CTradeMgrPreflight::ConfirmExecutionReceipt(symbolName, orderType, requestedVolume, fallbackPrice,
                                                           tradeResult, m_lastExecutionReceipt, m_confirmationQueue);
    }

public:
    CTradeManager(CPerformanceAnalytics* pPerfAnalytics = NULL,
                 CPortfolioRiskManager* pRiskManager = NULL,
                 CPositionSizer* pPositionSizer = NULL,
                 CMarketAnalysis* pMarketAnalysis = NULL,
                 CEnhancedErrorHandler* pErrorHandler = NULL) :
        m_perfAnalytics(pPerfAnalytics),
        m_riskManager(pRiskManager),
        m_positionSizer(pPositionSizer),
        m_marketAnalysis(pMarketAnalysis),
        m_errorHandler(pErrorHandler),
        m_slippage(10),
        m_magicNumber(0),
        m_magicRangeMax(0),
        m_useAsyncMode(false),
        m_orderFillMode(ORDER_FILLING_IOC),
        m_minModifyIntervalSec(5),
        m_maxEntrySpreadPoints(0.0),
        m_maxEntryDriftPoints(0.0),
        m_enableDynamicSlippage(true),
        m_dynamicSlippageAtrPercent(0.20),
        m_dynamicSlippageMinPoints(10),
        m_dynamicSlippageMaxMultiplier(10),
        m_dynamicSlippageAtrPeriod(14),
        m_baseSlippage(10),
        m_emergencyStop(false),
        m_logLevel(1),
        m_pendingOrderCount(0),
        m_totalTrades(0),
        m_successfulTrades(0),
        m_failedTrades(0),
        m_lastTradeTime(0),
        m_lastRequestedPrice(0.0),
        m_lastRequestedStopLoss(0.0),
        m_lastRequestedTakeProfit(0.0)
    {
        m_trade.SetExpertMagicNumber(m_magicNumber);
        m_trade.SetDeviationInPoints(m_slippage);
        m_trade.SetAsyncMode(m_useAsyncMode);
        m_symbolInfo.Name(Symbol());
    }

public:
    ~CTradeManager()
    {
        CleanupPersistedAsyncTrades();

        m_atrCache.Reset();

        m_asyncExecutor.FreePending();
        m_symbolRegistry.FreeMagicOffsets();

        m_confirmationQueue.Clear();
    }

        bool Initialize(const long magicNumber = 12345, const string expertName = "MultiStrategyEA");
    
        void Deinit();
    
    CPositionSizer* GetPositionSizer() const { return m_positionSizer; }

    void SetSlippage(const uint slippage) { m_slippage = slippage; m_baseSlippage = slippage; m_trade.SetDeviationInPoints(m_slippage); UpdatePerSymbolSlippage(m_slippage); }
    void SetMagicNumber(const long magicNumber) { m_magicNumber = magicNumber; m_trade.SetExpertMagicNumber(m_magicNumber); UpdatePerSymbolMagicNumber(m_magicNumber); }
    void SetMagicRangeMax(const long magicRangeMax) { m_magicRangeMax = magicRangeMax; }
    //--- Ownership window comes from CMagicRange, the single authority; its span must cover asset-class
    //--- offsets (0..9999). Before SetMagicRangeMax runs, ComputeMax(base, 1) is a minimum-width fallback.
    bool IsEAOwnedMagic(const long magic) const
    {
        long upper = (m_magicRangeMax >= m_magicNumber)
                     ? m_magicRangeMax
                     : CMagicRange::ComputeMax(m_magicNumber, 1);
        return CMagicRange::IsOwned(magic, m_magicNumber, upper);
    }

    void UpdatePerSymbolSlippage(const uint slippage) { m_symbolRegistry.UpdatePerSymbolSlippage(slippage); }

    void UpdatePerSymbolMagicNumber(const long magicNumber) { m_symbolRegistry.UpdatePerSymbolMagicNumber(magicNumber); }

    void UpdatePerSymbolFillMode(const ENUM_ORDER_TYPE_FILLING mode) { m_symbolRegistry.UpdatePerSymbolFillMode(mode); }

    void UpdatePerSymbolAsyncMode(const bool enabled) { m_symbolRegistry.UpdatePerSymbolAsyncMode(enabled); }

    void SetMagicOffsetForSymbol(const string symbol, int offset) { m_symbolRegistry.SetMagicOffsetForSymbol(symbol, offset); }

    int GetMagicOffsetForSymbol(const string symbol) const { return m_symbolRegistry.GetMagicOffsetForSymbol(symbol); }
    void SetOrderFillMode(const ENUM_ORDER_TYPE_FILLING mode) { m_orderFillMode = mode; m_trade.SetTypeFilling(m_orderFillMode); UpdatePerSymbolFillMode(m_orderFillMode); }
    void SetProtectiveModifyCooldownSeconds(const int seconds) { m_minModifyIntervalSec = MathMax(1, seconds); }
    void SetLogLevel(const int level) { m_logLevel = MathMax(0, MathMin(4, level)); }

    void SetDynamicSlippageConfig(const bool enable, const double atrPercent, const uint minPoints,
                                   const uint maxMultiplier, const int atrPeriod)
    {
        m_enableDynamicSlippage = enable;
        m_dynamicSlippageAtrPercent = MathMax(0.05, MathMin(0.5, atrPercent));
        m_dynamicSlippageMinPoints = MathMax(1, minPoints);
        m_dynamicSlippageMaxMultiplier = MathMax(1, maxMultiplier);
        m_dynamicSlippageAtrPeriod = MathMax(1, atrPeriod);
    }

    void SetExecutionCostLimits(const double maxEntrySpreadPoints, const double maxEntryDriftPoints)
    {
        m_maxEntrySpreadPoints = MathMax(0.0, maxEntrySpreadPoints);
        m_maxEntryDriftPoints = MathMax(0.0, maxEntryDriftPoints);
    }

    void SetAsyncMode(bool enabled) { m_asyncExecutor.SetAsyncModeEnabled(enabled); m_trade.SetAsyncMode(m_asyncExecutor.IsAsyncModeEnabled()); UpdatePerSymbolAsyncMode(m_asyncExecutor.IsAsyncModeEnabled()); }

    bool SendTradeAsync(ENUM_ORDER_TYPE orderType, const string symbol,
                        double lot, double price, double sl, double tp,
                        ulong magic, int timeoutMs = 5000);

    // Process trade transaction event (call from OnTradeTransaction)
    void ProcessTradeTransaction(const MqlTradeTransaction &trans,
                                const MqlTradeRequest &request,
                                const MqlTradeResult &result);

    // Check for timed-out async trades (call from OnTimer)
    void CheckAsyncTimeouts();

    int  GetPendingAsyncCount() const;

    ulong GetPendingAsyncTicket(int index) const;

    void PersistAsyncTradeRequest(const SAsyncTradeRequest &asyncTrade);

    void ReplayAsyncTradeRequests();

    bool IsDuplicateIdempotencyKey(const string key) const;

    void CleanupPersistedAsyncTrades();

    uint GetDynamicSlippage(const string symbol)
    {
        if(!m_enableDynamicSlippage)
        {
            return m_baseSlippage;
        }

        if(m_marketAnalysis == NULL)
        {
            return m_baseSlippage;
        }

        double atrValue = m_atrCache.GetATR(symbol, PERIOD_M15);
                if(atrValue == EMPTY_VALUE || atrValue <= 0.0)
                {
                    atrValue = m_marketAnalysis.GetATR(symbol, m_dynamicSlippageAtrPeriod);
                    if(atrValue > 0.0)
                    {
                        datetime barTime = iTime(symbol, PERIOD_M15, 0);
                        m_atrCache.StoreATR(symbol, PERIOD_M15, atrValue, barTime);
                    }
        }
        if(atrValue <= 0.0)
        {
            return m_baseSlippage;
        }

        double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(pointValue <= 0.0)
        {
            pointValue = m_symbolInfo.Point();
        }
        if(pointValue <= 0.0)
        {
            return m_baseSlippage;
        }

        double atrPoints = atrValue / pointValue;

        uint dynamicSlippage = (uint)MathRound(atrPoints * m_dynamicSlippageAtrPercent);

        uint minSlippage = MathMax(m_dynamicSlippageMinPoints, m_baseSlippage);
        uint maxSlippage = m_baseSlippage * m_dynamicSlippageMaxMultiplier;

        // Clamp using conditional since MathMin/MathMax don't work directly with uint cast
        double clamped = dynamicSlippage;
        if(clamped < (double)minSlippage) clamped = (double)minSlippage;
        if(clamped > (double)maxSlippage) clamped = (double)maxSlippage;
        return (uint)clamped;
    }

    void UpdateDynamicSlippage(const string symbol)
    {
        if(!m_enableDynamicSlippage)
        {
            return;
        }

        uint dynamicSlippage = GetDynamicSlippage(symbol);
        if(dynamicSlippage != m_slippage)
        {
            m_slippage = dynamicSlippage;
            m_trade.SetDeviationInPoints(m_slippage);
            UpdatePerSymbolSlippage(m_slippage);
        }
    }

    bool OpenPosition(const string symbol,
                     const ENUM_ORDER_TYPE orderType,
                     const double volume,
                     const double price,
                     const double stopLossPips,
                     const double takeProfitPips,
                     const string comment = "",
                     const uint magicNumber = 0);

    bool ClosePosition(const ulong ticket, const string reason = "Manual close");
    bool ClosePositionPartial(const ulong ticket, double volume, const string reason = "Partial close");
    //--- EA-scoped by default: flattenAllAccountPositions is the only way to close positions this EA did not open.
    bool CloseAllPositions(const string symbol = "", const string reason = "Close all",
                           const bool flattenAllAccountPositions = false);

    bool ModifyPosition(const ulong ticket,
                       const double newStopLoss,
                       const double newTakeProfit);

    void ManageAllPositions(const double breakevenBuffer = 20.0,
                           const double trailingDistance = 50.0,
                           const double trailingStep = 10.0,
                           const bool useATRTrailing = false,
                           const double atrMultiplier = 2.0);

    bool SetTrailingStop(const ulong ticket, const double distance, const double step, const bool useATR = false, const double atrMult = 2.0);
    bool MoveToBreakeven(const ulong ticket, const double buffer);

    double NormalizePrice(const string symbol, const double price);
    double NormalizeVolume(const string symbol, const double volume);
    double CalculateStopLoss(const string symbol, const ENUM_ORDER_TYPE orderType, const double price, const double stopLossPips);
    double CalculateTakeProfit(const string symbol, const ENUM_ORDER_TYPE orderType, const double price, const double takeProfitPips);
    ulong GetLastTicket() const { return (m_lastTradeResult.order > 0) ? m_lastTradeResult.order : m_trade.ResultOrder(); }
    double GetLastRequestedPrice() const { return m_lastRequestedPrice; }
    uint GetLastRetcode() const { return m_lastTradeResult.retcode; }
    void GetLastExecutionReceipt(STradeExecutionReceipt &receipt) const { receipt = m_lastExecutionReceipt; }

    // Check and resolve pending execution confirmations (call from main tick loop)
    void CheckPendingConfirmations() { m_confirmationQueue.CheckPendingConfirmations(); }

    void GetTradeStatistics(int &total, int &successful, int &failed, double &successRate)
    {
        m_tradeStats.GetTradeStatistics(total, successful, failed, successRate);
    }

    void ResetStatistics(void)
    {
        m_tradeStats.ResetStatistics();
        m_totalTrades = 0;
        m_successfulTrades = 0;
        m_failedTrades = 0;
        m_lastTradeTime = 0;
    }

    void GetExecutionQualityMetrics(int &totalOrders, int &filledOrders, int &partialFills, int &rejectedOrders,
                                     double &avgSlippagePoints, double &avgLatencyMs, double &fillRate)
    {
        m_execQuality.GetExecutionQualityMetrics(totalOrders, filledOrders, partialFills, rejectedOrders,
                                                 avgSlippagePoints, avgLatencyMs, fillRate);
    }

    void GetExecutionQualitySummary(string &summary)
    {
        m_execQuality.GetExecutionQualitySummary(summary, m_logLevel);
    }

    void ResetExecutionMetrics()
    {
        m_execQuality.ResetExecutionMetrics();
    }

    void GenerateExecutionQualityReport()
    {
        m_execQuality.GenerateExecutionQualityReport(m_logLevel,
                                                     m_enableDynamicSlippage,
                                                     m_dynamicSlippageAtrPercent,
                                                     m_dynamicSlippageMinPoints,
                                                     m_dynamicSlippageMaxMultiplier,
                                                     m_slippage);
    }

    struct SSmartOrderParams {
        uint recommendedSlippage;
        ENUM_ORDER_TYPE_FILLING recommendedFillMode;
        bool shouldTrade;
        string reason;
    };

    SSmartOrderParams AnalyzeAndRecommendOrderParams(const string symbol)
    {
        SSmartOrderParams params;
        params.recommendedSlippage = m_baseSlippage;
        params.recommendedFillMode = m_orderFillMode;
        params.shouldTrade = true;
        params.reason = "";

        if(m_execQuality.TotalOrders() < 5)
        {
            params.reason = "Insufficient execution history for analysis";
            return params;
        }

        double fillRate = (double)m_execQuality.FilledOrders() / m_execQuality.TotalOrders();

        double avgSlippage = 0.0;
        if(m_execQuality.FilledOrders() > 0)
        {
            avgSlippage = m_execQuality.TotalSlippagePoints() / m_execQuality.FilledOrders();
        }

        double avgLatency = 0.0;
        if(m_execQuality.FilledOrders() > 0 && m_execQuality.TotalLatencyMs() > 0)
        {
            avgLatency = m_execQuality.TotalLatencyMs() / m_execQuality.FilledOrders();
        }

        long currentSpread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);


        if(fillRate < 0.8)
        {
            params.recommendedSlippage = (uint)MathMax(m_baseSlippage * 2, avgSlippage * 1.5);
            params.recommendedFillMode = ORDER_FILLING_FOK;
            params.reason = StringFormat("Low fill rate (%.1f%%), increasing slippage to %d",
                                        fillRate * 100, params.recommendedSlippage);
        }
        else if(avgSlippage > m_baseSlippage * 2)
        {
            params.recommendedSlippage = (uint)(avgSlippage * 1.2);
            params.reason = StringFormat("High avg slippage (%.1f pts), increasing tolerance to %d",
                                        avgSlippage, params.recommendedSlippage);
        }
        else if(avgLatency > 500)
        {
            params.recommendedFillMode = ORDER_FILLING_IOC;
            params.reason = StringFormat("High latency (%.0f ms), using IOC fill mode", avgLatency);
        }
        else if(currentSpread > m_maxEntrySpreadPoints)
        {
            params.shouldTrade = false;
            params.reason = StringFormat("Spread too high (%d pts > %.0f limit)",
                                        currentSpread, m_maxEntrySpreadPoints);
        }
        else if(m_execQuality.FilledOrders() > 0 &&
                (double)m_execQuality.PartialFills() / m_execQuality.FilledOrders() > 0.2)
        {
            params.recommendedFillMode = ORDER_FILLING_FOK;
            params.reason = "High partial fill rate, using FOK mode";
        }
        else
        {
            params.reason = "Execution quality acceptable, using standard parameters";
        }

        return params;
    }


private:
    bool NormalizeAndValidateStops(const string symbol, const ENUM_ORDER_TYPE orderType, const double price, const double tp, double &slOut, double &tpOut, string &errorMsg);
    bool IsOrderTypeAllowedForSymbol(const string symbolName, const ENUM_ORDER_TYPE orderType, string &reason);
    double CalculatePositionRisk(const string symbolParam, const double volume, const double stopLossPips);
    double GetCurrentExecutionPrice(const string symbolName, const ENUM_ORDER_TYPE orderType);
    CTrade* GetSymbolTrade(const string symbol);
public:
    double GetMinimumStopDistance(const string symbolName);
    bool ExecuteMarketOrder(const string symbol, const ENUM_ORDER_TYPE orderType,
                           const double volume, const double requestedPrice,
                           const double stopLossPips,
                           const double takeProfitPips,
                           const string comment);

    void UpdatePerformanceMetrics(const ulong ticket, const double profit, const bool isWin);

    void LogTradeOperation(const string operation, const string symbolName, const ENUM_ORDER_TYPE orderType, const double volume, const bool success, const string details = "");

    bool ShouldMoveToBreakeven(const ulong ticket, const double buffer);
    bool ShouldUpdateTrailingStop(const ulong ticket, const double distance, const double step);

    void UpdateExecutionMetrics(const STradeExecutionReceipt &receipt) { m_execQuality.UpdateExecutionMetrics(receipt); }

    double CalculateSpreadCost(const string symbol, const double volume) { return CTradeSpreadCostModel::CalculateSpreadCost(symbol, volume); }

    ENUM_ORDER_TYPE OrderTypeFromString(const string orderTypeStr) const { return CTradeDescriptor::OrderTypeFromString(orderTypeStr); }

    double GetRoundTripCommissionCost(const string symbol, const double volume);
    double GetEstimatedSwapCost(const string symbol, const ENUM_ORDER_TYPE orderType,
                               const double volume, const int estimatedHoldDays);
};

bool CTradeManager::Initialize(const long magicNumber,
                              const string expertName)
{
    m_magicNumber = magicNumber;
    m_expertName = expertName;

    m_trade.SetExpertMagicNumber(m_magicNumber);
    m_trade.SetDeviationInPoints(m_slippage);
    m_trade.SetTypeFilling(m_orderFillMode);
    m_trade.SetAsyncMode(m_useAsyncMode);
    ZeroMemory(m_lastTradeResult);
    m_lastRequestedPrice = 0.0;
    m_lastRequestedStopLoss = 0.0;
    m_lastRequestedTakeProfit = 0.0;
    m_lastExecutionReceipt = STradeExecutionReceipt();
    m_pendingExplicitMagic = 0;

    m_symbolRegistry.ResetSymbolTrades();

    InitializeMarginMode();

    return true;
    }

    void CTradeManager::Deinit()
    {
        CleanupPersistedAsyncTrades();
    
        m_atrCache.Reset();
    
        m_asyncExecutor.FreePending();
        m_symbolRegistry.FreeMagicOffsets();

        m_confirmationQueue.Clear();
    
        Print("[TRADE-MANAGER] Deinit complete - async trades cleaned up");
            }

        CTrade* CTradeManager::GetSymbolTrade(const string symbol)
        {
            // Pool owned by CTradeMgrSymbolTradeRegistry; config is passed in so it holds no back-pointer to CTradeManager.
            return m_symbolRegistry.GetSymbolTrade(symbol, m_magicNumber, m_slippage, m_orderFillMode, m_useAsyncMode);
        }

bool CTradeManager::MoveToBreakeven(const ulong ticket, const double buffer)
{
    if(!PositionSelectByTicket(ticket)) return false;

    string positionSymbol = m_positionInfo.Symbol();
    double openPrice = m_positionInfo.PriceOpen();
    double currentSL = m_positionInfo.StopLoss();
    double currentTP = m_positionInfo.TakeProfit();
    double point = SymbolInfoDouble(positionSymbol, SYMBOL_POINT);
    double digits = (double)SymbolInfoInteger(positionSymbol, SYMBOL_DIGITS);

    double newSL = 0.0;
    bool shouldUpdate = false;

    if(m_positionInfo.PositionType() == POSITION_TYPE_BUY)
    {
        newSL = openPrice + (buffer * point);
        double bid = SymbolInfoDouble(positionSymbol, SYMBOL_BID);

        if(bid > openPrice + (buffer * point))
        {
            if(newSL > currentSL) shouldUpdate = true;
        }
    }
    else if(m_positionInfo.PositionType() == POSITION_TYPE_SELL)
    {
        newSL = openPrice - (buffer * point);
        double ask = SymbolInfoDouble(positionSymbol, SYMBOL_ASK);

        if(ask < openPrice - (buffer * point))
        {
            if(currentSL == 0 || newSL < currentSL) shouldUpdate = true;
        }
    }

    if(!shouldUpdate) return false;

    newSL = NormalizeDouble(newSL, (int)digits);

    if(!IsModificationNeeded(ticket, newSL, currentTP)) return false;

    PrintFormat("[BE-APPLIED] %s | ticket=%d | SL %.5f -> %.5f | buffer=%.0f pts",
                positionSymbol, ticket, currentSL, newSL, buffer);

    double diagPrice = 0;
    if(m_positionInfo.PositionType() == POSITION_TYPE_BUY)
        diagPrice = SymbolInfoDouble(positionSymbol, SYMBOL_BID);
    else
        diagPrice = SymbolInfoDouble(positionSymbol, SYMBOL_ASK);
    PrintFormat("[BE-DIAG] %s | ticket=%d | open=%.5f | price=%.5f | newSL=%.5f",
                positionSymbol, ticket, openPrice, diagPrice, newSL);

    return ModifyPosition(ticket, newSL, currentTP);
}

bool CTradeManager::ClosePosition(const ulong ticket, const string reason)
{
    if(!PositionSelectByTicket(ticket))
    {
        return false;
    }

    string localSymbol = m_positionInfo.Symbol();

    // Read TP/SL/open price before the close: the position is gone once PositionClose succeeds.
    double posTP = m_positionInfo.TakeProfit();
    double posSL = m_positionInfo.StopLoss();
    double posOpenPrice = m_positionInfo.PriceOpen();

    // Only DISABLED blocks a close - CLOSEONLY still allows closing positions.
    ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(localSymbol, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
    {
        PrintFormat("[POSITION-MANAGEMENT] Skipping position closure for %s - trading disabled (trade mode: %s)",
                    localSymbol, EnumToString(tradeMode));
        return false;
    }

    ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)m_positionInfo.Type();
    double volume = m_positionInfo.Volume();
    double profit = m_positionInfo.Profit();

    CTrade* symbolTrade = GetSymbolTrade(localSymbol);
    bool result = symbolTrade.PositionClose(ticket);

    if(result)
    {
        RemoveEAOwnedPosition(ticket);

        long journalMagic = (long)PositionGetInteger(POSITION_MAGIC);
        double exitPrice = (orderType == ORDER_TYPE_BUY)
                              ? SymbolInfoDouble(localSymbol, SYMBOL_BID)
                              : SymbolInfoDouble(localSymbol, SYMBOL_ASK);
        JournalTradeClose(ticket, localSymbol, orderType, volume, exitPrice,
                          posSL, posTP, journalMagic, profit, reason);

        // TP/SL calibration warning: if closed by profit-target before TP hit, log remaining distance
        if(posTP > 0.0 && reason != "")
        {
            double currentPrice = (orderType == ORDER_TYPE_BUY)
                                  ? SymbolInfoDouble(localSymbol, SYMBOL_BID)
                                  : SymbolInfoDouble(localSymbol, SYMBOL_ASK);
            if(currentPrice > 0.0)
            {
                double pointCal = SymbolInfoDouble(localSymbol, SYMBOL_POINT);
                if(pointCal <= 0.0)
                    pointCal = 0.00001;
                double distRemainingTP = MathAbs(posTP - currentPrice) / pointCal;
                double originalDistTP = MathAbs(posTP - posOpenPrice) / pointCal;
                if(distRemainingTP > 0.0 && originalDistTP > 0.0)
                {
                    PrintFormat("[TP-CALIBRATION-WARNING] %s | Closed before TP hit. TP dist remaining: %.0f pts (%.1f%% of original %.0f pts) | reason=%s",
                                localSymbol, distRemainingTP, distRemainingTP / originalDistTP * 100.0, originalDistTP, reason);
                }
            }
        }

        LogTradeOperation("CLOSE", localSymbol, orderType, volume, true,
                         StringFormat("Profit: %.2f, Reason: %s", profit, reason));

        UpdatePerformanceMetrics(ticket, profit, profit > 0);
    }
    else
    {
        LogTradeOperation("CLOSE", localSymbol, orderType, volume, false,
                         "Close failed - " + IntegerToString(GetLastError()));
    }

    return result;
}

bool CTradeManager::ClosePositionPartial(const ulong ticket, double volume, const string reason)
{
    if(volume <= 0)
        return false;

    if(!PositionSelectByTicket(ticket))
        return false;

    string symbol = m_positionInfo.Symbol();

    if(!IsMarketOpen(symbol))
    {
        LogTradeOperation("PARTIAL_CLOSE", symbol, (ENUM_ORDER_TYPE)m_positionInfo.Type(), volume, false,
                         StringFormat("[SESSION-REJECT] Market closed for %s", symbol));
        return false;
    }

    double positionVolume = m_positionInfo.Volume();

    double normalizedVolume = NormalizeVolume(symbol, volume);
    if(normalizedVolume <= 0 || normalizedVolume >= positionVolume)
    {
        LogTradeOperation("PARTIAL_CLOSE", symbol, (ENUM_ORDER_TYPE)m_positionInfo.Type(), volume, false,
                         StringFormat("Invalid volume: %.2f (Position: %.2f)", normalizedVolume, positionVolume));
        return false;
    }

    CTrade* symbolTrade = GetSymbolTrade(symbol);
    bool result = symbolTrade.PositionClosePartial(ticket, normalizedVolume);

    ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)m_positionInfo.Type();

    if(result)
    {
        LogTradeOperation("PARTIAL_CLOSE", symbol, orderType, normalizedVolume, true,
                          StringFormat("Reason: %s", reason));
    }
    else
    {
        // Report the sending instance retcode: m_trade is unused here, so its last retcode is another operation's.
        uint retcode = symbolTrade.ResultRetcode();
        LogTradeOperation("PARTIAL_CLOSE", symbol, orderType, normalizedVolume, false,
                          StringFormat("Partial close failed - retcode=%u (%s) | err=%d",
                                       retcode, GetTradeErrorDescription(retcode), GetLastError()));
    }

    return result;
}
bool CTradeManager::CloseAllPositions(const string symbolParam, const string reason,
                                      const bool flattenAllAccountPositions)
{
    int totalPositions = PositionsTotal();
    int closedCount = 0;
    int skippedForeign = 0;
    bool allSuccess = true;
    datetime closeStartTime = TimeCurrent();
    const int TIMEOUT_SECONDS = 10;

    for(int i = totalPositions - 1; i >= 0; i--)
    {
        if(TimeCurrent() - closeStartTime > TIMEOUT_SECONDS)
        {
            PrintFormat("[TRADE-MANAGER] CloseAllPositions timeout after %d seconds, %d/%d positions closed",
                        TIMEOUT_SECONDS, closedCount, totalPositions);
            return false;
        }

        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            // Emergency flatten path: closes only EA-owned magics unless flattenAllAccountPositions is opted in,
            // otherwise a circuit-breaker trip would also close the user's manual trades and other EAs' books.
            if(!flattenAllAccountPositions &&
               !IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
            {
                skippedForeign++;
                continue;
            }

            if(symbolParam == "" || PositionGetString(POSITION_SYMBOL) == symbolParam)
            {
                if(ClosePosition(ticket, reason))
                    closedCount++;
                else
                    allSuccess = false;
            }
        }
    }

    if(closedCount > 0)
        PrintFormat("[TRADE-MANAGER] CloseAllPositions completed: %d positions closed", closedCount);
    if(skippedForeign > 0)
        PrintFormat("[TRADE-MANAGER] CloseAllPositions skipped %d foreign position(s) (not EA-owned magic) | flatten_all=%s",
                    skippedForeign, flattenAllAccountPositions ? "true" : "false");

    ClearEAOwnedPositions();

    return allSuccess;
}

bool CTradeManager::ModifyPosition(const ulong ticket, const double stopLoss, const double takeProfit)
{
    if(!PositionSelectByTicket(ticket))
    {
        return false;
    }

    string symbol = PositionGetString(POSITION_SYMBOL);

    // Only DISABLED blocks a modify - CLOSEONLY still allows changing stops.
    ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
    {
        PrintFormat("[POSITION-MANAGEMENT] Skipping position modification for %s ticket=%d - trading disabled (trade mode: %s)",
                    symbol, ticket, EnumToString(tradeMode));
        return false;
    }
    double positionPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double minDistance = GetMinimumStopDistance(symbol);
    if(minDistance < point * 10) minDistance = point * 10; // Minimum 10 points fallback
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double referencePrice = positionPrice;
    if(posType == POSITION_TYPE_BUY && bid > 0.0)
        referencePrice = bid;
    else if(posType == POSITION_TYPE_SELL && ask > 0.0)
        referencePrice = ask;

    double modifyCushion = MathMax(point * 2.0, minDistance * 0.05);
    double requiredDistance = minDistance + modifyCushion;
    if(requiredDistance < point * 12.0)
        requiredDistance = point * 12.0;

    double adjustedSL = stopLoss;
    double adjustedTP = takeProfit;
    bool slAdjusted = false;
    bool tpAdjusted = false;

    // Auto-normalize SL distance to broker constraints instead of repeatedly skipping.
    if(adjustedSL > 0)
    {
        double slDistance = MathAbs(referencePrice - adjustedSL);
        if(slDistance < requiredDistance)
        {
            if(posType == POSITION_TYPE_BUY)
                adjustedSL = referencePrice - requiredDistance;
            else
                adjustedSL = referencePrice + requiredDistance;

            adjustedSL = NormalizeDouble(adjustedSL, digits);
            slAdjusted = true;
        }
    }

    if(adjustedTP > 0)
    {
        double tpDistance = MathAbs(referencePrice - adjustedTP);
        if(tpDistance < requiredDistance)
        {
            if(posType == POSITION_TYPE_BUY)
                adjustedTP = referencePrice + requiredDistance;
            else
                adjustedTP = referencePrice - requiredDistance;

            adjustedTP = NormalizeDouble(adjustedTP, digits);
            tpAdjusted = true;
        }
    }

    // Normalize requested stop levels before any comparisons or server calls.
    if(adjustedSL > 0)
        adjustedSL = NormalizeDouble(adjustedSL, digits);
    if(adjustedTP > 0)
        adjustedTP = NormalizeDouble(adjustedTP, digits);

    if(currentSL > 0.0)
    {
        bool loosens = (adjustedSL <= 0.0) ||
                       (posType == POSITION_TYPE_BUY && adjustedSL < currentSL) ||
                       (posType == POSITION_TYPE_SELL && adjustedSL > currentSL);
        if(loosens)
        {
            PrintFormat("[TRADE-GUARD] ModifyPosition refused to loosen SL | Symbol: %s | current=%.5f requested=%.5f",
                        symbol, currentSL, adjustedSL);
            adjustedSL = currentSL;
            slAdjusted = false;
        }
    }

    if(adjustedSL > 0)
    {
        if(posType == POSITION_TYPE_BUY && adjustedSL >= referencePrice)
        {
            PrintFormat("[TRADE-REJECT] ModifyPosition skipped - BUY SL above executable price: SL=%.5f, Price=%.5f", adjustedSL, referencePrice);
            return false;
        }
        if(posType == POSITION_TYPE_SELL && adjustedSL <= referencePrice)
        {
            PrintFormat("[TRADE-REJECT] ModifyPosition skipped - SELL SL below executable price: SL=%.5f, Price=%.5f", adjustedSL, referencePrice);
            return false;
        }
    }

    if(adjustedTP > 0)
    {
        if(posType == POSITION_TYPE_BUY && adjustedTP <= referencePrice)
        {
            PrintFormat("[TRADE-REJECT] ModifyPosition skipped - BUY TP below/at executable price: TP=%.5f, Price=%.5f", adjustedTP, referencePrice);
            return false;
        }
        if(posType == POSITION_TYPE_SELL && adjustedTP >= referencePrice)
        {
            PrintFormat("[TRADE-REJECT] ModifyPosition skipped - SELL TP above/at executable price: TP=%.5f, Price=%.5f", adjustedTP, referencePrice);
            return false;
        }
    }

    // Skip redundant server requests when requested levels are already in place.
    double comparisonTolerance = point * 0.5;
    bool slUnchanged = (adjustedSL == 0.0 && currentSL == 0.0) || MathAbs(adjustedSL - currentSL) <= comparisonTolerance;
    bool tpUnchanged = (adjustedTP == 0.0 && currentTP == 0.0) || MathAbs(adjustedTP - currentTP) <= comparisonTolerance;
    if(slUnchanged && tpUnchanged)
    {
        UpdatePositionState(ticket, currentSL, currentTP);
        return true;
    }

    if(!IsModificationNeeded(ticket, adjustedSL, adjustedTP))
    {
        return true;
    }

    if(slAdjusted || tpAdjusted)
    {
        PrintFormat("[TRADE-INFO] ModifyPosition normalized stops | Symbol: %s | SL: %.5f | TP: %.5f | RequiredDistance: %.5f",
                    symbol, adjustedSL, adjustedTP, requiredDistance);
    }

    CTrade* symbolTrade = GetSymbolTrade(symbol);
    if(symbolTrade.PositionModify(ticket, adjustedSL, adjustedTP))
    {
        UpdatePositionState(ticket, adjustedSL, adjustedTP);
            LogTradeOperation("MODIFY", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), true,
                         StringFormat("SL=%.5f TP=%.5f", adjustedSL, adjustedTP));
        return true;
    }

    MqlTradeResult tradeResult;
    symbolTrade.Result(tradeResult);
    if(tradeResult.retcode == TRADE_RETCODE_NO_CHANGES)
    {
        UpdatePositionState(ticket, adjustedSL, adjustedTP);
        LogTradeOperation("MODIFY_NOOP", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), true,
                         StringFormat("Already at SL=%.5f TP=%.5f", adjustedSL, adjustedTP));
        return true;
    }

    if(tradeResult.retcode == TRADE_RETCODE_INVALID_STOPS)
    {
        double retryBid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double retryAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double retryReferencePrice = referencePrice;
        if(posType == POSITION_TYPE_BUY && retryBid > 0.0)
            retryReferencePrice = retryBid;
        else if(posType == POSITION_TYPE_SELL && retryAsk > 0.0)
            retryReferencePrice = retryAsk;

        double retryDistance = requiredDistance + MathMax(point * 2.0, requiredDistance * 0.10);
        double retrySL = adjustedSL;
        double retryTP = adjustedTP;

        if(retrySL > 0.0)
        {
            if(posType == POSITION_TYPE_BUY)
                retrySL = NormalizeDouble(MathMin(retrySL, retryReferencePrice - retryDistance), digits);
            else
                retrySL = NormalizeDouble(MathMax(retrySL, retryReferencePrice + retryDistance), digits);
        }

        if(retryTP > 0.0)
        {
            if(posType == POSITION_TYPE_BUY)
                retryTP = NormalizeDouble(MathMax(retryTP, retryReferencePrice + retryDistance), digits);
            else
                retryTP = NormalizeDouble(MathMin(retryTP, retryReferencePrice - retryDistance), digits);
        }

        bool retryChanged = (MathAbs(retrySL - adjustedSL) > comparisonTolerance ||
                             MathAbs(retryTP - adjustedTP) > comparisonTolerance);
        if(retryChanged)
        {
            PrintFormat("[TRADE-INFO] ModifyPosition retry widened stops | Symbol: %s | SL: %.5f | TP: %.5f | RequiredDistance: %.5f",
                        symbol, retrySL, retryTP, retryDistance);
            if(symbolTrade.PositionModify(ticket, retrySL, retryTP))
            {
                UpdatePositionState(ticket, retrySL, retryTP);
                LogTradeOperation("MODIFY_ADJUSTED", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), true,
                                 StringFormat("SL=%.5f TP=%.5f (widened to meet broker min distance)", retrySL, retryTP));
                return true;
            }
            symbolTrade.Result(tradeResult);
            if(tradeResult.retcode == TRADE_RETCODE_NO_CHANGES)
            {
                UpdatePositionState(ticket, retrySL, retryTP);
                LogTradeOperation("MODIFY_NOOP", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), true,
                                 StringFormat("Already at widened SL=%.5f TP=%.5f", retrySL, retryTP));
                return true;
            }
        }
    }

    LogTradeOperation("MODIFY_FAILED", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), false,
                     StringFormat("SL=%.5f TP=%.5f | retcode=%u", adjustedSL, adjustedTP, tradeResult.retcode));
    LogTradeError(tradeResult, "ModifyPosition");

    return false;
}

bool CTradeManager::ExecuteMarketOrder(const string symbolName, const ENUM_ORDER_TYPE orderType,
                                      const double volume, const double requestedPrice,
                                      const double stopLossPips,
                                      const double takeProfitPips,
                                      const string comment)
{
    if(symbolName == "" || volume <= 0)
    {
        ResetExecutionReceipt(symbolName, volume);
        m_lastExecutionReceipt.note = "Invalid execution request";
        return false;
    }

    // Mandatory stop-loss gate: the execution layer rejects any send without an SL.
    if(stopLossPips <= 0.0)
    {
        LogError("EXECUTION BLOCKED: Stop-loss is mandatory. Trade rejected", symbolName);
        ResetExecutionReceipt(symbolName, volume);
        m_lastExecutionReceipt.note = "EXECUTION BLOCKED: Stop-loss is mandatory";
        PrintFormat("[EXECUTION-BLOCKED] %s | reason=MandatoryStopLoss | stopLossPips=%.1f",
                    symbolName, stopLossPips);
        return false;
    }

    ResetExecutionReceipt(symbolName, volume);
    bool executionConfirmed = false;
    int retryCount = 0;
    uint lastRetcode = 0;
    datetime executionStartTime = TimeCurrent();

    while(retryCount < MAX_TRADE_RETRIES && !executionConfirmed)
    {
        if(TimeCurrent() - executionStartTime > 15)
        {
            PrintFormat("[TRADE-TIMEOUT] %s | exceeded 15s after %d attempts | retcode=%u",
                        symbolName, retryCount, lastRetcode);
            m_lastExecutionReceipt.accepted = false;
            m_lastExecutionReceipt.note = "TIMEOUT: broker unresponsive after 15s";
            m_lastExecutionReceipt.retryCount = retryCount;
            break;
        }

        ApplyFillingModeForSymbol(symbolName);

            UpdateDynamicSlippage(symbolName);

        double executionPrice = GetCurrentExecutionPrice(symbolName, orderType);
        if(executionPrice <= 0.0)
        {
            executionPrice = NormalizePrice(symbolName, requestedPrice);
        }
        if(executionPrice <= 0.0)
        {
            LogError("Unable to resolve current execution price", symbolName);
            break;
        }

        string preflightReason = "";
        if(!ValidateExecutionPreflight(symbolName, orderType, executionPrice, requestedPrice, preflightReason))
        {
            m_lastExecutionReceipt.accepted = false;
            m_lastExecutionReceipt.retryCount = retryCount;
            m_lastExecutionReceipt.averagePrice = executionPrice;
            m_lastExecutionReceipt.note = preflightReason;
            PrintFormat("[EXECUTION-BLOCKED] %s | reason=%s | price=%.5f | volume=%.2f",
                        symbolName,
                        preflightReason,
                        executionPrice,
                        volume);
            break;
        }

        double stopLoss = 0.0;
        double takeProfit = 0.0;
        string errorMsg = "";

        if(stopLossPips > 0.0)
            stopLoss = CalculateStopLoss(symbolName, orderType, executionPrice, stopLossPips);
        if(takeProfitPips > 0.0)
            takeProfit = CalculateTakeProfit(symbolName, orderType, executionPrice, takeProfitPips);

        if(!NormalizeAndValidateStops(symbolName, orderType, executionPrice, takeProfit, stopLoss, takeProfit, errorMsg))
        {
            LogError("Invalid repriced stops: " + errorMsg, symbolName);
            break;
        }

        m_lastRequestedPrice = executionPrice;
        m_lastRequestedStopLoss = stopLoss;
        m_lastRequestedTakeProfit = takeProfit;
        m_lastExecutionReceipt.stopLoss = stopLoss;
        m_lastExecutionReceipt.takeProfit = takeProfit;
        m_lastExecutionReceipt.requestedPrice = executionPrice;
        m_lastExecutionReceipt.submitTime = TimeCurrent();

        CTrade* symbolTrade = GetSymbolTrade(symbolName);
        if(symbolTrade == NULL)
        {
            LogError("Per-symbol trade instance unavailable", symbolName);
            m_lastExecutionReceipt.accepted = false;
            m_lastExecutionReceipt.note = "No symbol trade instance";
            break;
        }

        ApplyFillingModeForSymbol(symbolName, symbolTrade);

        // Set deviation on this symbol's pooled instance: one shared m_slippage meant a send carried whichever
        // symbol was evaluated last, and a point's value differs between symbols.
        uint sendDeviation = m_enableDynamicSlippage ? GetDynamicSlippage(symbolName) : m_baseSlippage;
        symbolTrade.SetDeviationInPoints(sendDeviation);

        // Stamp the final magic before each send: the pool carries the bare base, so offsets never reached the broker.
        // An explicit override ships as-is (the engine bands precompute theirs); otherwise this is the consensus magic.
        ulong shipMagic = (m_pendingExplicitMagic > 0)
                          ? m_pendingExplicitMagic
                          : (ulong)(m_magicNumber + (long)GetMagicOffsetForSymbol(symbolName));
        symbolTrade.SetExpertMagicNumber(shipMagic);
        m_pendingExplicitMagic = 0;
        
        bool sendAccepted = false;
        ulong sendStartUs = GetMicrosecondCount();
        if(orderType == ORDER_TYPE_BUY)
        {
            sendAccepted = symbolTrade.Buy(volume, symbolName, executionPrice, stopLoss, takeProfit, comment);
        }
        else if(orderType == ORDER_TYPE_SELL)
        {
            sendAccepted = symbolTrade.Sell(volume, symbolName, executionPrice, stopLoss, takeProfit, comment);
        }

        MqlTradeResult tradeResult;
        symbolTrade.Result(tradeResult);
        ulong sendEndUs = GetMicrosecondCount();
        m_lastTradeResult = tradeResult;
        m_lastExecutionReceipt.retcode = tradeResult.retcode;
        m_lastExecutionReceipt.requestId = tradeResult.request_id;
        m_lastExecutionReceipt.orderTicket = tradeResult.order;
        m_lastExecutionReceipt.dealTicket = tradeResult.deal;
        m_lastExecutionReceipt.retryCount = retryCount;
        m_lastExecutionReceipt.averagePrice = (tradeResult.price > 0.0) ? tradeResult.price
                                     : (executionPrice > 0.0) ? executionPrice
                                     : m_lastExecutionReceipt.requestedPrice;
        m_lastExecutionReceipt.filledVolume = (tradeResult.volume > 0.0) ? tradeResult.volume : 0.0;
        m_lastExecutionReceipt.partialFill = false;
        m_lastExecutionReceipt.note = tradeResult.comment;
        if(sendEndUs >= sendStartUs)
            m_lastExecutionReceipt.roundTripMs = (sendEndUs - sendStartUs) / 1000;
        double pointSize = SymbolInfoDouble(symbolName, SYMBOL_POINT);
        // Guard against denormalized/zero point size to prevent NaN slippage
        if(pointSize <= 1e-15) pointSize = 1e-15;
        if(pointSize > 0.0 && m_lastExecutionReceipt.requestedPrice > 0.0 && m_lastExecutionReceipt.averagePrice > 0.0)
            m_lastExecutionReceipt.slippagePoints = MathAbs(m_lastExecutionReceipt.averagePrice - m_lastExecutionReceipt.requestedPrice) / pointSize;

        // Realized slippage is compared against the deviation the order was sent with: exceeding it is a real cost.
        if(m_lastExecutionReceipt.slippagePoints > (double)sendDeviation && m_lastExecutionReceipt.slippagePoints > 0.0)
        {
            PrintFormat("[EXECUTION-SLIPPAGE-EXCESS] %s | filled=%.5f vs requested=%.5f | slippage=%.1f pts > deviation=%.1f pts",
                        symbolName, m_lastExecutionReceipt.averagePrice, m_lastExecutionReceipt.requestedPrice,
                        m_lastExecutionReceipt.slippagePoints, (double)sendDeviation);
        }

        if(!sendAccepted)
        {
            m_lastExecutionReceipt.accepted = false;
            m_lastExecutionReceipt.averagePrice = executionPrice;
            LogTradeError(tradeResult, "ExecuteMarketOrder");

            string orderTypeStr = EnumToString(orderType);
            string failDetails = StringFormat("retcode=%u reason=%s price=%.5f",
                                             tradeResult.retcode,
                                             GetTradeErrorDescription(tradeResult.retcode),
                                             executionPrice);
            LogTradeOperation("OPEN", symbolName, orderType, volume, false, failDetails);

            uint retcode = tradeResult.retcode;
            lastRetcode = retcode;

            if(IsTransientTradeRetcode(retcode))
            {
                // A transient retcode (REQUOTE / PRICE_CHANGED / CONNECTION_LOSS) can follow a fill the server already
                // executed; resending opened a SECOND full-risk position. If this send's position exists, accept it.
                ulong dupTicket = 0;
                double dupVolume = 0.0;
                if(CTradeMgrPreflight::FindFreshPositionForSend(symbolName, orderType, volume,
                                                               dupTicket, dupVolume))
                {
                    m_lastExecutionReceipt.accepted = true;
                    m_lastExecutionReceipt.filledVolume = dupVolume;
                    m_lastExecutionReceipt.partialFill = (dupVolume + 1e-8 < volume);
                    m_lastExecutionReceipt.note = "dedup_position_exists";
                    executionConfirmed = true;
                    PrintFormat("[EXECUTION-DEDUP] %s | retcode=%u but position ticket=%I64u already exists (%.2f of %.2f lots) - refusing to resend",
                                symbolName, retcode, dupTicket, dupVolume, volume);
                    LogTradeOperation("OPEN", symbolName, orderType, dupVolume, true,
                                      StringFormat("retcode=%u dedup: position %I64u already open", tradeResult.retcode, dupTicket));
                    break;
                }

                retryCount++;
                if(retryCount < MAX_TRADE_RETRIES)
                {
                    PrintFormat("[EXECUTION-RETRY] %s | attempt=%d/%d | retcode=%u",
                                symbolName, retryCount + 1, MAX_TRADE_RETRIES, retcode);
                    m_symbolInfo.Refresh();
                }
                continue;
            }

            // LOCKED/FROZEN can persist; allow only one bounded retry to avoid prolonged stall loops.
            if(IsLimitedRetryRetcode(retcode) && retryCount == 0)
            {
                retryCount = 1;
                PrintFormat("[EXECUTION-RETRY] %s | retcode=%u | single_retry=1",
                            symbolName, retcode);
                m_symbolInfo.Refresh();
                continue;
            }

            break;
        }
        else
        {
            if(IsSuccessfulFillRetcode(tradeResult.retcode))
            {
                m_lastExecutionReceipt.accepted = true;
                if(m_lastExecutionReceipt.filledVolume <= 0.0)
                    m_lastExecutionReceipt.filledVolume = volume;
                m_lastExecutionReceipt.partialFill = ((tradeResult.retcode == TRADE_RETCODE_DONE_PARTIAL) ||
                                                      (m_lastExecutionReceipt.filledVolume > 0.0 &&
                                                       m_lastExecutionReceipt.filledVolume + 1e-8 < volume));
                executionConfirmed = true;
            }
            else
            {
                executionConfirmed = ConfirmExecutionReceipt(symbolName, orderType, volume, executionPrice, tradeResult);
            }

            lastRetcode = tradeResult.retcode;

            if(m_lastExecutionReceipt.partialFill)
            {
                PrintFormat("[PARTIAL-FILL] %s | requested=%.2f | filled=%.2f | retcode=%u",
                            symbolName,
                            volume,
                            m_lastExecutionReceipt.filledVolume,
                            m_lastExecutionReceipt.retcode);
            }

            PrintFormat("[EXECUTION-RECEIPT] %s | accepted=%s | requested=%.2f | filled=%.2f | price=%.5f | retcode=%u | retries=%d",
                        symbolName,
                        m_lastExecutionReceipt.accepted ? "true" : "false",
                        volume,
                        m_lastExecutionReceipt.filledVolume,
                        m_lastExecutionReceipt.averagePrice,
                        m_lastExecutionReceipt.retcode,
                        m_lastExecutionReceipt.retryCount);
            PrintFormat("[EXECUTION-TELEMETRY] %s | requested_price=%.5f | fill_price=%.5f | slippage_points=%.1f | latency_ms=%I64u | submit_time=%s",
                        symbolName,
                        m_lastExecutionReceipt.requestedPrice,
                        m_lastExecutionReceipt.averagePrice,
                        m_lastExecutionReceipt.slippagePoints,
                        m_lastExecutionReceipt.roundTripMs,
                        TimeToString(m_lastExecutionReceipt.submitTime, TIME_DATE | TIME_SECONDS));

            string orderTypeStr = EnumToString(orderType);
            string tradeDetails = StringFormat("price=%.5f sl=%.5f tp=%.5f slippage=%.1fpts latency=%I64ums retcode=%u",
                                              m_lastExecutionReceipt.averagePrice,
                                              stopLoss, takeProfit,
                                              m_lastExecutionReceipt.slippagePoints,
                                              m_lastExecutionReceipt.roundTripMs,
                                              m_lastExecutionReceipt.retcode);
            LogTradeOperation("OPEN", symbolName, orderType, m_lastExecutionReceipt.filledVolume, true, tradeDetails);

            if(stopLoss > 0.0 || takeProfit > 0.0)
            {
                double entryPrice = m_lastExecutionReceipt.averagePrice;
                if(entryPrice <= 0.0)
                    entryPrice = executionPrice;
                double pointCal = SymbolInfoDouble(symbolName, SYMBOL_POINT);
                if(pointCal <= 0.0)
                    pointCal = 0.00001;
                string dirStr = (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL";
                double distToTP = (takeProfit > 0.0) ? MathAbs(takeProfit - entryPrice) / pointCal : 0.0;
                double distToSL = (stopLoss > 0.0) ? MathAbs(stopLoss - entryPrice) / pointCal : 0.0;
                PrintFormat("[TP-SL-CALIBRATION] %s %s | entry=%.2f tp=%.2f sl=%.2f | distTP=%.0f pts distSL=%.0f pts | ratio=%.2f",
                            symbolName, dirStr, entryPrice, takeProfit, stopLoss, distToTP, distToSL,
                            distToSL > 0.0 ? distToTP / distToSL : 0.0);
            }
            if(!executionConfirmed && !m_lastExecutionReceipt.accepted)
            {
                PrintFormat("[EXECUTION-UNCONFIRMED] %s | request_id=%u | order=%I64u | deal=%I64u | retcode=%u | note=%s",
                            symbolName,
                            m_lastExecutionReceipt.requestId,
                            m_lastExecutionReceipt.orderTicket,
                            m_lastExecutionReceipt.dealTicket,
                            m_lastExecutionReceipt.retcode,
                            m_lastExecutionReceipt.note);
                break;
            }
        }
    }

    if(!executionConfirmed && retryCount >= MAX_TRADE_RETRIES)
        Print("[TRADE-FAILED] max retries exceeded");
    else if(!executionConfirmed && lastRetcode != 0)
        PrintFormat("[TRADE-FAILED] %s | retcode=%u | retries=%d", symbolName, lastRetcode, retryCount);

    if(!executionConfirmed)
        m_lastExecutionReceipt.retryCount = retryCount;

    UpdateExecutionMetrics(m_lastExecutionReceipt);

    return executionConfirmed;
}

double CTradeManager::NormalizePrice(const string symbolName, const double price)
{
    return CTradeMgrPricing::NormalizePrice(symbolName, price);
}

double CTradeManager::NormalizeVolume(const string symbolName, const double volume)
{
    return CTradeMgrPricing::NormalizeVolume(symbolName, volume);
}

double CTradeManager::CalculateStopLoss(const string symbolParam, const ENUM_ORDER_TYPE orderType,
                                       const double price, const double stopLossPips)
{
    return CTradeMgrPricing::CalculateStopLoss(symbolParam, orderType, price, stopLossPips);
}

double CTradeManager::CalculateTakeProfit(const string symbolParam, const ENUM_ORDER_TYPE orderType,
                                         const double price, const double takeProfitPips)
{
    return CTradeMgrPricing::CalculateTakeProfit(symbolParam, orderType, price, takeProfitPips);
}


bool CTradeManager::IsOrderTypeAllowedForSymbol(const string symbolName, const ENUM_ORDER_TYPE orderType, string &reason)
{
    return CTradeMgrPricing::IsOrderTypeAllowedForSymbol(symbolName, orderType, reason);
}

double CTradeManager::GetCurrentExecutionPrice(const string symbolName, const ENUM_ORDER_TYPE orderType)
{
    // m_symbolInfo is passed by reference because CTradeMgrPricing's fallback refreshes it in place.
    return CTradeMgrPricing::GetCurrentExecutionPrice(symbolName, orderType, m_symbolInfo);
}

// Broker minimum stop/freeze distance
double CTradeManager::GetMinimumStopDistance(const string symbolName)
{
    return CTradeMgrPricing::GetMinimumStopDistance(symbolName);
}


void CTradeManager::LogTradeOperation(const string operation, const string symbolName,
                                     const ENUM_ORDER_TYPE orderType, const double volume,
                                     const bool success, const string details)
{
    string message = StringFormat("%s %s %s %.2f lots - %s",
                                 operation, symbolName,
                                 EnumToString(orderType), volume,
                                 success ? "SUCCESS" : "FAILED");
    if(details != "")
        message += " | " + details;

    Print("[TRADE-OP] ", message);
}

bool CTradeManager::ShouldMoveToBreakeven(const ulong ticket, const double buffer)
{
    if(!PositionSelectByTicket(ticket))
        return false;

    double openPrice = m_positionInfo.PriceOpen();
    double currentPriceValue = (m_positionInfo.PositionType() == POSITION_TYPE_BUY) ?
                              SymbolInfoDouble(m_positionInfo.Symbol(), SYMBOL_BID) :
                              SymbolInfoDouble(m_positionInfo.Symbol(), SYMBOL_ASK);

    double point = SymbolInfoDouble(m_positionInfo.Symbol(), SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001; // Fallback for invalid symbol data
    double profitPoints = 0.0;

    if(m_positionInfo.PositionType() == POSITION_TYPE_BUY)
        profitPoints = (currentPriceValue - openPrice) / point;
    else
        profitPoints = (openPrice - currentPriceValue) / point;

    return (profitPoints >= buffer * 1.5);
}

bool CTradeManager::ShouldUpdateTrailingStop(const ulong ticket, const double distance, const double step)
{
    if(!PositionSelectByTicket(ticket))
        return false;

    double currentSL = m_positionInfo.StopLoss();
    if(currentSL <= 0)
        return false;

    string localSymbol = m_positionInfo.Symbol();
    double localCurrentPrice = (m_positionInfo.PositionType() == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(localSymbol, SYMBOL_BID) :
                         SymbolInfoDouble(localSymbol, SYMBOL_ASK);

    double point = SymbolInfoDouble(localSymbol, SYMBOL_POINT);
    double newSL = 0.0;

    if(m_positionInfo.PositionType() == POSITION_TYPE_BUY)
    {
        newSL = localCurrentPrice - (distance * point);
        return (newSL > currentSL + (step * point));
    }
    else
    {
        newSL = localCurrentPrice + (distance * point);
        return (newSL < currentSL - (step * point));
    }
}

double CTradeManager::CalculatePositionRisk(const string symbolParam, const double volume,
                                           const double stopLossPips)
{
    return CTradeMgrPricing::CalculatePositionRisk(symbolParam, volume, stopLossPips);
}


double CTradeManager::GetRoundTripCommissionCost(const string symbol, const double volume)
{
    return CTradeMgrPricing::GetRoundTripCommissionCost(symbol, volume);
}


double CTradeManager::GetEstimatedSwapCost(const string symbol, const ENUM_ORDER_TYPE orderType,
                                          const double volume, const int estimatedHoldDays)
{
    return CTradeMgrPricing::GetEstimatedSwapCost(symbol, orderType, volume, estimatedHoldDays);
}



void CTradeManager::UpdatePerformanceMetrics(const ulong ticket, const double profit, const bool isWin)
{
    // Runs after PositionClose - the live position no longer exists, so a PositionSelectByTicket gate here never passed.
    // Commission and swap come from deal history, which survives the close and captures the closing deal's commission.
    double commission = 0.0;
    double swap = 0.0;
    if(HistorySelectByPosition(ticket))
    {
        int totalDeals = HistoryDealsTotal();
        for(int i = 0; i < totalDeals; i++)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket > 0)
            {
                // POSITION_COMMISSION is deprecated; sum costs from deals
                commission += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                swap += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            }
        }
    }
    
    double netProfit = profit - commission - swap;
    
    m_tradeStats.RecordTrade(isWin, netProfit);

    // Legacy backward-compatibility mirrors â€?intentionally retained here
    m_totalTrades = m_tradeStats.TotalTrades();
    m_successfulTrades = m_tradeStats.SuccessfulTrades();
    m_failedTrades = m_tradeStats.FailedTrades();
    m_lastTradeTime = m_tradeStats.LastTradeTime();
}


void CTradeManager::LogTradeError(const MqlTradeResult &result, const string operation)
{
    string errorMsg = StringFormat("Trade Error: Code=%d, Comment=%s, Request ID=%d",
                                  (int)result.retcode, result.comment, (int)result.request_id);
    Print("[TRADE-ERROR] ", errorMsg);

    if(m_errorHandler != NULL)
    {
        SErrorContext context;
        context.component = "TradeManager";
        context.operation = operation;
        context.symbol = "";
        context.errorCode = (int)result.retcode;
        context.additionalInfo = errorMsg;
        context.timestamp = TimeCurrent();
        context.severity = ERROR_RECOVERABLE;
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_RECOVERABLE, context);
        }
    }
}

void CTradeManager::ManageAllPositions(const double breakevenBuffer,
                                       const double trailingDistance,
                                       const double trailingStep,
                                       const bool useATRTrailing,
                                       const double atrMultiplier)
{
    //--- Scan live positions through the ownership authority: the ticket cache only ever reaches positions this
    //--- process opened synchronously, so after a restart or an async fill surviving positions got no breakeven or trailing stop.
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;

        // Breakeven and trailing belong to whoever owns the exit: the scalp/grid/spike engines close and
        // partial-close their own positions, so moving their stops from here fought that engine.
        if(IsEngineManagedPosition(PositionGetString(POSITION_COMMENT))) continue;

        string symbolName = PositionGetString(POSITION_SYMBOL);
        double currentPriceValue = PositionGetDouble(POSITION_PRICE_CURRENT);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double stopLoss = PositionGetDouble(POSITION_SL);
        double takeProfit = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if(breakevenBuffer > 0)
        {
            MoveToBreakeven(ticket, breakevenBuffer);
        }

        if(useATRTrailing || (trailingDistance > 0 && trailingStep > 0))
        {
            SetTrailingStop(ticket, trailingDistance, trailingStep, useATRTrailing, atrMultiplier);
        }
    }
}

bool CTradeManager::SetTrailingStop(const ulong ticket, const double distance, const double step, const bool useATR, const double atrMult)
{
    if(ticket <= 0) return false;
    if(!PositionSelectByTicket(ticket)) return false;

    string symbolName = PositionGetString(POSITION_SYMBOL);
    double currentPriceValue = PositionGetDouble(POSITION_PRICE_CURRENT);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentStopLoss = PositionGetDouble(POSITION_SL);
    double currentTakeProfit = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    long positionMagic = (long)PositionGetInteger(POSITION_MAGIC);
    if(m_magicNumber > 0 && !IsEAOwnedMagic(positionMagic))
        return true;

    double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    double profitPoints = (type == POSITION_TYPE_BUY)
                          ? (currentPriceValue - openPrice) / point
                          : (openPrice - currentPriceValue) / point;
    if(profitPoints <= 0.0)
        return true;

    double newStopLoss = 0;
    // activationPoints = distance: the minimum profit that keeps the trailing stop above entry for a BUY.
    // Capped at 100 points (10 pips) so trailing activates on smaller forex moves.
    double activationPoints = MathMin(distance, 100.0);

    if(useATR)
    {
        double atr = CalculateATR(symbolName, PERIOD_CURRENT, 14);
        if(atr <= 0) return false;
        activationPoints = MathMax(activationPoints, (atr / point) * MathMax(0.3, atrMult * 0.20));
        if(profitPoints < activationPoints)
            return true;

        if(type == POSITION_TYPE_BUY)
        {
            double atrStop = currentPriceValue - (atr * atrMult);
            if(currentStopLoss < atrStop - (atr * 0.1)) // 10% of ATR step
                newStopLoss = atrStop;
        }
        else
        {
            double atrStop = currentPriceValue + (atr * atrMult);
            if(currentStopLoss > atrStop + (atr * 0.1) || currentStopLoss == 0)
                newStopLoss = atrStop;
        }
    }
    else if(distance > 0 && step > 0)
    {
        if(profitPoints < activationPoints)
            return true;

        if(type == POSITION_TYPE_BUY)
        {
            double minStopLoss = currentPriceValue - distance * point;
            if(currentStopLoss < minStopLoss - step * point)
            {
                newStopLoss = minStopLoss;
            }
        }
        else
        {
            double maxStopLoss = currentPriceValue + distance * point;
            if(currentStopLoss > maxStopLoss + step * point || currentStopLoss == 0)
            {
                newStopLoss = maxStopLoss;
            }
        }
    }

    if(newStopLoss > 0 && MathAbs(newStopLoss - currentStopLoss) > point * 0.5)
    {
        newStopLoss = NormalizePrice(symbolName, newStopLoss);
        bool trailResult = ModifyPosition(ticket, newStopLoss, currentTakeProfit);

        // Rate-limited [TRAIL-DIAG]: once per position per 5 seconds
        static datetime s_lastTrailDiagTime[];
        static ulong    s_lastTrailDiagTicket[];
        if(ArraySize(s_lastTrailDiagTicket) > 500)
        {
            ArrayResize(s_lastTrailDiagTicket, 0);
            ArrayResize(s_lastTrailDiagTime, 0);
        }
        int diagArrSize = ArraySize(s_lastTrailDiagTicket);
        int diagIdx = -1;
        for(int d = 0; d < diagArrSize; d++)
        {
            if(s_lastTrailDiagTicket[d] == ticket) { diagIdx = d; break; }
        }
        datetime now = TimeCurrent();
        bool shouldDiag = false;
        if(diagIdx == -1)
        {
            ArrayResize(s_lastTrailDiagTicket, diagArrSize + 1);
            ArrayResize(s_lastTrailDiagTime, diagArrSize + 1);
            diagIdx = diagArrSize;
            s_lastTrailDiagTicket[diagIdx] = ticket;
            s_lastTrailDiagTime[diagIdx] = now;
            shouldDiag = true;
        }
        else if(now - s_lastTrailDiagTime[diagIdx] >= 5)
        {
            s_lastTrailDiagTime[diagIdx] = now;
            shouldDiag = true;
        }
        if(shouldDiag)
        {
            PrintFormat("[TRAIL-DIAG] %s | ticket=%I64u | profit=%.1f pts | activation=%.1f pts | newSL=%.5f | curSL=%.5f",
                        symbolName, ticket, profitPoints, activationPoints, newStopLoss, currentStopLoss);
        }

        return trailResult;
    }

    return true;
}

bool CTradeManager::OpenPosition(const string symbol,
                                const ENUM_ORDER_TYPE orderType,
                                const double volume,
                                const double price,
                                const double stopLossPips,
                                const double takeProfitPips,
                                const string comment,
                                const uint magicNumber)
{
    double normalizedVolume = NormalizeVolume(symbol, volume);
    if(normalizedVolume <= 0.0)
    {
        LogError(StringFormat("Invalid normalized volume %.3f (requested %.3f)", normalizedVolume, volume), symbol);
        return false;
    }

    if(!IsHedgingAllowed(symbol))
    {
        PrintFormat("[TRADE-MGR] OpenPosition blocked: %s needs a hedging account, this one is %s | entries are refused because per-strategy books cannot be kept on a netted position",
                    symbol, EnumToString(m_accountMarginMode));
        return false;
    }

    // Forward the caller's magic decision to the send site: writing base+offset into the unused default m_trade
    // left the real send on the pool stamped with the bare base magic, so every strategy shipped an identical magic.
    m_pendingExplicitMagic = (ulong)magicNumber;

    bool executed = ExecuteMarketOrder(symbol, orderType, normalizedVolume, price, stopLossPips, takeProfitPips, comment);

    if(executed)
    {
        long journalMagic = (magicNumber > 0) ? (long)magicNumber
                            : (long)(m_magicNumber + GetMagicOffsetForSymbol(symbol));
        double journalPrice = (m_lastExecutionReceipt.averagePrice > 0.0) ? m_lastExecutionReceipt.averagePrice : price;
        double journalSL = 0.0;
        double journalTP = 0.0;
        if(stopLossPips > 0.0)
            journalSL = CalculateStopLoss(symbol, orderType, journalPrice, stopLossPips);
        if(takeProfitPips > 0.0)
            journalTP = CalculateTakeProfit(symbol, orderType, journalPrice, takeProfitPips);
        // Cache must hold POSITION tickets: on hedging (and netting) the position ticket equals the opening ORDER
        // ticket; storing dealTicket made PositionSelectByTicket always fail (BE/trailing dead).
        // Journal the volume that actually FILLED: a DONE_PARTIAL otherwise records a size that does not exist,
        // and reconciliation (orphan detection, attribution) works from it.
        double journalVolume = normalizedVolume;
        if(m_lastExecutionReceipt.partialFill && m_lastExecutionReceipt.filledVolume > 0.0 &&
           m_lastExecutionReceipt.filledVolume < normalizedVolume)
        {
            journalVolume = m_lastExecutionReceipt.filledVolume;
            PrintFormat("[PARTIAL-FILL-LEDGER] %s | requested=%.2f filled=%.2f | ledger records the filled volume; the remainder is NOT re-sent by design (a second send would open a separate position)",
                        symbol, normalizedVolume, journalVolume);
        }

        // Fall back to the order ticket from the instance that actually sent: m_trade.ResultOrder() is the unused
        // default, so it returned another symbol's last order ticket and poisoned the cache with a foreign ticket.
        ulong journalTicket = (m_lastExecutionReceipt.orderTicket > 0) ? m_lastExecutionReceipt.orderTicket
                             : (m_lastExecutionReceipt.dealTicket > 0) ? m_lastExecutionReceipt.dealTicket
                             : m_lastTradeResult.order;
        JournalTradeOpen(journalTicket, symbol, orderType, journalVolume,
                         journalPrice, journalSL, journalTP, journalMagic, "entry");
        
        if(journalTicket > 0)
            AddEAOwnedPosition(journalTicket);
    }

    return executed;
}


bool CTradeManager::NormalizeAndValidateStops(const string symbol,
                                             const ENUM_ORDER_TYPE orderType,
                                             const double price,
                                             const double tp,
                                             double &slOut,
                                             double &tpOut,
                                             string &errorMsg)
{
    return CTradeMgrPricing::NormalizeAndValidateStops(symbol, orderType, price, tp, slOut, tpOut, errorMsg);
}

// Split across CTradeMgrAsyncExecutor: guards over async state live in CheckSendGuards(); volume/price/preflight stay
// here because they need CTradeManager-owned pricing, ATR cache and slippage config.
bool CTradeManager::SendTradeAsync(ENUM_ORDER_TYPE orderType, const string symbol,
                                   double lot, double price, double sl, double tp,
                                   ulong magic, int timeoutMs)
{
    if(!m_asyncExecutor.CheckSendGuards(symbol, lot))
        return false;

    // Parity with the sync path: without this gate an async submission could ship a naked position.
    if(sl <= 0.0)
    {
        PrintFormat("[EXECUTION-BLOCKED] %s | reason=MandatoryStopLoss | path=async", symbol);
        return false;
    }

    double normalizedLot = NormalizeVolume(symbol, lot);
    if(normalizedLot <= 0.0)
    {
        PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=NormalizedLotZero requested=%.2f", symbol, lot);
        return false;
    }

    double executionPrice = price;
    if(executionPrice <= 0.0)
        executionPrice = GetCurrentExecutionPrice(symbol, orderType);
    executionPrice = NormalizePrice(symbol, executionPrice);
    if(executionPrice <= 0.0)
    {
        PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=InvalidPrice", symbol);
        return false;
    }

    string preflightReason = "";
    if(!ValidateExecutionPreflight(symbol, orderType, executionPrice, price, preflightReason))
    {
        PrintFormat("[ASYNC-TRADE-BLOCKED] %s | reason=%s", symbol, preflightReason);
        return false;
    }

    ApplyFillingModeForSymbol(symbol);
    UpdateDynamicSlippage(symbol);

    return m_asyncExecutor.SubmitAsync(orderType, symbol, normalizedLot, executionPrice, sl, tp,
                                       magic, timeoutMs, m_slippage, m_trade.RequestTypeFilling());
}

void CTradeManager::ProcessTradeTransaction(const MqlTradeTransaction &trans,
                                            const MqlTradeRequest &request,
                                            const MqlTradeResult &result)
{
    m_asyncExecutor.ProcessTradeTransaction(trans, request, result, m_execQuality);
}

void CTradeManager::CheckAsyncTimeouts()
{
    m_asyncExecutor.CheckAsyncTimeouts(m_execQuality);
}

int CTradeManager::GetPendingAsyncCount() const
{
    return m_asyncExecutor.GetPendingAsyncCount();
}

ulong CTradeManager::GetPendingAsyncTicket(int index) const
{
    return m_asyncExecutor.GetPendingAsyncTicket(index);
}

void CTradeManager::PersistAsyncTradeRequest(const SAsyncTradeRequest &asyncTrade)
{
    CTradeMgrAsyncExecutor::PersistAsyncTradeRequest(asyncTrade);
}

void CTradeManager::ReplayAsyncTradeRequests()
{
    m_asyncExecutor.ReplayAsyncTradeRequests();
}

bool CTradeManager::IsDuplicateIdempotencyKey(const string key) const
{
    return m_asyncExecutor.IsDuplicateIdempotencyKey(key);
}

void CTradeManager::CleanupPersistedAsyncTrades()
{
    CTradeMgrAsyncExecutor::CleanupPersistedAsyncTrades();
}

#endif // CORE_TRADE_MANAGER_MQH

