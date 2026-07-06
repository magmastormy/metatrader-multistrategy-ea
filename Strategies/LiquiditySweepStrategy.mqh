//+------------------------------------------------------------------+
//| LiquiditySweepStrategy.mqh                                       |
//| Liquidity Sweep / Stop Hunt Detection Strategy                   |
//| Detects when price briefly exceeds key levels then reverses      |
//| Algorithmic equivalent of ICT liquidity grab concept             |
//| Batch 114: New strategy — does NOT replace existing ICT/SMC      |
//+------------------------------------------------------------------+
#ifndef LIQUIDITY_SWEEP_STRATEGY_MQH
#define LIQUIDITY_SWEEP_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Utilities/SafeCopyBuffer.mqh"

//+------------------------------------------------------------------+
//| Liquidity Level Types                                             |
//+------------------------------------------------------------------+
enum ENUM_LIQUIDITY_LEVEL_TYPE
{
    LIQ_LEVEL_NONE = 0,
    LIQ_LEVEL_PREV_SESSION_HIGH,
    LIQ_LEVEL_PREV_SESSION_LOW,
    LIQ_LEVEL_DAILY_HIGH,
    LIQ_LEVEL_DAILY_LOW,
    LIQ_LEVEL_ROUND_NUMBER,
    LIQ_LEVEL_EQUAL_HIGHS,
    LIQ_LEVEL_EQUAL_LOWS
};

//+------------------------------------------------------------------+
//| Liquidity Sweep Signal Structure                                 |
//+------------------------------------------------------------------+
struct SLiquiditySweepSignal
{
    ENUM_TRADE_SIGNAL direction;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double confidence;
    string reason;
    double sweepLevel;         // The level that was swept
    double sweepWickSize;      // How far beyond the level
    ENUM_LIQUIDITY_LEVEL_TYPE levelType;

    SLiquiditySweepSignal() :
        direction(TRADE_SIGNAL_NONE),
        entryPrice(0),
        stopLoss(0),
        takeProfit(0),
        confidence(0),
        reason(""),
        sweepLevel(0),
        sweepWickSize(0),
        levelType(LIQ_LEVEL_NONE) {}
};

//+------------------------------------------------------------------+
//| CLiquiditySweepStrategy                                           |
//| Detects liquidity sweeps and enters on reversal                  |
//+------------------------------------------------------------------+
class CLiquiditySweepStrategy : public CStrategyBase
{
private:
    // Configuration
    double m_sweepThresholdATR;     // Min wick beyond level as ATR multiple (default: 0.3)
    int    m_atrPeriod;             // ATR period for threshold
    int    m_lookbackBars;          // Bars to look back for levels
    double m_sweepMinConfidence;     // Minimum confidence to generate signal (default: 0.6)
    double m_equalLevelTolerance;   // Points tolerance for equal highs/lows detection
    int    m_roundNumberPips;       // Round number spacing in pips (default: 50)

    // Indicator handles
    int    m_atrHandle;

    // Risk Manager
    CUnifiedRiskManager* m_riskManager;

    // State
    datetime m_lastSignalBar;
    string m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;

