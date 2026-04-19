//+------------------------------------------------------------------+
//| Universal Transformer Service for Multi-Symbol AI               |
//| Centralized transformer with symbol-specific adaptation          |
//+------------------------------------------------------------------+
#ifndef __UNIVERSAL_TRANSFORMER_SERVICE_MQH__
#define __UNIVERSAL_TRANSFORMER_SERVICE_MQH__

#include "TransformerBrain.mqh"
#include <Arrays/ArrayObj.mqh>
#include <Arrays/ArrayString.mqh>

// Symbol classification from logs
enum ENUM_SYMBOL_CLASS {
    SYMBOL_CLASS_UNKNOWN = 0,
    SYMBOL_CLASS_SYNTHETIC_STEP,
    SYMBOL_CLASS_SYNTHETIC_JUMP, 
    SYMBOL_CLASS_SYNTHETIC_VOLATILITY,
    SYMBOL_CLASS_FOREX,
    SYMBOL_CLASS_COMMODITY,
    SYMBOL_CLASS_CRYPTO
};

//+------------------------------------------------------------------+
//| Symbol Adaptation Head - Lightweight symbol-specific processing  |
//+------------------------------------------------------------------+
class CSymbolAdaptationHead : public CObject
{
private:
    string m_symbol;
    ENUM_SYMBOL_CLASS m_symbolClass;
    double m_adaptationWeights[32];  // dModel=32 for lightweight adaptation
    double m_adaptationBias;
    double m_performanceHistory[20]; // Track adaptation performance
    int m_performanceCount;
    
    uint GetSymbolHash() const {
        uint hash = 0;
        for(int i = 0; i < StringLen(m_symbol); i++) {
            hash = hash * 31 + (uint)StringGetCharacter(m_symbol, i);
        }
        return hash;
    }
    
public:
    CSymbolAdaptationHead(const string& symbol, ENUM_SYMBOL_CLASS symbolClass) {
        m_symbol = symbol;
        m_symbolClass = symbolClass;
        m_performanceCount = 0;
        ArrayInitialize(m_performanceHistory, 0.0);
        
        // Initialize adaptation weights based on symbol class
        InitializeAdaptationWeights();
    }
    
    void InitializeAdaptationWeights() {
        uint symbolHash = GetSymbolHash();
        
        switch(m_symbolClass) {
            case SYMBOL_CLASS_SYNTHETIC_STEP:
                // Emphasize step patterns, de-emphasize fundamentals
                for(int i = 0; i < 32; i++) {
                    if(i < 16) // Volatility/jump features
                        m_adaptationWeights[i] = 1.2 + (symbolHash % 100) / 1000.0;
                    else // Fundamental features
                        m_adaptationWeights[i] = 0.7 + (symbolHash % 50) / 1000.0;
                }
                break;
                
            case SYMBOL_CLASS_SYNTHETIC_JUMP:
                // Emphasize jump magnitude and frequency
                for(int i = 0; i < 32; i++) {
                    if(i >= 8 && i < 20) // Jump-related features
                        m_adaptationWeights[i] = 1.4 + (symbolHash % 80) / 1000.0;
                    else
                        m_adaptationWeights[i] = 0.9 + (symbolHash % 100) / 1000.0;
                }
                break;
                
            case SYMBOL_CLASS_SYNTHETIC_VOLATILITY:
                // Emphasize ultra-short-term volatility
                for(int i = 0; i < 32; i++) {
                    if(i < 12) // Short-term features
                        m_adaptationWeights[i] = 1.5 + (symbolHash % 60) / 1000.0;
                    else
                        m_adaptationWeights[i] = 0.8 + (symbolHash % 80) / 1000.0;
                }
                break;
                
            case SYMBOL_CLASS_FOREX:
                // Emphasize trend and macro factors
                for(int i = 0; i < 32; i++) {
                    if(i >= 16 && i < 24) // Trend features
                        m_adaptationWeights[i] = 1.3 + (symbolHash % 70) / 1000.0;
                    else if(i >= 24) // Macro features
                        m_adaptationWeights[i] = 1.1 + (symbolHash % 90) / 1000.0;
                    else
                        m_adaptationWeights[i] = 1.0 + (symbolHash % 100) / 1000.0;
                }
                break;
                
            default:
                // Balanced weights for unknown classes
                for(int i = 0; i < 32; i++) {
                    m_adaptationWeights[i] = 1.0 + (symbolHash % 100) / 1000.0;
                }
                break;
        }
        
        m_adaptationBias = (symbolHash % 200) / 1000.0 - 0.1; // Small bias [-0.1, 0.1]
    }
    
