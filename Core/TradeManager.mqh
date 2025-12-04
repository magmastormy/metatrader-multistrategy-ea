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
#include "Enums.mqh"
#include "ErrorHandling.mqh"
#include "PositionSizer.mqh"
#include "PerformanceAnalytics.mqh"
#include "PortfolioRiskManager.mqh"
#include "MarketAnalysis.mqh"

// Trade execution settings
#define MAX_TRADE_RETRIES 3
#define TRADE_RETRY_DELAY 100 // ms
#define MAX_ORDERS_PER_SYMBOL 5
#define ORDER_TIMEOUT_SECONDS 30

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
    
    // Trade execution state
    MqlTradeResult m_lastTradeResult;        // Result of the last trade operation
    MqlTick m_lastTick;                      // Last tick data for symbol validation
    datetime m_lastOrderCheckTime;           // Last time orders were checked
    
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
        
        // BEAST MODE: 30-second throttling for position management operations
        datetime localCurrentTime2 = TimeCurrent();
        if(localCurrentTime2 - m_positionStates[index].lastModified < 30) {
            return false; // Too soon since last modification
        }
        
        // Get symbol for proper tolerance calculation
        if(!PositionSelectByTicket(ticket)) return false;
        string positionSymbol = PositionGetString(POSITION_SYMBOL);
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
        if(CopyBuffer(iATR(symbolParam, timeframe, period), 0, 0, 1, atrValues) > 0)
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
        m_useAsyncMode(true),
        m_emergencyStop(false),
        m_maxDailyLoss(0.0),
        m_dailyLoss(0.0),
        m_dailyResetTime(0),
        m_pendingOrderCount(0),
        m_stateCount(0),
        m_totalTrades(0),
        m_successfulTrades(0),
        m_failedTrades(0),
        m_lastTradeTime(0)
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
    void SetSlippage(const uint slippage) { m_slippage = slippage; }
    void SetMagicNumber(const uint magicNumber) { m_magicNumber = magicNumber; }
    void SetMaxDailyLoss(const double maxLoss) { m_maxDailyLoss = maxLoss; }
    
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
    ulong GetLastTicket() const { return m_trade.ResultOrder(); }
    
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
    bool CheckDailyLimits();
    bool IsTradeAllowed(const string symbol, const double volume);
    double CalculatePositionRisk(const string symbolParam, const double volume, const double stopLossPips);
    bool CheckMarginRequirements(const string symbolParam, const double volume);
    bool CheckCorrelationLimits(const string symbolName);
    bool ExecuteMarketOrder(const string symbol, const ENUM_ORDER_TYPE orderType,
                           const double volume, const double stopLoss, 
                           const double takeProfit, const string comment);

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
    m_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
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
    
    if(!m_trade.PositionModify(ticket, newSL, currentTP))
    {
        return false;
    }
    
    return true;
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
    
    if(!IsModificationNeeded(ticket, stopLoss, takeProfit))
    {
        return true;
    }
    
    if(m_trade.PositionModify(ticket, stopLoss, takeProfit))
    {
        UpdatePositionState(ticket, stopLoss, takeProfit);
        return true;
    }
    
    MqlTradeResult tradeResult;
    m_trade.Result(tradeResult);
    LogTradeError(tradeResult, "ModifyPosition");
    
    return false;
}

