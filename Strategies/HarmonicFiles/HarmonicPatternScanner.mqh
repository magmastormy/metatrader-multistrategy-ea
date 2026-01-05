//+------------------------------------------------------------------+
//| HarmonicPatternScanner.mqh                                       |
//| Optimized O(n) Harmonic Pattern Scanner                          |
//| Replaces O(n^5) nested loop with efficient swing-based detection |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __HARMONIC_PATTERN_SCANNER_MQH__
#define __HARMONIC_PATTERN_SCANNER_MQH__

//+------------------------------------------------------------------+
//| Harmonic Pattern Types                                           |
//+------------------------------------------------------------------+
enum ENUM_HARMONIC_TYPE
{
    HARMONIC_NONE = 0,
    HARMONIC_GARTLEY,
    HARMONIC_BUTTERFLY,
    HARMONIC_BAT,
    HARMONIC_CRAB,
    HARMONIC_SHARK,
    HARMONIC_CYPHER,
    HARMONIC_ABCD
};

//+------------------------------------------------------------------+
//| Pattern Direction                                                |
//+------------------------------------------------------------------+
enum ENUM_HARMONIC_DIRECTION
{
    HARMONIC_BULLISH,
    HARMONIC_BEARISH
};

//+------------------------------------------------------------------+
//| Swing Point for Harmonic                                         |
//+------------------------------------------------------------------+
struct SHarmonicSwing
{
    datetime    time;
    double      price;
    int         barIndex;
    bool        isHigh;
    double      strength;
    
    SHarmonicSwing() : time(0), price(0), barIndex(0), isHigh(false), strength(0) {}
};

//+------------------------------------------------------------------+
//| Harmonic Pattern Structure                                       |
//+------------------------------------------------------------------+
struct SHarmonicPatternData
{
    ENUM_HARMONIC_TYPE      type;
    ENUM_HARMONIC_DIRECTION direction;
    datetime                time;
    
    // XABCD points
    double      xPoint;
    double      aPoint;
    double      bPoint;
    double      cPoint;
    double      dPoint;
    datetime    xTime;
    datetime    aTime;
    datetime    bTime;
    datetime    cTime;
    datetime    dTime;
    
    // Ratios
    double      abRatio;    // AB/XA
    double      bcRatio;    // BC/AB
    double      cdRatio;    // CD/BC
    double      xdRatio;    // XD/XA
    
    // Pattern quality
    double      prz;            // Potential Reversal Zone
    double      przHigh;
    double      przLow;
    double      strength;       // 0-1 pattern quality
    bool        isValid;
    bool        isComplete;
    
    SHarmonicPatternData() : type(HARMONIC_NONE), direction(HARMONIC_BULLISH), time(0),
                             xPoint(0), aPoint(0), bPoint(0), cPoint(0), dPoint(0),
                             xTime(0), aTime(0), bTime(0), cTime(0), dTime(0),
                             abRatio(0), bcRatio(0), cdRatio(0), xdRatio(0),
                             prz(0), przHigh(0), przLow(0), strength(0),
                             isValid(false), isComplete(false) {}
};

//+------------------------------------------------------------------+
//| Harmonic Pattern Scanner Class                                   |
//+------------------------------------------------------------------+
class CHarmonicPatternScanner
{
private:
    string                  m_symbol;
    ENUM_TIMEFRAMES         m_timeframe;
    
    // Swing storage
    SHarmonicSwing          m_swings[];
    int                     m_swingCount;
    int                     m_maxSwings;
    
    // Pattern storage
    SHarmonicPatternData    m_patterns[];
    int                     m_patternCount;
    int                     m_maxPatterns;
    
    // Configuration
    double                  m_tolerance;        // Fibonacci ratio tolerance (3-5%)
    int                     m_swingStrength;    // Bars for swing confirmation
    int                     m_lookback;         // Bars to scan
    
    // Internal methods
    void                    DetectSwings();
    bool                    GetAlternatingSwings(SHarmonicSwing &swings[], int count, bool startWithLow);
    bool                    ValidateTimeSequence(const SHarmonicSwing &swings[], int count);
    bool                    IsRatioValid(double ratio, double target, double tol);
    
    // Pattern validation
    bool                    IsGartley(double abRatio, double bcRatio, double cdRatio, double xdRatio);
    bool                    IsBat(double abRatio, double bcRatio, double cdRatio, double xdRatio);
    bool                    IsButterfly(double abRatio, double bcRatio, double cdRatio, double xdRatio);
    bool                    IsCrab(double abRatio, double bcRatio, double cdRatio, double xdRatio);
    bool                    IsShark(double abRatio, double bcRatio, double cdRatio, double xdRatio);
    bool                    IsCypher(double abRatio, double bcRatio, double cdRatio, double xdRatio);
    