    bool AdaptFeatures(const double& universalFeatures[], double& adaptedFeatures[]) {
        if(ArraySize(universalFeatures) < 32) {
            ArrayCopy(adaptedFeatures, universalFeatures);
            return false;
        }
        
        ArrayResize(adaptedFeatures, 32);
        
        // Apply symbol-specific weighting
        for(int i = 0; i < 32; i++) {
            adaptedFeatures[i] = universalFeatures[i] * m_adaptationWeights[i] + m_adaptationBias;
            // Clamp to reasonable range
            adaptedFeatures[i] = MathMax(-5.0, MathMin(5.0, adaptedFeatures[i]));
        }
        
        return true;
    }
    
    void UpdateFromPerformance(double performance) {
        // Simple moving average of performance
        if(m_performanceCount < 20) {
            m_performanceHistory[m_performanceCount] = performance;
            m_performanceCount++;
        } else {
            // Shift and add new performance
            for(int i = 0; i < 19; i++) {
                m_performanceHistory[i] = m_performanceHistory[i + 1];
            }
            m_performanceHistory[19] = performance;
        }
        
        // Adjust weights based on performance (simplified)
        if(m_performanceCount > 5) {
            double avgPerformance = 0.0;
            for(int i = 0; i < m_performanceCount; i++) {
                avgPerformance += m_performanceHistory[i];
            }
            avgPerformance /= m_performanceCount;
            
            // Slight weight adjustment based on performance
            if(avgPerformance > 0.6) {
                // Good performance - slightly increase weights
                for(int i = 0; i < 32; i++) {
                    m_adaptationWeights[i] *= 1.01;
                }
            } else if(avgPerformance < 0.4) {
                // Poor performance - slightly decrease weights
                for(int i = 0; i < 32; i++) {
                    m_adaptationWeights[i] *= 0.99;
                }
            }
        }
    }
    
    string GetSymbol() const { return m_symbol; }
    ENUM_SYMBOL_CLASS GetSymbolClass() const { return m_symbolClass; }
    double GetAveragePerformance() const {
        if(m_performanceCount == 0) return 0.5;
        double sum = 0.0;
        for(int i = 0; i < m_performanceCount; i++) {
            sum += m_performanceHistory[i];
        }
        return sum / m_performanceCount;
    }
};

//+------------------------------------------------------------------+
//| Cache entry for symbol features                                  |
//+------------------------------------------------------------------+
struct SSymbolFeatureCache {
    string symbol;
    datetime timestamp;
    double features[32];
    bool isValid;
    
    SSymbolFeatureCache() {
        symbol = "";
        timestamp = 0;
        ArrayInitialize(features, 0.0);
        isValid = false;
    }
};

//+------------------------------------------------------------------+
//| Universal Transformer Service - Centralized AI brain             |
//+------------------------------------------------------------------+
class CUniversalTransformerService {
private:
    CTransformerBrain* m_universalEncoder;     // Single shared transformer
    CArrayObj m_symbolAdaptationHeads;         // Per-symbol adaptation heads
    CArrayString m_registeredSymbols;          // Registered symbols
    SSymbolFeatureCache m_featureCache[20];    // Cache for recent features
    int m_cacheSize;
    datetime m_lastCacheCleanup;
    
    // Helper to classify symbols based on name patterns
    ENUM_SYMBOL_CLASS ClassifySymbol(const string& symbol) {
        string lowerSymbol = symbol;
        StringToLower(lowerSymbol);
        
        if(StringFind(lowerSymbol, "step") >= 0)
            return SYMBOL_CLASS_SYNTHETIC_STEP;
        else if(StringFind(lowerSymbol, "jump") >= 0)
            return SYMBOL_CLASS_SYNTHETIC_JUMP;
        else if(StringFind(lowerSymbol, "volatility") >= 0 || StringFind(lowerSymbol, "1s") >= 0)
            return SYMBOL_CLASS_SYNTHETIC_VOLATILITY;
        else if(StringFind(lowerSymbol, "eur") >= 0 || StringFind(lowerSymbol, "usd") >= 0 || 
                StringFind(lowerSymbol, "gbp") >= 0 || StringFind(lowerSymbol, "jpy") >= 0)
            return SYMBOL_CLASS_FOREX;
        else if(StringFind(lowerSymbol, "btc") >= 0 || StringFind(lowerSymbol, "eth") >= 0)
            return SYMBOL_CLASS_CRYPTO;
        else if(StringFind(lowerSymbol, "gold") >= 0 || StringFind(lowerSymbol, "silver") >= 0 || 
                StringFind(lowerSymbol, "oil") >= 0)
            return SYMBOL_CLASS_COMMODITY;
        else
            return SYMBOL_CLASS_UNKNOWN;
    }
    
