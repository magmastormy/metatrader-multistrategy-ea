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
#include "../Risk/PositionSizer.mqh"
#include "../Risk/PortfolioRiskManager.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"
#include "../Engines/MarketAnalysis.mqh"
#include "../../IndicatorManager.mqh"





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

// Trade execution settings
#define MAX_TRADE_RETRIES 4
#define TRADE_RETRY_DELAY 150 // ms
#define MAX_ORDERS_PER_SYMBOL 5
#define ORDER_TIMEOUT_SECONDS 30

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
    double averagePrice;
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
        averagePrice = 0.0;
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
    
    // Dependencies (owned externally)
    CPerformanceAnalytics* m_perfAnalytics;  // Performance analytics
    CPortfolioRiskManager* m_riskManager;    // Risk manager
    CPositionSizer* m_positionSizer;         // Position sizer
    CMarketAnalysis* m_marketAnalysis;       // Market analysis
    CEnhancedErrorHandler* m_errorHandler;   // Error handler
    
    // Trade settings
    uint m_slippage;                         // Maximum slippage (in points)
    uint m_magicNumber;                      // Magic number for trades
    string m_expertName;                     // Expert advisor name
    bool m_useAsyncMode;                     // Use asynchronous order execution
    ENUM_ORDER_TYPE_FILLING m_orderFillMode; // Preferred broker fill policy
    int m_minModifyIntervalSec;              // Minimum interval between routine stop updates
    
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
    double m_maxDailyLoss;                   // Maximum daily loss limit (in account currency)
    double m_dailyLoss;                      // Current daily loss
    datetime m_dailyResetTime;               // Daily reset timestamp
    bool m_externalRiskAuthority;            // External module owns risk veto when true
    
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
                if(!m_positionInfo.SelectByTicket(ticket)) 
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
        if(!m_positionInfo.SelectByTicket(ticket)) 
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
                // Position closed, remove from state tracking
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

        if(!PositionSelectByTicket(ticket))
            return false;

        string positionSymbol = PositionGetString(POSITION_SYMBOL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double currentSL = PositionGetDouble(POSITION_SL);

        // Bounded throttling with emergency bypass for missing or materially tighter protection.
        datetime localCurrentTime2 = TimeCurrent();
        int elapsedSec = (int)(localCurrentTime2 - m_positionStates[index].lastModified);
        if(elapsedSec < m_minModifyIntervalSec) {
            double pointFast = SymbolInfoDouble(positionSymbol, SYMBOL_POINT);
            if(pointFast <= 0.0)
                pointFast = 0.00001;

            bool missingProtection = (newSL > 0.0 && currentSL <= 0.0);
            bool materiallyTighter = false;
            if(newSL > 0.0 && currentSL > 0.0)
            {
                double tightenThreshold = pointFast * 20.0;
                if(posType == POSITION_TYPE_BUY)
                    materiallyTighter = (newSL - currentSL) > tightenThreshold;
                else if(posType == POSITION_TYPE_SELL)
                    materiallyTighter = (currentSL - newSL) > tightenThreshold;
            }

            if(!missingProtection && !materiallyTighter)
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
        if(!m_symbolInfo.Name(symbolParam))
            return false;
            
        if(!SymbolSelect(symbolParam, true)) {
            return false;
        }
        
        int syncAttempts = 0;
        const int maxSyncAttempts = 10;
        while(syncAttempts < maxSyncAttempts) {
            if(SymbolInfoInteger(symbolParam, SYMBOL_SELECT)) {
                break;
            }
            syncAttempts++;
        }
        
        if(syncAttempts >= maxSyncAttempts) {
            return false;
        }
        
        if(StringFind(symbolParam, "Volatility") >= 0 || StringFind(symbolParam, "Step") >= 0 ||
           StringFind(symbolParam, "Boom") >= 0 || StringFind(symbolParam, "Crash") >= 0) {
            
            for(int i = 0; i < 3; i++) {
                double bid = m_symbolInfo.Bid();
                double ask = m_symbolInfo.Ask();
                double point = m_symbolInfo.Point();
                
                if(bid > 0 && ask > 0 && ask > bid && point > 0) {
                    double spread = (ask - bid) / point;
                    if(spread > 0 && spread < 1000) {
                        return true;
                    }
                }
                
                if(i < 2) {
                    m_symbolInfo.Refresh();
                }
            }
            return false;
        }
        
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        
        if(dt.day_of_week == 0 || dt.day_of_week == 6) {
            return false;
        }
        
        double bid = m_symbolInfo.Bid();
        double ask = m_symbolInfo.Ask();
        if(bid <= 0 || ask <= 0 || ask <= bid) {
            return false;
        }
        
        int currentHour = dt.hour;
        return (currentHour >= 1 && currentHour <= 23);
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

        for(int attempt = 0; attempt < 3; attempt++)
        {
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

            if(attempt < 2)
                Sleep(TRADE_RETRY_DELAY);
        }

        m_lastExecutionReceipt.accepted = false;
        if(m_lastExecutionReceipt.averagePrice <= 0.0)
            m_lastExecutionReceipt.averagePrice = fallbackPrice;
        if(m_lastExecutionReceipt.filledVolume <= 0.0)
            m_lastExecutionReceipt.filledVolume = 0.0;
        m_lastExecutionReceipt.note = "broker_accept_unconfirmed";
        return false;
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
        m_useAsyncMode(false),
        m_orderFillMode(ORDER_FILLING_IOC),
        m_minModifyIntervalSec(5),
        m_emergencyStop(false),
        m_maxDailyLoss(0.0),
        m_dailyLoss(0.0),
        m_dailyResetTime(0),
        m_externalRiskAuthority(false),
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
        ResetDailyMetricsIfNeeded();
        ZeroMemory(m_positionStates);
    }
    
    // Destructor
    ~CTradeManager() {}

    // Initialization
    bool Initialize(const uint magicNumber = 12345, const string expertName = "MultiStrategyEA");
    
    // Set trading parameters
    void SetSlippage(const uint slippage) { m_slippage = slippage; m_trade.SetDeviationInPoints(m_slippage); }
    void SetMagicNumber(const uint magicNumber) { m_magicNumber = magicNumber; }
    void SetMaxDailyLoss(const double maxLoss) { m_maxDailyLoss = maxLoss; }
    void SetExternalRiskAuthority(const bool enabled) { m_externalRiskAuthority = enabled; }
    void SetOrderFillMode(const ENUM_ORDER_TYPE_FILLING mode) { m_orderFillMode = mode; }
    void SetProtectiveModifyCooldownSeconds(const int seconds) { m_minModifyIntervalSec = MathMax(1, seconds); }
    
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
                           const double trailingStep = 10.0);
    
    bool SetTrailingStop(const ulong ticket, const double distance, const double step);
    bool MoveToBreakeven(const ulong ticket, const double buffer);
    
    // Helper functions
    double NormalizePrice(const string symbol, const double price);
    double NormalizeVolume(const string symbol, const double volume);
    double CalculateStopLoss(const string symbol, const ENUM_ORDER_TYPE orderType, const double price, const double stopLossPips);
    double CalculateTakeProfit(const string symbol, const ENUM_ORDER_TYPE orderType, const double price, const double takeProfitPips);
    bool ValidateSymbol(const string symbol);
    ulong GetLastTicket() const { return (m_lastTradeResult.order > 0) ? m_lastTradeResult.order : m_trade.ResultOrder(); }
    double GetLastRequestedPrice() const { return m_lastRequestedPrice; }
    double GetLastRequestedStopLoss() const { return m_lastRequestedStopLoss; }
    double GetLastRequestedTakeProfit() const { return m_lastRequestedTakeProfit; }
    uint GetLastRequestId() const { return m_lastTradeResult.request_id; }
    uint GetLastRetcode() const { return m_lastTradeResult.retcode; }
    void GetLastExecutionReceipt(STradeExecutionReceipt &receipt) const { receipt = m_lastExecutionReceipt; }
    
    // Statistics
    void GetTradeStatistics(int &total, int &successful, int &failed, double &successRate);
    void ResetStatistics(void);

