//+------------------------------------------------------------------+
//| OrnsteinUhlenbeckEngine.mqh                                      |
//| OU process engine for mean-reversion z-score estimation          |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "1.0"
#property strict

#ifndef ORNSTEIN_UHLENBECK_ENGINE_MQH
#define ORNSTEIN_UHLENBECK_ENGINE_MQH

#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| OU Snapshot — full state capture for downstream consumers        |
//+------------------------------------------------------------------+
struct SOUSnapshot
{
    double theta;            // Mean-reversion speed
    double mu;               // Long-run mean
    double sigma;            // OU volatility (continuous-time corrected)
    double halfLife;         // Expected half-life in bars (ln(2)/theta)
    double ouZScore;         // OU-adjusted z-score: (X - mu) / sigma_ou
    bool   isMeanReverting;  // theta > 0 and statistically significant
    double signalQuality;    // 0.0 – 1.0 composite quality score
    double thetaTStat;       // t-statistic for theta significance
    int    barCount;         // Number of bars used in estimation
    datetime timestamp;      // When this snapshot was computed

    SOUSnapshot() :
        theta(0.0),
        mu(0.0),
        sigma(0.0),
        halfLife(0.0),
        ouZScore(0.0),
        isMeanReverting(false),
        signalQuality(0.0),
        thetaTStat(0.0),
        barCount(0),
        timestamp(0)
    {
    }
};

//+------------------------------------------------------------------+
//| COrnsteinUhlenbeckEngine                                         |
//| Estimates OU process parameters from price/spread series via     |
//| OLS regression and computes mean-reversion-adjusted z-scores.   |
//+------------------------------------------------------------------+
class COrnsteinUhlenbeckEngine
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int             m_lookbackPeriod;
    double          m_significanceLevel;

    // Estimated parameters
    double m_theta;
    double m_mu;
    double m_sigma;
    double m_halfLife;
    double m_ouZScore;
    double m_thetaTStat;
    bool   m_isMeanReverting;
    double m_signalQuality;

    // Internal state
    datetime m_lastBarTime;
    datetime m_lastLogTime;
    bool     m_warmedUp;
    int      m_barCount;

    SOUSnapshot m_lastSnapshot;

    //--- Private estimation methods
    bool EstimateParameters(const double &series[], int count);
    double ComputeSignalQuality(double thetaTStat, double halfLife, const double &residuals[], int resCount);
    double JarqueBeraStatistic(const double &residuals[], int count);

