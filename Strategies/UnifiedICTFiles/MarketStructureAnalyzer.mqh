// ICT market structure for the Unified ICT strategy: swings, BMS/ISP, HTF-MTF-LTF multiplex.
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef UICT_MARKET_STRUCTURE_ANALYZER_MQH
#define UICT_MARKET_STRUCTURE_ANALYZER_MQH

#include "../../Core/Utils/Instruments.mqh"

enum ENUM_BMS_TYPE
{
    BMS_NONE = 0,
    BMS_MINOR,
    BMS_SIGNIFICANT,
    BMS_MAJOR
};

enum ENUM_STRUCTURE_BREAK_TYPE
{
    STRUCT_BREAK_NONE = 0,
    STRUCT_BREAK_BOS,           // Break of Structure — trend continuation
    STRUCT_BREAK_CHOCH,         // Change of Character — potential reversal
    STRUCT_BREAK_CHOCH_CONFIRMED  // CHoCH confirmed by follow-through (used for entry)
};

struct SStructuralPoint
{
    datetime time;
    double   price;
    int      barIndex;
    bool     isHigh;
    double   strength;
    bool     isValid;
    bool     isBroken;
    
    SStructuralPoint() : time(0), price(0), barIndex(0), isHigh(false),
                        strength(0), isValid(false), isBroken(false) {}
};

struct SMarketStructure
{
    double currentHigh;
    double currentLow;
    double previousHigh;
    double previousLow;

    bool isBullishStructure;
    bool isBearishStructure;
    bool isConsolidating;

    ENUM_BMS_TYPE lastBMSType;
    datetime lastBMSTime;
    double lastBMSPrice;

    bool trendConfirmed;
    int consecutiveBMS;

    ENUM_STRUCTURE_BREAK_TYPE lastBreakType;
    bool lastBreakWasCHoCH;                   // mirrors lastBreakType for the break setters below
    bool lastBreakWasBOS;
    int chochCount;                           // several CHoCH = strong reversal
    int bosCount;
    datetime lastChochTime;
    datetime lastBosTime;
    double lastBreakPrice;

    SMarketStructure() : currentHigh(0), currentLow(0), previousHigh(0), previousLow(0),
                        isBullishStructure(false), isBearishStructure(false), isConsolidating(true),
                        lastBMSType(BMS_NONE), lastBMSTime(0), lastBMSPrice(0),
                        trendConfirmed(false), consecutiveBMS(0),
                        lastBreakType(STRUCT_BREAK_NONE), lastBreakWasCHoCH(false),
                        lastBreakWasBOS(false), chochCount(0), bosCount(0),
                        lastChochTime(0), lastBosTime(0), lastBreakPrice(0) {}
};

struct STFStructure
{
    ENUM_TIMEFRAMES timeframe;
    bool isBullish;
    bool isBearish;
    bool isConsolidating;
    double strength;
    
    STFStructure() : timeframe(PERIOD_CURRENT), isBullish(false), isBearish(false),
                    isConsolidating(true), strength(0) {}
};

class CMarketStructureAnalyzer
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    SStructuralPoint    m_highs[];
    SStructuralPoint    m_lows[];
    int                 m_highCount;
    int                 m_lowCount;
    
    SMarketStructure    m_structure;
    
    STFStructure        m_htf;
    STFStructure        m_mtf;
    STFStructure        m_ltf;
    
    int                 m_swingStrength;
    
    int                 m_atrHandle;
    int                 m_htfAtrHandle;
    int                 m_ltfAtrHandle;
    
    void                FindStructuralPoints(int lookback);
    bool                HasMomentum();
    bool                HasVolume();
    ENUM_TIMEFRAMES     GetHigherTF(ENUM_TIMEFRAMES tf);
    ENUM_TIMEFRAMES     GetLowerTF(ENUM_TIMEFRAMES tf);
    void                AnalyzeStructure(STFStructure &tfStruct);
    
