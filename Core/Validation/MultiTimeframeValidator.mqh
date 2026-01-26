//+------------------------------------------------------------------+
//| MultiTimeframeValidator.mqh                                      |
//| Multi-Timeframe Trade Validation Engine                         |
//| Prevents conflicting trades across timeframes                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __MULTI_TIMEFRAME_VALIDATOR_MQH__
#define __MULTI_TIMEFRAME_VALIDATOR_MQH__

#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Multi-Timeframe Validation Result                                |
//+------------------------------------------------------------------+
struct SMTFValidationResult
{
    bool isValid;
    string reason;
    double htfTrendStrength;
    double mtfTrendStrength;
    double ltfTrendStrength;
    ENUM_TREND_DIRECTION htfTrend;
    ENUM_TREND_DIRECTION mtfTrend;
    ENUM_TREND_DIRECTION ltfTrend;
    bool hasConflict;
    
    SMTFValidationResult() : isValid(false), reason(""), htfTrendStrength(0), mtfTrendStrength(0),
                            ltfTrendStrength(0), htfTrend(TREND_NONE), mtfTrend(TREND_NONE),
                            ltfTrend(TREND_NONE), hasConflict(false) {}
};

//+------------------------------------------------------------------+
//| Multi-Timeframe Validator Class                                  |
//+------------------------------------------------------------------+
class CMultiTimeframeValidator
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_entryTimeframe;
    
    // Trend detection
    ENUM_TREND_DIRECTION DetectTrend(const string symbol, ENUM_TIMEFRAMES tf, double &strength);
    bool CheckTrendAlignment(ENUM_TREND_DIRECTION htf, ENUM_TREND_DIRECTION mtf, ENUM_TREND_DIRECTION ltf, ENUM_TRADE_SIGNAL signal);
    
public:
    CMultiTimeframeValidator();
    ~CMultiTimeframeValidator();
    
    bool Initialize(const string symbol, ENUM_TIMEFRAMES entryTf);
    SMTFValidationResult ValidateSignal(ENUM_TRADE_SIGNAL signal, ENUM_TIMEFRAMES signalTf);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CMultiTimeframeValidator::CMultiTimeframeValidator() :
    m_symbol(""),
    m_entryTimeframe(PERIOD_CURRENT)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CMultiTimeframeValidator::~CMultiTimeframeValidator()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CMultiTimeframeValidator::Initialize(const string symbol, ENUM_TIMEFRAMES entryTf)
{
    m_symbol = symbol;
    m_entryTimeframe = entryTf;
    
    Print("[MTF-Validator] Initialized for ", symbol, " on ", EnumToString(entryTf));
    return true;
}