public:
    COrnsteinUhlenbeckEngine(const string symbol,
                              const ENUM_TIMEFRAMES timeframe,
                              const int lookbackPeriod = 100,
                              const double significanceLevel = 0.05);
    ~COrnsteinUhlenbeckEngine();

    //--- Main update — call each bar
    bool Update();

    //--- Accessors
    double GetOUZScore()     const { return m_ouZScore; }
    double GetHalfLife()     const { return m_halfLife; }
    bool   IsMeanReverting() const { return m_isMeanReverting; }
    double GetSignalQuality() const { return m_signalQuality; }

    void GetParameters(double &theta, double &mu, double &sigma) const
    {
        theta = m_theta;
        mu    = m_mu;
        sigma = m_sigma;
    }

    SOUSnapshot GetSnapshot() const { return m_lastSnapshot; }

    //--- Warmup check — need at least lookbackPeriod+1 bars
    bool IsWarmedUp() const { return m_lastSnapshot.barCount >= m_lookbackPeriod + 1 && m_lastSnapshot.timestamp > 0; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
COrnsteinUhlenbeckEngine::COrnsteinUhlenbeckEngine(
    const string symbol,
    const ENUM_TIMEFRAMES timeframe,
    const int lookbackPeriod,
    const double significanceLevel) :
    m_symbol(symbol),
    m_timeframe(timeframe),
    m_lookbackPeriod(MathMax(30, lookbackPeriod)),
    m_significanceLevel(MathMax(0.01, MathMin(0.10, significanceLevel))),
    m_theta(0.0),
    m_mu(0.0),
    m_sigma(0.0),
    m_halfLife(0.0),
    m_ouZScore(0.0),
    m_thetaTStat(0.0),
    m_isMeanReverting(false),
    m_signalQuality(0.0),
    m_lastBarTime(0),
    m_lastLogTime(0),
    m_warmedUp(false),
    m_barCount(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
COrnsteinUhlenbeckEngine::~COrnsteinUhlenbeckEngine()
{
}

//+------------------------------------------------------------------+
//| Update — called each bar, estimates OU parameters from closes    |
//+------------------------------------------------------------------+
bool COrnsteinUhlenbeckEngine::Update()
{
    // Bar-change guard — skip if same bar
    datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);
    if(currentBarTime <= 0)
        return false;
    if(currentBarTime == m_lastBarTime && m_warmedUp)
        return true;

    // Warmup guard — need at least lookbackPeriod bars
    int availableBars = Bars(m_symbol, m_timeframe);
    if(availableBars < m_lookbackPeriod + 1)
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
        {
            PrintFormat("[OU] WARMUP | symbol=%s | tf=%s | available=%d | need=%d",
                        m_symbol,
                        EnumToString(m_timeframe),
                        availableBars,
                        m_lookbackPeriod + 1);
            m_lastLogTime = now;
        }
        return false;
    }

    // Copy close prices (series[0] = most recent)
    double closes[];
    ArraySetAsSeries(closes, true);
    int copied = CopyClose(m_symbol, m_timeframe, 0, m_lookbackPeriod + 1, closes);
    if(copied < m_lookbackPeriod + 1)
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
        {
            PrintFormat("[OU] COPY_FAILED | symbol=%s | tf=%s | copied=%d | need=%d",
                        m_symbol,
                        EnumToString(m_timeframe),
                        copied,
                        m_lookbackPeriod + 1);
            m_lastLogTime = now;
        }
        return false;
    }

    // Estimate OU parameters
    if(!EstimateParameters(closes, copied))
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
        {
            PrintFormat("[OU] ESTIMATION_FAILED | symbol=%s | tf=%s",
                        m_symbol,
                        EnumToString(m_timeframe));
            m_lastLogTime = now;
        }
        return false;
    }

    m_lastBarTime = currentBarTime;
    m_warmedUp = true;

    // Throttled logging
    datetime now = TimeCurrent();
    if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
    {
        PrintFormat("[OU] PARAMS | symbol=%s | tf=%s | theta=%.6f | mu=%.6f | sigma=%.6f | halfLife=%.1f | z=%.3f | meanRev=%s | quality=%.2f | tStat=%.2f",
                    m_symbol,
                    EnumToString(m_timeframe),
                    m_theta,
                    m_mu,
                    m_sigma,
                    m_halfLife,
                    m_ouZScore,
                    m_isMeanReverting ? "true" : "false",
                    m_signalQuality,
                    m_thetaTStat);
        m_lastLogTime = now;
    }

    // Build snapshot
    m_lastSnapshot.theta           = m_theta;
    m_lastSnapshot.mu              = m_mu;
    m_lastSnapshot.sigma           = m_sigma;
    m_lastSnapshot.halfLife        = m_halfLife;
    m_lastSnapshot.ouZScore        = m_ouZScore;
    m_lastSnapshot.isMeanReverting = m_isMeanReverting;
    m_lastSnapshot.signalQuality   = m_signalQuality;
    m_lastSnapshot.thetaTStat      = m_thetaTStat;
    m_lastSnapshot.barCount        = m_barCount;
    m_lastSnapshot.timestamp       = TimeCurrent();

    return true;
}