    int FindSymbolHeadIndex(const string& symbol) {
        for(int i = 0; i < m_symbolAdaptationHeads.Total(); i++) {
            CSymbolAdaptationHead* head = m_symbolAdaptationHeads.At(i);
            if(head != NULL && head.GetSymbol() == symbol) {
                return i;
            }
        }
        return -1;
    }
    
    int FindCacheEntry(const string& symbol) {
        datetime now = TimeCurrent();
        for(int i = 0; i < m_cacheSize; i++) {
            if(m_featureCache[i].symbol == symbol && 
               m_featureCache[i].isValid &&
               now - m_featureCache[i].timestamp < 10) { // 10 second cache
                return i;
            }
        }
        return -1;
    }
    
    void CleanupCache() {
        datetime now = TimeCurrent();
        if(now - m_lastCacheCleanup < 60) return; // Cleanup every minute
        
        for(int i = m_cacheSize - 1; i >= 0; i--) {
            if(now - m_featureCache[i].timestamp >= 30) { // Expire after 30 seconds
                // Remove expired entry
                for(int j = i; j < m_cacheSize - 1; j++) {
                    m_featureCache[j] = m_featureCache[j + 1];
                }
                m_cacheSize--;
            }
        }
        m_lastCacheCleanup = now;
    }

    bool EnsureServiceInitialized() {
        if(m_universalEncoder != NULL)
            return true;

        return Initialize();
    }
    
public:
    CUniversalTransformerService() {
        m_universalEncoder = NULL;
        m_cacheSize = 0;
        m_lastCacheCleanup = 0;
    }
    
    ~CUniversalTransformerService() {
        if(m_universalEncoder != NULL) {
            delete m_universalEncoder;
            m_universalEncoder = NULL;
        }
        m_symbolAdaptationHeads.Clear();
        m_registeredSymbols.Clear();
    }
    
    bool Initialize() {
        if(m_universalEncoder != NULL)
            return true;

        Print("[UNIVERSAL-TRANSFORMER] Initializing centralized AI service...");
        
        // Create single universal encoder with optimized parameters
        // Using dModel=64, heads=4, layers=2, dFF=128, maxSeqLen=100
        m_universalEncoder = new CTransformerBrain(64, 4, 2, 128, 100, 0.001);
        
        if(m_universalEncoder == NULL) {
            Print("[UNIVERSAL-TRANSFORMER] ERROR: Failed to create universal encoder");
            return false;
        }
        
        if(!m_universalEncoder.IsWarmedUp(0)) {
            Print("[UNIVERSAL-TRANSFORMER] Universal encoder created successfully");
        }
        
        m_cacheSize = 0;
        m_lastCacheCleanup = TimeCurrent();
        
        Print("[UNIVERSAL-TRANSFORMER] Service initialized with single transformer (64,4,2,128,100)");
        return true;
    }
    
    bool RegisterSymbol(const string& symbol) {
        if(symbol == "") {
            return false;
        }

        if(!EnsureServiceInitialized()) {
            PrintFormat("[UNIVERSAL-TRANSFORMER] ERROR: Service initialization failed while registering %s", symbol);
            return false;
        }

        if(FindSymbolHeadIndex(symbol) >= 0)
            return true;
        
        ENUM_SYMBOL_CLASS symbolClass = ClassifySymbol(symbol);
        
        CSymbolAdaptationHead* head = new CSymbolAdaptationHead(symbol, symbolClass);
        if(head == NULL) {
            return false;
        }
        
        if(!m_symbolAdaptationHeads.Add(head)) {
            delete head;
            return false;
        }
        
        m_registeredSymbols.Add(symbol);
        
        PrintFormat("[UNIVERSAL-TRANSFORMER] Registered symbol: %s (class: %d)", 
                   symbol, symbolClass);
        return true;
    }
    
    bool IsSymbolRegistered(const string& symbol) {
        return FindSymbolHeadIndex(symbol) >= 0;
    }
    
