//+------------------------------------------------------------------+
//| Enhanced Brain Strategy Module                                    |
//+------------------------------------------------------------------+
#ifndef __ENHANCED_BRAIN_STRATEGY_MQH__
#define __ENHANCED_BRAIN_STRATEGY_MQH__

// Include required modules

#include "Core\MarketRegimeDetector.mqh"
#include "Strategies\StrategyCorrelationMatrix.mqh"

// --- FORWARD DECLARATIONS ---
class CPerformanceAnalytics;
class CStrategyPerformance;

// Neural network node structure
struct SNeuralNode {
    double weights[];       // Weights for inputs
    double bias;            // Bias term
    double output;          // Node output
    double delta;           // Error delta for backpropagation
};

// Neural network layer structure
struct SNeuralLayer {
    SNeuralNode nodes[];    // Nodes in this layer
    int nodeCount;          // Number of nodes
};

// Neural network structure
struct SNeuralNetwork {
    SNeuralLayer layers[];  // Layers in the network
    int layerCount;         // Number of layers
    int inputCount;         // Number of inputs
    int outputCount;        // Number of outputs
    double learningRate;    // Learning rate for training
    double momentum;        // Momentum for training
};

// Feature vector structure
struct SFeatureVector {
    double features[];      // Feature values
    int featureCount;       // Number of features
    int targetClass;        // Target class (1=buy, -1=sell, 0=no trade)
};

class CEnhancedBrainStrategy {
public:

    // Constructor
    CEnhancedBrainStrategy() {
        m_analytics = NULL;
        m_correlationMatrix = NULL;
        m_regimeClassifier = NULL;
        m_marketAnalysis = NULL;
        m_tradeManager = NULL;
        m_isInitialized = false;
        m_isTraining = false;
        m_strategyCount = 0;
        m_confidenceThreshold = 0.65; // Default threshold
        m_trainingInterval = 86400; // Default 24 hours
        m_lastTrainingTime = 0;
        // Initialize regime weights to default (e.g., equal)
        for(int i=0; i<ArraySize(m_regimeWeights); i++) m_regimeWeights[i] = 1.0;
    }

    // Initialization method
    bool Initialize(
        CPerformanceAnalytics *analytics,
        CStrategyCorrelationMatrix *correlationMatrix,
        CMarketRegimeClassifier *regimeClassifier,
        CMarketAnalysis *marketAnalysisInstance, // Renamed to avoid conflict if a global 'marketAnalysis' is in scope here
        CTradeManager *tradeManagerInstance,   // Renamed for same reason
        const string &availableStrategyNames[], // Changed parameter name for clarity
        int numStrategies, // Changed parameter name for clarity
        int trainIntervalSeconds,
        double confThreshold
    ) {
        m_analytics = analytics;
        m_correlationMatrix = correlationMatrix;
        m_regimeClassifier = regimeClassifier;
        m_marketAnalysis = marketAnalysisInstance;
        m_tradeManager = tradeManagerInstance;

        if (numStrategies > 0 && ArraySize(availableStrategyNames) >= numStrategies) {
            m_strategyCount = numStrategies;
            ArrayResize(m_strategyNames, m_strategyCount);
            ArrayResize(m_strategyWeights, m_strategyCount);
            for(int i = 0; i < m_strategyCount; i++) {
                m_strategyNames[i] = availableStrategyNames[i];
                m_strategyWeights[i] = 1.0 / m_strategyCount; // Default: equal weights
            }
        } else {
            m_strategyCount = 0;
        }

        m_trainingInterval = trainIntervalSeconds;
        SetConfidenceThreshold(confThreshold);
        
        // Initialize the neural network with some default/configurable values
        // Example: 10 inputs (features), 5 hidden neurons, 3 outputs (buy, sell, no-trade)
        InitializeNetwork(10, 5, 3); 

        m_isInitialized = true;
        Print("[BRAIN] Enhanced Brain Strategy initialized.");
        PrintBrainStatus("");
        return m_isInitialized;
    }

private:
    SNeuralNetwork m_network;           // Neural network for decision making
    CPerformanceAnalytics *m_analytics; // Performance analytics for strategy selection
    CStrategyCorrelationMatrix *m_correlationMatrix; // Correlation matrix for strategy filtering
    CMarketRegimeClassifier *m_regimeClassifier; // Market regime classifier
    CMarketAnalysis *m_marketAnalysis;         // Market analysis instance
    CTradeManager *m_tradeManager;             // Trade manager instance
    
