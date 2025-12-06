//+------------------------------------------------------------------+
//| Harmonic Patterns Strategy Module                                 |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_HARMONIC_PATTERNS_MQH__
#define __STRATEGY_HARMONIC_PATTERNS_MQH__

#include "../Core/StrategyBase.mqh"

// Harmonic Patterns Strategy - Identifies and trades Fibonacci-based harmonic price patterns
// including Gartley, Butterfly, Bat, Crab, and Shark patterns

// Define pattern types
enum ENUM_HARMONIC_PATTERN {
    PATTERN_NONE = 0,
    PATTERN_GARTLEY = 1,
    PATTERN_BUTTERFLY = 2,
    PATTERN_BAT = 3,
    PATTERN_CRAB = 4,
    PATTERN_SHARK = 5
};

// Define pattern direction
enum ENUM_PATTERN_DIRECTION {
    PATTERN_BULLISH = 1,
    PATTERN_BEARISH = -1
};

// Structure to store pattern points
struct SHarmonicPattern {
    ENUM_HARMONIC_PATTERN type;
    ENUM_PATTERN_DIRECTION direction;
    datetime time;
    double xPoint;
    double aPoint;
    double bPoint;
    double cPoint;
    double dPoint;
    double potentialReversal; // PRZ (Potential Reversal Zone)
    double strength;          // Pattern strength/quality 0.0-1.0
    bool isValid;
    bool isComplete;
    
    // Default constructor
    SHarmonicPattern() : type(PATTERN_NONE), direction(PATTERN_BULLISH), time(0),
                        xPoint(0), aPoint(0), bPoint(0), cPoint(0), dPoint(0),
                        potentialReversal(0), strength(0), isValid(false), isComplete(false) {}
    
    // Set method to initialize all values
    void Set(ENUM_HARMONIC_PATTERN _type, ENUM_PATTERN_DIRECTION _direction, datetime _time,
             double _xPoint, double _aPoint, double _bPoint, double _cPoint, double _dPoint,
             double _prz, double _strength, bool _isValid, bool _isComplete) {
        type = _type;
        direction = _direction;
        time = _time;
        xPoint = _xPoint;
        aPoint = _aPoint;
        bPoint = _bPoint;
        cPoint = _cPoint;
        dPoint = _dPoint;
        potentialReversal = _prz;
        strength = _strength;
        isValid = _isValid;
        isComplete = _isComplete;
    }
};

//+------------------------------------------------------------------+
//| Harmonic Patterns Strategy Class                                  |
//+------------------------------------------------------------------+
class CStrategyHarmonicPatterns : public CStrategyBase {
private:
    SHarmonicPattern m_patterns[10]; // Reduced size for performance
    int m_patternCount;
    int m_maxPatterns;
    
    // Helper methods
    double FibRatio(double start, double end, double target);
    bool IsRatioValid(double ratio, double target, double tolerance);
    void IdentifyHarmonicPatterns();

public:
    CStrategyHarmonicPatterns(const string name = "Harmonic Patterns Strategy", int magic = 0);
    virtual ~CStrategyHarmonicPatterns() {}

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override {
        return CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer);
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override {
        if(!IsEnabled() || !m_is_initialized) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        confidence = 0.0;
        IdentifyHarmonicPatterns();
        
        if(m_patternCount == 0) return TRADE_SIGNAL_NONE;
        
        double closePrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(point == 0) point = 0.0001;
        
        for(int i = 0; i < m_patternCount; i++) {
            if(!m_patterns[i].isValid || !m_patterns[i].isComplete) continue;
            
            double prz = m_patterns[i].potentialReversal;
            double pips = 20 * point; // 20 pips tolerance
            
            if(MathAbs(closePrice - prz) <= pips) {
                confidence = m_patterns[i].strength;
                return (m_patterns[i].direction == PATTERN_BULLISH) ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
            }
        }
        return TRADE_SIGNAL_NONE;
    }
    
