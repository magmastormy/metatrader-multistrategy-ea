//+------------------------------------------------------------------+
//| FourStateRegimeDetector.mqh                                      |
//| Four-State Market Regime Detector (MSR + KAMA)                   |
//| Combines volatility regime (MSR-inspired) with trend (KAMA)      |
//| States: LowVol-Bull, LowVol-Bear, HighVol-Bull, HighVol-Bear    |
//| Source: arXiv:2208.11574 (Springer 2023, cited 12 times)        |
//| Batch 114: New engine for regime-conditional strategy weighting  |
//+------------------------------------------------------------------+
#ifndef FOUR_STATE_REGIME_DETECTOR_MQH
#define FOUR_STATE_REGIME_DETECTOR_MQH

#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Four-State Market Regime                                          |
//+------------------------------------------------------------------+
enum ENUM_FOUR_STATE_REGIME
{
    FSTATE_LOW_VOL_BULL = 0,   // Low volatility + Bullish trend
    FSTATE_LOW_VOL_BEAR = 1,   // Low volatility + Bearish trend
    FSTATE_HIGH_VOL_BULL = 2,  // High volatility + Bullish trend
    FSTATE_HIGH_VOL_BEAR = 3   // High volatility + Bearish trend
};

//+------------------------------------------------------------------+
//| Four-State Regime Snapshot                                        |
//+------------------------------------------------------------------+
struct SFourStateSnapshot
{
    ENUM_FOUR_STATE_REGIME regime;
    double kamaValue;          // Current KAMA value
    double kamaSlope;          // KAMA direction (+1 bull, -1 bear)
    double volPercentile;      // Current vol vs 252-bar range (0-1)
    bool   isHighVol;          // volPercentile > threshold
    bool   isBullish;          // price > KAMA
    double regimeConfidence;   // 0-1 confidence in current regime
    int    barsInRegime;       // Bars since last regime change
    datetime lastChangeTime;
    datetime timestamp;

    // Strategy weight multipliers per state
    double trendWeightMult;
    double momentumWeightMult;
    double meanRevWeightMult;
    double breakoutWeightMult;
    double ictWeightMult;

    SFourStateSnapshot() :
        regime(FSTATE_LOW_VOL_BULL),
        kamaValue(0),
        kamaSlope(0),
        volPercentile(0.5),
        isHighVol(false),
        isBullish(true),
        regimeConfidence(0.5),
        barsInRegime(0),
        lastChangeTime(0),
        timestamp(0),
        trendWeightMult(1.0),
        momentumWeightMult(1.0),
        meanRevWeightMult(1.0),
        breakoutWeightMult(1.0),
        ictWeightMult(1.0)
    {}
};

