//+------------------------------------------------------------------+
//| TransformerAIStrategyAdapter.mqh                                 |
//| IStrategy adapter for runtime transformer voting                 |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_STRATEGY_TRANSFORMER_AI_STRATEGY_ADAPTER_MQH
#define CORE_STRATEGY_TRANSFORMER_AI_STRATEGY_ADAPTER_MQH

// Checkpoint version constant for transformer models (integer version)
#define TRANSFORMER_CHECKPOINT_VERSION 1

#include "../../Interfaces/IStrategy.mqh"
#include "../../Interfaces/IAIStrategy.mqh"
#include "../../AIModules/TransformerBrain.mqh"
#include "../AI/AIFeatureVectorBuilder.mqh"

class CTransformerAIStrategyAdapter : public IAIStrategy
{
private:
    CTransformerBrain* m_transformer;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_enabled;
    double m_weight;
    datetime m_lastSignalTime;
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
    bool m_ownsTransformer;  // Track ownership for proper cleanup
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

    bool BuildFeaturesFailed(const string symbol, const ENUM_TIMEFRAMES tf, double &inputSeq[])
    {
        bool success = CAIFeatureVectorBuilder::BuildTransformerInput(symbol, tf, inputSeq, TRANSFORMER_D_MODEL_DEFAULT, 8);
        if(!success)
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "TRANSFORMER_FEATURES_UNAVAILABLE";
            // Don't cache failed feature builds - allow retry on next tick
            m_hasCachedSignal = false;
            LogVoteHeartbeat();
        }
        return !success;
    }
    
    bool InferenceFailed()
    {
        m_noneVotes++;
        m_lastDecisionReasonTag = "TRANSFORMER_INFERENCE_FAILED";
        // Don't cache failed inference - allow retry on next tick
        m_hasCachedSignal = false;
        LogVoteHeartbeat();
        return true;
    }


    datetime GetCurrentBarTime() const
    {
        if(m_symbol == "")
            return 0;
        return iTime(m_symbol, m_timeframe, 0);
    }

    bool NeedsNewInference(const datetime currentBarTime) const
    {
        return (!m_hasCachedSignal ||
                currentBarTime <= 0 ||
                currentBarTime != m_cacheBarTime ||
                m_cacheTimeframe != m_timeframe ||
                m_cacheRefreshTime <= 0 ||
                (TimeCurrent() - m_cacheRefreshTime) >= 10);
    }

    void UpdateCache(const datetime currentBarTime, const ENUM_TRADE_SIGNAL signal, const double confidence)
    {
        m_cachedSignal = signal;
        m_cachedConfidence = confidence;
        m_cacheBarTime = currentBarTime;
        m_cacheRefreshTime = TimeCurrent();
        m_cacheTimeframe = m_timeframe;
        m_hasCachedSignal = true;
    }

    void LogVoteHeartbeat()
    {
        datetime now = TimeCurrent();
        if(m_lastVoteLogTime == 0 || (now - m_lastVoteLogTime) >= 10) // More frequent heartbeats
        {
            PrintFormat("[AI-VOTE][Transformer] %s | votes=%I64u | buy=%I64u | sell=%I64u | none=%I64u | conf=%.2f | reason=%s",
                        m_symbol, m_voteCount, m_buyVotes, m_sellVotes, m_noneVotes, m_cachedConfidence, m_lastDecisionReasonTag);
            m_lastVoteLogTime = now;
        }
    }