public:
                        CMarketStructureAnalyzer();
                       ~CMarketStructureAnalyzer();
    
    double              GetATR(int period);
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, int swingStrength = 3);
    void                Update();
    
    bool                IdentifyISP(bool &isBullish);
    
    bool                ConfirmTrend(bool isBullish);
    
    ENUM_BMS_TYPE       DetectBMS();
    bool                HasStructureBreak();
    bool                HasBMS(int maxBarsAgo = 5);
    
    void                UpdateMultiplexStructure();
    bool                IsValidMultiplexSetup(ENUM_TRADE_SIGNAL &signal);
    bool                IsHTFAligned(bool bullish);
    bool                IsCISD(const ENUM_POSITION_TYPE direction, const int barShift = 1);
    bool                HasRecentBullishCISD(const int maxBarsAgo = 3);
    bool                HasRecentBearishCISD(const int maxBarsAgo = 3);
    
    SMarketStructure    GetStructure() const { return m_structure; }
    bool                IsBullish() const { return m_structure.isBullishStructure; }
    bool                IsBearish() const { return m_structure.isBearishStructure; }
    bool                IsBullishStructure() const { return m_structure.isBullishStructure; }
    bool                IsBearishStructure() const { return m_structure.isBearishStructure; }
    bool                IsTrendConfirmed() const { return m_structure.trendConfirmed; }
    int                 GetConsecutiveBMS() const { return m_structure.consecutiveBMS; }

    ENUM_STRUCTURE_BREAK_TYPE GetLastBreakType() const { return m_structure.lastBreakType; }
    bool WasLastBreakCHoCH() const { return m_structure.lastBreakWasCHoCH; }
    bool WasLastBreakBOS()   const { return m_structure.lastBreakWasBOS; }
    int  GetCHoCHCount()     const { return m_structure.chochCount; }
    int  GetBOSCount()       const { return m_structure.bosCount; }
    
    int                 GetSwingHighCount() const { return m_highCount; }
    int                 GetSwingLowCount() const { return m_lowCount; }
    bool                GetLastSwingHigh(SStructuralPoint &swing);
    bool                GetLastSwingLow(SStructuralPoint &swing);

    bool                DetectFastCHOCH();              // 1-bar close beyond structure level
    bool                DetectWickBOS();                 // Wick penetration = immediate BOS
    bool                DetectCISDDisplacement();        // Displacement > 1.5 ATR = CISD confirmation
    double              GetSwingHighLevel(int lookback = 20);
    double              GetSwingLowLevel(int lookback = 20);
};

CMarketStructureAnalyzer::CMarketStructureAnalyzer() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_highCount(0),
    m_lowCount(0),
    m_swingStrength(3),
    m_atrHandle(INVALID_HANDLE),
    m_htfAtrHandle(INVALID_HANDLE),
    m_ltfAtrHandle(INVALID_HANDLE)
{
    ArrayResize(m_highs, 0);
    ArrayResize(m_lows, 0);
}

CMarketStructureAnalyzer::~CMarketStructureAnalyzer()
{
    ArrayFree(m_highs);
    ArrayFree(m_lows);
}

bool CMarketStructureAnalyzer::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, int swingStrength)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_swingStrength = swingStrength;
    
    m_structure = SMarketStructure();
    
    // CIndicatorManager owns these handles and releases them
    CIndicatorManager* indManager = CIndicatorManager::Instance();
    if(indManager != NULL)
    {
        m_atrHandle = indManager.GetATRHandle(m_symbol, m_timeframe, 14);
        m_htfAtrHandle = indManager.GetATRHandle(m_symbol, GetHigherTF(m_timeframe), 14);
        m_ltfAtrHandle = indManager.GetATRHandle(m_symbol, GetLowerTF(m_timeframe), 14);
    }
    
    return true;
}

