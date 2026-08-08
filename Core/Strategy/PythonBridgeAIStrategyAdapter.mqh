//+------------------------------------------------------------------+
//| PythonBridgeAIStrategyAdapter.mqh                                |
//| Symbol-scoped Python Bridge AI strategy adapter                  |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_STRATEGY_PYTHON_BRIDGE_AI_STRATEGY_ADAPTER_MQH
#define CORE_STRATEGY_PYTHON_BRIDGE_AI_STRATEGY_ADAPTER_MQH

#include "../../Interfaces/IStrategy.mqh"
#include "../../Interfaces/IAIStrategy.mqh"
#include "../Utils/PythonBridge.mqh"
#include "../AI/AIFeatureVectorBuilder.mqh"
#include "../AI/IFeaturePipeline.mqh"
#include "../AI/FeaturePipelineONNX.mqh"

class CPythonBridgeAIStrategyAdapter : public IAIStrategy
{
private:
    CPythonBridge*    m_pythonBridge;
    string            m_symbol;
    ENUM_TIMEFRAMES   m_timeframe;
    bool              m_enabled;
    double            m_weight;
    datetime          m_lastSignalTime;
    datetime          m_cacheBarTime;
    datetime          m_cacheRefreshTime;
    bool              m_hasCachedSignal;
    ENUM_TRADE_SIGNAL m_cachedSignal;
    double            m_cachedConfidence;
    string            m_lastDecisionReasonTag;
    double            m_minConfidence;
    ulong             m_voteCount;
    ulong             m_buyVotes;
    ulong             m_sellVotes;
    ulong             m_noneVotes;
    datetime          m_lastVoteLogTime;
    int               m_barCounter;
    int               m_familyId;
    string            m_predictionMode;
    
    // Direction calibration
    int  m_directionWindow[20];
    int  m_directionWindowIdx;
    int  m_directionWindowCount;
    uint m_lastCalibrationWarningTick;
    int  m_consecutiveBiasedVotes;
    datetime m_lastNoSignalDiagTime;
    int  m_calibrationWindowSize;
    double m_calibrationRatioThreshold;
    int  m_minDirectionalCount;
    
    // Feature pipeline
    CFeaturePipelineONNX* m_featurePipeline;
    bool              m_ownsPipeline;

    bool IsValidConfidence(const double conf) const
    {
        return (conf == conf) && (MathAbs(conf) < 1e308) && conf >= 0.0 && conf <= 1.0;
    }

    void RecordDirectionPrediction(ENUM_TRADE_SIGNAL signal)
    {
        int dirValue = 0;
        if(signal == TRADE_SIGNAL_BUY) dirValue = 1;
        else if(signal == TRADE_SIGNAL_SELL) dirValue = -1;
        
        m_directionWindow[m_directionWindowIdx] = dirValue;
        m_directionWindowIdx = (m_directionWindowIdx + 1) % 20;
        if(m_directionWindowCount < 20)
            m_directionWindowCount++;
        
        if(IsDirectionDegenerate())
        {
            m_consecutiveBiasedVotes++;
            uint currentTick = GetTickCount();
            if(m_lastCalibrationWarningTick == 0 || (currentTick - m_lastCalibrationWarningTick) >= 60000)
            {
                int buyCount = 0, sellCount = 0;
                for(int i = 0; i < m_directionWindowCount; i++)
                {
                    if(m_directionWindow[i] == 1) buyCount++;
                    else if(m_directionWindow[i] == -1) sellCount++;
                }
                double windowBuyRatio = (double)buyCount / (double)m_directionWindowCount;
                double windowSellRatio = (double)sellCount / (double)m_directionWindowCount;
                int directionalCount = buyCount + sellCount;
                double dirBuyRatio = (directionalCount > 0) ? (double)buyCount / (double)directionalCount : 0.0;
                double dirSellRatio = (directionalCount > 0) ? (double)sellCount / (double)directionalCount : 0.0;
                PrintFormat("[AI-CALIBRATION-WARNING][PYTHON] Model degenerate: window_buy=%.2f, window_sell=%.2f, dir_buy=%.2f, dir_sell=%.2f, consecutive=%d | %s",
                           windowBuyRatio, windowSellRatio, dirBuyRatio, dirSellRatio, m_consecutiveBiasedVotes, m_symbol);
                m_lastCalibrationWarningTick = currentTick;
            }
        }
        else
        {
            m_consecutiveBiasedVotes = 0;
        }
    }

