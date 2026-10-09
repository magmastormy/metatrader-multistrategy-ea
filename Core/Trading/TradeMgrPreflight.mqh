//+------------------------------------------------------------------+
//| TradeMgrPreflight.mqh                                            |
//| Pre-send gating + post-send receipt confirmation for CTradeManager|
//|                                                                  |
//| Extracted from Core/Trading/TradeManager.mqh (God-Object split). |
//| All members are static pure functions - this module holds NO     |
//| instance state. Bodies are verbatim copies of the original       |
//| CTradeManager methods:                                           |
//|   - ApplyFillingModeForSymbol   (IOC/FOK selection by spread/ATR)|
//|   - ValidateExecutionPreflight  (session/tick/spread/drift gates)|
//|   - ConfirmExecutionReceipt     (history-deal confirmation)      |
//|                                                                  |
//| NO BACK-POINTER: every piece of CTradeManager state these three  |
//| need is passed in explicitly - the CTrade / CSessionManager /    |
//| CATRCache / CMarketAnalysis objects by reference (or pointer,    |
//| for the optional market-analysis dependency), the tunables as    |
//| plain values, and the execution receipt as an in/out reference.  |
//| Same pattern already used by CPositionStateTracker.              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_MGR_PREFLIGHT_MQH
#define CORE_TRADING_TRADE_MGR_PREFLIGHT_MQH

#include <Trade/Trade.mqh>
#include "../Utils/SessionManager.mqh"
#include "../Utils/Instruments.mqh"
#include "../Utils/MagicRange.mqh"
#include "../Cache/ATRCache.mqh"
#include "../Engines/MarketAnalysis.mqh"
#include "TradeTypes.mqh"
#include "TradeMgrPricing.mqh"
#include "TradeMgrConfirmationQueue.mqh"

//+------------------------------------------------------------------+
//| Trade Manager Preflight                                          |
//+------------------------------------------------------------------+
class CTradeMgrPreflight
{
public:
    //+--------------------------------------------------------------+
    //| Choose and apply the broker fill policy for a symbol         |
    //+--------------------------------------------------------------+
    static void ApplyFillingModeForSymbol(const string symbolParam,
                                          CTrade &trade,
                                          CMarketAnalysis *marketAnalysis,
                                          const ENUM_ORDER_TYPE_FILLING orderFillMode)
    {
        if(symbolParam == "")
            return;

        // Analyze market conditions to choose appropriate fill mode
        bool useIOC = true;

        // Get spread for the symbol
        double spreadPoints = (double)SymbolInfoInteger(symbolParam, SYMBOL_SPREAD);
        double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
        if(point <= 0.0)
            point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001; // Fallback for invalid symbol data

        // Get ATR volatility to assess market conditions
        double volatilityMultiplier = 1.0;
        if(marketAnalysis != NULL)
        {
            double atr = marketAnalysis.GetATR(symbolParam, 14);
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
            trade.SetTypeFilling(ORDER_FILLING_IOC);
        }
        else
        {
            trade.SetTypeFilling(ORDER_FILLING_FOK);
        }

        // Batch 151: keep the IOC/FOK decision unless the symbol does not
        // support it.
        // Batch 169: the fallback used to be `orderFillMode`, which the trade
        // manager initialises to ORDER_FILLING_IOC - so on a broker that allows
        // neither FOK nor IOC the sender still shipped IOC and the order was
        // rejected with INVALID_FILL (10030). ORDER_FILLING_RETURN imposes no fill
        // constraint and is accepted universally; SL/TP travel in the same request,
        // so RETURN does not expose an unprotected-fill window.
        const int fillingFlags = (int)SymbolInfoInteger(symbolParam, SYMBOL_FILLING_MODE);
        const bool iocAllowed = ((fillingFlags & SYMBOL_FILLING_IOC) != 0);
        const bool fokAllowed = ((fillingFlags & SYMBOL_FILLING_FOK) != 0);
        if(useIOC && !iocAllowed)
            trade.SetTypeFilling(fokAllowed ? ORDER_FILLING_FOK : ORDER_FILLING_RETURN);
        else if(!useIOC && !fokAllowed)
            trade.SetTypeFilling(iocAllowed ? ORDER_FILLING_IOC : ORDER_FILLING_RETURN);
    }

