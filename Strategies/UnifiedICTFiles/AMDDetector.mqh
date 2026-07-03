//+------------------------------------------------------------------+
//| AMDDetector.mqh                                                  |
//| Accumulation-Manipulation-Distribution (AMD) Phase Detector     |
//| P2-B: Identifies which phase of the ICT AMD cycle is active     |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef AMD_DETECTOR_MQH
#define AMD_DETECTOR_MQH

//+------------------------------------------------------------------+
//| AMD Phase Enum                                                   |
//+------------------------------------------------------------------+
enum ENUM_AMD_PHASE
{
    AMD_PHASE_UNKNOWN         = 0,
    AMD_PHASE_ACCUMULATION,       // Asian session + early market: range, inducement builds
    AMD_PHASE_MANIPULATION,       // Early session liquidity sweep (the "fake")
    AMD_PHASE_DISTRIBUTION,       // True directional move after manipulation
    AMD_PHASE_POST_DISTRIBUTION   // Late session, trend exhausts / reversal begins
};

//+------------------------------------------------------------------+
//| AMD State Structure                                              |
//+------------------------------------------------------------------+
struct SAMDState
{
    ENUM_AMD_PHASE  phase;
    bool            isBullishManipulation;  // The sweep went DOWN before true move UP
    bool            isBearishManipulation;  // The sweep went UP before true move DOWN

    double          accumulationHigh;   // Asian session range high
    double          accumulationLow;    // Asian session range low
    double          manipulationLevel;  // The swept high or low during manipulation
    datetime        manipulationTime;   // When manipulation spike occurred
    double          distributionTarget; // Expected target of the true move

    bool            liquiditySwept;     // Has manipulation cleared liquidity?
    bool            chochAfterSweep;    // Did a CHoCH occur after the sweep?

    double          confidence;         // Confidence in AMD identification (0.0-1.0)

    SAMDState() : phase(AMD_PHASE_UNKNOWN), isBullishManipulation(false),
                 isBearishManipulation(false), accumulationHigh(0), accumulationLow(DBL_MAX),
                 manipulationLevel(0), manipulationTime(0), distributionTarget(0),
                 liquiditySwept(false), chochAfterSweep(false), confidence(0) {}
};

//+------------------------------------------------------------------+
//| AMD Detector Class                                               |
//+------------------------------------------------------------------+
class CAMDDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    SAMDState       m_state;

    // Session hour definitions (EST)
    int             m_asianStartESTHour;    // 20 (8pm)
    int             m_asianEndESTHour;      // 2  (2am = London open)
    int             m_londonOpenESTHour;    // 2
    int             m_nyOpenESTHour;        // 8
    int             m_brokerGMTOffset;

    // Price-action AMD for synthetics (no session dependency)
    bool            m_isSynthetic;          // True for synthetic indices
    double          m_paAccumHigh;          // Price-action accumulation range high
    double          m_paAccumLow;           // Price-action accumulation range low
    int             m_paConsolidationBars;  // Bars in consolidation (accumulation)
    int             m_paBarsSinceSweep;     // Bars since manipulation sweep
    int             m_paAtrHandle;          // ATR handle for price-action AMD

    // Internal helpers
    int             GetCurrentESTHour();
    bool            IsAsianSession();
    bool            IsManipulationWindow();
    bool            IsDistributionWindow();
    bool            IsDSTActive();
    void            BuildAccumulationRange();
    void            CheckManipulation();
    void            CheckDistributionEntry();
    void            UpdatePriceActionAMD();   // Price-action AMD for synthetics

