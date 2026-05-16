//+------------------------------------------------------------------+
//| SymbolUniverseBuilder.mqh                                        |
//| Validates and builds the active trading symbol universe          |
//+------------------------------------------------------------------+
#ifndef __SYMBOL_UNIVERSE_BUILDER_MQH__
#define __SYMBOL_UNIVERSE_BUILDER_MQH__

#include "../Utils/Instruments.mqh"

class CSymbolUniverseBuilder
{
public:
    static bool ContainsSymbol(const string &activePairs[], const string symbol)
    {
        for(int i = 0; i < ArraySize(activePairs); i++)
        {
            if(activePairs[i] == symbol)
                return true;
        }
        return false;
    }

    static bool Build(const string rawSymbols, string &activePairs[])
    {
        ArrayResize(activePairs, 0);

        if(StringLen(rawSymbols) == 0)
        {
            Print("[ERROR] InpSymbolsToTrade is empty - no symbols to trade");
            return false;
        }

        string symbols[];
        int splitCount = StringSplit(rawSymbols, ',', symbols);
        if(splitCount == 0)
        {
            Print("[ERROR] Failed to parse InpSymbolsToTrade - malformed symbol string");
            return false;
        }

        Print("[SYMBOLS] Processing ", ArraySize(symbols), " trading symbols");

        for(int i = 0; i < ArraySize(symbols); i++)
        {
            string sym = symbols[i];
            StringTrimLeft(sym);
            StringTrimRight(sym);

            if(StringLen(sym) == 0)
            {
                Print("[SYMBOLS] Empty symbol token skipped at input index ", i, " - Please check InpSymbolsToTrade parameter for empty entries");
                continue;
            }

            string symUpper = sym;
            StringToUpper(symUpper);

            bool isSynthetic = (StringFind(symUpper, "VOL") >= 0  || StringFind(symUpper, "STEP") >= 0 ||
                                StringFind(symUpper, "BOOM") >= 0 || StringFind(symUpper, "CRASH") >= 0 ||
                                StringFind(symUpper, "JUMP") >= 0 || StringFind(symUpper, "PAINX") >= 0 ||
                                StringFind(symUpper, "PAIN ") >= 0 || StringFind(symUpper, "GAINX") >= 0 ||
                                StringFind(symUpper, "FLIPX") >= 0 || StringFind(symUpper, "FX VOL") >= 0 ||
                                StringFind(symUpper, "SWITCHX") >= 0);

            if(StringFind(sym, " ") >= 0 && StringFind(sym, ".") < 0 && !isSynthetic)
            {
                // AUDIT: Synthetic symbols often have spaces (e.g., "SFX Vol 20", "SwitchX 1200")
                // If it's synthetic but contains a space, we should still allow it if it's select-able
                if(!isSynthetic)
                {
                    Print("[WARNING] Symbol '", sym, "' contains spaces without period - likely malformed, skipping");
                    continue;
                }
            }

            if(!SymbolSelect(sym, true))
            {
                Print("[WARNING] Symbol ", sym, " not available - skipping");
                continue;
            }

            long symbolTradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
            if(symbolTradeMode == SYMBOL_TRADE_MODE_DISABLED)
            {
                Print("[WARNING] Symbol ", sym, " trading is disabled - skipping");
                continue;
            }
            if(symbolTradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
            {
                Print("[WARNING] Symbol ", sym, " is close-only - skipping");
                continue;
            }
            if(SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP) <= 0.0)
            {
                Print("[WARNING] Symbol ", sym, " has invalid volume step - skipping");
                continue;
            }

            if(ContainsSymbol(activePairs, sym))
            {
                Print("[SYMBOLS] Duplicate symbol skipped: ", sym);
                continue;
            }

            long spread = SymbolInfoInteger(sym, SYMBOL_SPREAD);
            if(spread > 1000)
            {
                PrintFormat("[SYMBOLS] Symbol %s rejected - extreme spread %d points exceeds maximum threshold (1000 points)", sym, spread);
                continue;
            }

            int size = ArraySize(activePairs);
            ArrayResize(activePairs, size + 1);
            activePairs[size] = sym;

            Print("[SYMBOL] ", sym, " - Configured for trading");
            Print("  - Spread: ", spread, " points");
            Print("  - Min Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN));
            Print("  - Max Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX));
            Print("  - Lot Step: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP));
            Print("  - Contract Size: ", SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE));
        }

        return (ArraySize(activePairs) > 0);
    }
};

#endif
