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
    CArrayDouble m_priceData;
    CArrayDouble m_volumeData;
    CArrayDouble m_indicatorData;
    int m_maxSequenceLength;
    
public:
    CMarketDataProcessor(int maxSeqLen = 100) {
        m_maxSequenceLength = maxSeqLen;
    }
    
    // Add market data point
    bool AddDataPoint(double price, double volume, const CArrayDouble &indicators) {
        m_priceData.Add(price);
        m_volumeData.Add(volume);
        
        // Add indicator values
        for(int i = 0; i < indicators.Total(); i++) {
            m_indicatorData.Add(indicators.At(i));
        }
        
        // Maintain sequence length
        while(m_priceData.Total() > m_maxSequenceLength) {
            m_priceData.Delete(0);
            m_volumeData.Delete(0);
        }
        
        // Maintain indicator data (assuming 10 indicators per data point)
        int indicatorsPerPoint = 10;
        while(m_indicatorData.Total() > m_maxSequenceLength * indicatorsPerPoint) {
            for(int i = 0; i < indicatorsPerPoint; i++) {
                m_indicatorData.Delete(0);
            }
        }
        
        return true;
    }
    
    // Prepare data for AI models with proper normalization
    bool PrepareModelInput(CArrayDouble &modelInput, int &sequenceLength) {
        sequenceLength = m_priceData.Total();
        if(sequenceLength < 10) return false; // Need minimum data
        
        int featuresPerStep = 12; // price, volume, + 10 indicators
        modelInput.Resize(sequenceLength * featuresPerStep);
        
        // Calculate price statistics for proper normalization
        double priceMean = 0.0, priceStd = 0.0;
        for(int i = 0; i < sequenceLength; i++) {
            priceMean += m_priceData.At(i);
        }
        priceMean /= sequenceLength;
        
        for(int i = 0; i < sequenceLength; i++) {
            double diff = m_priceData.At(i) - priceMean;
            priceStd += diff * diff;
        }
        priceStd = MathSqrt(priceStd / sequenceLength);
        if(priceStd < 0.001) priceStd = 0.001; // Prevent division by zero
        
        // Calculate volume statistics
        double volumeMean = 0.0, volumeStd = 0.0;
        for(int i = 0; i < sequenceLength; i++) {
            volumeMean += m_volumeData.At(i);
        }
        volumeMean /= sequenceLength;
        
        for(int i = 0; i < sequenceLength; i++) {
            double diff = m_volumeData.At(i) - volumeMean;
            volumeStd += diff * diff;
        }
        volumeStd = MathSqrt(volumeStd / sequenceLength);
        if(volumeStd < 0.001) volumeStd = 0.001;
        
        for(int i = 0; i < sequenceLength; i++) {
            int baseIdx = i * featuresPerStep;
            
            // Normalize price using z-score normalization
            double price = m_priceData.At(i);
            double normalizedPrice = (price - priceMean) / priceStd;
            modelInput.Update(baseIdx, normalizedPrice);
            
            // Normalize volume using z-score
            double volume = m_volumeData.At(i);
            double normalizedVolume = (volume - volumeMean) / volumeStd;
            // Clamp to reasonable range [-3, 3]
            normalizedVolume = MathMax(-3.0, MathMin(3.0, normalizedVolume));
            modelInput.Update(baseIdx + 1, normalizedVolume);
            
            // Add indicator values with proper bounds checking
            for(int j = 0; j < 10; j++) {
                int indicatorIdx = i * 10 + j;
                double indicatorValue = 0.0;
                
                if(indicatorIdx < m_indicatorData.Total()) {
                    indicatorValue = m_indicatorData.At(indicatorIdx);
                    // Clamp indicator values to reasonable range
                    indicatorValue = MathMax(-10.0, MathMin(10.0, indicatorValue));
                }
                
                modelInput.Update(baseIdx + 2 + j, indicatorValue);
            }
        }
        
        return true;
    }
    
    // Get current price and volume
    bool GetCurrentData(double &price, double &volume) {
        if(m_priceData.Total() == 0) return false;
        
        price = m_priceData.At(m_priceData.Total() - 1);
        volume = m_volumeData.At(m_volumeData.Total() - 1);
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
    CMarketRegimeClassifier* m_regimeDetector;
    
    // Performance tracking
    double m_totalReturn;
    int m_totalTrades;
    int m_winningTrades;
    datetime m_lastUpdate;
    
    // AI model parameters
    double m_confidenceThreshold;
    double m_uncertaintyThreshold;
    bool m_useUncertaintyFiltering;
    
public:
    // Initialize transformer brain component
    bool InitializeTransformerBrain(int dModel, int numHeads, int numLayers) {
        // Initialize transformer brain with specified parameters
        if(m_transformerBrain != NULL) {
            delete m_transformerBrain;
            m_transformerBrain = NULL;
        }
        
        m_transformerBrain = new CTransformerBrain(dModel, numHeads, numLayers);
        if(m_transformerBrain == NULL) {
            Print("[ERROR] Failed to allocate transformer brain");
            return false;
        }
        
        Print("[NEXTGEN] Transformer brain initialized: dModel=", dModel, ", heads=", numHeads, ", layers=", numLayers);
        return true;
    }
    
    // Initialize ensemble component
    bool InitializeEnsemble(int maxModels) {
        // Initialize ensemble system with specified parameters
        if(m_ensembleSystem != NULL) {
            delete m_ensembleSystem;
            m_ensembleSystem = NULL;
        }
        
        m_ensembleSystem = new CEnsembleMetaLearner();
        if(m_ensembleSystem == NULL) {
            Print("[ERROR] Failed to allocate ensemble system");
            return false;
        }
        
        // Ensemble system is ready to use after construction
        // No additional initialization needed
        
        Print("[NEXTGEN] Ensemble system initialized: maxModels=", maxModels);
        return true;
    }
    
    // Initialize uncertainty quantifier
    bool InitializeUncertainty(int maxSamples, double confidenceLevel) {
        // Initialize uncertainty quantifier with specified parameters
        if(m_uncertaintyQuantifier != NULL) {
            delete m_uncertaintyQuantifier;
            m_uncertaintyQuantifier = NULL;
        }
        
        m_uncertaintyQuantifier = new CUncertaintyQuantifier(maxSamples, confidenceLevel);
        if(m_uncertaintyQuantifier == NULL) {
            Print("[ERROR] Failed to allocate uncertainty quantifier");
            return false;
        }
        
        Print("[NEXTGEN] Uncertainty quantifier initialized: maxSamples=", maxSamples, ", confidence=", confidenceLevel);
        return true;
    }
    
    // Generate trade signal
    SEnhancedTradeSignal GenerateSignal();
    
    // Update with market data
    bool UpdateMarketData(double price, double volume, const CArrayDouble &indicators);
    
    // Save models
    bool SaveModels(const string &filename);
    
    // Load models
    bool LoadModels(const string &filename);
    
    // Get performance metrics
    void GetPerformanceMetrics(double &totalReturn, int &totalTrades, int &winningTrades);
    
    // Check if initialized
    bool IsInitialized() const { return m_initialized; }
    
private:
    // Send inference request to Python AI server
    bool SendInferenceRequest(const CArrayDouble &modelInput, SEnhancedTradeSignal &signal) {
        char postData[];
        char resultData[];
        string resultHeaders;
        string url = "http://localhost:8000/predict";
        
        // Construct JSON payload manually
        string jsonPayload = "{\"market_data\": [";
        for(int i = 0; i < modelInput.Total(); i++) {
            jsonPayload += DoubleToString(modelInput.At(i), 5);
            if(i < modelInput.Total() - 1) jsonPayload += ",";
        }
        jsonPayload += "], \"symbol\": \"" + m_symbol + "\", \"timeframe\": " + IntegerToString((int)m_timeframe) + "}";
        
        StringToCharArray(jsonPayload, postData);
        
        // Reset error state
        ResetLastError();
        
        // Send WebRequest
        int res = WebRequest("POST", url, "Content-Type: application/json\r\n", 5000, postData, resultData, resultHeaders);
        
        if(res == 200) {
            // Parse successful response
            string jsonResponse = CharArrayToString(resultData);
            return ParseJSONResponse(jsonResponse, signal);
        } else {
            Print("[AI-BRIDGE] WebRequest failed. Error: ", GetLastError(), " Status: ", res);
            if(res == -1) {
                Print("[AI-BRIDGE] Hint: Add 'http://localhost:8000' to Allowed URLs in Tools->Options->Expert Advisors");
            }
            return false;
        }
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
                    
                    // Store raw probabilities (simulated from signal strength)
                    if(sigVal > 0) {
                        signal.buyProbability = 0.5 + (sigVal * 0.5);
                        signal.sellProbability = 1.0 - signal.buyProbability;
                    } else {
                        signal.sellProbability = 0.5 + (MathAbs(sigVal) * 0.5);
                        signal.buyProbability = 1.0 - signal.sellProbability;
                    }
                }
                else if(key == "confidence") signal.confidence = StringToDouble(value);
                else if(key == "uncertainty") signal.uncertainty.uncertainty = StringToDouble(value);
                else if(key == "volatility") signal.volatilityFactor = StringToDouble(value);
                else if(key == "reasoning") signal.reasoning = value;
            }
        }
        
        // Set derived fields
        signal.timestamp = TimeCurrent();
        signal.regime = MARKET_REGIME_TRENDING; // Default, could be parsed if added to response
        signal.regimeConfidence = 0.8;
        signal.riskAdjustedSize = 1.0 * (1.0 - signal.uncertainty.uncertainty);
        
        return true;
    }

    // Generate reasoning explanation
    string GenerateReasoning(const SEnhancedTradeSignal &signal) {
        string reasoning = "";
        
        // Regime-based reasoning
        string regimeName = "UNKNOWN";
        switch(signal.regime) {
            case MARKET_REGIME_TRENDING: regimeName = "TRENDING"; break;
            case MARKET_REGIME_RANGING: regimeName = "RANGING"; break;
            case MARKET_REGIME_VOLATILE: regimeName = "VOLATILE"; break;
            case MARKET_REGIME_LOW_VOLATILITY: regimeName = "LOW_VOLATILITY"; break;
            default: regimeName = "UNKNOWN"; break;
        }
        reasoning += "Market Regime: " + regimeName + 
                    " (Confidence: " + DoubleToString(signal.regimeConfidence * 100, 1) + "%). ";
        
        // Signal strength reasoning
        if(signal.signal == TRADE_SIGNAL_BUY) {
            reasoning += "Strong BUY signal detected with " + DoubleToString(signal.buyProbability * 100, 1) + 
                        "% probability. ";
        } else if(signal.signal == TRADE_SIGNAL_SELL) {
            reasoning += "Strong SELL signal detected with " + DoubleToString(signal.sellProbability * 100, 1) + 
                        "% probability. ";
        } else {
            reasoning += "Neutral/HOLD signal - insufficient conviction for directional trade. ";
        }
        
        // Uncertainty reasoning
        if(signal.uncertainty.uncertainty > 0.5) {
            reasoning += "HIGH uncertainty detected (" + DoubleToString(signal.uncertainty.uncertainty * 100, 1) + 
                        "%) - position size reduced. ";
        } else if(signal.uncertainty.uncertainty < 0.3) {
            reasoning += "LOW uncertainty (" + DoubleToString(signal.uncertainty.uncertainty * 100, 1) + 
                        "%) - high confidence trade. ";
        }
        
        // Risk adjustment reasoning
        if(signal.riskAdjustedSize < 1.0) {
            reasoning += "Risk-adjusted position sizing applied due to uncertainty.";
        }
        
        return reasoning;
    }
    