    //+--------------------------------------------------------------+
    //| Hard gates evaluated immediately before a market send        |
    //+--------------------------------------------------------------+
    static bool ValidateExecutionPreflight(const string symbolName,
                                           const ENUM_ORDER_TYPE orderType,
                                           const double executionPrice,
                                           const double requestedPrice,
                                           CSessionManager &sessionManager,
                                           CATRCache &atrCache,
                                           const double maxEntrySpreadPoints,
                                           const double maxEntryDriftPoints,
                                           const int dynamicSlippageAtrPeriod,
                                           string &reason)
    {
        reason = "";
        if(!sessionManager.IsMarketOpen(symbolName))
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
        if(maxEntrySpreadPoints > 0.0 && spreadPoints > maxEntrySpreadPoints)
        {
            reason = StringFormat("spread_points %.1f exceeds %.1f", spreadPoints, maxEntrySpreadPoints);
            return false;
        }

        if(maxEntryDriftPoints > 0.0 && requestedPrice > 0.0)
        {
            double driftPoints = MathAbs(executionPrice - requestedPrice) / point;
            double effectiveDriftLimit = maxEntryDriftPoints;
            double atr = atrCache.GetATR(symbolName, PERIOD_M15);
            if(atr == EMPTY_VALUE || atr <= 0.0)
            {
                atr = CTradeMgrPricing::CalculateATR(symbolName, PERIOD_M15, dynamicSlippageAtrPeriod);
                if(atr > 0.0)
                {
                    datetime barTime = iTime(symbolName, PERIOD_M15, 0);
                    atrCache.StoreATR(symbolName, PERIOD_M15, atr, barTime);
                }
            }

            // Fix #12-13: Symbol-class-aware drift limits for synthetic indices
            bool isSynthetic = IsSyntheticIndexSymbolName(symbolName);
            double atrMultiplier = isSynthetic ? 0.50 : 0.30;
            double spreadFloorMultiplier = isSynthetic ? 3.0 : 2.0;

            if(atr > 0.0)
                effectiveDriftLimit = MathMax(effectiveDriftLimit, (atr / point) * atrMultiplier);
            effectiveDriftLimit = MathMax(effectiveDriftLimit, spreadPoints * spreadFloorMultiplier);

            if(isSynthetic)
            {
                PrintFormat("[DRIFT-SYNTHETIC] symbol=%s | atr_mult=%.2f | spread_floor_mult=%.1f | drift_limit=%.1f | atr_pts=%.1f",
                            symbolName, atrMultiplier, spreadFloorMultiplier, effectiveDriftLimit,
                            (atr > 0.0) ? (atr / point) : 0.0);
            }

            if(driftPoints > effectiveDriftLimit)
            {
                reason = StringFormat("entry_drift_points %.1f exceeds %.1f", driftPoints, effectiveDriftLimit);
                return false;
            }
        }

        // Batch 169: the anomaly floor must come from the broker's declared stop
        // level, not from GetMinimumStopDistance(). That helper now folds a 1.5x
        // spread term into its result, so `minStopDistance * 2` was always at
        // least 3x the spread and this gate could never fire.
        double brokerStopDistance = CTradeMgrPricing::GetBrokerStopLevelDistance(symbolName);
        double spreadHardLimit = MathMax(brokerStopDistance * 2.0, executionPrice * 0.0015);
        if(spread > spreadHardLimit)
        {
            reason = StringFormat("spread_anomaly spread=%.5f limit=%.5f", spread, spreadHardLimit);
            return false;
        }

        // Batch 169: the absolute maxEntrySpreadPoints gate is a catastrophic-quote
        // backstop only - it is deliberately loose (15000 points) so synthetic
        // indices, whose normal spreads run into four figures, are not filtered
        // wholesale. The relative gate above (0.15% of price) is what protects
        // FX and metals; the expectancy gate in NormalizeAndValidateStops is what
        // stops a wide spread swallowing a narrow target.

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

    //+--------------------------------------------------------------+
    //| Confirm a broker-accepted send against deal history          |
    //+--------------------------------------------------------------+
    static bool ConfirmExecutionReceipt(const string symbolName,
                                        const ENUM_ORDER_TYPE orderType,
                                        const double requestedVolume,
                                        const double fallbackPrice,
                                        const MqlTradeResult &tradeResult,
                                        STradeExecutionReceipt &receipt,
                                        CTradeMgrConfirmationQueue &confirmationQueue)
    {
        datetime historyFrom = TimeCurrent() - 300;
        datetime historyTo = TimeCurrent() + 60;

        // Single non-blocking check - no Sleep loop
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
                        receipt.filledVolume = dealVolume;
                    if(dealPrice > 0.0)
                        receipt.averagePrice = dealPrice;
                    else if(receipt.averagePrice <= 0.0)
                        receipt.averagePrice = fallbackPrice;

                    receipt.accepted = true;
                    receipt.partialFill = (receipt.filledVolume > 0.0 &&
                                           receipt.filledVolume + 1e-8 < requestedVolume);
                    receipt.note = "history_deal_confirmed";
                    return true;
                }
            }
        }

        // Deal not found yet - defer to pending confirmation for later resolution.
        //
        // Batch 169: two holes closed here.
        // (1) Enqueue() only stores the entry when orderTicket > 0, so a broker that
        //     returns order=0 left the send accepted but permanently untracked - no
        //     resolver would ever look at it. That case is now logged at CRITICAL.
        // (2) A deferred send was claimed accepted with filledVolume forced to 0.
        //     Before accepting that, check whether the position actually exists on
        //     the terminal: a fill that has no visible deal yet still produces a
        //     position, and confirming from the position (with its real volume)
        //     keeps the journal and the risk ledger truthful instead of optimistic.
        if(tradeResult.order > 0)
            confirmationQueue.Enqueue(symbolName, tradeResult.order, fallbackPrice);
        else
            PrintFormat("[EXECUTION-UNTRACKABLE] %s | retcode=%u | broker returned order=0, deferred confirmation is impossible - relying on position scan",
                        symbolName, tradeResult.retcode);

        ulong filledTicket = 0;
        double filledVolume = 0.0;
        if(FindFreshPositionForSend(symbolName, orderType, requestedVolume, filledTicket, filledVolume))
        {
            receipt.accepted = true;
            receipt.filledVolume = filledVolume;
            if(receipt.averagePrice <= 0.0)
                receipt.averagePrice = fallbackPrice;
            receipt.partialFill = (filledVolume > 0.0 && filledVolume + 1e-8 < requestedVolume);
            receipt.note = "position_confirmed_deferred";
            PrintFormat("[EXECUTION-CONFIRMED-BY-POSITION] %s | ticket=%I64u | filled=%.2f of %.2f | retcode=%u (no deal visible yet)",
                        symbolName, filledTicket, filledVolume, requestedVolume, tradeResult.retcode);
            return true;
        }

        // Optimistic return - broker accepted the order, confirmation deferred
        receipt.accepted = true;
        if(receipt.averagePrice <= 0.0)
            receipt.averagePrice = fallbackPrice;
        if(receipt.filledVolume <= 0.0)
            receipt.filledVolume = 0.0;
        receipt.note = "broker_accept_deferred";
        return true;
    }

    //+--------------------------------------------------------------+
    //| Find a position that just appeared for this send             |
    //| Used to confirm a fill whose deal is not in history yet, and  |
    //| to stop a retry duplicating an order the server already dealt. |
    //+--------------------------------------------------------------+
    static bool FindFreshPositionForSend(const string symbolName,
                                         const ENUM_ORDER_TYPE orderType,
                                         const double requestedVolume,
                                         ulong &ticketOut,
                                         double &volumeOut)
    {
        ticketOut = 0;
        volumeOut = 0.0;

        // Only positions opened in the last 30 s count, so pre-existing positions on
        // the same symbol (other strategies, earlier layers) cannot be mistaken for
        // this send.
        datetime cutoff = TimeCurrent() - 30;
        ENUM_POSITION_TYPE wantType = (orderType == ORDER_TYPE_BUY)
                                      ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != symbolName) continue;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != wantType) continue;
            if(!IsMagicOwned(PositionGetInteger(POSITION_MAGIC))) continue;
            if((datetime)PositionGetInteger(POSITION_TIME) < cutoff) continue;

            ticketOut = ticket;
            volumeOut = PositionGetDouble(POSITION_VOLUME);
            return true;
        }
        return false;
    }
};

#endif // CORE_TRADING_TRADE_MGR_PREFLIGHT_MQH
//+------------------------------------------------------------------+
