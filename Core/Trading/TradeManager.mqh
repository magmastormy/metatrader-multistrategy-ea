//+------------------------------------------------------------------+
//| Safe Trade Execution Engine                                      |
//| Handles all trade operations with comprehensive safety checks    |
//| and enhanced error handling                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#ifndef CORE_TRADE_MANAGER_MQH
#define CORE_TRADE_MANAGER_MQH

// Standard includes
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/HistoryOrderInfo.mqh>

// Project includes
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
#include "../Utils/TradeJournal.mqh"
#include "TradeTypes.mqh"
// Phase D T1: stateless helpers extracted out of this file
#include "TradeRetcodeClassifier.mqh"
#include "TradeSpreadCostModel.mqh"
#include "TradeDescriptor.mqh"
// Phase D T2: stateful telemetry subsystems extracted out of this file
#include "ExecutionQualityTracker.mqh"
#include "TradeStatsTracker.mqh"
// Phase D T3: position SL/TP state registry extracted out of this file
#include "PositionStateTracker.mqh"
// Phase D T4: TradeManager God-Object split — stateless price/risk math,
// per-symbol CTrade registry, deferred confirmation queue, send preflight
// and the async (OrderSendAsync) executor now live in their own modules.
// Included ABOVE the class body because CTradeManager holds the stateful
// ones BY VALUE and therefore needs their complete types.
#include "TradeMgrPricing.mqh"
#include "TradeMgrSymbolTradeRegistry.mqh"
#include "TradeMgrConfirmationQueue.mqh"
#include "TradeMgrPreflight.mqh"
#include "TradeMgrAsyncExecutor.mqh"


// Forward declarations
class CEnhancedErrorHandler;
class CMarketAnalysis;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;

// Phase D T4: SPendingConfirmation + MAX_PENDING_CONFIRMATIONS moved to
// CTradeMgrConfirmationQueue (Core/Trading/TradeMgrConfirmationQueue.mqh).

// Trade execution settings
#define MAX_TRADE_RETRIES 4
#define TRADE_RETRY_DELAY 150 // ms
#define MAX_ORDERS_PER_SYMBOL 5
#define ORDER_TIMEOUT_SECONDS 30

// Phase D T4: SSymbolMagicOffset moved to CTradeMgrSymbolTradeRegistry
// (Core/Trading/TradeMgrSymbolTradeRegistry.mqh).

