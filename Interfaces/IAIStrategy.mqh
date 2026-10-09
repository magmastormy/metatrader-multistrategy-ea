// AI-specific interface extending IStrategy with capability interfaces
#ifndef INTERFACES_IAISTRATEGY_MQH
#define INTERFACES_IAISTRATEGY_MQH

#include "IStrategy.mqh"

// AI Strategy Interface - Combines all AI capability interfaces
class IAIStrategy : public IStrategy
{
public:
    virtual ~IAIStrategy(void) {}

    // --- Uncertainty Estimation ---
    virtual double GetUncertainty(void) = 0;
    virtual void GetConfidenceInterval(double &lower, double &upper) const = 0;

    virtual bool IsModelHealthy(void) const = 0;
    virtual double GetHealthScore(void) const = 0;

    virtual void EnableOnlineTraining(const bool enable) = 0;
    virtual bool TrainStep(void) = 0;
    virtual string GetTrainingState(void) const = 0;
    virtual bool IsTraining(void) const = 0;
    virtual int GetTrainingSteps(void) const = 0;

    // --- Regime Awareness ---
    virtual int GetCurrentRegime(void) const = 0;
    virtual void OnRegimeChange(const int newRegime) = 0;

    // --- Temperature Control ---
    virtual double GetTemperature(void) const = 0;
    virtual void SetTemperature(const double temperature) = 0;

        virtual bool SaveCheckpoint(void) = 0;
        virtual string GetLastLoadStatus(void) const = 0;

        // --- AI Initialization ---
        // Initialize AI model with symbol/timeframe/risk manager after factory creation
        // Returns true if initialization successful
        virtual bool InitializeAI(const string symbol, const ENUM_TIMEFRAMES timeframe, void* unifiedRiskManager) = 0;

        // --- AI-Specific Methods ---
        // Check if model direction is degenerate (stuck on one direction in recent predictions)
        virtual bool IsDirectionDegenerate(void) const { return false; }

        // Check if model should be disabled entirely (e.g., degenerate + persistent)
        virtual bool ShouldDisableModel(void) const { return false; }

        // Get calibrated weight - reduces weight by 50% if model direction is degenerate
        virtual double GetCalibratedWeight(double baseWeight) const { return baseWeight; }

        // --- AI Decision Tracking ---
        virtual datetime GetLastSignalTime(void) const = 0;
        virtual string GetLastDecisionReasonTag(void) const = 0;
    };

#endif // INTERFACES_IAISTRATEGY_MQH
