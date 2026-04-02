//+------------------------------------------------------------------+
//| Next-Generation Strategy Brain Integration                      |
//| Replaces old StrategyBrain with modern AI ensemble system      |
//+------------------------------------------------------------------+
#ifndef __NEXTGEN_STRATEGY_BRAIN_MQH__
#define __NEXTGEN_STRATEGY_BRAIN_MQH__

#include <Arrays\ArrayDouble.mqh>
#include <Math\Stat\Math.mqh>
#include "TransformerBrain.mqh"
#include "UncertaintyQuantifier.mqh"
#include "../Core/Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Market Data Processor for AI Models                            |
//+------------------------------------------------------------------+
class CMarketDataProcessor {
private:
    double m_priceData[];
    double m_volumeData[];
    double m_indicatorData[];
    int m_maxSequenceLength;
    int m_head;
    int m_count;
    bool m_isFull;

    enum { INDICATOR_COUNT = 10 };

    int PhysicalIndex(const int logicalIndex) const
    {
        if(!m_isFull)
            return logicalIndex;

        return (m_head - m_count + logicalIndex + m_maxSequenceLength) % m_maxSequenceLength;
    }
    
public:
    CMarketDataProcessor(int maxSeqLen = 100) {
        m_maxSequenceLength = maxSeqLen;
        m_head = 0;
        m_count = 0;
        m_isFull = false;
        ArrayResize(m_priceData, maxSeqLen);
        ArrayResize(m_volumeData, maxSeqLen);
        ArrayResize(m_indicatorData, maxSeqLen * INDICATOR_COUNT);
        ArrayInitialize(m_priceData, 0.0);
        ArrayInitialize(m_volumeData, 0.0);
        ArrayInitialize(m_indicatorData, 0.0);
    }
    
    // Add market data point
    bool AddDataPoint(double price, double volume, const double &indicators[]) {
        int writeIndex = m_head;
        m_priceData[writeIndex] = price;
        m_volumeData[writeIndex] = volume;

        int indicatorBase = writeIndex * INDICATOR_COUNT;
        int copyCount = MathMin(ArraySize(indicators), INDICATOR_COUNT);
        for(int i = 0; i < INDICATOR_COUNT; i++)
            m_indicatorData[indicatorBase + i] = (i < copyCount) ? indicators[i] : 0.0;

        m_head = (m_head + 1) % m_maxSequenceLength;
        if(m_count < m_maxSequenceLength)
            m_count++;
        if(m_count == m_maxSequenceLength)
            m_isFull = true;

        return true;
    }
    
    // Prepare data for AI models with proper normalization
    bool PrepareModelInput(double &modelInput[], int &sequenceLength) {
        sequenceLength = m_count;
        if(sequenceLength < 10) return false; // Need minimum data
        
        int featuresPerStep = 2 + INDICATOR_COUNT;
        ArrayResize(modelInput, sequenceLength * featuresPerStep);
        
        // Calculate price statistics
        double priceMean = 0.0, priceStd = 0.0;
        for(int i = 0; i < sequenceLength; i++)
        {
            int physicalIndex = PhysicalIndex(i);
            priceMean += m_priceData[physicalIndex];
        }
        priceMean /= sequenceLength;
        
        for(int i = 0; i < sequenceLength; i++) {
            int physicalIndex = PhysicalIndex(i);
            double diff = m_priceData[physicalIndex] - priceMean;
            priceStd += diff * diff;
        }
        priceStd = MathSqrt(priceStd / sequenceLength + 1e-9);
        
        // Calculate volume statistics
        double volumeMean = 0.0, volumeStd = 0.0;
        for(int i = 0; i < sequenceLength; i++)
        {
            int physicalIndex = PhysicalIndex(i);
            volumeMean += m_volumeData[physicalIndex];
        }
        volumeMean /= sequenceLength;
        
        for(int i = 0; i < sequenceLength; i++) {
            int physicalIndex = PhysicalIndex(i);
            double diff = m_volumeData[physicalIndex] - volumeMean;
            volumeStd += diff * diff;
        }
        volumeStd = MathSqrt(volumeStd / sequenceLength + 1e-9);
        
        // Normalize and fill input
        for(int i = 0; i < sequenceLength; i++) {
            int physicalIndex = PhysicalIndex(i);
            int baseIdx = i * featuresPerStep;
            
            // Price (Z-score)
            modelInput[baseIdx] = (m_priceData[physicalIndex] - priceMean) / priceStd;
            
            // Volume (Z-score clamped)
            double normVol = (m_volumeData[physicalIndex] - volumeMean) / volumeStd;
            modelInput[baseIdx + 1] = MathMax(-3.0, MathMin(3.0, normVol));
            
            // Indicators
            int indicatorBase = physicalIndex * INDICATOR_COUNT;
            for(int j = 0; j < INDICATOR_COUNT; j++) {
                double val = m_indicatorData[indicatorBase + j];
                modelInput[baseIdx + 2 + j] = MathMax(-10.0, MathMin(10.0, val));
            }
        }
        
        return true;
    }

    int GetCount() const { return m_count; }
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
    
    datetime m_lastDataBarTime;
    datetime m_cacheBarTime;
    bool m_hasCachedSignal;
    SEnhancedTradeSignal m_cachedSignal;

    datetime GetCurrentBarTime() const
    {
        if(m_symbol == "")
            return 0;
        return iTime(m_symbol, m_timeframe, 0);
    }

    bool NeedsNewInference(const datetime currentBarTime) const
    {
        return (!m_hasCachedSignal || currentBarTime <= 0 || currentBarTime != m_cacheBarTime);
    }