//+------------------------------------------------------------------+
//| Trade Manager Class                                            |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
    // Core MT5 trade objects
    CTrade m_trade;                          // MT5 trade object (fallback/default)
    CPositionInfo m_positionInfo;            // Position info object
    CSymbolInfo m_symbolInfo;                // Symbol info object
    CHistoryOrderInfo m_historyOrderInfo;    // History order info
    CSessionManager m_sessionManager;        // Session manager object

    // Per-symbol CTrade instances to avoid race conditions in multi-symbol
    // trading (L10-013) — Phase D T4: state owned by
    // CTradeMgrSymbolTradeRegistry, which also owns the magic-offset table
    // and the EA-owned position ticket cache.
    CTradeMgrSymbolTradeRegistry m_symbolRegistry;

    // Dependencies (owned externally)
    CPerformanceAnalytics* m_perfAnalytics;  // Performance analytics
    CPortfolioRiskManager* m_riskManager;    // Risk manager
    CPositionSizer* m_positionSizer;         // Position sizer
    CMarketAnalysis* m_marketAnalysis;       // Market analysis
    CEnhancedErrorHandler* m_errorHandler;   // Error handler

    // Trade settings
    uint m_slippage;                         // Maximum slippage (in points)
    long m_magicNumber;                      // Magic number for trades (base) — Batch 125: changed from uint to long for 64-bit support
    long m_magicRangeMax;                    // Max magic number for EA ownership range check — Batch 125: changed from uint to long
    string m_expertName;                     // Expert advisor name
    bool m_useAsyncMode;                     // Use asynchronous order execution
    ENUM_ORDER_TYPE_FILLING m_orderFillMode; // Preferred broker fill policy
    int m_minModifyIntervalSec;              // Minimum interval between routine stop updates
    double m_maxEntrySpreadPoints;           // Hard quote-spread gate before market send
    double m_maxEntryDriftPoints;            // Hard drift gate between signal price and send price

    // Dynamic slippage settings
    bool m_enableDynamicSlippage;            // Enable ATR-based dynamic slippage
    double m_dynamicSlippageAtrPercent;      // Slippage as percentage of ATR
    uint m_dynamicSlippageMinPoints;         // Minimum slippage in points
    uint m_dynamicSlippageMaxMultiplier;     // Maximum slippage as multiplier of base
    int m_dynamicSlippageAtrPeriod;          // ATR period for volatility calculation
    uint m_baseSlippage;                     // Base slippage before dynamic adjustment

    // Execution quality metrics — Phase D T2a: state owned by
    // CExecutionQualityTracker (Core/Trading/ExecutionQualityTracker.mqh)
    CExecutionQualityTracker m_execQuality;

    // Trade tracking and statistics — Phase D T2b: state owned by
    // CTradeStatsTracker (Core/Trading/TradeStatsTracker.mqh)
    CTradeStatsTracker m_tradeStats;

    // Additional statistics variables for backward compatibility
    int m_totalTrades;
    int m_successfulTrades;
    uint m_failedTrades;
    datetime m_lastTradeTime;

    // Safety mechanisms
    bool m_emergencyStop;                    // Emergency stop flag
    int m_logLevel;                          // Log verbosity: 0=Silent, 1=Critical, 2=Normal, 3=Verbose, 4=Debug

    // ATR value cache to avoid redundant indicator reads per bar
    CATRCache m_atrCache;

    // Pending confirmation tracking for non-blocking execution
    // Phase D T4: state owned by CTradeMgrConfirmationQueue
    // (Core/Trading/TradeMgrConfirmationQueue.mqh)
    CTradeMgrConfirmationQueue m_confirmationQueue;

    // Async trade execution tracking — Phase D T4: state owned by
    // CTradeMgrAsyncExecutor (Core/Trading/TradeMgrAsyncExecutor.mqh)
    CTradeMgrAsyncExecutor m_asyncExecutor;

    // Trade execution state
    MqlTradeResult m_lastTradeResult;        // Result of the last trade operation
    MqlTick m_lastTick;                      // Last tick data for symbol validation
    datetime m_lastOrderCheckTime;           // Last time orders were checked
    double m_lastRequestedPrice;             // Last market price used for submit
    double m_lastRequestedStopLoss;          // Last SL sent to broker
    double m_lastRequestedTakeProfit;        // Last TP sent to broker
    STradeExecutionReceipt m_lastExecutionReceipt;

    // EA-owned position ticket cache for O(1) position management (L12-008)
    // Phase D T4: state owned by CTradeMgrSymbolTradeRegistry
    // (m_symbolRegistry).

    // Order tracking
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

    // BEAST MODE: State tracking to prevent redundant modifications
    // Phase D T3: state owned by CPositionStateTracker
    // (Core/Trading/PositionStateTracker.mqh)
    CPositionStateTracker m_positionStateTracker;

    // Per-symbol magic offset for family-specific magic number differentiation
        // Phase D T4: state owned by CTradeMgrSymbolTradeRegistry
        // (m_symbolRegistry).

        // L10-005: Account margin mode caching (hedging/netting compliance)
        ENUM_ACCOUNT_MARGIN_MODE m_accountMarginMode;
        bool m_marginModeInitialized;

        //+------------------------------------------------------------------+
        //| Initialize account margin mode cache                             |
        //+------------------------------------------------------------------+
        void InitializeMarginMode()
        {
           if(!m_marginModeInitialized)
           {
              m_accountMarginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
              m_marginModeInitialized = true;
              PrintFormat("[TRADE-MGR] Account margin mode: %s", EnumToString(m_accountMarginMode));
           }
        }

        //+------------------------------------------------------------------+
        //| Check if hedging is allowed for symbol (netting mode compliance) |
        //+------------------------------------------------------------------+
        bool IsHedgingAllowed(const string symbol) const
        {
           if(m_accountMarginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
              return true;
       
           // In netting mode, check if there's already an opposite position
           // This is a simplified check - full compliance would need position scanning
           return true; // Allow for now, netting handled by broker
        }

        //+------------------------------------------------------------------+
        //| Get net position volume for netting mode compliance             |
        //+------------------------------------------------------------------+
        // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
        double GetNetPositionVolume(const string symbol, ENUM_POSITION_TYPE type) const { return CTradeMgrPricing::GetNetPositionVolume(symbol, type, m_accountMarginMode); }

    //+------------------------------------------------------------------+
    //| Position state registry — Phase D T3: thin forwarders onto       |
    //| CPositionStateTracker (Core/Trading/PositionStateTracker.mqh).   |
    //| FindPositionState / RemovePositionState are not forwarded: both  |
    //| are internal to the module now (their only callers moved with    |
    //| them, and they have no callers anywhere else in the repo).       |
    //+------------------------------------------------------------------+
    void UpdatePositionState(ulong ticket, double sl, double tp) { m_positionStateTracker.UpdatePositionState(ticket, sl, tp); }

    void CleanupPositionStates() { m_positionStateTracker.CleanupPositionStates(); }

    bool IsModificationNeeded(ulong ticket, double newSL, double newTP) { return m_positionStateTracker.IsModificationNeeded(ticket, newSL, newTP, m_minModifyIntervalSec); }

    //+------------------------------------------------------------------+
    //| EA-owned position ticket cache helpers (L12-008)               |
    //| Phase D T4: thin forwarders onto CTradeMgrSymbolTradeRegistry.  |
    //+------------------------------------------------------------------+
    void AddEAOwnedPosition(ulong ticket) { m_symbolRegistry.AddEAOwnedPosition(ticket); }

    void RemoveEAOwnedPosition(ulong ticket) { m_symbolRegistry.RemoveEAOwnedPosition(ticket); }

    void ClearEAOwnedPositions() { m_symbolRegistry.ClearEAOwnedPositions(); }

    int GetEAOwnedPositionCount() const { return m_symbolRegistry.GetEAOwnedPositionCount(); }

    ulong GetEAOwnedPositionTicket(int index) const { return m_symbolRegistry.GetEAOwnedPositionTicket(index); }

    //+------------------------------------------------------------------+
    //| Check if two double values are approximately equal               |
    //+------------------------------------------------------------------+
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    bool DoubleEquals(double a, double b, double epsilon = 0.00001) { return CTradeMgrPricing::DoubleEquals(a, b, epsilon); }

    //+------------------------------------------------------------------+
    //| Log error with context                                           |
    //+------------------------------------------------------------------+
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

    // Overloads for direct context/severity logging
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

    //+------------------------------------------------------------------+
    //| Calculate Average True Range (ATR) for volatility measurement    |
    //+------------------------------------------------------------------+
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    double CalculateATR(const string symbolParam, ENUM_TIMEFRAMES timeframe, int period) { return CTradeMgrPricing::CalculateATR(symbolParam, timeframe, period); }

    //+------------------------------------------------------------------+
    //| Log trade error with context                                     |
    //+------------------------------------------------------------------+
    void LogTradeError(const MqlTradeResult &result, const string operation = "TradeOperation");

    //+------------------------------------------------------------------+
    //| Get trade error description                                      |
    //+------------------------------------------------------------------+
    // Phase D T1: moved to CTradeDescriptor (Core/Trading/TradeDescriptor.mqh)
    string GetTradeErrorDescription(int errorCode) { return CTradeDescriptor::GetTradeErrorDescription(errorCode); }

    //+------------------------------------------------------------------+
    //| Check if market is open for trading                             |
    //+------------------------------------------------------------------+
    bool IsMarketOpen(const string symbolParam)
    {
        return m_sessionManager.IsMarketOpen(symbolParam);
    }

    // Phase D T1: moved to CTradeRetcodeClassifier (Core/Trading/TradeRetcodeClassifier.mqh)
    bool IsTransientTradeRetcode(const uint retcode) const { return CTradeRetcodeClassifier::IsTransientTradeRetcode(retcode); }

    bool IsLimitedRetryRetcode(const uint retcode) const { return CTradeRetcodeClassifier::IsLimitedRetryRetcode(retcode); }

    bool IsSuccessfulFillRetcode(const uint retcode) const { return CTradeRetcodeClassifier::IsSuccessfulFillRetcode(retcode); }

    // Phase D T4: moved to CTradeMgrPreflight (Core/Trading/TradeMgrPreflight.mqh)
    void ApplyFillingModeForSymbol(const string symbolParam) { CTradeMgrPreflight::ApplyFillingModeForSymbol(symbolParam, m_trade, m_marketAnalysis, m_orderFillMode); }

    void ResetExecutionReceipt(const string symbolParam, const double requestedVolume)
    {
        m_lastExecutionReceipt = STradeExecutionReceipt();
        m_lastExecutionReceipt.symbol = symbolParam;
        m_lastExecutionReceipt.requestedVolume = requestedVolume;
    }

    // Phase D T4: moved to CTradeMgrPreflight (Core/Trading/TradeMgrPreflight.mqh)
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

    // Phase D T4: moved to CTradeMgrPreflight (Core/Trading/TradeMgrPreflight.mqh)
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
    // Constructor with dependency injection
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
        // Phase D T3: position-state array zeroing and state-counter reset
        // now happen in the CPositionStateTracker constructor
        // (m_positionStateTracker).
        // Phase D T2a: execution-quality metrics zeroing now happens in the
        // CExecutionQualityTracker constructor (m_execQuality).
        // Phase D T4: EA-owned ticket cache zeroing now happens in the
        // CTradeMgrSymbolTradeRegistry constructor (m_symbolRegistry).
    }