private:
    // Internal helper functions
    bool ValidateAndAdjustStopLevels(const string symbol, const double entryPrice, double &sl, double &tp, const int direction);
    bool ValidateVolume(const string symbolName, const double volume);
    bool ValidatePrice(const string symbolName, const double price);
    bool ValidateStopLevels(const string symbolParam, const double price, const double stopLoss, const double takeProfit);
    bool NormalizeAndValidateStops(const string symbol, const ENUM_ORDER_TYPE orderType, const double price, const double tp, double &slOut, double &tpOut, string &errorMsg);
    bool ValidateTradeRequest(const string symbol, const ENUM_ORDER_TYPE orderType, const double volume, const double price);
    bool IsOrderTypeAllowedForSymbol(const string symbolName, const ENUM_ORDER_TYPE orderType, string &reason);
    bool CheckDailyLimits();
    bool IsTradeAllowed(const string symbol, const double volume, const ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY);
    double CalculatePositionRisk(const string symbolParam, const double volume, const double stopLossPips);
    bool CheckMarginRequirements(const string symbolParam, const double volume, const ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY);
    bool CheckCorrelationLimits(const string symbolName);
    double GetCurrentExecutionPrice(const string symbolName, const ENUM_ORDER_TYPE orderType);
    double GetMinimumStopDistance(const string symbolName);
    bool ExecuteMarketOrder(const string symbol, const ENUM_ORDER_TYPE orderType,
                           const double volume, const double requestedPrice,
                           const double stopLossPips,
                           const double takeProfitPips,
                           const string comment);

    void ResetDailyMetricsIfNeeded();
    void UpdatePerformanceMetrics(const ulong ticket, const double profit, const bool isWin);
    
    // Logging
    void LogTradeOperation(const string operation, const string symbolName, const ENUM_ORDER_TYPE orderType, const double volume, const bool success, const string details = "");
    
    // Logic helpers
    bool ShouldMoveToBreakeven(const ulong ticket, const double buffer);
    bool ShouldUpdateTrailingStop(const ulong ticket, const double distance, const double step);
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
    
    m_dailyResetTime = TimeCurrent();
    m_dailyLoss = 0.0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Move position to breakeven                                      |
