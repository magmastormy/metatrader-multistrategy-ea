//+------------------------------------------------------------------+
//| ChangepointDetector.mqh                                          |
//| Bayesian Online Changepoint Detection (Adams & MacKay 2007)     |
//| Detects regime breaks in real-time for signal gating            |
//| Batch 114: Integrates with AI pipeline as preprocessing gate    |
//+------------------------------------------------------------------+
#ifndef CHANGEPOINT_DETECTOR_MQH
#define CHANGEPOINT_DETECTOR_MQH

#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Changepoint Snapshot                                              |
//+------------------------------------------------------------------+
struct SChangepointSnapshot
{
    double hazardRate;         // P(regime change at time t)
    double runLength;          // Expected run length (mean of posterior)
    bool   changeDetected;     // True if hazard > threshold
    double confidence;         // 0-1 confidence in current regime
    int    barsSinceChange;    // Bars since last detected change
    datetime lastChangeTime;   // When last change was detected
    datetime timestamp;

    SChangepointSnapshot() :
        hazardRate(0.0),
        runLength(0.0),
        changeDetected(false),
        confidence(1.0),
        barsSinceChange(0),
        lastChangeTime(0),
        timestamp(0)
    {}
};

//+------------------------------------------------------------------+
//| CChangepointDetector — BOCPD for real-time regime break detection|
//|                                                                  |
//| Based on Adams & MacKay (2007) "Bayesian Online Changepoint      |
//| Detection". Maintains a posterior over run lengths and computes   |
//| the hazard function P(changepoint at t | data_{1:t}).            |
//|                                                                  |
//| Key insight: After a changepoint, momentum signals should be    |
//| paused/reset, and stops should be widened. This prevents the     |
//| EA from entering trades based on stale regime assumptions.       |
//+------------------------------------------------------------------+
class CChangepointDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int             m_maxRunLength;     // Maximum run length to track
    double          m_hazardThreshold;  // Threshold for change detection
    double          m_observationNoise; // Assumed observation noise (std dev)

    // Posterior over run lengths: P(run_length = r | data_{1:t})
    double m_runLengthProbs[];
    int    m_maxRL;                     // Current max tracked run length

    // Sufficient statistics for each run length (online Gaussian)
    double m_runMean[];                  // Running mean for each run length
    double m_runM2[];                    // Running M2 for Welford update
    long   m_runCount[];                 // Observation count for each run length

    // State
    double m_lastObservation;
    int    m_currentRunLength;
    int    m_barsSinceChange;
    datetime m_lastChangeTime;
    datetime m_lastBarTime;
    datetime m_lastLogTime;
    bool     m_initialized;

    SChangepointSnapshot m_lastSnapshot;

    void ThrottledLog(const string message)
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
        {
            PrintFormat("%s", message);
            m_lastLogTime = now;
        }
    }

    //--- Gaussian log-likelihood of observation given run stats
    double LogPredictiveProbability(double observation, int runIdx) const
    {
        long n = m_runCount[runIdx];
        if(n <= 1)
        {
            // Use prior: N(0, observationNoise^2)
            double var = m_observationNoise * m_observationNoise;
            return -0.5 * MathLog(2.0 * M_PI * var) - 0.5 * observation * observation / var;
        }

        double mean = m_runMean[runIdx];
        double m2 = m_runM2[runIdx];
        double var = m2 / (double)(n - 1);
        var = MathMax(var, 1e-15);

        double diff = observation - mean;
        return -0.5 * MathLog(2.0 * M_PI * var) - 0.5 * diff * diff / var;
    }