public:
    // Destructor
    ~CTradeManager()
    {
        // Clean up persisted async trades file
        CleanupPersistedAsyncTrades();

        // Reset ATR cache
        m_atrCache.Reset();

        // Free dynamic arrays — Phase D T4: owned by the extracted modules
        m_asyncExecutor.FreePending();
        m_symbolRegistry.FreeMagicOffsets();

        // Clear pending confirmations
        m_confirmationQueue.Clear();
    }

    // Initialization
        bool Initialize(const long magicNumber = 12345, const string expertName = "MultiStrategyEA");
    
        // Deinitialization - explicit cleanup for orchestrated shutdown
        void Deinit();
    
        // Getters for dependencies
    CPortfolioRiskManager* GetRiskManager() const { return m_riskManager; }
    CPositionSizer* GetPositionSizer() const { return m_positionSizer; }
    CMarketAnalysis* GetMarketAnalysis() const { return m_marketAnalysis; }

    // Set trading parameters
    void SetSlippage(const uint slippage) { m_slippage = slippage; m_baseSlippage = slippage; m_trade.SetDeviationInPoints(m_slippage); UpdatePerSymbolSlippage(m_slippage); }
    void SetMagicNumber(const long magicNumber) { m_magicNumber = magicNumber; m_trade.SetExpertMagicNumber(m_magicNumber); UpdatePerSymbolMagicNumber(m_magicNumber); }
    void SetMagicRangeMax(const long magicRangeMax) { m_magicRangeMax = magicRangeMax; }
    bool IsEAOwnedMagic(const long magic) const { return (m_magicRangeMax > m_magicNumber) ? (magic >= m_magicNumber && magic <= m_magicRangeMax) : (magic == m_magicNumber); }

    // L10-013: Update all per-symbol CTrade instances with new slippage
    // Phase D T4: thin forwarders onto CTradeMgrSymbolTradeRegistry
    void UpdatePerSymbolSlippage(const uint slippage) { m_symbolRegistry.UpdatePerSymbolSlippage(slippage); }

    // L10-013: Update all per-symbol CTrade instances with new magic number
    void UpdatePerSymbolMagicNumber(const long magicNumber) { m_symbolRegistry.UpdatePerSymbolMagicNumber(magicNumber); }

    // L10-013: Update all per-symbol CTrade instances with new fill mode
    void UpdatePerSymbolFillMode(const ENUM_ORDER_TYPE_FILLING mode) { m_symbolRegistry.UpdatePerSymbolFillMode(mode); }

    // L10-013: Update all per-symbol CTrade instances with new async mode
    void UpdatePerSymbolAsyncMode(const bool enabled) { m_symbolRegistry.UpdatePerSymbolAsyncMode(enabled); }

    //--- Per-symbol magic offset for family-specific magic number differentiation
    void SetMagicOffsetForSymbol(const string symbol, int offset) { m_symbolRegistry.SetMagicOffsetForSymbol(symbol, offset); }

    int GetMagicOffsetForSymbol(const string symbol) const { return m_symbolRegistry.GetMagicOffsetForSymbol(symbol); }
    void SetOrderFillMode(const ENUM_ORDER_TYPE_FILLING mode) { m_orderFillMode = mode; m_trade.SetTypeFilling(m_orderFillMode); UpdatePerSymbolFillMode(m_orderFillMode); }
    void SetProtectiveModifyCooldownSeconds(const int seconds) { m_minModifyIntervalSec = MathMax(1, seconds); }
    void SetLogLevel(const int level) { m_logLevel = MathMax(0, MathMin(4, level)); }

    // Set dynamic slippage configuration
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

    //--- Async trade execution interface (OrderSendAsync + OnTradeTransaction)
    // Enable or disable async mode
    void SetAsyncMode(bool enabled) { m_asyncExecutor.SetAsyncModeEnabled(enabled); m_trade.SetAsyncMode(m_asyncExecutor.IsAsyncModeEnabled()); UpdatePerSymbolAsyncMode(m_asyncExecutor.IsAsyncModeEnabled()); }

    // Submit trade asynchronously via OrderSendAsync
    bool SendTradeAsync(ENUM_ORDER_TYPE orderType, const string symbol,
                        double lot, double price, double sl, double tp,
                        ulong magic, int timeoutMs = 5000);

    // Process trade transaction event (call from OnTradeTransaction)
    void ProcessTradeTransaction(const MqlTradeTransaction &trans,
                                const MqlTradeRequest &request,
                                const MqlTradeResult &result);

    // Check for timed-out async trades (call from OnTimer)
    void CheckAsyncTimeouts();

    // Get pending async trade count
    int  GetPendingAsyncCount() const;

    // Get pending async trade ticket by index
    ulong GetPendingAsyncTicket(int index) const;

    // Persist async trade request to CSV for replay on restart
    void PersistAsyncTradeRequest(const SAsyncTradeRequest &asyncTrade);

    // Replay async trade requests from CSV on EA restart
    void ReplayAsyncTradeRequests();

    // Check for duplicate idempotency key
    bool IsDuplicateIdempotencyKey(const string key) const;

    // Clean up confirmed/expired persisted async trades
    void CleanupPersistedAsyncTrades();

    // Calculate dynamic slippage based on ATR volatility
    uint GetDynamicSlippage(const string symbol)
    {
        // If dynamic slippage is disabled, return base slippage
        if(!m_enableDynamicSlippage)
        {
            return m_baseSlippage;
        }

        // Default to base slippage if no market analysis
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

        // Convert ATR to points
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

        // Calculate dynamic slippage as percentage of ATR
        uint dynamicSlippage = (uint)MathRound(atrPoints * m_dynamicSlippageAtrPercent);

        // Clamp to configurable bounds
        uint minSlippage = MathMax(m_dynamicSlippageMinPoints, m_baseSlippage);
        uint maxSlippage = m_baseSlippage * m_dynamicSlippageMaxMultiplier;

        // Clamp using conditional since MathMin/MathMax don't work directly with uint cast
        double clamped = dynamicSlippage;
        if(clamped < (double)minSlippage) clamped = (double)minSlippage;
        if(clamped > (double)maxSlippage) clamped = (double)maxSlippage;
        return (uint)clamped;
    }

    // Update and apply dynamic slippage for a symbol
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

    // Main trading functions
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
    bool CloseAllPositions(const string symbol = "", const string reason = "Close all");

    bool ModifyPosition(const ulong ticket,
                       const double newStopLoss,
                       const double newTakeProfit);

    // Position management
    void ManageAllPositions(const double breakevenBuffer = 20.0,
                           const double trailingDistance = 50.0,
                           const double trailingStep = 10.0,
                           const bool useATRTrailing = false,
                           const double atrMultiplier = 2.0);

    bool SetTrailingStop(const ulong ticket, const double distance, const double step, const bool useATR = false, const double atrMult = 2.0);
    bool MoveToBreakeven(const ulong ticket, const double buffer);

    // Helper functions
    double NormalizePrice(const string symbol, const double price);
    double NormalizeVolume(const string symbol, const double volume);
    double CalculateStopLoss(const string symbol, const ENUM_ORDER_TYPE orderType, const double price, const double stopLossPips);
    double CalculateTakeProfit(const string symbol, const ENUM_ORDER_TYPE orderType, const double price, const double takeProfitPips);
    ulong GetLastTicket() const { return (m_lastTradeResult.order > 0) ? m_lastTradeResult.order : m_trade.ResultOrder(); }
    double GetLastRequestedPrice() const { return m_lastRequestedPrice; }
    double GetLastRequestedStopLoss() const { return m_lastRequestedStopLoss; }
    double GetLastRequestedTakeProfit() const { return m_lastRequestedTakeProfit; }
    uint GetLastRequestId() const { return m_lastTradeResult.request_id; }
    uint GetLastRetcode() const { return m_lastTradeResult.retcode; }
    void GetLastExecutionReceipt(STradeExecutionReceipt &receipt) const { receipt = m_lastExecutionReceipt; }

    // Check and resolve pending execution confirmations (call from main tick loop)
    // Phase D T4: moved to CTradeMgrConfirmationQueue
    // (Core/Trading/TradeMgrConfirmationQueue.mqh)
    void CheckPendingConfirmations() { m_confirmationQueue.CheckPendingConfirmations(); }

    // Statistics — Phase D T2b: forwarders onto CTradeStatsTracker
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

    // Execution quality metrics — Phase D T2a: forwarders onto CExecutionQualityTracker
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

    // Generate detailed execution quality report
    void GenerateExecutionQualityReport()
    {
        m_execQuality.GenerateExecutionQualityReport(m_logLevel,
                                                     m_enableDynamicSlippage,
                                                     m_dynamicSlippageAtrPercent,
                                                     m_dynamicSlippageMinPoints,
                                                     m_dynamicSlippageMaxMultiplier,
                                                     m_slippage);
    }

    // Smart order routing - analyze execution history and recommend optimal parameters
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

        // Check if we have enough execution history
        if(m_execQuality.TotalOrders() < 5)
        {
            params.reason = "Insufficient execution history for analysis";
            return params;
        }

        // Calculate fill rate
        double fillRate = (double)m_execQuality.FilledOrders() / m_execQuality.TotalOrders();

        // Calculate average slippage
        double avgSlippage = 0.0;
        if(m_execQuality.FilledOrders() > 0)
        {
            avgSlippage = m_execQuality.TotalSlippagePoints() / m_execQuality.FilledOrders();
        }

        // Calculate average latency
        double avgLatency = 0.0;
        if(m_execQuality.FilledOrders() > 0 && m_execQuality.TotalLatencyMs() > 0)
        {
            avgLatency = m_execQuality.TotalLatencyMs() / m_execQuality.FilledOrders();
        }

        // Get current spread
        long currentSpread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);

        // Decision logic based on execution history

        // If fill rate is low, recommend more conservative parameters
        if(fillRate < 0.8)
        {
            params.recommendedSlippage = (uint)MathMax(m_baseSlippage * 2, avgSlippage * 1.5);
            params.recommendedFillMode = ORDER_FILLING_FOK;
            params.reason = StringFormat("Low fill rate (%.1f%%), increasing slippage to %d",
                                        fillRate * 100, params.recommendedSlippage);
        }
        // If slippage is high, increase tolerance
        else if(avgSlippage > m_baseSlippage * 2)
        {
            params.recommendedSlippage = (uint)(avgSlippage * 1.2);
            params.reason = StringFormat("High avg slippage (%.1f pts), increasing tolerance to %d",
                                        avgSlippage, params.recommendedSlippage);
        }
        // If latency is high, use IOC to avoid stale orders
        else if(avgLatency > 500)
        {
            params.recommendedFillMode = ORDER_FILLING_IOC;
            params.reason = StringFormat("High latency (%.0f ms), using IOC fill mode", avgLatency);
        }
        // If spread is very high, consider not trading
        else if(currentSpread > m_maxEntrySpreadPoints)
        {
            params.shouldTrade = false;
            params.reason = StringFormat("Spread too high (%d pts > %.0f limit)",
                                        currentSpread, m_maxEntrySpreadPoints);
        }
        // If partial fills are common, use FOK
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

    // Apply smart order routing recommendations
    bool ApplySmartOrderRouting(const string symbol)
    {
        SSmartOrderParams params = AnalyzeAndRecommendOrderParams(symbol);

        if(!params.shouldTrade)
        {
            PrintFormat("[SMART-ROUTING] NOT TRADING: %s", params.reason);
            return false;
        }

        // Apply recommended slippage
        if(params.recommendedSlippage != m_slippage)
        {
            m_slippage = params.recommendedSlippage;
            m_trade.SetDeviationInPoints(m_slippage);
            // L10-013: Update all per-symbol CTrade instances
            m_symbolRegistry.UpdatePerSymbolSlippage(m_slippage);
            PrintFormat("[SMART-ROUTING] Adjusted slippage to %d pts: %s",
                       m_slippage, params.reason);
        }

        // Apply recommended fill mode
        if(params.recommendedFillMode != m_orderFillMode)
        {
            m_trade.SetTypeFilling(params.recommendedFillMode);
            // L10-013: Update all per-symbol CTrade instances
            m_symbolRegistry.UpdatePerSymbolFillMode(params.recommendedFillMode);
            PrintFormat("[SMART-ROUTING] Changed fill mode to %d: %s",
                       params.recommendedFillMode, params.reason);
        }

        return true;
    }