void CMarketStructureAnalyzer::Update()
{
    // Warmup guard: fewer than 100 calculated bars means the indicator has no usable history
    if(m_atrHandle != INVALID_HANDLE && BarsCalculated(m_atrHandle) < 100) return;
    if(m_htfAtrHandle != INVALID_HANDLE && BarsCalculated(m_htfAtrHandle) < 100) return;
    
    FindStructuralPoints(100);
    DetectBMS();
    UpdateMultiplexStructure();
}

void CMarketStructureAnalyzer::FindStructuralPoints(int lookback)
{
    m_highCount = 0;
    m_lowCount = 0;
    ArrayResize(m_highs, 0);
    ArrayResize(m_lows, 0);
    
    double high[], low[];
    datetime time[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(time, true);
    
    // Start at shift 1: the forming bar would repaint swing points.
    if(CopyHigh(m_symbol, m_timeframe, 1, lookback, high) <= 0) return;
    if(CopyLow(m_symbol, m_timeframe, 1, lookback, low) <= 0) return;
    if(CopyTime(m_symbol, m_timeframe, 1, lookback, time) <= 0) return;
    
    int str = m_swingStrength;
    
    // A swing high must be strictly higher than m_swingStrength bars on both sides
    for(int i = str; i < lookback - str; i++)
    {
        bool isSwingHigh = true;
        for(int j = 1; j <= str; j++)
        {
            if(high[i] <= high[i-j] || high[i] <= high[i+j])
            {
                isSwingHigh = false;
                break;
            }
        }
        
        if(isSwingHigh)
        {
            ArrayResize(m_highs, m_highCount + 1);
            m_highs[m_highCount].time = time[i];
            m_highs[m_highCount].price = high[i];
            m_highs[m_highCount].barIndex = i;
            m_highs[m_highCount].isHigh = true;
            m_highs[m_highCount].isValid = true;
            m_highCount++;
        }
    }
    
    for(int i = str; i < lookback - str; i++)
    {
        bool isSwingLow = true;
        for(int j = 1; j <= str; j++)
        {
            if(low[i] >= low[i-j] || low[i] >= low[i+j])
            {
                isSwingLow = false;
                break;
            }
        }
        
        if(isSwingLow)
        {
            ArrayResize(m_lows, m_lowCount + 1);
            m_lows[m_lowCount].time = time[i];
            m_lows[m_lowCount].price = low[i];
            m_lows[m_lowCount].barIndex = i;
            m_lows[m_lowCount].isHigh = false;
            m_lows[m_lowCount].isValid = true;
            m_lowCount++;
        }
    }
    
    // m_highs/m_lows fill newest-first (as-series scan), so [0] is the current swing
    if(m_highCount >= 2)
    {
        m_structure.currentHigh = m_highs[0].price;
        m_structure.previousHigh = m_highs[1].price;
    }
    
    if(m_lowCount >= 2)
    {
        m_structure.currentLow = m_lows[0].price;
        m_structure.previousLow = m_lows[1].price;
    }
}

// ISP: a >=5-bar range holding inside 0.30 * ATR that price then breaks
bool CMarketStructureAnalyzer::IdentifyISP(bool &isBullish)
{
    double atr = GetATR(14);
    double consolidationThreshold = atr * 0.30;
    
    int consolidationBars = 0;
    double consolidationHigh = 0;
    double consolidationLow = DBL_MAX;
    
    for(int i = 1; i <= 20; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        
        if(consolidationHigh == 0) consolidationHigh = high;
        if(consolidationLow == DBL_MAX) consolidationLow = low;
        
        consolidationHigh = MathMax(consolidationHigh, high);
        consolidationLow = MathMin(consolidationLow, low);
        
        double range = consolidationHigh - consolidationLow;
        if(range < consolidationThreshold)
            consolidationBars++;
        else
            break;
    }
    
    if(consolidationBars < 5)
        return false;
    
    double currentHigh = iHigh(m_symbol, m_timeframe, 0);
    double currentLow = iLow(m_symbol, m_timeframe, 0);
    
    if(currentHigh > consolidationHigh)
    {
        isBullish = true;
        m_structure.currentHigh = currentHigh;
        return true;
    }
    
    if(currentLow < consolidationLow)
    {
        isBullish = false;
        m_structure.currentLow = currentLow;
        return true;
    }
    
    return false;
}

bool CMarketStructureAnalyzer::ConfirmTrend(bool isBullish)
{
    if(isBullish)
    {
        bool newHigh = (m_structure.currentHigh > m_structure.previousHigh);
        bool higherLow = (m_structure.currentLow > m_structure.previousLow);
        
        if(newHigh && higherLow)
        {
            m_structure.isBullishStructure = true;
            m_structure.isBearishStructure = false;
            m_structure.isConsolidating = false;
            m_structure.trendConfirmed = true;
            m_structure.consecutiveBMS++;
            return true;
        }
    }
    else
    {
        bool newLow = (m_structure.currentLow < m_structure.previousLow);
        bool lowerHigh = (m_structure.currentHigh < m_structure.previousHigh);
        
        if(newLow && lowerHigh)
        {
            m_structure.isBearishStructure = true;
            m_structure.isBullishStructure = false;
            m_structure.isConsolidating = false;
            m_structure.trendConfirmed = true;
            m_structure.consecutiveBMS++;
            return true;
        }
    }
    
    return false;
}

ENUM_BMS_TYPE CMarketStructureAnalyzer::DetectBMS()
{
    if(!HasStructureBreak())
        return BMS_NONE;
    
    // Classify by PeriodSeconds: a raw enum-range compare left H2..H12 out of every
    // branch, so those charts returned BMS_NONE forever.
    int tfSeconds = PeriodSeconds(m_timeframe);

    if(tfSeconds <= PeriodSeconds(PERIOD_M15))
    {
        m_structure.lastBMSType = BMS_MINOR;
        m_structure.lastBMSTime = TimeCurrent();
        return BMS_MINOR;
    }
    else if(tfSeconds <= PeriodSeconds(PERIOD_H1))
    {
        if(HasMomentum())
        {
            m_structure.lastBMSType = BMS_SIGNIFICANT;
            m_structure.lastBMSTime = TimeCurrent();
            return BMS_SIGNIFICANT;
        }
    }
    else
    {
        if(HasMomentum() && HasVolume())
        {
            m_structure.lastBMSType = BMS_MAJOR;
            m_structure.lastBMSTime = TimeCurrent();
            return BMS_MAJOR;
        }
    }

    return BMS_NONE;
}

bool CMarketStructureAnalyzer::HasStructureBreak()
{
    // Shift 1 only: classifying breaks off the forming bar flipped the flags tick-by-tick.
    double close = iClose(m_symbol, m_timeframe, 1);
    m_structure.lastBreakType = STRUCT_BREAK_NONE;
    m_structure.lastBreakWasCHoCH = false;
    m_structure.lastBreakWasBOS   = false;

    if(m_structure.isBullishStructure)
    {
        // Bullish: BOS = close above currentHigh, CHoCH = close below previousLow
        if(close > m_structure.currentHigh)
        {
            m_structure.lastBreakType   = STRUCT_BREAK_BOS;
            m_structure.lastBreakWasBOS = true;
            m_structure.lastBMSPrice    = close;
            m_structure.lastBreakPrice  = close;
            m_structure.bosCount++;
            m_structure.lastBosTime     = TimeCurrent();
            m_structure.consecutiveBMS++;
            return true;
        }

        if(close < m_structure.previousLow)
        {
            m_structure.lastBreakType     = STRUCT_BREAK_CHOCH;
            m_structure.lastBreakWasCHoCH = true;
            m_structure.lastBMSPrice      = close;
            m_structure.lastBreakPrice    = close;
            m_structure.chochCount++;
            m_structure.lastChochTime     = TimeCurrent();
            // Do NOT flip isBullishStructure yet — wait for confirmation (second break)
            return true;
        }
    }
    else if(m_structure.isBearishStructure)
    {
        // Bearish: BOS = close below currentLow, CHoCH = close above previousHigh
        if(close < m_structure.currentLow)
        {
            m_structure.lastBreakType   = STRUCT_BREAK_BOS;
            m_structure.lastBreakWasBOS = true;
            m_structure.lastBMSPrice    = close;
            m_structure.lastBreakPrice  = close;
            m_structure.bosCount++;
            m_structure.lastBosTime     = TimeCurrent();
            m_structure.consecutiveBMS++;
            return true;
        }

        if(close > m_structure.previousHigh)
        {
            m_structure.lastBreakType     = STRUCT_BREAK_CHOCH;
            m_structure.lastBreakWasCHoCH = true;
            m_structure.lastBMSPrice      = close;
            m_structure.lastBreakPrice    = close;
            m_structure.chochCount++;
            m_structure.lastChochTime     = TimeCurrent();
            return true;
        }
    }
    else
    {
        // Consolidating — any breakout is treated as CHoCH (new structure forming)
        if(close > m_structure.currentHigh)
        {
            m_structure.isBullishStructure  = true;
            m_structure.isConsolidating     = false;
            m_structure.lastBreakType       = STRUCT_BREAK_CHOCH;
            m_structure.lastBreakWasCHoCH   = true;
            m_structure.lastBMSPrice        = close;
            m_structure.lastBreakPrice      = close;
            m_structure.lastChochTime       = TimeCurrent();
            return true;
        }
        if(close < m_structure.currentLow)
        {
            m_structure.isBearishStructure  = true;
            m_structure.isConsolidating     = false;
            m_structure.lastBreakType       = STRUCT_BREAK_CHOCH;
            m_structure.lastBreakWasCHoCH   = true;
            m_structure.lastBMSPrice        = close;
            m_structure.lastBreakPrice      = close;
            m_structure.lastChochTime       = TimeCurrent();
            return true;
        }
    }

    return false;
}

// A BMS counts as recent when its timestamp is at or after the open of bar maxBarsAgo
bool CMarketStructureAnalyzer::HasBMS(int maxBarsAgo)
{
    if(m_structure.lastBMSType == BMS_NONE)
        return false;
    
    datetime thresholdTime = iTime(m_symbol, m_timeframe, maxBarsAgo);
    return (m_structure.lastBMSTime >= thresholdTime);
}

bool CMarketStructureAnalyzer::HasMomentum()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 3, rates) != 3)
        return false;
    
    for(int i = 0; i < 2; i++)
    {
        double body = MathAbs(rates[i].close - rates[i].open);
        double range = rates[i].high - rates[i].low;
        
        if(range > 0 && body >= range * 0.70)
            return true;
    }
    
    if(rates[0].close > rates[1].close && rates[1].close > rates[2].close)
        return true;
    if(rates[0].close < rates[1].close && rates[1].close < rates[2].close)
        return true;
    
    return false;
}