    //--- Find session levels (prev session high/low)
    void FindSessionLevels(double &prevSessionHigh, double &prevSessionLow,
                           double &dailyHigh, double &dailyLow)
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);

        // Get daily bars for the last 5 days
        int copied = CopyRates(m_symbol, PERIOD_D1, 0, 5, rates);
        if(copied < 2)
        {
            prevSessionHigh = 0;
            prevSessionLow = 0;
            dailyHigh = 0;
            dailyLow = 0;
            return;
        }

        // Previous session (yesterday)
        prevSessionHigh = rates[1].high;
        prevSessionLow = rates[1].low;

        // Daily high/low (today so far)
        dailyHigh = rates[0].high;
        dailyLow = rates[0].low;
    }

    //--- Find round number levels near current price
    void FindRoundNumbers(double currentPrice, double &levels[], int &levelCount)
    {
        levelCount = 0;
        ArrayResize(levels, 20);

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double pipValue = point * 10.0; // for 5-digit brokers
        double roundSpacing = m_roundNumberPips * pipValue;

        if(roundSpacing <= 0) return;

        double startLevel = MathFloor(currentPrice / roundSpacing) * roundSpacing;

        for(int i = -5; i <= 5 && levelCount < 20; i++)
        {
            double level = startLevel + i * roundSpacing;
            if(level > 0 && MathAbs(level - currentPrice) < roundSpacing * 2)
            {
                levels[levelCount] = level;
                levelCount++;
            }
        }
    }

    //--- Detect sweep of a level
    bool DetectSweep(double level, bool isHighLevel,
                     double high, double low, double close, double atr)
    {
        double threshold = m_sweepThresholdATR * atr;
        if(threshold <= 0) return false;

        if(isHighLevel)
        {
            // Sweep above: wick exceeds level but close is back below
            double wickAbove = high - level;
            return (wickAbove > 0 && wickAbove <= threshold && close < level);
        }
        else
        {
            // Sweep below: wick exceeds level but close is back above
            double wickBelow = level - low;
            return (wickBelow > 0 && wickBelow <= threshold && close > level);
        }
    }

    //--- Compute confidence based on sweep quality
    double ComputeConfidence(double sweepWick, double atr, double close,
                              double entryPrice, ENUM_LIQUIDITY_LEVEL_TYPE levelType)
    {
        double confidence = 0.5;

        // Factor 1: Wick quality (bigger wick = stronger rejection)
        double wickRatio = sweepWick / MathMax(1e-10, atr);
        confidence += MathMin(0.2, wickRatio * 0.3);

        // Factor 2: Close position (closer to opposite side = stronger)
        double bodyRange = MathAbs(close - entryPrice);
        if(bodyRange > 0 && atr > 0)
            confidence += MathMin(0.1, (bodyRange / atr) * 0.1);

        // Factor 3: Level type importance
        switch(levelType)
        {
            case LIQ_LEVEL_PREV_SESSION_HIGH:
            case LIQ_LEVEL_PREV_SESSION_LOW:
                confidence += 0.1; // Session levels are strong
                break;
            case LIQ_LEVEL_EQUAL_HIGHS:
            case LIQ_LEVEL_EQUAL_LOWS:
                confidence += 0.15; // Equal levels are strongest liquidity
                break;
            case LIQ_LEVEL_ROUND_NUMBER:
                confidence += 0.05; // Round numbers moderate
                break;
            default:
                break;
        }

        return MathMax(0.0, MathMin(1.0, confidence));
    }

    //--- Find equal highs/lows (liquidity pools)
    bool FindEqualLevels(double &equalHigh, double &equalLow, bool &hasEqualHigh, bool &hasEqualLow)
    {
        hasEqualHigh = false;
        hasEqualLow = false;
        equalHigh = 0;
        equalLow = 0;

        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookbackBars, rates);
        if(copied < 10) return false;

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double tolerance = m_equalLevelTolerance * point;

        // Find equal highs (two or more highs within tolerance)
        for(int i = 0; i < copied - 5; i++)
        {
            for(int j = i + 5; j < MathMin(i + 30, copied); j++)
            {
                if(MathAbs(rates[i].high - rates[j].high) < tolerance)
                {
                    equalHigh = MathMax(rates[i].high, rates[j].high);
                    hasEqualHigh = true;
                    break;
                }
            }
            if(hasEqualHigh) break;
        }

        // Find equal lows
        for(int i = 0; i < copied - 5; i++)
        {
            for(int j = i + 5; j < MathMin(i + 30, copied); j++)
            {
                if(MathAbs(rates[i].low - rates[j].low) < tolerance)
                {
                    equalLow = MathMin(rates[i].low, rates[j].low);
                    hasEqualLow = true;
                    break;
                }
            }
            if(hasEqualLow) break;
        }

        return (hasEqualHigh || hasEqualLow);
    }

    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;

        PrintFormat("[LIQ-SWEEP] Filtered: %s | Symbol=%s | TF=%s",
                   reasonTag, m_symbol, EnumToString(m_timeframe));
        m_lastRejectReasonTag = reasonTag;
        m_lastRejectLogTime = nowTime;
    }

