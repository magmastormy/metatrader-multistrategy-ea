// Stateless price / volume / stop-level arithmetic for CTradeManager
// Extracted from Core/Trading/TradeManager.mqh (God-Object split).
// Every member is a static pure function - this module holds NO
// instance state. Bodies are verbatim copies of the original
// CTradeManager methods, so execution behaviour is byte-identical.
// NO BACK-POINTER: the two helpers that originally touched
// CTradeManager state (GetCurrentExecutionPrice -> m_symbolInfo)
// receive that object by reference, exactly like the pattern
// already used by CPositionStateTracker.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_MGR_PRICING_MQH
#define CORE_TRADING_TRADE_MGR_PRICING_MQH

#include <Trade/SymbolInfo.mqh>
#include "../../IndicatorManager.mqh"

// A stop inside 1.5 spreads is noise, and brokers often report stops level 0, hence
// MIN_STOP_DISTANCE_POINTS. Lots are sized on the requested stop, so a broker-forced
// widening past MAX_ACCEPTABLE_STOP_WIDENING_RATIO risks more than was authorised.
#ifndef MIN_STOP_SPREAD_MULTIPLIER
#define MIN_STOP_SPREAD_MULTIPLIER 1.5
#endif
#ifndef MIN_STOP_DISTANCE_POINTS
#define MIN_STOP_DISTANCE_POINTS 10
#endif
#ifndef MAX_ACCEPTABLE_STOP_WIDENING_RATIO
#define MAX_ACCEPTABLE_STOP_WIDENING_RATIO 1.25
#endif
#ifndef MIN_TP_COST_MULTIPLE
#define MIN_TP_COST_MULTIPLE 4.0
#endif

// Trade Manager Pricing Helpers
// Broker-constraint aware normalisation and cost arithmetic.
class CTradeMgrPricing
{
public:
// Check if two double values are approximately equal
    static bool DoubleEquals(double a, double b, double epsilon = 0.00001)
    {
        return MathAbs(a - b) < epsilon;
    }

// Calculate Average True Range (ATR) for volatility measurement
    static double CalculateATR(const string symbolParam, ENUM_TIMEFRAMES timeframe, int period)
    {
        double atrValues[];
        CIndicatorManager* manager = CIndicatorManager::Instance();
        if(manager == NULL) {
            return 0.0;
        }

        int atrHandle = manager.GetATRHandle(symbolParam, timeframe, period);
        if(atrHandle == INVALID_HANDLE) {
            return 0.0;
        }

        if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) > 0)
        {
            return atrValues[0];
        }
        return 0.0;
    }

    static double NormalizePrice(const string symbolName, const double price)
    {
        if(price <= 0) {
            return 0.0;
        }

        int digits = (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);
        return NormalizeDouble(price, digits);
    }

    static double NormalizeVolume(const string symbolName, const double volume)
    {
        double minVolume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
        double maxVolume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MAX);
        double stepVolume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
        if(stepVolume <= 0.0 || !MathIsValidNumber(stepVolume))
            stepVolume = 0.01;

        if(volume < minVolume || !MathIsValidNumber(volume)) {
            return 0.0;
        }

        int volumeDigits = 0;
        double stepProbe = stepVolume;
        while(volumeDigits < 8 && MathAbs(stepProbe - MathRound(stepProbe)) > 1e-8 && MathIsValidNumber(stepProbe))
        {
            stepProbe *= 10.0;
            volumeDigits++;
        }

        double normalized = MathFloor((volume + 1e-12) / stepVolume) * stepVolume;
        normalized = NormalizeDouble(normalized, volumeDigits);
        normalized = MathMin(normalized, maxVolume);

        if(normalized < minVolume) {
            return 0.0;
        }

        return normalized;
    }

    static double CalculateStopLoss(const string symbolParam, const ENUM_ORDER_TYPE orderType,
                                    const double price, const double stopLossPips)
    {
        if(stopLossPips <= 0) {
            return 0.0;
        }

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

    static double CalculateTakeProfit(const string symbolParam, const ENUM_ORDER_TYPE orderType,
                                      const double price, const double takeProfitPips)
    {
        if(takeProfitPips <= 0) {
            return 0.0;
        }

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

// Check whether symbol trade mode supports requested order type
    static bool IsOrderTypeAllowedForSymbol(const string symbolName, const ENUM_ORDER_TYPE orderType, string &reason)
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

// Current execution price for a market order
// symbolInfo is the caller-owned CSymbolInfo (was m_symbolInfo)
    static double GetCurrentExecutionPrice(const string symbolName, const ENUM_ORDER_TYPE orderType,
                                           CSymbolInfo &symbolInfo)
    {
        double price = (orderType == ORDER_TYPE_SELL) ?
                       SymbolInfoDouble(symbolName, SYMBOL_BID) :
                       SymbolInfoDouble(symbolName, SYMBOL_ASK);

        if(price <= 0.0)
        {
            symbolInfo.Name(symbolName);
            symbolInfo.Refresh();
            price = (orderType == ORDER_TYPE_SELL) ?
                    SymbolInfoDouble(symbolName, SYMBOL_BID) :
                    SymbolInfoDouble(symbolName, SYMBOL_ASK);
        }

        return NormalizePrice(symbolName, price);
    }

// Broker minimum stop/freeze distance
    static double GetMinimumStopDistance(const string symbolName)
    {
        double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
        if(point <= 0.0) {
            return 0.0;
        }

        int stopLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_STOPS_LEVEL);
        int freezeLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_FREEZE_LEVEL);
        int requiredPoints = MathMax(stopLevel, freezeLevel);

        // Batch 169: floor. Many brokers report SYMBOL_TRADE_STOPS_LEVEL = 0, which
        // previously produced a 0-point minimum, so a 1-point stop was accepted and
        // then rejected by the server (INVALID_STOPS) or placed inside the spread
        // where it triggers on noise. Require the greater of the broker level, a
        // spread multiple (a stop inside the spread is not a stop) and 10 points.
        int spreadPoints = (int)SymbolInfoInteger(symbolName, SYMBOL_SPREAD);
        int spreadBasedMinimum = (int)MathCeil(spreadPoints * MIN_STOP_SPREAD_MULTIPLIER);
        requiredPoints = MathMax(requiredPoints, MathMax(spreadBasedMinimum, MIN_STOP_DISTANCE_POINTS));

        return (double)requiredPoints * point;
    }