    double                  CalculatePRZ(const SHarmonicPatternData &pattern);
    double                  ScorePattern(const SHarmonicPatternData &pattern);
    
public:
                            CHarmonicPatternScanner();
                           ~CHarmonicPatternScanner();
    
    // Initialization
    bool                    Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                       double tolerance = 0.05, int swingStrength = 2);
    
    // Scanning
    void                    ScanPatterns();
    void                    Update();
    
    // Getters
    int                     GetPatternCount() const { return m_patternCount; }
    bool                    GetPatternAt(int index, SHarmonicPatternData &pattern);
    bool                    GetBestBullishPattern(SHarmonicPatternData &pattern);
    bool                    GetBestBearishPattern(SHarmonicPatternData &pattern);
    
    // Pattern checks
    bool                    IsPriceAtPRZ(double price, SHarmonicPatternData &pattern);
    bool                    HasPendingPattern(ENUM_HARMONIC_DIRECTION direction);
    
    // Configuration
    void                    SetTolerance(double tol) { m_tolerance = tol; }
    void                    SetSwingStrength(int str) { m_swingStrength = str; }
    void                    SetLookback(int bars) { m_lookback = bars; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CHarmonicPatternScanner::CHarmonicPatternScanner() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_swingCount(0),
    m_maxSwings(50),
    m_patternCount(0),
    m_maxPatterns(10),
    m_tolerance(0.05),
    m_swingStrength(2),
    m_lookback(100)
{
    ArrayResize(m_swings, 0);
    ArrayResize(m_patterns, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CHarmonicPatternScanner::~CHarmonicPatternScanner()
{
    ArrayFree(m_swings);
    ArrayFree(m_patterns);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                         double tolerance, int swingStrength)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_tolerance = tolerance;
    m_swingStrength = swingStrength;
    
    ArrayResize(m_swings, 0);
    ArrayResize(m_patterns, 0);
    m_swingCount = 0;
    m_patternCount = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Swings                                                    |
//+------------------------------------------------------------------+
void CHarmonicPatternScanner::DetectSwings()
{
    ArrayResize(m_swings, 0);
    m_swingCount = 0;
    
    int bars = iBars(m_symbol, m_timeframe);
    int scanBars = MathMin(m_lookback, bars - m_swingStrength * 2);
    
    for(int i = m_swingStrength; i < scanBars - m_swingStrength; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        
        // Check swing high
        bool isSwingHigh = true;
        for(int j = 1; j <= m_swingStrength; j++)
        {
            if(iHigh(m_symbol, m_timeframe, i - j) >= high ||
               iHigh(m_symbol, m_timeframe, i + j) >= high)
            {
                isSwingHigh = false;
                break;
            }
        }
        
        if(isSwingHigh && m_swingCount < m_maxSwings)
        {
            ArrayResize(m_swings, m_swingCount + 1);
            m_swings[m_swingCount].price = high;
            m_swings[m_swingCount].time = iTime(m_symbol, m_timeframe, i);
            m_swings[m_swingCount].barIndex = i;
            m_swings[m_swingCount].isHigh = true;
            m_swings[m_swingCount].strength = (double)m_swingStrength;
            m_swingCount++;
        }
        
        // Check swing low
        bool isSwingLow = true;
        for(int j = 1; j <= m_swingStrength; j++)
        {
            if(iLow(m_symbol, m_timeframe, i - j) <= low ||
               iLow(m_symbol, m_timeframe, i + j) <= low)
            {
                isSwingLow = false;
                break;
            }
        }
        
        if(isSwingLow && m_swingCount < m_maxSwings)
        {
            ArrayResize(m_swings, m_swingCount + 1);
            m_swings[m_swingCount].price = low;
            m_swings[m_swingCount].time = iTime(m_symbol, m_timeframe, i);
            m_swings[m_swingCount].barIndex = i;
            m_swings[m_swingCount].isHigh = false;
            m_swings[m_swingCount].strength = (double)m_swingStrength;
            m_swingCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Get Alternating Swings - O(n) efficient method                   |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::GetAlternatingSwings(SHarmonicSwing &swings[], int count, bool startWithLow)
{
    ArrayResize(swings, count);
    int found = 0;
    bool lookingForHigh = !startWithLow;
    
    for(int i = 0; i < m_swingCount && found < count; i++)
    {
        if(m_swings[i].isHigh == lookingForHigh)
        {
            swings[found++] = m_swings[i];
            lookingForHigh = !lookingForHigh;
        }
    }
    
    return (found == count);
}

//+------------------------------------------------------------------+
//| Validate Time Sequence                                           |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::ValidateTimeSequence(const SHarmonicSwing &swings[], int count)
{
    for(int i = 1; i < count; i++)
    {
        // Each point must occur AFTER the previous (chronological)
        if(swings[i].barIndex >= swings[i-1].barIndex)
            return false;  // Bar indices are reversed (0 = current)
    }
    return true;
}

//+------------------------------------------------------------------+
//| Is Ratio Valid                                                   |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::IsRatioValid(double ratio, double target, double tol)
{
    return (ratio >= target - tol && ratio <= target + tol);
}

//+------------------------------------------------------------------+
//| Pattern Validation Methods                                       |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::IsGartley(double abRatio, double bcRatio, double cdRatio, double xdRatio)
{
    // Gartley: AB = 61.8% XA, XD = 78.6% XA
    return IsRatioValid(abRatio, 0.618, m_tolerance) &&
           (bcRatio >= 0.382 && bcRatio <= 0.886) &&
           IsRatioValid(xdRatio, 0.786, m_tolerance);
}

bool CHarmonicPatternScanner::IsBat(double abRatio, double bcRatio, double cdRatio, double xdRatio)
{
    // Bat: AB = 38.2-50% XA, XD = 88.6% XA
    return (abRatio >= 0.382 && abRatio <= 0.50) &&
           (bcRatio >= 0.382 && bcRatio <= 0.886) &&
           IsRatioValid(xdRatio, 0.886, m_tolerance * 0.6);  // Tighter for Bat
}

bool CHarmonicPatternScanner::IsButterfly(double abRatio, double bcRatio, double cdRatio, double xdRatio)
{
    // Butterfly: AB = 78.6% XA, XD = 127% or 161.8% (exceeds X)
    return IsRatioValid(abRatio, 0.786, m_tolerance) &&
           (bcRatio >= 0.382 && bcRatio <= 0.886) &&
           (IsRatioValid(xdRatio, 1.27, m_tolerance) || IsRatioValid(xdRatio, 1.618, m_tolerance));
}

bool CHarmonicPatternScanner::IsCrab(double abRatio, double bcRatio, double cdRatio, double xdRatio)
{
    // Crab: AB = 38.2-61.8% XA, XD = 161.8% (deepest extension)
    return (abRatio >= 0.382 && abRatio <= 0.618) &&
           (bcRatio >= 0.382 && bcRatio <= 0.886) &&
           IsRatioValid(xdRatio, 1.618, m_tolerance);
}

bool CHarmonicPatternScanner::IsShark(double abRatio, double bcRatio, double cdRatio, double xdRatio)
{
    // Shark: 88.6-113% XA, 113-161.8% BC extension
    return (abRatio >= 0.886 && abRatio <= 1.13) &&
           (cdRatio >= 1.13 && cdRatio <= 1.618);
}

bool CHarmonicPatternScanner::IsCypher(double abRatio, double bcRatio, double cdRatio, double xdRatio)
{
    // Cypher: AB = 38.2-61.8% XA, BC = 113-141.4% AB
    return (abRatio >= 0.382 && abRatio <= 0.618) &&
           (bcRatio >= 1.13 && bcRatio <= 1.414) &&
           IsRatioValid(xdRatio, 0.786, m_tolerance);
}

//+------------------------------------------------------------------+
//| Calculate PRZ                                                    |
//+------------------------------------------------------------------+
double CHarmonicPatternScanner::CalculatePRZ(const SHarmonicPatternData &pattern)
{
    double xa = MathAbs(pattern.aPoint - pattern.xPoint);
    double prz = pattern.dPoint;
    
    switch(pattern.type)
    {
        case HARMONIC_GARTLEY:
            prz = (pattern.direction == HARMONIC_BULLISH) ?
                  pattern.aPoint - (xa * 0.786) : pattern.aPoint + (xa * 0.786);
            break;
        case HARMONIC_BAT:
            prz = (pattern.direction == HARMONIC_BULLISH) ?
                  pattern.aPoint - (xa * 0.886) : pattern.aPoint + (xa * 0.886);
            break;
        case HARMONIC_BUTTERFLY:
            prz = (pattern.direction == HARMONIC_BULLISH) ?
                  pattern.xPoint - (xa * 0.27) : pattern.xPoint + (xa * 0.27);
            break;
        case HARMONIC_CRAB:
            prz = (pattern.direction == HARMONIC_BULLISH) ?
                  pattern.xPoint - (xa * 0.618) : pattern.xPoint + (xa * 0.618);
            break;
        default:
            break;
    }
    
    return prz;
}

//+------------------------------------------------------------------+
//| Score Pattern                                                    |
//+------------------------------------------------------------------+
double CHarmonicPatternScanner::ScorePattern(const SHarmonicPatternData &pattern)
{
    double score = 60.0;  // Base score
    
    // Ratio precision bonus
    double abDiff = MathAbs(pattern.abRatio - 0.618);
    double xdDiff = MathAbs(pattern.xdRatio - 0.786);
    
    if(abDiff < 0.02) score += 10.0;
    else if(abDiff < 0.04) score += 5.0;
    
    if(xdDiff < 0.02) score += 10.0;
    else if(xdDiff < 0.04) score += 5.0;
    
    // Pattern type bonus (Bat and Crab are more reliable)
    switch(pattern.type)
    {
        case HARMONIC_BAT:      score += 5.0; break;
        case HARMONIC_CRAB:     score += 5.0; break;
        case HARMONIC_GARTLEY:  score += 3.0; break;
        case HARMONIC_BUTTERFLY: score += 2.0; break;
        default: break;
    }
    
    // Completion bonus
    if(pattern.isComplete)
        score += 10.0;
    
    return MathMin(100.0, score);
}

//+------------------------------------------------------------------+
//| Scan Patterns - O(n) efficient algorithm                         |
//+------------------------------------------------------------------+
void CHarmonicPatternScanner::ScanPatterns()
{
    // Step 1: Detect swings
    DetectSwings();
    
    ArrayResize(m_patterns, 0);
    m_patternCount = 0;
    
    if(m_swingCount < 5) return;
    
    // Step 2: Get alternating swings for bullish patterns (L-H-L-H-L)
    SHarmonicSwing bullishSwings[5];
    if(GetAlternatingSwings(bullishSwings, 5, true))
    {
        if(ValidateTimeSequence(bullishSwings, 5))
        {
            // Calculate ratios
            double X = bullishSwings[0].price;  // Low
            double A = bullishSwings[1].price;  // High
            double B = bullishSwings[2].price;  // Low
            double C = bullishSwings[3].price;  // High
            double D = bullishSwings[4].price;  // Low
            
            double XA = A - X;
            double AB = A - B;
            double BC = C - B;
            double CD = C - D;
            double XD = A - D;
            
            if(XA > 0)
            {
                double abRatio = AB / XA;
                double bcRatio = (AB > 0) ? BC / AB : 0;
                double cdRatio = (BC > 0) ? CD / BC : 0;
                double xdRatio = XD / XA;
                
                SHarmonicPatternData pattern;
                pattern.direction = HARMONIC_BULLISH;
                pattern.xPoint = X; pattern.aPoint = A; pattern.bPoint = B;
                pattern.cPoint = C; pattern.dPoint = D;
                pattern.xTime = bullishSwings[0].time;
                pattern.aTime = bullishSwings[1].time;
                pattern.bTime = bullishSwings[2].time;
                pattern.cTime = bullishSwings[3].time;
                pattern.dTime = bullishSwings[4].time;
                pattern.time = bullishSwings[4].time;
                pattern.abRatio = abRatio;
                pattern.bcRatio = bcRatio;
                pattern.cdRatio = cdRatio;
                pattern.xdRatio = xdRatio;
                pattern.isComplete = true;
                
                // Check pattern types
                if(IsGartley(abRatio, bcRatio, cdRatio, xdRatio))
                    pattern.type = HARMONIC_GARTLEY;
                else if(IsBat(abRatio, bcRatio, cdRatio, xdRatio))
                    pattern.type = HARMONIC_BAT;
                else if(IsButterfly(abRatio, bcRatio, cdRatio, xdRatio))
                    pattern.type = HARMONIC_BUTTERFLY;
                else if(IsCrab(abRatio, bcRatio, cdRatio, xdRatio))
                    pattern.type = HARMONIC_CRAB;
                
                if(pattern.type != HARMONIC_NONE)
                {
                    pattern.prz = CalculatePRZ(pattern);
                    pattern.przHigh = pattern.prz * 1.005;
                    pattern.przLow = pattern.prz * 0.995;
                    pattern.strength = ScorePattern(pattern);
                    pattern.isValid = true;
                    
                    if(m_patternCount < m_maxPatterns)
                    {
                        ArrayResize(m_patterns, m_patternCount + 1);
                        m_patterns[m_patternCount++] = pattern;
                    }
                }
            }
        }
    }
    
    // Step 3: Get alternating swings for bearish patterns (H-L-H-L-H)
    SHarmonicSwing bearishSwings[5];
    if(GetAlternatingSwings(bearishSwings, 5, false))
    {
        if(ValidateTimeSequence(bearishSwings, 5))
        {
            double X = bearishSwings[0].price;  // High
            double A = bearishSwings[1].price;  // Low
            double B = bearishSwings[2].price;  // High
            double C = bearishSwings[3].price;  // Low
            double D = bearishSwings[4].price;  // High
            
            double XA = X - A;
            double AB = B - A;
            double BC = B - C;
            double CD = D - C;
            double XD = D - A;
            
            if(XA > 0)
            {
                double abRatio = AB / XA;
                double bcRatio = (AB > 0) ? BC / AB : 0;
                double cdRatio = (BC > 0) ? CD / BC : 0;
                double xdRatio = XD / XA;
                
                SHarmonicPatternData pattern;
                pattern.direction = HARMONIC_BEARISH;
                pattern.xPoint = X; pattern.aPoint = A; pattern.bPoint = B;
                pattern.cPoint = C; pattern.dPoint = D;
                pattern.xTime = bearishSwings[0].time;
                pattern.aTime = bearishSwings[1].time;
                pattern.bTime = bearishSwings[2].time;
                pattern.cTime = bearishSwings[3].time;
                pattern.dTime = bearishSwings[4].time;
                pattern.time = bearishSwings[4].time;
                pattern.abRatio = abRatio;
                pattern.bcRatio = bcRatio;
                pattern.cdRatio = cdRatio;
                pattern.xdRatio = xdRatio;
                pattern.isComplete = true;
                
                if(IsGartley(abRatio, bcRatio, cdRatio, xdRatio))
                    pattern.type = HARMONIC_GARTLEY;
                else if(IsBat(abRatio, bcRatio, cdRatio, xdRatio))
                    pattern.type = HARMONIC_BAT;
                else if(IsButterfly(abRatio, bcRatio, cdRatio, xdRatio))
                    pattern.type = HARMONIC_BUTTERFLY;
                else if(IsCrab(abRatio, bcRatio, cdRatio, xdRatio))
                    pattern.type = HARMONIC_CRAB;
                
                if(pattern.type != HARMONIC_NONE)
                {
                    pattern.prz = CalculatePRZ(pattern);
                    pattern.przHigh = pattern.prz * 1.005;
                    pattern.przLow = pattern.prz * 0.995;
                    pattern.strength = ScorePattern(pattern);
                    pattern.isValid = true;
                    
                    if(m_patternCount < m_maxPatterns)
                    {
                        ArrayResize(m_patterns, m_patternCount + 1);
                        m_patterns[m_patternCount++] = pattern;
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CHarmonicPatternScanner::Update()
{
    ScanPatterns();
}

//+------------------------------------------------------------------+
//| Get Pattern At Index                                             |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::GetPatternAt(int index, SHarmonicPatternData &pattern)
{
    if(index < 0 || index >= m_patternCount) return false;
    pattern = m_patterns[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Best Bullish Pattern                                         |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::GetBestBullishPattern(SHarmonicPatternData &pattern)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_patternCount; i++)
    {
        if(m_patterns[i].direction == HARMONIC_BULLISH &&
           m_patterns[i].isValid && m_patterns[i].strength > bestScore)
        {
            bestScore = m_patterns[i].strength;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        pattern = m_patterns[bestIndex];
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get Best Bearish Pattern                                         |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::GetBestBearishPattern(SHarmonicPatternData &pattern)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_patternCount; i++)
    {
        if(m_patterns[i].direction == HARMONIC_BEARISH &&
           m_patterns[i].isValid && m_patterns[i].strength > bestScore)
        {
            bestScore = m_patterns[i].strength;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        pattern = m_patterns[bestIndex];
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Is Price At PRZ                                                  |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::IsPriceAtPRZ(double price, SHarmonicPatternData &pattern)
{
    for(int i = 0; i < m_patternCount; i++)
    {
        if(m_patterns[i].isValid &&
           price >= m_patterns[i].przLow && price <= m_patterns[i].przHigh)
        {
            pattern = m_patterns[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Has Pending Pattern                                              |
//+------------------------------------------------------------------+
bool CHarmonicPatternScanner::HasPendingPattern(ENUM_HARMONIC_DIRECTION direction)
{
    for(int i = 0; i < m_patternCount; i++)
    {
        if(m_patterns[i].direction == direction && m_patterns[i].isValid)
            return true;
    }
    return false;
}

#endif // __HARMONIC_PATTERN_SCANNER_MQH__
