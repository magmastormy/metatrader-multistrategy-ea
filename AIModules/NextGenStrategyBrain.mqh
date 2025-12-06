//+------------------------------------------------------------------+
//| Next-Generation Strategy Brain Integration                      |
//| Replaces old StrategyBrain with modern AI ensemble system      |
//+------------------------------------------------------------------+
#ifndef __NEXTGEN_STRATEGY_BRAIN_MQH__
#define __NEXTGEN_STRATEGY_BRAIN_MQH__

#include <Arrays\ArrayDouble.mqh>
#include <Math\Stat\Math.mqh>
#include "TransformerBrain.mqh"
#include "EnsembleMetaLearner.mqh"
#include "UncertaintyQuantifier.mqh"
#include "../Core/MarketRegimeDetector.mqh"
#include "../Core/Enums.mqh"

//+------------------------------------------------------------------+
//| Market Data Processor for AI Models                            |
//+------------------------------------------------------------------+
class CMarketDataProcessor {
private:
    double m_priceData[];
    double m_volumeData[];
    double m_indicatorData[];
    int m_maxSequenceLength;
    int m_currentCount;
    
public:
    CMarketDataProcessor(int maxSeqLen = 100) {
        m_maxSequenceLength = maxSeqLen;
        m_currentCount = 0;
        ArrayResize(m_priceData, maxSeqLen);
        ArrayResize(m_volumeData, maxSeqLen);
        ArrayResize(m_indicatorData, maxSeqLen * 10); // 10 indicators per point
        ArrayInitialize(m_priceData, 0.0);
        ArrayInitialize(m_volumeData, 0.0);
        ArrayInitialize(m_indicatorData, 0.0);
    }
    
    // Add market data point
    bool AddDataPoint(double price, double volume, const double &indicators[]) {
        // Shift data left
        if(m_currentCount >= m_maxSequenceLength) {
            ArrayCopy(m_priceData, m_priceData, 0, 1, m_maxSequenceLength - 1);
            ArrayCopy(m_volumeData, m_volumeData, 0, 1, m_maxSequenceLength - 1);
            
            // Shift indicators (block copy)
            int indCount = 10;
            int totalInd = m_maxSequenceLength * indCount;
            ArrayCopy(m_indicatorData, m_indicatorData, 0, indCount, totalInd - indCount);
            
            m_priceData[m_maxSequenceLength - 1] = price;
            m_volumeData[m_maxSequenceLength - 1] = volume;
            
            // Add new indicators
            int startIdx = (m_maxSequenceLength - 1) * indCount;
            for(int i = 0; i < indCount && i < ArraySize(indicators); i++) {
                m_indicatorData[startIdx + i] = indicators[i];
            }
        } else {
            m_priceData[m_currentCount] = price;
            m_volumeData[m_currentCount] = volume;
            
            int startIdx = m_currentCount * 10;
            for(int i = 0; i < 10 && i < ArraySize(indicators); i++) {
                m_indicatorData[startIdx + i] = indicators[i];
            }
            m_currentCount++;
        }
        
        return true;
    }
    
    // Prepare data for AI models with proper normalization
    bool PrepareModelInput(double &modelInput[], int &sequenceLength) {
        sequenceLength = m_currentCount;
        if(sequenceLength < 10) return false; // Need minimum data
        
        int featuresPerStep = 12; // price, volume, + 10 indicators
        ArrayResize(modelInput, sequenceLength * featuresPerStep);
        
        // Calculate price statistics
        double priceMean = 0.0, priceStd = 0.0;
        for(int i = 0; i < sequenceLength; i++) priceMean += m_priceData[i];
        priceMean /= sequenceLength;
        
        for(int i = 0; i < sequenceLength; i++) {
            double diff = m_priceData[i] - priceMean;
            priceStd += diff * diff;
        }
        priceStd = MathSqrt(priceStd / sequenceLength);
        if(priceStd < 0.001) priceStd = 0.001;
        
        // Calculate volume statistics
        double volumeMean = 0.0, volumeStd = 0.0;
        for(int i = 0; i < sequenceLength; i++) volumeMean += m_volumeData[i];
        volumeMean /= sequenceLength;
        
        for(int i = 0; i < sequenceLength; i++) {
            double diff = m_volumeData[i] - volumeMean;
            volumeStd += diff * diff;
        }
        volumeStd = MathSqrt(volumeStd / sequenceLength);
        if(volumeStd < 0.001) volumeStd = 0.001;
        
        // Normalize and fill input
        for(int i = 0; i < sequenceLength; i++) {
            int baseIdx = i * featuresPerStep;
            
            // Price (Z-score)
            modelInput[baseIdx] = (m_priceData[i] - priceMean) / priceStd;
            
            // Volume (Z-score clamped)
            double normVol = (m_volumeData[i] - volumeMean) / volumeStd;
            modelInput[baseIdx + 1] = MathMax(-3.0, MathMin(3.0, normVol));
            
            // Indicators
            for(int j = 0; j < 10; j++) {
                int indIdx = i * 10 + j;
                double val = m_indicatorData[indIdx];
                modelInput[baseIdx + 2 + j] = MathMax(-10.0, MathMin(10.0, val));
            }
        }
        
        return true;
    }
};

