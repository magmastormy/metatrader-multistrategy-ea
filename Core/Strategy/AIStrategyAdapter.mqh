//+------------------------------------------------------------------+
 //| AIStrategyAdapter.mqh                                            |
 //| Adapter to integrate CNeuralNetworkStrategy into Enterprise Manager|
 //+------------------------------------------------------------------+
 #property copyright "Copyright 2025, Advanced Trading Systems"
 #property strict
 
 #include "../../Interfaces/IStrategy.mqh"
 #include "../../Interfaces/IAIStrategy.mqh"
 #include "../../AIModules/NeuralNetworkStrategy.mqh"
 #include "../Utils/SubsystemLogger.mqh"
 
 //+------------------------------------------------------------------+
 //| AI Strategy Adapter Class                                        |
 //+------------------------------------------------------------------+
 class CAIStrategyAdapter : public IAIStrategy
 {
private:
    CNeuralNetworkStrategy* m_neuralNet;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_enabled;
    double m_weight;
    datetime m_lastSignalTime;
    string m_lastDecisionReasonTag;
    CSubsystemLogger* m_logger;  // AI subsystem logger
    int m_logCounter;  // Counter for periodic logging
    
    // Direction calibration rolling window (last 50 predictions)
    int  m_directionWindow[50];  // 1=BUY, -1=SELL, 0=NONE
    int  m_directionWindowIdx;   // Circular buffer index
    int  m_directionWindowCount; // Number of filled slots (0..50)
    uint m_lastCalibrationWarningTick;  // Throttle calibration warning logs (GetTickCount-based, Issue 12.3)
    int  m_consecutiveBiasedVotes;  // Consecutive degenerate-vote counter
    datetime m_lastInvalidLog;  // FIX: Instance-level log throttle (not static)
    
    // Vote tracking for [AI-VOTE] heartbeat logs
    ulong m_voteCount;
    ulong m_buyVotes;
    ulong m_sellVotes;
    ulong m_noneVotes;
    datetime m_lastVoteLogTime;
    double m_cachedConfidence;
    
    bool IsValidConfidence(const double conf) const
    {
        return (conf == conf) && (MathAbs(conf) < 1e308) && conf >= 0.0 && conf <= 1.0;
    }
    
    void LogVoteHeartbeat()
    {
        datetime now = TimeCurrent();
        if(m_lastVoteLogTime == 0 || (now - m_lastVoteLogTime) >= 10)
        {
            PrintFormat("[AI-VOTE][NeuralNet] %s | votes=%I64u | buy=%I64u | sell=%I64u | none=%I64u | conf=%.3f | reason=%s",
                        m_symbol, m_voteCount, m_buyVotes, m_sellVotes, m_noneVotes, m_cachedConfidence, m_lastDecisionReasonTag);
            m_lastVoteLogTime = now;
        }
    }
    
    void RecordDirectionPrediction(ENUM_TRADE_SIGNAL signal)
    {
        int dirValue = 0;
        if(signal == TRADE_SIGNAL_BUY) dirValue = 1;
        else if(signal == TRADE_SIGNAL_SELL) dirValue = -1;
        
        m_directionWindow[m_directionWindowIdx] = dirValue;
        m_directionWindowIdx = (m_directionWindowIdx + 1) % 50;
        if(m_directionWindowCount < 50)
            m_directionWindowCount++;
        
        // Check and log degenerate detection
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
                PrintFormat("[AI-CALIBRATION-WARNING] Model degenerate: window_buy=%.2f, window_sell=%.2f, dir_buy=%.2f, dir_sell=%.2f, consecutive=%d | %s",
                           windowBuyRatio, windowSellRatio, dirBuyRatio, dirSellRatio, m_consecutiveBiasedVotes, m_symbol);
                m_lastCalibrationWarningTick = currentTick;
            }
        }
        else
        {
            m_consecutiveBiasedVotes = 0;
        }
    }
    