public:
    CTransformerAIStrategyAdapter()
    {
        m_transformer = NULL;
        m_ownsTransformer = true;  // Default: adapter owns the transformer
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_enabled = true;
        m_weight = 1.0;
        m_lastSignalTime = 0;
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
        m_lastDecisionReasonTag = "TRANSFORMER_UNSET";
        m_minConfidence = 0.70;
        m_voteWindowStart = TimeCurrent();
        m_directionWindowIdx = 0;
        m_directionWindowCount = 0;
        m_lastCalibrationWarningTime = 0;
        ArrayInitialize(m_directionWindow, 0);
    }
    
    void SetSharedTransformer(CTransformerBrain* transformer)
    {
        // Only delete if we own the current transformer
        if(m_ownsTransformer && m_transformer != NULL)
        {
            delete m_transformer;
        }
        m_transformer = transformer;
        m_ownsTransformer = false;  // Now using shared transformer
    }
    
    virtual ~CTransformerAIStrategyAdapter()
    {
        if(m_ownsTransformer && m_transformer != NULL)
        {
            delete m_transformer;
            m_transformer = NULL;
        }
        // If shared, don't delete - let the owner handle cleanup
    }

    virtual bool Init(const string symbol,
                      const ENUM_TIMEFRAMES timeframe,
                      void* tradeManagerPtr,
                      void* positionSizerPtr,
                      void* unifiedRiskManagerPtr = NULL) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        if(m_transformer == NULL)
            m_transformer = new CTransformerBrain(TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_NUM_HEADS_DEFAULT, TRANSFORMER_NUM_LAYERS_A_DEFAULT, TRANSFORMER_D_FF_DEFAULT, TRANSFORMER_MAX_SEQ_LEN_DEFAULT, TRANSFORMER_LR_A_DEFAULT);
        if(m_transformer == NULL)
            return false;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_cacheBarTime = 0;
        m_cacheRefreshTime = 0;
        m_cacheTimeframe = timeframe;
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = (m_transformer != NULL) ? "TRANSFORMER_INITIALIZED" : "TRANSFORMER_INIT_FAILED";
        return true;
    }

    virtual void Deinit(void) override
    {
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = "TRANSFORMER_DEINIT";
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
            PrintFormat("[AI-VOTE][Transformer] %s | Rolling vote window reset after 24h", m_symbol);
        }

        if(!m_enabled || m_transformer == NULL)
        {
            m_voteCount++;
            m_noneVotes++;
            m_lastDecisionReasonTag = "TRANSFORMER_DISABLED_OR_UNINIT";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        datetime currentBarTime = GetCurrentBarTime();
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        if(!NeedsNewInference(currentBarTime))
        {
            confidence = m_cachedConfidence;
            signal = m_cachedSignal;
        }
        else
        {
            m_voteCount++;
            double inputSequence[];
            if(!CAIFeatureVectorBuilder::BuildTransformerInput(m_symbol, m_timeframe, inputSequence, TRANSFORMER_D_MODEL_DEFAULT, 8))
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "TRANSFORMER_FEATURES_UNAVAILABLE";
                // Don't cache failed feature builds - allow retry on next tick
                m_hasCachedSignal = false;
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            double predictions[];
            if(!m_transformer.GetPredictions(inputSequence, 8, predictions) || ArraySize(predictions) != 3)
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "TRANSFORMER_INFERENCE_FAILED";
                // Don't cache failed inference - allow retry on next tick
                m_hasCachedSignal = false;
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            double pNone = predictions[0];
            double pBuy = predictions[1];
            double pSell = predictions[2];

            double directionalConfidence = MathMax(pBuy, pSell);
            
            // Validate prediction values
            if(!IsValidConfidence(pNone) || !IsValidConfidence(pBuy) || !IsValidConfidence(pSell))
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "TRANSFORMER_INVALID_PREDICTION";
                // Don't cache invalid predictions - allow retry on next tick
                m_hasCachedSignal = false;
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }
            
            confidence = MathMax(0.0, MathMin(1.0, directionalConfidence));

            if(pBuy > pSell && pBuy >= pNone && directionalConfidence >= m_minConfidence)
                signal = TRADE_SIGNAL_BUY;
            else if(pSell > pBuy && pSell >= pNone && directionalConfidence >= m_minConfidence)
                signal = TRADE_SIGNAL_SELL;

            UpdateCache(currentBarTime, signal, confidence);
        }

        if(signal == TRADE_SIGNAL_BUY)
        {
            m_buyVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "TRANSFORMER_SIGNAL_BUY";
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_sellVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "TRANSFORMER_SIGNAL_SELL";
        }
        else
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "TRANSFORMER_NO_SIGNAL";
        }

        // Record prediction for direction calibration
        RecordDirectionPrediction(signal);

        LogVoteHeartbeat();
        return signal;
    }

    virtual void OnNewBar(void) override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}

    virtual string GetName(void) const override { return "Transformer AI"; }
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_AI_ENHANCED; }
    virtual bool IsEnabled(void) const override { return m_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    virtual double GetWeight(void) const override { return GetCalibratedWeight(m_weight); }
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    
    virtual bool IsDirectionDegenerate(void) const override
    {
        if(m_directionWindowCount < 20)
            return false;
        int windowSize = MathMin(m_directionWindowCount, 20);
        int buyCount = 0, sellCount = 0;
        for(int i = 0; i < windowSize; i++)
        {
            if(m_directionWindow[i] == 1) buyCount++;
            else if(m_directionWindow[i] == -1) sellCount++;
        }
        double buyRatio = (double)buyCount / (double)windowSize;
        double sellRatio = (double)sellCount / (double)windowSize;
        return (buyRatio > 0.80 || sellRatio > 0.80);
    }
    
    virtual double GetCalibratedWeight(double baseWeight) const override
    {
        if(IsDirectionDegenerate())
            return baseWeight * 0.5;
        return baseWeight;
    }
    virtual bool ValidateParameters(void) override { return (m_transformer != NULL); }
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
        if(m_transformer == NULL) return 0.5;
        return 1.0 - m_cachedConfidence;
    }
    
    virtual bool IsModelHealthy(void) const override
    {
        return (m_transformer != NULL);
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
        return (m_transformer != NULL) ? m_transformer.GetTemperature() : 1.0;
    }
    
    virtual void SetTemperature(const double temperature) override
    {
        if(m_transformer != NULL)
            m_transformer.SetTemperature(temperature);
    }
    
    virtual int GetRegimeState(void) const override
    {
        return -1;
    }
    
    virtual bool SaveCheckpoint(void) override
    {
        if(m_transformer == NULL || !m_ownsTransformer)
            return false;
        return m_transformer.SaveHeadState(NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe, TRANSFORMER_CHECKPOINT_VERSION));
    }
    
    virtual string GetLastLoadStatus(void) const override
    {
        return (m_transformer != NULL) ? "LOADED" : "NOT_INITIALIZED";
    }
};

#endif // CORE_STRATEGY_TRANSFORMER_AI_STRATEGY_ADAPTER_MQH