//+------------------------------------------------------------------+
//| Next-Generation Strategy Brain                                 |
//+------------------------------------------------------------------+
class CNextGenStrategyBrain {
private:
    CMarketDataProcessor* m_dataProcessor;
    bool m_initialized;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    
    // AI components
    CTransformerBrain* m_transformerBrain;
    CEnsembleMetaLearner* m_ensembleSystem;
    CUncertaintyQuantifier* m_uncertaintyQuantifier;
    
    // Performance tracking
    double m_totalReturn;
    int m_totalTrades;
    int m_winningTrades;
    datetime m_lastUpdate;
    
    // AI model parameters
    double m_confidenceThreshold;
    double m_uncertaintyThreshold;
    bool m_useUncertaintyFiltering;
    
    // Connection state
    int m_consecutiveFailures;
    datetime m_lastFailureTime;
    bool m_serverCircuitOpen;
    
public:
    CNextGenStrategyBrain() {
        m_dataProcessor = new CMarketDataProcessor(100);
        m_initialized = false;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_transformerBrain = NULL;
        m_ensembleSystem = NULL;
        m_uncertaintyQuantifier = NULL;
        
        m_totalReturn = 0.0;
        m_totalTrades = 0;
        m_winningTrades = 0;
        m_lastUpdate = 0;
        
        m_confidenceThreshold = 0.6;
        m_uncertaintyThreshold = 0.4;
        m_useUncertaintyFiltering = true;
        
        m_consecutiveFailures = 0;
        m_lastFailureTime = 0;
        m_serverCircuitOpen = false;
    }
    
    ~CNextGenStrategyBrain() {
        if(CheckPointer(m_dataProcessor) == POINTER_DYNAMIC) delete m_dataProcessor;
        if(CheckPointer(m_transformerBrain) == POINTER_DYNAMIC) delete m_transformerBrain;
        if(CheckPointer(m_ensembleSystem) == POINTER_DYNAMIC) delete m_ensembleSystem;
        if(CheckPointer(m_uncertaintyQuantifier) == POINTER_DYNAMIC) delete m_uncertaintyQuantifier;
    }
    
    // Initialize the AI brain system
    bool Initialize(string brainSymbol, ENUM_TIMEFRAMES timeframe) {
        m_symbol = brainSymbol;
        m_timeframe = timeframe;
        
        // Initialize Transformer Brain (Local Model)
        if(m_transformerBrain == NULL) {
            m_transformerBrain = new CTransformerBrain(64, 4, 2, 128, 100); // Lightweight config for EA
            if(!m_transformerBrain) return false;
        }
        
        // Initialize Ensemble
        if(m_ensembleSystem == NULL) {
            m_ensembleSystem = new CEnsembleMetaLearner();
            if(!m_ensembleSystem) return false;
        }
        
        // Initialize Uncertainty
        if(m_uncertaintyQuantifier == NULL) {
            m_uncertaintyQuantifier = new CUncertaintyQuantifier(100, 0.95);
            if(!m_uncertaintyQuantifier) return false;
        }
        
        m_initialized = true;
        Print("[NEXTGEN] AI Strategy Brain initialized for ", brainSymbol);
        return true;
    }
    