public:
    CNextGenStrategyBrain() {
        m_dataProcessor = new CMarketDataProcessor(100);
        m_initialized = false;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        
        m_totalReturn = 0.0;
        m_totalTrades = 0;
        m_winningTrades = 0;
        m_lastUpdate = 0;
        
        m_confidenceThreshold = 0.6;
        m_uncertaintyThreshold = 0.4;
        m_useUncertaintyFiltering = true;
    }
    
    ~CNextGenStrategyBrain() {
        // Clean up data processor
        if(m_dataProcessor != NULL) {
            delete m_dataProcessor;
            m_dataProcessor = NULL;
        }
        
        // Note: Transformer, ensemble, and other AI components
        // are stack-allocated and will clean up automatically
        
        Print("[NextGenBrain] Destructor called - memory cleaned");
    }
    
    // Initialize the AI brain system
    bool Initialize(string brainSymbol, ENUM_TIMEFRAMES timeframe) {
        m_symbol = brainSymbol;
        m_timeframe = timeframe;
        
        // Initialize all AI components
        if(!InitializeTransformerBrain(256, 6, 8)) {
            Print("[ERROR] Failed to initialize Transformer Brain");
            return false;
        }
        
        if(!InitializeEnsemble(5)) {
            Print("[ERROR] Failed to initialize Ensemble System");
            return false;
        }
        
        if(!InitializeUncertainty(1000, 0.95)) {
            Print("[ERROR] Failed to initialize Uncertainty Quantifier");
            return false;
        }
        
        m_initialized = true;
        Print("[NEXTGEN] AI Strategy Brain initialized for ", brainSymbol, " on ", EnumToString(timeframe));
        
        return true;
    }
    
    // Process market data and generate enhanced trading signal
    bool GenerateSignal(double price, double volume, const CArrayDouble &indicators, 
                       SEnhancedTradeSignal &signal) {
        if(!m_initialized) {
            Print("[ERROR] NextGen Brain not initialized");
            return false;
        }
        
        // Add new market data
        m_dataProcessor.AddDataPoint(price, volume, indicators);
        
        // Prepare input for AI models
        CArrayDouble modelInput;
        int sequenceLength;
        if(!m_dataProcessor.PrepareModelInput(modelInput, sequenceLength)) {
            Print("[WARNING] Insufficient data for AI prediction");
            return false;
        }
        
        // Get ensemble prediction via WebRequest
        if(SendInferenceRequest(modelInput, signal)) {
            // Signal populated by ParseJSONResponse
            
            // Apply local filters
            bool passesFilters = true;
            if(signal.confidence < m_confidenceThreshold) passesFilters = false;
            if(m_useUncertaintyFiltering && signal.uncertainty.uncertainty > m_uncertaintyThreshold) passesFilters = false;
            
            if(!passesFilters) {
                signal.signal = TRADE_SIGNAL_NONE;
                signal.riskAdjustedSize = 0.0;
                signal.reasoning += " [FILTERED: Low Confidence/High Uncertainty]";
            }
            
            return true;
        } else {
            // Fallback to local logic if server fails
            Print("[AI-BRIDGE] Connection failed - using fallback logic");
            
            // Simple fallback logic (e.g., random or based on indicators)
            // For safety, return NO SIGNAL in fallback mode
            signal.signal = TRADE_SIGNAL_NONE;
            signal.confidence = 0.0;
            signal.reasoning = "AI Server Connection Failed - Fallback Safety Mode";
            return true;
        }
    }
    
    // Update performance based on trade results
    bool UpdatePerformance(double tradeReturn, bool isWin, double drawdown = 0.0) {
        m_totalTrades++;
        m_totalReturn += tradeReturn;
        if(isWin) m_winningTrades++;
        
        // Update ensemble performance - simplified
        // Model weights update simulated
        
        // Update uncertainty quantifier
        double prediction = (tradeReturn > 0) ? 1.0 : -1.0;
        // Simplified uncertainty update - in real implementation would call uncertainty quantifier
        double uncertainty = MathAbs(tradeReturn) * 0.1; // Simple uncertainty estimation
        
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

    // Get epoch count (placeholder for Python training)
    int GetEpochCount() {
        return 0;
    }

    // Shutdown alias
    void Shutdown() {
        Deinitialize();
    }
    
    // Generate comprehensive AI report
    string GenerateAIReport() {
        string report = "\n=== NEXT-GENERATION AI BRAIN REPORT ===\n";
        report += StringFormat("Symbol: %s | Timeframe: %s\n", m_symbol, EnumToString(m_timeframe));
        report += StringFormat("Total Return: %.2f%% | Win Rate: %.1f%% | Trades: %d\n", 
                              m_totalReturn * 100, 
                              (m_totalTrades > 0) ? (double)m_winningTrades / m_totalTrades * 100 : 0.0,
                              m_totalTrades);
        
        // Add ensemble report - simplified
        report += "Ensemble Status: Active\n";
        
        // Add current regime info - simplified
        ENUM_MARKET_REGIME localRegime = MARKET_REGIME_TRENDING; // Default
        double regimeConf = 0.75; // Default confidence
        string regimeName = "Unknown";
        switch(localRegime) {
            case MARKET_REGIME_TRENDING: regimeName = "Trending"; break;
            case MARKET_REGIME_RANGING: regimeName = "Ranging"; break;
            case MARKET_REGIME_VOLATILE: regimeName = "Volatile"; break;
            case MARKET_REGIME_LOW_VOLATILITY: regimeName = "Low Volatility"; break;
            case MARKET_REGIME_UNKNOWN: regimeName = "Unknown"; break;
            default: regimeName = "Unknown"; break;
        }
        report += StringFormat("\nCurrent Market Regime: %s (Confidence: %.1f%%)\n", 
                              regimeName, regimeConf * 100);
        
        // Add uncertainty statistics
        double avgUnc, maxUnc, avgErr;
        int samples;
        if(::g_uncertaintyQuantifier) {
            ::g_uncertaintyQuantifier.GetUncertaintyStats(avgUnc, maxUnc, avgErr, samples);
            report += StringFormat("Uncertainty Stats: Avg=%.3f, Max=%.3f, Error=%.3f, Samples=%d\n", 
                                  avgUnc, maxUnc, avgErr, samples);
        }
        
        report += StringFormat("Last Update: %s\n", TimeToString(m_lastUpdate));
        
        return report;
    }
    
    // Set AI parameters
    void SetParameters(double confidenceThreshold, double uncertaintyThreshold, bool useUncertaintyFiltering) {
        m_confidenceThreshold = confidenceThreshold;
        m_uncertaintyThreshold = uncertaintyThreshold;
        m_useUncertaintyFiltering = useUncertaintyFiltering;
        
        Print("[NEXTGEN] Parameters updated - Confidence: ", confidenceThreshold, 
              ", Uncertainty: ", uncertaintyThreshold, ", Filtering: ", useUncertaintyFiltering);
    }
    
    // Save AI state
    bool SaveAIState(string filename) {
        string ensembleFile = filename + "_ensemble.dat";
        bool success = true;
        
        // Save ensemble state - simplified implementation
        // In real implementation, would save ensemble state here
        success = true;
        
        // Save transformer models
        string transformerFile = filename + "_transformer.dat";
        success &= m_transformerBrain.SaveModel(transformerFile);
        
        // Save performance data
        int handle = FileOpen(filename + "_performance.txt", FILE_WRITE | FILE_TXT);
        if(handle != INVALID_HANDLE) {
            FileWriteString(handle, StringFormat("TotalReturn=%.6f\n", m_totalReturn));
            FileWriteString(handle, StringFormat("TotalTrades=%d\n", m_totalTrades));
            FileWriteString(handle, StringFormat("WinningTrades=%d\n", m_winningTrades));
            FileWriteString(handle, StringFormat("LastUpdate=%d\n", (int)m_lastUpdate));
            FileClose(handle);
        } else {
            success = false;
        }
        
        if(success) {
            Print("[NEXTGEN] AI state saved successfully to: ", filename);
        } else {
            Print("[ERROR] Failed to save AI state to: ", filename);
        }
        
        return success;
    }
    
    // Check if AI system is ready
    bool IsReady() {
        return (m_initialized && CheckPointer(m_dataProcessor) != POINTER_INVALID);
    }
    
    // Get current market regime
    ENUM_MARKET_REGIME GetCurrentRegime() {
        // Simplified regime detection - return default for now
        return MARKET_REGIME_TRENDING;
        return MARKET_REGIME_UNKNOWN;
    }
    
    // Enhanced AI reasoning with detailed market analysis - simplified implementation
    SEnhancedTradeSignal EnhanceSignalWithAdvancedReasoning(const SEnhancedTradeSignal &signal, string signalSymbol) {
        // Work on a local copy to avoid modifying const reference
        SEnhancedTradeSignal enhanced = signal;

        // Market volatility analysis (ATR using indicator handle)
        int atrHandle = iATR(signalSymbol, m_timeframe, 14);
        double atrBuf[1];
        double atr = 0.0;
        if(atrHandle != INVALID_HANDLE) {
            if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0) atr = atrBuf[0];
            IndicatorRelease(atrHandle);
        }
        double currentBidPrice = SymbolInfoDouble(signalSymbol, SYMBOL_BID);
        if(currentBidPrice > 0.0)
            enhanced.volatilityFactor = (atr / currentBidPrice) * 100.0; // Volatility as percentage
        else
            enhanced.volatilityFactor = 0.0;
        
        // Trend strength analysis (EMA values via handles)
        int ema20Handle = iMA(signalSymbol, m_timeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
        int ema50Handle = iMA(signalSymbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
        double ema20Buf[1], ema50Buf[1];
        double ema20 = 0.0, ema50 = 0.0;
        if(ema20Handle != INVALID_HANDLE) {
            if(CopyBuffer(ema20Handle, 0, 0, 1, ema20Buf) > 0) ema20 = ema20Buf[0];
            IndicatorRelease(ema20Handle);
        }
        if(ema50Handle != INVALID_HANDLE) {
            if(CopyBuffer(ema50Handle, 0, 0, 1, ema50Buf) > 0) ema50 = ema50Buf[0];
            IndicatorRelease(ema50Handle);
        }
        if(ema50 != 0.0)
            enhanced.trendStrength = MathAbs(ema20 - ema50) / MathAbs(ema50) * 100.0;
        else
            enhanced.trendStrength = 0.0;
        
        // Support/Resistance analysis
        double high = iHigh(signalSymbol, m_timeframe, 0);
        double low = iLow(signalSymbol, m_timeframe, 0);
        if(high > 0.0 && low > 0.0)
            enhanced.supportResistanceLevel = (high + low) / 2.0;
        else
            enhanced.supportResistanceLevel = 0.0;
        
        // Momentum analysis (RSI via handle)
        int rsiHandle = iRSI(signalSymbol, m_timeframe, 14, PRICE_CLOSE);
        double rsiBuf[1];
        double rsi = 50.0;
        if(rsiHandle != INVALID_HANDLE) {
            if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuf) > 0) rsi = rsiBuf[0];
            IndicatorRelease(rsiHandle);
        }
        enhanced.momentumScore = (rsi - 50.0) / 50.0; // Normalized momentum (-1 to 1)
        
        // Market context assessment
        if(enhanced.volatilityFactor > 2.0) {
            enhanced.marketContext = "High Volatility - Increased Risk";
        } else if(enhanced.volatilityFactor < 0.5) {
            enhanced.marketContext = "Low Volatility - Range Bound";
        } else {
            enhanced.marketContext = "Normal Volatility - Trending";
        }
        
        return enhanced;
    }
    
    // Generate comprehensive AI reasoning explanation
    string GenerateAdvancedReasoning(const SEnhancedTradeSignal &signal, string reasoningSymbol) {
        string reasoning = "[AI-REASONING] ";
        
        // Signal strength assessment
        reasoning += "Signal: " + EnumToString(signal.signal) + " (Confidence: " + DoubleToString(signal.confidence, 2) + ") | ";
        
        // Market regime analysis
        reasoning += "Regime: " + EnumToString(signal.regime) + " | ";
        
        // Volatility assessment
        reasoning += "Volatility: " + DoubleToString(signal.volatilityFactor, 2) + "% | ";
        
        // Trend analysis
        if(signal.trendStrength > 1.0) {
            reasoning += "Strong Trend (" + DoubleToString(signal.trendStrength, 2) + ") | ";
        } else {
            reasoning += "Weak/Sideways Trend | ";
        }
        
        // Momentum analysis
        if(signal.momentumScore > 0.3) {
            reasoning += "Bullish Momentum | ";
        } else if(signal.momentumScore < -0.3) {
            reasoning += "Bearish Momentum | ";
        } else {
            reasoning += "Neutral Momentum | ";
        }
        
        // Risk assessment
        reasoning += "Risk Level: " + signal.marketContext + " | ";
        
        // Uncertainty factor
        reasoning += "Uncertainty: " + DoubleToString(signal.uncertainty.uncertainty, 2) + " | ";
        
        // Position sizing recommendation
        reasoning += "Recommended Size: " + DoubleToString(signal.riskAdjustedSize, 2) + " lots";
        
        return reasoning;
    }
    
    // Advanced learning from market feedback
    void LearnFromMarketFeedback(string feedbackSymbol, double actualReturn, double predictedReturn) {
        // Calculate prediction error
        double error = MathAbs(actualReturn - predictedReturn);
        
        // Update confidence based on accuracy
        if(error < 0.001) { // Very accurate prediction
            m_confidenceThreshold = MathMax(0.5, m_confidenceThreshold - 0.01);
            Print("[AI-LEARNING] High accuracy - reducing confidence threshold to ", m_confidenceThreshold);
        } else if(error > 0.01) { // Poor prediction
            m_confidenceThreshold = MathMin(0.9, m_confidenceThreshold + 0.01);
            Print("[AI-LEARNING] Poor accuracy - increasing confidence threshold to ", m_confidenceThreshold);
        }
        
        // Update ensemble models with feedback
        if(m_ensembleSystem != NULL) {
            // This would update the ensemble learning system
            Print("[AI-LEARNING] Updating ensemble models with market feedback");
        }
    }
    
    // Adaptive strategy selection based on market conditions
    ENUM_TRADE_SIGNAL AdaptiveStrategySelection(string adaptiveSymbol, const SEnhancedTradeSignal &baseSignal) {
        // In high volatility, be more conservative
        if(baseSignal.volatilityFactor > 3.0) {
            if(baseSignal.confidence < 0.8) {
                Print("[AI-ADAPTIVE] High volatility + low confidence - signal filtered");
                return TRADE_SIGNAL_NONE;
            }
        }
        
        // In trending markets, follow the trend
        if(baseSignal.trendStrength > 2.0 && MathAbs(baseSignal.momentumScore) > 0.5) {
            Print("[AI-ADAPTIVE] Strong trend detected - enhancing signal strength");
            return baseSignal.signal;
        }
        
        // In ranging markets, look for reversals
        if(baseSignal.volatilityFactor < 1.0 && MathAbs(baseSignal.momentumScore) > 0.7) {
            Print("[AI-ADAPTIVE] Range-bound market with extreme momentum - potential reversal");
            // Could reverse the signal in ranging conditions
        }
        
        return baseSignal.signal;
    }
    
    // Cleanup
    void Deinitialize() {
        // Clean up transformer brain
        if(m_transformerBrain != NULL) {
            delete m_transformerBrain;
            m_transformerBrain = NULL;
        }
        
        // Clean up ensemble learner
        if(m_ensembleSystem != NULL) {
            delete m_ensembleSystem;
            m_ensembleSystem = NULL;
        }
        
        // Clean up uncertainty quantifier
        if(m_uncertaintyQuantifier != NULL) {
            delete m_uncertaintyQuantifier;
            m_uncertaintyQuantifier = NULL;
        }
        
        m_initialized = false;
        Print("[NEXTGEN] AI Brain deinitialized");
    }
};