// Broker-declared stop/freeze distance only, in price units.
// GetMinimumStopDistance() deliberately folds in a spread
// multiple, which makes it circular for the spread-anomaly gate
// in preflight: a limit of 2 * (1.5 * spread) can never be
// exceeded by that spread. This is the term that belongs there.
    static double GetBrokerStopLevelDistance(const string symbolName)
    {
        double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
        if(point <= 0.0) {
            return 0.0;
        }
        int stopLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_STOPS_LEVEL);
        int freezeLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_FREEZE_LEVEL);
        return (double)MathMax(stopLevel, freezeLevel) * point;
    }

// Round-trip transaction cost, expressed in PRICE units
// Buying at ask and selling at bid costs exactly one quoted
// spread against the mid, so the factor is 1.0 - the previous
// 2.0 "paid entering and leaving" double-counted the same half
// spread on each side and every risk estimate that adds this
// term was inflated accordingly.
    static double GetRoundTripCostPrice(const string symbol)
    {
        double spreadPoints = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(spreadPoints <= 0.0 || point <= 0.0)
            return 0.0;
        return spreadPoints * point;
    }

    static bool NormalizeAndValidateStops(const string symbol,
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

        // Batch 169: capture the distance the position was SIZED at before any
        // broker-driven adjustment, and be able to reject. This function used to
        // `return true` unconditionally, which made the caller's reject branch dead
        // code, and it silently pushed a too-close SL out to minDistance *after*
        // lot sizing - so realised risk exceeded sized risk by however much the
        // stop widened, escaping the per-trade risk cap (which is evaluated on the
        // pre-trade stopLossPips).
        double requestedSlDistance = (slOut > 0.0) ? MathAbs(price - slOut) : 0.0;

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

        double finalSlDistance = (slOut > 0.0) ? MathAbs(price - slOut) : 0.0;
        if(requestedSlDistance > 0.0 && finalSlDistance > requestedSlDistance * MAX_ACCEPTABLE_STOP_WIDENING_RATIO)
        {
            errorMsg = StringFormat("SL widened from %.1f to %.1f points (%.2fx) to satisfy broker minimum %.1f points - lots were sized on the tighter stop, so this trade would risk more than authorised",
                                    requestedSlDistance / point, finalSlDistance / point,
                                    finalSlDistance / requestedSlDistance, minDistance / point);
            return false;
        }

        // Batch 169: cost-aware target. Nothing in the entry path compared the
        // reward with the round-trip cost - the absolute spread gate was set to
        // 15000 points so it never bound either. A take-profit that does not
        // clear a small multiple of the spread is negative expectancy before
        // the first tick, so reject it here, the one place both are known.
        double costPrice = GetRoundTripCostPrice(symbol);
        if(tpOut > 0.0 && costPrice > 0.0 && point > 0.0)
        {
            double tpDistance = MathAbs(price - tpOut);
            double requiredTp = costPrice * MIN_TP_COST_MULTIPLE;
            if(tpDistance < requiredTp)
            {
                errorMsg = StringFormat("TP distance %.1f points is below %.1f points (%.0fx the %.1f-point round-trip cost) - target does not pay for the spread",
                                        tpDistance / point, requiredTp / point,
                                        MIN_TP_COST_MULTIPLE, costPrice / point);
                return false;
            }
        }

        return true;
    }