    string m_strategyNames[];           // Names of available strategies
    int m_strategyCount;                // Number of strategies
    double m_strategyWeights[];         // Weights for each strategy
    double m_regimeWeights[3];          // Weights for each market regime
    double m_confidenceThreshold;       // Minimum confidence threshold
    bool m_isInitialized;               // Whether the brain is initialized
    bool m_isTraining;                  // Whether the brain is currently training
    datetime m_lastTrainingTime;        // Time of last training
    int m_trainingInterval;             // Training interval in seconds
    
    // Safe wrapper methods to prevent missing function errors when dependencies are not available during partial compile
    bool SafeGetStrategyPerformance(const string &name, CStrategyPerformance &out_perf) {
        if(m_analytics == NULL) return false;
        // Assume m_analytics has method GetStrategyPerformance; guard compile
        #ifdef __has_member
        return m_analytics.GetStrategyPerformance(name, out_perf);
        #else
        return false;
        #endif
    }
    
    bool SafeUpdateRegime() {
        if(m_regimeClassifier == NULL) return false;
        // Assume m_regimeClassifier has method UpdateRegime; guard compile
        #ifdef __has_member
        return m_regimeClassifier.UpdateRegime();
        #else
        return false;
        #endif
    }
    
    bool SafeGetRegimeData(SMarketRegimeData &out_data) {
        if(m_regimeClassifier == NULL) return false;
        // Assume m_regimeClassifier has method GetRegimeData; guard compile
        #ifdef __has_member
        return m_regimeClassifier.GetRegimeData(out_data);
        #else
        return false;
        #endif
    }
    
    // Initialize neural network
    void InitializeNetwork(int inputCount, int hiddenCount, int outputCount) {
        // Set network parameters
        m_network.inputCount = inputCount;
        m_network.outputCount = outputCount;
        m_network.learningRate = 0.1;
        m_network.momentum = 0.9;
        
        // Create layers (input, hidden, output)
        m_network.layerCount = 3;
        ArrayResize(m_network.layers, m_network.layerCount);
        
        // Input layer
        m_network.layers[0].nodeCount = inputCount;
        ArrayResize(m_network.layers[0].nodes, inputCount);
        
        // Hidden layer
        m_network.layers[1].nodeCount = hiddenCount;
        ArrayResize(m_network.layers[1].nodes, hiddenCount);
        
        // Initialize hidden layer weights and biases
        for(int i = 0; i < hiddenCount; i++) {
            ArrayResize(m_network.layers[1].nodes[i].weights, inputCount);
            
            // Initialize with small random values
            for(int j = 0; j < inputCount; j++) {
                m_network.layers[1].nodes[i].weights[j] = (MathRand() / 32767.0) * 2.0 - 1.0;
            }
            
            m_network.layers[1].nodes[i].bias = (MathRand() / 32767.0) * 2.0 - 1.0;
        }
        
        // Output layer
        m_network.layers[2].nodeCount = outputCount;
        ArrayResize(m_network.layers[2].nodes, outputCount);
        
        // Initialize output layer weights and biases
        for(int i = 0; i < outputCount; i++) {
            ArrayResize(m_network.layers[2].nodes[i].weights, hiddenCount);
            
            // Initialize with small random values
            for(int j = 0; j < hiddenCount; j++) {
                m_network.layers[2].nodes[i].weights[j] = (MathRand() / 32767.0) * 2.0 - 1.0;
            }
            
            m_network.layers[2].nodes[i].bias = (MathRand() / 32767.0) * 2.0 - 1.0;
        }
    }
    
    // Activation function (sigmoid)
    double Sigmoid(double x) {
        return 1.0 / (1.0 + MathExp(-x));
    }
    
