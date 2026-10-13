// Liquidity sweep / stop hunt: price briefly pierces a key level, then closes back inside it.
#ifndef LIQUIDITY_SWEEP_STRATEGY_MQH
#define LIQUIDITY_SWEEP_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Utilities/SafeCopyBuffer.mqh"

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

class CLiquiditySweepStrategy : public CStrategyBase
{
private:
    double m_sweepThresholdATR;     // Min wick beyond level as ATR multiple (default: 0.3)
    int    m_atrPeriod;             // ATR period for threshold
    int    m_lookbackBars;          // Bars to look back for levels
    double m_sweepMinConfidence;     // Minimum confidence to generate signal (default: 0.6)
    double m_equalLevelTolerance;   // Points tolerance for equal highs/lows detection
    int    m_roundNumberPips;       // Round number spacing in pips (default: 50)

    int    m_atrHandle;

    CUnifiedRiskManager* m_riskManager;

    datetime m_lastSignalBar;

    void FindSessionLevels(double &prevSessionHigh, double &prevSessionLow,
                           double &dailyHigh, double &dailyLow)
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);

        // PERIOD_D1 bars, series order; fewer than 2 copied = fail closed (all four levels stay 0)
        int copied = CopyRates(m_symbol, PERIOD_D1, 0, 5, rates);
        if(copied < 2)
        {
            prevSessionHigh = 0;
            prevSessionLow = 0;
            dailyHigh = 0;
            dailyLow = 0;
            return;
        }

        // rates[1] = last completed daily bar, rates[0] = the still-forming one
        prevSessionHigh = rates[1].high;
        prevSessionLow = rates[1].low;

        dailyHigh = rates[0].high;
        dailyLow = rates[0].low;
    }

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

    bool DetectSweep(double level, bool isHighLevel,
                     double high, double low, double close, double atr)
    {
        double threshold = m_sweepThresholdATR * atr;
        if(threshold <= 0) return false;

        if(isHighLevel)
        {
            // Sweep above: wick pierces the level, close returns below it; a pierce past the ATR cap is a breakout
            double wickAbove = high - level;
            return (wickAbove > 0 && wickAbove <= threshold && close < level);
        }
        else
        {
            // Sweep below: mirror rule - wick pierces from underneath, close returns above
            double wickBelow = level - low;
            return (wickBelow > 0 && wickBelow <= threshold && close > level);
        }
    }

    double ComputeConfidence(double sweepWick, double atr, double close,
                              double entryPrice, ENUM_LIQUIDITY_LEVEL_TYPE levelType)
    {
        double confidence = 0.5;

        double wickRatio = sweepWick / MathMax(1e-10, atr);
        confidence += MathMin(0.2, wickRatio * 0.3);

        double bodyRange = MathAbs(close - entryPrice);
        if(bodyRange > 0 && atr > 0)
            confidence += MathMin(0.1, (bodyRange / atr) * 0.1);

        switch(levelType)
        {
            case LIQ_LEVEL_PREV_SESSION_HIGH:
            case LIQ_LEVEL_PREV_SESSION_LOW:
                confidence += 0.1; // Session levels are strong
                break;
            case LIQ_LEVEL_DAILY_HIGH:
            case LIQ_LEVEL_DAILY_LOW:
                confidence += 0.1; // Daily extremes carry major resting liquidity
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

    bool FindEqualLevels(double &equalHigh, double &equalLow, bool &hasEqualHigh, bool &hasEqualLow)
    {
        hasEqualHigh = false;
        hasEqualLow = false;
        equalHigh = 0;
        equalLow = 0;

        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        // closed bars only (shift 1): otherwise the live bar's own high counts as one of the equal highs it is being swept into
        // fewer than 10 closed bars scanned = no pools at all
        int copied = CopyRates(m_symbol, m_timeframe, 1, m_lookbackBars, rates);
        if(copied < 10) return false;

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double tolerance = m_equalLevelTolerance * point;

        // equal highs = two highs within `tolerance` (points) and 5-29 bars apart
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
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "LIQ-SWEEP";
    }

    ~CLiquiditySweepStrategy()
    {
        if(m_atrHandle != INVALID_HANDLE)
            IndicatorRelease(m_atrHandle);
    }

    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                    CUnifiedRiskManager* riskManager = NULL)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_riskManager = riskManager;

        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        return (m_atrHandle != INVALID_HANDLE);
    }

    void Configure(double sweepThresholdATR = 0.6, int lookbackBars = 100,
                   double minConfidence = 0.6, int roundNumberPips = 50)
    {
        m_sweepThresholdATR = MathMax(0.1, MathMin(1.0, sweepThresholdATR));
        m_lookbackBars = MathMax(20, lookbackBars);
        m_sweepMinConfidence = MathMax(0.3, MathMin(0.9, minConfidence));
        m_roundNumberPips = MathMax(10, roundNumberPips);
    }

    SLiquiditySweepSignal GetSignal()
    {
        SLiquiditySweepSignal signal;

        if(m_atrHandle == INVALID_HANDLE)
            return signal;

        double atr[1];
        // ATR at shift 1: shift 0 would move the sweep cap with the tick being judged
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0)
            return signal;

        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(m_symbol, m_timeframe, 0, 2, rates) < 2)
            return signal;

        double high = rates[1].high;    // Previous bar (completed)
        double low = rates[1].low;
        double close = rates[1].close;
        double currentPrice = rates[0].close;

        double prevSessionHigh, prevSessionLow, dailyHigh, dailyLow;
        FindSessionLevels(prevSessionHigh, prevSessionLow, dailyHigh, dailyLow);

        double roundLevels[];
        int roundCount = 0;
        FindRoundNumbers(currentPrice, roundLevels, roundCount);

        double equalHigh, equalLow;
        bool hasEqualHigh, hasEqualLow;
        FindEqualLevels(equalHigh, equalLow, hasEqualHigh, hasEqualLow);

        double bestConfidence = 0;
        double bestSweepLevel = 0;
        double bestSweepWick = 0;
        ENUM_LIQUIDITY_LEVEL_TYPE bestLevelType = LIQ_LEVEL_NONE;
        ENUM_TRADE_SIGNAL bestDirection = TRADE_SIGNAL_NONE;

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

        // Same sweep bar only votes once
        datetime currentBarTime = rates[1].time;
        if(currentBarTime == m_lastSignalBar)
        {
            LogRejectEvent("SAME_BAR");
            return signal;
        }

        signal.direction = bestDirection;
        signal.entryPrice = close; // Enter at close of sweep bar
        signal.sweepLevel = bestSweepLevel;
        signal.sweepWickSize = bestSweepWick;
        signal.levelType = bestLevelType;
        signal.confidence = bestConfidence;

        // stop sits past the sweep extreme (level +/- 1.1x the wick); inside the wick it is already-traded price
        if(bestDirection == TRADE_SIGNAL_BUY)
        {
            signal.stopLoss = bestSweepLevel - bestSweepWick * 1.1; // Beyond the swept extreme
            signal.takeProfit = close + (close - signal.stopLoss) * 2.0; // 2R target
        }
        else
        {
            signal.stopLoss = bestSweepLevel + bestSweepWick * 1.1; // Beyond the swept extreme
            signal.takeProfit = close - (signal.stopLoss - close) * 2.0; // 2R target
        }

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

    // Consensus vote entry point: CStrategyBase::GetSignal(double&) forwards to this ExecuteSignal override.
    // SL/TP are stashed for the execution path (used only when InpUseStrategyStops is on); this class places no orders and gates no risk.
    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence)
    {
        SLiquiditySweepSignal sig = GetSignal();
        confidence = sig.confidence;
        m_lastDecisionReasonTag = sig.reason;
        if(sig.direction != TRADE_SIGNAL_NONE && sig.entryPrice > 0)
        {
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(point > 0)
                SetProposedStops(MathAbs(sig.entryPrice - sig.stopLoss) / point,
                                 MathAbs(sig.takeProfit - sig.entryPrice) / point);
        }
        return sig.direction;
    }

    // Must be GetType(): CStrategyBase::GetType() returns STRATEGY_TYPE_CUSTOM, and a lookalike name here
    // meant the consensus regime gate and category multiplier never saw this strategy's type.
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_LIQUIDITY_SWEEP; }

    void Deinit()
    {
        // owns its ATR handle: released and invalidated here so the destructor never releases it twice
        if(m_atrHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
        }
        m_riskManager = NULL;
    }
};

#endif // LIQUIDITY_SWEEP_STRATEGY_MQH