bool CMarketStructureAnalyzer::HasVolume()
{
    long vol0 = iVolume(m_symbol, m_timeframe, 0);
    long vol1 = iVolume(m_symbol, m_timeframe, 1);
    long avgVol = 0;
    int validBars = 0;
    
    for(int i = 2; i < 22; i++)
    {
        long vol = iVolume(m_symbol, m_timeframe, i);
        if(vol > 0)
        {
            avgVol += vol;
            validBars++;
        }
    }
    if(validBars > 0)
        avgVol /= validBars;
    
    return (vol0 > avgVol * 1.5 || vol1 > avgVol * 1.5);
}

double CMarketStructureAnalyzer::GetATR(int period)
{
    int handle = m_atrHandle;
    // m_atrHandle is fixed at period 14; any other period needs a fresh manager handle
    if(period != 14 || handle == INVALID_HANDLE)
    {
        CIndicatorManager* indManager = CIndicatorManager::Instance();
        if(indManager != NULL)
            handle = indManager.GetATRHandle(m_symbol, m_timeframe, period);
    }
    
    if(handle == INVALID_HANDLE) return 0;
    
    double value[];
    ArraySetAsSeries(value, true);
    if(CopyBuffer(handle, 0, 0, 1, value) > 0)
    {
        return value[0];
    }
    
    return 0;
}