//+------------------------------------------------------------------+
bool CTradeManager::MoveToBreakeven(const ulong ticket, const double buffer)
{
    if(!m_positionInfo.SelectByTicket(ticket)) return false;
    
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
    if(!m_positionInfo.SelectByTicket(ticket))
    {
        return false;
    }
    
    string localSymbol = m_positionInfo.Symbol();
    ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)m_positionInfo.Type();
    double volume = m_positionInfo.Volume();
    double profit = m_positionInfo.Profit();
    
    bool result = m_trade.PositionClose(ticket);
    
    if(result)
    {
        LogTradeOperation("CLOSE", localSymbol, orderType, volume, true,
                         StringFormat("Profit: %.2f, Reason: %s", profit, reason));
        
        if(profit < 0)
            m_dailyLoss += MathAbs(profit);
            
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
    
    if(!m_positionInfo.SelectByTicket(ticket))
        return false;
    
    string symbol = m_positionInfo.Symbol();
    double positionVolume = m_positionInfo.Volume();
    
    double normalizedVolume = NormalizeVolume(symbol, volume);
    if(normalizedVolume <= 0 || normalizedVolume >= positionVolume)
        return false;
    
    bool result = m_trade.PositionClosePartial(ticket, normalizedVolume);
    
    ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)m_positionInfo.Type();
    
    if(result)
    {
        LogTradeOperation("PARTIAL_CLOSE", symbol, orderType, normalizedVolume, true,
                          StringFormat("Reason: %s", reason));
    }
    else
    {
        LogTradeOperation("PARTIAL_CLOSE", symbol, orderType, normalizedVolume, false,
                          "Partial close failed - " + IntegerToString(GetLastError()));
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
    double positionPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // Validate stop levels against broker minimum distance
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double minDistance = GetMinimumStopDistance(symbol);
    if(minDistance < point * 10) minDistance = point * 10; // Minimum 10 points fallback

    double adjustedSL = stopLoss;
    double adjustedTP = takeProfit;
    bool slAdjusted = false;
    bool tpAdjusted = false;
    
    // Auto-normalize SL distance to broker constraints instead of repeatedly skipping.
    if(adjustedSL > 0)
    {
        double slDistance = MathAbs(positionPrice - adjustedSL);
        if(slDistance < minDistance)
        {
            if(posType == POSITION_TYPE_BUY)
                adjustedSL = positionPrice - minDistance - point;
            else
                adjustedSL = positionPrice + minDistance + point;
            
            adjustedSL = NormalizeDouble(adjustedSL, digits);
            slAdjusted = true;
        }
    }

    // Auto-normalize TP distance to broker constraints instead of repeatedly skipping.
    if(adjustedTP > 0)
    {
        double tpDistance = MathAbs(positionPrice - adjustedTP);
        if(tpDistance < minDistance)
        {
            if(posType == POSITION_TYPE_BUY)
                adjustedTP = positionPrice + minDistance + point;
            else
                adjustedTP = positionPrice - minDistance - point;
            
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
        if(posType == POSITION_TYPE_BUY && adjustedSL >= positionPrice)
        {
            PrintFormat("[TRADE-WARN] ModifyPosition skipped - BUY SL above price: SL=%.5f, Price=%.5f", adjustedSL, positionPrice);
            return false;
        }
        if(posType == POSITION_TYPE_SELL && adjustedSL <= positionPrice)
        {
            PrintFormat("[TRADE-WARN] ModifyPosition skipped - SELL SL below price: SL=%.5f, Price=%.5f", adjustedSL, positionPrice);
            return false;
        }
    }

    // Validate TP is on correct side of current price
    if(adjustedTP > 0)
    {
        if(posType == POSITION_TYPE_BUY && adjustedTP <= positionPrice)
        {
            PrintFormat("[TRADE-WARN] ModifyPosition skipped - BUY TP below/at price: TP=%.5f, Price=%.5f", adjustedTP, positionPrice);
            return false;
        }
        if(posType == POSITION_TYPE_SELL && adjustedTP >= positionPrice)
        {
            PrintFormat("[TRADE-WARN] ModifyPosition skipped - SELL TP above/at price: TP=%.5f, Price=%.5f", adjustedTP, positionPrice);
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
        PrintFormat("[TRADE-INFO] ModifyPosition normalized stops | Symbol: %s | SL: %.5f | TP: %.5f | MinDistance: %.5f",
                    symbol, adjustedSL, adjustedTP, minDistance);
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
    
    ResetExecutionReceipt(symbolName, volume);
    bool executionConfirmed = false;
    int retryCount = 0;
    uint lastRetcode = 0;
    
    while(retryCount < MAX_TRADE_RETRIES && !executionConfirmed)
    {
        ApplyFillingModeForSymbol(symbolName);

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
        if(!ValidateExecutionPreflight(symbolName, orderType, executionPrice, preflightReason))
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

        bool sendAccepted = false;
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
//| Validate Symbol                                                |
//+------------------------------------------------------------------+
bool CTradeManager::ValidateSymbol(const string symbolParam)
{
    if(StringLen(symbolParam) == 0)
    {
        return false;
    }
    
    if(!SymbolSelect(symbolParam, true))
    {
        return false;
    }
    
    ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbolParam, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
    {
        return false;
    }

    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    double volumeStep = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_STEP);
    if(point <= 0.0 || volumeStep <= 0.0)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Volume                                                |
//+------------------------------------------------------------------+
bool CTradeManager::ValidateVolume(const string symbolName, const double volume)
{
    double minVolume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MAX);
    
    if(volume < minVolume || volume > maxVolume)
    {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Price                                                 |
//+------------------------------------------------------------------+
bool CTradeManager::ValidatePrice(const string symbolName, const double price)
{
    if(price <= 0)
    {
        return false;
    }
    
    double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
    
    if(bid <= 0 || ask <= 0)
    {
        return false;
    }
    
    return true;
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
//| Validate Stop Levels                                          |
//+------------------------------------------------------------------+
bool CTradeManager::ValidateStopLevels(const string symbolParam, const double price,
                                      const double stopLoss, const double takeProfit)
{
    double minDistance = GetMinimumStopDistance(symbolParam);
    
    bool valid = true;
    
    if(stopLoss > 0)
    {
        double slDistance = MathAbs(price - stopLoss);
        if(slDistance < minDistance)
        {
            valid = false;
        }
    }
    
    if(takeProfit > 0)
    {
        double tpDistance = MathAbs(takeProfit - price);
        if(tpDistance < minDistance)
        {
            valid = false;
        }
    }
    
    return valid;
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
    if(!m_positionInfo.SelectByTicket(ticket))
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
    if(!m_positionInfo.SelectByTicket(ticket))
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
//| Check Margin Requirements                                      |
//+------------------------------------------------------------------+
bool CTradeManager::CheckMarginRequirements(const string symbolParam, const double volume, const ENUM_ORDER_TYPE orderType)
{
    double currentPrice = (orderType == ORDER_TYPE_SELL) ?
                         SymbolInfoDouble(symbolParam, SYMBOL_BID) :
                         SymbolInfoDouble(symbolParam, SYMBOL_ASK);
    if(currentPrice <= 0.0)
        return false;

    double marginRequired = 0.0;
    if(!OrderCalcMargin(orderType, symbolParam, volume, currentPrice, marginRequired))
        return false;

    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    if(marginRequired <= 0) return false;
    
    if(marginRequired > (freeMargin * 0.8)) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Correlation Limits                                       |
//+------------------------------------------------------------------+
bool CTradeManager::CheckCorrelationLimits(const string symbolName)
{
    int sameBaseCount = 0;
    string symbolBase = StringSubstr(symbolName, 0, 3);
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                if(StringFind(posSymbol, symbolBase) >= 0)
                    sameBaseCount++;
            }
        }
    }
    
    if(sameBaseCount >= 3) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Reset Daily Metrics If Needed                                   |
//+------------------------------------------------------------------+
void CTradeManager::ResetDailyMetricsIfNeeded()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(m_dailyResetTime == 0 || (dt.hour == 0 && TimeCurrent() - m_dailyResetTime > 3600))
    {
        m_dailyLoss = 0.0;
        m_dailyResetTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Update Performance Metrics                                      |
//+------------------------------------------------------------------+
void CTradeManager::UpdatePerformanceMetrics(const ulong ticket, const double profit, const bool isWin)
{
    if(!m_positionInfo.SelectByTicket(ticket))
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
//| Validate and Adjust Stop Levels                                 |
//+------------------------------------------------------------------+
bool CTradeManager::ValidateAndAdjustStopLevels(const string symbolName, const double price,
                                               double &stopLoss, double &takeProfit, const int direction)
{
    double minStopLevel = GetMinimumStopDistance(symbolName);
    double spread = (int)SymbolInfoInteger(symbolName, SYMBOL_SPREAD) * SymbolInfoDouble(symbolName, SYMBOL_POINT);
    
    if(direction > 0) // Buy position
    {
        if(stopLoss > 0 && (price - stopLoss) < minStopLevel)
        {
            stopLoss = price - minStopLevel - spread;
        }
        if(takeProfit > 0 && (takeProfit - price) < minStopLevel)
        {
            takeProfit = price + minStopLevel + spread;
        }
    }
    else // Sell position
    {
        if(stopLoss > 0 && (stopLoss - price) < minStopLevel)
        {
            stopLoss = price + minStopLevel + spread;
        }
        if(takeProfit > 0 && (price - takeProfit) < minStopLevel)
        {
            takeProfit = price - minStopLevel - spread;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate trade request                                             |
//+------------------------------------------------------------------+
bool CTradeManager::ValidateTradeRequest(const string symbolName, const ENUM_ORDER_TYPE orderType,
                                        const double volume, const double price)
{
    if(!ValidateSymbol(symbolName)) return false;
    if(!ValidateVolume(symbolName, volume)) return false;
    if(!ValidatePrice(symbolName, price)) return false;

    string tradeModeReason = "";
    if(!IsOrderTypeAllowedForSymbol(symbolName, orderType, tradeModeReason))
    {
        LogError("Trade request rejected: " + tradeModeReason, symbolName);
        return false;
    }

    if(!CheckMarginRequirements(symbolName, volume, orderType)) return false;
    if(!m_externalRiskAuthority && !CheckCorrelationLimits(symbolName)) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check daily trading limits                                         |
//+------------------------------------------------------------------+
bool CTradeManager::CheckDailyLimits(void)
{
    datetime localCurrentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(localCurrentTime, dt);
    
    static int lastCheckedDay = -1;
    if(dt.day != lastCheckedDay)
    {
        m_dailyLoss = 0.0;
        lastCheckedDay = dt.day;
    }
    
    double maxDailyLoss = m_maxDailyLoss;
    if(maxDailyLoss <= 0.0)
        maxDailyLoss = AccountInfoDouble(ACCOUNT_BALANCE) * 0.05;

    if(m_dailyLoss >= maxDailyLoss)
    {
        PrintFormat("[TRADE-LIMIT] Daily loss limit reached: %.2f / %.2f", m_dailyLoss, maxDailyLoss);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Is Trade Allowed                                                 |
//+------------------------------------------------------------------+
bool CTradeManager::IsTradeAllowed(const string symbolName, const double volume, const ENUM_ORDER_TYPE orderType)
{
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
    
    if(!ValidateSymbol(symbolName)) return false;
    string tradeModeReason = "";
    if(!IsOrderTypeAllowedForSymbol(symbolName, orderType, tradeModeReason))
    {
        LogError("Trade blocked: " + tradeModeReason, symbolName);
        return false;
    }
    if(!ValidateVolume(symbolName, volume)) return false;
    if(!CheckMarginRequirements(symbolName, volume, orderType)) return false;
    if(!m_externalRiskAuthority)
    {
        if(!CheckCorrelationLimits(symbolName)) return false;
        if(!CheckDailyLimits()) return false;
    }
    if(m_emergencyStop) return false;
    
    return true;
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
                                       const double trailingStep)
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
            
            if(breakevenBuffer > 0)
            {
                double profitPoints = 0;
                if(type == POSITION_TYPE_BUY)
                {
                    profitPoints = (currentPriceValue - openPrice) / SymbolInfoDouble(symbolName, SYMBOL_POINT);
                }
                else
                {
                    profitPoints = (openPrice - currentPriceValue) / SymbolInfoDouble(symbolName, SYMBOL_POINT);
                }
                
                if(profitPoints >= breakevenBuffer && stopLoss < openPrice)
                {
                    double newStopLoss = openPrice;
                    if(type == POSITION_TYPE_SELL)
                    {
                        int spread = (int)SymbolInfoInteger(m_positionInfo.Symbol(), SYMBOL_SPREAD);
                        newStopLoss = openPrice + spread * SymbolInfoDouble(m_positionInfo.Symbol(), SYMBOL_POINT);
                    }
                    
                    ModifyPosition(ticket, newStopLoss, takeProfit);
                }
            }
            
            if(trailingDistance > 0 && trailingStep > 0)
            {
                SetTrailingStop(ticket, trailingDistance, trailingStep);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Set Trailing Stop                                               |
//+------------------------------------------------------------------+
bool CTradeManager::SetTrailingStop(const ulong ticket, const double distance, const double step)
{
    if(ticket <= 0 || distance <= 0 || step <= 0) return false;
    if(!PositionSelectByTicket(ticket)) return false;
    
    string symbolName = PositionGetString(POSITION_SYMBOL);
    double currentPriceValue = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentStopLoss = PositionGetDouble(POSITION_SL);
    double currentTakeProfit = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
    double newStopLoss = 0;
    
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
    
    if(newStopLoss > 0 && newStopLoss != currentStopLoss)
    {
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
    
    // Validate trade request
    if(!ValidateTradeRequest(symbol, orderType, normalizedVolume, validationPrice))
    {
        return false;
    }
    
    // Check if trade is allowed
    if(!IsTradeAllowed(symbol, normalizedVolume, orderType))
    {
        return false;
    }

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

#endif // CORE_TRADE_MANAGER_MQH