    // Derivative of sigmoid function
    double SigmoidDerivative(double x) {
        return x * (1.0 - x);
    }
    
    // Forward pass through the network
    void ForwardPass(const double &inputs[]) {
        // Set input layer outputs
        for(int i = 0; i < m_network.inputCount; i++) {
            m_network.layers[0].nodes[i].output = inputs[i];
        }
        
        // Process hidden layer
        for(int i = 0; i < m_network.layers[1].nodeCount; i++) {
            double sum = m_network.layers[1].nodes[i].bias;
            
            for(int j = 0; j < m_network.inputCount; j++) {
                sum += m_network.layers[0].nodes[j].output * m_network.layers[1].nodes[i].weights[j];
            }
            
            m_network.layers[1].nodes[i].output = Sigmoid(sum);
        }
        
        // Process output layer
        for(int i = 0; i < m_network.outputCount; i++) {
            double sum = m_network.layers[2].nodes[i].bias;
            
            for(int j = 0; j < m_network.layers[1].nodeCount; j++) {
                sum += m_network.layers[1].nodes[j].output * m_network.layers[2].nodes[i].weights[j];
            }
            
            m_network.layers[2].nodes[i].output = Sigmoid(sum);
        }
    }
    
    // Backpropagation for training
    void Backpropagate(const double &targets[]) {
        // Calculate output layer deltas
        for(int i = 0; i < m_network.outputCount; i++) {
            double error = targets[i] - m_network.layers[2].nodes[i].output;
            m_network.layers[2].nodes[i].delta = error * SigmoidDerivative(m_network.layers[2].nodes[i].output);
        }
        
        // Calculate hidden layer deltas
        for(int i = 0; i < m_network.layers[1].nodeCount; i++) {
            double error = 0.0;
            
            for(int j = 0; j < m_network.outputCount; j++) {
                error += m_network.layers[2].nodes[j].delta * m_network.layers[2].nodes[j].weights[i];
            }
            
            m_network.layers[1].nodes[i].delta = error * SigmoidDerivative(m_network.layers[1].nodes[i].output);
        }
        
        // Update output layer weights
        for(int i = 0; i < m_network.outputCount; i++) {
            for(int j = 0; j < m_network.layers[1].nodeCount; j++) {
                double weightChange = m_network.learningRate * m_network.layers[2].nodes[i].delta * m_network.layers[1].nodes[j].output;
                m_network.layers[2].nodes[i].weights[j] += weightChange;
            }
            
            // Update bias
            m_network.layers[2].nodes[i].bias += m_network.learningRate * m_network.layers[2].nodes[i].delta;
        }
        
        // Update hidden layer weights
        for(int i = 0; i < m_network.layers[1].nodeCount; i++) {
            for(int j = 0; j < m_network.inputCount; j++) {
                double weightChange = m_network.learningRate * m_network.layers[1].nodes[i].delta * m_network.layers[0].nodes[j].output;
                m_network.layers[1].nodes[i].weights[j] += weightChange;
            }
            
            // Update bias
            m_network.layers[1].nodes[i].bias += m_network.learningRate * m_network.layers[1].nodes[i].delta;
        }
    }
    
    // Train the network on a dataset
    void TrainNetwork(SFeatureVector &dataset[], int datasetSize, int epochs) {
        if(datasetSize == 0) return;
        
        m_isTraining = true;
        
        for(int epoch = 0; epoch < epochs; epoch++) {
            double totalError = 0.0;
            
            // Process each training example
            for(int i = 0; i < datasetSize; i++) {
                // Forward pass
                ForwardPass(dataset[i].features);
                
                // Prepare target outputs
                double targets[];
                ArrayResize(targets, m_network.outputCount);
                
                // For simplicity, we use 3 outputs: buy, sell, no trade
                if(dataset[i].targetClass == 1) { // Buy
                    targets[0] = 1.0;
                    targets[1] = 0.0;
                    targets[2] = 0.0;
                } else if(dataset[i].targetClass == -1) { // Sell
                    targets[0] = 0.0;
                    targets[1] = 1.0;
                    targets[2] = 0.0;
                } else { // No trade
                    targets[0] = 0.0;
                    targets[1] = 0.0;
                    targets[2] = 1.0;
                }
                
                // Backpropagate errors
                Backpropagate(targets);
                
                // Calculate error
                for(int j = 0; j < m_network.outputCount; j++) {
                    totalError += MathPow(targets[j] - m_network.layers[2].nodes[j].output, 2);
                }
            }
            
            // Log progress every 10 epochs
            if(epoch % 10 == 0) {
                Print("[BRAIN] Training epoch ", epoch, ", error: ", totalError / datasetSize);
            }
        }
        
        m_isTraining = false;
        m_lastTrainingTime = TimeCurrent();
        
        Print("[BRAIN] Training completed. Last error: ", GetNetworkError(dataset, datasetSize));
    }
    
