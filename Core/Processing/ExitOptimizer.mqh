//+------------------------------------------------------------------+
//| ExitOptimizer.mqh                                                |
//| Advanced exit optimization module                                |
//| Chandelier exits, R-multiple partials, OU-based TP, time exits   |
//| Batch 114: Research-driven exit improvements                     |
//+------------------------------------------------------------------+
#ifndef EXIT_OPTIMIZER_MQH
#define EXIT_OPTIMIZER_MQH

#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Exit Optimization Configuration                                   |
//+------------------------------------------------------------------+
struct SExitConfig
{
    // Chandelier Exit
    bool   useChandelier;          // Enable Chandelier exit (default: true)
    int    chandelierPeriod;       // ATR period for Chandelier (default: 22)
    double chandelierMultiplier;   // ATR multiplier (default: 3.0)

    // R-Multiple Partials
    bool   useRMultiplePartials;   // Enable R-multiple partials (default: true)
    double partial1RMultiple;      // R level for first partial (default: 1.0)
    double partial1Percent;        // % to close at partial 1 (default: 0.25)
    double partial2RMultiple;      // R level for second partial (default: 2.0)
    double partial2Percent;        // % to close at partial 2 (default: 0.25)
    double partial3RMultiple;      // R level for third partial (default: 3.0)
    double partial3Percent;        // % to close at partial 3 (default: 0.25)

    // OU-Based TP
    bool   useOUTarget;           // Enable OU half-life TP (default: true)
    double ouMaxTargetBars;       // Max bars for OU target (default: 50)

    // Time-Based Exits
    bool   useTimeExit;           // Enable time-based exit (default: true)
    int    maxHoldingBarsDefault; // Default max holding bars (default: 48 on M5)
    int    maxHoldingBarsHighVol; // Max holding bars in high vol (default: 24)

    // Volatility-Adjusted TP
    bool   useVolAdjustedTP;      // Enable vol-adjusted TP (default: true)
    double baseTPMultiplier;      // Base TP = ATR * multiplier (default: 2.0)
    double lowVolTPMultiplier;    // TP multiplier in low vol (default: 1.5)
    double highVolTPMultiplier;   // TP multiplier in high vol (default: 2.5)
    double trendTPMultiplier;     // TP multiplier in trend (default: 3.0)

    SExitConfig() :
        useChandelier(true),
        chandelierPeriod(22),
        chandelierMultiplier(3.0),
        useRMultiplePartials(true),
        partial1RMultiple(1.0),
        partial1Percent(0.25),
        partial2RMultiple(2.0),
        partial2Percent(0.25),
        partial3RMultiple(3.0),
        partial3Percent(0.25),
        useOUTarget(true),
        ouMaxTargetBars(50),
        useTimeExit(true),
        maxHoldingBarsDefault(48),
        maxHoldingBarsHighVol(24),
        useVolAdjustedTP(true),
        baseTPMultiplier(2.0),
        lowVolTPMultiplier(1.5),
        highVolTPMultiplier(2.5),
        trendTPMultiplier(3.0)
    {}
};

//+------------------------------------------------------------------+
//| Exit Action Types                                                 |
//+------------------------------------------------------------------+
enum ENUM_EXIT_ACTION
{
    EXIT_ACTION_NONE = 0,
    EXIT_ACTION_CLOSE_FULL,       // Close entire position
    EXIT_ACTION_CLOSE_PARTIAL,    // Close partial (size from config)
    EXIT_ACTION_MOVE_SL,          // Move stop loss
    EXIT_ACTION_WIDEN_SL          // Widen stop loss (regime change)
};

//+------------------------------------------------------------------+
//| Exit Decision Structure                                           |
//+------------------------------------------------------------------+
struct SExitDecision
{
    ENUM_EXIT_ACTION action;
    double           newSL;           // New stop loss price
    double           closeFraction;   // Fraction of position to close (0-1)
    string           reason;
    double           confidence;      // 0-1

    SExitDecision() :
        action(EXIT_ACTION_NONE),
        newSL(0),
        closeFraction(0),
        reason(""),
        confidence(0)
    {}
};

//+------------------------------------------------------------------+
//| CExitOptimizer — Advanced exit management                        |
//|                                                                  |
//| Research findings implemented:                                    |
//| - Chandelier Exit (Le Beau 2000): uses highest-high since entry  |
//|   instead of current price, prevents premature tightening        |
//| - R-Multiple Partials: systematic profit taking at 1R, 2R, 3R   |
//| - OU Half-Life TP: target based on mean-reversion speed          |
//| - Time Exits: alpha decays after 1-5 days (Jegadeesh & Titman)  |
//| - Vol-Adjusted TP: wider targets in high-vol regimes             |
//+------------------------------------------------------------------+
class CExitOptimizer
{
private:
    SExitConfig m_config;
    string      m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    // Indicator handles
    int m_atrHandle;

    // Position tracking
    double m_entryPrice;
    double m_initialSL;
    double m_initialRisk;       // |entry - SL| = 1R
    int    m_barsHeld;
    int    m_partialsTaken;     // Bitmask: bit0=p1, bit1=p2, bit2=p3
    double m_highestSinceEntry; // For Chandelier
    double m_lowestSinceEntry;  // For Chandelier

