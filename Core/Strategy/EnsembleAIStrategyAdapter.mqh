//+------------------------------------------------------------------+
//| EnsembleAIStrategyAdapter.mqh                                    |
//| IStrategy adapter for runtime ensemble AI voting                 |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_STRATEGY_ENSEMBLE_AI_STRATEGY_ADAPTER_MQH
#define CORE_STRATEGY_ENSEMBLE_AI_STRATEGY_ADAPTER_MQH

#include "../../Interfaces/IStrategy.mqh"
#include "../../Interfaces/IAIStrategy.mqh"
#include "../../AIModules/EnsembleMetaLearner.mqh"
#include "../AI/AIFeatureVectorBuilder.mqh"

class CEnsembleAIStrategyAdapter : public IAIStrategy
{
private:
    CEnsembleMetaLearner m_ensemble;
    CTransformerBrain* m_modelA;
    CTransformerBrain* m_modelB;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_enabled;
    double m_weight;
    datetime m_lastSignalTime;
    bool m_modelsInitialized;
    ulong m_voteCount;
    ulong m_buyVotes;
    ulong m_sellVotes;
    ulong m_noneVotes;
    datetime m_lastVoteLogTime;
    ENUM_TRADE_SIGNAL m_cachedSignal;
    double m_cachedConfidence;
    datetime m_cacheBarTime;
    datetime m_cacheRefreshTime;
    ENUM_TIMEFRAMES m_cacheTimeframe;
    bool m_hasCachedSignal;
    string m_lastDecisionReasonTag;
    double m_minConfidence;
    bool m_ownsModels;  // Track ownership to prevent double-delete
    datetime m_voteWindowStart;  // Rolling vote window start time
    
    // Direction calibration rolling window (last 20 predictions)
    int  m_directionWindow[20];  // 1=BUY, -1=SELL, 0=NONE
    int  m_directionWindowIdx;   // Circular buffer index
    int  m_directionWindowCount; // Number of filled slots (0..20)
    datetime m_lastCalibrationWarningTime;  // Throttle calibration warning logs
    
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
        
        // Check and log degenerate detection
        if(IsDirectionDegenerate())
        {
            datetime now = TimeCurrent();
            if(m_lastCalibrationWarningTime == 0 || (now - m_lastCalibrationWarningTime) >= 60)
            {
                int buyCount = 0, sellCount = 0;
                for(int i = 0; i < m_directionWindowCount; i++)
                {
                    if(m_directionWindow[i] == 1) buyCount++;
                    else if(m_directionWindow[i] == -1) sellCount++;
                }
                double buyRatio = (double)buyCount / (double)m_directionWindowCount;
                double sellRatio = (double)sellCount / (double)m_directionWindowCount;
                PrintFormat("[AI-CALIBRATION-WARNING] Model degenerate: buy_ratio=%.2f, sell_ratio=%.2f, weight reduced by 50%% | %s",
                           buyRatio, sellRatio, m_symbol);
                m_lastCalibrationWarningTime = now;
            }
        }
    }


    bool EnsureModels()
    {
        if(m_modelsInitialized)
            return true;

        // Two diverse transformer members for ensemble voting.
        m_modelA = new CTransformerBrain(TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_NUM_HEADS_DEFAULT, TRANSFORMER_NUM_LAYERS_A_DEFAULT, TRANSFORMER_D_FF_DEFAULT, TRANSFORMER_MAX_SEQ_LEN_DEFAULT, TRANSFORMER_LR_A_DEFAULT);
        m_modelB = new CTransformerBrain(TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_NUM_HEADS_DEFAULT, TRANSFORMER_NUM_LAYERS_A_DEFAULT, TRANSFORMER_D_FF_B_DEFAULT, TRANSFORMER_SHORT_SEQ_LEN_DEFAULT, TRANSFORMER_LR_B_DEFAULT);
        if(m_modelA == NULL || m_modelB == NULL)
        {
            // Clean up on failure
            if(m_modelA != NULL)
            {
                delete m_modelA;
                m_modelA = NULL;
            }
            if(m_modelB != NULL)
            {
                delete m_modelB;
                m_modelB = NULL;
            }
            return false;
        }

        if(!m_ensemble.AddModel(m_modelA, 1.0))
        {
            // Clean up on ensemble addition failure
            delete m_modelA;
            m_modelA = NULL;
            delete m_modelB;
            m_modelB = NULL;
            return false;
        }
        if(!m_ensemble.AddModel(m_modelB, 1.0))
        {
            // Clean up on ensemble addition failure
            if(m_ensemble.GetActiveModelCount() > 0)
                m_ensemble.RemoveModel(m_ensemble.GetActiveModelCount() - 1);
            delete m_modelB;
            m_modelB = NULL;
            m_modelA = NULL;
            return false;
        }

        m_modelsInitialized = true;
        m_ownsModels = true;  // Mark adapter as owner since we created the models
        return true;
    }

    void LogVoteHeartbeat()
    {
        datetime now = TimeCurrent();
        if(m_lastVoteLogTime == 0 || (now - m_lastVoteLogTime) >= 10) // More frequent heartbeats
        {
            // FIX: Validate confidence before logging to prevent NaN output
            double logConfidence = m_cachedConfidence;
            if(!MathIsValidNumber(logConfidence))
                logConfidence = 0.0;
                
            PrintFormat("[AI-VOTE][Ensemble] %s | votes=%I64u | buy=%I64u | sell=%I64u | none=%I64u | models=%d | conf=%.2f | reason=%s",
                        m_symbol, m_voteCount, m_buyVotes, m_sellVotes, m_noneVotes, m_ensemble.GetActiveModelCount(), logConfidence, m_lastDecisionReasonTag);
            m_lastVoteLogTime = now;
        }
    }