private:
    // Internal helper functions
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

    // Logging
    void LogTradeOperation(const string operation, const string symbolName, const ENUM_ORDER_TYPE orderType, const double volume, const bool success, const string details = "");

    // Logic helpers
    bool ShouldMoveToBreakeven(const ulong ticket, const double buffer);
    bool ShouldUpdateTrailingStop(const ulong ticket, const double distance, const double step);

    // Execution metrics update
    // Phase D T2a: moved to CExecutionQualityTracker (Core/Trading/ExecutionQualityTracker.mqh)
    void UpdateExecutionMetrics(const STradeExecutionReceipt &receipt) { m_execQuality.UpdateExecutionMetrics(receipt); }

    // Phase D T1: moved to CTradeSpreadCostModel (Core/Trading/TradeSpreadCostModel.mqh)
    double CalculateSpreadCost(const string symbol, const double volume) { return CTradeSpreadCostModel::CalculateSpreadCost(symbol, volume); }

    // Phase D T1: moved to CTradeDescriptor (Core/Trading/TradeDescriptor.mqh)
    ENUM_ORDER_TYPE OrderTypeFromString(const string orderTypeStr) const { return CTradeDescriptor::OrderTypeFromString(orderTypeStr); }

    // Commission and swap cost helpers
    double GetRoundTripCommissionCost(const string symbol, const double volume);
    double GetEstimatedSwapCost(const string symbol, const ENUM_ORDER_TYPE orderType,
                               const double volume, const int estimatedHoldDays);
};