public:
    CChangepointDetector(const string symbol = "",
                          const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
                          const int maxRunLength = 200,
                          const double hazardThreshold = 0.3,
                          const double observationNoise = 0.0) :
        m_symbol(symbol),
        m_timeframe(timeframe),
        m_maxRunLength(MathMax(20, maxRunLength)),
        m_hazardThreshold(MathMax(0.05, MathMin(0.9, hazardThreshold))),
        m_observationNoise(observationNoise),
        m_maxRL(0),
        m_lastObservation(0.0),
        m_currentRunLength(0),
        m_barsSinceChange(0),
        m_lastChangeTime(0),
        m_lastBarTime(0),
        m_lastLogTime(0),
        m_initialized(false)
    {
    }

    ~CChangepointDetector() {}

    //--- Initialize from historical data
    bool Initialize()
    {
        double closes[];
        ArraySetAsSeries(closes, true);
        int copied = CopyClose(m_symbol, m_timeframe, 0, MathMin(100, m_maxRunLength), closes);
        if(copied < 20)
            return false;

        // Auto-estimate observation noise from recent returns
        if(m_observationNoise <= 0.0)
        {
            double returns[];
            ArrayResize(returns, copied - 1);
            for(int i = 0; i < copied - 1; i++)
                returns[i] = MathLog(closes[i] / closes[i + 1]);

            double sum = 0.0;
            for(int i = 0; i < copied - 1; i++)
                sum += returns[i];
            double mean = sum / (double)(copied - 1);

            double varSum = 0.0;
            for(int i = 0; i < copied - 1; i++)
            {
                double dev = returns[i] - mean;
                varSum += dev * dev;
            }
            m_observationNoise = MathSqrt(varSum / (double)(copied - 2));
            if(m_observationNoise < 1e-10)
                m_observationNoise = 0.001;
        }

        // Allocate arrays
        ArrayResize(m_runLengthProbs, m_maxRunLength + 1);
        ArrayResize(m_runMean, m_maxRunLength + 1);
        ArrayResize(m_runM2, m_maxRunLength + 1);
        ArrayResize(m_runCount, m_maxRunLength + 1);

        // Initialize: all mass on run length 0 (fresh start)
        for(int i = 0; i <= m_maxRunLength; i++)
        {
            m_runLengthProbs[i] = 0.0;
            m_runMean[i] = 0.0;
            m_runM2[i] = 0.0;
            m_runCount[i] = 0;
        }
        m_runLengthProbs[0] = 1.0;

        m_currentRunLength = 0;
        m_barsSinceChange = 0;
        m_maxRL = 0;

        // Feed historical data
        for(int i = copied - 1; i >= 0; i--)
            Update(closes[i]);

        m_initialized = true;
        return true;
    }

    //--- Core BOCPD update (call per bar or per tick)
    bool Update(double observation)
    {
        if(!m_initialized)
        {
            m_lastObservation = observation;
            return false;
        }

        int prevMaxRL = m_maxRL;

        // Ensure arrays are large enough (prevMaxRL+2 for growth term)
        int neededSize = MathMin(prevMaxRL + 2, m_maxRunLength + 1);

        // Step 1: Compute log predictive probabilities for each run length
        double logPredProbs[];
        ArrayResize(logPredProbs, neededSize);
        for(int r = 0; r <= prevMaxRL && r < neededSize; r++)
            logPredProbs[r] = LogPredictiveProbability(observation, r);

        // Step 2: Constant hazard rate (Adams & MacKay 2007, Section 3)
        // h(r) = 1 / (1 + r * λ) where λ = 1/E[run_length]
        // Using constant hazard = 1/maxRunLength for simplicity
        double hazardRate = 1.0 / MathMax(1.0, (double)m_maxRunLength);

        // Step 3: Compute log growth and changepoint probabilities in log-space
        // This avoids numerical underflow from multiplying many small probabilities
        double logCPProb = -1e300;  // log(0) ≈ -∞
        double logGrowthProbs[];
        ArrayResize(logGrowthProbs, neededSize);

        for(int r = 0; r <= prevMaxRL && r < neededSize; r++)
        {
            double logJoint = MathLog(MathMax(1e-300, m_runLengthProbs[r])) + logPredProbs[r];

            // Changepoint: mass goes to run length 0
            double logCP = logJoint + MathLog(hazardRate);
            if(logCP > logCPProb)
                logCPProb = logCP;  // log-sum-exp would be more accurate but this is simpler
            else
                logCPProb = logCPProb + MathLog(1.0 + MathExp(logCP - logCPProb));

            // Growth: mass extends to run length r+1
            logGrowthProbs[r] = logJoint + MathLog(MathMax(1e-300, 1.0 - hazardRate));
        }

        // Step 4: Normalize via log-sum-exp trick
        double logEvidence = logCPProb;
        for(int r = 0; r <= prevMaxRL && r < neededSize; r++)
        {
            if(logGrowthProbs[r] > logEvidence)
                logEvidence = logGrowthProbs[r] + MathLog(1.0 + MathExp(logEvidence - logGrowthProbs[r]));
            else
                logEvidence = logEvidence + MathLog(1.0 + MathExp(logGrowthProbs[r] - logEvidence));
        }

        if(!MathIsValidNumber(logEvidence) || logEvidence < -1e10)
        {
            // Numerical failure — reset posterior to single point
            for(int i = 0; i <= m_maxRunLength; i++)
                m_runLengthProbs[i] = 0.0;
            m_runLengthProbs[0] = 1.0;
            m_maxRL = 0;
            m_currentRunLength = 0;
            m_lastObservation = observation;
            return false;
        }

        // Step 5: Compute normalized probabilities
        double newProbs[];
        ArrayResize(newProbs, m_maxRunLength + 1);
        for(int i = 0; i <= m_maxRunLength; i++)
            newProbs[i] = 0.0;

        newProbs[0] = MathExp(logCPProb - logEvidence);
        for(int r = 0; r <= prevMaxRL && r + 1 <= m_maxRunLength; r++)
            newProbs[r + 1] = MathExp(logGrowthProbs[r] - logEvidence);

        // Step 6: Update sufficient statistics
        // Run length 0: fresh start
        m_runMean[0] = observation;
        m_runM2[0] = 0.0;
        m_runCount[0] = 1;

        // Extended run lengths: Welford online update
        for(int r = 1; r <= prevMaxRL + 1 && r <= m_maxRunLength; r++)
        {
            if(newProbs[r] > 1e-10 && r - 1 <= prevMaxRL && m_runCount[r - 1] > 0)
            {
                long n = m_runCount[r - 1] + 1;
                double delta = observation - m_runMean[r - 1];
                double newMean = m_runMean[r - 1] + delta / (double)n;
                double newM2 = m_runM2[r - 1] + delta * (observation - newMean);

                m_runMean[r] = newMean;
                m_runM2[r] = newM2;
                m_runCount[r] = n;
            }
            else if(newProbs[r] <= 1e-10)
            {
                // Prune: zero out stats for dead run lengths
                m_runMean[r] = 0.0;
                m_runM2[r] = 0.0;
                m_runCount[r] = 0;
            }
        }

        // Copy new probabilities
        for(int i = 0; i <= m_maxRunLength; i++)
            m_runLengthProbs[i] = newProbs[i];

        // Step 7: Find max run length with significant probability (prune tail)
        m_maxRL = 0;
        for(int r = MathMin(prevMaxRL + 1, m_maxRunLength); r >= 0; r--)
        {
            if(m_runLengthProbs[r] > 1e-8)
            {
                m_maxRL = r;
                break;
            }
        }

        // Step 8: Compute expected run length and hazard
        double expectedRL = 0.0;
        double totalHazard = 0.0;
        for(int r = 0; r <= m_maxRL; r++)
        {
            expectedRL += r * m_runLengthProbs[r];
            // Run-length-dependent hazard: h(r) = 1/(1 + r*lambda)
            double rlHazard = m_runLengthProbs[r] / MathMax(1.0, 1.0 + r * hazardRate);
            totalHazard += rlHazard;
        }

        // Step 9: Detect change
        bool changeDetected = (totalHazard > m_hazardThreshold);

        if(changeDetected)
        {
            m_currentRunLength = 0;
            m_barsSinceChange = 0;
            m_lastChangeTime = TimeCurrent();
        }
        else
        {
            m_currentRunLength = (int)MathRound(expectedRL);
            m_barsSinceChange++;
        }

        // Build snapshot
        m_lastSnapshot.hazardRate = totalHazard;
        m_lastSnapshot.runLength = expectedRL;
        m_lastSnapshot.changeDetected = changeDetected;
        m_lastSnapshot.confidence = MathMax(0.0, MathMin(1.0, 1.0 - totalHazard * 5.0));
        m_lastSnapshot.barsSinceChange = m_barsSinceChange;
        m_lastSnapshot.lastChangeTime = m_lastChangeTime;
        m_lastSnapshot.timestamp = TimeCurrent();

        m_lastObservation = observation;

        return true;
    }

    //--- Accessors
    double GetHazardRate() const     { return m_lastSnapshot.hazardRate; }
    double GetRunLength() const      { return m_lastSnapshot.runLength; }
    bool   IsChangeDetected() const  { return m_lastSnapshot.changeDetected; }
    double GetConfidence() const     { return m_lastSnapshot.confidence; }
    int    GetBarsSinceChange() const { return m_lastSnapshot.barsSinceChange; }

    //--- Should trading be paused? (regime just changed)
    bool ShouldPauseTrading() const
    {
        // Pause for 3 bars after a changepoint to let indicators recalibrate
        return m_barsSinceChange < 3 && m_lastChangeTime > 0;
    }

    //--- Should stops be widened? (regime uncertain)
    bool ShouldWidenStops() const
    {
        // Widen stops when hazard is elevated or recently changed
        return m_lastSnapshot.hazardRate > m_hazardThreshold * 0.5 || m_barsSinceChange < 5;
    }

    //--- Get stop widening factor (1.0 = normal, 1.5-2.0 = wider)
    double GetStopWideningFactor() const
    {
        if(m_barsSinceChange < 2)
            return 2.0;       // Very recently changed — double the stop
        if(m_barsSinceChange < 5)
            return 1.5;       // Recently changed — 50% wider
        if(m_lastSnapshot.hazardRate > m_hazardThreshold * 0.5)
            return 1.25;      // Elevated hazard — 25% wider
        return 1.0;           // Stable regime — normal stops
    }

    SChangepointSnapshot GetSnapshot() const { return m_lastSnapshot; }

    bool IsInitialized() const { return m_initialized; }
};

#endif // CHANGEPOINT_DETECTOR_MQH