//+------------------------------------------------------------------+
//| EstimateParameters — OLS regression on X(t)-X(t-1)=a+b*X(t-1)  |
//| theta = -b, mu = -a/b, sigma from residual std dev with         |
//| continuous-time correction                                       |
//+------------------------------------------------------------------+
bool COrnsteinUhlenbeckEngine::EstimateParameters(const double &series[], int count)
{
    // We need at least 2 observations for regression
    int n = count - 1; // number of delta observations
    if(n < 2)
        return false;

    // Compute OLS: delta_X = a + b * X_lag
    // X_lag[i] = series[i+1] (older), delta_X[i] = series[i] - series[i+1]
    // With ArraySetAsSeries: series[0] = newest, series[count-1] = oldest
    // So X_lag = series[i+1], X_current = series[i], delta = series[i] - series[i+1]

    double sumX  = 0.0;
    double sumY  = 0.0;
    double sumXX = 0.0;
    double sumXY = 0.0;

    for(int i = 0; i < n; i++)
    {
        double xLag   = series[i + 1];  // X(t-1)
        double deltaY = series[i] - series[i + 1]; // X(t) - X(t-1)

        sumX  += xLag;
        sumY  += deltaY;
        sumXX += xLag * xLag;
        sumXY += xLag * deltaY;
    }

    double denom = n * sumXX - sumX * sumX;
    if(MathAbs(denom) < 1e-15)
        return false;

    double b = (n * sumXY - sumX * sumY) / denom;  // slope
    double a = (sumY - b * sumX) / (double)n;       // intercept

    // theta = -b (mean-reversion speed)
    double theta = -b;

    // Edge case: near-zero or negative theta (trending, not mean-reverting)
    if(theta < 1e-10)
    {
        // Not mean-reverting — set degraded values
        m_theta           = MathMax(0.0, theta);
        m_mu              = series[0]; // fallback: current price
        m_sigma           = 0.0;
        m_halfLife        = 0.0;
        m_ouZScore        = 0.0;
        m_thetaTStat      = 0.0;
        m_isMeanReverting = false;
        m_signalQuality   = 0.0;
        m_barCount        = count;
        return true;
    }

    // mu = -a / b = -a / (-theta) = a / theta
    double mu = a / theta;

    // Compute residuals and their standard deviation
    double residuals[];
    ArrayResize(residuals, n);
    double residualSum = 0.0;

    for(int i = 0; i < n; i++)
    {
        double xLag   = series[i + 1];
        double deltaY = series[i] - series[i + 1];
        residuals[i]  = deltaY - (a + b * xLag);
        residualSum  += residuals[i];
    }

    double residualMean = residualSum / (double)n;
    double residualVar  = 0.0;
    for(int i = 0; i < n; i++)
    {
        double diff = residuals[i] - residualMean;
        residualVar += diff * diff;
    }
    residualVar /= (double)MathMax(1, n - 2); // unbiased estimator (n-2 for OLS)
    double residualStdDev = MathSqrt(MathMax(0.0, residualVar));

    // Continuous-time volatility correction:
    // sigma_ou = residualStdDev * sqrt(2*theta / (1 - exp(-2*theta*dt)))
    // where dt = 1 (one bar)
    double expTerm = MathExp(-2.0 * theta);
    double correctionDenom = 1.0 - expTerm;
    double sigmaOU = 0.0;
    if(correctionDenom > 1e-15)
        sigmaOU = residualStdDev * MathSqrt(2.0 * theta / correctionDenom);
    else
        sigmaOU = residualStdDev; // Fallback: use raw residual std dev when theta ≈ 0

    // Clamp sigmaOU to minimum floor to prevent extreme z-scores
    if(sigmaOU < residualStdDev * 0.1)
        sigmaOU = residualStdDev * 0.1;

    // Half-life = ln(2) / theta
    double halfLife = MathLog(2.0) / theta;

    // t-statistic for theta significance
    // SE(b) = residualStdDev / sqrt(sum((X_lag - mean_X)^2))
    double meanXLag = sumX / (double)n;
    double sumXDevSq = 0.0;
    for(int i = 0; i < n; i++)
    {
        double dev = series[i + 1] - meanXLag;
        sumXDevSq += dev * dev;
    }
    double seB = (sumXDevSq > 1e-15) ? residualStdDev / MathSqrt(sumXDevSq) : 1e15;
    double tStat = (seB > 1e-15) ? MathAbs(b) / seB : 0.0;

    // OU z-score: (X - mu) / sigma_ou where sigma_ou = sigma / sqrt(2*theta)
    // This accounts for mean-reversion speed
    double sigmaOUEq = (theta > 1e-10) ? sigmaOU / MathSqrt(2.0 * theta) : 1e15;
    double currentPrice = series[0];
    double ouZScore = (sigmaOUEq > 1e-15) ? (currentPrice - mu) / sigmaOUEq : 0.0;

    // Signal quality
    double quality = ComputeSignalQuality(tStat, halfLife, residuals, n);

    // Determine mean-reverting: theta > 0 and t-stat exceeds critical value
    // Approximate critical value for 5% two-tailed: ~2.0 for large n
    bool isMeanReverting = (theta > 1e-10) && (tStat > 2.0);

    // Store results
    m_theta           = theta;
    m_mu              = mu;
    m_sigma           = sigmaOU;
    m_halfLife        = halfLife;
    m_ouZScore        = ouZScore;
    m_thetaTStat      = tStat;
    m_isMeanReverting = isMeanReverting;
    m_signalQuality   = quality;
    m_barCount        = count;

    return true;
}

