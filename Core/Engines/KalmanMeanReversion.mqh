// FLS (Su & White 2007) dynamic mean-reversion estimator: algebraically equivalent to a Kalman filter but
// with no Gaussian assumption, which is why it is used on non-Gaussian synthetic indices.
// ADVISORY ONLY — nothing trades on it: the only external callers are OrchestratorMathEngineHub's per-bar Update()
// (line 638) and shutdown Deinit() (764). Every accessor (mu/kappa/sigma/z-score/quality/half-life/mean-reverting/
// snapshot/IsWarmedUp) is uncalled repo-wide, so the throttled [KALMAN-MR] log line is the sole consumer.
#ifndef KALMAN_MEAN_REVERSION_MQH
#define KALMAN_MEAN_REVERSION_MQH

#include "../Utils/Enums.mqh"

struct SKalmanMRSnapshot
{
    double mu;               // Dynamic long-run mean (time-varying)
    double kappa;            // Dynamic mean-reversion speed (time-varying)
    double sigma;            // Estimated volatility
    double halfLife;         // ln(2)/kappa (bars)
    double kalmanZScore;     // (price - mu) / sigma_kalman
    double predictionError;  // Innovation / prediction uncertainty
    double signalQuality;    // 0-1 composite quality
    bool   isMeanReverting;  // kappa > 0 and significant
    int    barCount;         // Bars used in estimation
    datetime timestamp;

    SKalmanMRSnapshot() :
        mu(0.0),
        kappa(0.0),
        sigma(0.0),
        halfLife(0.0),
        kalmanZScore(0.0),
        predictionError(0.0),
        signalQuality(0.0),
        isMeanReverting(false),
        barCount(0),
        timestamp(0)
    {}
};

// State [mu, kappa]; observation price_t = mu_t + noise; transition mu_{t+1} = mu_t + kappa_t*(mu_t - price_t) + w.
// lambda is the FLS penalty, i.e. the adaptation speed: clamped to >= 10 by the ctor and Configure(), default 500 (OrchestratorConfig.kalmanLambda is also 500).
// Small lambda tracks noise, large goes near-static OLS; lambda = 0 and infinity are not reachable. UpdateCovariance scales it 0.4x (floor 10) on a variance spike
// and 2.5x (cap 10000) in a quiet stretch.
class CKalmanMeanReversion
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int             m_lookbackPeriod;
    double          m_lambda;        // FLS smoothing parameter
    double          m_forgettingFactor; // Exponential decay for old data

    double m_mu;               // Current estimate of long-run mean
    double m_kappa;            // Current estimate of reversion speed
    double m_P_mu_mu;          // Variance of mu estimate
    double m_P_mu_kappa;       // Covariance of mu and kappa
    double m_P_kappa_kappa;    // Variance of kappa estimate
    double m_sigma;            // Estimated residual volatility (EWMA)
    double m_sigmaSq;          // EWMA variance (avoids sqrt+square round-trip)
    double m_lastZScore;       // Cached z-score for accessor
    double m_lastInnovation;   // Most recent innovation for diagnostics

    datetime m_lastBarTime;
    datetime m_lastLogTime;
    bool     m_warmedUp;
    int      m_barCount;

    SKalmanMRSnapshot m_lastSnapshot;

    double ComputeResidual(double price, double mu, double kappa, double prevPrice) const
    {
        double predictedMu = mu + kappa * (mu - prevPrice);
        return price - predictedMu;
    }

    void UpdateCovariance(double innovationVariance)
    {
        // Penalty adapts: raised in a quiet stretch, cut when innovation variance jumps.
        double adaptLambda = m_lambda;
        if(m_barCount > 20 && m_sigmaSq > 1e-20)
        {
            // The "recent" variance is the caller's innovation variance (sigmaSq + P_mu_mu) against the EWMA variance alone — not the same basis.
            double recentVar = innovationVariance;
            double ratio = (m_sigmaSq > 1e-20) ? recentVar / m_sigmaSq : 1.0;

            if(ratio > 2.5)
                adaptLambda = MathMax(10.0, adaptLambda * 0.4);   // Regime change → faster tracking
            else if(ratio < 0.4)
                adaptLambda = MathMin(10000.0, adaptLambda * 2.5); // Stable → slower tracking
        }

        double invLambda = 1.0 / MathMax(1.0, adaptLambda);

        // FLS covariance update P_new = (1/lambda)*P_old + Q, with Q scaled by the innovation variance.
        m_P_mu_mu     = invLambda * m_P_mu_mu + innovationVariance * 0.05;
        m_P_mu_kappa  = invLambda * m_P_mu_kappa;
        m_P_kappa_kappa = invLambda * m_P_kappa_kappa + innovationVariance * 0.005;

        // PSD guard: floor both variances, and zero the cross-covariance if the determinant collapses.
        m_P_mu_mu = MathMax(1e-12, m_P_mu_mu);
        m_P_kappa_kappa = MathMax(1e-12, m_P_kappa_kappa);
        double det = m_P_mu_mu * m_P_kappa_kappa - m_P_mu_kappa * m_P_mu_kappa;
        if(det < 1e-24)
        {
            m_P_mu_kappa = 0.0;
            m_P_kappa_kappa = MathMax(1e-12, m_P_kappa_kappa);
        }
    }

    void ThrottledLog(const string message)
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
        {
            PrintFormat("%s", message);
            m_lastLogTime = now;
        }
    }