void CMarketStructureAnalyzer::UpdateMultiplexStructure()
{
    m_htf.timeframe = GetHigherTF(m_timeframe);
    m_mtf.timeframe = m_timeframe;
    m_ltf.timeframe = GetLowerTF(m_timeframe);
    
    AnalyzeStructure(m_htf);
    AnalyzeStructure(m_mtf);
    AnalyzeStructure(m_ltf);
}

ENUM_TIMEFRAMES CMarketStructureAnalyzer::GetHigherTF(ENUM_TIMEFRAMES tf)
{
    bool syntheticIndex = IsSyntheticIndexSymbolName(m_symbol);
    switch(tf)
    {
        case PERIOD_M1:  return syntheticIndex ? PERIOD_M5  : PERIOD_M15;
        case PERIOD_M5:  return syntheticIndex ? PERIOD_M15 : PERIOD_H1;
        case PERIOD_M15: return syntheticIndex ? PERIOD_H1  : PERIOD_H4;
        case PERIOD_M30: return syntheticIndex ? PERIOD_H1  : PERIOD_H4;
        case PERIOD_H1:  return syntheticIndex ? PERIOD_H4  : PERIOD_D1;
        case PERIOD_H4:  return PERIOD_D1;
        case PERIOD_D1:  return PERIOD_W1;
        default:         return PERIOD_D1;
    }
}

