//+------------------------------------------------------------------+
//| NeuralNetworkStrategy.mqh                                        |
//| Complete 3-Layer Feedforward Neural Network for Trading         |
//| Implementation based on neural_networks.md specification        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#ifndef __NEURAL_NETWORK_STRATEGY_MQH__
#define __NEURAL_NETWORK_STRATEGY_MQH__

// Network architecture: 25→15→10→3 (Input→Hidden1→Hidden2→Output)

#include "../Core/Utils/Enums.mqh"
#include <Arrays/ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Training Example Structure                                       |
//+------------------------------------------------------------------+
class CTrainingExample : public CObject
{
public:
    double inputs[25];
    int expectedOutput;     // 0=None, 1=Buy, 2=Sell
    double actualResult;    // Profit/loss from this trade
    datetime time;
    
    CTrainingExample()
    {
        ArrayInitialize(inputs, 0.0);
        expectedOutput = 0;
        actualResult = 0.0;
        time = 0;
    }
};

//+------------------------------------------------------------------+
//| Neural Network Strategy Class                                    |
//+------------------------------------------------------------------+

class CNeuralNetworkStrategy
{
private:
    // Network weights
    double W1[25][15];       // Input → Hidden1
    double W2[15][10];       // Hidden1 → Hidden2
    double W3[10][3];        // Hidden2 → Output
    
    // Biases
    double B1[15];
    double B2[10];
    double B3[3];
    
    // Training configuration
    double m_learningRate;
    int m_epoch;
    double m_lastLoss;
    
    // Training data
    CArrayObj m_trainingData;
    int m_minTrainingExamples;
    
    // Symbol and timeframe
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_initialized;
    bool m_enableOnlineTraining;
    
public:
    CNeuralNetworkStrategy() : 
        m_learningRate(0.001),
        m_epoch(0),
        m_lastLoss(0.0),
        m_minTrainingExamples(20),  // Reduced from 100 for faster startup
        m_symbol(""),
        m_timeframe(PERIOD_CURRENT),
        m_initialized(false),
        m_enableOnlineTraining(true)
    {
        InitializeNetwork();
    }
    
    ~CNeuralNetworkStrategy()
    {
        m_trainingData.Clear();
    }
    
    bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_enableOnlineTraining = true;
        m_initialized = true;

        // Online training + persistence enabled in live runtime.
        if(m_enableOnlineTraining)
        {
            if(!LoadNetwork())
            {
                InitializeNetwork();
                SaveNetwork();
            }
        }
        else
        {
            InitializeNetwork();
        }
        
