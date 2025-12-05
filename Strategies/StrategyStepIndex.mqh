//+------------------------------------------------------------------+
//| Step Index Strategy Implementation                                |
//| Specialized strategy for Step Index level-break trading          |
//+------------------------------------------------------------------+
#property strict

#ifndef __STRATEGY_STEP_INDEX_MQH__
#define __STRATEGY_STEP_INDEX_MQH__

#include "../Core/StrategyBase.mqh"
#include "../Core/StepIndexLevelBreaker.mqh"
#include "../Core/ErrorHandling.mqh"
#include "../Utilities/Utilities.mqh"

// Forward declarations
class CStepIndexLevelBreaker;
class CEnhancedErrorHandler;
class CUtilities;

// Error code constants
#define STRATEGY_ERR_INVALID_PARAMETER 4001
#define STRATEGY_ERR_POINTER_INVALID 4002

class CStrategyStepIndex : public CStrategyBase {
private:
    CStepIndexLevelBreaker* m_levelBreaker;
    // m_errorHandler inherited from CStrategyBase
    CUtilities* m_utilities;
    
    // Strategy parameters
    double m_minConfidence;
    double m_riskPerTrade;
    bool m_useAdvancedEntry;
    bool m_useDynamicManagement;
    
    // Helper methods
    double GetStepSize(const string symbolParam) {
        // Default step size, should be overridden based on symbol
        if(StringFind(symbolParam, "Volatility") >= 0) return 50.0;
        if(StringFind(symbolParam, "Boom") >= 0 || StringFind(symbolParam, "Crash") >= 0) return 100.0;
        return 25.0; // Default step size
    }
    
    int GetStepFrequency(const string symbolParam) {
        // Default step frequency in seconds
        if(StringFind(symbolParam, "Volatility") >= 0) return 300;  // 5 minutes
        if(StringFind(symbolParam, "Boom") >= 0 || StringFind(symbolParam, "Crash") >= 0) return 60; // 1 minute
        return 60; // Default to 1 minute
    }
    
    bool IsStepIndex(const string symbolParam) {
        if (symbolParam == "") return false;
        
        string symbolUpper = symbolParam;
        StringToUpper(symbolUpper);
        
        if(StringFind(symbolUpper, "STEP") >= 0 || StringFind(symbolUpper, "STP") >= 0) return true;

        const string stepIndices[] = {
            "Volatility 50 Index", "Volatility 75 Index", "Volatility 100 Index",
            "Boom 1000 Index", "Crash 1000 Index"
        };
        
        for(int i = 0; i < ArraySize(stepIndices); i++) {
            if(symbolParam == stepIndices[i]) return true;
        }
        return false;
    }
    
public:
    CStrategyStepIndex(CStepIndexLevelBreaker* levelBreakerParam, CEnhancedErrorHandler* errHandler, CUtilities* utils) :
        CStrategyBase("StepIndex", 0),
        m_levelBreaker(levelBreakerParam),
        // m_errorHandler = errHandler; // Assigned in body
        m_utilities(utils),
        m_minConfidence(0.65),
        m_riskPerTrade(0.02),
        m_useAdvancedEntry(true),
        m_useDynamicManagement(true)
    {
    }
    
    // Destructor - cleanup resources
    virtual ~CStrategyStepIndex() {
        Deinit();
    }
    
    //--- IStrategy implementation ---
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;
            
        if(CheckPointer(m_levelBreaker) == POINTER_INVALID) {
            Print("StrategyStepIndex: Level breaker not initialized");
            return false;
        }
        
        // Initialize step index level detection
        double stepSize = GetStepSize(m_symbol);
        int stepFreq = GetStepFrequency(m_symbol);
        
        bool initResult = m_levelBreaker.InitializeStepIndex(m_symbol, stepSize, stepFreq);
        if(!initResult) {
            Print("StrategyStepIndex: Failed to initialize step index for ", m_symbol);
            return false;
        }
        
        Print("StrategyStepIndex: Initialized step index strategy for ", m_symbol,
            " (Step Size: ", DoubleToString(stepSize, 2), ")");
        
        return true;
    }
    
    virtual void Deinit() override {
        // Cleanup resources
        if(CheckPointer(m_levelBreaker) != POINTER_INVALID) {
            delete m_levelBreaker;
            m_levelBreaker = NULL;
        }
        CStrategyBase::Deinit();
    }
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override {
        if(!IsEnabled() || !m_is_initialized || CheckPointer(m_levelBreaker) == POINTER_INVALID) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        
        // Get signal from level breaker - simplified approach
        confidence = 0.0;
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        
        if (m_levelBreaker != NULL && CheckPointer(m_levelBreaker) != POINTER_INVALID) {
            // Placeholder logic to demonstrate signal generation
            // Replace with actual logic from level breaker
            // signal = m_levelBreaker->GetSignal(confidence);
            confidence = 0.0; 
            signal = TRADE_SIGNAL_NONE;
        }
        
        if(signal != TRADE_SIGNAL_NONE && confidence >= m_minConfidence) {
            m_lastSignalTime = TimeCurrent();
            m_totalSignals++;
        } else {
            signal = TRADE_SIGNAL_NONE;
            confidence = 0.0;
        }
        
        return signal;
    }
    
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {
        // Update internal state on new bar
        if(CheckPointer(m_levelBreaker) != POINTER_INVALID) {
            // Placeholder for level detection
            // m_levelBreaker->DetectStepLevels(m_symbol);
        }
    }
    
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_TYPE_STEP_INDEX; }
    
    // Additional methods for step index specific functionality
    bool UpdateMarketRegime(ENUM_MARKET_REGIME regime) {
        if(CheckPointer(m_levelBreaker) != POINTER_INVALID) return true;
        return false;
    }
    
    bool UpdateCorrelationMatrix() {
        if(CheckPointer(m_levelBreaker) != POINTER_INVALID) return true;
        return false;
    }
    
    // Getters and Setters
    void SetMinConfidence(double minConfidence) { m_minConfidence = MathMax(0.0, MathMin(1.0, minConfidence)); }
    double GetMinConfidence() const { return m_minConfidence; }
    
    void SetRiskPerTrade(double riskPerTrade) { m_riskPerTrade = MathMax(0.001, MathMin(0.1, riskPerTrade)); }
    double GetRiskPerTrade() const { return m_riskPerTrade; }
    
    void SetUseAdvancedEntry(bool useAdvancedEntry) { m_useAdvancedEntry = useAdvancedEntry; }
    bool GetUseAdvancedEntry() const { return m_useAdvancedEntry; }
    
    void SetUseDynamicManagement(bool useDynamicManagement) { m_useDynamicManagement = useDynamicManagement; }
    bool GetUseDynamicManagement() const { return m_useDynamicManagement; }
};

#endif // __STRATEGY_STEP_INDEX_MQH__