//+------------------------------------------------------------------+
//| Intelligent Trading Process Function                             |
//| Replaces aggressive high-frequency trading with smart logic      |
//+------------------------------------------------------------------+

#include <Trade\SymbolInfo.mqh>

#include "MultiStrategySelection.mqh"
#include "DirectTradeExecution.mqh"
#include "IntelligentRiskFunctions.mqh"
#include "Core\IntegrationHub.mqh"

static CSymbolInfo s_processSymbolInfo;

bool IsTradeManagerReady()
{
    return (CheckPointer(&tradeManager) != POINTER_INVALID);
}

bool IsStrategyManagerReady()
{
    return (CheckPointer(&strategyManager) != POINTER_INVALID);
}

SEnhancedTradeSignal GenerateNextGenAISignal(const string &symbol)
{
    SEnhancedTradeSignal signal;
    signal.signal = TRADE_SIGNAL_NONE;
    signal.confidence = 0.0;
    signal.reasoning = "AI Hub unavailable";
    signal.timestamp = TimeCurrent();
    signal.signalTime = signal.timestamp;
    signal.sourceStrategy = STRATEGY_AI_ENHANCED;

    if(!AIHubIsReady())
    {
        Print("[AI-SIGNAL] AI hub not ready. Returning neutral signal for ", symbol);
        return signal;
    }

    if(!AIHubGenerateAISignal(signal))
    {
        Print("[AI-SIGNAL] Generation failed for ", symbol, " - using neutral fallback");
        return signal;
    }

    if(signal.confidence < 0.1)
        signal.confidence = 0.1;

    signal.timestamp = TimeCurrent();
    signal.signalTime = signal.timestamp;
    signal.sourceStrategy = STRATEGY_AI_ENHANCED;

    return signal;
}

