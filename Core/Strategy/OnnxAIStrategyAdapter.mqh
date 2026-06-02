//+------------------------------------------------------------------+
//| OnnxAIStrategyAdapter.mqh                                        |
//| Symbol-scoped ONNX AI strategy adapter                           |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_STRATEGY_ONNX_AI_STRATEGY_ADAPTER_MQH
#define CORE_STRATEGY_ONNX_AI_STRATEGY_ADAPTER_MQH

#include "../../Interfaces/IStrategy.mqh"
#include "../../Interfaces/IAIStrategy.mqh"
#include "../../AIModules/OnnxBrain.mqh"
#include "../AI/AIFeatureVectorBuilder.mqh"
#include "../AI/PipelineScaler.mqh"

class COnnxAIStrategyAdapter : public IAIStrategy
{
private:
    COnnxBrain      m_brain;
    uchar           m_modelBuffer[];
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool            m_enabled;
    double          m_weight;
    datetime        m_lastSignalTime;
    datetime        m_cacheBarTime;
    bool            m_hasCachedSignal;
    ENUM_TRADE_SIGNAL m_cachedSignal;
    double          m_cachedConfidence;
    string          m_lastDecisionReasonTag;
    double          m_minConfidence;
    CPipelineScaler m_scaler;
    string          m_scalerWatchPath;
    datetime        m_lastScalerCheckTime;
    ulong           m_voteCount;
    ulong           m_buyVotes;
    ulong           m_sellVotes;
    ulong           m_noneVotes;
    datetime        m_lastVoteLogTime;
    int             m_barCounter;
    datetime        m_voteWindowStart;  // Rolling vote window start time
    
    bool IsValidConfidence(const double conf) const
    {
        return (conf == conf) && (MathAbs(conf) < 1e308) && conf >= 0.0 && conf <= 1.0;
    }

    void LogVoteHeartbeat()
    {
        datetime now = TimeCurrent();
        if(m_lastVoteLogTime == 0 || (now - m_lastVoteLogTime) >= 10)
        {
            PrintFormat("[AI-VOTE][ONNX] %s | votes=%I64u | buy=%I64u | sell=%I64u | none=%I64u | conf=%.3f | reason=%s",
                        m_symbol, m_voteCount, m_buyVotes, m_sellVotes, m_noneVotes, m_cachedConfidence, m_lastDecisionReasonTag);
            m_lastVoteLogTime = now;
        }
    }

public:
    COnnxAIStrategyAdapter(const uchar &modelBuffer[])
    {
        ArrayCopy(m_modelBuffer, modelBuffer);
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_enabled = true;
        m_weight = 2.0;
        m_lastSignalTime = 0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_lastDecisionReasonTag = "ONNX_UNSET";
        m_minConfidence = 0.70;
        m_scalerWatchPath = "EAModels\\ONNX\\scaler.bin";
        m_lastScalerCheckTime = 0;
        m_voteCount = 0;
        m_buyVotes = 0;
        m_sellVotes = 0;
        m_noneVotes = 0;
        m_lastVoteLogTime = 0;
        m_barCounter = 0;
        m_voteWindowStart = TimeCurrent();
    }

    virtual ~COnnxAIStrategyAdapter() {}

    virtual bool Init(const string symbol,
                      const ENUM_TIMEFRAMES timeframe,
                      void* tradeManagerPtr,
                      void* positionSizerPtr,
                      void* unifiedRiskManagerPtr = NULL) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_barCounter = 0;
        m_lastScalerCheckTime = 0;

        if(!m_brain.Init(m_modelBuffer))
        {
            m_lastDecisionReasonTag = "ONNX_MODEL_UNAVAILABLE";
            return false;
        }