public:
    CEnsembleAIStrategyAdapter()
    {
        m_modelA = NULL;
        m_modelB = NULL;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_enabled = true;
        m_weight = 1.0;
        m_lastSignalTime = 0;
        m_modelsInitialized = false;
        m_voteCount = 0;
        m_buyVotes = 0;
        m_sellVotes = 0;
        m_noneVotes = 0;
        m_lastVoteLogTime = 0;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_cacheBarTime = 0;
        m_cacheRefreshTime = 0;
        m_cacheTimeframe = PERIOD_CURRENT;
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = "ENSEMBLE_UNSET";
        m_minConfidence = 0.70;
        m_ownsModels = false;
        m_voteWindowStart = TimeCurrent();
        m_directionWindowIdx = 0;
        m_directionWindowCount = 0;
        m_lastCalibrationWarningTime = 0;
        ArrayInitialize(m_directionWindow, 0);
    }

    virtual ~CEnsembleAIStrategyAdapter()
    {
        // Clean up models if this adapter owns them
        // The ensemble's m_models.FreeMode(true) setting means it will also try to delete
        // models when cleared, so we need to ensure we only delete if we own them
        // and haven't already passed ownership to the ensemble
        if(m_ownsModels)
        {
            // Remove models from ensemble first to prevent double-delete
            m_ensemble.RemoveModel(m_ensemble.GetActiveModelCount() - 1);
            if(m_ensemble.GetActiveModelCount() > 0)
                m_ensemble.RemoveModel(m_ensemble.GetActiveModelCount() - 1);
            
            // Now safely delete the models
            if(m_modelA != NULL)
            {
                delete m_modelA;
                m_modelA = NULL;
            }
            if(m_modelB != NULL)
            {
                delete m_modelB;
                m_modelB = NULL;
            }
        }
        else
        {
            // Ensemble owns the models, just clear references
            m_modelA = NULL;
            m_modelB = NULL;
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
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_cacheBarTime = 0;
        m_cacheRefreshTime = 0;
        m_cacheTimeframe = timeframe;
        m_hasCachedSignal = false;
        bool modelsReady = EnsureModels();
        m_lastDecisionReasonTag = modelsReady ? "ENSEMBLE_INITIALIZED" : "ENSEMBLE_INIT_FAILED";
        return modelsReady;
    }

    virtual void Deinit(void) override
    {
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = "ENSEMBLE_DEINIT";
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        
        datetime now = TimeCurrent();
        if(now - m_voteWindowStart >= 86400)
        {
            m_voteCount = 0;
            m_buyVotes = 0;
            m_sellVotes = 0;
            m_noneVotes = 0;
            m_voteWindowStart = now;
            PrintFormat("[AI-VOTE][Ensemble] %s | Rolling vote window reset after 24h", m_symbol);
        }

        if(!m_enabled || !EnsureModels())
        {
            m_voteCount++;
            m_noneVotes++;
            m_lastDecisionReasonTag = "ENSEMBLE_DISABLED_OR_UNINIT";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        datetime currentBarTime = (m_symbol == "") ? 0 : iTime(m_symbol, m_timeframe, 0);
        bool needsNewInference = (!m_hasCachedSignal ||
                                  currentBarTime <= 0 ||
                                  currentBarTime != m_cacheBarTime ||
                                  m_cacheTimeframe != m_timeframe ||
                                  m_cacheRefreshTime <= 0 ||
                                  (TimeCurrent() - m_cacheRefreshTime) >= 10);
        if(!needsNewInference)
        {
            confidence = m_cachedConfidence;
            signal = m_cachedSignal;
        }
        else
        {
            m_voteCount++;
            double inputSequence[];
            if(!CAIFeatureVectorBuilder::BuildTransformerInput(m_symbol, m_timeframe, inputSequence, TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_SHORT_SEQ_LEN_DEFAULT))
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "ENSEMBLE_FEATURES_UNAVAILABLE";
                // Don't cache failed feature builds - allow retry on next tick
                m_hasCachedSignal = false;
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            double ensembleBuy = 0.0;
            double ensembleSell = 0.0;
            double ensembleConfidence = 0.0;
            if(!m_ensemble.ProcessMarketData(inputSequence, ensembleBuy, ensembleSell, ensembleConfidence))
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "ENSEMBLE_INFERENCE_FAILED";
                // Don't cache failed inference - allow retry on next tick
                m_hasCachedSignal = false;
                confidence = 0.0; // FIX: Reset confidence to 0.0 on failure
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            double directionalConfidence = MathMax(ensembleBuy, ensembleSell);
            confidence = MathMax(0.0, MathMin(1.0, MathMax(ensembleConfidence, directionalConfidence)));
            
            // Validate confidence value
            if(!IsValidConfidence(confidence))
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "ENSEMBLE_INVALID_CONFIDENCE";
                m_hasCachedSignal = false;
                confidence = 0.0;
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            // RECOVERY FIX: Exploration-mode threshold for untrained ensemble.
            // When ensemble has zero trade history, lower the threshold to allow
            // initial signal generation and enable the learning feedback loop.
            double effectiveMinConfidence = m_minConfidence;
            bool isExplorationMode = (m_buyVotes + m_sellVotes == 0);
            if(isExplorationMode && effectiveMinConfidence > 0.15)
                effectiveMinConfidence = 0.15;

            if(ensembleBuy > ensembleSell && directionalConfidence >= effectiveMinConfidence)
                signal = TRADE_SIGNAL_BUY;
            else if(ensembleSell > ensembleBuy && directionalConfidence >= effectiveMinConfidence)
                signal = TRADE_SIGNAL_SELL;

            m_cachedSignal = signal;
            m_cachedConfidence = confidence;
            m_cacheBarTime = currentBarTime;
            m_cacheRefreshTime = TimeCurrent();
            m_cacheTimeframe = m_timeframe;
            m_hasCachedSignal = true;
        }

        if(signal == TRADE_SIGNAL_BUY)
        {
            m_buyVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "ENSEMBLE_SIGNAL_BUY";
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_sellVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "ENSEMBLE_SIGNAL_SELL";
        }
        else
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ENSEMBLE_NO_SIGNAL";
            confidence = 0.0; // FIX: Reset confidence to 0.0 for NO_SIGNAL
        }

        // FIX: Final NaN validation before returning
        if(!MathIsValidNumber(confidence))
            confidence = 0.0;
        
        // Record prediction for direction calibration
        RecordDirectionPrediction(signal);
            
        LogVoteHeartbeat();
        return signal;
    }

    virtual void OnNewBar(void) override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}

    virtual string GetName(void) const override { return "Ensemble AI"; }
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_AI_ENHANCED; }
    virtual bool IsEnabled(void) const override { return m_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    virtual double GetWeight(void) const override { return GetCalibratedWeight(m_weight); }
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    
    virtual bool IsDirectionDegenerate(void) const override
    {
        if(m_directionWindowCount < 20)
            return false;
        int buyCount = 0, sellCount = 0;
        for(int i = 0; i < 20; i++)
        {
            if(m_directionWindow[i] == 1) buyCount++;
            else if(m_directionWindow[i] == -1) sellCount++;
        }
        double buyRatio = (double)buyCount / 20.0;
        double sellRatio = (double)sellCount / 20.0;
        return (buyRatio > 0.80 || sellRatio > 0.80);
    }
    
    virtual double GetCalibratedWeight(double baseWeight) const override
    {
        if(IsDirectionDegenerate())
            return baseWeight * 0.5;
        return baseWeight;
    }
    virtual bool ValidateParameters(void) override { return true; }
    virtual datetime GetLastSignalTime(void) const override { return m_lastSignalTime; }
    virtual string GetLastDecisionReasonTag(void) const override { return m_lastDecisionReasonTag; }
    virtual void SetConfidenceThreshold(double threshold) override { m_minConfidence = threshold; }

    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = (int)m_voteCount;
        successful = 0;
        accuracy = 0.0;
    }
    
    virtual double GetUncertainty(void) override
    {
        return m_ensemble.GetUncertainty();
    }
    
    virtual bool IsModelHealthy(void) const override
    {
        return (m_modelA != NULL || m_modelB != NULL) && m_modelsInitialized;
    }
    
    virtual bool IsTraining(void) const override
    {
        return m_ensemble.IsLearningEnabled();
    }
    
    virtual int GetTrainingSteps(void) const override
    {
        return m_ensemble.GetUpdateCount();
    }
    
    virtual double GetTemperature(void) const override
    {
        return 1.0;
    }
    
    virtual void SetTemperature(const double temperature) override
    {
    }
    
    virtual int GetRegimeState(void) const override
    {
        return m_ensemble.GetCurrentRegime();
    }
    
    virtual bool SaveCheckpoint(void) override
    {
        return false;
    }
    
    virtual string GetLastLoadStatus(void) const override
    {
        return m_modelsInitialized ? "LOADED" : "NOT_INITIALIZED";
    }
};

#endif // CORE_STRATEGY_ENSEMBLE_AI_STRATEGY_ADAPTER_MQH