    // Process market data and generate enhanced trading signal
    bool GenerateSignal(double price, double volume, const double &indicators[], 
                       SEnhancedTradeSignal &signal) {
        if(!m_initialized) return false;
        
        // Add new market data
        m_dataProcessor.AddDataPoint(price, volume, indicators);
        
        // Prepare input for AI models
        double modelInput[];
        int sequenceLength;
        if(!m_dataProcessor.PrepareModelInput(modelInput, sequenceLength)) {
            return false;
        }
        
        bool serverSuccess = false;
        
        // Try Remote Inference (if circuit not open)
        if(!m_serverCircuitOpen) {
            if(SendInferenceRequest(modelInput, signal)) {
                serverSuccess = true;
                m_consecutiveFailures = 0;
            } else {
                m_consecutiveFailures++;
                if(m_consecutiveFailures > 5) {
                    m_serverCircuitOpen = true;
                    m_lastFailureTime = TimeCurrent();
                    Print("[AI-BRIDGE] Circuit Breaker Open - Switching to Local Mode");
                }
            }
        } else {
            // Check if we should retry server (every 5 minutes)
            if(TimeCurrent() - m_lastFailureTime > 300) {
                m_serverCircuitOpen = false;
                m_consecutiveFailures = 0;
            }
        }
        
        // Fallback to Local Transformer if server failed or disabled
        if(!serverSuccess) {
            double output[];
            if(m_transformerBrain.Forward(modelInput, output)) {
                // Interpret output: [0]=Buy, [1]=Sell, [2]=Hold
                double buyProb = output[0];
                double sellProb = output[1];
                double holdProb = output[2];
                
                // Softmax normalization
                double maxVal = MathMax(buyProb, MathMax(sellProb, holdProb));
                double expBuy = MathExp(buyProb - maxVal);
                double expSell = MathExp(sellProb - maxVal);
                double expHold = MathExp(holdProb - maxVal);
                double sumExp = expBuy + expSell + expHold;
                
                buyProb = expBuy / sumExp;
                sellProb = expSell / sumExp;
                holdProb = expHold / sumExp;
                
                signal.buyProbability = buyProb;
                signal.sellProbability = sellProb;
                signal.timestamp = TimeCurrent();
                signal.reasoning = "Local Transformer Model";
                
                if(buyProb > m_confidenceThreshold && buyProb > sellProb && buyProb > holdProb) {
                    signal.signal = TRADE_SIGNAL_BUY;
                    signal.confidence = buyProb;
                } else if(sellProb > m_confidenceThreshold && sellProb > buyProb && sellProb > holdProb) {
                    signal.signal = TRADE_SIGNAL_SELL;
                    signal.confidence = sellProb;
                } else {
                    signal.signal = TRADE_SIGNAL_NONE;
                    signal.confidence = holdProb;
                }
                
                // Estimate uncertainty (entropy)
                double entropy = -(buyProb * MathLog(buyProb + 1e-9) + 
                                 sellProb * MathLog(sellProb + 1e-9) + 
                                 holdProb * MathLog(holdProb + 1e-9));
                signal.uncertainty.uncertainty = entropy / 1.0986; // Normalized by log(3)
                
            } else {
                // Total failure
                signal.signal = TRADE_SIGNAL_NONE;
                signal.reasoning = "AI Failure";
                return false;
            }
        }
        
        // Apply filters
        if(signal.confidence < m_confidenceThreshold) {
            signal.signal = TRADE_SIGNAL_NONE;
            signal.reasoning += " [Low Confidence]";
        }
        
        return true;
    }
    
private:
    // Send inference request to Python AI server
    bool SendInferenceRequest(const double &modelInput[], SEnhancedTradeSignal &signal) {
        char postData[];
        char resultData[];
        string resultHeaders;
        string url = "http://localhost:8000/predict";
        
        // Construct JSON payload manually
        string jsonPayload = "{\"market_data\": [";
        for(int i = 0; i < ArraySize(modelInput); i++) {
            jsonPayload += DoubleToString(modelInput[i], 5);
            if(i < ArraySize(modelInput) - 1) jsonPayload += ",";
        }
        jsonPayload += "], \"symbol\": \"" + m_symbol + "\", \"timeframe\": " + IntegerToString((int)m_timeframe) + "}";
        
        StringToCharArray(jsonPayload, postData);
        
        // Reset error state
        ResetLastError();
        
        // Send WebRequest
        int res = WebRequest("POST", url, "Content-Type: application/json\r\n", 2000, postData, resultData, resultHeaders);
        
        if(res == 200) {
            string jsonResponse = CharArrayToString(resultData);
            return ParseJSONResponse(jsonResponse, signal);
        }
        return false;
    }

