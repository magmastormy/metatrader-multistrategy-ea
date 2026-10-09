// Deterministic regime + microstructure viability engine
// Thin coordinator: state lives in the Regime* modules below.
#ifndef REGIME_ENGINE_MQH
#define REGIME_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/SignalDiagnostics.mqh"

#include "RegimeTypes.mqh"
#include "RegimeComposite.mqh"
#include "RegimeVolatility.mqh"
#include "RegimeSpread.mqh"
#include "RegimeHandles.mqh"
#include "RegimeFault.mqh"
#include "RegimeTelemetry.mqh"

class CRegimeEngine
{
private:
    SRegimeConfig m_config;             // tuning parameters (RegimeTypes.mqh)
    CRegimeHandles m_handles;           // indicator handles + symbol/timeframe context
    CRegimeSpreadTracker m_spread;      // rolling spread samples + shock/cooldown
    CRegimeFaultTracker m_faults;       // fault accounting + snapshot reuse
    CRegimeTelemetry m_telemetry;       // throttled healthy-path logging

    SRegimeSnapshot m_lastSnapshot;
    CSignalDiagnostics* m_signalDiagnostics;

    //--- Forwarders (signatures unchanged, logic lives in the modules)
    void ResetHandles()
    {
        m_handles.ResetHandles();
    }

    bool TryReuseRecentSnapshot(const string symbol,
                                const ENUM_TIMEFRAMES timeframe,
                                const string reasonTag,
                                const int errorCode)
    {
        return m_faults.TryReuseRecentSnapshot(m_lastSnapshot, m_handles.GetSymbol(), m_handles.GetTimeframe(),
                                               symbol, timeframe, reasonTag, errorCode, m_config);
    }

    bool BuildFallbackIndicators(const string symbol,
                                 const ENUM_TIMEFRAMES timeframe,
                                 double &atrValue,
                                 double &bbUpperValue,
                                 double &bbLowerValue) const
    {
        return CRegimeVolatility::BuildFallbackIndicators(symbol, timeframe, m_config, atrValue, bbUpperValue, bbLowerValue);
    }

    bool ComputeRangeZScore(double &zScoreOut)
    {
        return CRegimeVolatility::ComputeRangeZScore(m_handles.GetSymbol(), m_handles.GetTimeframe(), m_config.zScoreWindow, zScoreOut);
    }

    string RegimeToString(const ENUM_REGIME_STATE state) const
    {
        return CRegimeComposite::RegimeToString(state);
    }

    //--- Self-heal: recycle handles after repeated data faults
    void NoteDataFault(const string symbol,
                       const ENUM_TIMEFRAMES timeframe,
                       const string tag,
                       const int errorCode)
    {
        if(m_faults.RegisterDataFault(tag, errorCode, m_handles.GetSymbol(), m_handles.GetTimeframe()))
        {
            ResetHandles();
            PrintFormat("[REGIME-STATE] HANDLE_RESET | symbol=%s | timeframe=%s | reason=%s | faults=%d",
                        symbol,
                        EnumToString(timeframe),
                        tag,
                        m_faults.GetConsecutiveDataFaults());
            m_faults.ClearDataFaults();
        }
    }

    bool EnsureHandles(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        bool handlesReady = m_handles.AreHandlesReady();

        // Resolve PERIOD_CURRENT to actual chart timeframe
        ENUM_TIMEFRAMES resolvedTimeframe = CRegimeHandles::ResolveTimeframe(timeframe);

        bool contextMatches = m_handles.MatchesContext(symbol, resolvedTimeframe);
        if(handlesReady && contextMatches)
            return true;

        if(!contextMatches)
        {
            m_lastSnapshot.valid = false;
            m_faults.ResetFaultState();
            m_spread.ResetShockTime();
            m_telemetry.Reset();
        }

        bool handlesCreated = m_handles.Recreate(symbol, resolvedTimeframe, m_config);
        m_spread.Reset(m_config.spreadWindow);

        return handlesCreated;
    }

public:
    CRegimeEngine()
    {
    }

    ~CRegimeEngine()
    {
        ResetHandles();
    }