        m_brain.SetWatchPath("EAModels\\ONNX\\model_update.onnx", 100);
        if(m_scaler.LoadParams(m_scalerWatchPath, true))
            PrintFormat("[ONNX] Loaded scaler parameters | features=%d | path=%s",
                        m_scaler.GetFeatureCount(), m_scalerWatchPath);
        m_lastDecisionReasonTag = "ONNX_INITIALIZED";
        return true;
    }

    virtual void Deinit(void) override
    {
        m_brain.Deinit();
        m_lastDecisionReasonTag = "ONNX_DEINIT";
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
            PrintFormat("[AI-VOTE][ONNX] %s | Rolling vote window reset after 24h", m_symbol);
        }

        if(!m_enabled || !m_brain.IsLoaded())
        {
            m_voteCount++;
            m_noneVotes++;
            m_lastDecisionReasonTag = "ONNX_DISABLED_OR_UNAVAILABLE";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        datetime currentBarTime = (m_symbol == "") ? 0 : iTime(m_symbol, m_timeframe, 0);
        if(m_hasCachedSignal && currentBarTime > 0 && currentBarTime == m_cacheBarTime)
        {
            confidence = m_cachedConfidence;
            LogVoteHeartbeat();
            return m_cachedSignal;
        }

        m_voteCount++;
        double features[];
        if(!CAIFeatureVectorBuilder::BuildNNFeatureVector(m_symbol, m_timeframe, features, 1))
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ONNX_FEATURES_UNAVAILABLE";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        // Reuse 'now' from line 126 instead of redeclaring
        if(m_lastScalerCheckTime == 0 || (now - m_lastScalerCheckTime) >= 10)
        {
            if(m_scaler.MaybeReload(m_scalerWatchPath, true))
                PrintFormat("[ONNX] Reloaded scaler parameters | features=%d | path=%s",
                            m_scaler.GetFeatureCount(), m_scalerWatchPath);
            m_lastScalerCheckTime = now;
        }

        if(m_scaler.IsLoaded() && !m_scaler.Apply(features))
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ONNX_SCALER_APPLY_FAILED";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        m_brain.PushFeatures(features, ArraySize(features));
        m_barCounter++;
        if((m_barCounter % 10) == 0)
            m_brain.CheckForModelUpdate(features, ArraySize(features));

        // Gate on readiness FIRST (buffer not yet full = warmup, not an error).
        // Only attempt inference once the rolling window is full; a failure
        // after that is a genuine OnnxRun / handle error.
        if(!m_brain.IsReady())
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ONNX_WARMING_UP";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        if(!m_brain.RunInference())
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ONNX_INFERENCE_FAILED";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        int onnxSignal = m_brain.GetSignal();
        confidence = m_brain.GetConfidence();
        
        // Validate confidence value
        if(!IsValidConfidence(confidence))
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ONNX_INVALID_CONFIDENCE";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }
        
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        if(onnxSignal == 2 && confidence >= m_minConfidence)
            signal = TRADE_SIGNAL_BUY;
        else if(onnxSignal == 0 && confidence >= m_minConfidence)
            signal = TRADE_SIGNAL_SELL;

        m_cachedSignal = signal;
        m_cachedConfidence = (signal == TRADE_SIGNAL_NONE) ? 0.0 : confidence;
        m_cacheBarTime = currentBarTime;
        m_hasCachedSignal = true;

        if(signal == TRADE_SIGNAL_BUY)
        {
            m_buyVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "ONNX_SIGNAL_BUY";
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_sellVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "ONNX_SIGNAL_SELL";
        }
        else
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ONNX_NO_SIGNAL";
            confidence = 0.0;
        }

        LogVoteHeartbeat();
        return signal;
    }

    virtual void OnNewBar(void) override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}
    virtual string GetName(void) const override { return "ONNX AI"; }
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_AI_ENHANCED; }
    virtual bool IsEnabled(void) const override { return m_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    virtual double GetWeight(void) const override { return m_weight; }
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    virtual bool ValidateParameters(void) override { return m_brain.IsLoaded(); }
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
        return 0.5;
    }
    
    virtual bool IsModelHealthy(void) const override
    {
        return m_brain.IsLoaded();
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
    
    virtual void SetTemperature(const double temperature) override
    {
    }
    
    virtual int GetRegimeState(void) const override
    {
        return -1;
    }
    
    virtual bool SaveCheckpoint(void) override
    {
        return false;
    }
    
    virtual string GetLastLoadStatus(void) const override
    {
        return m_brain.IsLoaded() ? "LOADED" : "NOT_LOADED";
    }
};

#endif // CORE_STRATEGY_ONNX_AI_STRATEGY_ADAPTER_MQH