public:
                    CAMDDetector();
                   ~CAMDDetector();

    bool            Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                               int brokerGMTOffset = 2);
    void            Update();

    // Phase access
    ENUM_AMD_PHASE  GetPhase() const { return m_state.phase; }
    SAMDState       GetState() const { return m_state; }
    bool            IsAccumulation()  const { return m_state.phase == AMD_PHASE_ACCUMULATION; }
    bool            IsManipulation()  const { return m_state.phase == AMD_PHASE_MANIPULATION; }
    bool            IsDistribution()  const { return m_state.phase == AMD_PHASE_DISTRIBUTION; }

    // Trade context methods
    bool            IsSweepBullish()  const { return m_state.isBullishManipulation; }
    bool            IsSweepBearish()  const { return m_state.isBearishManipulation; }
    bool            HasCHoCHConfirmation() const { return m_state.chochAfterSweep; }
    double          GetConfidence()   const { return m_state.confidence; }

    // String representation for logging
    string          GetPhaseName() const;
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CAMDDetector::CAMDDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_H1),
    m_asianStartESTHour(20),
    m_asianEndESTHour(2),
    m_londonOpenESTHour(2),
    m_nyOpenESTHour(8),
    m_brokerGMTOffset(2),
    m_isSynthetic(false),
    m_paAccumHigh(0),
    m_paAccumLow(DBL_MAX),
    m_paConsolidationBars(0),
    m_paBarsSinceSweep(0),
    m_paAtrHandle(INVALID_HANDLE)
{}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CAMDDetector::~CAMDDetector() {}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CAMDDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                              int brokerGMTOffset)
{
    m_symbol         = symbol;
    m_timeframe      = timeframe;
    m_brokerGMTOffset = brokerGMTOffset;

    m_state = SAMDState();

    // Detect synthetic indices (no forex session structure)
    m_isSynthetic = (StringFind(symbol, "Volatility") >= 0 ||
                     StringFind(symbol, "Boom") >= 0 ||
                     StringFind(symbol, "Crash") >= 0 ||
                     StringFind(symbol, "Jump") >= 0 ||
                     StringFind(symbol, "Step") >= 0);

    m_paAccumHigh = 0;
    m_paAccumLow = DBL_MAX;
    m_paConsolidationBars = 0;
    m_paBarsSinceSweep = 0;
    m_paAtrHandle = INVALID_HANDLE;

    Print("[AMD] Initialized for ", symbol, " TF=", EnumToString(timeframe),
          " mode=", m_isSynthetic ? "PRICE_ACTION" : "SESSION_BASED");
    return true;
}

//+------------------------------------------------------------------+
//| Get Current EST Hour                                             |
//+------------------------------------------------------------------+
int CAMDDetector::GetCurrentESTHour()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Calculate DST offset using proper US DST rules
    int dstOffset = IsDSTActive() ? -4 : -5;  // EDT or EST
    
    int estHour = dt.hour - m_brokerGMTOffset + dstOffset;
    while(estHour < 0)  estHour += 24;
    while(estHour >= 24) estHour -= 24;
    return estHour;
}

//+------------------------------------------------------------------+
//| Session Window Checks                                            |
//+------------------------------------------------------------------+
bool CAMDDetector::IsAsianSession()
{
    int h = GetCurrentESTHour();
    return (h >= 20 || h < 2);
}

bool CAMDDetector::IsManipulationWindow()
{
    int h = GetCurrentESTHour();
    // Manipulation windows: London open (2-4 EST) and NY open (8-9:30 EST)
    return ((h >= 2 && h < 4) || (h >= 8 && h < 10));
}

bool CAMDDetector::IsDistributionWindow()
{
    int h = GetCurrentESTHour();
    // Distribution (true move): London 4-8 EST and NY 9:30-12 EST
    return ((h >= 4 && h < 8) || (h >= 10 && h < 12));
}

//+------------------------------------------------------------------+
//| Build Accumulation Range                                        |
//+------------------------------------------------------------------+
void CAMDDetector::BuildAccumulationRange()
{
    // Scan back through Asian session bars (up to 8H of bars)
    int lookback = 30;  // On H1, 30 bars back covers ~1 full Asian session + buffer
    m_state.accumulationHigh = 0;
    m_state.accumulationLow  = DBL_MAX;

    for(int i = 0; i < lookback; i++)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        MqlDateTime dt;
        TimeToStruct(barTime, dt);

        int estHour = dt.hour - m_brokerGMTOffset - 5;
        while(estHour < 0)   estHour += 24;
        while(estHour >= 24) estHour -= 24;

        // Only include Asian session bars
        if(estHour < 20 && estHour >= 2) continue;

        double h = iHigh(m_symbol, m_timeframe, i);
        double l = iLow(m_symbol,  m_timeframe, i);

        if(h > m_state.accumulationHigh) m_state.accumulationHigh = h;
        if(l < m_state.accumulationLow)  m_state.accumulationLow  = l;
    }
}

