//+------------------------------------------------------------------+
//| Script: BrainTrainer.mq5                                         |
//| Description: Backtest script to train the StrategyBrain network   |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include "Core/StrategyFunctions.mqh"
#include "Strategies/StrategyBrain.mqh"
#include "Strategies/StrategyRSI.mqh"
#include "Strategies/StrategySupplyDemand.mqh"
#include "Strategies/StrategyOrderBlockFVG.mqh"
#include "Strategies/StrategyFibonacci.mqh"
#include "Strategies/StrategyElliott.mqh"
#include "Strategies/StrategySwing.mqh"
#include "Strategies/StrategyVolatility.mqh"
#include "Strategies/StrategyTrend.mqh"
#include "Strategies/StrategyMeanReversion.mqh"
#include "Strategies/StrategyBreakout.mqh"

// Strategy instances
CStrategyRSI rsiStrategy("RSI", 1001);
CStrategySupplyDemand supplyDemandStrategy("SupplyDemand", 1002);
CStrategyOrderBlockFVG orderBlockFVGStrategy("OrderBlockFVG", 1003);
CStrategyFibonacci fibonacciStrategy("Fibonacci", 1004);
CStrategyElliott elliottStrategy("Elliott", 1005);
CStrategySwing swingStrategy("Swing", 1006);
CStrategyVolatility volatilityStrategy("Volatility", 1007);
CStrategyTrend trendStrategy("Trend", 1008);
CStrategyMeanReversion meanReversionStrategy("MeanReversion", 1009);
CStrategyBreakout breakoutStrategy("Breakout", 1010);

