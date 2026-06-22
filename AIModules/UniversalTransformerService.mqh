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
//| ITransformerEncoder Interface - Allows swapping implementations   |
//+------------------------------------------------------------------+
interface ITransformerEncoder {
    bool GetPredictions(const double &inputSequence[], const int seqLen, double &outputs[]);
    bool SaveHeadState(const string &path);
    bool LoadHeadState(const string &path);
    int GetDModel() const;
    int GetNumHeads() const;
    int GetNumLayers() const;
};

class CTransformerBrainAsEncoder : public ITransformerEncoder {
private:
    CTransformerBrain* m_transformer;
public:
    CTransformerBrainAsEncoder(CTransformerBrain* transformer) { m_transformer = transformer; }
    bool GetPredictions(const double &inputSequence[], const int seqLen, double &outputs[]) {
        return m_transformer.GetPredictions(inputSequence, seqLen, outputs);
    }
    bool SaveHeadState(const string &path) { return m_transformer.SaveHeadState(path); }
    bool LoadHeadState(const string &path) { return m_transformer.LoadHeadState(path); }
    int GetDModel() const { return m_transformer.GetDModel(); }
    int GetNumHeads() const { return m_transformer.GetNumHeads(); }
    int GetNumLayers() const { return m_transformer.GetNumLayers(); }
};

//+------------------------------------------------------------------+
//| Symbol Adaptation Head - Lightweight symbol-specific processing  |
//+------------------------------------------------------------------+
class CSymbolEmbedding
{
private:
    double m_embedding[32];  // Learnable symbol embedding
    uint m_symbolHash;
    int m_updateCount;
    
    uint GetSymbolHash(const string &symbol) const
    {
        uint hash = 0;
        for(int i = 0; i < StringLen(symbol); i++)
        {
            hash = hash * 31 + (uint)StringGetCharacter(symbol, i);
        }
        return hash;
    }
    
public:
    CSymbolEmbedding(const string &symbol)
    {
        m_symbolHash = GetSymbolHash(symbol);
        m_updateCount = 0;
        InitializeEmbedding(symbol);
    }
    
    void InitializeEmbedding(const string &symbol)
    {
        uint hash = m_symbolHash;
        
        // Initialize with class-dependent seed based on symbol characteristics
        // This creates deterministic but varied embeddings per symbol
        for(int i = 0; i < 32; i++)
        {
            hash = hash * 1664525 + 1013904223;
            m_embedding[i] = ((double)(hash % 1000) / 500.0) - 1.0;  // Range [-1, 1]
            m_embedding[i] *= 0.1;  // Scale down for gentle adaptation
        }
        
        // First few dimensions encode symbol class characteristics
        double classEncoding[32];
        ClassifySymbol(symbol, classEncoding);
        for(int i = 0; i < 8; i++)
            m_embedding[i] = classEncoding[i];
    }
    
    void ClassifySymbol(const string &symbol, double &encoding[])
    {
        ArrayResize(encoding, 32);
        ArrayInitialize(encoding, 0.0);
        
        bool isSynthetic = (StringFind(symbol, "RANDOM") >= 0 || 
                           StringFind(symbol, "SYNTH") >= 0 ||
                           StringFind(symbol, "_IND") >= 0);
        bool isForex = (StringFind(symbol, "EUR") >= 0 || 
                       StringFind(symbol, "GBP") >= 0 ||
                       StringFind(symbol, "USD") >= 0 ||
                       StringFind(symbol, "JPY") >= 0 ||
                       StringFind(symbol, "AUD") >= 0);
        bool isCrypto = (StringFind(symbol, "BTC") >= 0 || 
                        StringFind(symbol, "ETH") >= 0 ||
                        StringFind(symbol, "Crypto") >= 0);
        
        int classId = 0;
        if(isSynthetic) classId = 1;
        else if(isForex) classId = 2;
        else if(isCrypto) classId = 3;
        
        // One-hot class encoding
        if(classId == 1) { encoding[0] = 1.0; }
        else if(classId == 2) { encoding[1] = 1.0; }
        else if(classId == 3) { encoding[2] = 1.0; }
        
        // Additional continuous features
        encoding[3] = (StringLen(symbol) > 6) ? 1.0 : 0.0;  // Long symbol name
        encoding[4] = 0.5;  // Default
    }
    
    void UpdateEmbedding(const double &predictionError, const double learningRate = 0.001)
    {
        // Hebbian-style update: increase embedding when predictions are correct
        m_updateCount++;
        
        if(predictionError < 0.3)
        {
            // Good prediction - reinforce current embedding
            for(int i = 0; i < 32; i++)
            {
                m_embedding[i] += learningRate * m_embedding[i] * (1.0 - predictionError);
                m_embedding[i] = MathMax(-1.0, MathMin(1.0, m_embedding[i]));
            }
        }
        else if(predictionError > 0.7)
        {
            // Poor prediction - decay towards zero
            for(int i = 0; i < 32; i++)
            {
                m_embedding[i] *= 0.99;
            }
        }
    }
    