    // Simple JSON parser for flat response structure
    bool ParseJSONResponse(string json, SEnhancedTradeSignal &signal) {
        // Remove braces and cleanup
        StringReplace(json, "{", "");
        StringReplace(json, "}", "");
        StringReplace(json, "\"", "");
        
        string parts[];
        StringSplit(json, ',', parts);
        
        for(int i = 0; i < ArraySize(parts); i++) {
            string pair[];
            StringSplit(parts[i], ':', pair);
            
            if(ArraySize(pair) == 2) {
                string key = pair[0];
                string value = pair[1];
                
                // Trim whitespace
                StringTrimLeft(key); StringTrimRight(key);
                StringTrimLeft(value); StringTrimRight(value);
                
                if(key == "signal") {
                    double sigVal = StringToDouble(value);
                    if(sigVal > 0.3) signal.signal = TRADE_SIGNAL_BUY;
                    else if(sigVal < -0.3) signal.signal = TRADE_SIGNAL_SELL;
                    else signal.signal = TRADE_SIGNAL_NONE;
                }
                else if(key == "confidence") signal.confidence = StringToDouble(value);
                else if(key == "uncertainty") signal.uncertainty.uncertainty = StringToDouble(value);
                else if(key == "volatility") signal.volatilityFactor = StringToDouble(value);
                else if(key == "reasoning") signal.reasoning = value;
            }
        }
        
        signal.timestamp = TimeCurrent();
        signal.riskAdjustedSize = 1.0 * (1.0 - signal.uncertainty.uncertainty);
        return true;
    }
    
public:
    // Update performance based on trade results
    bool UpdatePerformance(double tradeReturn, bool isWin, double drawdown = 0.0) {
        m_totalTrades++;
        m_totalReturn += tradeReturn;
        if(isWin) m_winningTrades++;
        m_lastUpdate = TimeCurrent();
        return true;
    }
    
    // Get performance statistics
    void GetPerformanceStats(double &totalReturn, double &winRate, int &brainTotalTrades) {
        totalReturn = m_totalReturn;
        brainTotalTrades = m_totalTrades;
        winRate = (m_totalTrades > 0) ? (double)m_winningTrades / m_totalTrades : 0.0;
    }

    // Get accuracy (win rate)
    double GetAccuracy() {
        return (m_totalTrades > 0) ? (double)m_winningTrades / m_totalTrades : 0.0;
    }

    // Get epoch count (placeholder for now as online learning is continuous)
    int GetEpochCount() {
        return m_totalTrades; // Using total trades as a proxy for "experience" or epochs
    }

    // Save AI state to file
    bool SaveAIState(string filename) {
        int handle = FileOpen(filename, FILE_WRITE|FILE_BIN);
        if(handle == INVALID_HANDLE) return false;
        
        // Save metadata
        FileWriteString(handle, m_symbol);
        FileWriteInteger(handle, (int)m_timeframe);
        FileWriteDouble(handle, m_totalReturn);
        FileWriteInteger(handle, m_totalTrades);
        FileWriteInteger(handle, m_winningTrades);
        FileWriteLong(handle, (long)m_lastUpdate);
        
        // Note: Full transformer weight saving would require recursive serialization
        // For now we save the performance state which is critical for the EA
        
        FileClose(handle);
        return true;
    }

    // Generate detailed AI report
    string GenerateAIReport() {
        string report = "=== NextGen AI Strategy Brain Report ===\n";
        report += StringFormat("Symbol: %s\n", m_symbol);
        report += StringFormat("Timeframe: %s\n", EnumToString(m_timeframe));
        report += StringFormat("Total Trades: %d\n", m_totalTrades);
        report += StringFormat("Win Rate: %.2f%%\n", GetAccuracy() * 100.0);
        report += StringFormat("Total Return: %.2f\n", m_totalReturn);
        
        if(m_transformerBrain != NULL) {
            report += "\n--- Transformer Model ---\n";
            report += m_transformerBrain.GetModelInfo();
        }
        
        return report;
    }

    // Shutdown alias
    void Shutdown() {
        // Cleanup handled by destructor
    }
};

#endif // __NEXTGEN_STRATEGY_BRAIN_MQH__
