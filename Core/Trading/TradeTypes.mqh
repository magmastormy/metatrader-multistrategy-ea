//+------------------------------------------------------------------+
//| TradeTypes.mqh                                                   |
//| Shared trade type definitions for modular trade components       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#ifndef CORE_TRADE_TYPES_MQH
#define CORE_TRADE_TYPES_MQH

#define DEFAULT_ASYNC_TIMEOUT_MS 5000

// Trade execution receipt - shared across all trade components
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

// Async trade request tracking
struct SAsyncTradeRequest
{
    ulong ticket;           // Order ticket assigned by broker
    string symbol;          // Trading symbol
    ENUM_ORDER_TYPE orderType;  // Order type (BUY/SELL)
    double lot;             // Lot size
    double price;           // Expected execution price
    double sl;              // Stop loss
    double tp;              // Take profit
    ulong magic;            // Magic number
    datetime submitTime;    // When the request was submitted
    int timeoutMs;          // Confirmation timeout in milliseconds
    bool confirmed;         // Whether the trade was confirmed
    bool expired;           // Whether the request timed out
    string comment;         // Trade comment
    STradeExecutionReceipt executionReceipt;  // Execution details

    SAsyncTradeRequest() : ticket(0), orderType(ORDER_TYPE_BUY), lot(0), price(0), 
                           sl(0), tp(0), magic(0), submitTime(0), timeoutMs(DEFAULT_ASYNC_TIMEOUT_MS),
                           confirmed(false), expired(false) {}
};

// Smart order routing parameters
struct SSmartOrderParams
{
    bool shouldTrade;
    uint recommendedSlippage;
    ENUM_ORDER_TYPE_FILLING recommendedFillMode;
    string reason;

    SSmartOrderParams() : shouldTrade(true), recommendedSlippage(0), recommendedFillMode(ORDER_FILLING_FOK), reason("") {}
};

// Execution quality metrics
struct ExecutionQualityMetrics
{
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

    ExecutionQualityMetrics() : totalOrders(0), filledOrders(0), partialFills(0), rejectedOrders(0),
                               totalSlippagePoints(0), totalSpreadCost(0), totalLatencyMs(0),
                               maxSlippagePoints(0), maxLatencyMs(0), lastUpdateTime(0) {}
};

// Trade statistics per symbol
struct SSymbolTradeStats
{
    string symbol;
    int totalTrades;
    int winningTrades;
    int losingTrades;
    double totalProfit;
    double totalLoss;
    double grossProfit;
    double grossLoss;
    double maxWin;
    double maxLoss;
    double maxDrawdown;
    double avgWin;
    double avgLoss;
    double winRate;
    double profitFactor;
    double expectancy;
    double sharpeRatio;
    datetime firstTradeTime;
    datetime lastTradeTime;
    int consecutiveWins;
    int consecutiveLosses;
    int maxConsecutiveWins;
    int maxConsecutiveLosses;
    double avgHoldTimeHours;
    double bestTradeProfit;
    double worstTradeLoss;

    SSymbolTradeStats() : symbol(""), totalTrades(0), winningTrades(0), losingTrades(0),
                         totalProfit(0), totalLoss(0), grossProfit(0), grossLoss(0),
                         maxWin(0), maxLoss(0), maxDrawdown(0), avgWin(0), avgLoss(0),
                         winRate(0), profitFactor(0), expectancy(0), sharpeRatio(0),
                         firstTradeTime(0), lastTradeTime(0), consecutiveWins(0), consecutiveLosses(0),
                         maxConsecutiveWins(0), maxConsecutiveLosses(0), avgHoldTimeHours(0),
                         bestTradeProfit(0), worstTradeLoss(0) {}
};

// Trade statistics per magic number
struct SMagicTradeStats
{
    ulong magicNumber;
    int totalTrades;
    int winningTrades;
    int losingTrades;
    double totalProfit;
    double totalLoss;
    double grossProfit;
    double grossLoss;
    double maxWin;
    double maxLoss;
    double maxDrawdown;
    double avgWin;
    double avgLoss;
    double winRate;
    double profitFactor;
    double expectancy;
    double sharpeRatio;
    datetime firstTradeTime;
    datetime lastTradeTime;
    int consecutiveWins;
    int consecutiveLosses;
    int maxConsecutiveWins;
    int maxConsecutiveLosses;
    double avgHoldTimeHours;
    double bestTradeProfit;
    double worstTradeLoss;

    SMagicTradeStats() : magicNumber(0), totalTrades(0), winningTrades(0), losingTrades(0),
                        totalProfit(0), totalLoss(0), grossProfit(0), grossLoss(0),
                        maxWin(0), maxLoss(0), maxDrawdown(0), avgWin(0), avgLoss(0),
                        winRate(0), profitFactor(0), expectancy(0), sharpeRatio(0),
                        firstTradeTime(0), lastTradeTime(0), consecutiveWins(0), consecutiveLosses(0),
                        maxConsecutiveWins(0), maxConsecutiveLosses(0), avgHoldTimeHours(0),
                        bestTradeProfit(0), worstTradeLoss(0) {}
};

// Position management parameters
struct SPositionParams
{
    double breakevenTrigger;
    double breakevenBuffer;
    double trailStart;
    double trailDistance;
    double trailStep;
    double partialClosePct;
    double partialCloseTrigger;
    bool enableBreakeven;
    bool enableTrailing;
    bool enablePartialClose;
    bool enablePyramiding;
    double pyramidTrigger;
    double pyramidVolumeMultiplier;
    int maxPyramidEntries;

    SPositionParams() : breakevenTrigger(0), breakevenBuffer(0), trailStart(0), trailDistance(0), trailStep(0),
                       partialClosePct(0), partialCloseTrigger(0), enableBreakeven(false), enableTrailing(false),
                       enablePartialClose(false), enablePyramiding(false), pyramidTrigger(0), pyramidVolumeMultiplier(0),
                       maxPyramidEntries(0) {}
};

// Trade validation result
struct STradeValidationResult
{
    bool isValid;
    string rejectionReason;
    uint rejectionCode;
    double recommendedVolume;
    double maxAllowedVolume;
    double riskAmount;
    double riskPercent;

    STradeValidationResult() : isValid(true), rejectionReason(""), rejectionCode(0),
                              recommendedVolume(0), maxAllowedVolume(0), riskAmount(0), riskPercent(0) {}
};

#endif // CORE_TRADE_TYPES_MQH