ENUM_TIMEFRAMES CMarketStructureAnalyzer::GetLowerTF(ENUM_TIMEFRAMES tf)
{
    bool syntheticIndex = IsSyntheticIndexSymbolName(m_symbol);
    switch(tf)
    {
        case PERIOD_W1:  return PERIOD_D1;
        case PERIOD_D1:  return PERIOD_H4;
        case PERIOD_H4:  return syntheticIndex ? PERIOD_M30 : PERIOD_H1;
        case PERIOD_H1:  return syntheticIndex ? PERIOD_M30 : PERIOD_M15;
        case PERIOD_M30: return syntheticIndex ? PERIOD_M15 : PERIOD_M5;
        case PERIOD_M15: return PERIOD_M5;
        case PERIOD_M5:  return PERIOD_M1;
        default:         return PERIOD_M5;
    }
}

void CMarketStructureAnalyzer::AnalyzeStructure(STFStructure &tfStruct)
{
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(m_symbol, tfStruct.timeframe, 0, 50, high) <= 0) return;
    if(CopyLow(m_symbol, tfStruct.timeframe, 0, 50, low) <= 0) return;
    if(CopyClose(m_symbol, tfStruct.timeframe, 0, 50, close) <= 0) return;
    
    // Swing = beyond both neighbours one and two bars either side; only the first two count
    int swingHigh1 = -1, swingHigh2 = -1;
    int swingLow1 = -1, swingLow2 = -1;
    
    for(int i = 2; i < 48; i++)
    {
        if(high[i] > high[i-1] && high[i] > high[i+1] &&
           high[i] > high[i-2] && high[i] > high[i+2])
        {
            if(swingHigh1 == -1) swingHigh1 = i;
            else if(swingHigh2 == -1) { swingHigh2 = i; break; }
        }
    }
    
    for(int i = 2; i < 48; i++)
    {
        if(low[i] < low[i-1] && low[i] < low[i+1] &&
           low[i] < low[i-2] && low[i] < low[i+2])
        {
            if(swingLow1 == -1) swingLow1 = i;
            else if(swingLow2 == -1) { swingLow2 = i; break; }
        }
    }
    
    // Bullish needs a higher high AND a higher low; bearish the mirror image
    tfStruct.isBullish = false;
    tfStruct.isBearish = false;
    tfStruct.isConsolidating = true;
    
    if(swingHigh1 >= 0 && swingHigh2 >= 0 && swingLow1 >= 0 && swingLow2 >= 0)
    {
        bool higherHigh = (high[swingHigh1] > high[swingHigh2]);
        bool higherLow = (low[swingLow1] > low[swingLow2]);
        bool lowerHigh = (high[swingHigh1] < high[swingHigh2]);
        bool lowerLow = (low[swingLow1] < low[swingLow2]);
        
        if(higherHigh && higherLow)
        {
            tfStruct.isBullish = true;
            tfStruct.isConsolidating = false;
            tfStruct.strength = 0.8;
        }
        else if(lowerHigh && lowerLow)
        {
            tfStruct.isBearish = true;
            tfStruct.isConsolidating = false;
            tfStruct.strength = 0.8;
        }
    }
}