//+------------------------------------------------------------------+
//| CFourStateRegimeDetector                                          |
//|                                                                  |
//| Implementation:                                                   |
//| Layer 1: Volatility regime via rolling percentile of realized vol|
//|   - Uses 50-bar realized vol (log returns)                       |
//|   - Compares to 252-bar rolling window                           |
//|   - > 75th percentile = high vol, < 25th = low vol               |
//|                                                                  |
//| Layer 2: Trend direction via KAMA (Kaufman Adaptive MA)          |
//|   - KAMA > price → bearish                                       |
//|   - KAMA < price → bullish                                       |
//|   - KAMA adapts to market efficiency (ER ratio)                  |
//|                                                                  |
//| Combined: 4 states × strategy weight multipliers                 |
//+------------------------------------------------------------------+
class CFourStateRegimeDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    // KAMA parameters
    int    m_kamaPeriod;
    int    m_kamaFastPeriod;
    int    m_kamaSlowPeriod;

    // Volatility regime parameters
    int    m_volCalcPeriod;      // Bars for realized vol calculation
    int    m_volHistoryWindow;   // Bars for percentile comparison
    double m_highVolThreshold;   // Percentile threshold for high vol (default: 0.75)
    double m_lowVolThreshold;    // Percentile threshold for low vol (default: 0.25)

    // State
    double m_kama;
    double m_kamaPrev;
    double m_volHistory[];
    int    m_volCursor;
    int    m_volCount;
    double m_currentVol;
    ENUM_FOUR_STATE_REGIME m_lastRegime;
    int    m_barsInRegime;
    int    m_barsSinceRegimeChange;  // For hysteresis
    datetime m_lastChangeTime;
    datetime m_lastBarTime;
    datetime m_lastLogTime;

    SFourStateSnapshot m_lastSnapshot;

    void ThrottledLog(const string message)
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
        {
            PrintFormat("%s", message);
            m_lastLogTime = now;
        }
    }

    //--- Compute KAMA (Kaufman Adaptive Moving Average)
    double ComputeKAMA(const double &closes[], int count) const
    {
        if(count < m_kamaPeriod + 2)
            return closes[0];

        // Direction change = |close - close[ER_period]|
        int erPeriod = m_kamaPeriod;
        double direction = MathAbs(closes[0] - closes[MathMin(erPeriod, count - 1)]);

        // Volatility = sum of |close[i] - close[i-1]| over ER period
        double volatility = 0;
        for(int i = 0; i < erPeriod && i < count - 1; i++)
            volatility += MathAbs(closes[i] - closes[i + 1]);

        // Efficiency Ratio
        double ER = (volatility > 1e-15) ? direction / volatility : 0.0;

        // Smoothing constant
        double fastSC = 2.0 / (double)(m_kamaFastPeriod + 1);
        double slowSC = 2.0 / (double)(m_kamaSlowPeriod + 1);
        double SC = ER * (fastSC - slowSC) + slowSC;
        SC = SC * SC; // Square for smoother response

        return closes[0] + SC * (m_kama - closes[0]);
    }

    //--- Compute realized volatility (annualized)
    double ComputeRealizedVol(const double &closes[], int count) const
    {
        if(count < 3) return 0;

        double returns[];
        ArrayResize(returns, count - 1);
        for(int i = 0; i < count - 1; i++)
        {
            if(closes[i + 1] > 0)
                returns[i] = MathLog(closes[i] / closes[i + 1]);
            else
                returns[i] = 0;
        }

        double sum = 0;
        for(int i = 0; i < count - 1; i++)
            sum += returns[i];
        double mean = sum / (double)(count - 1);

        double varSum = 0;
        for(int i = 0; i < count - 1; i++)
        {
            double dev = returns[i] - mean;
            varSum += dev * dev;
        }

        int barSeconds = PeriodSeconds(m_timeframe);
        if(barSeconds <= 0) barSeconds = 300;
        double barsPerYear = (252.0 * 6.5 * 3600.0) / (double)barSeconds;

        return MathSqrt(varSum / (double)(count - 2)) * MathSqrt(barsPerYear);
    }

    //--- Compute volatility percentile in history
    double ComputeVolPercentile() const
    {
        if(m_volCount < 10) return 0.5;

        int belowCount = 0;
        for(int i = 0; i < m_volCount; i++)
        {
            if(m_volHistory[i] < m_currentVol)
                belowCount++;
        }
        return (double)belowCount / (double)m_volCount;
    }

    //--- Get weight multipliers for a given state
    void GetStateWeights(ENUM_FOUR_STATE_REGIME state,
                         double &trendW, double &momentumW, double &meanRevW,
                         double &breakoutW, double &ictW) const
    {
        switch(state)
        {
            case FSTATE_LOW_VOL_BULL:
                trendW = 1.5;  momentumW = 1.2;  meanRevW = 0.8;  breakoutW = 0.7;  ictW = 1.3;
                break;
            case FSTATE_LOW_VOL_BEAR:
                trendW = 1.5;  momentumW = 1.2;  meanRevW = 0.8;  breakoutW = 0.7;  ictW = 1.3;
                break;
            case FSTATE_HIGH_VOL_BULL:
                trendW = 0.8;  momentumW = 0.9;  meanRevW = 1.5;  breakoutW = 1.8;  ictW = 1.0;
                break;
            case FSTATE_HIGH_VOL_BEAR:
                trendW = 0.8;  momentumW = 0.9;  meanRevW = 1.5;  breakoutW = 1.8;  ictW = 1.0;
                break;
            default:
                trendW = 1.0;  momentumW = 1.0;  meanRevW = 1.0;  breakoutW = 1.0;  ictW = 1.0;
                break;
        }
    }

