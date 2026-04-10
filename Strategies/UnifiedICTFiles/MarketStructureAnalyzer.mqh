//+------------------------------------------------------------------+
//| MarketStructureAnalyzer.mqh                                      |
//| Advanced Market Structure for Unified ICT Strategy               |
//| Implements BMS, ISP, Trend Confirmation, Multiplex Structure     |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __UICT_MARKET_STRUCTURE_ANALYZER_MQH__
#define __UICT_MARKET_STRUCTURE_ANALYZER_MQH__

#include "../../Core/Utils/Instruments.mqh"

//+------------------------------------------------------------------+
//| BMS Type Enum                                                    |
//+------------------------------------------------------------------+
enum ENUM_BMS_TYPE
{
    BMS_NONE = 0,
    BMS_MINOR,
    BMS_SIGNIFICANT,
    BMS_MAJOR
};

//+------------------------------------------------------------------+
//| Structure Break Type Enum — P0-D                                 |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_BREAK_TYPE
{
    STRUCT_BREAK_NONE = 0,
    STRUCT_BREAK_BOS,           // Break of Structure — trend continuation
    STRUCT_BREAK_CHOCH,         // Change of Character — potential reversal
    STRUCT_BREAK_CHOCH_CONFIRMED  // CHoCH confirmed by follow-through (used for entry)
};

//+------------------------------------------------------------------+
//| Structural Point Structure                                       |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Market Structure State                                           |
//+------------------------------------------------------------------+
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

    // --- NEW FIELDS (P0-D) ---
    ENUM_STRUCTURE_BREAK_TYPE lastBreakType;  // BOS or CHoCH
    bool lastBreakWasCHoCH;                   // Shortcut flag
    bool lastBreakWasBOS;                     // Shortcut flag
    int chochCount;                           // Number of CHoCH events (multiple = strong reversal)
    int bosCount;                             // Number of BOS events in current trend
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

