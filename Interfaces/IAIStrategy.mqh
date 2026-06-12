//+------------------------------------------------------------------+
//| IAIStrategy Interface                                            |
//| AI-specific interface extending IStrategy                        |
//+------------------------------------------------------------------+
#ifndef INTERFACES_IAISTRATEGY_MQH
#define INTERFACES_IAISTRATEGY_MQH

#include "IStrategy.mqh"

//+------------------------------------------------------------------+
//| AI Strategy Interface                                            |
//+------------------------------------------------------------------+
class IAIStrategy : public IStrategy
{
public:
    virtual ~IAIStrategy(void) {}
    
    // Get model uncertainty (0 = certain, 1 = uncertain)
    virtual double GetUncertainty(void) = 0;
    
    // Check if model is healthy (loaded, not corrupted)
    virtual bool IsModelHealthy(void) const = 0;
    
    // Get training status (true = actively training)
    virtual bool IsTraining(void) const = 0;
    
    // Get last training step count
    virtual int GetTrainingSteps(void) const = 0;
    
    // Get model temperature (for confidence calibration)
    virtual double GetTemperature(void) const = 0;
    
    // Set model temperature (T > 1 for smoother, T < 1 for sharper)
    virtual void SetTemperature(const double temperature) = 0;
    
    // Get regime detection state (-1 = unknown, 0-3 = regime index)
    virtual int GetRegimeState(void) const = 0;
    
    // Force checkpoint save
    virtual bool SaveCheckpoint(void) = 0;
    
    // Get last load status for diagnostics
    virtual string GetLastLoadStatus(void) const = 0;
    
    // Check if model direction is degenerate (stuck on one direction in recent predictions)
    virtual bool IsDirectionDegenerate(void) const { return false; }
    
    // Get calibrated weight — reduces weight by 50% if model direction is degenerate
    virtual double GetCalibratedWeight(double baseWeight) const { return baseWeight; }
};

#endif // INTERFACES_IAISTRATEGY_MQH