    // Regime context
    bool   m_isHighVol;
    bool   m_isTrending;

    // OU context (injected from Kalman engine)
    double m_ouHalfLife;
    double m_ouMu;

    datetime m_lastBarTime;
    datetime m_lastLogTime;  // Per-instance log timer (was static — shared across instances)

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
    CExitOptimizer() :
        m_atrHandle(INVALID_HANDLE),
        m_entryPrice(0),
        m_initialSL(0),
        m_initialRisk(0),
        m_barsHeld(0),
        m_partialsTaken(0),
        m_highestSinceEntry(0),
        m_lowestSinceEntry(0),
        m_isHighVol(false),
        m_isTrending(false),
        m_ouHalfLife(0),
        m_ouMu(0),
        m_lastBarTime(0)
    {
    }

    ~CExitOptimizer()
    {
        if(m_atrHandle != INVALID_HANDLE)
            IndicatorRelease(m_atrHandle);
    }

    //--- Initialize
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_atrHandle = iATR(symbol, timeframe, 14);
        return (m_atrHandle != INVALID_HANDLE);
    }

    //--- Configure
    void Configure(const SExitConfig &config)
    {
        m_config = config;
    }

    //--- Set trade context (call when position opens)
    void SetTradeContext(double entryPrice, double initialSL)
    {
        m_entryPrice = entryPrice;
        m_initialSL = initialSL;
        m_initialRisk = MathAbs(entryPrice - initialSL);
        m_barsHeld = 0;
        m_partialsTaken = 0;
        m_highestSinceEntry = entryPrice;
        m_lowestSinceEntry = entryPrice;
    }

    //--- Inject OU parameters (from KalmanMeanReversion engine)
    void SetOUContext(double halfLife, double mu)
    {
        m_ouHalfLife = halfLife;
        m_ouMu = mu;
    }

    //--- Inject regime context
    void SetRegimeContext(bool isHighVol, bool isTrending)
    {
        m_isHighVol = isHighVol;
        m_isTrending = isTrending;
    }

    //--- Get current ATR
    double GetATR() const
    {
        if(m_atrHandle == INVALID_HANDLE) return 0;
        double atr[1];
        if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) == 1)
            return atr[0];
        return 0;
    }

    //--- Compute Chandelier Exit level
    double ComputeChandelierExit(bool isLong) const
    {
        if(!m_config.useChandelier) return 0;

        double atr = GetATR();
        if(atr <= 0) return 0;

        if(isLong)
            return m_highestSinceEntry - m_config.chandelierMultiplier * atr;
        else
            return m_lowestSinceEntry + m_config.chandelierMultiplier * atr;
    }

    //--- Compute volatility-adjusted take profit
    double ComputeVolAdjustedTP(bool isLong) const
    {
        if(!m_config.useVolAdjustedTP) return 0;

        double atr = GetATR();
        if(atr <= 0) return 0;

        double multiplier = m_config.baseTPMultiplier;
        if(m_isHighVol)
            multiplier = m_config.highVolTPMultiplier;
        else if(m_isTrending)
            multiplier = m_config.trendTPMultiplier;
        // Low vol uses default base multiplier (already set)

        if(isLong)
            return m_entryPrice + atr * multiplier;
        else
            return m_entryPrice - atr * multiplier;
    }

    //--- Compute OU-based take profit
    double ComputeOUTarget(bool isLong) const
    {
        if(!m_config.useOUTarget || m_ouHalfLife <= 0 || m_ouMu <= 0)
            return 0;

        // Target = mu (long-run mean) — this is the natural reversion target
        // But only if it's in the right direction
        if(isLong && m_ouMu > m_entryPrice)
            return m_ouMu;
        else if(!isLong && m_ouMu < m_entryPrice)
            return m_ouMu;

        return 0; // OU target not applicable (would be counter-trend)
    }

    //--- Compute time-based exit threshold
    int GetMaxHoldingBars() const
    {
        if(!m_config.useTimeExit) return 9999;
        return m_isHighVol ? m_config.maxHoldingBarsHighVol : m_config.maxHoldingBarsDefault;
    }

    //--- Check R-multiple partial levels
    // Returns which partial to take (0=none, 1/2/3)
    // Takes partials in order — if price jumped from 0R to 3R, takes partial 1 first
    int CheckRMultiplePartials(double currentPrice, bool isLong) const
    {
        if(!m_config.useRMultiplePartials || m_initialRisk <= 0)
            return 0;

        double currentR;
        if(isLong)
            currentR = (currentPrice - m_entryPrice) / m_initialRisk;
        else
            currentR = (m_entryPrice - currentPrice) / m_initialRisk;

        // Check in order: partial 1 first, then 2, then 3
        // This ensures we don't skip a level on a large move
        if(!(m_partialsTaken & 1) && currentR >= m_config.partial1RMultiple)
            return 1;
        if(!(m_partialsTaken & 2) && currentR >= m_config.partial2RMultiple)
            return 2;
        if(!(m_partialsTaken & 4) && currentR >= m_config.partial3RMultiple)
            return 3;

        return 0;
    }

    //--- Get partial close fraction
    double GetPartialFraction(int partialLevel) const
    {
        switch(partialLevel)
        {
            case 1: return m_config.partial1Percent;
            case 2: return m_config.partial2Percent;
            case 3: return m_config.partial3Percent;
            default: return 0;
        }
    }

    //--- Main evaluation: called each bar with current price
    SExitDecision Evaluate(double currentPrice, bool isLong)
    {
        SExitDecision decision;
        m_barsHeld++;

        // Update highest/lowest since entry
        if(currentPrice > m_highestSinceEntry)
            m_highestSinceEntry = currentPrice;
        if(currentPrice < m_lowestSinceEntry)
            m_lowestSinceEntry = currentPrice;

        // 1. Check time-based exit (highest priority — force close)
        if(m_config.useTimeExit && m_barsHeld >= GetMaxHoldingBars())
        {
            double currentR;
            if(isLong)
                currentR = (currentPrice - m_entryPrice) / MathMax(1e-10, m_initialRisk);
            else
                currentR = (m_entryPrice - currentPrice) / MathMax(1e-10, m_initialRisk);

            // Only force exit if not profitable
            if(currentR < 0.5)
            {
                decision.action = EXIT_ACTION_CLOSE_FULL;
                decision.reason = StringFormat("TIME_EXIT | bars=%d/%d | R=%.2f",
                                                m_barsHeld, GetMaxHoldingBars(), currentR);
                decision.confidence = 0.8;
                return decision;
            }
        }

        // 2. Check R-multiple partials
        int partialLevel = CheckRMultiplePartials(currentPrice, isLong);
        if(partialLevel > 0)
        {
            double fraction = GetPartialFraction(partialLevel);
            if(fraction > 0 && fraction < 1.0)
            {
                decision.action = EXIT_ACTION_CLOSE_PARTIAL;
                decision.closeFraction = fraction;
                decision.reason = StringFormat("R_MULTIPLE_PARTIAL_%d | fraction=%.0f%%",
                                                partialLevel, fraction * 100);
                decision.confidence = 0.9;

                // Mark partial as taken
                m_partialsTaken |= (1 << (partialLevel - 1));

                // Move SL to breakeven after first partial
                if(partialLevel == 1)
                {
                    decision.newSL = m_entryPrice; // Breakeven
                }
                // Trail SL after second partial
                else if(partialLevel == 2)
                {
                    double atr = GetATR();
                    if(isLong)
                        decision.newSL = currentPrice - 1.5 * atr;
                    else
                        decision.newSL = currentPrice + 1.5 * atr;
                }
                return decision;
            }
        }

        // 3. Chandelier exit check
        if(m_config.useChandelier)
        {
            double chandelier = ComputeChandelierExit(isLong);
            if(chandelier > 0)
            {
                bool chandelierTriggered = isLong ? (currentPrice < chandelier) : (currentPrice > chandelier);
                if(chandelierTriggered)
                {
                    decision.action = EXIT_ACTION_CLOSE_FULL;
                    decision.reason = StringFormat("CHANDELIER_EXIT | level=%.5f | price=%.5f",
                                                    chandelier, currentPrice);
                    decision.confidence = 0.85;
                    return decision;
                }

                // Move SL to Chandelier level if it's better than current SL
                // (This is handled by the position lifecycle manager)
            }
        }

        // 4. OU-based TP check
        if(m_config.useOUTarget)
        {
            double ouTarget = ComputeOUTarget(isLong);
            if(ouTarget > 0)
            {
                bool ouTargetReached = isLong ? (currentPrice >= ouTarget) : (currentPrice <= ouTarget);
                if(ouTargetReached)
                {
                    decision.action = EXIT_ACTION_CLOSE_FULL;
                    decision.reason = StringFormat("OU_TARGET | target=%.5f | price=%.5f | hl=%.1f",
                                                    ouTarget, currentPrice, m_ouHalfLife);
                    decision.confidence = 0.75;
                    return decision;
                }
            }
        }

        // 5. Vol-adjusted TP check
        if(m_config.useVolAdjustedTP)
        {
            double volTP = ComputeVolAdjustedTP(isLong);
            if(volTP > 0)
            {
                bool volTPReached = isLong ? (currentPrice >= volTP) : (currentPrice <= volTP);
                if(volTPReached)
                {
                    decision.action = EXIT_ACTION_CLOSE_FULL;
                    decision.reason = StringFormat("VOL_ADJUSTED_TP | tp=%.5f | price=%.5f",
                                                    volTP, currentPrice);
                    decision.confidence = 0.7;
                    return decision;
                }
            }
        }

        // 6. No exit needed
        decision.action = EXIT_ACTION_NONE;
        return decision;
    }

    //--- Accessors
    int    GetBarsHeld() const    { return m_barsHeld; }
    int    GetPartialsTaken() const { return m_partialsTaken; }
    double GetInitialRisk() const { return m_initialRisk; }
};

#endif // EXIT_OPTIMIZER_MQH