// Get Round-Trip Commission Cost (entry + exit)
    static double GetRoundTripCommissionCost(const string symbol, const double volume)
    {
        // SYMBOL_SPREAD is already points - dividing it by tickSize again inflated
        // every risk estimate by ~10^5. Per-lot commission has no MQL5 constant;
        // brokers charging it go through CTradeSpreadCostModel.
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

        double costPrice = GetRoundTripCostPrice(symbol);
        if(costPrice <= 0.0 || point <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0)
            return 0.0;

        double moneyPerPoint = (tickValue / tickSize) * point;
        double costPoints = costPrice / point;
        return costPoints * moneyPerPoint * volume;
    }

// Get Estimated Swap Cost for holding position overnight
    static double GetEstimatedSwapCost(const string symbol, const ENUM_ORDER_TYPE orderType,
                                       const double volume, const int estimatedHoldDays)
    {
        if(estimatedHoldDays <= 0) { return 0.0; }

        double swapLong = SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
        double swapShort = SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);

        double swapPerLot = (orderType == ORDER_TYPE_BUY) ? swapLong : swapShort;

        // Swap is typically in points per lot per day
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

        if(point <= 0 || tickValue <= 0 || tickSize <= 0) {
            return 0.0;
        }

        // Convert swap points to currency per lot per day
        double swapPerLotPerDay = (swapPerLot * point / tickSize) * tickValue;

        return swapPerLotPerDay * volume * estimatedHoldDays;
    }

    static double CalculatePositionRisk(const string symbolParam, const double volume,
                                        const double stopLossPips)
    {
        double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_SIZE);
        double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);

        if(tickValue <= 0 || tickSize <= 0 || point <= 0) {
            return 0.0;
        }

        double stopDistancePrice = stopLossPips * point;
        double riskPerLot = (stopDistancePrice / tickSize) * tickValue;

        // L10-006: Add commission cost to risk calculation
        double commissionCost = GetRoundTripCommissionCost(symbolParam, volume);
        return volume * riskPerLot + commissionCost;
    }

// Get net position volume for netting mode compliance
    static double GetNetPositionVolume(const string symbol, ENUM_POSITION_TYPE type,
                                       const ENUM_ACCOUNT_MARGIN_MODE accountMarginMode)
    {
        if(accountMarginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
            return 0.0; // Not applicable in hedging mode

        double netVolume = 0.0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == symbol)
                {
                    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    if(posType == type)
                        netVolume += PositionGetDouble(POSITION_VOLUME);
                }
            }
        }
        return netVolume;
    }
};

#endif // CORE_TRADING_TRADE_MGR_PRICING_MQH
//+------------------------------------------------------------------+