//+------------------------------------------------------------------+
//| Initialize trade manager                                        |
//+------------------------------------------------------------------+
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

    // L10-013: Initialize per-symbol CTrade array
    m_symbolRegistry.ResetSymbolTrades();

    // L10-005: Initialize account margin mode cache for hedging/netting compliance
    InitializeMarginMode();

    return true;
    }

    //+------------------------------------------------------------------+
    //| Deinitialize trade manager - explicit cleanup for orchestrated shutdown
    //+------------------------------------------------------------------+
    void CTradeManager::Deinit()
    {
        // Clean up persisted async trades file
        CleanupPersistedAsyncTrades();
    
        // Reset ATR cache
        m_atrCache.Reset();
    
        // Free dynamic arrays — Phase D T4: owned by the extracted modules
        m_asyncExecutor.FreePending();
        m_symbolRegistry.FreeMagicOffsets();

        // Clear pending confirmations
        m_confirmationQueue.Clear();
    
        Print("[TRADE-MANAGER] Deinit complete - async trades cleaned up");
            }

        //+------------------------------------------------------------------+
        //| Get or create per-symbol CTrade instance (L10-013)              |
        //+------------------------------------------------------------------+
        CTrade* CTradeManager::GetSymbolTrade(const string symbol)
        {
            // Phase D T4: pool owned by CTradeMgrSymbolTradeRegistry; the four
            // configuration values it needs are passed in explicitly so the
            // registry keeps no back-pointer to CTradeManager.
            return m_symbolRegistry.GetSymbolTrade(symbol, m_magicNumber, m_slippage, m_orderFillMode, m_useAsyncMode);
        }

        //+------------------------------------------------------------------+
        //| Move position to breakeven                                      |
        //+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Close Position                                                  |