    void ApplyToFeatures(const double &inputFeatures[], double &outputFeatures[], const int featureSize)
    {
        if(ArraySize(inputFeatures) < featureSize)
            return;
            
        ArrayResize(outputFeatures, featureSize);
        
        // Blend input features with symbol embedding
        for(int i = 0; i < featureSize && i < 32; i++)
        {
            // Additive combination with small weight for embedding
            outputFeatures[i] = inputFeatures[i] + 0.1 * m_embedding[i];
            outputFeatures[i] = MathMax(-10.0, MathMin(10.0, outputFeatures[i]));
        }
        
        // Copy remaining features directly
        for(int i = 32; i < featureSize && i < ArraySize(inputFeatures); i++)
        {
            outputFeatures[i] = inputFeatures[i];
        }
    }
    
    int GetUpdateCount() const { return m_updateCount; }
    void GetEmbedding(double &embedding[]) const
    {
        ArrayResize(embedding, 32);
        ArrayCopy(embedding, m_embedding);
    }
};

class CSymbolAdaptationHead : public CObject
{
private:
    string m_symbol;
    ENUM_SYMBOL_CLASS m_symbolClass;
    double m_adaptationWeights[32];  // dModel=32 for lightweight adaptation
    double m_adaptationBias;
    double m_performanceHistory[20]; // Track adaptation performance
    int m_performanceCount;
    CSymbolEmbedding* m_embedding;  // Learnable symbol embedding
    
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
        m_embedding = new CSymbolEmbedding(symbol);
        ArrayInitialize(m_performanceHistory, 0.0);
        
        InitializeAdaptationWeights();
    }
    
    ~CSymbolAdaptationHead()
    {
        if(m_embedding != NULL)
        {
            delete m_embedding;
            m_embedding = NULL;
        }
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
        
        double embeddingModified[];
        if(m_embedding != NULL)
            m_embedding.ApplyToFeatures(universalFeatures, embeddingModified, 32);
        
        for(int i = 0; i < 32; i++) {
            double baseFeature = (ArraySize(embeddingModified) >= 32) ? embeddingModified[i] : universalFeatures[i];
            adaptedFeatures[i] = baseFeature * m_adaptationWeights[i] + m_adaptationBias;
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
        
        // Update symbol embedding based on performance
        if(m_embedding != NULL)
        {
            double perfValue = 1.0 - performance;
            m_embedding.UpdateEmbedding(perfValue);
        }
        
        // Adjust weights based on performance (simplified)
        if(m_performanceCount > 5) {
            double avgPerformance = 0.0;
            for(int i = 0; i < m_performanceCount; i++) {
                avgPerformance += m_performanceHistory[i];
            }
            avgPerformance /= m_performanceCount;
            
            // Slight weight adjustment based on performance (clamped to prevent drift)
            if(avgPerformance > 0.6) {
                for(int i = 0; i < 32; i++) {
                    m_adaptationWeights[i] = MathMin(10.0, m_adaptationWeights[i] * 1.01);
                }
            } else if(avgPerformance < 0.4) {
                for(int i = 0; i < 32; i++) {
                    m_adaptationWeights[i] = MathMax(0.01, m_adaptationWeights[i] * 0.99);
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
    ITransformerEncoder* m_encoder;             // Interface for encoder implementation
    bool m_ownsEncoder;                         // Track if service owns encoder
    CTransformerBrain* m_universalEncoder;      // Backward compat - legacy direct access
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
        m_encoder = NULL;
        m_ownsEncoder = false;
        m_universalEncoder = NULL;
        m_cacheSize = 0;
        m_lastCacheCleanup = 0;
    }
    
    ~CUniversalTransformerService() {
        if(m_ownsEncoder && m_encoder != NULL) {
            delete m_encoder;
            m_encoder = NULL;
        }
        if(m_universalEncoder != NULL) {
            delete m_universalEncoder;
            m_universalEncoder = NULL;
        }
        for(int i = m_symbolAdaptationHeads.Total() - 1; i >= 0; i--)
        {
            CSymbolAdaptationHead* head = m_symbolAdaptationHeads.At(i);
            if(head != NULL) delete head;
        }
        m_symbolAdaptationHeads.Clear();
        m_registeredSymbols.Clear();
    }
    
    void SetEncoder(ITransformerEncoder* encoder, const bool takeOwnership = false) {
        if(m_ownsEncoder && m_encoder != NULL)
            delete m_encoder;
        m_encoder = encoder;
        m_ownsEncoder = takeOwnership;
    }
    
    ITransformerEncoder* GetEncoder() const { return m_encoder; }
    
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
        
        if(m_universalEncoder.IsWarmedUp(0)) {
            Print("[UNIVERSAL-TRANSFORMER] Universal encoder ready with existing weights");
        } else {
            Print("[UNIVERSAL-TRANSFORMER] Universal encoder created (cold start — no pre-trained weights)");
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
        return m_universalEncoder.GetTrainingSteps();
    }
    
    void GetServiceStatus(string& status) {
        status = "[UNIVERSAL-TRANSFORMER] ";
        status += "Symbols: " + IntegerToString(GetRegisteredSymbolCount()) + " | ";
        status += "Cache: " + IntegerToString(m_cacheSize) + "/20 | ";
        status += m_universalEncoder != NULL ? "Encoder: READY" : "Encoder: ERROR";
    }
};

// Global service instance
// SAFETY: In MT5, each chart/EA has its own program memory space — globals are
// per-chart, not cross-chart. Per-symbol state is keyed internally (registered
// symbols, feature cache, embeddings). Multiple charts with this EA each get
// their own independent service instance.
CUniversalTransformerService g_universalTransformerService;

#endif // __UNIVERSAL_TRANSFORMER_SERVICE_MQH__