    void UpdateSignalCache(const datetime currentBarTime, const SEnhancedTradeSignal &signal)
    {
        m_cachedSignal = signal;
        m_cacheBarTime = currentBarTime;
        m_hasCachedSignal = true;
    }
    
public:
    CNextGenStrategyBrain() {
        m_dataProcessor = new CMarketDataProcessor(100);
        m_initialized = false;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_transformerBrain = NULL;
        m_uncertaintyQuantifier = NULL;
        m_totalReturn = 0.0;
        m_totalTrades = 0;
        m_winningTrades = 0;
        m_lastUpdate = 0;
        
        m_confidenceThreshold = 0.6;
        m_uncertaintyThreshold = 0.4;
        m_useUncertaintyFiltering = true;

        m_lastDataBarTime = 0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
    }
    
    ~CNextGenStrategyBrain() {
        if(CheckPointer(m_dataProcessor) == POINTER_DYNAMIC) delete m_dataProcessor;
        if(CheckPointer(m_transformerBrain) == POINTER_DYNAMIC) delete m_transformerBrain;
        if(CheckPointer(m_uncertaintyQuantifier) == POINTER_DYNAMIC) delete m_uncertaintyQuantifier;
    }
    // Initialize the AI brain system
    bool Initialize(string brainSymbol, ENUM_TIMEFRAMES timeframe) {
        m_symbol = brainSymbol;
        m_timeframe = timeframe;
        
        // Initialize Transformer Brain (Local Model)
        if(m_transformerBrain == NULL) {
            m_transformerBrain = new CTransformerBrain(64, 4, 2, 128, 50); // Right-sized local model for MT5 runtime
            if(!m_transformerBrain) return false;
        }
        
        // Initialize Uncertainty
        if(m_uncertaintyQuantifier == NULL) {
            m_uncertaintyQuantifier = new CUncertaintyQuantifier(100, 0.95);
            if(!m_uncertaintyQuantifier) return false;
        }
        
        m_lastDataBarTime = 0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
        m_initialized = true;
        Print("[NEXTGEN] AI Strategy Brain initialized for ", brainSymbol);
        return true;
    }
    
    // Process market data and generate enhanced trading signal
    bool GenerateSignal(double price, double volume, const double &indicators[], 
                       SEnhancedTradeSignal &signal) {
        if(!m_initialized) return false;

        datetime currentBarTime = GetCurrentBarTime();
        if(currentBarTime != m_lastDataBarTime)
        {
            m_dataProcessor.AddDataPoint(price, volume, indicators);
            m_lastDataBarTime = currentBarTime;
        }

        if(!NeedsNewInference(currentBarTime))
        {
            signal = m_cachedSignal;
            return true;
        }

        double modelInput[];
        int sequenceLength;
        if(!m_dataProcessor.PrepareModelInput(modelInput, sequenceLength)) {
            return false;
        }

        double predictions[];
        if(!m_transformerBrain.GetPredictions(modelInput, sequenceLength, predictions) || ArraySize(predictions) != 3)
        {
            signal.signal = TRADE_SIGNAL_NONE;
            signal.reasoning = "AI Failure";
            return false;
        }

        double noneProb = predictions[0];
        double buyProb = predictions[1];
        double sellProb = predictions[2];

        signal.buyProbability = buyProb;
        signal.sellProbability = sellProb;
        signal.timestamp = TimeCurrent();
        signal.reasoning = "Local Transformer";
        signal.signal = TRADE_SIGNAL_NONE;
        signal.confidence = noneProb;

        if(buyProb > m_confidenceThreshold && buyProb > sellProb && buyProb > noneProb)
        {
            signal.signal = TRADE_SIGNAL_BUY;
            signal.confidence = buyProb;
        }
        else if(sellProb > m_confidenceThreshold && sellProb > buyProb && sellProb > noneProb)
        {
            signal.signal = TRADE_SIGNAL_SELL;
            signal.confidence = sellProb;
        }

        double entropy = -(buyProb * MathLog(buyProb + 1e-9) +
                           sellProb * MathLog(sellProb + 1e-9) +
                           noneProb * MathLog(noneProb + 1e-9));
        signal.uncertainty.uncertainty = entropy / 1.0986;
        signal.riskAdjustedSize = 1.0 * (1.0 - signal.uncertainty.uncertainty);

        // Apply filters
        if(signal.confidence < m_confidenceThreshold) {
            signal.signal = TRADE_SIGNAL_NONE;
            signal.reasoning += " [Low Confidence]";
        }

        UpdateSignalCache(currentBarTime, signal);
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

    // Get training experience count (online learning does not use fixed epochs)
    int GetEpochCount() {
        return m_totalTrades;
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

    // --- Dashboard Getters ---
    double GetCurrentUncertainty()
    {
        if(m_uncertaintyQuantifier == NULL) return 1.0;
        // Return latest uncertainty if available or estimated based on history
        double avgUnc, maxUnc, avgErr;
        int samples;
        m_uncertaintyQuantifier.GetUncertaintyStats(avgUnc, maxUnc, avgErr, samples);
        return avgUnc;
    }

    bool IsInitialized() const
    {
        return m_initialized;
    }
    
    string GetRuntimeMode() const
    {
        return "LOCAL_TRANSFORMER";
    }

    CTransformerBrain* GetTransformerBrain() const
    {
        return m_transformerBrain;
    }
};

#endif // __NEXTGEN_STRATEGY_BRAIN_MQH__