//+------------------------------------------------------------------+
//| Execute Market Order                                           |
//+------------------------------------------------------------------+
bool CTradeManager::ExecuteMarketOrder(const string symbolName, const ENUM_ORDER_TYPE orderType,
                                      const double volume, const double stopLoss, 
                                      const double takeProfit, const string comment)
{
    if(symbolName == "" || volume <= 0)
    {
        return false;
    }
    
    bool result = false;
    if(orderType == ORDER_TYPE_BUY)
    {
        result = m_trade.Buy(volume, symbolName, 0, stopLoss, takeProfit, comment);
    }
    else if(orderType == ORDER_TYPE_SELL)
    {
        result = m_trade.Sell(volume, symbolName, 0, stopLoss, takeProfit, comment);
    }
    
    if(!result)
    {
        MqlTradeResult tradeResult;
        m_trade.Result(tradeResult);
        LogTradeError(tradeResult, "ExecuteMarketOrder");
    }
    
    return result;
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
    
    if(volume < minVolume)
        return 0.0;
    
    if(volume > maxVolume)
        return maxVolume;
    
    return NormalizeDouble(MathFloor(volume / stepVolume) * stepVolume, 2);
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
    
    if(!SymbolInfoInteger(symbolParam, SYMBOL_TRADE_MODE))
    {
        return false;
    }
    
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
//| Validate Stop Levels                                          |
//+------------------------------------------------------------------+
bool CTradeManager::ValidateStopLevels(const string symbolParam, const double price,
                                      const double stopLoss, const double takeProfit)
{
    int stopLevel = (int)SymbolInfoInteger(symbolParam, SYMBOL_TRADE_STOPS_LEVEL);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    double minDistance = stopLevel * point;
    
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
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    
    if(tickValue <= 0 || point <= 0)
        return 0.0;
    
    double riskPerPip = tickValue * (1.0 / point);
    return volume * stopLossPips * riskPerPip;
}

//+------------------------------------------------------------------+
//| Check Margin Requirements                                      |
//+------------------------------------------------------------------+
bool CTradeManager::CheckMarginRequirements(const string symbolParam, const double volume)
{
    double marginRequired = SymbolInfoDouble(symbolParam, SYMBOL_MARGIN_INITIAL) * volume;
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
    double minStopLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(symbolName, SYMBOL_POINT);
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
    if(!CheckMarginRequirements(symbolName, volume)) return false;
    if(!CheckCorrelationLimits(symbolName)) return false;
    
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
    
    double maxDailyLoss = AccountInfoDouble(ACCOUNT_BALANCE) * 0.05;
    if(m_dailyLoss >= maxDailyLoss)
    {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Is Trade Allowed                                                 |
//+------------------------------------------------------------------+
bool CTradeManager::IsTradeAllowed(const string symbolName, const double volume)
{
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
    if(!SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE)) return false;
    
    if(!ValidateSymbol(symbolName)) return false;
    if(!ValidateVolume(symbolName, volume)) return false;
    if(!CheckMarginRequirements(symbolName, volume)) return false;
    if(!CheckCorrelationLimits(symbolName)) return false;
    if(!CheckDailyLimits()) return false;
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
                    profitPoints = (currentPriceValue - openPrice) / SymbolInfoDouble(m_positionInfo.Symbol(), SYMBOL_POINT);
                }
                else
                {
                    profitPoints = (openPrice - currentPriceValue) / SymbolInfoDouble(m_positionInfo.Symbol(), SYMBOL_POINT);
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
    
    double point = SymbolInfoDouble(m_positionInfo.Symbol(), SYMBOL_POINT);
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
    // Update magic number if provided
    if(magicNumber > 0)
    {
        m_trade.SetExpertMagicNumber(magicNumber);
    }
    else
    {
        m_trade.SetExpertMagicNumber(m_magicNumber);
    }
    
    // Validate trade request
    if(!ValidateTradeRequest(symbol, orderType, volume, price))
    {
        return false;
    }
    
    // Check if trade is allowed
    if(!IsTradeAllowed(symbol, volume))
    {
        return false;
    }
    
    // Calculate and validate stops
    double sl = 0.0;
    double tp = 0.0;
    string errorMsg = "";
    
    // Calculate initial stops based on pips
    if(stopLossPips > 0)
        sl = CalculateStopLoss(symbol, orderType, price, stopLossPips);
        
    if(takeProfitPips > 0)
        tp = CalculateTakeProfit(symbol, orderType, price, takeProfitPips);
    
    // Normalize and validate
    if(!NormalizeAndValidateStops(symbol, orderType, price, tp, sl, tp, errorMsg))
    {
        LogError("Invalid stops: " + errorMsg, symbol);
        return false;
    }
    
    // Execute the order
    return ExecuteMarketOrder(symbol, orderType, volume, sl, tp, comment);
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
    int stopLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double minDistance = stopLevel * point;
    
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