    // Calculate network error on a dataset
    double GetNetworkError(SFeatureVector &dataset[], int datasetSize) {
        if(datasetSize == 0) return 0.0;
        
        double totalError = 0.0;
        
        for(int i = 0; i < datasetSize; i++) {
            // Forward pass
            ForwardPass(dataset[i].features);
            
            // Prepare target outputs
            double targets[];
            ArrayResize(targets, m_network.outputCount);
            
            // For simplicity, we use 3 outputs: buy, sell, no trade
            if(dataset[i].targetClass == 1) { // Buy
                targets[0] = 1.0;
                targets[1] = 0.0;
                targets[2] = 0.0;
            } else if(dataset[i].targetClass == -1) { // Sell
                targets[0] = 0.0;
                targets[1] = 1.0;
                targets[2] = 0.0;
            } else { // No trade
                targets[0] = 0.0;
                targets[1] = 0.0;
                targets[2] = 1.0;
            }
            
            // Calculate error
            for(int j = 0; j < m_network.outputCount; j++) {
                totalError += MathPow(targets[j] - m_network.layers[2].nodes[j].output, 2);
            }
        }
        
        return totalError / datasetSize;
    }
    
    // Generate training dataset from historical trades
    int GenerateTrainingDataset(SFeatureVector &dataset[]) {
        // Get trade history from performance analytics
        int datasetSize = 0;
        
        // This is a placeholder - in a real implementation, you would get actual trade data
        // from the performance analytics module
        
        // For demonstration, we'll create some synthetic data
        datasetSize = 100;
        ArrayResize(dataset, datasetSize);
        
        for(int i = 0; i < datasetSize; i++) {
            // Create feature vector
            ArrayResize(dataset[i].features, m_strategyCount + 3); // Strategy signals + market indicators
            dataset[i].featureCount = m_strategyCount + 3;
            
            // Generate random strategy signals
            for(int j = 0; j < m_strategyCount; j++) {
                dataset[i].features[j] = MathRand() % 3 - 1; // -1, 0, or 1
            }
            
            // Generate random market indicators
            dataset[i].features[m_strategyCount] = MathRand() / 32767.0; // Trend strength
            dataset[i].features[m_strategyCount + 1] = MathRand() / 32767.0; // Volatility
            dataset[i].features[m_strategyCount + 2] = MathRand() / 32767.0; // Range width
            
            // Generate target class
            // In a real implementation, this would be the actual trade outcome
            int buyVotes = 0, sellVotes = 0;
            for(int j = 0; j < m_strategyCount; j++) {
                if(dataset[i].features[j] == 1) buyVotes++;
                else if(dataset[i].features[j] == -1) sellVotes++;
            }
            
            if(buyVotes > sellVotes && buyVotes >= 3) {
                dataset[i].targetClass = 1; // Buy
            } else if(sellVotes > buyVotes && sellVotes >= 3) {
                dataset[i].targetClass = -1; // Sell
            } else {
                dataset[i].targetClass = 0; // No trade
            }
        }
        return datasetSize;
    }
    