public:
    CKalmanMeanReversion(const string symbol = "",
                          const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
                          const int lookbackPeriod = 200,
                          const double lambda = 500.0) :
        m_symbol(symbol),
        m_timeframe(timeframe),
        m_lookbackPeriod(MathMax(50, lookbackPeriod)),
        m_lambda(MathMax(10.0, lambda)),
        m_forgettingFactor(0.995),
        m_mu(0.0),
        m_kappa(0.0),
        m_P_mu_mu(1.0),
        m_P_mu_kappa(0.0),
        m_P_kappa_kappa(1.0),
        m_sigma(0.0),
        m_sigmaSq(0.0),
        m_lastZScore(0.0),
        m_lastInnovation(0.0),
        m_lastBarTime(0),
                m_lastLogTime(0),
                m_warmedUp(false),
                m_barCount(0)
            {
                ResolveTimeframe();
            }

            ~CKalmanMeanReversion() {}

            void ResolveTimeframe()
            {
                if(m_timeframe == PERIOD_CURRENT || m_timeframe == 0)
                    m_timeframe = Period();
            }

    void Configure(double lambda, double forgettingFactor)
    {
        m_lambda = MathMax(10.0, lambda);
        m_forgettingFactor = MathMax(0.90, MathMin(1.0, forgettingFactor));
    }

    //--- Cold start: returns false unless CopyClose delivers the FULL m_lookbackPeriod bars (no partial warm-up); Update() retries it on every call while m_warmedUp stays false.
    bool InitializeFromHistory()
    {
        if(m_timeframe == PERIOD_CURRENT || m_timeframe == 0)
            m_timeframe = Period();
        
        double closes[];
        ArraySetAsSeries(closes, true);
        int copied = CopyClose(m_symbol, m_timeframe, 0, m_lookbackPeriod, closes);
        if(copied < m_lookbackPeriod)
            return false;

        double sum = 0.0;
        for(int i = 0; i < copied; i++)
            sum += closes[i];
        m_mu = sum / (double)copied;

        // Bootstrap kappa from OLS on the differenced series: dX = a + b*X_lag, kappa = -b.
        double sumX = 0, sumY = 0, sumXX = 0, sumXY = 0;
        int n = copied - 1;
        for(int i = 0; i < n; i++)
        {
            // closes[0] = most recent, closes[copied-1] = oldest
            double xLag = closes[i + 1];
            double deltaY = closes[i] - closes[i + 1];
            sumX += xLag;
            sumY += deltaY;
            sumXX += xLag * xLag;
            sumXY += xLag * deltaY;
        }
        double denom = (double)n * sumXX - sumX * sumX;
        if(MathAbs(denom) > 1e-15)
        {
            double b = ((double)n * sumXY - sumX * sumY) / denom;
            m_kappa = MathMax(0.001, MathMin(2.0, -b));
        }
        else
            m_kappa = 0.05;

        // Bootstrap sigma comes from UNDEMEANED log returns (return units); FLSUpdate then EWMA-blends price-unit innovations into the same variable.
        double varSum = 0.0;
        for(int i = 0; i < copied - 1; i++)
        {
            double ret = MathLog(closes[i] / MathMax(1e-15, closes[i + 1]));
            varSum += ret * ret;
        }
        m_sigmaSq = varSum / (double)(copied - 1);
        m_sigma = MathSqrt(MathMax(1e-20, m_sigmaSq));

        m_barCount = 0;

        // Feed historical data oldest-first for proper warmup
        for(int i = copied - 1; i >= 0; i--)
        {
            m_barCount++;
            FLSUpdate(closes[i]);
        }

        m_warmedUp = true;
        return true;
    }

    //--- Core FLS update, fed once per BAR (Update() -> FLSUpdate(closes[0]) from the hub's bar sweep); MathematicalEngineRegistry::OnTickAll would feed ticks but has no caller in this repo.
    void FLSUpdate(double price)
    {
        if(!m_warmedUp)
        {
            m_mu = price;
            m_warmedUp = true;
            m_lastZScore = 0.0;
            return;
        }

        // OU-style prediction: mu moves toward the observed price at rate kappa.
        double predictedMu = m_mu + m_kappa * (m_mu - price);

        double innovation = price - predictedMu;
        m_lastInnovation = innovation;

        double innovVar = innovation * innovation;
        if(m_barCount <= 1)
        {
            m_sigmaSq = innovVar;
            m_sigma = MathSqrt(innovVar);
        }
        else
        {
            m_sigmaSq = m_forgettingFactor * m_sigmaSq + (1.0 - m_forgettingFactor) * innovVar;
            m_sigma = MathSqrt(MathMax(1e-20, m_sigmaSq));
        }

        double innovationVariance = m_sigmaSq + m_P_mu_mu;
        double K_mu = (innovationVariance > 1e-15) ? m_P_mu_mu / innovationVariance : 0.5;

        // K_kappa = P_mu_kappa/innovationVariance, but m_P_mu_kappa starts at 0 and is only ever multiplied by 1/lambda or reset to 0 — nothing drives it, so K_kappa stays 0 and kappa keeps its cold-start OLS value.
        double K_kappa = (innovationVariance > 1e-15) ? m_P_mu_kappa / innovationVariance : 0.0;

        m_mu = predictedMu + K_mu * innovation;
        m_kappa = m_kappa + K_kappa * innovation;

        // Clamp to [0.001, 2.0] discards the sign, so a trending (negative-kappa) series reports as weak reversion — and with K_kappa dead it only clamps the bootstrap value.
        m_kappa = MathMax(0.001, MathMin(2.0, m_kappa));

        UpdateCovariance(innovationVariance);

        // Ad-hoc extra pull of mu toward price, 0.05 (kappa>=1) to 0.15 (kappa~0) of the gap per update.
        double pullRate = MathMin(0.2, 0.05 + 0.1 * (1.0 - MathMin(1.0, m_kappa)));
        m_mu = m_mu + pullRate * (price - m_mu);

        m_lastZScore = (m_sigma > 1e-15) ? (price - m_mu) / m_sigma : 0.0;
    }

    double ComputeZScore(double currentPrice) const
    {
        if(m_sigma < 1e-15)
            return 0.0;

        // (price - mu)/sigma in price units, 0.0 (not NaN) when sigma is unusable. No caller — the snapshot carries m_lastZScore, written by FLSUpdate.
        double spread = currentPrice - m_mu;
        return spread / m_sigma;
    }

    //--- Half-width (price units) of the 95% band around mu; only ComputeSignalQuality reads it, nothing adapts a threshold from it.
    double GetPredictionIntervalWidth() const
    {
        // 95% prediction interval: ±1.96 * sqrt(P_mu_mu + sigma^2)
        double totalUncertainty = MathSqrt(m_P_mu_mu + m_sigma * m_sigma);
        return 1.96 * totalUncertainty;
    }

    double ComputeSignalQuality() const
    {
        double quality = 0.0;

        // Dimension 1 (weight 0.4): kappa/0.5 capped at 1 — larger kappa scores higher.
        double kappaScore = MathMin(1.0, m_kappa / 0.5); // 0.5 is "strong" reversion
        quality += 0.4 * kappaScore;

        // Dimension 2 (weight 0.35): half-life in bars scores 1.0 inside [5,100], ramps below 5, decays as 100/hl above.
        double hl = GetHalfLife();
        double hlScore = 0.0;
        if(hl >= 5.0 && hl <= 100.0)
            hlScore = 1.0;
        else if(hl < 5.0)
            hlScore = hl / 5.0;
        else
            hlScore = MathMax(0.0, 100.0 / hl);
        quality += 0.35 * hlScore;

        // Dimension 3 (weight 0.25): 1 - PI width/(5*sigma), 0.5 when sigma is unusable.
        double uncertainty = GetPredictionIntervalWidth();
        double priceRange = m_sigma * 5.0; // rough price range
        double uncScore = (priceRange > 1e-15) ? MathMax(0.0, 1.0 - uncertainty / priceRange) : 0.5;
        quality += 0.25 * uncScore;

        return MathMax(0.0, MathMin(1.0, quality));
    }

    //--- Bar-level driver: returns true without recomputation if this bar was already consumed; returns false (and retries next call) when iTime/CopyClose give no data or the cold start fails.
    bool Update()
    {
        datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);
        if(currentBarTime <= 0)
            return false;
        if(currentBarTime == m_lastBarTime && m_warmedUp)
            return true;

        if(!m_warmedUp)
        {
            if(!InitializeFromHistory())
            {
                ThrottledLog(StringFormat("[KALMAN-MR] INIT_FAILED | symbol=%s | tf=%s",
                                           m_symbol, EnumToString(m_timeframe)));
                return false;
            }
        }

        double closes[];
        ArraySetAsSeries(closes, true);
        int copied = CopyClose(m_symbol, m_timeframe, 0, MathMin(5, m_lookbackPeriod), closes);
        if(copied <= 0)
            return false;

        FLSUpdate(closes[0]);

        m_lastBarTime = currentBarTime;
        // copied is at most 5 here, overwriting the lookback-bar warm-up count, so IsWarmedUp() (needs barCount >= 10) reads false from the second bar on. No caller uses it.
        m_barCount = copied;

        m_lastSnapshot.mu = m_mu;
        m_lastSnapshot.kappa = m_kappa;
        m_lastSnapshot.sigma = m_sigma;
        m_lastSnapshot.halfLife = GetHalfLife();
        m_lastSnapshot.kalmanZScore = m_lastZScore;
        m_lastSnapshot.predictionError = MathAbs(closes[0] - m_mu);
        m_lastSnapshot.signalQuality = ComputeSignalQuality();
        m_lastSnapshot.isMeanReverting = (m_kappa > 0.01);
        m_lastSnapshot.barCount = m_barCount;
        m_lastSnapshot.timestamp = TimeCurrent();

        ThrottledLog(StringFormat("[KALMAN-MR] %s | mu=%.5f | kappa=%.4f | sigma=%.5f | hl=%.1f | z=%.3f | quality=%.2f | meanRev=%s",
                                   m_symbol,
                                   m_mu,
                                   m_kappa,
                                   m_sigma,
                                   m_lastSnapshot.halfLife,
                                   m_lastSnapshot.kalmanZScore,
                                   m_lastSnapshot.signalQuality,
                                   m_lastSnapshot.isMeanReverting ? "true" : "false"));

        return true;
    }

    double GetMu() const              { return m_mu; }
    double GetKappa() const           { return m_kappa; }
    double GetSigma() const           { return m_sigma; }
    double GetHalfLife() const        { return (m_kappa > 1e-10) ? MathLog(2.0) / m_kappa : 999.0; }
    double GetZScore() const          { return m_lastZScore; }
    double GetSignalQuality() const   { return ComputeSignalQuality(); }
    bool   IsMeanReverting() const    { return m_kappa > 0.01; }

    SKalmanMRSnapshot GetSnapshot() const { return m_lastSnapshot; }

    bool IsWarmedUp() const { return m_warmedUp && m_barCount >= 10; }

        void Deinit()
        {
            // No indicator handles or external resources here — state reset only; the hub calls this before delete.
            m_mu = 0.0;
            m_kappa = 0.0;
            m_P_mu_mu = 1.0;
            m_P_mu_kappa = 0.0;
            m_P_kappa_kappa = 1.0;
            m_sigma = 0.0;
            m_sigmaSq = 0.0;
            m_lastZScore = 0.0;
            m_lastInnovation = 0.0;
            m_lastBarTime = 0;
            m_lastLogTime = 0;
            m_warmedUp = false;
            m_barCount = 0;
            m_lastSnapshot = SKalmanMRSnapshot();
        }
    };

#endif // KALMAN_MEAN_REVERSION_MQH