//+------------------------------------------------------------------+
//| Timeframe Structure                                              |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Market Structure Analyzer Class                                  |
//+------------------------------------------------------------------+
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
    
    // Multiplex
    STFStructure        m_htf;
    STFStructure        m_mtf;
    STFStructure        m_ltf;
    
    int                 m_swingStrength;
    
    // Indicator handles
    int                 m_atrHandle;
    int                 m_htfAtrHandle;
    int                 m_ltfAtrHandle;
    
    // Internal methods
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
    
    // ISP Detection
    bool                IdentifyISP(bool &isBullish);
    
    // Trend Confirmation
    bool                ConfirmTrend(bool isBullish);
    
    // BMS Detection
    ENUM_BMS_TYPE       DetectBMS();
    bool                HasStructureBreak();
    
    // Multiplex Structure
    void                UpdateMultiplexStructure();
    bool                IsValidMultiplexSetup(ENUM_TRADE_SIGNAL &signal);
    bool                IsHTFAligned(bool bullish);
    
    // Getters
    SMarketStructure    GetStructure() const { return m_structure; }
    bool                IsBullish() const { return m_structure.isBullishStructure; }
    bool                IsBearish() const { return m_structure.isBearishStructure; }
    bool                IsBullishStructure() const { return m_structure.isBullishStructure; }
    bool                IsBearishStructure() const { return m_structure.isBearishStructure; }
    bool                IsTrendConfirmed() const { return m_structure.trendConfirmed; }
    int                 GetConsecutiveBMS() const { return m_structure.consecutiveBMS; }

    // CHoCH/BOS accessors — P0-D
    ENUM_STRUCTURE_BREAK_TYPE GetLastBreakType() const { return m_structure.lastBreakType; }
    bool WasLastBreakCHoCH() const { return m_structure.lastBreakWasCHoCH; }
    bool WasLastBreakBOS()   const { return m_structure.lastBreakWasBOS; }
    int  GetCHoCHCount()     const { return m_structure.chochCount; }
    int  GetBOSCount()       const { return m_structure.bosCount; }
    
    // Swing access
    int                 GetSwingHighCount() const { return m_highCount; }
    int                 GetSwingLowCount() const { return m_lowCount; }
    bool                GetLastSwingHigh(SStructuralPoint &swing);
    bool                GetLastSwingLow(SStructuralPoint &swing);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CMarketStructureAnalyzer::~CMarketStructureAnalyzer()
{
    ArrayFree(m_highs);
    ArrayFree(m_lows);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CMarketStructureAnalyzer::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, int swingStrength)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_swingStrength = swingStrength;
    
    m_structure = SMarketStructure();
    
    // Initialize handles via singleton IndicatorManager
    CIndicatorManager* indManager = CIndicatorManager::Instance();
    if(indManager != NULL)
    {
        m_atrHandle = indManager.GetATRHandle(m_symbol, m_timeframe, 14);
        m_htfAtrHandle = indManager.GetATRHandle(m_symbol, GetHigherTF(m_timeframe), 14);
        m_ltfAtrHandle = indManager.GetATRHandle(m_symbol, GetLowerTF(m_timeframe), 14);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CMarketStructureAnalyzer::Update()
{
    // FIX: Check indicator readiness before updating
    if(m_atrHandle != INVALID_HANDLE && BarsCalculated(m_atrHandle) < 100) return;
    if(m_htfAtrHandle != INVALID_HANDLE && BarsCalculated(m_htfAtrHandle) < 100) return;
    
    FindStructuralPoints(100);
    DetectBMS();
    UpdateMultiplexStructure();
}

//+------------------------------------------------------------------+
//| Find Structural Points                                           |
//+------------------------------------------------------------------+
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
    
    if(CopyHigh(m_symbol, m_timeframe, 0, lookback, high) <= 0) return;
    if(CopyLow(m_symbol, m_timeframe, 0, lookback, low) <= 0) return;
    if(CopyTime(m_symbol, m_timeframe, 0, lookback, time) <= 0) return;
    
    int str = m_swingStrength;
    
    // Find swing highs
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
    
    // Find swing lows
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
    
    // Update structure with latest swings
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

//+------------------------------------------------------------------+
//| Identify Initial Structural Point                                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Confirm Trend                                                    |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Detect BMS                                                       |
//+------------------------------------------------------------------+
ENUM_BMS_TYPE CMarketStructureAnalyzer::DetectBMS()
{
    if(!HasStructureBreak())
        return BMS_NONE;
    
    ENUM_TIMEFRAMES tf = m_timeframe;
    
    // Minor BMS (15m and below)
    if(tf <= PERIOD_M15)
    {
        m_structure.lastBMSType = BMS_MINOR;
        m_structure.lastBMSTime = TimeCurrent();
        return BMS_MINOR;
    }
    // Significant BMS (15m to 1H)
    else if(tf >= PERIOD_M15 && tf <= PERIOD_H1)
    {
        if(HasMomentum())
        {
            m_structure.lastBMSType = BMS_SIGNIFICANT;
            m_structure.lastBMSTime = TimeCurrent();
            return BMS_SIGNIFICANT;
        }
    }
    // Major BMS (Daily+)
    else if(tf >= PERIOD_D1)
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

//+------------------------------------------------------------------+
//| Has Structure Break — P0-D Rewrite with CHoCH/BOS Classification|
//+------------------------------------------------------------------+
bool CMarketStructureAnalyzer::HasStructureBreak()
{
    double close = iClose(m_symbol, m_timeframe, 0);
    m_structure.lastBreakType = STRUCT_BREAK_NONE;
    m_structure.lastBreakWasCHoCH = false;
    m_structure.lastBreakWasBOS   = false;

    if(m_structure.isBullishStructure)
    {
        // In a bullish structure:
        // BOS = close above current high (breaks to the upside — continuation)
        // CHoCH = close below previous low (breaks to the downside — reversal)

        if(close > m_structure.currentHigh)
        {
            // BOS: bullish trend continues upward
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
            // CHoCH: bullish structure is being challenged by a bearish break
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
        // In a bearish structure:
        // BOS = close below current low (breaks to the downside — continuation)
        // CHoCH = close above previous high (breaks to the upside — reversal)

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

//+------------------------------------------------------------------+
//| Has Momentum                                                     |
//+------------------------------------------------------------------+
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
    
    // Check for consistent direction
    if(rates[0].close > rates[1].close && rates[1].close > rates[2].close)
        return true;
    if(rates[0].close < rates[1].close && rates[1].close < rates[2].close)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Has Volume                                                       |
//+------------------------------------------------------------------+
bool CMarketStructureAnalyzer::HasVolume()
{
    long vol0 = iVolume(m_symbol, m_timeframe, 0);
    long vol1 = iVolume(m_symbol, m_timeframe, 1);
    long avgVol = 0;
    
    for(int i = 2; i < 22; i++)
        avgVol += iVolume(m_symbol, m_timeframe, i);
    avgVol /= 20;
    
    return (vol0 > avgVol * 1.5 || vol1 > avgVol * 1.5);
}

//+------------------------------------------------------------------+
//| Get ATR                                                          |
//+------------------------------------------------------------------+
double CMarketStructureAnalyzer::GetATR(int period)
{
    int handle = m_atrHandle;
    // If handle is invalid or was requested for non-default period, fallback to manager
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

//+------------------------------------------------------------------+
//| Update Multiplex Structure                                       |
//+------------------------------------------------------------------+
void CMarketStructureAnalyzer::UpdateMultiplexStructure()
{
    m_htf.timeframe = GetHigherTF(m_timeframe);
    m_mtf.timeframe = m_timeframe;
    m_ltf.timeframe = GetLowerTF(m_timeframe);
    
    AnalyzeStructure(m_htf);
    AnalyzeStructure(m_mtf);
    AnalyzeStructure(m_ltf);
}

//+------------------------------------------------------------------+
//| Get Higher Timeframe                                             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get Lower Timeframe                                              |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Analyze Structure for Timeframe                                  |
//+------------------------------------------------------------------+
void CMarketStructureAnalyzer::AnalyzeStructure(STFStructure &tfStruct)
{
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(m_symbol, tfStruct.timeframe, 0, 50, high) <= 0) return;
    if(CopyLow(m_symbol, tfStruct.timeframe, 0, 50, low) <= 0) return;
    if(CopyClose(m_symbol, tfStruct.timeframe, 0, 50, close) <= 0) return;
    
    // Find recent swing points
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
    
    // Determine structure
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

//+------------------------------------------------------------------+
//| Is Valid Multiplex Setup                                         |
//+------------------------------------------------------------------+
bool CMarketStructureAnalyzer::IsValidMultiplexSetup(ENUM_TRADE_SIGNAL &signal)
{
    UpdateMultiplexStructure();
    
    // Best: HTF and LTF aligned
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

//+------------------------------------------------------------------+
//| Is HTF Aligned                                                   |
//+------------------------------------------------------------------+
bool CMarketStructureAnalyzer::IsHTFAligned(bool bullish)
{
    UpdateMultiplexStructure();
    
    if(bullish)
        return m_htf.isBullish;
    else
        return m_htf.isBearish;
}

//+------------------------------------------------------------------+
//| Get Last Swing High                                              |
//+------------------------------------------------------------------+
bool CMarketStructureAnalyzer::GetLastSwingHigh(SStructuralPoint &swing)
{
    if(m_highCount <= 0) return false;
    swing = m_highs[0];
    return true;
}

//+------------------------------------------------------------------+
//| Get Last Swing Low                                               |
//+------------------------------------------------------------------+
bool CMarketStructureAnalyzer::GetLastSwingLow(SStructuralPoint &swing)
{
    if(m_lowCount <= 0) return false;
    swing = m_lows[0];
    return true;
}

#endif // __UICT_MARKET_STRUCTURE_ANALYZER_MQH__