//+------------------------------------------------------------------+
bool CTradeManager::ClosePosition(const ulong ticket, const string reason)
{
    if(!PositionSelectByTicket(ticket))
    {
        return false;
    }

    string localSymbol = m_positionInfo.Symbol();

    // Capture TP/SL before close for calibration warning
    double posTP = m_positionInfo.TakeProfit();
    double posSL = m_positionInfo.StopLoss();
    double posOpenPrice = m_positionInfo.PriceOpen();

    // Check if market is open for trading
    // SYMBOL_TRADE_MODE_CLOSEONLY allows closing positions, so we allow it
    // SYMBOL_TRADE_MODE_DISABLED means no trading at all
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

    // L10-013: Use per-symbol CTrade instance to avoid race conditions
    CTrade* symbolTrade = GetSymbolTrade(localSymbol);
    bool result = symbolTrade.PositionClose(ticket);

    if(result)
    {
        // L12-008: Remove from EA-owned position cache
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

//+------------------------------------------------------------------+
//| Close Position Partial                                           |
//+------------------------------------------------------------------+
bool CTradeManager::ClosePositionPartial(const ulong ticket, double volume, const string reason)
{
    if(volume <= 0)
        return false;

    if(!PositionSelectByTicket(ticket))
        return false;

    string symbol = m_positionInfo.Symbol();

    // Add market open check
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

    // L10-013: Use per-symbol CTrade instance to avoid race conditions
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
        int errCode = GetLastError();
        LogTradeOperation("PARTIAL_CLOSE", symbol, orderType, normalizedVolume, false,
                          StringFormat("Partial close failed - %d (%s)", errCode, GetTradeErrorDescription(m_trade.ResultRetcode())));
    }

    return result;
}
//| Close All Positions                                             |
//+------------------------------------------------------------------+
bool CTradeManager::CloseAllPositions(const string symbolParam, const string reason)
{
    int totalPositions = PositionsTotal();
    int closedCount = 0;
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

    // L12-008: Clear EA-owned position cache after closing all
    ClearEAOwnedPositions();

    return allSuccess;
}

//+------------------------------------------------------------------+
//| Modify Position                                                 |
//+------------------------------------------------------------------+
bool CTradeManager::ModifyPosition(const ulong ticket, const double stopLoss, const double takeProfit)
{
    if(!PositionSelectByTicket(ticket))
    {
        return false;
    }

    // Get position details for stop level validation
    string symbol = PositionGetString(POSITION_SYMBOL);

    // Check if market is open for trading
    // SYMBOL_TRADE_MODE_CLOSEONLY allows modifying existing positions, so we allow it
    // SYMBOL_TRADE_MODE_DISABLED means no trading at all
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

    // Validate stop levels against broker minimum distance
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

    // Auto-normalize TP distance to broker constraints instead of repeatedly skipping.
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

    // Validate SL is on correct side of current price
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

    // Validate TP is on correct side of current price
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

    // L10-013: Use per-symbol CTrade instance to avoid race conditions
    CTrade* symbolTrade = GetSymbolTrade(symbol);
    if(symbolTrade.PositionModify(ticket, adjustedSL, adjustedTP))
    {
        UpdatePositionState(ticket, adjustedSL, adjustedTP);
        // Log successful modification
        LogTradeOperation("MODIFY", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), true,
                         StringFormat("SL=%.5f TP=%.5f", adjustedSL, adjustedTP));
        return true;
    }

    MqlTradeResult tradeResult;
    symbolTrade.Result(tradeResult);
    if(tradeResult.retcode == TRADE_RETCODE_NO_CHANGES)
    {
        UpdatePositionState(ticket, adjustedSL, adjustedTP);
        // Log no-changes as noop (not a real modification)
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
                // Log successful auto-adjusted modification
                LogTradeOperation("MODIFY_ADJUSTED", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), true,
                                 StringFormat("SL=%.5f TP=%.5f (widened to meet broker min distance)", retrySL, retryTP));
                return true;
            }
            symbolTrade.Result(tradeResult);
            if(tradeResult.retcode == TRADE_RETCODE_NO_CHANGES)
            {
                UpdatePositionState(ticket, retrySL, retryTP);
                // Log no-changes after widening as noop
                LogTradeOperation("MODIFY_NOOP", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), true,
                                 StringFormat("Already at widened SL=%.5f TP=%.5f", retrySL, retryTP));
                return true;
            }
        }
    }

    // Log failed modification
    LogTradeOperation("MODIFY_FAILED", symbol, (ENUM_ORDER_TYPE)posType, PositionGetDouble(POSITION_VOLUME), false,
                     StringFormat("SL=%.5f TP=%.5f | retcode=%u", adjustedSL, adjustedTP, tradeResult.retcode));
    LogTradeError(tradeResult, "ModifyPosition");

    return false;
}

//+------------------------------------------------------------------+
//| Execute Market Order                                           |
//+------------------------------------------------------------------+
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

    // MANDATORY STOP-LOSS GATE: Defense-in-depth �?execution layer enforces SL invariant
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

        // Update dynamic slippage based on current volatility
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

        // L10-013: Use per-symbol CTrade instance to avoid race conditions
        CTrade* symbolTrade = GetSymbolTrade(symbolName);
        
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
        // FIX: Fallback to requestedPrice if both tradeResult.price and executionPrice are 0
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

        if(!sendAccepted)
        {
            m_lastExecutionReceipt.accepted = false;
            m_lastExecutionReceipt.averagePrice = executionPrice;
            LogTradeError(tradeResult, "ExecuteMarketOrder");

            // Log failed trade operation for audit trail
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

            // Log successful trade operation for audit trail (fixes missing trade logs in EA logs)
            string orderTypeStr = EnumToString(orderType);
            string tradeDetails = StringFormat("price=%.5f sl=%.5f tp=%.5f slippage=%.1fpts latency=%I64ums retcode=%u",
                                              m_lastExecutionReceipt.averagePrice,
                                              stopLoss, takeProfit,
                                              m_lastExecutionReceipt.slippagePoints,
                                              m_lastExecutionReceipt.roundTripMs,
                                              m_lastExecutionReceipt.retcode);
            LogTradeOperation("OPEN", symbolName, orderType, m_lastExecutionReceipt.filledVolume, true, tradeDetails);

            // TP/SL calibration diagnostic: log distance to TP and SL at entry
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

    // Update execution quality metrics
    UpdateExecutionMetrics(m_lastExecutionReceipt);

    return executionConfirmed;
}

//+------------------------------------------------------------------+
//| Normalize Price                                                |
//+------------------------------------------------------------------+
double CTradeManager::NormalizePrice(const string symbolName, const double price)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::NormalizePrice(symbolName, price);
}

//+------------------------------------------------------------------+
//| Normalize Volume                                               |
//+------------------------------------------------------------------+
double CTradeManager::NormalizeVolume(const string symbolName, const double volume)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::NormalizeVolume(symbolName, volume);
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss                                            |
//+------------------------------------------------------------------+
double CTradeManager::CalculateStopLoss(const string symbolParam, const ENUM_ORDER_TYPE orderType,
                                       const double price, const double stopLossPips)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::CalculateStopLoss(symbolParam, orderType, price, stopLossPips);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                          |
//+------------------------------------------------------------------+
double CTradeManager::CalculateTakeProfit(const string symbolParam, const ENUM_ORDER_TYPE orderType,
                                         const double price, const double takeProfitPips)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::CalculateTakeProfit(symbolParam, orderType, price, takeProfitPips);
}


//+------------------------------------------------------------------+
//| Check whether symbol trade mode supports requested order type    |
//+------------------------------------------------------------------+
bool CTradeManager::IsOrderTypeAllowedForSymbol(const string symbolName, const ENUM_ORDER_TYPE orderType, string &reason)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::IsOrderTypeAllowedForSymbol(symbolName, orderType, reason);
}