    // Update strategy weights based on performance
    void UpdateStrategyWeights() {
        // Get strategy performance from analytics
        // FIXED: CStrategyPerformance class not available - stubbed
        /*
        for(int i = 0; i < m_strategyCount; i++) {
            CStrategyPerformance perf;
            if(SafeGetStrategyPerformance(m_strategyNames[i], perf)) {
                // Use expectancy as weight
                m_strategyWeights[i] = MathMax(0.0, perf.expectancy);
                
                // Store regime-specific performance
                m_regimeWeights[REGIME_TREND] = perf.performanceByRegime[REGIME_TREND];
                m_regimeWeights[REGIME_RANGE] = perf.performanceByRegime[REGIME_RANGE];
                m_regimeWeights[REGIME_VOLATILE] = perf.performanceByRegime[REGIME_VOLATILE];
            }
        }
        */
        
        // Fallback: Use equal weights
        for(int i = 0; i < m_strategyCount; i++) {
            m_strategyWeights[i] = 1.0;
        }
        
        // Normalize weights
        double totalWeight = 0.0;
        for(int i = 0; i < m_strategyCount; i++) {
            totalWeight += m_strategyWeights[i];
        }
        
        if(totalWeight > 0.0) {
            for(int i = 0; i < m_strategyCount; i++) {
                m_strategyWeights[i] /= totalWeight;
            }
        } else {
            // If no positive weights, use equal weights
            for(int i = 0; i < m_strategyCount; i++) {
                m_strategyWeights[i] = 1.0 / m_strategyCount;
            }
        }
    }

public:
    // Get trading signal and confidence
    int GetSignal(const string &symbol, const int &inputStrategySignals[], double &out_confidence) {
        if(!m_isInitialized) {
            Print("[BRAIN] Error: Brain not initialized. Cannot generate signal.");
            return 0; // No signal / error 
        }
        if(m_regimeClassifier == NULL) {
            Print("[BRAIN] Error: Regime classifier missing. Cannot generate signal.");
            return 0; // No signal / error 
        }
        
        // Check if training is needed
        if(TimeCurrent() - m_lastTrainingTime >= m_trainingInterval && !m_isTraining) {
            // Train in a separate thread or during off-hours
            SFeatureVector dataset[];
            int datasetSize = GenerateTrainingDataset(dataset);
            if(datasetSize > 0) {
                TrainNetwork(dataset, datasetSize, 100);
            }
            
            // Update strategy weights
            UpdateStrategyWeights();
        }
        
        // Prepare inputs for the neural network
        double inputs[];
        ArrayResize(inputs, m_strategyCount + 3);

        
        // Copy strategy signals
        for(int i = 0; i < m_strategyCount; i++) {
            inputs[i] = (double)inputStrategySignals[i]; 
        }
        
        // Add market indicators and capture regime for later logging
        SMarketRegimeData currentRegimeData;
        bool hasRegime = false;
        if(SafeUpdateRegime()) {
            if(SafeGetRegimeData(currentRegimeData)) {
                hasRegime = true;
                inputs[m_strategyCount] = currentRegimeData.trendStrength / 100.0; 
                inputs[m_strategyCount + 1] = currentRegimeData.volatility / 10.0; 
                inputs[m_strategyCount + 2] = currentRegimeData.rangeWidth / 10.0; 
            }
        }
        
        // Forward pass through the network
        ForwardPass(inputs);
        
        // Get outputs
        double buyConfidence = m_network.layers[2].nodes[0].output;
        double sellConfidence = m_network.layers[2].nodes[1].output;
        double noTradeConfidence = m_network.layers[2].nodes[2].output;
        
        // Determine signal
        int signal = 0;
        double confidence = 0.0;
        
        if(buyConfidence > sellConfidence && buyConfidence > noTradeConfidence && buyConfidence > m_confidenceThreshold) {
            signal = 1; 
            confidence = buyConfidence;
        } else if(sellConfidence > buyConfidence && sellConfidence > noTradeConfidence && sellConfidence > m_confidenceThreshold) {
            signal = -1; 
            confidence = sellConfidence;
        } else {
            signal = 0; 
            confidence = noTradeConfidence;
        }
        
        // Apply regime-specific adjustment
        double regimeAdjustment = 1.0;
        if(hasRegime) {
            switch(currentRegimeData.regime) {
                case MARKET_REGIME_TRENDING:
                    regimeAdjustment = m_regimeWeights[MARKET_REGIME_TRENDING];
                    break;
                case MARKET_REGIME_RANGING:
                    regimeAdjustment = m_regimeWeights[MARKET_REGIME_RANGING];
                    break;
                case MARKET_REGIME_VOLATILE:
                    regimeAdjustment = m_regimeWeights[MARKET_REGIME_VOLATILE];
                    break;
                case MARKET_REGIME_LOW_VOLATILITY:
                    regimeAdjustment = m_regimeWeights[MARKET_REGIME_LOW_VOLATILITY];
                    break;
            }
        }
        
        // Adjust confidence based on regime performance
        confidence *= regimeAdjustment;
        
        // Log decision
        string regimeDesc = hasRegime ? GetMarketRegimeDescription(currentRegimeData.regime) : "Unknown";
        Print("[BRAIN] Signal: ", signal, ", Confidence: ", DoubleToString(confidence, 2), 
             ", Buy: ", DoubleToString(buyConfidence, 2), 
             ", Sell: ", DoubleToString(sellConfidence, 2), 
             ", No Trade: ", DoubleToString(noTradeConfidence, 2), 
             ", Regime: ", regimeDesc);
        
        out_confidence = confidence;
        return signal;
    }
    
