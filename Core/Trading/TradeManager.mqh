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





// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;

// Pending confirmation tracking for non-blocking execution
struct SPendingConfirmation
{
    ulong    orderTicket;
    string   symbol;
    double   expectedPrice;
    datetime sentAt;
    int      checkAttempts;
    bool     isActive;
};

// Async trade request tracking for OrderSendAsync + OnTradeTransaction pattern
struct SAsyncTradeRequest
{
    ulong           ticket;       // Order ticket assigned by broker
    string          symbol;       // Trading symbol
    ENUM_ORDER_TYPE orderType;    // Order type (BUY/SELL)
    double          lot;          // Lot size
    double          price;        // Expected execution price
    double          sl;           // Stop loss
    double          tp;           // Take profit
    ulong           magic;        // Magic number
    datetime        submitTime;   // When the request was submitted
    int             timeoutMs;    // Confirmation timeout in milliseconds
    bool            confirmed;    // Whether the trade was confirmed
    bool            expired;      // Whether the request timed out
};

// Trade execution settings
#define MAX_TRADE_RETRIES 4
#define TRADE_RETRY_DELAY 150 // ms
#define MAX_ORDERS_PER_SYMBOL 5
#define ORDER_TIMEOUT_SECONDS 30
#define MAX_PENDING_CONFIRMATIONS 20

struct STradeExecutionReceipt
{
    bool accepted;
    bool partialFill;
    uint retcode;
    uint requestId;
    int retryCount;
    ulong orderTicket;
    ulong dealTicket;
    double requestedVolume;
    double filledVolume;
    double requestedPrice;
    double averagePrice;
    double slippagePoints;
    ulong roundTripMs;
    datetime submitTime;
    double stopLoss;
    double takeProfit;
    string symbol;
    string note;

    STradeExecutionReceipt()
    {
        accepted = false;
        partialFill = false;
        retcode = 0;
        requestId = 0;
        retryCount = 0;
        orderTicket = 0;
        dealTicket = 0;
        requestedVolume = 0.0;
        filledVolume = 0.0;
        requestedPrice = 0.0;
        averagePrice = 0.0;
        slippagePoints = 0.0;
        roundTripMs = 0;
        submitTime = 0;
        stopLoss = 0.0;
        takeProfit = 0.0;
        symbol = "";
        note = "";
    }
};

//+------------------------------------------------------------------+
//| Trade Manager Class                                            |
//+------------------------------------------------------------------+
class CTradeManager
{
private:
    // Core MT5 trade objects
    CTrade m_trade;                          // MT5 trade object
    CPositionInfo m_positionInfo;            // Position info object
    CSymbolInfo m_symbolInfo;                // Symbol info object
    CHistoryOrderInfo m_historyOrderInfo;    // History order info
    CSessionManager m_sessionManager;        // Session manager object
    
    // Dependencies (owned externally)
    CPerformanceAnalytics* m_perfAnalytics;  // Performance analytics
    CPortfolioRiskManager* m_riskManager;    // Risk manager
    CPositionSizer* m_positionSizer;         // Position sizer
    CMarketAnalysis* m_marketAnalysis;       // Market analysis
    CEnhancedErrorHandler* m_errorHandler;   // Error handler
    
    // Trade settings
    uint m_slippage;                         // Maximum slippage (in points)
    uint m_magicNumber;                      // Magic number for trades (base)
    uint m_magicRangeMax;                    // Max magic number for EA ownership range check
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
    
    // Execution quality metrics
    struct ExecutionQualityMetrics {
        int totalOrders;                     // Total orders submitted
        int filledOrders;                    // Successfully filled orders
        int partialFills;                    // Partially filled orders
        int rejectedOrders;                  // Rejected orders
        double totalSlippagePoints;          // Cumulative slippage in points
        double totalSpreadCost;              // Cumulative spread cost
        double totalLatencyMs;               // Cumulative execution latency
        double maxSlippagePoints;            // Maximum slippage observed
        double maxLatencyMs;                 // Maximum latency observed
        datetime lastUpdateTime;             // Last metrics update time
    } m_execMetrics;
    
    // Trade tracking and statistics
    struct TradeStats {
        int totalTrades;                     // Total trades executed
        int successfulTrades;                // Successful trades
        int winningTrades;                   // Winning trades (profitable)
        uint failedTrades;                   // Number of failed trades
        double totalProfit;                  // Total profit
        double totalLoss;                    // Total loss
        datetime lastTradeTime;              // Last trade execution time
    } m_stats;

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
    SPendingConfirmation m_pendingConfirmations[MAX_PENDING_CONFIRMATIONS];
    int m_pendingConfirmationCount;

    // Async trade execution tracking
    SAsyncTradeRequest m_pendingAsyncTrades[];  // Dynamic array of pending async confirmations
    int                m_maxPendingAsync;        // Maximum pending async trades (default 10)
    bool               m_asyncModeEnabled;       // Whether async mode is active
    
    // Trade execution state
    MqlTradeResult m_lastTradeResult;        // Result of the last trade operation
    MqlTick m_lastTick;                      // Last tick data for symbol validation
    datetime m_lastOrderCheckTime;           // Last time orders were checked
    double m_lastRequestedPrice;             // Last market price used for submit
    double m_lastRequestedStopLoss;          // Last SL sent to broker
    double m_lastRequestedTakeProfit;        // Last TP sent to broker
    STradeExecutionReceipt m_lastExecutionReceipt;
    
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
    struct SPositionState {
        ulong ticket;
        double lastSL;
        double lastTP;
        datetime lastModified;
    };
    SPositionState m_positionStates[100]; // Track up to 100 positions
    int m_stateCount;

    //+------------------------------------------------------------------+
    //| Find position state by ticket with enhanced validation           |
    //+------------------------------------------------------------------+
    int FindPositionState(ulong ticket) 
    {
        if(ticket <= 0) return -1;
        
        for(int i = 0; i < m_stateCount; i++) 
        {
            if(m_positionStates[i].ticket == ticket) 
            {
                // Validate that the position still exists
                if(!PositionSelectByTicket(ticket)) 
                {
                    // Position no longer exists, remove from tracking
                    RemovePositionState(i);
                    return -1;
                }
                return i;
            }
        }
        return -1;
    }
    
    //+------------------------------------------------------------------+
    //| Update position state with validation                            |
    //+------------------------------------------------------------------+
    void UpdatePositionState(ulong ticket, double sl, double tp) 
    {
        if(ticket <= 0) return;
        
        // Validate position exists before updating state
        if(!PositionSelectByTicket(ticket)) 
        {
            return;
        }
        
        int index = FindPositionState(ticket);
        if(index == -1) 
        {
            if(m_stateCount < ArraySize(m_positionStates)) 
            {
                index = m_stateCount++;
                m_positionStates[index].ticket = ticket;
                m_positionStates[index].lastModified = TimeCurrent();
            }
            else
            {
                return;
            }
        }
        
        // Only update if values have changed
        if(!DoubleEquals(m_positionStates[index].lastSL, sl) || 
           !DoubleEquals(m_positionStates[index].lastTP, tp))
        {
            m_positionStates[index].lastSL = sl;
            m_positionStates[index].lastTP = tp;
            m_positionStates[index].lastModified = TimeCurrent();
        }
    }
    