//+------------------------------------------------------------------+
//| Current execution price for a market order                       |
//+------------------------------------------------------------------+
double CTradeManager::GetCurrentExecutionPrice(const string symbolName, const ENUM_ORDER_TYPE orderType)
{
    // Phase D T4: moved to CTradeMgrPricing; m_symbolInfo is passed by
    // reference because the fallback path refreshes it in place.
    return CTradeMgrPricing::GetCurrentExecutionPrice(symbolName, orderType, m_symbolInfo);
}

//+------------------------------------------------------------------+
//| Broker minimum stop/freeze distance                              |
//+------------------------------------------------------------------+
double CTradeManager::GetMinimumStopDistance(const string symbolName)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::GetMinimumStopDistance(symbolName);
}


//+------------------------------------------------------------------+
//| Log Trade Operation                                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Should Move to Breakeven                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Should Update Trailing Stop                                    |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Calculate Position Risk                                        |
//+------------------------------------------------------------------+
double CTradeManager::CalculatePositionRisk(const string symbolParam, const double volume,
                                           const double stopLossPips)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::CalculatePositionRisk(symbolParam, volume, stopLossPips);
}


//+------------------------------------------------------------------+
//| Get Round-Trip Commission Cost (entry + exit)                   |
//+------------------------------------------------------------------+
double CTradeManager::GetRoundTripCommissionCost(const string symbol, const double volume)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::GetRoundTripCommissionCost(symbol, volume);
}


//+------------------------------------------------------------------+
//| Get Estimated Swap Cost for holding position overnight          |
//+------------------------------------------------------------------+
double CTradeManager::GetEstimatedSwapCost(const string symbol, const ENUM_ORDER_TYPE orderType,
                                          const double volume, const int estimatedHoldDays)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::GetEstimatedSwapCost(symbol, orderType, volume, estimatedHoldDays);
}



//+------------------------------------------------------------------+
//| Update Performance Metrics                                      |
//+------------------------------------------------------------------+
void CTradeManager::UpdatePerformanceMetrics(const ulong ticket, const double profit, const bool isWin)
{
    if(!PositionSelectByTicket(ticket))
        return;

    // L10-006: Get position details to calculate commission/swap costs
    string symbol = PositionGetString(POSITION_SYMBOL);
    double volume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    double swap = PositionGetDouble(POSITION_SWAP);
    // POSITION_COMMISSION is deprecated; sum commission from deals via HistorySelectByPosition
    double commission = 0.0;
    if(HistorySelectByPosition(ticket))
    {
        int totalDeals = HistoryDealsTotal();
        for(int i = 0; i < totalDeals; i++)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket > 0)
                commission += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
        }
    }
    
    // Calculate net profit after commission and swap
    double netProfit = profit - commission - swap;
    
    // Phase D T2b: accumulation moved to CTradeStatsTracker
    m_tradeStats.RecordTrade(isWin, netProfit);

    // Legacy backward-compatibility mirrors — intentionally retained here
    m_totalTrades = m_tradeStats.TotalTrades();
    m_successfulTrades = m_tradeStats.SuccessfulTrades();
    m_failedTrades = m_tradeStats.FailedTrades();
    m_lastTradeTime = m_tradeStats.LastTradeTime();
}


//+------------------------------------------------------------------+
//| Log Trade Error                                                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Manage All Positions                                            |
//+------------------------------------------------------------------+
void CTradeManager::ManageAllPositions(const double breakevenBuffer,
                                       const double trailingDistance,
                                       const double trailingStep,
                                       const bool useATRTrailing,
                                       const double atrMultiplier)
{
    // L12-008: Use EA-owned position ticket cache for O(1) iteration instead of scanning all positions
    for(int i = GetEAOwnedPositionCount() - 1; i >= 0; i--)
    {
        ulong ticket = GetEAOwnedPositionTicket(i);
        if(ticket == 0) continue;
        
        if(!PositionSelectByTicket(ticket))
        {
            // Position no longer exists, remove from cache
            RemoveEAOwnedPosition(ticket);
            continue;
        }
        
        string symbolName = PositionGetString(POSITION_SYMBOL);
        double currentPriceValue = PositionGetDouble(POSITION_PRICE_CURRENT);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double stopLoss = PositionGetDouble(POSITION_SL);
        double takeProfit = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if(breakevenBuffer > 0)
        {
            // Batch104-BUG2+BUG3: Use MoveToBreakeven() instead of broken inline logic.
            // The old inline code required BOTH profitPoints >= buffer AND profitPercent >= 0.3,
            // which made breakeven nearly impossible on forex (0.3% = 300+ pips on EURUSD).
            // MoveToBreakeven() correctly checks only if price exceeds entry + buffer*point.
            MoveToBreakeven(ticket, breakevenBuffer);
        }

        if(useATRTrailing || (trailingDistance > 0 && trailingStep > 0))
        {
            SetTrailingStop(ticket, trailingDistance, trailingStep, useATRTrailing, atrMultiplier);
        }
    }
}

//+------------------------------------------------------------------+
//| Set Trailing Stop                                               |
//+------------------------------------------------------------------+
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
// Batch104-BUG4: Lower trailing activation threshold.
    // Old: activationPoints = MathMax(step, distance) = max(120, 300) = 300 points
    // This required 300 points profit before trailing started — too aggressive for forex.
    // New: activationPoints = distance (the trailing distance itself is the minimum
    // profit needed for the trailing stop to sit above entry for BUY positions).
    // Further fix (Issue #26): Cap activation at 100 points (10 pips) to allow earlier trailing
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