        PrintFormat("[NEURAL-NET] Initialized for %s on %s", symbol, EnumToString(timeframe));
        return true;
    }
    
    void InitializeNetwork()
    {
        // Xavier initialization for better convergence
        double xavier_input = MathSqrt(2.0 / 25);
        double xavier_hidden1 = MathSqrt(2.0 / 15);
        double xavier_hidden2 = MathSqrt(2.0 / 10);
        
        // Local deterministic seeding for reproducibility
        m_randomState = 12345; // Fixed seed

        // Initialize W1
        for(int i = 0; i < 25; i++)
        {
            for(int j = 0; j < 15; j++)
            {
                W1[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_input;
            }
        }
        
        // Initialize W2
        for(int i = 0; i < 15; i++)
        {
            for(int j = 0; j < 10; j++)
            {
                W2[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_hidden1;
            }
        }
        
        // Initialize W3
        for(int i = 0; i < 10; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                W3[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_hidden2;
            }
        }
        
        // Initialize biases to small values
        for(int i = 0; i < 15; i++)
            B1[i] = 0.01;
        
        for(int i = 0; i < 10; i++)
            B2[i] = 0.01;
        
        for(int i = 0; i < 3; i++)
            B3[i] = 0.01;
        
        Print("[NEURAL-NET] Network weights initialized with Deterministic Xavier method");
    }

    // Simple LCG for deterministic behavior
    uint m_randomState;
    double GetDeterministicRandom()
    {
        m_randomState = m_randomState * 1664525 + 1013904223;
        return (double)m_randomState / 4294967296.0;
    }
    
    // Helper to get indicator value from buffer
    double GetIndicatorValue(int handle, int buffer, int shift)
    {
        double val[1];
        if(CopyBuffer(handle, buffer, shift, 1, val) > 0) return val[0];
        return 0.0;
    }

    // Helper for MA value
    double GetMAValue(int period, int shift, ENUM_MA_METHOD method, ENUM_APPLIED_PRICE price, int bar)
    {
        int handle = iMA(m_symbol, m_timeframe, period, shift, method, price);
        return GetIndicatorValue(handle, 0, bar);
    }

    // Helper for RSI value
    double GetRSIValue(int period, ENUM_APPLIED_PRICE price, int bar)
    {
        int handle = iRSI(m_symbol, m_timeframe, period, price);
        return GetIndicatorValue(handle, 0, bar);
    }

    // Helper for ATR value
    double GetATRValue(int period, int bar)
    {
        int handle = iATR(m_symbol, m_timeframe, period);
        return GetIndicatorValue(handle, 0, bar);
    }

    // Helper for ADX value
    double GetADXValue(int period, int bar)
    {
        int handle = iADX(m_symbol, m_timeframe, period);
        return GetIndicatorValue(handle, 0, bar);
    }

    // Helper for Bollinger Bands value
    double GetBBValue(int period, double dev, int shift, ENUM_APPLIED_PRICE price, int buffer, int bar)
    {
        int handle = iBands(m_symbol, m_timeframe, period, dev, shift, price);
        return GetIndicatorValue(handle, buffer, bar);
    }

    // Helper for MACD value
    double GetMACDValue(int fast, int slow, int signal, ENUM_APPLIED_PRICE price, int buffer, int bar)
    {
        int handle = iMACD(m_symbol, m_timeframe, fast, slow, signal, price);
        return GetIndicatorValue(handle, buffer, bar);
    }

    // Helper for CCI value
    double GetCCIValue(int period, ENUM_APPLIED_PRICE price, int bar)
    {
        int handle = iCCI(m_symbol, m_timeframe, period, price);
        return GetIndicatorValue(handle, 0, bar);
    }

    // Extract 25 features from current market state
    bool ExtractFeatures(double &features[])
    {
        if(!m_initialized || ArraySize(features) < 25)
        {
            ArrayResize(features, 25);
        }
        
        // Initialize all features to 0
        ArrayInitialize(features, 0.0);
        
        // --- Market Structure (Features 0-4) ---
        // Feature 0: Trend Direction based on MA Cross (Fast vs Slow)
        double maFast = GetMAValue(9, 0, MODE_EMA, PRICE_CLOSE, 1);
        double maSlow = GetMAValue(21, 0, MODE_EMA, PRICE_CLOSE, 1);
        features[0] = (maFast > maSlow) ? 1.0 : (maFast < maSlow) ? -1.0 : 0.0;
        
        // Feature 1: Trend Strength (ADX)
        double adx = GetADXValue(14, 1);
        features[1] = GetNormalizedValue(0, 100, adx);

        // Feature 2: Momentum (RSI)
        double rsi = GetRSIValue(14, PRICE_CLOSE, 1);
        features[2] = GetNormalizedValue(0, 100, rsi);
        
        // Feature 3: Price vs EMA200 (Long term trend)
        double ema200 = GetMAValue(200, 0, MODE_EMA, PRICE_CLOSE, 1);
        double close = iClose(m_symbol, m_timeframe, 1);
        features[3] = (close > ema200) ? 1.0 : -1.0;
        
        // Feature 4: Volatility (ATR Normalized)
        double atr = GetATRValue(14, 1);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        features[4] = GetNormalizedValue(0, 100 * point, atr); // Rough normalization
        
        // --- Oscillator / Reversion (Features 5-9) ---
        // Feature 5: Stochastic Lookalike (RSI based: Overbought/Oversold)
        features[5] = (rsi > 70) ? 1.0 : (rsi < 30) ? -1.0 : 0.0;
        
        // Feature 6: Bollinger Band Position
        double bbUpper = GetBBValue(20, 2, 0, PRICE_CLOSE, 1, 1); // Buffer 1 = Upper
        double bbLower = GetBBValue(20, 2, 0, PRICE_CLOSE, 2, 1); // Buffer 2 = Lower
        double bbBasis = (bbUpper - bbLower > 0) ? (close - bbLower) / (bbUpper - bbLower) : 0.5;
        features[6] = MathMin(1.0, MathMax(0.0, bbBasis)); // 0 = Lower Band, 1 = Upper Band
        
        // Feature 7: MACD Histogram
        double macdMain = GetMACDValue(12, 26, 9, PRICE_CLOSE, 0, 1); // Buffer 0 = Main
        double macdSignal = GetMACDValue(12, 26, 9, PRICE_CLOSE, 1, 1); // Buffer 1 = Signal
        double macdHist = macdMain - macdSignal;
        features[7] = (macdHist > 0) ? 1.0 : -1.0;
        
        // Feature 8: Williams %R or similar (using RSI delta)
        double rsiPrev = GetRSIValue(14, PRICE_CLOSE, 2);
        features[8] = (rsi - rsiPrev) / 100.0; // Momentum change
        
        // Feature 9: CCI
        double cci = GetCCIValue(14, PRICE_CLOSE, 1);
        features[9] = GetNormalizedValue(-200, 200, cci); // Limit to range usually -1 to 1
        
        // --- Volume / Liquidity Proxy (Features 10-14) ---
        // Feature 10: Volume Trend
        long vol = iVolume(m_symbol, m_timeframe, 1);
        long volPrev = iVolume(m_symbol, m_timeframe, 2);
        features[10] = (vol > volPrev) ? 1.0 : 0.0;
        
        // Feature 11: MFI (Money Flow Index) - approximated via RSI/Vol mix
        features[11] = (rsi > 50 && vol > volPrev) ? 1.0 : 0.0;

        // Feature 12: High/Low Breakout (Donchian-ish)
        double high20 = iHigh(m_symbol, m_timeframe, iHighest(m_symbol, m_timeframe, MODE_HIGH, 20, 1));
        double low20 = iLow(m_symbol, m_timeframe, iLowest(m_symbol, m_timeframe, MODE_LOW, 20, 1));
        features[12] = (close >= high20) ? 1.0 : (close <= low20) ? -1.0 : 0.0;
        
        // Feature 13: Candle Range Quality
        double open = iOpen(m_symbol, m_timeframe, 1);
        double high = iHigh(m_symbol, m_timeframe, 1);
        double low = iLow(m_symbol, m_timeframe, 1);
        
        // Feature 14: Gap (Open vs Prev Close)
        double closePrev = iClose(m_symbol, m_timeframe, 2);
        features[14] = (open > closePrev) ? 1.0 : (open < closePrev) ? -1.0 : 0.0;
        
        // --- Price Action (Features 15-19) ---
        double body = MathAbs(close - open);
        double range = high - low;
        double bodyRatio = (range > 0) ? body / range : 0;
        
        features[15] = bodyRatio; // 1 = Marubozu, 0 = Doji
        features[16] = (close > open) ? 1.0 : -1.0; // Bullish/Bearish
        
        // Feature 17: Upper Wick Ratio
        double upperWick = (close > open) ? (high - close) : (high - open);
        features[17] = (range > 0) ? upperWick / range : 0;
        
        // Feature 18: Lower Wick Ratio
        double lowerWick = (close > open) ? (open - low) : (close - low);
        features[18] = (range > 0) ? lowerWick / range : 0;
        
        // Feature 19: Inside Bar check
        double highPrev = iHigh(m_symbol, m_timeframe, 2);
        double lowPrev = iLow(m_symbol, m_timeframe, 2);
        bool insideBar = (high < highPrev) && (low > lowPrev);
        features[19] = insideBar ? 1.0 : 0.0;
        
        // --- Time & Context (Features 20-22) ---
        // Features 20-22: Time/Session
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        features[20] = dt.hour / 24.0;                          // Hour normalized
        features[21] = dt.day_of_week / 7.0;                    // Day normalized
        features[22] = IsKillZoneTime(dt.hour) ? 1.0 : 0.0;   // Kill zone binary
        
        // --- Context Tail Features (23-24) ---
        // Feature 23: Volatility regime ratio (fast ATR / slow ATR proxy)
        double atrFast = GetATRValue(14, 1);
        double atrSlow = GetATRValue(50, 1);
        features[23] = (atrSlow > 0.0) ? MathMin(2.0, atrFast / atrSlow) : 1.0;

        // Feature 24: Bias Unit
        features[24] = 1.0;
        
        return true;
    }
    
    // Forward propagation
    void ForwardPropagate(const double &inputs[], double &outputs[])
    {
        double hidden1[15];
        double hidden2[10];
        
        ArrayResize(outputs, 3);
        
        // Input → Hidden1
        for(int j = 0; j < 15; j++)
        {
            hidden1[j] = B1[j];
            for(int i = 0; i < 25; i++)
            {
                hidden1[j] += inputs[i] * W1[i][j];
            }
            hidden1[j] = ReLU(hidden1[j]);  // Activation
        }
        
        // Hidden1 → Hidden2
        for(int j = 0; j < 10; j++)
        {
            hidden2[j] = B2[j];
            for(int i = 0; i < 15; i++)
            {
                hidden2[j] += hidden1[i] * W2[i][j];
            }
            hidden2[j] = ReLU(hidden2[j]);
        }
        
        // Hidden2 → Output
        for(int j = 0; j < 3; j++)
        {
            outputs[j] = B3[j];
            for(int i = 0; i < 10; i++)
            {
                outputs[j] += hidden2[i] * W3[i][j];
            }
        }
        
        // Softmax activation for output layer
        Softmax(outputs, 3);
    }
    
    // Get trading signal from neural network
    ENUM_TRADE_SIGNAL GetNeuralSignal(double &confidence)
    {
        if(m_enableOnlineTraining && m_trainingData.Total() < m_minTrainingExamples)
        {
            // Not enough data - return signal anyway with low confidence
            // This enables "exploration" phase while gathering training data
            confidence = 0.30;  // Low confidence during exploration
            PrintFormat("[NEURAL-NET] Exploration mode: %d/%d training examples", 
                       m_trainingData.Total(), m_minTrainingExamples);
            // Continue to generate a signal instead of returning NONE
        }
        
        // Extract current features
        double inputs[25];
        if(!ExtractFeatures(inputs))
        {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        
        // Forward propagate
        double outputs[3];
        ForwardPropagate(inputs, outputs);
        
        // outputs[0] = probability of NONE
        // outputs[1] = probability of BUY
        // outputs[2] = probability of SELL
        
        // Find highest probability
        int maxIndex = 0;
        double maxProb = outputs[0];
        
        for(int i = 1; i < 3; i++)
        {
            if(outputs[i] > maxProb)
            {
                maxProb = outputs[i];
                maxIndex = i;
            }
        }
        
        // Require minimum 60% confidence
        if(maxProb < 0.60)
        {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        
        confidence = maxProb;
        
        // Store for training when online training is enabled
        if(m_enableOnlineTraining)
        {
            CTrainingExample* example = new CTrainingExample();
            ArrayCopy(example.inputs, inputs);
            example.expectedOutput = maxIndex;
            example.time = TimeCurrent();
            m_trainingData.Add(example);
        }
        
        PrintFormat("[NEURAL-NET] Signal: %d | Confidence: %.2f%%", maxIndex, maxProb * 100);
        
        if(maxIndex == 1)
            return TRADE_SIGNAL_BUY;
        else if(maxIndex == 2)
            return TRADE_SIGNAL_SELL;
        
        return TRADE_SIGNAL_NONE;
    }
    
    // Update trade result for training
    void UpdateTradeResult(datetime tradeTime, double profitLoss)
    {
        if(!m_enableOnlineTraining)
            return;

        // Find the training example and update result
        for(int i = m_trainingData.Total() - 1; i >= 0; i--)
        {
            CTrainingExample* example = (CTrainingExample*)m_trainingData.At(i);
            if(example == NULL) continue;
            
            if(MathAbs(example.time - tradeTime) < 60)  // Within 1 minute
            {
                example.actualResult = profitLoss;
                
                PrintFormat("[NEURAL-NET] Updated trade result: %.2f", profitLoss);
                
                // Trigger training every 20 completed trades
                if(GetCompletedTradesCount() % 20 == 0)
                {
                    TrainNetwork();
                }
                
                break;
            }
        }
    }
    
    // Train network with backpropagation
    void TrainNetwork()
    {
        if(!m_enableOnlineTraining)
            return;

        if(m_trainingData.Total() < m_minTrainingExamples)
            return;
        
        Print("[NEURAL-NET] Training network with ", m_trainingData.Total(), " examples");
        
        // Mini-batch training
        int batchSize = 32;
        int batches = m_trainingData.Total() / batchSize;
        
        for(int epoch = 0; epoch < 10; epoch++)  // 10 epochs
        {
            double epochLoss = 0.0;
            
            for(int b = 0; b < batches; b++)
            {
                // Process one batch
                for(int i = 0; i < batchSize; i++)
                {
                    int idx = b * batchSize + i;
                    if(idx >= m_trainingData.Total())
                        break;
                    
                    CTrainingExample* example = (CTrainingExample*)m_trainingData.At(idx);
                    if(example == NULL) continue;
                    
                    // Only train on completed trades
                    if(example.actualResult == 0.0)
                        continue;
                    
                    // Forward pass
                    double outputs[3];
                    ForwardPropagate(example.inputs, outputs);
                    
                    // Calculate loss (cross-entropy)
                    double target[3];
                    ArrayInitialize(target, 0.0);
                    
                    // Adjust target based on actual result
                    if(example.actualResult > 0)
                    {
                        // Profitable trade - reinforce this action
                        target[example.expectedOutput] = 1.0;
                    }
                    else
                    {
                        // Losing trade - penalize this action
                        target[example.expectedOutput] = 0.0;
                        // Encourage NONE instead
                        target[0] = 1.0;
                    }
                    
                    double loss = CalculateLoss(outputs, target);
                    epochLoss += loss;
                    
                    // Backward pass (simplified weight update)
                    UpdateWeights(example.inputs, outputs, target);
                }
            }
            
            m_lastLoss = epochLoss / (batches * batchSize);
            m_epoch++;
            
            PrintFormat("[NEURAL-NET] Epoch %d | Loss: %.6f", epoch, m_lastLoss);
        }
        
        // Save after training
        SaveNetwork();
    }
    
    int GetTrainingExampleCount() { return m_trainingData.Total(); }
    int GetCompletedTradesCount()
    {
        int count = 0;
        for(int i = 0; i < m_trainingData.Total(); i++)
        {
            CTrainingExample* ex = (CTrainingExample*)m_trainingData.At(i);
            if(ex != NULL && ex.actualResult != 0.0)
                count++;
        }
        return count;
    }
    
    // Save network weights and biases to file
    bool SaveNetwork()
    {
        if(!m_enableOnlineTraining)
            return false;

        string filename = "AI_Net_" + m_symbol + "_" + EnumToString(m_timeframe) + ".bin";
        int fileHandle = FileOpen(filename, FILE_WRITE|FILE_BIN);
        if(fileHandle == INVALID_HANDLE) return false;
        
        // Write weights (manually since FileWriteArray doesn't like 2D slices)
        for(int i=0; i<25; i++) {
            for(int j=0; j<15; j++) FileWriteDouble(fileHandle, W1[i][j]);
        }
        for(int i=0; i<15; i++) {
            for(int j=0; j<10; j++) FileWriteDouble(fileHandle, W2[i][j]);
        }
        for(int i=0; i<10; i++) {
            for(int j=0; j<3; j++) FileWriteDouble(fileHandle, W3[i][j]);
        }
        
        // Write biases
        for(int i=0; i<15; i++) FileWriteDouble(fileHandle, B1[i]);
        for(int i=0; i<10; i++) FileWriteDouble(fileHandle, B2[i]);
        for(int i=0; i<3; i++) FileWriteDouble(fileHandle, B3[i]);
        
        FileClose(fileHandle);
        Print("[NEURAL-NET] Network state saved to ", filename);
        return true;
    }
    
    // Load network weights and biases from file
    bool LoadNetwork()
    {
        if(!m_enableOnlineTraining)
            return false;

        string filename = "AI_Net_" + m_symbol + "_" + EnumToString(m_timeframe) + ".bin";
        if(!FileIsExist(filename)) return false;
        
        int fileHandle = FileOpen(filename, FILE_READ|FILE_BIN);
        if(fileHandle == INVALID_HANDLE) return false;
        
        // Read weights
        for(int i=0; i<25; i++) {
            for(int j=0; j<15; j++) W1[i][j] = FileReadDouble(fileHandle);
        }
        for(int i=0; i<15; i++) {
            for(int j=0; j<10; j++) W2[i][j] = FileReadDouble(fileHandle);
        }
        for(int i=0; i<10; i++) {
            for(int j=0; j<3; j++) W3[i][j] = FileReadDouble(fileHandle);
        }
        
        // Read biases
        for(int i=0; i<15; i++) B1[i] = FileReadDouble(fileHandle);
        for(int i=0; i<10; i++) B2[i] = FileReadDouble(fileHandle);
        for(int i=0; i<3; i++) B3[i] = FileReadDouble(fileHandle);
        
        FileClose(fileHandle);
        Print("[NEURAL-NET] Network state loaded from ", filename);
        return true;
    }
    
private:
    double ReLU(double x)
    {
        return MathMax(0.0, x);
    }
    
    void Softmax(double &arr[], int size)
    {
        double maxVal = arr[0];
        for(int i = 1; i < size; i++)
            maxVal = MathMax(maxVal, arr[i]);
        
        double sum = 0.0;
        for(int i = 0; i < size; i++)
        {
            arr[i] = MathExp(arr[i] - maxVal);
            sum += arr[i];
        }
        
        if(sum > 0)
        {
            for(int i = 0; i < size; i++)
                arr[i] /= sum;
        }
    }
    
    double CalculateLoss(const double &outputs[], const double &target[])
    {
        // Cross-entropy loss
        double loss = 0.0;
        for(int i = 0; i < 3; i++)
        {
            if(target[i] > 0)
                loss -= target[i] * MathLog(outputs[i] + 1e-10);
        }
        return loss;
    }
    
    void UpdateWeights(const double &inputs[], const double &outputs[], const double &target[])
    {
        // Simplified weight update (gradient descent on output layer)
        // Full implementation would require proper backpropagation through all layers
        
        double outputError[3];  // OUTPUT_SIZE
        for(int i = 0; i < 3; i++)  // OUTPUT_SIZE
        {
            outputError[i] = outputs[i] - target[i];
        }
        
        // Update output layer weights (W3) and biases (B3)
        // This is a simplified version - proper backprop would compute gradients through all layers
        for(int i = 0; i < 10; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                double gradient = outputError[j];
                W3[i][j] -= m_learningRate * gradient * 0.1; // Scaled down
            }
        }
        
        // Update biases
        for(int i = 0; i < 3; i++)
        {
            B3[i] -= m_learningRate * outputError[i];
        }
    }
    
    double GetNormalizedValue(double min, double max, double value)
    {
        if(max - min == 0) return 0;
        return (value - min) / (max - min);
    }
    
    bool IsKillZoneTime(int hour)
    {
        // London Kill Zone: 02:00-05:00 (server time)
        // New York Kill Zone: 07:00-10:00 (server time)
        // Asian Kill Zone: 20:00-23:00 (server time)
        return (hour >= 2 && hour <= 5) || (hour >= 7 && hour <= 10) || (hour >= 20 && hour <= 23);
    }
};

#endif // __NEURAL_NETWORK_STRATEGY_MQH__