    bool Initialize(const int atrPeriod = 14,
                    const int bbPeriod = 20,
                    const double bbDeviation = 2.0,
                    const int zScoreWindow = 30,
                    const int spreadWindow = 120,
                    CSignalDiagnostics* diagnostics = NULL)
    {
        m_config.ApplyInitialize(atrPeriod, bbPeriod, bbDeviation, zScoreWindow, spreadWindow);
        m_spread.Reset(m_config.spreadWindow);
        m_signalDiagnostics = diagnostics;
        return true;
    }

    void ConfigureCostLimits(const double maxSpreadToAtrRatio,
                             const int spreadShockCooldownSeconds,
                             const double lateEntryZScoreLimit)
    {
        m_config.ApplyCostLimits(maxSpreadToAtrRatio, spreadShockCooldownSeconds, lateEntryZScoreLimit);
    }

    void SetSnapshotReuseTtlSeconds(const int seconds)
    {
        m_faults.SetSnapshotReuseTtlSeconds(seconds);
    }

    bool Update(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        ENUM_TIMEFRAMES resolvedTimeframe = CRegimeHandles::ResolveTimeframe(timeframe);

        double atrValue = 0.0;
        double bbUpperValue = 0.0;
        double bbLowerValue = 0.0;
        bool usedFallback = false;

        if(!EnsureHandles(symbol, resolvedTimeframe))
        {
            int handleErr = GetLastError();
            if(!BuildFallbackIndicators(symbol, resolvedTimeframe, atrValue, bbUpperValue, bbLowerValue))
            {
                NoteDataFault(symbol, resolvedTimeframe, "HANDLE_INIT_FAILED", handleErr);
                return TryReuseRecentSnapshot(symbol, resolvedTimeframe, "HANDLE_INIT_FAILED", handleErr);
            }
            usedFallback = true;
        }

        int minBars = MathMax(m_config.bbPeriod + 5, m_config.atrPeriod + 5);
        int availableBars = Bars(symbol, resolvedTimeframe);
        int calculatedBarsBB = BarsCalculated(m_handles.GetBbHandle());
        int calculatedBarsATR = BarsCalculated(m_handles.GetAtrHandle());

        if(!usedFallback &&
           (availableBars < minBars ||
            calculatedBarsBB < minBars ||
            calculatedBarsATR < minBars))
        {
            m_lastSnapshot.readinessClass = "WARMUP";
            m_lastSnapshot.reuseActive = false;
            m_lastSnapshot.stalenessSeconds = 0;
            if(!BuildFallbackIndicators(symbol, resolvedTimeframe, atrValue, bbUpperValue, bbLowerValue))
                return TryReuseRecentSnapshot(symbol, resolvedTimeframe, "WARMUP", 0);
            usedFallback = true;
        }

        if(!usedFallback)
        {
            ResetLastError();

            // HIGH FIX: Validate handles are valid before attempting copy
            if(m_handles.GetAtrHandle() == INVALID_HANDLE || m_handles.GetBbHandle() == INVALID_HANDLE)
            {
                if(!BuildFallbackIndicators(symbol, resolvedTimeframe, atrValue, bbUpperValue, bbLowerValue))
                {
                    NoteDataFault(symbol, resolvedTimeframe, "INVALID_HANDLE", 0);
                    return TryReuseRecentSnapshot(symbol, resolvedTimeframe, "INVALID_HANDLE", 0);
                }
                usedFallback = true;
            }

            if(!usedFallback)
            {
                double atr[1];
                double bbUpper[1];
                double bbLower[1];
                int atrRet = CopyBuffer(m_handles.GetAtrHandle(), 0, 0, 1, atr);
                int upperRet = CopyBuffer(m_handles.GetBbHandle(), 1, 0, 1, bbUpper);
                int lowerRet = CopyBuffer(m_handles.GetBbHandle(), 2, 0, 1, bbLower);
                int copyErr = GetLastError();

                if(atrRet <= 0)
                {
                    if(!BuildFallbackIndicators(symbol, resolvedTimeframe, atrValue, bbUpperValue, bbLowerValue))
                    {
                        NoteDataFault(symbol, resolvedTimeframe, "ATR_BUFFER_COPY_FAILED", copyErr);
                        return TryReuseRecentSnapshot(symbol, resolvedTimeframe, "ATR_BUFFER_COPY_FAILED", copyErr);
                    }
                    usedFallback = true;
                }
                else if(upperRet <= 0 || lowerRet <= 0)
                {
                    if(!BuildFallbackIndicators(symbol, resolvedTimeframe, atrValue, bbUpperValue, bbLowerValue))
                    {
                        NoteDataFault(symbol, resolvedTimeframe, "BB_BUFFER_COPY_FAILED", copyErr);
                        return TryReuseRecentSnapshot(symbol, resolvedTimeframe, "BB_BUFFER_COPY_FAILED", copyErr);
                    }
                    usedFallback = true;
                }
                else if(atr[0] <= 0.0)
                {
                    if(!BuildFallbackIndicators(symbol, resolvedTimeframe, atrValue, bbUpperValue, bbLowerValue))
                    {
                        NoteDataFault(symbol, resolvedTimeframe, "INVALID_ATR_VALUE", 0);
                        return TryReuseRecentSnapshot(symbol, resolvedTimeframe, "INVALID_ATR_VALUE", 0);
                    }
                    usedFallback = true;
                }
                else
                {
                    atrValue = atr[0];
                    bbUpperValue = bbUpper[0];
                    bbLowerValue = bbLower[0];
                }
            }
        }

        double spreadPrice = 0.0;
        double spreadBaseline = 0.0;
        bool spreadShock = false;
        bool cooldownActive = false;
        m_spread.CaptureSpread(symbol, m_config, spreadPrice, spreadBaseline, spreadShock, cooldownActive);

        double bbWidth = MathMax(0.0, bbUpperValue - bbLowerValue);
        double bbWidthAtrRatio = (atrValue > 0.0) ? (bbWidth / atrValue) : 0.0;
        bool compression = (bbWidthAtrRatio > 0.0 && bbWidthAtrRatio <= m_config.compressionRatioThreshold);

        double zScore = 0.0;
        if(!ComputeRangeZScore(zScore))
            zScore = 0.0;

        bool lateEntryOutlier = (MathAbs(zScore) >= m_config.lateEntryZScoreLimit);
        double spreadToAtr = (atrValue > 0.0) ? (spreadPrice / atrValue) : 0.0;

        double regimeConfidence = 0.5;
        ENUM_REGIME_STATE state = CRegimeComposite::ClassifyState(cooldownActive,
                                                                  spreadToAtr,
                                                                  zScore,
                                                                  compression,
                                                                  bbWidthAtrRatio,
                                                                  m_config,
                                                                  regimeConfidence);

        int stabilityBars = 1;
        if(state == m_lastSnapshot.state && m_lastSnapshot.regimeStabilityBars > 0)
            stabilityBars = m_lastSnapshot.regimeStabilityBars + 1;
        m_faults.ClearDataFaults();
        m_lastSnapshot.valid = true;
        m_lastSnapshot.readinessClass = usedFallback ? "FALLBACK_RATES" : "HEALTHY";
        m_lastSnapshot.reuseActive = false;
        m_lastSnapshot.stalenessSeconds = 0;
        m_lastSnapshot.state = state;
        m_lastSnapshot.regimeConfidence = regimeConfidence;
        m_lastSnapshot.regimeStabilityBars = stabilityBars;
        if(stabilityBars >= 3)
            m_lastSnapshot.confirmedState = state;
        else
            m_lastSnapshot.confirmedState = m_lastSnapshot.confirmedState;
        m_lastSnapshot.compression = compression;
        m_lastSnapshot.spreadShock = spreadShock;
        m_lastSnapshot.spreadShockCooldownActive = cooldownActive;
        m_lastSnapshot.lateEntryOutlier = lateEntryOutlier;
        m_lastSnapshot.atrValue = atrValue;
        m_lastSnapshot.bbWidth = bbWidth;
        m_lastSnapshot.bbWidthAtrRatio = bbWidthAtrRatio;
        m_lastSnapshot.spreadPrice = spreadPrice;
        m_lastSnapshot.spreadBaseline = spreadBaseline;
        m_lastSnapshot.spreadToAtrRatio = spreadToAtr;
        m_lastSnapshot.rangeZScore = zScore;
        m_lastSnapshot.timestamp = TimeCurrent();

        double adxValue = CRegimeVolatility::ReadAdxValue(m_handles.GetAdxHandle(), symbol, timeframe);

        m_lastSnapshot.trendStrength = adxValue;
        m_lastSnapshot.detailedRegime = CalculateDetailedRegime(adxValue, zScore, bbWidthAtrRatio, compression);

        CalculateStrategyWeightMultipliers(
            m_lastSnapshot.detailedRegime,
            m_lastSnapshot.momentumWeightMult,
            m_lastSnapshot.trendWeightMult,
            m_lastSnapshot.meanRevWeightMult,
            m_lastSnapshot.breakoutWeightMult,
            m_lastSnapshot.ictWeightMult
        );

        datetime now = TimeCurrent();

        m_telemetry.LogDetailedRegime(m_lastSnapshot, adxValue, now);

        m_telemetry.LogRegimeState(symbol,
                                   resolvedTimeframe,
                                   state,
                                   m_lastSnapshot.confirmedState,
                                   regimeConfidence,
                                   stabilityBars,
                                   compression,
                                   spreadShock,
                                   cooldownActive,
                                   spreadToAtr,
                                   zScore,
                                   bbWidthAtrRatio,
                                   now);

        if(usedFallback)
            m_faults.LogFallbackRates(symbol, resolvedTimeframe, m_lastSnapshot.atrValue, m_lastSnapshot.bbWidth, now);

        return true;
    }