    void LogVoteHeartbeat()
    {
        datetime now = TimeCurrent();
        if(m_lastVoteLogTime == 0 || (now - m_lastVoteLogTime) >= 10)
        {
            PrintFormat("[AI-VOTE][PYTHON] %s | votes=%I64u | buy=%I64u | sell=%I64u | none=%I64u | conf=%.3f | reason=%s | mode=%s",
                        m_symbol, m_voteCount, m_buyVotes, m_sellVotes, m_noneVotes, m_cachedConfidence, m_lastDecisionReasonTag, m_predictionMode);
            m_lastVoteLogTime = now;
        }
    }

public:
    CPythonBridgeAIStrategyAdapter(CPythonBridge* pythonBridge = NULL, 
                                   const string predictionMode = "ensemble",
                                   int familyId = -1)
    {
        m_pythonBridge = pythonBridge;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_enabled = true;
        m_weight = 1.5;
        m_lastSignalTime = 0;
        m_cacheBarTime = 0;
        m_cacheRefreshTime = 0;
        m_hasCachedSignal = false;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_lastDecisionReasonTag = "PYTHON_UNSET";
        m_minConfidence = 0.55;
        m_voteCount = 0;
        m_buyVotes = 0;
        m_sellVotes = 0;
        m_noneVotes = 0;
        m_lastVoteLogTime = 0;
        m_barCounter = 0;
        m_familyId = familyId;
        m_predictionMode = predictionMode;
        m_directionWindowIdx = 0;
        m_directionWindowCount = 0;
        m_lastCalibrationWarningTick = 0;
        m_consecutiveBiasedVotes = 0;
        m_lastNoSignalDiagTime = 0;
        m_calibrationWindowSize = 20;
        m_calibrationRatioThreshold = 0.70;
        m_minDirectionalCount = 5;
        m_featurePipeline = NULL;
        m_ownsPipeline = false;
        ArrayInitialize(m_directionWindow, 0);
    }

    virtual ~CPythonBridgeAIStrategyAdapter() 
    {
        if(m_ownsPipeline && m_featurePipeline != NULL)
        {
            delete m_featurePipeline;
        }
    }

    virtual bool Init(const string symbol,
                      const ENUM_TIMEFRAMES timeframe,
                      void* tradeManagerPtr,
                      void* positionSizerPtr,
                      void* unifiedRiskManagerPtr = NULL) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_cacheBarTime = 0;
        m_cacheRefreshTime = 0;
        m_hasCachedSignal = false;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_barCounter = 0;

        // Initialize feature pipeline
        if(m_featurePipeline == NULL)
        {
            m_featurePipeline = new CFeaturePipelineONNX();
            m_ownsPipeline = true;
        }

        if(m_pythonBridge != NULL && m_pythonBridge.IsInitialized())
        {
            m_lastDecisionReasonTag = "PYTHON_BRIDGE_INITIALIZED";
            return true;
        }
        