public:
    CAIStrategyAdapter(CNeuralNetworkStrategy* neuralNet)
    {
        m_neuralNet = neuralNet;
        m_enabled = true;
        m_weight = 1.0;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_lastSignalTime = 0;
        m_lastDecisionReasonTag = "NNAI_UNSET";
        m_logger = NULL;
        m_logCounter = 0;
        m_directionWindowIdx = 0;
        m_directionWindowCount = 0;
        m_lastCalibrationWarningTick = 0;
        m_consecutiveBiasedVotes = 0;
        m_lastInvalidLog = 0;
        m_voteCount = 0;
        m_buyVotes = 0;
        m_sellVotes = 0;
        m_noneVotes = 0;
        m_lastVoteLogTime = 0;
        m_cachedConfidence = 0.0;
        ArrayInitialize(m_directionWindow, 0);
    }
    
    ~CAIStrategyAdapter()
    {
        if(m_logger != NULL)
        {
            delete m_logger;
            m_logger = NULL;
        }
        // Do NOT delete m_neuralNet as it's managed externally
        m_neuralNet = NULL;
    }
    
    //+------------------------------------------------------------------+
    //| IStrategy Interface Implementation                               |
    //+------------------------------------------------------------------+
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                     void* tradeManagerPtr, void* positionSizerPtr, void* unifiedRiskManagerPtr = NULL) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_lastDecisionReasonTag = (m_neuralNet != NULL) ? "NNAI_INITIALIZED" : "NNAI_INIT_FAILED";
        
        // Initialize AI logger
        if(m_logger == NULL)
        {
            m_logger = new CSubsystemLogger();
            if(m_logger != NULL)
            {
                m_logger.Initialize(symbol, "");
                m_logger.Log(LOG_AI, StringFormat("[INIT] Neural Network AI initialized | Symbol=%s TF=%s",
                                                  symbol, EnumToString(timeframe)));
            }
        }
        
        return (m_neuralNet != NULL);
    }
    
    virtual void Deinit(void) override
    {
        m_lastDecisionReasonTag = "NNAI_DEINIT";
    }
    
virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!m_enabled || m_neuralNet == NULL)
        {
            confidence = 0.0;
            m_voteCount++;
            m_noneVotes++;
            m_lastDecisionReasonTag = "NNAI_DISABLED_OR_UNINIT";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }
        
        // Use the neural network to get signal
        ENUM_TRADE_SIGNAL signal = m_neuralNet.GetNeuralSignalCached(confidence);
        
        // Validate confidence value
        if(!IsValidConfidence(confidence))
        {
            static datetime s_lastInvalidLog = 0;
            if(s_lastInvalidLog == 0 || (TimeCurrent() - s_lastInvalidLog) >= 300)
            {
                PrintFormat("[AI-ADAPTER] Invalid confidence value: %.10f", confidence);
                s_lastInvalidLog = TimeCurrent();
            }
            confidence = 0.0;
            m_voteCount++;
            m_noneVotes++;
            m_lastDecisionReasonTag = "NNAI_INVALID_CONFIDENCE";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }
        
        m_voteCount++;
        m_cachedConfidence = confidence;
        
        // Log AI decision every 5 calls
        m_logCounter++;
        if(m_logCounter % 5 == 0 && m_logger != NULL)
        {
            string signalStr = "NONE";
            if(signal == TRADE_SIGNAL_BUY) signalStr = "BUY";
            else if(signal == TRADE_SIGNAL_SELL) signalStr = "SELL";
            
            m_logger.Log(LOG_AI, StringFormat("[PREDICTION] Signal=%s | Confidence=%.3f | Regime=%d | Temp=%.2f",
                                                  signalStr, confidence,
                                                  m_neuralNet.GetCurrentRegime(),
                                                  m_neuralNet.GetTemperature()));
            
            // Log model health stats
            m_logger.Log(LOG_AI, StringFormat("[MODEL-HEALTH] Training=%s | Steps=%d | Uncertainty=%.3f",
                                                  m_neuralNet.IsTraining() ? "YES" : "NO",
                                                  m_neuralNet.GetTrainingSteps(),
                                                  m_neuralNet.GetLastUncertainty()));
        }
        
        if(signal == TRADE_SIGNAL_BUY)
        {
            m_buyVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "NNAI_SIGNAL_BUY";
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_sellVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "NNAI_SIGNAL_SELL";
        }
        else
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "NNAI_NO_SIGNAL";
        }
        
        // Record prediction for direction calibration
        RecordDirectionPrediction(signal);
        
        LogVoteHeartbeat();
        return signal;
    }
    
    virtual void OnNewBar(void) override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}
    
    virtual string GetName(void) const override { return "Neural Network AI"; }
    
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_BRAIN; }
    
    virtual bool IsEnabled(void) const override { return m_enabled; }
    
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    
    virtual double GetWeight(void) const override { return GetCalibratedWeight(m_weight); }
    
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    
    virtual bool IsDirectionDegenerate(void) const override
    {
        if(m_directionWindowCount < 50)
            return false;
        int buyCount = 0, sellCount = 0;
        for(int i = 0; i < 50; i++)
        {
            if(m_directionWindow[i] == 1) buyCount++;
            else if(m_directionWindow[i] == -1) sellCount++;
        }
        int directionalCount = buyCount + sellCount;
        if(directionalCount < 10) return false;  // Not enough directional data
        double buyRatio = (double)buyCount / (double)directionalCount;
        double sellRatio = (double)sellCount / (double)directionalCount;
        return (buyRatio > 0.70 || sellRatio > 0.70);
    }
    
    // FIX: Disable model entirely when degenerate (not just reduce weight)
    virtual bool ShouldDisableModel(void) const override
    {
        return IsDirectionDegenerate();
    }
    
    double GetDirectionalBias(void) const
    {
        if(m_directionWindowCount < 50) return 0.0;
        int buyCount = 0, sellCount = 0;
        for(int i = 0; i < 50; i++)
        {
            if(m_directionWindow[i] == 1) buyCount++;
            else if(m_directionWindow[i] == -1) sellCount++;
        }
        int directionalCount = buyCount + sellCount;
        if(directionalCount < 10) return 0.0;
        return (double)buyCount / (double)directionalCount;
    }
    
    virtual double GetCalibratedWeight(double baseWeight) const override
    {
        if(!IsDirectionDegenerate())
            return baseWeight;
        // FIX: Return 0 to completely disable the model when degenerate
        return 0.0;
    }
    
    virtual bool ValidateParameters(void) override { return (m_neuralNet != NULL); }
    
    virtual datetime GetLastSignalTime(void) const override { return m_lastSignalTime; }
    virtual string GetLastDecisionReasonTag(void) const override { return m_lastDecisionReasonTag; }
    
    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = 0;
        successful = 0;
        accuracy = 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| IAIStrategy Interface Implementation                             |
    //+------------------------------------------------------------------+
    virtual double GetUncertainty(void) override
    {
        if(m_neuralNet == NULL)
            return 1.0;
        return m_neuralNet.GetLastUncertainty();
    }
    
    virtual bool IsModelHealthy(void) const override
    {
        return (m_neuralNet != NULL);
    }
    
    virtual bool IsTraining(void) const override
    {
        if(m_neuralNet == NULL)
            return false;
        return m_neuralNet.IsTraining();
    }
    
    virtual int GetTrainingSteps(void) const override
    {
        if(m_neuralNet == NULL)
            return 0;
        return m_neuralNet.GetTrainingSteps();
    }
    
    virtual double GetTemperature(void) const override
    {
        if(m_neuralNet == NULL)
            return 1.0;
        return m_neuralNet.GetTemperature();
    }
    
    virtual void SetTemperature(const double temperature) override
    {
        if(m_neuralNet != NULL)
            m_neuralNet.SetTemperature(temperature);
    }
    
    virtual int GetRegimeState(void) const override
    {
        if(m_neuralNet == NULL)
            return -1;
        return (int)m_neuralNet.GetCurrentRegime();
    }
    
    virtual bool SaveCheckpoint(void) override
    {
        if(m_neuralNet == NULL)
            return false;
        return m_neuralNet.SaveCheckpoint();
    }
    
    virtual string GetLastLoadStatus(void) const override
    {
        if(m_neuralNet == NULL)
            return "MODEL_NULL";
        return m_neuralNet.GetLastLoadStatus();
    }
};