    string DetailedRegimeToString(ENUM_DETAILED_REGIME regime)
    {
        return CRegimeComposite::DetailedRegimeToString(regime);
    }

    ENUM_DETAILED_REGIME CalculateDetailedRegime(double adxValue, double zScore,
                                                  double bbWidthAtrRatio, bool compression)
    {
        return CRegimeComposite::CalculateDetailedRegime(adxValue, zScore, bbWidthAtrRatio, compression);
    }

    void CalculateStrategyWeightMultipliers(ENUM_DETAILED_REGIME regime,
                                             double &momentumMult,
                                             double &trendMult,
                                             double &meanRevMult,
                                             double &breakoutMult,
                                             double &ictMult)
    {
        CRegimeComposite::CalculateStrategyWeightMultipliers(regime, momentumMult, trendMult, meanRevMult, breakoutMult, ictMult);
    }

    SRegimeSnapshot GetSnapshot() const
    {
        return m_lastSnapshot;
    }

    // Batch 100: Apply Hurst exponent weight multipliers on top of regime multipliers
    // This modifies the snapshot's weight multipliers in-place by multiplying
    // regime-based weights with Hurst-based persistence weights
    void ApplyHurstWeightModifiers(double hurstMeanRevMult,
                                    double hurstMomentumMult,
                                    double hurstTrendMult,
                                    double hurstBreakoutMult)
    {
        CRegimeComposite::ApplyHurstWeightModifiers(m_lastSnapshot, hurstMeanRevMult, hurstMomentumMult, hurstTrendMult, hurstBreakoutMult);
    }

    string GetStateTag() const
    {
        return RegimeToString(m_lastSnapshot.state);
    }

    double GetMaxSpreadToAtrRatio() const { return m_config.maxSpreadToAtrRatio; }
    double GetLateEntryZScoreLimit() const { return m_config.lateEntryZScoreLimit; }
    ENUM_REGIME_STATE GetConfirmedState() const { return m_lastSnapshot.confirmedState; }
    double GetRegimeConfidence() const { return m_lastSnapshot.regimeConfidence; }
    int GetRegimeStabilityBars() const { return m_lastSnapshot.regimeStabilityBars; }
};

#endif // REGIME_ENGINE_MQH