//+------------------------------------------------------------------+
//| Validate Multi-Timeframe Signal                                  |
//+------------------------------------------------------------------+
SMTFValidationResult CMultiTimeframeValidator::ValidateSignal(ENUM_TRADE_SIGNAL signal, ENUM_TIMEFRAMES signalTf)
{
    SMTFValidationResult result;
    
    if(signal == TRADE_SIGNAL_NONE)
    {
        result.isValid = false;
        result.reason = "No signal";
        return result;
    }
    
    // Determine higher and lower timeframes
    ENUM_TIMEFRAMES htf = PERIOD_H4;
    ENUM_TIMEFRAMES mtf = PERIOD_H1;
    ENUM_TIMEFRAMES ltf = signalTf;
    
    // Adjust based on signal timeframe
    if(signalTf == PERIOD_M5 || signalTf == PERIOD_M15)
    {
        htf = PERIOD_H4;
        mtf = PERIOD_H1;
        ltf = signalTf;
    }
    else if(signalTf == PERIOD_H1)
    {
        htf = PERIOD_D1;
        mtf = PERIOD_H4;
        ltf = PERIOD_H1;
    }
    else if(signalTf == PERIOD_H4)
    {
        htf = PERIOD_W1;
        mtf = PERIOD_D1;
        ltf = PERIOD_H4;
    }
    
    // Detect trends on all timeframes
    result.htfTrend = DetectTrend(m_symbol, htf, result.htfTrendStrength);
    result.mtfTrend = DetectTrend(m_symbol, mtf, result.mtfTrendStrength);
    result.ltfTrend = DetectTrend(m_symbol, ltf, result.ltfTrendStrength);
    
    // Check for conflicts
    result.hasConflict = false;
    
    // CRITICAL: HTF vs LTF conflict check
    if(signal == TRADE_SIGNAL_BUY)
    {
        // Buying into HTF downtrend = BAD
        if(result.htfTrend == TREND_BEARISH && result.htfTrendStrength > 60.0)
        {
            result.hasConflict = true;
            result.isValid = false;
            result.reason = "HTF downtrend conflict - buying into bearish H4/D1";
            return result;
        }
        
        // Buying when MTF is strongly bearish = RISKY
        if(result.mtfTrend == TREND_BEARISH && result.mtfTrendStrength > 70.0)
        {
            result.hasConflict = true;
            result.isValid = false;
            result.reason = "MTF strong downtrend - poor buy timing";
            return result;
        }
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        // Selling into HTF uptrend = BAD
        if(result.htfTrend == TREND_BULLISH && result.htfTrendStrength > 60.0)
        {
            result.hasConflict = true;
            result.isValid = false;
            result.reason = "HTF uptrend conflict - selling into bullish H4/D1";
            return result;
        }
        
        // Selling when MTF is strongly bullish = RISKY
        if(result.mtfTrend == TREND_BULLISH && result.mtfTrendStrength > 70.0)
        {
            result.hasConflict = true;
            result.isValid = false;
            result.reason = "MTF strong uptrend - poor sell timing";
            return result;
        }
    }
    
    // Check alignment
    if(CheckTrendAlignment(result.htfTrend, result.mtfTrend, result.ltfTrend, signal))
    {
        result.isValid = true;
        result.reason = "Multi-timeframe alignment confirmed";
    }
    else
    {
        result.isValid = true; // Allow but warn
        result.reason = "Trend alignment weak but acceptable";
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Detect Trend on Timeframe                                        |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION CMultiTimeframeValidator::DetectTrend(const string symbol, ENUM_TIMEFRAMES tf, double &strength)
{
    // Use EMAs for trend detection
    int ema20Handle = iMA(symbol, tf, 20, 0, MODE_EMA, PRICE_CLOSE);
    int ema50Handle = iMA(symbol, tf, 50, 0, MODE_EMA, PRICE_CLOSE);
    int ema200Handle = iMA(symbol, tf, 200, 0, MODE_EMA, PRICE_CLOSE);
    
    if(ema20Handle == INVALID_HANDLE || ema50Handle == INVALID_HANDLE || ema200Handle == INVALID_HANDLE)
    {
        strength = 0;
        return TREND_NONE;
    }
    
    double ema20[], ema50[], ema200[], close[];
    ArraySetAsSeries(ema20, true);
    ArraySetAsSeries(ema50, true);
    ArraySetAsSeries(ema200, true);
    ArraySetAsSeries(close, true);
    
    if(CopyBuffer(ema20Handle, 0, 0, 3, ema20) <= 0 ||
       CopyBuffer(ema50Handle, 0, 0, 3, ema50) <= 0 ||
       CopyBuffer(ema200Handle, 0, 0, 3, ema200) <= 0 ||
       CopyClose(symbol, tf, 0, 3, close) <= 0)
    {
        IndicatorRelease(ema20Handle);
        IndicatorRelease(ema50Handle);
        IndicatorRelease(ema200Handle);
        strength = 0;
        return TREND_NONE;
    }
    
    // Calculate trend
    ENUM_TREND_DIRECTION trend = TREND_NONE;
    strength = 50.0;
    
    // Bullish: 20 > 50 > 200 and price > 20
    if(ema20[0] > ema50[0] && ema50[0] > ema200[0] && close[0] > ema20[0])
    {
        trend = TREND_BULLISH;
        
        // Calculate strength based on separation
        double separation20_50 = ((ema20[0] - ema50[0]) / ema50[0]) * 1000;
        double separation50_200 = ((ema50[0] - ema200[0]) / ema200[0]) * 1000;
        
        strength = 50.0 + (separation20_50 * 5) + (separation50_200 * 3);
        strength = MathMin(100.0, strength);
    }
    // Bearish: 20 < 50 < 200 and price < 20
    else if(ema20[0] < ema50[0] && ema50[0] < ema200[0] && close[0] < ema20[0])
    {
        trend = TREND_BEARISH;
        
        // Calculate strength based on separation
        double separation20_50 = ((ema50[0] - ema20[0]) / ema50[0]) * 1000;
        double separation50_200 = ((ema200[0] - ema50[0]) / ema200[0]) * 1000;
        
        strength = 50.0 + (separation20_50 * 5) + (separation50_200 * 3);
        strength = MathMin(100.0, strength);
    }
    
    IndicatorRelease(ema20Handle);
    IndicatorRelease(ema50Handle);
    IndicatorRelease(ema200Handle);
    
    return trend;
}

//+------------------------------------------------------------------+
//| Check Trend Alignment                                            |
//+------------------------------------------------------------------+
bool CMultiTimeframeValidator::CheckTrendAlignment(ENUM_TREND_DIRECTION htf, ENUM_TREND_DIRECTION mtf, ENUM_TREND_DIRECTION ltf, ENUM_TRADE_SIGNAL signal)
{
    if(signal == TRADE_SIGNAL_BUY)
    {
        // Best case: all bullish or neutral
        if((htf == TREND_BULLISH || htf == TREND_NONE) &&
           (mtf == TREND_BULLISH || mtf == TREND_NONE) &&
           ltf == TREND_BULLISH)
        {
            return true;
        }
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        // Best case: all bearish or neutral
        if((htf == TREND_BEARISH || htf == TREND_NONE) &&
           (mtf == TREND_BEARISH || mtf == TREND_NONE) &&
           ltf == TREND_BEARISH)
        {
            return true;
        }
    }
    
    return false;
}

#endif // __MULTI_TIMEFRAME_VALIDATOR_MQH__