bool CMarketStructureAnalyzer::IsValidMultiplexSetup(ENUM_TRADE_SIGNAL &signal)
{
    UpdateMultiplexStructure();
    
    // HTF and LTF must agree; the MTF is computed but not consulted here
    if(m_htf.isBullish && m_ltf.isBullish)
    {
        signal = TRADE_SIGNAL_BUY;
        return true;
    }
    
    if(m_htf.isBearish && m_ltf.isBearish)
    {
        signal = TRADE_SIGNAL_SELL;
        return true;
    }
    
    return false;
}

bool CMarketStructureAnalyzer::IsHTFAligned(bool bullish)
{
    UpdateMultiplexStructure();
    
    if(bullish)
        return m_htf.isBullish;
    else
        return m_htf.isBearish;
}

bool CMarketStructureAnalyzer::IsCISD(const ENUM_POSITION_TYPE direction, const int barShift)
{
    int totalBars = iBars(m_symbol, m_timeframe);
    if(totalBars <= barShift + 2)
        return false;

    double open0 = iOpen(m_symbol, m_timeframe, barShift);
    double close0 = iClose(m_symbol, m_timeframe, barShift);
    double high0 = iHigh(m_symbol, m_timeframe, barShift);
    double low0 = iLow(m_symbol, m_timeframe, barShift);

    double open1 = iOpen(m_symbol, m_timeframe, barShift + 1);
    double close1 = iClose(m_symbol, m_timeframe, barShift + 1);
    double high1 = iHigh(m_symbol, m_timeframe, barShift + 1);
    double low1 = iLow(m_symbol, m_timeframe, barShift + 1);

    double open2 = iOpen(m_symbol, m_timeframe, barShift + 2);
    double close2 = iClose(m_symbol, m_timeframe, barShift + 2);

    bool candle1Bullish = (close1 > open1);
    bool candle1Bearish = (close1 < open1);
    bool candle0Bullish = (close0 > open0);
    bool candle0Bearish = (close0 < open0);

    if(direction == POSITION_TYPE_BUY)
    {
        bool reclaimBody = (close0 > open1 && close0 > close1);
        bool deliveryShift = (low0 >= low1 && high0 >= high1);
        bool priorPressure = candle1Bearish || close2 < open2;
        return (candle0Bullish && reclaimBody && deliveryShift && priorPressure);
    }

    if(direction == POSITION_TYPE_SELL)
    {
        bool reclaimBody = (close0 < open1 && close0 < close1);
        bool deliveryShift = (high0 <= high1 && low0 <= low1);
        bool priorPressure = candle1Bullish || close2 > open2;
        return (candle0Bearish && reclaimBody && deliveryShift && priorPressure);
    }

    return false;
}