    // Get market regime description
    string GetMarketRegimeDescription(ENUM_MARKET_REGIME regime) {
        switch(regime) {
            case MARKET_REGIME_TRENDING:
                return "Trending";
            case MARKET_REGIME_RANGING:
                return "Range-bound";
            case MARKET_REGIME_VOLATILE:
                return "Volatile";
            default:
                return "Unknown";
        }
    }
    
    // Get strategy weight
    double GetStrategyWeight(int strategyIndex) {
        if(strategyIndex >= 0 && strategyIndex < m_strategyCount) {
            return m_strategyWeights[strategyIndex];
        }
        return 0.0;
    }
    
    // Get strategy weight by name
    double GetStrategyWeight(const string &strategyName) {
        for(int i = 0; i < m_strategyCount; i++) {
            if(m_strategyNames[i] == strategyName) {
                return m_strategyWeights[i];
            }
        }
        return 0.0;
    }
    
    // Set confidence threshold
    void SetConfidenceThreshold(double threshold) {
        m_confidenceThreshold = MathMax(0.5, MathMin(1.0, threshold));
    }
    
    // Print brain status
    void PrintBrainStatus(const string &symbol) {
        if(!m_isInitialized) {
            Print("=== ENHANCED BRAIN STATUS ===");
            Print("Initialized: No");
            Print("===========================");
            return;
        }
        Print("=== ENHANCED BRAIN STATUS ===");
        Print("Initialized: ", m_isInitialized ? "Yes" : "No");
        Print("Training: ", m_isTraining ? "Yes" : "No");
        Print("Last Training: ", TimeToString(m_lastTrainingTime));
        Print("Next Training: ", TimeToString(m_lastTrainingTime + m_trainingInterval));
        Print("Confidence Threshold: ", DoubleToString(m_confidenceThreshold, 2));
        
        Print("Strategy Weights:");
        for(int i = 0; i < m_strategyCount; i++) {
            Print("  ", m_strategyNames[i], ": ", DoubleToString(m_strategyWeights[i] * 100, 1), "%");
        }
        
        Print("Regime Weights:");
        Print("  Trend: ", DoubleToString(m_regimeWeights[MARKET_REGIME_TRENDING], 2));
        Print("  Range: ", DoubleToString(m_regimeWeights[MARKET_REGIME_RANGING], 2));
        Print("  Volatile: ", DoubleToString(m_regimeWeights[MARKET_REGIME_VOLATILE], 2));
        
        if(m_regimeClassifier != NULL) {
            if(SafeUpdateRegime()) {
                SMarketRegimeData _reg;
                if(SafeGetRegimeData(_reg)) {
                    Print("[BRAIN STATUS] Current Regime: ", GetMarketRegimeDescription(_reg.regime));
                }
            }
        } else {
            Print("Current Market Regime: Classifier not available.");
        }
        Print("===========================");
    }
};

#endif
