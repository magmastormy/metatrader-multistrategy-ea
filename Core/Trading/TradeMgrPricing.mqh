//+------------------------------------------------------------------+
//| TradeMgrPricing.mqh                                              |
//| Stateless price / volume / stop-level arithmetic for CTradeManager|
//|                                                                  |
//| Extracted from Core/Trading/TradeManager.mqh (God-Object split). |
//| Every member is a static pure function - this module holds NO    |
//| instance state. Bodies are verbatim copies of the original       |
//| CTradeManager methods, so execution behaviour is byte-identical. |
//|                                                                  |
//| NO BACK-POINTER: the two helpers that originally touched         |
//| CTradeManager state (GetCurrentExecutionPrice -> m_symbolInfo)   |
//| receive that object by reference, exactly like the pattern       |
//| already used by CPositionStateTracker.                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_MGR_PRICING_MQH
#define CORE_TRADING_TRADE_MGR_PRICING_MQH

#include <Trade/SymbolInfo.mqh>
#include "../../IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Trade Manager Pricing Helpers                                    |
//| Broker-constraint aware normalisation and cost arithmetic.       |
//+------------------------------------------------------------------+
class CTradeMgrPricing
{
public:
    //+--------------------------------------------------------------+
    //| Check if two double values are approximately equal           |
    //+--------------------------------------------------------------+
    static bool DoubleEquals(double a, double b, double epsilon = 0.00001)
    {
        return MathAbs(a - b) < epsilon;
    }

    //+--------------------------------------------------------------+
    //| Calculate Average True Range (ATR) for volatility measurement|
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Normalize Price                                              |
    //+--------------------------------------------------------------+
    static double NormalizePrice(const string symbolName, const double price)
    {
        if(price <= 0) {
            return 0.0;
        }

        int digits = (int)SymbolInfoInteger(symbolName, SYMBOL_DIGITS);
        return NormalizeDouble(price, digits);
    }

    //+--------------------------------------------------------------+
    //| Normalize Volume                                             |
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Calculate Stop Loss                                          |
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Calculate Take Profit                                        |
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Check whether symbol trade mode supports requested order type|
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Current execution price for a market order                   |
    //| symbolInfo is the caller-owned CSymbolInfo (was m_symbolInfo)|
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Broker minimum stop/freeze distance                          |
    //+--------------------------------------------------------------+
    static double GetMinimumStopDistance(const string symbolName)
    {
        double point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
        if(point <= 0.0) {
            return 0.0;
        }

        int stopLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_STOPS_LEVEL);
        int freezeLevel = (int)SymbolInfoInteger(symbolName, SYMBOL_TRADE_FREEZE_LEVEL);
        int requiredPoints = MathMax(stopLevel, freezeLevel);

        return (double)requiredPoints * point;
    }

    //+--------------------------------------------------------------+
    //| Normalize and Validate Stops                                 |
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Get Round-Trip Commission Cost (entry + exit)                |
    //+--------------------------------------------------------------+
    static double GetRoundTripCommissionCost(const string symbol, const double volume)
    {
        double commission = 0.0;

        // Check for explicit commission (per lot, per side)
        // NOTE: MQL5 has no SYMBOL_TRADE_COMMISSION constant; commission is broker-set
        // and not directly queryable. Fall through to spread-based estimation below.
        double commissionPerLot = 0.0;
        if(commissionPerLot > 0.0)
        {
            // Commission is charged per side, so round-trip = 2 * commissionPerLot * volume
            commission = commissionPerLot * 2.0 * volume;
        }
        else
        {
            // Many synthetic brokers embed commission in spread
            // Estimate via spread cost: spread * tickValue * volume
            double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
            double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

            if(spread > 0.0 && tickValue > 0.0 && tickSize > 0.0)
            {
                double spreadPoints = spread / tickSize;
                commission = spreadPoints * tickValue * volume; // Entry + exit spread cost
            }
        }

        return commission;
    }

    //+--------------------------------------------------------------+
    //| Get Estimated Swap Cost for holding position overnight       |
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Calculate Position Risk                                      |
    //+--------------------------------------------------------------+
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

    //+--------------------------------------------------------------+
    //| Get net position volume for netting mode compliance          |
    //+--------------------------------------------------------------+
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