bool CMarketStructureAnalyzer::HasRecentBullishCISD(const int maxBarsAgo)
{
    int limit = MathMax(1, maxBarsAgo);
    for(int shift = 1; shift <= limit; shift++)
    {
        if(IsCISD(POSITION_TYPE_BUY, shift))
            return true;
    }
    return false;
}

bool CMarketStructureAnalyzer::HasRecentBearishCISD(const int maxBarsAgo)
{
    int limit = MathMax(1, maxBarsAgo);
    for(int shift = 1; shift <= limit; shift++)
    {
        if(IsCISD(POSITION_TYPE_SELL, shift))
            return true;
    }
    return false;
}

bool CMarketStructureAnalyzer::GetLastSwingHigh(SStructuralPoint &swing)
{
    if(m_highCount <= 0) return false;
    swing = m_highs[0];
    return true;
}

bool CMarketStructureAnalyzer::GetLastSwingLow(SStructuralPoint &swing)
{
    if(m_lowCount <= 0) return false;
    swing = m_lows[0];
    return true;
}

// Fast CHoCH: one closed bar's close beyond the nearest swing level
bool CMarketStructureAnalyzer::DetectFastCHOCH()
{
    // Closed bar only: the forming-bar close flip-flopped this bonus tick-by-tick
    // inside FVGScalper and AsianRangeBreak confidence scores.
    double close1 = iClose(m_symbol, m_timeframe, 1);
    if(close1 <= 0) return false;

    double swingHigh = GetSwingHighLevel(20);
    if(swingHigh > 0 && close1 > swingHigh)
        return true;

    double swingLow = GetSwingLowLevel(20);
    if(swingLow > 0 && close1 < swingLow)
        return true;

    return false;
}

// Wick BOS: a closed bar's wick penetrating a swing level counts immediately
bool CMarketStructureAnalyzer::DetectWickBOS()
{
    // Closed bars only, matching the shift-1 convention every other read here uses.
    double high1 = iHigh(m_symbol, m_timeframe, 1);
    double low1 = iLow(m_symbol, m_timeframe, 1);
    if(high1 <= 0 || low1 <= 0) return false;

    double swingHigh = GetSwingHighLevel(10);
    if(swingHigh > 0 && high1 > swingHigh)
        return true;

    double swingLow = GetSwingLowLevel(10);
    if(swingLow > 0 && low1 < swingLow)
        return true;

    return false;
}

// CISD displacement: the 5-bar close range must exceed 1.5 ATR
bool CMarketStructureAnalyzer::DetectCISDDisplacement()
{
    // Measured across closed bars (shifts 1 and 6): including the forming bar biased
    // displacement low for most of each bar's life.
    double close1 = iClose(m_symbol, m_timeframe, 1);
    double close6 = iClose(m_symbol, m_timeframe, 6);
    if(close1 <= 0 || close6 <= 0) return false;

    double displacement = MathAbs(close1 - close6);
    double atr = GetATR(14);
    if(atr <= 0) return false;

    return displacement > 1.5 * atr;
}

double CMarketStructureAnalyzer::GetSwingHighLevel(int lookback = 20)
{
    int highestBar = iHighest(m_symbol, m_timeframe, MODE_HIGH, lookback, 1);
    if(highestBar < 0) return 0.0;
    return iHigh(m_symbol, m_timeframe, highestBar);
}

double CMarketStructureAnalyzer::GetSwingLowLevel(int lookback = 20)
{
    int lowestBar = iLowest(m_symbol, m_timeframe, MODE_LOW, lookback, 1);
    if(lowestBar < 0) return 0.0;
    return iLow(m_symbol, m_timeframe, lowestBar);
}

#endif // __UICT_MARKET_STRUCTURE_ANALYZER_MQH__