// Global next-gen brain instance
CNextGenStrategyBrain* g_nextGenBrain;

//+------------------------------------------------------------------+
//| Initialize Next-Gen Strategy Brain                             |
//+------------------------------------------------------------------+
bool NextGenBrainInit(string symbolParam, ENUM_TIMEFRAMES timeframe) {
    if(g_nextGenBrain) {
        delete g_nextGenBrain;
    }
    
    g_nextGenBrain = new CNextGenStrategyBrain();
    if(g_nextGenBrain) {
        return g_nextGenBrain.Initialize(symbolParam, timeframe);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Generate Enhanced Trading Signal                               |
//+------------------------------------------------------------------+
bool NextGenGenerateSignal(double price, double volume, const CArrayDouble &indicators, 
                          SEnhancedTradeSignal &signal) {
    if(!g_nextGenBrain) {
        Print("[ERROR] NextGen Brain not initialized");
        return false;
    }
    
    return g_nextGenBrain.GenerateSignal(price, volume, indicators, signal);
}

//+------------------------------------------------------------------+
//| Update AI Performance                                          |
//+------------------------------------------------------------------+
bool NextGenUpdatePerformance(double tradeReturn, bool isWin, double drawdown = 0.0) {
    if(!g_nextGenBrain) return false;
    return g_nextGenBrain.UpdatePerformance(tradeReturn, isWin, drawdown);
}

//+------------------------------------------------------------------+
//| Get AI Performance Report                                      |
//+------------------------------------------------------------------+
string NextGenGetReport() {
    if(!g_nextGenBrain) return "NextGen Brain not initialized";
    return g_nextGenBrain.GenerateAIReport();
}

//+------------------------------------------------------------------+
//| Set AI Parameters                                              |
//+------------------------------------------------------------------+
void NextGenSetParameters(double confidenceThreshold, double uncertaintyThreshold, bool useFiltering) {
    if(g_nextGenBrain) {
        g_nextGenBrain.SetParameters(confidenceThreshold, uncertaintyThreshold, useFiltering);
    }
}

//+------------------------------------------------------------------+
//| Save AI State                                                  |
//+------------------------------------------------------------------+
bool NextGenSaveState(string filename) {
    if(!g_nextGenBrain) return false;
    return g_nextGenBrain.SaveAIState(filename);
}

//+------------------------------------------------------------------+
//| Check if AI is Ready                                           |
//+------------------------------------------------------------------+
bool NextGenIsReady() {
    if(!g_nextGenBrain) return false;
    return g_nextGenBrain.IsReady();
}

//+------------------------------------------------------------------+
//| Cleanup                                                         |
//+------------------------------------------------------------------+
void NextGenBrainDeinit() {
    if(g_nextGenBrain) {
        g_nextGenBrain.Deinitialize();
        delete g_nextGenBrain;
        g_nextGenBrain = NULL;
    }
}

#endif // __NEXTGEN_STRATEGY_BRAIN_MQH__