//--- Script Parameters (converted from input variables)
string   InpSymbol = "";              // Symbol for training (empty = current chart)
ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1; // Timeframe
int      InpBarsToTrain = 1000;        // Number of historical bars to use
int      InpFutureOffset = 5;          // Bars ahead for target label
double   InpThresholdPoints = 10.0;    // Price move threshold (points)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------
void OnStart()
{
    // Set random seed for reproducibility
    MathSrand(42);
    
    string sym = (InpSymbol==""?Symbol():InpSymbol);
    int totalBars = Bars(sym, InpTimeframe);
    int count = MathMin(InpBarsToTrain + InpFutureOffset, totalBars);
    
    Print("Starting training on ", sym, " with ", count, " bars");
    
    MqlRates rates[];
    if(CopyRates(sym, InpTimeframe, 0, count, rates) < count) {
        Print("Error: Not enough data for training. Requested ", count, " bars but got ", ArraySize(rates));
        return;
    }
    
    Print("Successfully loaded ", ArraySize(rates), " bars of historical data");

    // Initialize network
    if(!BrainInit()) {
        Print("Error: Failed to initialize brain network");
        return;
    }
    
    int trainedSamples = 0;
    int positiveSamples = 0;
    int negativeSamples = 0;
    
    Print("Starting training loop...");
    
    // Loop through bars for training
    for(int i = InpFutureOffset; i < count; i++) {
        // Get strategy signals (normalized between -1 and 1)
        double inputs[10];
        
        // Initialize strategies if needed
        CTradeManager tradeManager;
        CPositionSizer positionSizer;
        
        // Initialize trade manager and position sizer
        if(!tradeManager.Initialize(12345, "BrainTrainer") || !positionSizer.Initialize("BrainTrainer", ERROR_LEVEL_INFO)) {
            Print("Error: Failed to initialize trade manager or position sizer");
            return;
        }
        
        if(!rsiStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !supplyDemandStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !orderBlockFVGStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !fibonacciStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !elliottStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !swingStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !volatilityStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !trendStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !meanReversionStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer) ||
           !breakoutStrategy.Init(sym, InpTimeframe, &tradeManager, &positionSizer)) {
            Print("Error: Failed to initialize one or more strategies");
            return;
        }
        
        // Get strategy signals (normalized between -1 and 1)
        double close[];
        ArraySetAsSeries(close, true);
        CopyClose(sym, InpTimeframe, 0, 1, close);
        
        // Get signals from each strategy
        double confidence = 0.0;
        inputs[0] = (rsiStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((rsiStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        
        inputs[1] = (supplyDemandStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((supplyDemandStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        
        inputs[2] = (orderBlockFVGStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((orderBlockFVGStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        
        inputs[3] = (fibonacciStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((fibonacciStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        
        inputs[4] = (elliottStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((elliottStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        
        inputs[5] = (swingStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((swingStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        
        inputs[6] = (volatilityStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((volatilityStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        inputs[7] = (trendStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((trendStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        
        inputs[8] = (meanReversionStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((meanReversionStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
        
        inputs[9] = (breakoutStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                   ((breakoutStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);

        // Determine target from future price movement
        double currentClose = rates[i].close;
        double futureClose = rates[i - InpFutureOffset].close;  // Future price
        
        // Calculate price change in points
        double point = SymbolInfoDouble(sym, SYMBOL_POINT);
        double diff = (futureClose - currentClose) / point;
        
        // Set target based on threshold
        double target = 0;
        if(diff > InpThresholdPoints) {
            target = 1.0;    // Strong buy signal
            positiveSamples++;
        } else if(diff < -InpThresholdPoints) {
            target = -1.0;   // Strong sell signal
            negativeSamples++;
        } else {
            // Skip samples with small price movements
            continue;
        }
        
        // Train on this sample
        if(BrainTrainSample(inputs, target)) {
            trainedSamples++;
            
            // Print progress
            if(trainedSamples % 100 == 0) {
                Print("Trained on ", trainedSamples, " samples...");
            }
        } else {
            Print("Error training on sample at bar ", i);
        }
    }
    
    // Save the trained network
    string filename = "brain_" + sym + "_" + IntegerToString(TimeCurrent()) + ".nn";
    if(BrainSaveNetwork(filename)) {
        Print("\nTraining complete!");
        Print("Total samples: ", trainedSamples, " (+", positiveSamples, "/-", negativeSamples, ")");
        Print("Network saved to: ", filename);
        
        // Test the network on the last few samples
        Print("\nTesting on recent data:");
        int testSamples = MathMin(10, trainedSamples / 10);
        int correct = 0;
        
        for(int i = count - testSamples; i < count; i++) {
            if(i < InpFutureOffset) continue;
            
            // Prepare inputs (same as training)
            double inputs[10];
            double confidence;
            
            inputs[0] = (rsiStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((rsiStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[1] = (supplyDemandStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((supplyDemandStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[2] = (orderBlockFVGStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((orderBlockFVGStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[3] = (fibonacciStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((fibonacciStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[4] = (elliottStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((elliottStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[5] = (swingStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((swingStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[6] = (volatilityStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((volatilityStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[7] = (trendStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((trendStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[8] = (meanReversionStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((meanReversionStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            inputs[9] = (breakoutStrategy.GetSignal(confidence) == TRADE_SIGNAL_BUY) ? 1.0 : 
                       ((breakoutStrategy.GetSignal(confidence) == TRADE_SIGNAL_SELL) ? -1.0 : 0.0);
            
            // Get prediction
            double prediction;
            int signal = StrategyBrain(prediction, inputs);
            
            // Determine actual movement
            double currentClose = rates[i].close;
            double futureClose = rates[i - InpFutureOffset].close;
            double point = SymbolInfoDouble(sym, SYMBOL_POINT);
            double diff = (futureClose - currentClose) / point;
            
            // Determine if prediction was correct
            bool correctPrediction = false;
            if((signal > 0 && diff > 0) || (signal < 0 && diff < 0)) {
                correct++;
                correctPrediction = true;
            }
            
            Print("Bar ", i, ": Predicted=", signal, " (", DoubleToString(prediction, 4), "), ",
                  "Actual=", (diff > 0 ? "UP" : (diff < 0 ? "DOWN" : "SIDEWAYS")), ", ",
                  "Correct=", (correctPrediction ? "YES" : "NO"));
        }
        
        if(testSamples > 0) {
            double accuracy = (double)correct / testSamples * 100.0;
            Print("\nTest accuracy: ", DoubleToString(accuracy, 2), "% (", correct, "/", testSamples, ")");
        }
    } else {
        Print("Error: Failed to save trained network to ", filename);
    }
}