        m_lastDecisionReasonTag = "PYTHON_BRIDGE_UNAVAILABLE";
        return false;
    }

    virtual void Deinit(void) override
    {
        if(m_ownsPipeline && m_featurePipeline != NULL)
        {
            delete m_featurePipeline;
            m_featurePipeline = NULL;
        }
        m_lastDecisionReasonTag = "PYTHON_DEINIT";
    }

    // Initialize AI model with symbol/timeframe/risk manager after factory creation
    virtual bool InitializeAI(const string symbol, const ENUM_TIMEFRAMES timeframe, void* unifiedRiskManager) override
    {
        if(m_pythonBridge != NULL && m_pythonBridge.IsInitialized())
        {
            m_symbol = symbol;
            m_timeframe = timeframe;
            m_lastDecisionReasonTag = "PYTHON_AI_INITIALIZED";
            return true;
        }
        m_lastDecisionReasonTag = "PYTHON_AI_INIT_FAILED";
        return false;
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        
        datetime now = TimeCurrent();
        if(now - m_lastVoteLogTime >= 86400)
        {
            m_voteCount = 0;
            m_buyVotes = 0;
            m_sellVotes = 0;
            m_noneVotes = 0;
            m_lastVoteLogTime = now;
            PrintFormat("[AI-VOTE][PYTHON] %s | Rolling vote window reset after 24h", m_symbol);
        }

        if(!m_enabled || m_pythonBridge == NULL || !m_pythonBridge.IsInitialized())
        {
            m_voteCount++;
            m_noneVotes++;
            m_lastDecisionReasonTag = "PYTHON_DISABLED_OR_UNAVAILABLE";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        datetime currentBarTime = (m_symbol == "") ? 0 : iTime(m_symbol, m_timeframe, 0);
        datetime cacheNow = TimeCurrent();
        if(m_hasCachedSignal && currentBarTime > 0 && currentBarTime == m_cacheBarTime &&
           m_cacheRefreshTime > 0 && (cacheNow - m_cacheRefreshTime) < 10)
        {
            confidence = m_cachedConfidence;
            LogVoteHeartbeat();
            return m_cachedSignal;
        }

        m_voteCount++;
        
        // Build features using centralized pipeline
        double features[];
        if(m_featurePipeline == NULL || !m_featurePipeline.BuildFeatures(m_symbol, m_timeframe, features, 1))
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "PYTHON_FEATURES_UNAVAILABLE";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        // Get prediction from Python Bridge
        SPythonBridgeResponse response = m_pythonBridge.Predict(features, ArraySize(features), m_predictionMode, m_familyId, m_symbol);
        
        if(!response.success)
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "PYTHON_PREDICTION_FAILED: " + response.error_message;
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        // Determine signal from probabilities
        double buyProb = response.buy_prob;
        double sellProb = response.sell_prob;
        double holdProb = response.hold_prob;
        
        // Use the highest probability
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        double maxProb = holdProb;
        
        if(buyProb > maxProb && buyProb >= m_minConfidence)
        {
            maxProb = buyProb;
            signal = TRADE_SIGNAL_BUY;
        }
        else if(sellProb > maxProb && sellProb >= m_minConfidence)
        {
            maxProb = sellProb;
            signal = TRADE_SIGNAL_SELL;
        }
        else
        {
            // No clear signal
            m_noneVotes++;
            m_lastDecisionReasonTag = "PYTHON_NO_CLEAR_SIGNAL";
            confidence = maxProb;
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        confidence = maxProb;
        
        // Validate confidence
        if(!IsValidConfidence(confidence))
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "PYTHON_INVALID_CONFIDENCE";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        m_cachedSignal = signal;
        m_cachedConfidence = confidence;
        m_cacheBarTime = currentBarTime;
        m_cacheRefreshTime = cacheNow;
        m_hasCachedSignal = true;

        if(signal == TRADE_SIGNAL_BUY)
        {
            m_buyVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "PYTHON_SIGNAL_BUY";
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_sellVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "PYTHON_SIGNAL_SELL";
        }
        else
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "PYTHON_NO_SIGNAL";
            confidence = 0.0;
        }

        // Record prediction for direction calibration
        RecordDirectionPrediction(signal);

        LogVoteHeartbeat();
        return signal;
    }
    
    virtual string GetName(void) const override { return "Python Bridge AI (" + m_predictionMode + ")"; }
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_AI_ENHANCED; }
    virtual bool IsEnabled(void) const override { return m_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    virtual double GetWeight(void) const override { return GetCalibratedWeight(m_weight); }
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    
    virtual bool IsDirectionDegenerate(void) const override
    {
        int windowSize = m_calibrationWindowSize;
        if(m_directionWindowCount < windowSize)
            return false;
        int buyCount = 0, sellCount = 0;
        int limit = MathMin(windowSize, 20);
        for(int i = 0; i < limit; i++)
        {
            if(m_directionWindow[i] == 1) buyCount++;
            else if(m_directionWindow[i] == -1) sellCount++;
        }
        int directionalCount = buyCount + sellCount;
        if(directionalCount < m_minDirectionalCount) return false;
        double buyRatio = (double)buyCount / (double)directionalCount;
        double sellRatio = (double)sellCount / (double)directionalCount;
        return (buyRatio > m_calibrationRatioThreshold || sellRatio > m_calibrationRatioThreshold);
    }
    
    double GetDirectionalBias(void) const
    {
        int windowSize = m_calibrationWindowSize;
        if(m_directionWindowCount < windowSize) return 0.0;
        int buyCount = 0, sellCount = 0;
        int limit = MathMin(windowSize, 20);
        for(int i = 0; i < limit; i++)
        {
            if(m_directionWindow[i] == 1) buyCount++;
            else if(m_directionWindow[i] == -1) sellCount++;
        }
        int directionalCount = buyCount + sellCount;
        if(directionalCount < m_minDirectionalCount) return 0.0;
        return (double)buyCount / (double)directionalCount;
    }
    
    virtual double GetCalibratedWeight(double baseWeight) const override
    {
        if(!IsDirectionDegenerate())
            return baseWeight;
        double bias = GetDirectionalBias();
        if(bias > 0.95 || bias < 0.05)
            return baseWeight * 0.10;
        if(bias > 0.90 || bias < 0.10)
            return baseWeight * 0.25;
        if(bias > 0.80 || bias < 0.20)
            return baseWeight * 0.50;
        return baseWeight * 0.70;
    }
    
    virtual bool ValidateParameters(void) override 
        { 
            return (m_pythonBridge != NULL && m_pythonBridge.IsInitialized()); 
        }
    
        virtual bool ValidateRiskManagerInjection(void) const override
        {
            return false; // Default: risk manager not injected
        }
    
        virtual bool ShouldBypassTierConfidenceFloor(void) const override
        {
            return false; // Default: no bypass
        }
    
        virtual datetime GetLastSignalTime(void) const override { return m_lastSignalTime; }
    virtual string GetLastDecisionReasonTag(void) const override { return m_lastDecisionReasonTag; }
    virtual void SetConfidenceThreshold(double threshold) override { m_minConfidence = threshold; }
    
    // Configurable direction calibration setters
    virtual void SetCalibrationWindowSize(int size) { m_calibrationWindowSize = MathMax(5, MathMin(size, 20)); }
    virtual void SetCalibrationRatioThreshold(double threshold) { m_calibrationRatioThreshold = MathMax(0.5, MathMin(threshold, 0.95)); }
    virtual void SetMinDirectionalCount(int count) { m_minDirectionalCount = MathMax(1, MathMin(count, 20)); }
    
    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = (int)m_voteCount;
        successful = 0; // Python bridge doesn't track wins internally
        accuracy = (m_voteCount > 0) ? 0.0 : 0.0;
    }

    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}
    virtual void OnTick(void) override {}
    virtual void OnTimer(void) override {}

    virtual double GetUncertainty(void) override
    {
        return 1.0 - m_cachedConfidence;
    }
    
    virtual bool IsModelHealthy(void) const override
    {
        return (m_pythonBridge != NULL && m_pythonBridge.IsConnected());
    }
    
    virtual bool IsTraining(void) const override
    {
        return false;
    }
    
    virtual int GetTrainingSteps(void) const override
    {
        return 0;
    }
    
    virtual double GetTemperature(void) const override
    {
        return 1.0;
    }
    
    virtual void SetTemperature(const double temperature) override {}
    
    virtual int GetCurrentRegime(void) const override
    {
        return 0;
    }
    
    virtual bool SaveCheckpoint(void) override
    {
        return false;
    }
    
    // IUncertaintyEstimation
    virtual void GetConfidenceInterval(double &lower, double &upper) const override
    {
        lower = 0.0;
        upper = 1.0;
        if(m_pythonBridge != NULL)
        {
            double confidence = m_cachedConfidence;
            double uncertainty = 1.0 - confidence;
            lower = MathMax(0.0, confidence - uncertainty);
            upper = MathMin(1.0, confidence + uncertainty);
        }
    }
    
    // IModelHealth
    virtual double GetHealthScore(void) const override
    {
        return IsModelHealthy() ? 1.0 : 0.0;
    }
    
    // IOnlineTraining
    virtual void EnableOnlineTraining(const bool enable) override
    {
        // Python bridge doesn't support online training
    }
    
    virtual bool TrainStep(void) override
    {
        return false;
    }
    
    virtual string GetTrainingState(void) const override
    {
        return "NOT_SUPPORTED";
    }
    
    // IRegimeAware
    virtual void OnRegimeChange(const int newRegime) override
    {
        // Python bridge doesn't have regime awareness
    }
    
    // ICheckpointing
    virtual string GetLastLoadStatus(void) const override
    {
        return m_pythonBridge != NULL ? "LOADED" : "NOT_INITIALIZED";
    }
    
    // Set Python Bridge reference
    void SetPythonBridge(CPythonBridge* bridge) { m_pythonBridge = bridge; }
    
    // Set family ID for family-aware predictions
    void SetFamilyId(int familyId) { m_familyId = familyId; }
    
    // Set prediction mode (ensemble, doubleadapt, maml_ppo, family)
    void SetPredictionMode(const string mode) { m_predictionMode = mode; }
};

#endif // CORE_STRATEGY_PYTHON_BRIDGE_AI_STRATEGY_ADAPTER_MQH