public:
    CLiquiditySweepStrategy() :
        CStrategyBase("LiquiditySweep", 0),
        m_sweepThresholdATR(0.3),
        m_atrPeriod(14),
        m_lookbackBars(100),
        m_sweepMinConfidence(0.6),
        m_equalLevelTolerance(10),
        m_roundNumberPips(50),
        m_atrHandle(INVALID_HANDLE),
        m_riskManager(NULL),
        m_lastSignalBar(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0)
    {
    }

    ~CLiquiditySweepStrategy()
    {
        if(m_atrHandle != INVALID_HANDLE)
            IndicatorRelease(m_atrHandle);
    }

    //--- Initialize
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                    CUnifiedRiskManager* riskManager = NULL)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_riskManager = riskManager;

        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        return (m_atrHandle != INVALID_HANDLE);
    }

    //--- Configure
    void Configure(double sweepThresholdATR = 0.3, int lookbackBars = 100,
                   double minConfidence = 0.6, int roundNumberPips = 50)
    {
        m_sweepThresholdATR = MathMax(0.1, MathMin(1.0, sweepThresholdATR));
        m_lookbackBars = MathMax(20, lookbackBars);
        m_sweepMinConfidence = MathMax(0.3, MathMin(0.9, minConfidence));
        m_roundNumberPips = MathMax(10, roundNumberPips);
    }

    //--- Generate signal (called each bar)
    SLiquiditySweepSignal GetSignal()
    {
        SLiquiditySweepSignal signal;

        // ATR check
        if(m_atrHandle == INVALID_HANDLE)
            return signal;

        double atr[1];
        if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) != 1 || atr[0] <= 0)
            return signal;

        // Get current bar data
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(m_symbol, m_timeframe, 0, 2, rates) < 2)
            return signal;

        double high = rates[1].high;    // Previous bar (completed)
        double low = rates[1].low;
        double close = rates[1].close;
        double currentPrice = rates[0].close;

        // Find key levels
        double prevSessionHigh, prevSessionLow, dailyHigh, dailyLow;
        FindSessionLevels(prevSessionHigh, prevSessionLow, dailyHigh, dailyLow);

        // Find round numbers
        double roundLevels[];
        int roundCount = 0;
        FindRoundNumbers(currentPrice, roundLevels, roundCount);

        // Find equal highs/lows
        double equalHigh, equalLow;
        bool hasEqualHigh, hasEqualLow;
        FindEqualLevels(equalHigh, equalLow, hasEqualHigh, hasEqualLow);

        // Check for sweeps at each level type
        double bestConfidence = 0;
        double bestSweepLevel = 0;
        double bestSweepWick = 0;
        ENUM_LIQUIDITY_LEVEL_TYPE bestLevelType = LIQ_LEVEL_NONE;
        ENUM_TRADE_SIGNAL bestDirection = TRADE_SIGNAL_NONE;

        // Check session highs/lows
        if(prevSessionHigh > 0 && DetectSweep(prevSessionHigh, true, high, low, close, atr[0]))
        {
            double wick = high - prevSessionHigh;
            double conf = ComputeConfidence(wick, atr[0], close, prevSessionHigh, LIQ_LEVEL_PREV_SESSION_HIGH);
            if(conf > bestConfidence)
            {
                bestConfidence = conf;
                bestSweepLevel = prevSessionHigh;
                bestSweepWick = wick;
                bestLevelType = LIQ_LEVEL_PREV_SESSION_HIGH;
                bestDirection = TRADE_SIGNAL_SELL; // Sweep above → sell reversal
            }
        }

        if(prevSessionLow > 0 && DetectSweep(prevSessionLow, false, high, low, close, atr[0]))
        {
            double wick = prevSessionLow - low;
            double conf = ComputeConfidence(wick, atr[0], close, prevSessionLow, LIQ_LEVEL_PREV_SESSION_LOW);
            if(conf > bestConfidence)
            {
                bestConfidence = conf;
                bestSweepLevel = prevSessionLow;
                bestSweepWick = wick;
                bestLevelType = LIQ_LEVEL_PREV_SESSION_LOW;
                bestDirection = TRADE_SIGNAL_BUY; // Sweep below → buy reversal
            }
        }

        // Check daily levels
        if(dailyHigh > 0 && DetectSweep(dailyHigh, true, high, low, close, atr[0]))
        {
            double wick = high - dailyHigh;
            double conf = ComputeConfidence(wick, atr[0], close, dailyHigh, LIQ_LEVEL_DAILY_HIGH);
            if(conf > bestConfidence)
            {
                bestConfidence = conf;
                bestSweepLevel = dailyHigh;
                bestSweepWick = wick;
                bestLevelType = LIQ_LEVEL_DAILY_HIGH;
                bestDirection = TRADE_SIGNAL_SELL;
            }
        }

        if(dailyLow > 0 && DetectSweep(dailyLow, false, high, low, close, atr[0]))
        {
            double wick = dailyLow - low;
            double conf = ComputeConfidence(wick, atr[0], close, dailyLow, LIQ_LEVEL_DAILY_LOW);
            if(conf > bestConfidence)
            {
                bestConfidence = conf;
                bestSweepLevel = dailyLow;
                bestSweepWick = wick;
                bestLevelType = LIQ_LEVEL_DAILY_LOW;
                bestDirection = TRADE_SIGNAL_BUY;
            }
        }

        // Check equal highs/lows (strongest liquidity)
        if(hasEqualHigh && DetectSweep(equalHigh, true, high, low, close, atr[0]))
        {
            double wick = high - equalHigh;
            double conf = ComputeConfidence(wick, atr[0], close, equalHigh, LIQ_LEVEL_EQUAL_HIGHS);
            if(conf > bestConfidence)
            {
                bestConfidence = conf;
                bestSweepLevel = equalHigh;
                bestSweepWick = wick;
                bestLevelType = LIQ_LEVEL_EQUAL_HIGHS;
                bestDirection = TRADE_SIGNAL_SELL;
            }
        }

        if(hasEqualLow && DetectSweep(equalLow, false, high, low, close, atr[0]))
        {
            double wick = equalLow - low;
            double conf = ComputeConfidence(wick, atr[0], close, equalLow, LIQ_LEVEL_EQUAL_LOWS);
            if(conf > bestConfidence)
            {
                bestConfidence = conf;
                bestSweepLevel = equalLow;
                bestSweepWick = wick;
                bestLevelType = LIQ_LEVEL_EQUAL_LOWS;
                bestDirection = TRADE_SIGNAL_BUY;
            }
        }

        // Check round numbers
        for(int i = 0; i < roundCount; i++)
        {
            bool isHighLevel = (roundLevels[i] > currentPrice);
            if(DetectSweep(roundLevels[i], isHighLevel, high, low, close, atr[0]))
            {
                double wick = isHighLevel ? (high - roundLevels[i]) : (roundLevels[i] - low);
                double conf = ComputeConfidence(wick, atr[0], close, roundLevels[i], LIQ_LEVEL_ROUND_NUMBER);
                if(conf > bestConfidence)
                {
                    bestConfidence = conf;
                    bestSweepLevel = roundLevels[i];
                    bestSweepWick = wick;
                    bestLevelType = LIQ_LEVEL_ROUND_NUMBER;
                    bestDirection = isHighLevel ? TRADE_SIGNAL_SELL : TRADE_SIGNAL_BUY;
                }
            }
        }

        // Validate best signal
        if(bestConfidence < m_sweepMinConfidence)
        {
            LogRejectEvent("BELOW_MIN_CONFIDENCE");
            return signal;
        }

        if(bestDirection == TRADE_SIGNAL_NONE)
        {
            LogRejectEvent("NO_SWEEP_DETECTED");
            return signal;
        }

        // Same-bar filter
        datetime currentBarTime = rates[1].time;
        if(currentBarTime == m_lastSignalBar)
        {
            LogRejectEvent("SAME_BAR");
            return signal;
        }

        // Build signal
        signal.direction = bestDirection;
        signal.entryPrice = close; // Enter at close of sweep bar
        signal.sweepLevel = bestSweepLevel;
        signal.sweepWickSize = bestSweepWick;
        signal.levelType = bestLevelType;
        signal.confidence = bestConfidence;

        // SL/TP based on sweep structure
        if(bestDirection == TRADE_SIGNAL_BUY)
        {
            signal.stopLoss = bestSweepLevel - bestSweepWick * 0.5; // Below the sweep wick
            signal.takeProfit = close + (close - signal.stopLoss) * 2.0; // 2R target
        }
        else
        {
            signal.stopLoss = bestSweepLevel + bestSweepWick * 0.5; // Above the sweep wick
            signal.takeProfit = close - (signal.stopLoss - close) * 2.0; // 2R target
        }

        // Reason string
        string levelNames[] = {"NONE", "PREV_SESS_H", "PREV_SESS_L", "DAILY_H", "DAILY_L",
                               "ROUND_NUM", "EQUAL_HIGHS", "EQUAL_LOWS"};
        signal.reason = StringFormat("Sweep %s @ %.5f | wick=%.1f ATR | conf=%.2f",
                                      levelNames[bestLevelType], bestSweepLevel,
                                      bestSweepWick / atr[0], bestConfidence);

        m_lastSignalBar = currentBarTime;

        PrintFormat("[LIQ-SWEEP] SIGNAL | %s | %s | %s",
                   m_symbol,
                   bestDirection == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   signal.reason);

        return signal;
    }

    //--- Standard interface
    ENUM_STRATEGY_TYPE GetStrategyType() const { return STRATEGY_UNIFIED_ICT; }
    string GetStrategyName() const { return "LiquiditySweep"; }
};

#endif // LIQUIDITY_SWEEP_STRATEGY_MQH