public:
    CFourStateRegimeDetector(const string symbol = "",
                              const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT) :
        m_symbol(symbol),
        m_timeframe(timeframe),
        m_kamaPeriod(10),
        m_kamaFastPeriod(2),
        m_kamaSlowPeriod(30),
        m_volCalcPeriod(50),
        m_volHistoryWindow(252),
        m_highVolThreshold(0.75),
        m_lowVolThreshold(0.25),
        m_kama(0),
        m_kamaPrev(0),
        m_volCursor(0),
        m_volCount(0),
        m_currentVol(0),
        m_lastRegime(FSTATE_LOW_VOL_BULL),
        m_barsInRegime(0),
        m_barsSinceRegimeChange(0),
        m_lastChangeTime(0),
        m_lastBarTime(0),
        m_lastLogTime(0)
    {
        ArrayResize(m_volHistory, 252);
    }

    ~CFourStateRegimeDetector() {}

    //--- Configure
    void Configure(int kamaPeriod = 10, int volCalcPeriod = 50,
                   int volHistoryWindow = 252,
                   double highVolThreshold = 0.75, double lowVolThreshold = 0.25)
    {
        m_kamaPeriod = MathMax(5, kamaPeriod);
        m_volCalcPeriod = MathMax(10, volCalcPeriod);
        m_volHistoryWindow = MathMax(50, volHistoryWindow);
        m_highVolThreshold = MathMax(0.5, MathMin(0.95, highVolThreshold));
        m_lowVolThreshold = MathMax(0.05, MathMin(0.5, lowVolThreshold));
        ArrayResize(m_volHistory, m_volHistoryWindow);
    }

    //--- Initialize from history
    bool Initialize()
    {
        double closes[];
        ArraySetAsSeries(closes, true);
        int copied = CopyClose(m_symbol, m_timeframe, 0, m_volHistoryWindow + m_volCalcPeriod + 10, closes);
        if(copied < m_volCalcPeriod + 10)
            return false;

        // Initialize KAMA with SMA of oldest available bars
        // ArraySetAsSeries: index 0 = most recent, index copied-1 = oldest
        double sum = 0;
        int smaEnd = MathMin(m_kamaPeriod, copied);
        for(int i = copied - 1; i >= copied - smaEnd && i >= 0; i--)
            sum += closes[i];
        m_kama = sum / (double)smaEnd;
        m_kamaPrev = m_kama;

        // Warm up volatility history with proper window shifting
        m_volCount = 0;
        m_volCursor = 0;
        for(int offset = 0; offset < m_volHistoryWindow && offset + m_volCalcPeriod < copied; offset++)
        {
            // Build a window of m_volCalcPeriod closes starting at offset from the end
            double window[];
            ArrayResize(window, m_volCalcPeriod);
            for(int j = 0; j < m_volCalcPeriod; j++)
                window[j] = closes[copied - 1 - offset - j];

            double vol = ComputeRealizedVol(window, m_volCalcPeriod);
            if(vol > 0.0)
            {
                m_volHistory[m_volCursor] = vol;
                m_volCursor = (m_volCursor + 1) % m_volHistoryWindow;
                m_volCount++;
            }
        }

        // Set current vol from most recent window
        m_currentVol = (m_volCount > 0) ? m_volHistory[(m_volCursor - 1 + m_volHistoryWindow) % m_volHistoryWindow] : 0.0;

        return (m_volCount >= 10);
    }

    //--- Update: called each bar
    bool Update()
    {
        datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);
        if(currentBarTime <= 0)
            return false;
        if(currentBarTime == m_lastBarTime && m_lastSnapshot.timestamp > 0)
            return true;

        // Get closes
        double closes[];
        ArraySetAsSeries(closes, true);
        int copied = CopyClose(m_symbol, m_timeframe, 0, MathMax(m_volCalcPeriod + 10, m_kamaPeriod + 5), closes);
        if(copied < m_kamaPeriod + 2)
            return false;

        // Update KAMA
        m_kamaPrev = m_kama;
        m_kama = ComputeKAMA(closes, copied);
        double kamaSlope = (m_kama > m_kamaPrev) ? 1.0 : -1.0;

        // Determine trend direction
        bool isBullish = (closes[0] > m_kama);

        // Update volatility
        m_currentVol = ComputeRealizedVol(closes, MathMin(m_volCalcPeriod, copied));

        // Store in history
        m_volHistory[m_volCursor] = m_currentVol;
        m_volCursor = (m_volCursor + 1) % m_volHistoryWindow;
        if(m_volCount < m_volHistoryWindow) m_volCount++;

        // Compute volatility percentile
        double volPctile = ComputeVolPercentile();
        bool isHighVol = (volPctile > m_highVolThreshold);

        // Determine four-state regime
        ENUM_FOUR_STATE_REGIME newRegime;
        if(!isHighVol && isBullish)        newRegime = FSTATE_LOW_VOL_BULL;
        else if(!isHighVol && !isBullish)  newRegime = FSTATE_LOW_VOL_BEAR;
        else if(isHighVol && isBullish)    newRegime = FSTATE_HIGH_VOL_BULL;
        else                               newRegime = FSTATE_HIGH_VOL_BEAR;

        // Hysteresis: require 3 consecutive bars of new regime before switching
        // This prevents flip-flopping when vol percentile hovers around threshold
        if(newRegime != m_lastRegime)
        {
            m_barsSinceRegimeChange++;
            if(m_barsSinceRegimeChange < 3)
            {
                // Not enough consecutive bars — keep old regime
                newRegime = m_lastRegime;
            }
            else
            {
                // Regime confirmed — switch
                m_barsInRegime = 0;
                m_lastChangeTime = TimeCurrent();
                m_lastRegime = newRegime;
                m_barsSinceRegimeChange = 0;
            }
        }
        else
        {
            m_barsSinceRegimeChange = 0;
        }
        m_barsInRegime++;

        // Get weight multipliers
        double trendW, momentumW, meanRevW, breakoutW, ictW;
        GetStateWeights(newRegime, trendW, momentumW, meanRevW, breakoutW, ictW);

        // Build snapshot
        m_lastSnapshot.regime = newRegime;
        m_lastSnapshot.kamaValue = m_kama;
        m_lastSnapshot.kamaSlope = kamaSlope;
        m_lastSnapshot.volPercentile = volPctile;
        m_lastSnapshot.isHighVol = isHighVol;
        m_lastSnapshot.isBullish = isBullish;
        m_lastSnapshot.regimeConfidence = MathMin(1.0, 0.5 + MathAbs(volPctile - 0.5));
        m_lastSnapshot.barsInRegime = m_barsInRegime;
        m_lastSnapshot.lastChangeTime = m_lastChangeTime;
        m_lastSnapshot.timestamp = TimeCurrent();
        m_lastSnapshot.trendWeightMult = trendW;
        m_lastSnapshot.momentumWeightMult = momentumW;
        m_lastSnapshot.meanRevWeightMult = meanRevW;
        m_lastSnapshot.breakoutWeightMult = breakoutW;
        m_lastSnapshot.ictWeightMult = ictW;

        m_lastBarTime = currentBarTime;

        string regimeNames[] = {"LOW_VOL_BULL", "LOW_VOL_BEAR", "HIGH_VOL_BULL", "HIGH_VOL_BEAR"};
        ThrottledLog(StringFormat("[4STATE] %s | %s | KAMA=%.5f | volPct=%.2f | highVol=%s | bullish=%s | bars=%d | Trend=%.1fx MR=%.1fx BO=%.1fx",
                                   m_symbol,
                                   regimeNames[newRegime],
                                   m_kama,
                                   volPctile,
                                   isHighVol ? "H" : "L",
                                   isBullish ? "B" : "R",
                                   m_barsInRegime,
                                   trendW, meanRevW, breakoutW));

        return true;
    }

    //--- Accessors
    ENUM_FOUR_STATE_REGIME GetRegime() const { return m_lastSnapshot.regime; }
    double GetKAMA() const { return m_kama; }
    double GetVolPercentile() const { return m_lastSnapshot.volPercentile; }
    bool   IsHighVol() const { return m_lastSnapshot.isHighVol; }
    bool   IsBullish() const { return m_lastSnapshot.isBullish; }
    int    GetBarsInRegime() const { return m_lastSnapshot.barsInRegime; }

    double GetTrendWeightMult() const { return m_lastSnapshot.trendWeightMult; }
    double GetMomentumWeightMult() const { return m_lastSnapshot.momentumWeightMult; }
    double GetMeanRevWeightMult() const { return m_lastSnapshot.meanRevWeightMult; }
    double GetBreakoutWeightMult() const { return m_lastSnapshot.breakoutWeightMult; }
    double GetICTWeightMult() const { return m_lastSnapshot.ictWeightMult; }

    SFourStateSnapshot GetSnapshot() const { return m_lastSnapshot; }
};

#endif // FOUR_STATE_REGIME_DETECTOR_MQH