//+------------------------------------------------------------------+
//| ComputeSignalQuality — composite quality from three dimensions   |
//| 1. theta significance (t-stat > 2.0 = good)                     |
//| 2. half-life reasonableness (5-100 bars = good)                 |
//| 3. residual normality (Jarque-Bera approximation)               |
//+------------------------------------------------------------------+
double COrnsteinUhlenbeckEngine::ComputeSignalQuality(double thetaTStat,
                                                       double halfLife,
                                                       const double &residuals[],
                                                       int resCount)
{
    double quality = 0.0;

    // --- Dimension 1: Theta significance (weight: 0.4)
    double thetaScore = 0.0;
    if(thetaTStat >= 4.0)
        thetaScore = 1.0;
    else if(thetaTStat >= 2.0)
        thetaScore = 0.5 + 0.5 * ((thetaTStat - 2.0) / 2.0);
    else if(thetaTStat >= 1.0)
        thetaScore = 0.2 * thetaTStat;
    // else thetaScore stays 0.0
    quality += 0.4 * thetaScore;

    // --- Dimension 2: Half-life reasonableness (weight: 0.35)
    double halfLifeScore = 0.0;
    if(halfLife <= 0.0)
        halfLifeScore = 0.0; // invalid
    else if(halfLife >= 5.0 && halfLife <= 100.0)
        halfLifeScore = 1.0; // ideal range
    else if(halfLife < 5.0)
        halfLifeScore = halfLife / 5.0; // too fast — degraded
    else // halfLife > 100
        halfLifeScore = MathMax(0.0, 100.0 / halfLife); // too slow — degraded
    quality += 0.35 * halfLifeScore;

    // --- Dimension 3: Residual normality (weight: 0.25)
    double normalityScore = 0.0;
    if(resCount >= 10)
    {
        double jbStat = JarqueBeraStatistic(residuals, resCount);
        // JB statistic: under null (normality), JB ~ chi-squared(2)
        // Critical values: 5.99 at 5%, 9.21 at 1%
        if(jbStat < 5.99)
            normalityScore = 1.0;
        else if(jbStat < 9.21)
            normalityScore = 0.5;
        else
            normalityScore = MathMax(0.0, 1.0 - (jbStat - 9.21) / 20.0);
    }
    quality += 0.25 * normalityScore;

    return MathMax(0.0, MathMin(1.0, quality));
}

//+------------------------------------------------------------------+
//| JarqueBeraStatistic — test for normality of residuals            |
//| JB = (n/6) * (S^2 + (K-3)^2/4) where S=skewness, K=kurtosis    |
//+------------------------------------------------------------------+
double COrnsteinUhlenbeckEngine::JarqueBeraStatistic(const double &residuals[], int count)
{
    if(count < 10)
        return 1e6; // insufficient data — assume non-normal

    // Compute mean
    double mean = 0.0;
    for(int i = 0; i < count; i++)
        mean += residuals[i];
    mean /= (double)count;

    // Compute variance, skewness, kurtosis
    double m2 = 0.0; // second central moment
    double m3 = 0.0; // third central moment
    double m4 = 0.0; // fourth central moment

    for(int i = 0; i < count; i++)
    {
        double diff = residuals[i] - mean;
        double d2 = diff * diff;
        m2 += d2;
        m3 += d2 * diff;
        m4 += d2 * d2;
    }

    m2 /= (double)count;
    m3 /= (double)count;
    m4 /= (double)count;

    if(m2 < 1e-30)
        return 0.0; // zero variance — perfectly "normal" (degenerate)

    double skewness = m3 / MathPow(m2, 1.5);
    double kurtosis = m4 / (m2 * m2);

    double n = (double)count;
    double jb = (n / 6.0) * (skewness * skewness + (kurtosis - 3.0) * (kurtosis - 3.0) / 4.0);

    return jb;
}

#endif // ORNSTEIN_UHLENBECK_ENGINE_MQH
