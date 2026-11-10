// Pre-send gating + post-send receipt confirmation for CTradeManager
// Static members, no instance state: every CTradeManager dependency arrives as a parameter -
// CTrade/CSessionManager/CATRCache by reference, CMarketAnalysis by pointer (optional),
// tunables by value, the receipt in/out.
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

class CTradeMgrPreflight
{
public:
// Choose and apply the broker fill policy for a symbol
    static void ApplyFillingModeForSymbol(const string symbolParam,
                                          CTrade &trade,
                                          CMarketAnalysis *marketAnalysis,
                                          const ENUM_ORDER_TYPE_FILLING orderFillMode)
    {
        if(symbolParam == "")
            return;

        bool useIOC = true;

        double spreadPoints = (double)SymbolInfoInteger(symbolParam, SYMBOL_SPREAD);
        double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
        if(point <= 0.0)
            point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001; // Fallback for invalid symbol data

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

        if(useIOC)
        {
            trade.SetTypeFilling(ORDER_FILLING_IOC);
        }
        else
        {
            trade.SetTypeFilling(ORDER_FILLING_FOK);
        }

        // The caller's orderFillMode is not consulted: the fallback comes from SYMBOL_FILLING_MODE,
        // because sending an IOC/FOK the symbol disallows is rejected with INVALID_FILL (10030).
        // ORDER_FILLING_RETURN imposes no fill constraint and is accepted by every broker; SL/TP
        // travel in the same request, so RETURN leaves no unprotected-fill window.
        const int fillingFlags = (int)SymbolInfoInteger(symbolParam, SYMBOL_FILLING_MODE);
        const bool iocAllowed = ((fillingFlags & SYMBOL_FILLING_IOC) != 0);
        const bool fokAllowed = ((fillingFlags & SYMBOL_FILLING_FOK) != 0);
        if(useIOC && !iocAllowed)
            trade.SetTypeFilling(fokAllowed ? ORDER_FILLING_FOK : ORDER_FILLING_RETURN);
        else if(!useIOC && !fokAllowed)
            trade.SetTypeFilling(iocAllowed ? ORDER_FILLING_IOC : ORDER_FILLING_RETURN);
    }

// Hard gates evaluated immediately before a market send
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

            // Synthetics quote four-figure spreads, so both multipliers below are looser for them.
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

        // The floor must be the broker's declared stop level: GetMinimumStopDistance() already folds
        // in 1.5x the spread, so a multiple of it is circular and this gate could never fire.
        double brokerStopDistance = CTradeMgrPricing::GetBrokerStopLevelDistance(symbolName);
        double spreadHardLimit = MathMax(brokerStopDistance * 2.0, executionPrice * 0.0015);
        if(spread > spreadHardLimit)
        {
            reason = StringFormat("spread_anomaly spread=%.5f limit=%.5f", spread, spreadHardLimit);
            return false;
        }

        // The absolute gate is a loose catastrophic-quote backstop (15000 points) so four-figure
        // synthetic spreads are not filtered wholesale; the 0.15%-of-price gate above protects FX and metals.
        // A wide spread swallowing a narrow target is rejected by the TP-cost gate in NormalizeAndValidateStops.

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

// Confirm a broker-accepted send against deal history
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

        // A send with order=0 is never tracked by the resolver, and a fill can exist
        // as a position before its deal is visible - so confirm from the position.
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

        receipt.accepted = false;
        receipt.filledVolume = 0.0;
        receipt.note = "broker_accept_unconfirmed";
        PrintFormat("[EXECUTION-UNCONFIRMED-NO-FILL-EVIDENCE] %s | order=%I64u | retcode=%u - not treated as filled",
                    symbolName, tradeResult.order, tradeResult.retcode);
        return false;
    }

// Used to confirm a fill whose deal is not in history yet, and
// to stop a retry duplicating an order the server already dealt.
// Magic cannot separate these sends: a fast-scalp market order carries base + the same per-symbol
// offset the consensus path composes (TradeManager.mqh:1267), so on one symbol both owners look
// identical. The order comment is the discriminator the exit paths already trust, so an owner that
// names its prefix matches only its own positions, and one that names none matches only positions no
// engine claims.
    static bool HasEngineComment(const string comment)
    {
        return (StringFind(comment, "SCALP") == 0 ||
                StringFind(comment, "ATR-SCALP") == 0 ||
                StringFind(comment, "GRID-RECOVERY") == 0 ||
                StringFind(comment, "SPIKE-HUNT") == 0);
    }

    static bool FindFreshPositionForSend(const string symbolName,
                                         const ENUM_ORDER_TYPE orderType,
                                         const double requestedVolume,
                                         ulong &ticketOut,
                                         double &volumeOut,
                                         const string expectedCommentPrefix = "")
    {
        ticketOut = 0;
        volumeOut = 0.0;

        // Only positions opened within the last 30 s count, so pre-existing positions on the
        // same symbol (other strategies, earlier layers) cannot be mistaken for this send.
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

            string posComment = PositionGetString(POSITION_COMMENT);
            if(expectedCommentPrefix != "")
            {
                if(StringFind(posComment, expectedCommentPrefix) != 0) continue;
            }
            else if(HasEngineComment(posComment))
                continue;

            ticketOut = ticket;
            volumeOut = PositionGetDouble(POSITION_VOLUME);
            return true;
        }
        return false;
    }
};

#endif // CORE_TRADING_TRADE_MGR_PREFLIGHT_MQH