//+------------------------------------------------------------------+
//| Process intelligent trading with all safety checks               |
//+------------------------------------------------------------------+
void ProcessIntelligentTrading()
{
    Print("[INTELLIGENT-TRADING] Starting intelligent trading process...");
    
    // Parse symbols to trade
    string syms[];
    int symCount = StringSplit(g_symbolsToTrade, ',', syms);
    
    if(symCount <= 0) {
        Print("[ERROR] No symbols configured for trading");
        return;
    }
    
    Print("[INTELLIGENT-TRADING] Processing ", symCount, " symbols with intelligent controls");
    
    // Process each symbol with intelligent controls
    for(int i = 0; i < ArraySize(syms); i++)
    {
        string symbol = syms[i];
        StringTrimLeft(symbol);
        StringTrimRight(symbol);
        syms[i] = symbol;
        
        if(StringLen(symbol) == 0) continue;
        
        // TIMING CONTROL: Prevent machine-gun trading
        if(TimeCurrent() - g_lastTradeTime < g_minTimeBetweenTrades) {
            Print("[TIMING] Skipping ", symbol, " - too soon since last trade");
            continue;
        }
        
        // POSITION LIMIT CHECK
        if(g_totalActivePositions >= g_maxPositionsAllowed) {
            Print("[RISK] Maximum positions reached (", g_totalActivePositions, "/", g_maxPositionsAllowed, ")");
            break; // Stop processing more symbols
        }
        
        // Check if symbol is available
        if(!SymbolSelect(symbol, true)) {
            Print("[WARNING] Symbol ", symbol, " not available");
            continue;
        }
        
        // Update symbol info
        if(!s_processSymbolInfo.Name(symbol)) {
            Print("[ERROR] Failed to initialize symbol info for ", symbol);
            continue;
        }
        
        // CORRELATION CHECK: Block highly correlated trades
        if(HasHighlyCorrelatedPosition(symbol)) {
            Print("[CORRELATION] Blocking ", symbol, " due to high correlation with existing position");
            continue;
        }
        
        // MARKET REGIME CHECK: Adapt strategy to market conditions
        if(!IsStrategyValidForRegime(symbol, g_currentRegime)) {
            Print("[REGIME] Skipping ", symbol, " - strategy not suitable for current market regime: ", EnumToString(g_currentRegime));
            continue;
        }
        
        // DATA VALIDATION: Ensure we have sufficient data
        if(!ValidateMarketData(symbol)) {
            Print("[DATA] Insufficient data for ", symbol, " - skipping");
            continue;
        }
        
        // Get AI signal for this symbol
        SEnhancedTradeSignal aiSignal = GenerateNextGenAISignal(symbol);
        
        // MULTI-STRATEGY SELECTION: Rotate between all available strategies
        ENUM_TRADE_SIGNAL signal = GetMultiStrategySignal(symbol, g_currentRegime);
        
        // INTELLIGENT SIGNAL FUSION: Combine AI and strategy signals
        signal = FuseAIAndStrategySignals(signal, aiSignal, symbol);
        
        // Execute trade if signal is valid
        if(signal != TRADE_SIGNAL_NONE)
        {
            ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            
            // ADAPTIVE STOP LOSS: Adjust based on volatility and market regime
            double stopLossPips = CalculateAdaptiveStopLoss(symbol, g_currentRegime);
            
            // INTELLIGENT POSITION SIZING: Risk-based with volatility adjustment
            double lotSize = CalculateIntelligentLotSize(symbol, stopLossPips, aiSignal.confidence);
            
            // 🚨 BEAST MODE FINAL EMERGENCY OVERRIDE - LAST LINE OF DEFENSE 🚨
            if(lotSize > 0.1) {
                Print("🚨🚨🚨 BEAST MODE FINAL OVERRIDE: Lot size ", DoubleToString(lotSize, 3), " reduced to 0.01 for ", symbol);
                lotSize = 0.01;
            }
            
            double localAccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            if(localAccountBalance < 100.0 && lotSize > 0.01) {
                Print("🚨 BEAST MODE: Small account - forcing micro lot for ", symbol);
                lotSize = 0.01;
            }
            
            // FINAL RISK VALIDATION
            if(lotSize > 0 && ValidateTradeRisk(symbol, lotSize, stopLossPips)) {
                
                // Calculate SL and TP prices
                double executionPrice = (orderType == ORDER_TYPE_BUY) ?
                SymbolInfoDouble(symbol, SYMBOL_ASK) :
                SymbolInfoDouble(symbol, SYMBOL_BID);
                
                double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
                double stopLossPrice = 0, takeProfitPrice = 0;
                
                if(orderType == ORDER_TYPE_BUY) {
                    stopLossPrice = executionPrice - (stopLossPips * pointValue * 10);
                    takeProfitPrice = executionPrice + (DefaultTakeProfitPips * pointValue * 10);
                } else {
                    stopLossPrice = executionPrice + (stopLossPips * pointValue * 10);
                    takeProfitPrice = executionPrice - (DefaultTakeProfitPips * pointValue * 10);
                }
                
                // Execute the trade
                bool success = false;
                if(IsTradeManagerReady()) {
                    // Use direct trade manager call - fix function signature
                    success = ExecuteDirectTrade(symbol, orderType, lotSize, stopLossPrice, takeProfitPrice);
                } else {
                    // Fallback to direct trade execution
                    m_trade.SetExpertMagicNumber(12345);
                    if(orderType == ORDER_TYPE_BUY) {
                        success = m_trade.Buy(lotSize, symbol, 0, stopLossPrice, takeProfitPrice, "Intelligent EA Trade");
                    } else {
                        success = m_trade.Sell(lotSize, symbol, 0, stopLossPrice, takeProfitPrice, "Intelligent EA Trade");
                    }
                }
                
                if(success) {
                    g_lastTradeTime = TimeCurrent();
                    g_totalActivePositions++;
                    ArrayResize(g_activePairs, ArraySize(g_activePairs) + 1);
                    g_activePairs[ArraySize(g_activePairs) - 1] = symbol;
                    
                    Print("[SUCCESS] Intelligent trade executed: ", symbol, " ", EnumToString(orderType), 
                          " ", DoubleToString(lotSize, 2), " lots");
                    Print("  SL: ", DoubleToString(stopLossPrice, 5), " TP: ", DoubleToString(takeProfitPrice, 5));
                    Print("  AI Confidence: ", DoubleToString(aiSignal.confidence, 3));
                    Print("  Market Regime: ", EnumToString(g_currentRegime));
                    
                    // Log trade for performance analysis
                    LogTradeExecution(symbol, orderType, lotSize, aiSignal.confidence, g_currentRegime);
                    
                } else {
                    Print("[ERROR] Failed to execute intelligent trade: ", symbol);
                    Print("  Last Error: ", GetLastError());
                }
            } else {
                Print("[RISK-BLOCKED] Trade blocked by risk validation: ", symbol);
            }
        } else {
            // Log why no signal was generated
            Print("[NO-SIGNAL] No valid signal for ", symbol, 
                  " (Strategy: ", EnumToString(signal), 
                  ", AI Confidence: ", DoubleToString(aiSignal.confidence, 3), ")");
        }
    }
    
    Print("[INTELLIGENT-TRADING] Completed processing. Active positions: ", g_totalActivePositions);
}

//+------------------------------------------------------------------+
//| Validate market data availability                                |
//+------------------------------------------------------------------+
bool ValidateMarketData(string symbol)
{
    // Check if we have recent price data
    double localBidPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
    if(localBidPrice <= 0) {
        return false;
    }
    
    // Check if we have enough historical data for indicators
    int bars = iBars(symbol, PERIOD_H1);
    if(bars < 100) {
        return false;
    }
    
    // Check spread
    double spreadPoints = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    double maxSpread = 50; // Maximum 50 points spread
    if(spreadPoints > maxSpread) {
        Print("[DATA] Spread too high for ", symbol, ": ", spreadPoints, " points");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Log trade execution for performance analysis                     |
//+------------------------------------------------------------------+
void LogTradeExecution(string symbol, ENUM_ORDER_TYPE orderType, double lotSize, double aiConfidence, ENUM_MARKET_REGIME regime)
{
    string logEntry = StringFormat("[TRADE-LOG] %s %s %s %.2f lots | AI: %.3f | Regime: %s | Time: %s",
        TimeToString(TimeCurrent()),
        symbol,
        EnumToString(orderType),
        lotSize,
        aiConfidence,
        EnumToString(regime),
        TimeToString(TimeCurrent())
    );
    
    Print(logEntry);
    
    // Could also write to file for later analysis
    // FileWrite(tradeLogHandle, logEntry);
}