//+------------------------------------------------------------------+
//| Open Position                                                    |
//+------------------------------------------------------------------+
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

    // L10-005: Check hedging/netting mode compliance
    if(!IsHedgingAllowed(symbol))
    {
        PrintFormat("[TRADE-MGR] OpenPosition blocked: hedging not allowed for %s in netting mode", symbol);
        return false;
    }

    // Update magic number if provided
    if(magicNumber > 0)
    {
        m_trade.SetExpertMagicNumber(magicNumber + GetMagicOffsetForSymbol(symbol));
    }
    else
    {
        m_trade.SetExpertMagicNumber(m_magicNumber + GetMagicOffsetForSymbol(symbol));
    }

    double validationPrice = price;
    if(validationPrice <= 0.0)
        validationPrice = GetCurrentExecutionPrice(symbol, orderType);

    // Execute the order using the freshest price available at send time.
    bool executed = ExecuteMarketOrder(symbol, orderType, normalizedVolume, price, stopLossPips, takeProfitPips, comment);

    if(executed)
    {
        long journalMagic = (long)(m_magicNumber + GetMagicOffsetForSymbol(symbol));
        double journalPrice = (m_lastExecutionReceipt.averagePrice > 0.0) ? m_lastExecutionReceipt.averagePrice : price;
        double journalSL = 0.0;
        double journalTP = 0.0;
        if(stopLossPips > 0.0)
            journalSL = CalculateStopLoss(symbol, orderType, journalPrice, stopLossPips);
        if(takeProfitPips > 0.0)
            journalTP = CalculateTakeProfit(symbol, orderType, journalPrice, takeProfitPips);
        ulong journalTicket = (m_lastExecutionReceipt.dealTicket > 0) ? m_lastExecutionReceipt.dealTicket
                             : (m_lastExecutionReceipt.orderTicket > 0) ? m_lastExecutionReceipt.orderTicket
                             : m_trade.ResultDeal();
        JournalTradeOpen(journalTicket, symbol, orderType, normalizedVolume,
                         journalPrice, journalSL, journalTP, journalMagic, "entry");
        
        // L12-008: Add to EA-owned position cache
        if(journalTicket > 0)
            AddEAOwnedPosition(journalTicket);
    }

    return executed;
}

// Phase D T2b: GetTradeStatistics / ResetStatistics are now inline
// forwarders onto CTradeStatsTracker (declared in the class body).

//+------------------------------------------------------------------+
//| Normalize and Validate Stops                                    |
//+------------------------------------------------------------------+
bool CTradeManager::NormalizeAndValidateStops(const string symbol,
                                             const ENUM_ORDER_TYPE orderType,
                                             const double price,
                                             const double tp,
                                             double &slOut,
                                             double &tpOut,
                                             string &errorMsg)
{
    // Phase D T4: moved to CTradeMgrPricing (Core/Trading/TradeMgrPricing.mqh)
    return CTradeMgrPricing::NormalizeAndValidateStops(symbol, orderType, price, tp, slOut, tpOut, errorMsg);
}

//+------------------------------------------------------------------+
//| Send trade asynchronously via OrderSendAsync                     |
//| Phase D T4: split across CTradeMgrAsyncExecutor. The guards that |
//| only read async state live in CheckSendGuards(); the volume /    |
//| price / preflight resolution stays here because it needs the     |
//| CTradeManager-owned pricing, ATR cache and slippage config; the  |
//| request build + OrderSendAsync + pending bookkeeping is          |
//| SubmitAsync(). Order of operations is byte-for-byte unchanged.   |
//+------------------------------------------------------------------+
bool CTradeManager::SendTradeAsync(ENUM_ORDER_TYPE orderType, const string symbol,
                                   double lot, double price, double sl, double tp,
                                   ulong magic, int timeoutMs)
{
    // Guards: async mode enabled, non-empty symbol, positive lot, pending limit
    if(!m_asyncExecutor.CheckSendGuards(symbol, lot))
        return false;

    // Normalize volume and price
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

    // Preflight validation
    string preflightReason = "";
    if(!ValidateExecutionPreflight(symbol, orderType, executionPrice, price, preflightReason))
    {
        PrintFormat("[ASYNC-TRADE-BLOCKED] %s | reason=%s", symbol, preflightReason);
        return false;
    }

    // Apply filling mode and dynamic slippage
    ApplyFillingModeForSymbol(symbol);
    UpdateDynamicSlippage(symbol);

    // Build the request, submit via OrderSendAsync and record it as pending
    return m_asyncExecutor.SubmitAsync(orderType, symbol, normalizedLot, executionPrice, sl, tp,
                                       magic, timeoutMs, m_slippage, m_orderFillMode);
}

//+------------------------------------------------------------------+
//| Process trade transaction event (call from OnTradeTransaction)    |
//| Phase D T4: moved to CTradeMgrAsyncExecutor                       |
//+------------------------------------------------------------------+
void CTradeManager::ProcessTradeTransaction(const MqlTradeTransaction &trans,
                                            const MqlTradeRequest &request,
                                            const MqlTradeResult &result)
{
    m_asyncExecutor.ProcessTradeTransaction(trans, request, result, m_execQuality);
}

//+------------------------------------------------------------------+
//| Check for timed-out async trades (call from OnTimer)              |
//| Phase D T4: moved to CTradeMgrAsyncExecutor                       |
//+------------------------------------------------------------------+
void CTradeManager::CheckAsyncTimeouts()
{
    m_asyncExecutor.CheckAsyncTimeouts(m_execQuality);
}

//+------------------------------------------------------------------+
//| Get pending async trade count                                     |
//+------------------------------------------------------------------+
int CTradeManager::GetPendingAsyncCount() const
{
    return m_asyncExecutor.GetPendingAsyncCount();
}

//+------------------------------------------------------------------+
//| Get pending async trade ticket by index                          |
//+------------------------------------------------------------------+
ulong CTradeManager::GetPendingAsyncTicket(int index) const
{
    return m_asyncExecutor.GetPendingAsyncTicket(index);
}

//+------------------------------------------------------------------+
//| Persist async trade request to CSV for replay on restart         |
//+------------------------------------------------------------------+
void CTradeManager::PersistAsyncTradeRequest(const SAsyncTradeRequest &asyncTrade)
{
    CTradeMgrAsyncExecutor::PersistAsyncTradeRequest(asyncTrade);
}

//+------------------------------------------------------------------+
//| Replay async trade requests from CSV on EA restart               |
//+------------------------------------------------------------------+
void CTradeManager::ReplayAsyncTradeRequests()
{
    m_asyncExecutor.ReplayAsyncTradeRequests();
}

//+------------------------------------------------------------------+
//| Check for duplicate idempotency key                               |
//+------------------------------------------------------------------+
bool CTradeManager::IsDuplicateIdempotencyKey(const string key) const
{
    return m_asyncExecutor.IsDuplicateIdempotencyKey(key);
}

//+------------------------------------------------------------------+
//| Clean up confirmed/expired persisted async trades                 |
//+------------------------------------------------------------------+
void CTradeManager::CleanupPersistedAsyncTrades()
{
    CTradeMgrAsyncExecutor::CleanupPersistedAsyncTrades();
}

#endif // CORE_TRADE_MANAGER_MQH