    bool GetSymbolFeatures(const string& symbol,
                          const double& marketData[],
                          int seqLen,
                          double& symbolFeatures[]) {
        if(symbol == "" || seqLen <= 0) {
            return false;
        }

        if(!EnsureServiceInitialized()) {
            return false;
        }

        if(!IsSymbolRegistered(symbol) && !RegisterSymbol(symbol))
            return false;
        
        // Check cache first
        int cacheIndex = FindCacheEntry(symbol);
        if(cacheIndex >= 0) {
            ArrayCopy(symbolFeatures, m_featureCache[cacheIndex].features);
            return true;
        }
        
        // Step 1: Universal encoding
        double universalFeatures[];
        if(!m_universalEncoder.Forward(marketData, seqLen, universalFeatures)) {
            static datetime s_lastEncoderFailLog = 0;
            datetime now = TimeCurrent();
            if(now - s_lastEncoderFailLog >= 120) {
                PrintFormat("[UNIVERSAL-TRANSFORMER] DIAG: Universal encoding failed for %s | inputSize=%d | seqLen=%d | warmedUp=%s",
                            symbol, ArraySize(marketData), seqLen,
                            m_universalEncoder.IsWarmedUp(0) ? "yes" : "no");
                s_lastEncoderFailLog = now;
            }
            return false;
        }
        
        // Step 2: Symbol-specific adaptation
        int headIndex = FindSymbolHeadIndex(symbol);
        if(headIndex < 0) {
            PrintFormat("[UNIVERSAL-TRANSFORMER] ERROR: Symbol %s not registered", symbol);
            ArrayCopy(symbolFeatures, universalFeatures);
            return false;
        }
        
        CSymbolAdaptationHead* head = m_symbolAdaptationHeads.At(headIndex);
        if(head == NULL) {
            ArrayCopy(symbolFeatures, universalFeatures);
            return false;
        }
        
        double adaptedFeatures[];
        if(!head.AdaptFeatures(universalFeatures, adaptedFeatures)) {
            ArrayCopy(symbolFeatures, universalFeatures);
            return false;
        }
        
        ArrayCopy(symbolFeatures, adaptedFeatures);
        
        // Cache the result
        if(m_cacheSize < 20) {
            m_featureCache[m_cacheSize].symbol = symbol;
            m_featureCache[m_cacheSize].timestamp = TimeCurrent();
            ArrayCopy(m_featureCache[m_cacheSize].features, symbolFeatures);
            m_featureCache[m_cacheSize].isValid = true;
            m_cacheSize++;
        } else {
            // Replace oldest entry
            int oldestIndex = 0;
            datetime oldestTime = m_featureCache[0].timestamp;
            for(int i = 1; i < 20; i++) {
                if(m_featureCache[i].timestamp < oldestTime) {
                    oldestTime = m_featureCache[i].timestamp;
                    oldestIndex = i;
                }
            }
            
            m_featureCache[oldestIndex].symbol = symbol;
            m_featureCache[oldestIndex].timestamp = TimeCurrent();
            ArrayCopy(m_featureCache[oldestIndex].features, symbolFeatures);
            m_featureCache[oldestIndex].isValid = true;
        }
        
        CleanupCache();
        
        return true;
    }
    
    bool UpdateSymbolPerformance(const string& symbol, double performance) {
        int headIndex = FindSymbolHeadIndex(symbol);
        if(headIndex < 0) return false;
        
        CSymbolAdaptationHead* head = m_symbolAdaptationHeads.At(headIndex);
        if(head == NULL) return false;
        
        head.UpdateFromPerformance(performance);
        return true;
    }
    
    double GetSymbolPerformance(const string& symbol) {
        int headIndex = FindSymbolHeadIndex(symbol);
        if(headIndex < 0) return 0.5;
        
        CSymbolAdaptationHead* head = m_symbolAdaptationHeads.At(headIndex);
        if(head == NULL) return 0.5;
        
        return head.GetAveragePerformance();
    }
    
    int GetRegisteredSymbolCount() const {
        return m_symbolAdaptationHeads.Total();
    }
    
    string GetRegisteredSymbol(int index) const {
        if(index < 0 || index >= m_registeredSymbols.Total()) return "";
        return m_registeredSymbols.At(index);
    }
    
    bool IsWarmedUp(int minSteps = 100) const {
        if(m_universalEncoder == NULL) return false;
        return m_universalEncoder.IsWarmedUp(minSteps);
    }
    
    int GetUniversalEncoderTrainingSteps() const {
        if(m_universalEncoder == NULL) return 0;
        // This would need to be added to CTransformerBrain
        return 0; // Placeholder
    }
    
    void GetServiceStatus(string& status) {
        status = "[UNIVERSAL-TRANSFORMER] ";
        status += "Symbols: " + IntegerToString(GetRegisteredSymbolCount()) + " | ";
        status += "Cache: " + IntegerToString(m_cacheSize) + "/20 | ";
        status += m_universalEncoder != NULL ? "Encoder: READY" : "Encoder: ERROR";
    }
};

// Global service instance
CUniversalTransformerService g_universalTransformerService;

#endif // __UNIVERSAL_TRANSFORMER_SERVICE_MQH__
