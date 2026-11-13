// Owns the four plain-data structs of the scalp pipeline.
// FastScalpEngine.mqh #includes this header, so every existing
// consumer of these types keeps seeing them unchanged.
// Field order, defaults and comments are reproduced verbatim.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_TYPES_MQH
#define CORE_SCALP_FAST_SCALP_TYPES_MQH

struct SScalpConfig
{
   int      maxScalpPositions;       // Max concurrent scalp positions (3)
   double   scalpRiskPct;            // Risk % from tier scalpBudgetPct
   int      scalpSLPips;             // Tight SL in pips (50-80)
   int      scalpTPPips;             // TP in pips (75-120, 1.5-2x SL)
   int      scalpCooldownMs;         // Cooldown between scalps in ms (5000)
   int      fastEMA;                 // Fast EMA period (5)
   int      slowEMA;                 // Slow EMA period (13)
   int      rsiPeriod;
   double   rsiOverbought;           // RSI overbought level (75)
   double   rsiOversold;             // RSI oversold level (25)
   double   maxSpreadATRRatio;       // Reject if spread > 30% ATR (0.30)
   double   momentumBurstATRRatio;   // Bar body > 80% ATR (0.80)
   bool     usePendingOrders;        // Use pending limit orders (true)
   int      pendingOrderTTL;         // Pending order TTL in seconds (120)
   bool     partialCloseEnabled;     // Close 50% at 1R profit (true)
   int      breakevenProfitPoints;   // Points profit to trigger BE (10)
   int      breakevenBufferPoints;   // Buffer past entry for BE (5)
   int      trailingDistancePoints;

   // Default constructor with production defaults
   SScalpConfig()
   {
      maxScalpPositions       = 3;
      scalpRiskPct            = 3.0;
      scalpSLPips             = 60;
      scalpTPPips             = 90;
      scalpCooldownMs         = 5000;
      fastEMA                 = 5;
      slowEMA                 = 13;
      rsiPeriod               = 7;
      rsiOverbought           = 75.0;
      rsiOversold             = 25.0;
      maxSpreadATRRatio       = 0.30;
      momentumBurstATRRatio   = 0.80;
      usePendingOrders        = true;
      pendingOrderTTL         = 20;
      partialCloseEnabled     = true;
      breakevenProfitPoints   = 10;
      breakevenBufferPoints   = 5;
      trailingDistancePoints  = 15;
   }
};

struct SPendingScalpOrder
{
   ulong    ticket;
   string   symbol;
   ENUM_ORDER_TYPE orderType;
   double   lotSize;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit;
   datetime placedAt;
   bool     isActive;

   // Batch 152 (S-M-04): field-wise reset - ZeroMemory corrupts the reference
   // count of the string member.
   void Reset()
   {
      ticket     = 0;
      symbol     = "";
      orderType  = ORDER_TYPE_BUY;
      lotSize    = 0.0;
      entryPrice = 0.0;
      stopLoss   = 0.0;
      takeProfit = 0.0;
      placedAt   = 0;
      isActive   = false;
   }
};

// Async scalp order tracking (for OrderSendAsync confirmation)
struct SScalpPendingAsync
{
   ulong    orderTicket;
   string   symbol;
   int      direction;        // 1=BUY, -1=SELL
   double   lotSize;          // Requested lots
   double   entryPrice;       // Expected entry price
   double   stopLoss;         // SL price
   double   takeProfit;       // TP price
   uint     sendTimestampMs;  // GetTickCount at send time
   bool     confirmed;        // Whether deal was confirmed
   bool     expired;          // Whether order expired

   // Batch 152 (S-M-04): field-wise reset - ZeroMemory corrupts the reference
   // count of the string member.
   void Reset()
   {
      symbol          = "";
      orderTicket     = 0;
      direction       = 0;
      lotSize         = 0.0;
      entryPrice      = 0.0;
      stopLoss        = 0.0;
      takeProfit      = 0.0;
      sendTimestampMs = 0;
      confirmed       = false;
      expired         = false;
   }
};

// Reserved-budget ledger for async scalp orders that timed out but may still
// receive a late fill. Keyed by order ticket so OnDealConfirmed() can match a
// late deal, register the position, and keep the budget reserved instead of
// orphaning it. Budget is released only on a final zero-fill outcome.
struct SScalpReservedBudgetLedger
{
   ulong    orderTicket;        // key - the async order ticket
   string   symbol;
   int      direction;          // 1=BUY, -1=SELL
   double   lotSize;            // Requested lots
   double   entryPrice;         // Expected entry price
   double   stopLoss;           // SL price
   double   takeProfit;         // TP price
   uint     sendTimestampMs;    // GetTickCount at send time
   uint     quarantinedAtMs;    // GetTickCount when moved to the ledger
   double   riskReservedPct;    // risk budget reserved for this ticket
   bool     released;           // budget already released

   // Field-wise reset - ZeroMemory corrupts the reference count of the string member.
   void Reset()
   {
      symbol          = "";
      orderTicket     = 0;
      direction       = 0;
      lotSize         = 0.0;
      entryPrice      = 0.0;
      stopLoss        = 0.0;
      takeProfit      = 0.0;
      sendTimestampMs = 0;
      quarantinedAtMs = 0;
      riskReservedPct = 0.0;
      released        = false;
   }
};

// Scalp position state for tick-level management
struct SScalpPositionState
{
   ulong    ticket;
   string   symbol;
   bool     breakevenSet;
   bool     partialClosed;
   double   entryPrice;
   double   originalSL;
   double   originalTP;
   double   oneRProfitPrice;   // Price at 1R profit (for partial close)

   // Batch 152 (S-M-04): field-wise reset - ZeroMemory corrupts the reference
   // count of the string member.
   void Reset()
   {
      ticket          = 0;
      symbol          = "";
      breakevenSet    = false;
      partialClosed   = false;
      entryPrice      = 0.0;
      originalSL      = 0.0;
      originalTP      = 0.0;
      oneRProfitPrice = 0.0;
   }
};

#endif // CORE_SCALP_FAST_SCALP_TYPES_MQH