    //+------------------------------------------------------------------+
    //| Remove position state by index                                   |
    //+------------------------------------------------------------------+
    void RemovePositionState(int index)
    {
        if(index < 0 || index >= m_stateCount) return;
        
        // Shift remaining elements
        for(int i = index; i < m_stateCount - 1; i++)
        {
            m_positionStates[i] = m_positionStates[i + 1];
        }
        
        // Clear last element
        m_positionStates[m_stateCount - 1].ticket = 0;
        m_positionStates[m_stateCount - 1].lastSL = 0;
        m_positionStates[m_stateCount - 1].lastTP = 0;
        m_positionStates[m_stateCount - 1].lastModified = 0;
        
        m_stateCount--;
    }
    
    //+------------------------------------------------------------------+
    //| Check if two double values are approximately equal               |
    //+------------------------------------------------------------------+
    bool DoubleEquals(double a, double b, double epsilon = 0.00001)
    {
        return MathAbs(a - b) < epsilon;
    }
    
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
    //| BEAST MODE: Clean up closed position states                      |
    //+------------------------------------------------------------------+
    void CleanupPositionStates() {
        static datetime lastCleanup = 0;
        datetime localCurrentTime = TimeCurrent();
        
        // Clean up every 5 minutes
        if(localCurrentTime - lastCleanup < 300) return;
        lastCleanup = localCurrentTime;
        
        int removedCount = 0;
        for(int i = m_stateCount - 1; i >= 0; i--) {
            // Check if position still exists
            if(!PositionSelectByTicket(m_positionStates[i].ticket)) {
                int errCode = GetLastError();
                if(errCode != 0 && errCode != 4001) {
                    PrintFormat("[TRADE-MGR] PositionSelectByTicket failed in cleanup | ticket=%I64u | err=%d",
                                m_positionStates[i].ticket, errCode);
                }
                // Position closed or not found, remove from state tracking
                for(int j = i; j < m_stateCount - 1; j++) {
                    m_positionStates[j] = m_positionStates[j + 1];
                }
                m_stateCount--;
                removedCount++;
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| BEAST MODE: Check if modification is needed                      |
    //+------------------------------------------------------------------+
    bool IsModificationNeeded(ulong ticket, double newSL, double newTP) {
        int index = FindPositionState(ticket);
        if(index == -1) return true; // New position, modification needed

        if(!PositionSelectByTicket(ticket)) {
            int errCode = GetLastError();
            if(errCode != 0 && errCode != 4001) {
                PrintFormat("[TRADE-MGR] PositionSelectByTicket failed in IsModificationNeeded | ticket=%I64u | err=%d",
                            ticket, errCode);
            }
            return false;
        }

        string positionSymbol = PositionGetString(POSITION_SYMBOL);
        double currentSL = PositionGetDouble(POSITION_SL);

        // Bounded throttling with emergency bypass only for missing protection.
        datetime localCurrentTime2 = TimeCurrent();
        int elapsedSec = (int)(localCurrentTime2 - m_positionStates[index].lastModified);
        if(elapsedSec < m_minModifyIntervalSec) {
            bool missingProtection = (newSL > 0.0 && currentSL <= 0.0);
            if(!missingProtection)
                return false;
        }

        // Get symbol for proper tolerance calculation
        double point = SymbolInfoDouble(positionSymbol, SYMBOL_POINT);
        double tolerance = point * 5; // 5 points tolerance to avoid micro-adjustments
        
        bool slChanged = MathAbs(m_positionStates[index].lastSL - newSL) > tolerance;
        bool tpChanged = MathAbs(m_positionStates[index].lastTP - newTP) > tolerance;
        
        return (slChanged || tpChanged);
    }

    //+------------------------------------------------------------------+
    //| Calculate Average True Range (ATR) for volatility measurement    |
    //+------------------------------------------------------------------+
    double CalculateATR(const string symbolParam, ENUM_TIMEFRAMES timeframe, int period)
    {
        double atrValues[];
        CIndicatorManager* manager = CIndicatorManager::Instance();
        if(manager == NULL)
            return 0.0;
            
        int atrHandle = manager.GetATRHandle(symbolParam, timeframe, period);
        if(atrHandle == INVALID_HANDLE)
            return 0.0;
            
        if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) > 0)
        {
            return atrValues[0];
        }
        return 0.0;
    }

    //+------------------------------------------------------------------+
    //| Log trade error with context                                     |
    //+------------------------------------------------------------------+
    void LogTradeError(const MqlTradeResult &result, const string operation = "TradeOperation");
    
    //+------------------------------------------------------------------+
    //| Get trade error description                                      |
    //+------------------------------------------------------------------+
    string GetTradeErrorDescription(int errorCode)
    {
        switch(errorCode)
        {
            case TRADE_RETCODE_REQUOTE:          return "Requote";
            case TRADE_RETCODE_PRICE_OFF:        return "Price off";
            case TRADE_RETCODE_INVALID_PRICE:    return "Invalid price";
            case TRADE_RETCODE_INVALID_STOPS:    return "Invalid stops";
            case TRADE_RETCODE_INVALID_VOLUME:   return "Invalid volume";
            case TRADE_RETCODE_MARKET_CLOSED:    return "Market closed";
            case TRADE_RETCODE_NO_MONEY:         return "Not enough money";
            case TRADE_RETCODE_PRICE_CHANGED:    return "Price changed";
            case TRADE_RETCODE_TIMEOUT:          return "Timeout";
            case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid expiration";
            case TRADE_RETCODE_ORDER_CHANGED:    return "Order changed";
            case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too many requests";
            case TRADE_RETCODE_NO_CHANGES:       return "No changes";
            case TRADE_RETCODE_SERVER_DISABLES_AT: return "AutoTrading disabled";
            case TRADE_RETCODE_CLIENT_DISABLES_AT: return "AutoTrading disabled by client";
            case TRADE_RETCODE_INVALID_ORDER:    return "Invalid order";
            case TRADE_RETCODE_POSITION_CLOSED:  return "Position closed";
            case TRADE_RETCODE_TRADE_DISABLED:   return "Trading disabled";
            case TRADE_RETCODE_HEDGE_PROHIBITED: return "Hedging prohibited";
            case TRADE_RETCODE_DONE:             return "Success";
            default:                             return "Unknown error (" + IntegerToString(errorCode) + ")";
        }
    }
    
    //+------------------------------------------------------------------+
    //| Check if market is open for trading                             |
    //+------------------------------------------------------------------+
    bool IsMarketOpen(const string symbolParam)
    {
        return m_sessionManager.IsMarketOpen(symbolParam);
    }

    bool IsTransientTradeRetcode(const uint retcode) const
    {
        return (retcode == TRADE_RETCODE_REQUOTE ||
                retcode == TRADE_RETCODE_PRICE_CHANGED ||
                retcode == TRADE_RETCODE_PRICE_OFF ||
                retcode == TRADE_RETCODE_TIMEOUT ||
                retcode == TRADE_RETCODE_TOO_MANY_REQUESTS ||
                retcode == TRADE_RETCODE_CONNECTION);
    }

    bool IsLimitedRetryRetcode(const uint retcode) const
    {
        return (retcode == TRADE_RETCODE_LOCKED ||
                retcode == TRADE_RETCODE_FROZEN);
    }

    bool IsSuccessfulFillRetcode(const uint retcode) const
    {
        return (retcode == TRADE_RETCODE_DONE ||
                retcode == TRADE_RETCODE_DONE_PARTIAL);
    }

    void ApplyFillingModeForSymbol(const string symbolParam)
    {
        if(symbolParam == "")
            return;

        // Analyze market conditions to choose appropriate fill mode
        bool useIOC = true;
        
        // Get spread for the symbol
        double spreadPoints = (double)SymbolInfoInteger(symbolParam, SYMBOL_SPREAD);
        double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
        
        // Get ATR volatility to assess market conditions
        double volatilityMultiplier = 1.0;
        if(m_marketAnalysis != NULL)
        {
            double atr = m_marketAnalysis.GetATR(symbolParam, 14);
            if(atr > 0.0)
            {
                double atrPoints = atr / point;
                // If spread is very high relative to volatility, use FOK to avoid partial fills at bad prices
                if(spreadPoints > atrPoints * 0.5)
                {
                    useIOC = false; // Use FOK in high spread/volatility conditions
                }
            }
        }
        
        // Choose fill mode based on analysis
        if(useIOC)
        {
            m_trade.SetTypeFilling(ORDER_FILLING_IOC);
        }
        else
        {
            m_trade.SetTypeFilling(ORDER_FILLING_FOK);
        }
        
        // Fallback to symbol default or base mode if needed
        if(!m_trade.SetTypeFillingBySymbol(symbolParam))
            m_trade.SetTypeFilling(m_orderFillMode);
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
        reason = "";
        if(!IsMarketOpen(symbolName))
        {
            reason = "market_unavailable";
            return false;
        }

        MqlTick tick;
        if(!SymbolInfoTick(symbolName, tick))
        {
            reason = "tick_unavailable";
            return false;
        }

        datetime tickTime = (tick.time > 0) ? (datetime)tick.time : TimeCurrent();
        int tickAgeSeconds = (int)MathMax(0, TimeCurrent() - tickTime);
        if(tickAgeSeconds > 30)
        {
            reason = StringFormat("stale_tick age=%ds", tickAgeSeconds);
            return false;
        }

        double bid = tick.bid;
        double ask = tick.ask;
        if(bid <= 0.0 || ask <= 0.0 || ask < bid)
        {
            reason = "invalid_quote";
            return false;
        }

        double spread = ask - bid;
        double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001;
        double spreadPoints = spread / point;
        if(m_maxEntrySpreadPoints > 0.0 && spreadPoints > m_maxEntrySpreadPoints)
        {
            reason = StringFormat("spread_points %.1f exceeds %.1f", spreadPoints, m_maxEntrySpreadPoints);
            return false;
        }

        if(m_maxEntryDriftPoints > 0.0 && requestedPrice > 0.0)
        {
            double driftPoints = MathAbs(executionPrice - requestedPrice) / point;
            double effectiveDriftLimit = m_maxEntryDriftPoints;
            double atr = m_atrCache.GetATR(symbolName, PERIOD_CURRENT);
            if(atr == EMPTY_VALUE || atr <= 0.0)
            {
                atr = CalculateATR(symbolName, PERIOD_CURRENT, m_dynamicSlippageAtrPeriod);
                if(atr > 0.0)
                {
                    datetime barTime = iTime(symbolName, PERIOD_CURRENT, 0);
                    m_atrCache.StoreATR(symbolName, PERIOD_CURRENT, atr, barTime);
                }
            }
            if(atr > 0.0)
                effectiveDriftLimit = MathMax(effectiveDriftLimit, (atr / point) * 0.30);
            effectiveDriftLimit = MathMax(effectiveDriftLimit, spreadPoints * 2.0);

            if(driftPoints > effectiveDriftLimit)
            {
                reason = StringFormat("entry_drift_points %.1f exceeds %.1f", driftPoints, effectiveDriftLimit);
                return false;
            }
        }

        double minStopDistance = GetMinimumStopDistance(symbolName);
        double spreadHardLimit = MathMax(minStopDistance * 2.0, executionPrice * 0.0015);
        if(spread > spreadHardLimit)
        {
            reason = StringFormat("spread_anomaly spread=%.5f limit=%.5f", spread, spreadHardLimit);
            return false;
        }

        if(orderType == ORDER_TYPE_BUY && executionPrice < bid)
        {
            reason = "buy_price_below_bid";
            return false;
        }

        if(orderType == ORDER_TYPE_SELL && executionPrice > ask)
        {
            reason = "sell_price_above_ask";
            return false;
        }

        return true;
    }

    bool ConfirmExecutionReceipt(const string symbolName,
                                 const ENUM_ORDER_TYPE orderType,
                                 const double requestedVolume,
                                 const double fallbackPrice,
                                 const MqlTradeResult &tradeResult)
    {
        datetime historyFrom = TimeCurrent() - 300;
        datetime historyTo = TimeCurrent() + 60;

        // Single non-blocking check — no Sleep loop
        if(HistorySelect(historyFrom, historyTo))
        {
            if(tradeResult.deal > 0 && HistoryDealSelect(tradeResult.deal))
            {
                string dealSymbol = HistoryDealGetString(tradeResult.deal, DEAL_SYMBOL);
                long dealEntry = HistoryDealGetInteger(tradeResult.deal, DEAL_ENTRY);
                long dealType = HistoryDealGetInteger(tradeResult.deal, DEAL_TYPE);
                bool directionMatches = ((orderType == ORDER_TYPE_BUY && dealType == DEAL_TYPE_BUY) ||
                                         (orderType == ORDER_TYPE_SELL && dealType == DEAL_TYPE_SELL));
                if(dealSymbol == symbolName &&
                   directionMatches &&
                   (dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT))
                {
                    double dealVolume = HistoryDealGetDouble(tradeResult.deal, DEAL_VOLUME);
                    double dealPrice = HistoryDealGetDouble(tradeResult.deal, DEAL_PRICE);
                    if(dealVolume > 0.0)
                        m_lastExecutionReceipt.filledVolume = dealVolume;
                    if(dealPrice > 0.0)
                        m_lastExecutionReceipt.averagePrice = dealPrice;
                    else if(m_lastExecutionReceipt.averagePrice <= 0.0)
                        m_lastExecutionReceipt.averagePrice = fallbackPrice;

                    m_lastExecutionReceipt.accepted = true;
                    m_lastExecutionReceipt.partialFill = (m_lastExecutionReceipt.filledVolume > 0.0 &&
                                                          m_lastExecutionReceipt.filledVolume + 1e-8 < requestedVolume);
                    m_lastExecutionReceipt.note = "history_deal_confirmed";
                    return true;
                }
            }
        }

        // Deal not found yet — defer to pending confirmation for later resolution
        if(tradeResult.order > 0 && m_pendingConfirmationCount < MAX_PENDING_CONFIRMATIONS)
        {
            int idx = m_pendingConfirmationCount;
            m_pendingConfirmations[idx].orderTicket   = tradeResult.order;
            m_pendingConfirmations[idx].symbol        = symbolName;
            m_pendingConfirmations[idx].expectedPrice = fallbackPrice;
            m_pendingConfirmations[idx].sentAt        = TimeCurrent();
            m_pendingConfirmations[idx].checkAttempts = 0;
            m_pendingConfirmations[idx].isActive      = true;
            m_pendingConfirmationCount++;
            PrintFormat("[EXECUTION-DEFERRED] %s | order=%I64u | added to pending confirmation queue",
                        symbolName, tradeResult.order);
        }

        // Optimistic return — broker accepted the order, confirmation deferred
        m_lastExecutionReceipt.accepted = true;
        if(m_lastExecutionReceipt.averagePrice <= 0.0)
            m_lastExecutionReceipt.averagePrice = fallbackPrice;
        if(m_lastExecutionReceipt.filledVolume <= 0.0)
            m_lastExecutionReceipt.filledVolume = 0.0;
        m_lastExecutionReceipt.note = "broker_accept_deferred";
        return true;
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
        m_pendingConfirmationCount(0),
        m_maxPendingAsync(10),
        m_asyncModeEnabled(false),
        m_pendingOrderCount(0),
        m_stateCount(0),
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
        ZeroMemory(m_positionStates);
        ZeroMemory(m_execMetrics);
    }
    
    // Destructor
    ~CTradeManager() {}

    // Initialization
    bool Initialize(const uint magicNumber = 12345, const string expertName = "MultiStrategyEA");
    
    // Getters for dependencies
    CPortfolioRiskManager* GetRiskManager() const { return m_riskManager; }
    CPositionSizer* GetPositionSizer() const { return m_positionSizer; }
    CMarketAnalysis* GetMarketAnalysis() const { return m_marketAnalysis; }
    
    // Set trading parameters
    void SetSlippage(const uint slippage) { m_slippage = slippage; m_baseSlippage = slippage; m_trade.SetDeviationInPoints(m_slippage); }
    void SetMagicNumber(const uint magicNumber) { m_magicNumber = magicNumber; }
    void SetMagicRangeMax(const uint magicRangeMax) { m_magicRangeMax = magicRangeMax; }
    bool IsEAOwnedMagic(const uint magic) const { return (m_magicRangeMax > m_magicNumber) ? (magic >= m_magicNumber && magic <= m_magicRangeMax) : (magic == m_magicNumber); }
    void SetOrderFillMode(const ENUM_ORDER_TYPE_FILLING mode) { m_orderFillMode = mode; }
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
    void SetAsyncMode(bool enabled) { m_asyncModeEnabled = enabled; }

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

        double atrValue = m_atrCache.GetATR(symbol, PERIOD_CURRENT);
        if(atrValue == EMPTY_VALUE || atrValue <= 0.0)
        {
            atrValue = m_marketAnalysis.GetATR(symbol, m_dynamicSlippageAtrPeriod);
            if(atrValue > 0.0)
            {
                datetime barTime = iTime(symbol, PERIOD_CURRENT, 0);
                m_atrCache.StoreATR(symbol, PERIOD_CURRENT, atrValue, barTime);
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
    void CheckPendingConfirmations()
    {
        if(m_pendingConfirmationCount <= 0)
            return;

        datetime historyFrom = TimeCurrent() - 300;
        datetime historyTo = TimeCurrent() + 60;

        for(int i = m_pendingConfirmationCount - 1; i >= 0; i--)
        {
            if(!m_pendingConfirmations[i].isActive)
                continue;

            m_pendingConfirmations[i].checkAttempts++;

            bool resolved = false;
            if(HistorySelect(historyFrom, historyTo))
            {
                int totalDeals = HistoryDealsTotal();
                for(int d = 0; d < totalDeals; d++)
                {
                    ulong dealTicket = HistoryDealGetTicket(d);
                    if(dealTicket == 0)
                        continue;

                    long dealOrderId = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
                    if((ulong)dealOrderId == m_pendingConfirmations[i].orderTicket)
                    {
                        string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
                        if(dealSymbol == m_pendingConfirmations[i].symbol)
                        {
                            double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                            double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                            PrintFormat("[EXECUTION-CONFIRMED] %s | order=%I64u | deal=%I64u | price=%.5f | volume=%.2f | attempts=%d",
                                        dealSymbol,
                                        m_pendingConfirmations[i].orderTicket,
                                        dealTicket,
                                        dealPrice,
                                        dealVolume,
                                        m_pendingConfirmations[i].checkAttempts);
                            resolved = true;
                            break;
                        }
                    }
                }
            }

            if(resolved || m_pendingConfirmations[i].checkAttempts >= 5)
            {
                if(!resolved)
                {
                    PrintFormat("[EXECUTION-TIMEOUT] %s | order=%I64u | attempts=%d | no deal found after max checks",
                                m_pendingConfirmations[i].symbol,
                                m_pendingConfirmations[i].orderTicket,
                                m_pendingConfirmations[i].checkAttempts);
                }

                // Remove by shifting
                for(int j = i; j < m_pendingConfirmationCount - 1; j++)
                {
                    m_pendingConfirmations[j] = m_pendingConfirmations[j + 1];
                }
                m_pendingConfirmationCount--;
                m_pendingConfirmations[m_pendingConfirmationCount].isActive = false;
                m_pendingConfirmations[m_pendingConfirmationCount].orderTicket = 0;
                m_pendingConfirmations[m_pendingConfirmationCount].symbol = "";
                m_pendingConfirmations[m_pendingConfirmationCount].expectedPrice = 0.0;
                m_pendingConfirmations[m_pendingConfirmationCount].sentAt = 0;
                m_pendingConfirmations[m_pendingConfirmationCount].checkAttempts = 0;
            }
        }
    }
    
    // Statistics
    void GetTradeStatistics(int &total, int &successful, int &failed, double &successRate);
    void ResetStatistics(void);
    
    // Execution quality metrics
    void GetExecutionQualityMetrics(int &totalOrders, int &filledOrders, int &partialFills, int &rejectedOrders,
                                     double &avgSlippagePoints, double &avgLatencyMs, double &fillRate)
    {
        totalOrders = m_execMetrics.totalOrders;
        filledOrders = m_execMetrics.filledOrders;
        partialFills = m_execMetrics.partialFills;
        rejectedOrders = m_execMetrics.rejectedOrders;
        
        if(m_execMetrics.filledOrders > 0)
        {
            avgSlippagePoints = m_execMetrics.totalSlippagePoints / m_execMetrics.filledOrders;
            avgLatencyMs = m_execMetrics.totalLatencyMs / m_execMetrics.filledOrders;
        }
        else
        {
            avgSlippagePoints = 0.0;
            avgLatencyMs = 0.0;
        }
        
        if(m_execMetrics.totalOrders > 0)
        {
            fillRate = (double)m_execMetrics.filledOrders / m_execMetrics.totalOrders * 100.0;
        }
        else
        {
            fillRate = 0.0;
        }
    }
    
    void GetExecutionQualitySummary(string &summary)
    {
        if(m_logLevel < 3)
        {
            summary = "";
            return;
        }
        int total, filled, partial, rejected;
        double avgSlippage, avgLatency, fillRate;
        GetExecutionQualityMetrics(total, filled, partial, rejected, avgSlippage, avgLatency, fillRate);

        summary = StringFormat("[EXECUTION-QUALITY] Total: %d | Filled: %d | Partial: %d | Rejected: %d | "
                              "Fill Rate: %.1f%% | Avg Slippage: %.1f pts | Avg Latency: %.0f ms | "
                              "Max Slippage: %.1f pts | Max Latency: %.0f ms",
                              total, filled, partial, rejected, fillRate, avgSlippage, avgLatency,
                              m_execMetrics.maxSlippagePoints, m_execMetrics.maxLatencyMs);
    }
    
    void ResetExecutionMetrics()
    {
        ZeroMemory(m_execMetrics);
    }
    
    // Generate detailed execution quality report
    void GenerateExecutionQualityReport()
    {
        if(m_logLevel < 3)
            return;

        Print("========== EXECUTION QUALITY REPORT ==========");
        PrintFormat("Report Generated: %s", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
        
        if(m_execMetrics.totalOrders == 0)
        {
            Print("[EXECUTION-REPORT] No orders executed yet.");
            Print("==============================================");
            return;
        }
        
        // Order statistics
        double fillRate = (double)m_execMetrics.filledOrders / m_execMetrics.totalOrders * 100.0;
        double partialRate = m_execMetrics.filledOrders > 0 ? 
                            (double)m_execMetrics.partialFills / m_execMetrics.filledOrders * 100.0 : 0.0;
        double rejectRate = (double)m_execMetrics.rejectedOrders / m_execMetrics.totalOrders * 100.0;
        
        Print("--- Order Statistics ---");
        PrintFormat("Total Orders:      %d", m_execMetrics.totalOrders);
        PrintFormat("Filled Orders:     %d (%.1f%%)", m_execMetrics.filledOrders, fillRate);
        PrintFormat("Partial Fills:     %d (%.1f%% of filled)", m_execMetrics.partialFills, partialRate);
        PrintFormat("Rejected Orders:   %d (%.1f%%)", m_execMetrics.rejectedOrders, rejectRate);
        
        // Slippage statistics
        Print("--- Slippage Analysis ---");
        if(m_execMetrics.filledOrders > 0)
        {
            double avgSlippage = m_execMetrics.totalSlippagePoints / m_execMetrics.filledOrders;
            PrintFormat("Average Slippage:  %.1f points", avgSlippage);
            PrintFormat("Maximum Slippage:  %.1f points", m_execMetrics.maxSlippagePoints);
            PrintFormat("Total Slippage:    %.1f points", m_execMetrics.totalSlippagePoints);
        }
        else
        {
            Print("No slippage data available.");
        }
        
        // Latency statistics
        Print("--- Latency Analysis ---");
        if(m_execMetrics.filledOrders > 0 && m_execMetrics.totalLatencyMs > 0)
        {
            double avgLatency = m_execMetrics.totalLatencyMs / m_execMetrics.filledOrders;
            PrintFormat("Average Latency:   %.0f ms", avgLatency);
            PrintFormat("Maximum Latency:   %.0f ms", m_execMetrics.maxLatencyMs);
            PrintFormat("Total Latency:     %.0f ms", m_execMetrics.totalLatencyMs);
        }
        else
        {
            Print("No latency data available.");
        }
        
        // Spread cost analysis
        Print("--- Spread Cost Analysis ---");
        PrintFormat("Total Spread Cost: %.2f %s", m_execMetrics.totalSpreadCost, 
                    AccountInfoString(ACCOUNT_CURRENCY));
        if(m_execMetrics.filledOrders > 0)
        {
            double avgSpreadCost = m_execMetrics.totalSpreadCost / m_execMetrics.filledOrders;
            PrintFormat("Average Spread Cost: %.2f %s per trade", avgSpreadCost,
                        AccountInfoString(ACCOUNT_CURRENCY));
        }
        
        // Dynamic slippage status
        Print("--- Dynamic Slippage Status ---");
        PrintFormat("Enabled:           %s", m_enableDynamicSlippage ? "Yes" : "No");
        PrintFormat("ATR Percentage:    %.0f%%", m_dynamicSlippageAtrPercent * 100);
        PrintFormat("Min Slippage:      %d points", m_dynamicSlippageMinPoints);
        PrintFormat("Max Multiplier:    %dx", m_dynamicSlippageMaxMultiplier);
        PrintFormat("Current Slippage:  %d points", m_slippage);
        
        Print("==============================================");
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
        if(m_execMetrics.totalOrders < 5)
        {
            params.reason = "Insufficient execution history for analysis";
            return params;
        }
        
        // Calculate fill rate
        double fillRate = (double)m_execMetrics.filledOrders / m_execMetrics.totalOrders;
        
        // Calculate average slippage
        double avgSlippage = 0.0;
        if(m_execMetrics.filledOrders > 0)
        {
            avgSlippage = m_execMetrics.totalSlippagePoints / m_execMetrics.filledOrders;
        }
        
        // Calculate average latency
        double avgLatency = 0.0;
        if(m_execMetrics.filledOrders > 0 && m_execMetrics.totalLatencyMs > 0)
        {
            avgLatency = m_execMetrics.totalLatencyMs / m_execMetrics.filledOrders;
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
        else if(m_execMetrics.filledOrders > 0 && 
                (double)m_execMetrics.partialFills / m_execMetrics.filledOrders > 0.2)
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
            PrintFormat("[SMART-ROUTING] Adjusted slippage to %d pts: %s", 
                       m_slippage, params.reason);
        }
        
        // Apply recommended fill mode
        if(params.recommendedFillMode != m_orderFillMode)
        {
            m_trade.SetTypeFilling(params.recommendedFillMode);
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
    void UpdateExecutionMetrics(const STradeExecutionReceipt &receipt)
    {
        m_execMetrics.totalOrders++;
        
        if(receipt.accepted)
        {
            m_execMetrics.filledOrders++;
            
            if(receipt.partialFill)
            {
                m_execMetrics.partialFills++;
            }
            
            // Track slippage
            if(receipt.slippagePoints > 0.0)
            {
                m_execMetrics.totalSlippagePoints += receipt.slippagePoints;
                if(receipt.slippagePoints > m_execMetrics.maxSlippagePoints)
                {
                    m_execMetrics.maxSlippagePoints = receipt.slippagePoints;
                }
            }
            
            // Track latency
            if(receipt.roundTripMs > 0)
            {
                m_execMetrics.totalLatencyMs += (double)receipt.roundTripMs;
                if((double)receipt.roundTripMs > m_execMetrics.maxLatencyMs)
                {
                    m_execMetrics.maxLatencyMs = (double)receipt.roundTripMs;
                }
            }
            
            // Track spread cost
            double spreadCost = CalculateSpreadCost(receipt.symbol, receipt.filledVolume);
            if(spreadCost > 0.0)
            {
                m_execMetrics.totalSpreadCost += spreadCost;
            }
        }
        else
        {
            m_execMetrics.rejectedOrders++;
        }
        
        m_execMetrics.lastUpdateTime = TimeCurrent();
    }
    
    // Calculate spread cost for a trade
    double CalculateSpreadCost(const string symbol, const double volume)
    {
        if(symbol == "" || volume <= 0.0)
            return 0.0;
            
        double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        
        if(point <= 0.0 || tickSize <= 0.0)
            return 0.0;
            
        // Spread cost = spread_points * point * volume * (tick_value / tick_size)
        double spreadCostPoints = spread * point;
        double valuePerPoint = tickValue / tickSize;
        double spreadCost = spreadCostPoints * volume * valuePerPoint;
        
        return spreadCost;
    }
    
    // Log spread cost analytics
    void LogSpreadCostAnalytics(const string symbol, const double volume)
    {
        double spreadCost = CalculateSpreadCost(symbol, volume);
        double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double spreadPips = spread * point / 0.0001; // Convert to pips
        
        PrintFormat("[SPREAD-COST] %s | Spread: %.1f pips | Volume: %.2f | Cost: %.2f %s",
                    symbol, spreadPips, volume, spreadCost, AccountInfoString(ACCOUNT_CURRENCY));
    }
};

//+------------------------------------------------------------------+
//| Initialize trade manager                                        |
//+------------------------------------------------------------------+
bool CTradeManager::Initialize(const uint magicNumber, 
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
    
    return true;
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

    bool result = m_trade.PositionClose(ticket);

    if(result)
    {
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
    
    bool result = m_trade.PositionClosePartial(ticket, normalizedVolume);
    
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
    
    for(int i = totalPositions - 1; i >= 0; i--)
    {
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

    if(m_trade.PositionModify(ticket, adjustedSL, adjustedTP))
    {
        UpdatePositionState(ticket, adjustedSL, adjustedTP);
        return true;
    }

    MqlTradeResult tradeResult;
    m_trade.Result(tradeResult);
    if(tradeResult.retcode == TRADE_RETCODE_NO_CHANGES)
    {
        UpdatePositionState(ticket, adjustedSL, adjustedTP);
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
            if(m_trade.PositionModify(ticket, retrySL, retryTP))
            {
                UpdatePositionState(ticket, retrySL, retryTP);
                return true;
            }
            m_trade.Result(tradeResult);
            if(tradeResult.retcode == TRADE_RETCODE_NO_CHANGES)
            {
                UpdatePositionState(ticket, retrySL, retryTP);
                return true;
            }
        }
    }

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

    // MANDATORY STOP-LOSS GATE: Defense-in-depth — execution layer enforces SL invariant
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
    
    while(retryCount < MAX_TRADE_RETRIES && !executionConfirmed)
    {
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

        bool sendAccepted = false;
        ulong sendStartUs = GetMicrosecondCount();
        if(orderType == ORDER_TYPE_BUY)
        {
            sendAccepted = m_trade.Buy(volume, symbolName, executionPrice, stopLoss, takeProfit, comment);
        }
        else if(orderType == ORDER_TYPE_SELL)
        {
            sendAccepted = m_trade.Sell(volume, symbolName, executionPrice, stopLoss, takeProfit, comment);
        }

        MqlTradeResult tradeResult;
        m_trade.Result(tradeResult);
        ulong sendEndUs = GetMicrosecondCount();
        m_lastTradeResult = tradeResult;
        m_lastExecutionReceipt.retcode = tradeResult.retcode;
        m_lastExecutionReceipt.requestId = tradeResult.request_id;
        m_lastExecutionReceipt.orderTicket = tradeResult.order;
        m_lastExecutionReceipt.dealTicket = tradeResult.deal;
        m_lastExecutionReceipt.retryCount = retryCount;
        m_lastExecutionReceipt.averagePrice = (tradeResult.price > 0.0) ? tradeResult.price : executionPrice;
        m_lastExecutionReceipt.filledVolume = (tradeResult.volume > 0.0) ? tradeResult.volume : 0.0;
        m_lastExecutionReceipt.partialFill = false;
        m_lastExecutionReceipt.note = tradeResult.comment;
        if(sendEndUs >= sendStartUs)
            m_lastExecutionReceipt.roundTripMs = (sendEndUs - sendStartUs) / 1000;
        double pointSize = SymbolInfoDouble(symbolName, SYMBOL_POINT);
        if(pointSize > 0.0 && m_lastExecutionReceipt.requestedPrice > 0.0 && m_lastExecutionReceipt.averagePrice > 0.0)
            m_lastExecutionReceipt.slippagePoints = MathAbs(m_lastExecutionReceipt.averagePrice - m_lastExecutionReceipt.requestedPrice) / pointSize;

        if(!sendAccepted)
        {
            m_lastExecutionReceipt.accepted = false;
            m_lastExecutionReceipt.averagePrice = executionPrice;
            LogTradeError(tradeResult, "ExecuteMarketOrder");
            
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
    if(price <= 0)
        return 0.0;
    
    int digits = (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);
    return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| Normalize Volume                                               |
//+------------------------------------------------------------------+
double CTradeManager::NormalizeVolume(const string symbolName, const double volume)
{
    double minVolume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MAX);
    double stepVolume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
    if(stepVolume <= 0.0)
        stepVolume = 0.01;
    
    if(volume < minVolume)
        return 0.0;
    
    int volumeDigits = 0;
    double stepProbe = stepVolume;
    while(volumeDigits < 8 && MathAbs(stepProbe - MathRound(stepProbe)) > 1e-8)
    {
        stepProbe *= 10.0;
        volumeDigits++;
    }
    
    double normalized = MathFloor((volume + 1e-12) / stepVolume) * stepVolume;
    normalized = NormalizeDouble(normalized, volumeDigits);
    normalized = MathMin(normalized, maxVolume);

    if(normalized < minVolume)
        return 0.0;

    return normalized;
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss                                            |
//+------------------------------------------------------------------+
double CTradeManager::CalculateStopLoss(const string symbolParam, const ENUM_ORDER_TYPE orderType,
                                       const double price, const double stopLossPips)
{
    if(stopLossPips <= 0)
        return 0.0;
    
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    double stopLoss = 0.0;
    
    if(orderType == ORDER_TYPE_BUY)
    {
        stopLoss = price - (stopLossPips * point);
    }
    else if(orderType == ORDER_TYPE_SELL)
    {
        stopLoss = price + (stopLossPips * point);
    }
    
    return NormalizePrice(symbolParam, stopLoss);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                          |
//+------------------------------------------------------------------+
double CTradeManager::CalculateTakeProfit(const string symbolParam, const ENUM_ORDER_TYPE orderType,
                                         const double price, const double takeProfitPips)
{
    if(takeProfitPips <= 0)
        return 0.0;
    
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    double takeProfit = 0.0;
    
    if(orderType == ORDER_TYPE_BUY)
    {
        takeProfit = price + (takeProfitPips * point);
    }
    else if(orderType == ORDER_TYPE_SELL)
    {
        takeProfit = price - (takeProfitPips * point);
    }
    
    return NormalizePrice(symbolParam, takeProfit);
}


//+------------------------------------------------------------------+
//| Check whether symbol trade mode supports requested order type    |
//+------------------------------------------------------------------+
bool CTradeManager::IsOrderTypeAllowedForSymbol(const string symbolName, const ENUM_ORDER_TYPE orderType, string &reason)
{
    reason = "";
    ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
    {
        reason = "Symbol trading disabled";
        return false;
    }

    if(tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
    {
        reason = "Symbol is close-only";
        return false;
    }

    if(orderType == ORDER_TYPE_BUY && tradeMode == SYMBOL_TRADE_MODE_SHORTONLY)
    {
        reason = "BUY not allowed by symbol trade mode";
        return false;
    }

    if(orderType == ORDER_TYPE_SELL && tradeMode == SYMBOL_TRADE_MODE_LONGONLY)
    {
        reason = "SELL not allowed by symbol trade mode";
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Current execution price for a market order                       |
//+------------------------------------------------------------------+
double CTradeManager::GetCurrentExecutionPrice(const string symbolName, const ENUM_ORDER_TYPE orderType)
{
    double price = (orderType == ORDER_TYPE_SELL) ?
                   SymbolInfoDouble(symbolName, SYMBOL_BID) :
                   SymbolInfoDouble(symbolName, SYMBOL_ASK);

    if(price <= 0.0)
    {
        m_symbolInfo.Name(symbolName);
        m_symbolInfo.Refresh();
        price = (orderType == ORDER_TYPE_SELL) ?
                SymbolInfoDouble(symbolName, SYMBOL_BID) :
                SymbolInfoDouble(symbolName, SYMBOL_ASK);
    }

    return NormalizePrice(symbolName, price);
}

//+------------------------------------------------------------------+
//| Broker minimum stop/freeze distance                              |
//+------------------------------------------------------------------+
double CTradeManager::GetMinimumStopDistance(const string symbolName)
{
    double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
    if(point <= 0.0)
        return 0.0;

    int stopLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_STOPS_LEVEL);
    int freezeLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_FREEZE_LEVEL);
    int requiredPoints = MathMax(stopLevel, freezeLevel);

    return (double)requiredPoints * point;
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
    double profitPoints = 0.0;
    
    if(m_positionInfo.PositionType() == POSITION_TYPE_BUY)
        profitPoints = (currentPriceValue - openPrice) / point;
    else
        profitPoints = (openPrice - currentPriceValue) / point;
    
    return (profitPoints >= buffer * 2);
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
    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    
    if(tickValue <= 0 || tickSize <= 0 || point <= 0)
        return 0.0;
    
    double stopDistancePrice = stopLossPips * point;
    double riskPerLot = (stopDistancePrice / tickSize) * tickValue;
    return volume * riskPerLot;
}



//+------------------------------------------------------------------+
//| Update Performance Metrics                                      |
//+------------------------------------------------------------------+
void CTradeManager::UpdatePerformanceMetrics(const ulong ticket, const double profit, const bool isWin)
{
    if(!PositionSelectByTicket(ticket))
        return;
        
    if(isWin)
    {
        m_stats.successfulTrades++;
        if(profit > 0) {
            m_stats.winningTrades++;
            m_stats.totalProfit += profit;
        }
    }
    else
    {
        m_stats.failedTrades++;
        if(profit < 0) {
            m_stats.totalLoss += MathAbs(profit);
        }
    }
    
    m_stats.totalTrades++;
    m_stats.lastTradeTime = TimeCurrent();
    
    m_totalTrades = m_stats.totalTrades;
    m_successfulTrades = m_stats.successfulTrades;
    m_failedTrades = m_stats.failedTrades;
    m_lastTradeTime = m_stats.lastTradeTime;
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
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            ulong ticket = PositionGetTicket(i);
            string symbolName = PositionGetString(POSITION_SYMBOL);
            double currentPriceValue = PositionGetDouble(POSITION_PRICE_CURRENT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double stopLoss = PositionGetDouble(POSITION_SL);
            double takeProfit = PositionGetDouble(POSITION_TP);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            uint positionMagic = (uint)PositionGetInteger(POSITION_MAGIC);
            if(m_magicNumber > 0 && !IsEAOwnedMagic(positionMagic))
                continue;
            
            if(breakevenBuffer > 0)
            {
                double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
                if(point <= 0.0)
                    point = 0.00001;

                double profitPoints = 0;
                double profitPercent = 0.0;
                if(type == POSITION_TYPE_BUY)
                {
                    profitPoints = (currentPriceValue - openPrice) / point;
                    if(openPrice > 0.0)
                        profitPercent = ((currentPriceValue - openPrice) / openPrice) * 100.0;
                }
                else
                {
                    profitPoints = (openPrice - currentPriceValue) / point;
                    if(openPrice > 0.0)
                        profitPercent = ((openPrice - currentPriceValue) / openPrice) * 100.0;
                }

                // Require BOTH: sufficient points buffer AND minimum 0.3% profit.
                // On synthetics with tiny point values (e.g., PainX point=0.01),
                // 120 points = only 0.0013% move — noise, not a real profit signal.
                // The 0.3% gate ensures breakeven only triggers on meaningful moves.
                bool breakevenNeeded = false;
                if(type == POSITION_TYPE_BUY)
                    breakevenNeeded = (profitPoints >= breakevenBuffer && profitPercent >= 0.3 && (stopLoss == 0.0 || stopLoss < openPrice));
                else
                    breakevenNeeded = (profitPoints >= breakevenBuffer && profitPercent >= 0.3 && (stopLoss == 0.0 || stopLoss > openPrice));

                if(breakevenNeeded)
                {
                    double newStopLoss = NormalizePrice(symbolName, openPrice);
                    ModifyPosition(ticket, newStopLoss, takeProfit);
                }
            }
            
            if(useATRTrailing || (trailingDistance > 0 && trailingStep > 0))
            {
                SetTrailingStop(ticket, trailingDistance, trailingStep, useATRTrailing, atrMultiplier);
            }
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
    uint positionMagic = (uint)PositionGetInteger(POSITION_MAGIC);
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
    double activationPoints = MathMax(step, distance);
    
    if(useATR)
    {
        double atr = CalculateATR(symbolName, PERIOD_CURRENT, 14);
        if(atr <= 0) return false;
        activationPoints = MathMax(activationPoints, (atr / point) * MathMax(0.75, atrMult * 0.50));
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
    
    if(newStopLoss > 0 && newStopLoss != currentStopLoss)
    {
        newStopLoss = NormalizePrice(symbolName, newStopLoss);
        return ModifyPosition(ticket, newStopLoss, currentTakeProfit);
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

    // Update magic number if provided
    if(magicNumber > 0)
    {
        m_trade.SetExpertMagicNumber(magicNumber);
    }
    else
    {
        m_trade.SetExpertMagicNumber(m_magicNumber);
    }

    double validationPrice = price;
    if(validationPrice <= 0.0)
        validationPrice = GetCurrentExecutionPrice(symbol, orderType);
    
    // Execute the order using the freshest price available at send time.
    return ExecuteMarketOrder(symbol, orderType, normalizedVolume, price, stopLossPips, takeProfitPips, comment);
}

//+------------------------------------------------------------------+
//| Get Trade Statistics                                            |
//+------------------------------------------------------------------+
void CTradeManager::GetTradeStatistics(int &total, int &successful, int &failed, double &successRate)
{
    total = m_stats.totalTrades;
    successful = m_stats.successfulTrades;
    failed = (int)m_stats.failedTrades;
    
    if(total > 0)
        successRate = (double)successful / total * 100.0;
    else
        successRate = 0.0;
}

//+------------------------------------------------------------------+
//| Reset Statistics                                                |
//+------------------------------------------------------------------+
void CTradeManager::ResetStatistics(void)
{
    ZeroMemory(m_stats);
    m_totalTrades = 0;
    m_successfulTrades = 0;
    m_failedTrades = 0;
    m_lastTradeTime = 0;
}

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
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    double minDistance = GetMinimumStopDistance(symbol);
    
    // Normalize input values
    slOut = NormalizeDouble(slOut, digits);
    tpOut = NormalizeDouble(tpOut, digits);
    
    // Validate Stop Loss
    if(slOut > 0)
    {
        double dist = MathAbs(price - slOut);
        if(dist < minDistance)
        {
            // Adjust to minimum distance
            if(orderType == ORDER_TYPE_BUY)
                slOut = price - minDistance - point;
            else
                slOut = price + minDistance + point;
                
            slOut = NormalizeDouble(slOut, digits);
        }
    }
    
    // Validate Take Profit
    if(tpOut > 0)
    {
        double dist = MathAbs(price - tpOut);
        if(dist < minDistance)
        {
            // Adjust to minimum distance
            if(orderType == ORDER_TYPE_BUY)
                tpOut = price + minDistance + point;
            else
                tpOut = price - minDistance - point;
                
            tpOut = NormalizeDouble(tpOut, digits);
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Send trade asynchronously via OrderSendAsync                     |
//+------------------------------------------------------------------+
bool CTradeManager::SendTradeAsync(ENUM_ORDER_TYPE orderType, const string symbol,
                                   double lot, double price, double sl, double tp,
                                   ulong magic, int timeoutMs)
{
    // Guard: async mode must be enabled
    if(!m_asyncModeEnabled)
    {
        PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=AsyncModeDisabled", symbol);
        return false;
    }

    // Validate inputs
    if(symbol == "")
    {
        Print("[ASYNC-TRADE-REJECTED] reason=EmptySymbol");
        return false;
    }
    if(lot <= 0.0)
    {
        PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=InvalidLot lot=%.2f", symbol, lot);
        return false;
    }

    // Enforce maximum pending limit
    int pendingCount = ArraySize(m_pendingAsyncTrades);
    if(pendingCount >= m_maxPendingAsync)
    {
        PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=MaxPendingReached count=%d max=%d",
                    symbol, pendingCount, m_maxPendingAsync);
        return false;
    }

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

    // Build the trade request
    MqlTradeRequest request = {};
    request.action    = TRADE_ACTION_DEAL;
    request.symbol    = symbol;
    request.volume    = normalizedLot;
    request.type      = orderType;
    request.price     = executionPrice;
    request.sl        = sl;
    request.tp        = tp;
    request.magic     = magic;
    request.comment   = "AsyncTrade";
    request.deviation = m_slippage;
    request.type_filling = m_orderFillMode;

    // Submit via OrderSendAsync
    MqlTradeResult result = {};
    bool sent = OrderSendAsync(request, result);

    if(!sent)
    {
        PrintFormat("[ASYNC-TRADE-FAILED] %s | retcode=%u | comment=%s | err=%d",
                    symbol, result.retcode, result.comment, GetLastError());
        return false;
    }

    // Store in pending array for later confirmation via OnTradeTransaction
    int newSize = ArraySize(m_pendingAsyncTrades) + 1;
    ArrayResize(m_pendingAsyncTrades, newSize);
    int idx = newSize - 1;

    m_pendingAsyncTrades[idx].ticket      = result.order;
    m_pendingAsyncTrades[idx].symbol      = symbol;
    m_pendingAsyncTrades[idx].orderType   = orderType;
    m_pendingAsyncTrades[idx].lot         = normalizedLot;
    m_pendingAsyncTrades[idx].price       = executionPrice;
    m_pendingAsyncTrades[idx].sl          = sl;
    m_pendingAsyncTrades[idx].tp          = tp;
    m_pendingAsyncTrades[idx].magic       = magic;
    m_pendingAsyncTrades[idx].submitTime  = TimeCurrent();
    m_pendingAsyncTrades[idx].timeoutMs   = timeoutMs;
    m_pendingAsyncTrades[idx].confirmed   = false;
    m_pendingAsyncTrades[idx].expired     = false;

    PrintFormat("[ASYNC-TRADE-SENT] Symbol=%s Type=%s Lot=%.2f Price=%.5f Ticket=%I64u",
                symbol, EnumToString(orderType), normalizedLot, executionPrice, result.order);

    return true;
}

//+------------------------------------------------------------------+
//| Process trade transaction event (call from OnTradeTransaction)    |
//+------------------------------------------------------------------+
void CTradeManager::ProcessTradeTransaction(const MqlTradeTransaction &trans,
                                            const MqlTradeRequest &request,
                                            const MqlTradeResult &result)
{
    // Only process deal-add transactions (completed fills)
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
        return;

    int pendingCount = ArraySize(m_pendingAsyncTrades);
    if(pendingCount == 0)
        return;

    ulong dealOrder = (ulong)trans.order;

    // Search for matching pending request by order ticket
    for(int i = pendingCount - 1; i >= 0; i--)
    {
        if(m_pendingAsyncTrades[i].ticket == dealOrder && !m_pendingAsyncTrades[i].confirmed)
        {
            // Mark as confirmed
            m_pendingAsyncTrades[i].confirmed = true;

            // Calculate slippage
            double pointSize = SymbolInfoDouble(m_pendingAsyncTrades[i].symbol, SYMBOL_POINT);
            double slippage = 0.0;
            if(pointSize > 0.0 && trans.price > 0.0 && m_pendingAsyncTrades[i].price > 0.0)
                slippage = MathAbs(trans.price - m_pendingAsyncTrades[i].price) / pointSize;

            PrintFormat("[ASYNC-TRADE-CONFIRMED] Ticket=%I64u Price=%.5f (expected=%.5f slippage=%.1f pts)",
                        m_pendingAsyncTrades[i].ticket,
                        trans.price,
                        m_pendingAsyncTrades[i].price,
                        slippage);

            // Update execution quality metrics
            STradeExecutionReceipt receipt;
            receipt.accepted        = true;
            receipt.orderTicket     = m_pendingAsyncTrades[i].ticket;
            receipt.requestedVolume = m_pendingAsyncTrades[i].lot;
            receipt.filledVolume    = trans.volume;
            receipt.requestedPrice  = m_pendingAsyncTrades[i].price;
            receipt.averagePrice    = trans.price;
            receipt.slippagePoints  = slippage;
            receipt.stopLoss        = m_pendingAsyncTrades[i].sl;
            receipt.takeProfit      = m_pendingAsyncTrades[i].tp;
            receipt.symbol          = m_pendingAsyncTrades[i].symbol;
            receipt.submitTime      = m_pendingAsyncTrades[i].submitTime;
            receipt.note            = "async_confirmed";
            if(m_pendingAsyncTrades[i].submitTime > 0)
            {
                ulong elapsedMs = (ulong)(TimeCurrent() - m_pendingAsyncTrades[i].submitTime) * 1000;
                receipt.roundTripMs = elapsedMs;
            }
            UpdateExecutionMetrics(receipt);

            // Remove confirmed entry by shifting remaining elements
            for(int j = i; j < ArraySize(m_pendingAsyncTrades) - 1; j++)
                m_pendingAsyncTrades[j] = m_pendingAsyncTrades[j + 1];
            ArrayResize(m_pendingAsyncTrades, ArraySize(m_pendingAsyncTrades) - 1);

            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Check for timed-out async trades (call from OnTimer)              |
//+------------------------------------------------------------------+
void CTradeManager::CheckAsyncTimeouts()
{
    int pendingCount = ArraySize(m_pendingAsyncTrades);
    if(pendingCount == 0)
        return;

    datetime checkTime = TimeCurrent();

    for(int i = pendingCount - 1; i >= 0; i--)
    {
        if(m_pendingAsyncTrades[i].confirmed || m_pendingAsyncTrades[i].expired)
            continue;

        // Calculate elapsed time in milliseconds
        long elapsedMs = (long)(checkTime - m_pendingAsyncTrades[i].submitTime) * 1000;

        if(elapsedMs > m_pendingAsyncTrades[i].timeoutMs)
        {
            m_pendingAsyncTrades[i].expired = true;

            PrintFormat("[ASYNC-TRADE-TIMEOUT] Ticket=%I64u expired after %I64dms (limit=%dms)",
                        m_pendingAsyncTrades[i].ticket,
                        elapsedMs,
                        m_pendingAsyncTrades[i].timeoutMs);

            // Update execution metrics for the timeout
            STradeExecutionReceipt receipt;
            receipt.accepted        = false;
            receipt.orderTicket     = m_pendingAsyncTrades[i].ticket;
            receipt.requestedVolume = m_pendingAsyncTrades[i].lot;
            receipt.requestedPrice  = m_pendingAsyncTrades[i].price;
            receipt.stopLoss        = m_pendingAsyncTrades[i].sl;
            receipt.takeProfit      = m_pendingAsyncTrades[i].tp;
            receipt.symbol          = m_pendingAsyncTrades[i].symbol;
            receipt.submitTime      = m_pendingAsyncTrades[i].submitTime;
            receipt.note            = "async_timeout";
            if(m_pendingAsyncTrades[i].submitTime > 0)
                receipt.roundTripMs = (ulong)elapsedMs;
            UpdateExecutionMetrics(receipt);

            // Remove expired entry by shifting remaining elements
            for(int j = i; j < ArraySize(m_pendingAsyncTrades) - 1; j++)
                m_pendingAsyncTrades[j] = m_pendingAsyncTrades[j + 1];
            ArrayResize(m_pendingAsyncTrades, ArraySize(m_pendingAsyncTrades) - 1);
        }
    }
}

//+------------------------------------------------------------------+
//| Get pending async trade count                                     |
//+------------------------------------------------------------------+
int CTradeManager::GetPendingAsyncCount() const
{
    return ArraySize(m_pendingAsyncTrades);
}

#endif // CORE_TRADE_MANAGER_MQH