    virtual string GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_HARMONIC_PATTERNS; }
};

CStrategyHarmonicPatterns::CStrategyHarmonicPatterns(const string name, int magic)
    : CStrategyBase(name, magic), m_patternCount(0), m_maxPatterns(10) {}

double CStrategyHarmonicPatterns::FibRatio(double start, double end, double target) {
    if(MathAbs(end - start) < 0.00001) return 0;
    return MathAbs((target - end) / (end - start));
}

bool CStrategyHarmonicPatterns::IsRatioValid(double ratio, double target, double tolerance) {
    return (ratio >= target - tolerance && ratio <= target + tolerance);
}

void CStrategyHarmonicPatterns::IdentifyHarmonicPatterns() {
    double high[];
    double low[];
    double closeArr[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(closeArr, true);
    
    // Reduced lookback for performance
    if(CopyHigh(m_symbol, m_timeframe, 0, 100, high) <= 0 ||
       CopyLow(m_symbol, m_timeframe, 0, 100, low) <= 0 ||
       CopyClose(m_symbol, m_timeframe, 0, 100, closeArr) <= 0) {
        return;
    }
    
    int swingHighs[10];
    int swingLows[10];
    int swingHighCount = 0;
    int swingLowCount = 0;
    
    // Identify swings (Fractals)
    for(int i = 2; i < 98; i++) {
        if(swingHighCount < 10 && high[i] > high[i-1] && high[i] > high[i+1] && high[i] > high[i-2] && high[i] > high[i+2]) {
            swingHighs[swingHighCount++] = i;
        }
        if(swingLowCount < 10 && low[i] < low[i-1] && low[i] < low[i+1] && low[i] < low[i-2] && low[i] < low[i+2]) {
            swingLows[swingLowCount++] = i;
        }
    }
    
    m_patternCount = 0;
    double tolerance = 0.10; // Increased tolerance slightly
    datetime currentTimeValue = TimeCurrent();
    
    // Check for Bullish Patterns (X-A-B-C-D where D is low)
    // X (Low) -> A (High) -> B (Low) -> C (High) -> D (Low)
    for(int x = 0; x < swingLowCount; x++) {
        int xIndex = swingLows[x];
        double xPoint = low[xIndex];
        
        for(int a = 0; a < swingHighCount; a++) {
            int aIndex = swingHighs[a];
            if(aIndex <= xIndex) continue; // A must be after X
            double aPoint = high[aIndex];
            
            for(int b = 0; b < swingLowCount; b++) {
                int bIndex = swingLows[b];
                if(bIndex <= aIndex) continue; // B must be after A
                double bPoint = low[bIndex];
                
                double abRatio = FibRatio(xPoint, aPoint, bPoint); // Retracement of XA
                
                for(int c = 0; c < swingHighCount; c++) {
                    int cIndex = swingHighs[c];
                    if(cIndex <= bIndex) continue; // C must be after B
                    double cPoint = high[cIndex];
                    
                    double bcRatio = FibRatio(aPoint, bPoint, cPoint); // Retracement of AB
                    
                    for(int d = 0; d < swingLowCount; d++) {
                        int dIndex = swingLows[d];
                        if(dIndex <= cIndex) continue; // D must be after C
                        double dPoint = low[dIndex];
                        
                        double cdRatio = FibRatio(bPoint, cPoint, dPoint); // Extension of BC
                        double xdRatio = FibRatio(xPoint, aPoint, dPoint); // Retracement of XA
                        
                        if(m_patternCount >= m_maxPatterns) return;

                        // Gartley
                        if(IsRatioValid(abRatio, 0.618, tolerance) && IsRatioValid(bcRatio, 0.382, tolerance) && IsRatioValid(xdRatio, 0.786, tolerance)) {
                            m_patterns[m_patternCount++].Set(PATTERN_GARTLEY, PATTERN_BULLISH, currentTimeValue, xPoint, aPoint, bPoint, cPoint, dPoint, dPoint, 0.8, true, true);
                        } 
                        // Butterfly
                        else if(IsRatioValid(abRatio, 0.786, tolerance) && IsRatioValid(bcRatio, 0.382, tolerance) && IsRatioValid(xdRatio, 1.27, tolerance)) {
                            m_patterns[m_patternCount++].Set(PATTERN_BUTTERFLY, PATTERN_BULLISH, currentTimeValue, xPoint, aPoint, bPoint, cPoint, dPoint, dPoint, 0.9, true, true);
                        }
                        // Bat
                        else if(IsRatioValid(abRatio, 0.5, tolerance) && IsRatioValid(bcRatio, 0.382, tolerance) && IsRatioValid(xdRatio, 0.886, tolerance)) {
                            m_patterns[m_patternCount++].Set(PATTERN_BAT, PATTERN_BULLISH, currentTimeValue, xPoint, aPoint, bPoint, cPoint, dPoint, dPoint, 0.85, true, true);
                        }
                    }
                }
            }
        }
    }
    
    // Check for Bearish Patterns (X-A-B-C-D where D is high)
    // X (High) -> A (Low) -> B (High) -> C (Low) -> D (High)
    for(int x = 0; x < swingHighCount; x++) {
        int xIndex = swingHighs[x];
        double xPoint = high[xIndex];
        
        for(int a = 0; a < swingLowCount; a++) {
            int aIndex = swingLows[a];
            if(aIndex <= xIndex) continue;
            double aPoint = low[aIndex];
            
            for(int b = 0; b < swingHighCount; b++) {
                int bIndex = swingHighs[b];
                if(bIndex <= aIndex) continue;
                double bPoint = high[bIndex];
                
                double abRatio = FibRatio(xPoint, aPoint, bPoint);
                
                for(int c = 0; c < swingLowCount; c++) {
                    int cIndex = swingLows[c];
                    if(cIndex <= bIndex) continue;
                    double cPoint = low[cIndex];
                    
                    double bcRatio = FibRatio(aPoint, bPoint, cPoint);
                    
                    for(int d = 0; d < swingHighCount; d++) {
                        int dIndex = swingHighs[d];
                        if(dIndex <= cIndex) continue;
                        double dPoint = high[dIndex];
                        
                        double cdRatio = FibRatio(bPoint, cPoint, dPoint);
                        double xdRatio = FibRatio(xPoint, aPoint, dPoint);
                        
                        if(m_patternCount >= m_maxPatterns) return;

                        // Gartley
                        if(IsRatioValid(abRatio, 0.618, tolerance) && IsRatioValid(bcRatio, 0.382, tolerance) && IsRatioValid(xdRatio, 0.786, tolerance)) {
                            m_patterns[m_patternCount++].Set(PATTERN_GARTLEY, PATTERN_BEARISH, currentTimeValue, xPoint, aPoint, bPoint, cPoint, dPoint, dPoint, 0.8, true, true);
                        } 
                        // Butterfly
                        else if(IsRatioValid(abRatio, 0.786, tolerance) && IsRatioValid(bcRatio, 0.382, tolerance) && IsRatioValid(xdRatio, 1.27, tolerance)) {
                            m_patterns[m_patternCount++].Set(PATTERN_BUTTERFLY, PATTERN_BEARISH, currentTimeValue, xPoint, aPoint, bPoint, cPoint, dPoint, dPoint, 0.9, true, true);
                        }
                        // Bat
                        else if(IsRatioValid(abRatio, 0.5, tolerance) && IsRatioValid(bcRatio, 0.382, tolerance) && IsRatioValid(xdRatio, 0.886, tolerance)) {
                            m_patterns[m_patternCount++].Set(PATTERN_BAT, PATTERN_BEARISH, currentTimeValue, xPoint, aPoint, bPoint, cPoint, dPoint, dPoint, 0.85, true, true);
                        }
                    }
                }
            }
        }
    }
}

#endif // __STRATEGY_HARMONIC_PATTERNS_MQH__