//+------------------------------------------------------------------+
//| Check Manipulation                                               |
//+------------------------------------------------------------------+
// Manipulation = a wick spike that clears the Asian range high or low
// THEN price reverses back INTO the range within 1-3 bars
void CAMDDetector::CheckManipulation()
{
    if(m_state.accumulationHigh <= 0 || m_state.accumulationLow >= DBL_MAX) return;

    for(int i = 1; i <= 6; i++)
    {
        double high  = iHigh(m_symbol,  m_timeframe, i);
        double low   = iLow(m_symbol,   m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        datetime t   = iTime(m_symbol,  m_timeframe, i);

        // Bullish manipulation: low pierced BELOW Asian range low but closed INSIDE
        if(low < m_state.accumulationLow && close > m_state.accumulationLow)
        {
            m_state.isBullishManipulation = true;
            m_state.isBearishManipulation = false;
            m_state.manipulationLevel     = low;
            m_state.manipulationTime      = t;
            m_state.liquiditySwept        = true;
            m_state.confidence            = 0.70;
            m_state.phase                 = AMD_PHASE_MANIPULATION;
            return;
        }

        // Bearish manipulation: high pierced ABOVE Asian range high but closed INSIDE
        if(high > m_state.accumulationHigh && close < m_state.accumulationHigh)
        {
            m_state.isBearishManipulation = true;
            m_state.isBullishManipulation = false;
            m_state.manipulationLevel     = high;
            m_state.manipulationTime      = t;
            m_state.liquiditySwept        = true;
            m_state.confidence            = 0.70;
            m_state.phase                 = AMD_PHASE_MANIPULATION;
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Check Distribution Entry                                         |
//+------------------------------------------------------------------+
// Distribution = after manipulation, price breaks OUT of range in the TRUE direction
// Bullish manipulation (fake down) → true move UP
// Bearish manipulation (fake up) → true move DOWN
void CAMDDetector::CheckDistributionEntry()
{
    if(!m_state.liquiditySwept) return;

    double close = iClose(m_symbol, m_timeframe, 0);

    if(m_state.isBullishManipulation)
    {
        // True move is UP: close above the Asian range HIGH = distribution phase
        if(close > m_state.accumulationHigh)
        {
            m_state.phase               = AMD_PHASE_DISTRIBUTION;
            m_state.chochAfterSweep     = true;
            m_state.distributionTarget  = m_state.accumulationHigh +
                                          (m_state.accumulationHigh - m_state.manipulationLevel) * 2.0;
            m_state.confidence          = MathMin(1.0, m_state.confidence + 0.20);
        }
    }
    else if(m_state.isBearishManipulation)
    {
        // True move is DOWN: close below Asian range LOW = distribution phase
        if(close < m_state.accumulationLow)
        {
            m_state.phase               = AMD_PHASE_DISTRIBUTION;
            m_state.chochAfterSweep     = true;
            m_state.distributionTarget  = m_state.accumulationLow -
                                          (m_state.manipulationLevel - m_state.accumulationLow) * 2.0;
            m_state.confidence          = MathMin(1.0, m_state.confidence + 0.20);
        }
    }
}

//+------------------------------------------------------------------+
//| Price-Action AMD for Synthetic Indices                           |
//+------------------------------------------------------------------+
// Synthetics trade 24/7 with no session structure. Instead of using
// time-based session windows, detect AMD phases from price action:
//   ACCUMULATION = price consolidating in a range (low ATR ratio)
//   MANIPULATION = spike outside range with reversal (liquidity sweep)
//   DISTRIBUTION = breakout in true direction after manipulation
void CAMDDetector::UpdatePriceActionAMD()
{
    // Get ATR using member handle
    if(m_paAtrHandle == INVALID_HANDLE)
        m_paAtrHandle = iATR(m_symbol, m_timeframe, 14);
    if(m_paAtrHandle == INVALID_HANDLE) return;
    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if(CopyBuffer(m_paAtrHandle, 0, 0, 1, atrBuf) <= 0) return;
    double atr = atrBuf[0];
    if(atr <= 0) return;

    double close0 = iClose(m_symbol, m_timeframe, 0);
    double high0  = iHigh(m_symbol, m_timeframe, 0);
    double low0   = iLow(m_symbol, m_timeframe, 0);
    double range0 = high0 - low0;

    // --- ACCUMULATION detection ---
    // A bar is "consolidating" if its range is < 0.7x ATR (tight relative to avg)
    bool isConsolidating = (range0 < atr * 0.7);

    if(m_state.phase == AMD_PHASE_UNKNOWN || m_state.phase == AMD_PHASE_POST_DISTRIBUTION)
    {
        // Start fresh accumulation
        if(isConsolidating)
        {
            m_paConsolidationBars++;
            if(m_paConsolidationBars >= 3)  // Need at least 3 bars of consolidation
            {
                m_state.phase = AMD_PHASE_ACCUMULATION;
                // Build accumulation range from last N consolidating bars
                m_paAccumHigh = 0;
                m_paAccumLow = DBL_MAX;
                int lookback = MathMin(m_paConsolidationBars + 2, 20);
                for(int i = 0; i < lookback; i++)
                {
                    double h = iHigh(m_symbol, m_timeframe, i);
                    double l = iLow(m_symbol, m_timeframe, i);
                    if(h > m_paAccumHigh) m_paAccumHigh = h;
                    if(l < m_paAccumLow)  m_paAccumLow = l;
                }
                m_state.accumulationHigh = m_paAccumHigh;
                m_state.accumulationLow  = m_paAccumLow;
            }
        }
        else
        {
            m_paConsolidationBars = 0;
        }
        return;
    }

    if(m_state.phase == AMD_PHASE_ACCUMULATION)
    {
        // Update accumulation range
        if(isConsolidating)
        {
            m_paConsolidationBars++;
            if(high0 > m_state.accumulationHigh) m_state.accumulationHigh = high0;
            if(low0 < m_state.accumulationLow)   m_state.accumulationLow = low0;
        }

        // Check for manipulation: spike outside range with reversal
        // Bullish manipulation: wick below range low, close inside
        if(low0 < m_state.accumulationLow && close0 > m_state.accumulationLow)
        {
            m_state.isBullishManipulation = true;
            m_state.isBearishManipulation = false;
            m_state.manipulationLevel     = low0;
            m_state.manipulationTime      = iTime(m_symbol, m_timeframe, 0);
            m_state.liquiditySwept        = true;
            m_state.confidence            = 0.70;
            m_state.phase                 = AMD_PHASE_MANIPULATION;
            m_paBarsSinceSweep = 0;
            return;
        }

        // Bearish manipulation: wick above range high, close inside
        if(high0 > m_state.accumulationHigh && close0 < m_state.accumulationHigh)
        {
            m_state.isBearishManipulation = true;
            m_state.isBullishManipulation = false;
            m_state.manipulationLevel     = high0;
            m_state.manipulationTime      = iTime(m_symbol, m_timeframe, 0);
            m_state.liquiditySwept        = true;
            m_state.confidence            = 0.70;
            m_state.phase                 = AMD_PHASE_MANIPULATION;
            m_paBarsSinceSweep = 0;
            return;
        }

        // If range expands significantly without manipulation, reset
        if(!isConsolidating && range0 > atr * 1.5)
        {
            m_state = SAMDState();
            m_paConsolidationBars = 0;
        }
        return;
    }

    if(m_state.phase == AMD_PHASE_MANIPULATION)
    {
        m_paBarsSinceSweep++;

        // Check for distribution: breakout in true direction
        if(m_state.isBullishManipulation && close0 > m_state.accumulationHigh)
        {
            m_state.phase               = AMD_PHASE_DISTRIBUTION;
            m_state.chochAfterSweep     = true;
            m_state.distributionTarget  = m_state.accumulationHigh +
                                          (m_state.accumulationHigh - m_state.manipulationLevel) * 2.0;
            m_state.confidence          = MathMin(1.0, m_state.confidence + 0.20);
            return;
        }

        if(m_state.isBearishManipulation && close0 < m_state.accumulationLow)
        {
            m_state.phase               = AMD_PHASE_DISTRIBUTION;
            m_state.chochAfterSweep     = true;
            m_state.distributionTarget  = m_state.accumulationLow -
                                          (m_state.manipulationLevel - m_state.accumulationLow) * 2.0;
            m_state.confidence          = MathMin(1.0, m_state.confidence + 0.20);
            return;
        }

        // If too many bars pass without distribution, reset
        if(m_paBarsSinceSweep > 10)
        {
            m_state = SAMDState();
            m_paConsolidationBars = 0;
        }
        return;
    }

    if(m_state.phase == AMD_PHASE_DISTRIBUTION)
    {
        // Stay in distribution for up to 5 bars, then transition to post-distribution
        m_paBarsSinceSweep++;
        if(m_paBarsSinceSweep > 5)
        {
            m_state.phase = AMD_PHASE_POST_DISTRIBUTION;
            m_paConsolidationBars = 0;
        }
        return;
    }
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CAMDDetector::Update()
{
    // Use price-action AMD for synthetics (no session dependency)
    if(m_isSynthetic)
    {
        UpdatePriceActionAMD();
        return;
    }

    // Session-based AMD for forex/commodities
    if(IsAsianSession())
    {
        // Reset state at start of each Asian session
        if(m_state.phase == AMD_PHASE_DISTRIBUTION || m_state.phase == AMD_PHASE_POST_DISTRIBUTION)
        {
            m_state = SAMDState();
        }
        m_state.phase = AMD_PHASE_ACCUMULATION;
        BuildAccumulationRange();
        return;
    }

    if(IsManipulationWindow())
    {
        if(m_state.phase == AMD_PHASE_ACCUMULATION)
        {
            BuildAccumulationRange();  // Finalize range
            CheckManipulation();
        }
        return;
    }

    if(IsDistributionWindow())
    {
        if(m_state.phase == AMD_PHASE_MANIPULATION)
            CheckDistributionEntry();
        return;
    }

    // Late session
    if(m_state.phase == AMD_PHASE_DISTRIBUTION)
        m_state.phase = AMD_PHASE_POST_DISTRIBUTION;
}

//+------------------------------------------------------------------+
//| Get Phase Name                                                   |
//+------------------------------------------------------------------+
string CAMDDetector::GetPhaseName() const
{
    switch(m_state.phase)
    {
        case AMD_PHASE_ACCUMULATION:    return "Accumulation";
        case AMD_PHASE_MANIPULATION:    return "Manipulation";
        case AMD_PHASE_DISTRIBUTION:    return "Distribution";
        case AMD_PHASE_POST_DISTRIBUTION: return "Post-Distribution";
        default: return "Unknown";
    }
}

//+------------------------------------------------------------------+
//| Check if DST is currently active using US DST rules                  |
//| DST starts on second Sunday in March at 2:00 AM EST                |
//| DST ends on first Sunday in November at 2:00 AM EST                |
//+------------------------------------------------------------------+
bool CAMDDetector::IsDSTActive()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // If outside DST window months, return false
    if(dt.mon < 3 || dt.mon > 11)
        return false;
    if(dt.mon == 3 || dt.mon == 11)
    {
        // Need to check specific dates for March and November
        int day = dt.day;
        
        if(dt.mon == 3)
        {
            // DST starts on second Sunday in March
            // Find the second Sunday of the month
            int secondSunday = 0;
            int sundayCount = 0;
            
            for(int d = 1; d <= 14; d++)
            {
                MqlDateTime tempDt;
                tempDt.year = dt.year;
                tempDt.mon = 3;
                tempDt.day = d;
                tempDt.hour = 0;
                tempDt.min = 0;
                tempDt.sec = 0;
                datetime testTime = StructToTime(tempDt);
                TimeToStruct(testTime, tempDt);
                if(tempDt.day_of_week == 0)
                {
                    sundayCount++;
                    if(sundayCount == 2)
                    {
                        secondSunday = d;
                        break;
                    }
                }
            }
            
            // DST starts at 2:00 AM EST on second Sunday
            if(day < secondSunday)
                return false;
            if(day == secondSunday && dt.hour < 2)
                return false;
        }
        else if(dt.mon == 11)
        {
            // DST ends on first Sunday in November
            // Find the first Sunday of the month
            int firstSunday = 0;
            
            for(int d = 1; d <= 7; d++)
            {
                MqlDateTime tempDt;
                tempDt.year = dt.year;
                tempDt.mon = 11;
                tempDt.day = d;
                tempDt.hour = 0;
                tempDt.min = 0;
                tempDt.sec = 0;
                datetime testTime = StructToTime(tempDt);
                TimeToStruct(testTime, tempDt);
                if(tempDt.day_of_week == 0)
                {
                    firstSunday = d;
                    break;
                }
            }
            
            // DST ends at 2:00 AM EST on first Sunday
            if(day > firstSunday)
                return false;
            if(day == firstSunday && dt.hour >= 2)
                return false;
        }
    }
    
    return true;
}

#endif // __AMD_DETECTOR_MQH__
