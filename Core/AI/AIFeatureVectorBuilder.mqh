//+------------------------------------------------------------------+
//| AIFeatureVectorBuilder.mqh                                       |
//| Shared AI feature construction for NN/Transformer/Ensemble paths |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_AI_FEATURE_VECTOR_BUILDER_MQH
#define CORE_AI_FEATURE_VECTOR_BUILDER_MQH

// AI Model Configuration Constants
#define TRANSFORMER_D_MODEL_DEFAULT         64
#define TRANSFORMER_NUM_HEADS_DEFAULT        4
#define TRANSFORMER_NUM_LAYERS_A_DEFAULT     2
#define TRANSFORMER_D_FF_DEFAULT           128
#define TRANSFORMER_D_FF_B_DEFAULT          96
#define TRANSFORMER_MAX_SEQ_LEN_DEFAULT     50
#define TRANSFORMER_SHORT_SEQ_LEN_DEFAULT   10
#define TRANSFORMER_DROPOUT_DEFAULT TRANSFORMER_MAX_SEQ_LEN_DEFAULT
#define TRANSFORMER_LR_A_DEFAULT           0.001
#define TRANSFORMER_LR_B_DEFAULT          0.0015
#define FEATURE_VECTOR_SIZE               50
#define TEMPORAL_BLEND_CURRENT            0.85
#define TEMPORAL_BLEND_LAG                0.15
#define DMODE_BASE_FEATURE_RATIO_WARNING   6

#include "../../IndicatorManager.mqh"
#include "../Engines/StructureEngine.mqh"
#include "../../Strategies/UnifiedICTFiles/AdvancedOrderBlocks.mqh"
#include "../../Strategies/UnifiedICTFiles/ImbalanceDetector.mqh"

class CAIFeatureVectorBuilder
{
private:
    static double GetIndicatorValue(const int handle, const int buffer, const int shift)
    {
        if(handle == INVALID_HANDLE)
            return 0.0;

        // Check if handle is ready
        if(BarsCalculated(handle) < shift + 1)
            return 0.0;

        double value[1];
        if(CopyBuffer(handle, buffer, shift, 1, value) > 0)
        {
            if(!MathIsValidNumber(value[0])) return 0.0;
            return value[0];
        }

        return 0.0;
    }

    static int GetRequiredBarsForTimeframe(ENUM_TIMEFRAMES timeframe)
    {
        // AUDIT FIX: Timeframe-aware history check
        // Higher timeframes need fewer bars, lower timeframes need more
        switch(timeframe)
        {
            case PERIOD_M1:  return 200;  // M1: need more bars for stability
            case PERIOD_M5:  return 150;
            case PERIOD_M15: return 100;
            case PERIOD_M30: return 80;
            case PERIOD_H1:  return 60;
            case PERIOD_H4:  return 50;
            case PERIOD_D1:  return 30;
            case PERIOD_W1:  return 20;
            case PERIOD_MN1: return 12;
            default:         return 50;   // Default for other timeframes
        }
    }
    
    static bool IsDataReady(const string symbol, const ENUM_TIMEFRAMES timeframe, const int requiredBars)
    {
        int available = Bars(symbol, timeframe);
        if(available < requiredBars)
        {
            static datetime lastLog = 0;
            if(TimeCurrent() - lastLog > 60) {
                PrintFormat("[AI-DATA] Waiting for history: %s %s | available=%d | required=%d", 
                            symbol, EnumToString(timeframe), available, requiredBars);
                lastLog = TimeCurrent();
            }
            return false;
        }
        
        if(iTime(symbol, timeframe, requiredBars - 1) <= 0)
            return false;

        return true;
    }

    static double GetNormalizedValue(const double minValue, const double maxValue, const double value)
    {
        double range = maxValue - minValue;
        if(range <= 1e-9)
            return 0.0;
        return (value - minValue) / range;
    }

    static bool IsKillZoneTime(const int hour)
    {
        // Match NeuralNetworkStrategy session semantics.
        return (hour >= 2 && hour <= 5) || (hour >= 7 && hour <= 10) || (hour >= 20 && hour <= 23);
    }

public:
    static bool BuildNNFeatureVector(const string symbol,
                                     const ENUM_TIMEFRAMES timeframe,
                                     double &features[],
                                     const int barShift = 1)
    {
        ArrayResize(features, FEATURE_VECTOR_SIZE);
        ArrayInitialize(features, 0.0);

        if(symbol == "" || barShift < 1)
            return false;

        // AUDIT FIX: Timeframe-aware history check instead of fixed 50 bars
        int requiredBars = GetRequiredBarsForTimeframe(timeframe);
        if(!IsDataReady(symbol, timeframe, barShift + requiredBars))
        {
            static datetime s_lastHistoryLog = 0;
            datetime now = TimeCurrent();
            if(s_lastHistoryLog == 0 || (now - s_lastHistoryLog) >= 60)
            {
                int available = Bars(symbol, timeframe);
                PrintFormat("[AI-FEATURE] History not ready for %s %s | available=%d | required=%d | barShift=%d",
                            symbol, EnumToString(timeframe), available, barShift + requiredBars, barShift);
                s_lastHistoryLog = now;
            }
            return false;
        }

        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return false;

        double close = iClose(symbol, timeframe, barShift);
        if(close <= 0.0)
            close = SymbolInfoDouble(symbol, SYMBOL_BID);

        if(close <= 0.0) return false; // Critical failure

        double open = iOpen(symbol, timeframe, barShift);
        double high = iHigh(symbol, timeframe, barShift);
        double low = iLow(symbol, timeframe, barShift);
        double closePrev = iClose(symbol, timeframe, barShift + 1);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001;

        // Fetch handles and check readiness
        int hMaFast = ind.GetMAHandle(symbol, timeframe, 9, 0, MODE_EMA, PRICE_CLOSE);
        int hMaSlow = ind.GetMAHandle(symbol, timeframe, 21, 0, MODE_EMA, PRICE_CLOSE);
        int hEma200 = ind.GetMAHandle(symbol, timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
        int hAdx = ind.GetADXHandle(symbol, timeframe, 14);
        int hRsi = ind.GetRSIHandle(symbol, timeframe, 14, PRICE_CLOSE);
        int hAtrFast = ind.GetATRHandle(symbol, timeframe, 14);
        int hAtrSlow = ind.GetATRHandle(symbol, timeframe, 50);
        int hBands = ind.GetBandsHandle(symbol, timeframe, 20, 0, 2.0, PRICE_CLOSE);
        int hMacd = ind.GetMACDHandle(symbol, timeframe, 12, 26, 9, PRICE_CLOSE);
        int hCci = ind.GetCCIHandle(symbol, timeframe, 14, PRICE_CLOSE);

        // Tolerant indicator check - check each indicator individually
        // Use available indicators with sensible defaults for warming ones
        // Only fail if ALL critical indicators are warming
        bool ema200Ready = (BarsCalculated(hEma200) >= barShift + 1);
        bool atrSlowReady = (BarsCalculated(hAtrSlow) >= barShift + 1);
        bool adxReady = (BarsCalculated(hAdx) >= barShift + 1);
        bool rsiReady = (BarsCalculated(hRsi) >= barShift + 1);

        bool anyReady = (ema200Ready || atrSlowReady || adxReady || rsiReady);
        bool allWarming = !anyReady;

        if(allWarming)
        {
            static datetime s_lastIndicatorLog = 0;
            datetime now = TimeCurrent();
            if(s_lastIndicatorLog == 0 || (now - s_lastIndicatorLog) >= 60)
            {
                // [DIAGNOSTIC] Log whether the indicator calculation failed entirely (-1) or is just waiting for history bars
                PrintFormat("[AI-FEATURE] ALL indicators warming up (or failed) for %s %s | EMA200=%d | ATR50=%d | ADX=%d | RSI=%d | barShift=%d | Skipping AI feature build",
                            symbol, EnumToString(timeframe),
                            BarsCalculated(hEma200), BarsCalculated(hAtrSlow),
                            BarsCalculated(hAdx), BarsCalculated(hRsi), barShift);
                s_lastIndicatorLog = now;
            }
            return false; // Cannot build features if ALL indicators are warming
        }

        // Log partial indicator readiness (non-blocking diagnostic)
        static datetime s_lastPartialLog = 0;
        datetime now = TimeCurrent();
        if(now - s_lastPartialLog >= 120) // Log every 2 minutes
        {
            string readyStatus = StringFormat("EMA200=%s | ATR50=%s | ADX=%s | RSI=%s",
                                              ema200Ready ? "READY" : "WARMING",
                                              atrSlowReady ? "READY" : "WARMING",
                                              adxReady ? "READY" : "WARMING",
                                              rsiReady ? "READY" : "WARMING");
            PrintFormat("[AI-FEATURE] Partial indicator readiness for %s %s | %s | Proceeding with available indicators",
                        symbol, EnumToString(timeframe), readyStatus);
            s_lastPartialLog = now;
        }

        double maFast = GetIndicatorValue(hMaFast, 0, barShift);
        double maSlow = GetIndicatorValue(hMaSlow, 0, barShift);
        double ema200 = GetIndicatorValue(hEma200, 0, barShift);
        double adx = GetIndicatorValue(hAdx, 0, barShift);
        double rsi = GetIndicatorValue(hRsi, 0, barShift);
        double rsiPrev = GetIndicatorValue(hRsi, 0, barShift + 1);
        double atrFast = GetIndicatorValue(hAtrFast, 0, barShift);
        double atrSlow = GetIndicatorValue(hAtrSlow, 0, barShift);

        // Fallback values for warming indicators to provide meaningful features
        if(!ema200Ready && ema200 <= 0.0)
            ema200 = close; // Use current price if EMA200 not ready
        if(!atrSlowReady && atrSlow <= 0.0)
            atrSlow = atrFast; // Use fast ATR if slow ATR not ready
        if(!adxReady && adx <= 0.0)
            adx = 20.0; // Neutral ADX value (moderate trend)
        if(!rsiReady && rsi <= 0.0)
        {
            rsi = 50.0; // Neutral RSI value
            rsiPrev = 50.0;
        }
        double bbUpper = GetIndicatorValue(hBands, 1, barShift);
        double bbLower = GetIndicatorValue(hBands, 2, barShift);
        double macdMain = GetIndicatorValue(hMacd, 0, barShift);
        double macdSignal = GetIndicatorValue(hMacd, 1, barShift);
        double cci = GetIndicatorValue(hCci, 0, barShift);

        // 0-4: Market structure
        features[0] = (maFast > maSlow) ? 1.0 : (maFast < maSlow) ? -1.0 : 0.0;
        features[1] = GetNormalizedValue(0.0, 100.0, adx);
        features[2] = GetNormalizedValue(0.0, 100.0, rsi);
        features[3] = (close > ema200) ? 1.0 : -1.0;
        double atrPercent = (close > 0.0) ? (atrFast / close) * 100.0 : 0.0;
        features[4] = GetNormalizedValue(0.0, 5.0, atrPercent);

        // 5-9: Oscillator / reversion
        features[5] = (rsi > 70.0) ? 1.0 : (rsi < 30.0) ? -1.0 : 0.0;
        double bbBasis = (bbUpper - bbLower > 0.0) ? (close - bbLower) / (bbUpper - bbLower) : 0.5;
        features[6] = MathMin(1.0, MathMax(0.0, bbBasis));
        double macdHist = macdMain - macdSignal;
        features[7] = (macdHist > 0.0) ? 1.0 : -1.0;
        features[8] = (rsi - rsiPrev) / 100.0;
        features[9] = GetNormalizedValue(-200.0, 200.0, cci);

        // 10-14: Volume / liquidity proxy
        long volume = iVolume(symbol, timeframe, barShift);
        long volumePrev = iVolume(symbol, timeframe, barShift + 1);
        features[10] = (volume > volumePrev) ? 1.0 : 0.0;
        features[11] = (rsi > 50.0 && volume > volumePrev) ? 1.0 : 0.0;
        double high20 = iHigh(symbol, timeframe, iHighest(symbol, timeframe, MODE_HIGH, 20, barShift));
        double low20 = iLow(symbol, timeframe, iLowest(symbol, timeframe, MODE_LOW, 20, barShift));
        features[12] = (close >= high20) ? 1.0 : (close <= low20) ? -1.0 : 0.0;
        double candleRangePercent = (close > 0.0) ? ((high - low) / close) * 100.0 : 0.0;
        features[13] = GetNormalizedValue(0.0, 2.0, candleRangePercent);
        features[14] = (open > closePrev) ? 1.0 : (open < closePrev) ? -1.0 : 0.0;

        // 15-19: Price action
        double body = MathAbs(close - open);
        double range = high - low;
        double bodyRatio = (range > 0.0) ? body / range : 0.0;
        features[15] = bodyRatio;
        features[16] = (close > open) ? 1.0 : -1.0;
        double upperWick = (close > open) ? (high - close) : (high - open);
        double lowerWick = (close > open) ? (open - low) : (close - low);
        features[17] = (range > 0.0) ? upperWick / range : 0.0;
        features[18] = (range > 0.0) ? lowerWick / range : 0.0;
        double highPrev = iHigh(symbol, timeframe, barShift + 1);
        double lowPrev = iLow(symbol, timeframe, barShift + 1);
        bool insideBar = (high < highPrev) && (low > lowPrev);
        features[19] = insideBar ? 1.0 : 0.0;

        // 20-22: Time/context
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        features[20] = dt.hour / 24.0;
        features[21] = dt.day_of_week / 7.0;
        features[22] = IsKillZoneTime(dt.hour) ? 1.0 : 0.0;

        // 23-24: Tail context
        features[23] = (atrSlow > 0.0) ? MathMin(2.0, atrFast / atrSlow) : 1.0;
        features[24] = 1.0;

        // --- Pattern-Specific Features (Features 25-43) ---
        // 25-29: Higher Highs / Lower Lows Sequences
        double highs[5], lows[5];
        int hhCount = 0, llCount = 0;
        for(int i = 0; i < 5; i++) {
            highs[i] = iHigh(symbol, timeframe, barShift + i);
            lows[i] = iLow(symbol, timeframe, barShift + i);
            if(i > 0) {
                if(highs[i] > highs[i-1]) hhCount++;
                if(lows[i] < lows[i-1]) llCount++;
            }
        }
        features[25] = hhCount / 4.0;  // Higher highs ratio
        features[26] = llCount / 4.0;  // Lower lows ratio
        features[27] = (highs[0] > highs[4]) ? 1.0 : -1.0;  // Overall trend
        features[28] = (highs[0] > highs[2]) ? 1.0 : -1.0;  // Recent trend
        features[29] = (lows[0] < lows[2]) ? 1.0 : -1.0;  // Recent lows trend

        // 30-32: Support/Resistance Touch Counts
        double supportLevel = iLow(symbol, timeframe, iLowest(symbol, timeframe, MODE_LOW, 20, barShift));
        double resistanceLevel = iHigh(symbol, timeframe, iHighest(symbol, timeframe, MODE_HIGH, 20, barShift));
        int supportTouches = 0, resistanceTouches = 0;
        for(int i = 0; i < 20; i++) {
            double barLow = iLow(symbol, timeframe, barShift + i);
            double barHigh = iHigh(symbol, timeframe, barShift + i);
            if(resistanceLevel > 0 && MathAbs(barHigh - resistanceLevel) / resistanceLevel < 0.005) resistanceTouches++;
            if(supportLevel > 0 && MathAbs(barLow - supportLevel) / supportLevel < 0.005) supportTouches++;
        }
        features[30] = supportTouches / 20.0;
        features[31] = resistanceTouches / 20.0;
        features[32] = (resistanceLevel - supportLevel > 0) ? (close - supportLevel) / (resistanceLevel - supportLevel) : 0.5;

        // 33-35: Fibonacci Retracement Level Proximity
        // AUDIT FIX: Use timeframe-aware swing lookback instead of fixed 50 bars
        int swingLookback = GetRequiredBarsForTimeframe(timeframe);
        double swingHigh = iHigh(symbol, timeframe, iHighest(symbol, timeframe, MODE_HIGH, swingLookback, barShift));
        double swingLow = iLow(symbol, timeframe, iLowest(symbol, timeframe, MODE_LOW, swingLookback, barShift));
        double fibRange = swingHigh - swingLow;
        if(fibRange > 0) {
            double fib382 = swingLow + fibRange * 0.382;
            double fib500 = swingLow + fibRange * 0.500;
            double fib618 = swingLow + fibRange * 0.618;
            features[33] = 1.0 - MathMin(1.0, MathAbs(close - fib382) / fibRange);
            features[34] = 1.0 - MathMin(1.0, MathAbs(close - fib500) / fibRange);
            features[35] = 1.0 - MathMin(1.0, MathAbs(close - fib618) / fibRange);
        }

        // 36-38: Pivot Point Proximity
        double pivot = (high + low + close) / 3.0;
        double r1 = 2 * pivot - low;
        double s1 = 2 * pivot - high;
        if(pivot > 0) {
            features[36] = 1.0 - MathMin(1.0, MathAbs(close - pivot) / pivot);
            features[37] = 1.0 - MathMin(1.0, MathAbs(close - r1) / r1);
            features[38] = 1.0 - MathMin(1.0, MathAbs(close - s1) / s1);
        }

        // 39-43: Price Distance from Moving Averages
        // Cache handles locally to prevent repeated lookups
        int hMA5 = ind.GetMAHandle(symbol, timeframe, 5, 0, MODE_SMA, PRICE_CLOSE);
        int hMA10 = ind.GetMAHandle(symbol, timeframe, 10, 0, MODE_SMA, PRICE_CLOSE);
        int hMA20 = ind.GetMAHandle(symbol, timeframe, 20, 0, MODE_SMA, PRICE_CLOSE);
        int hMA50 = ind.GetMAHandle(symbol, timeframe, 50, 0, MODE_SMA, PRICE_CLOSE);
        int hMA100 = ind.GetMAHandle(symbol, timeframe, 100, 0, MODE_SMA, PRICE_CLOSE);
        
        double ma5 = GetIndicatorValue(hMA5, 0, barShift);
        double ma10 = GetIndicatorValue(hMA10, 0, barShift);
        double ma20 = GetIndicatorValue(hMA20, 0, barShift);
        double ma50 = GetIndicatorValue(hMA50, 0, barShift);
        double ma100 = GetIndicatorValue(hMA100, 0, barShift);
        
        if(ma5 > 0) features[39] = (close - ma5) / ma5;
        if(ma10 > 0) features[40] = (close - ma10) / ma10;
        if(ma20 > 0) features[41] = (close - ma20) / ma20;
        if(ma50 > 0) features[42] = (close - ma50) / ma50;
        if(ma100 > 0) features[43] = (close - ma100) / ma100;

        // --- Advanced ICT Features (Features 44-49) ---
        // 44-45: Order Block Proximity
        bool obSuccess = true;
        CAdvancedOrderBlockDetector obDetector;
        if(obDetector.Initialize(symbol, timeframe))
        {
            obDetector.ScanForOrderBlocks(100);
            int bestBullOB = obDetector.FindBestBullishOB();
            int bestBearOB = obDetector.FindBestBearishOB();
            SAdvancedOrderBlock ob;
            if(bestBullOB >= 0 && obDetector.GetOrderBlock(bestBullOB, ob))
                features[44] = (ob.top > 0) ? 1.0 - MathMin(1.0, MathAbs(close - ob.top) / ob.top) : 0.0;
            if(bestBearOB >= 0 && obDetector.GetOrderBlock(bestBearOB, ob))
                features[45] = (ob.bottom > 0) ? 1.0 - MathMin(1.0, MathAbs(close - ob.bottom) / ob.bottom) : 0.0;
        }
        else
        {
            obSuccess = false;
        }

        // 46-47: Fair Value Gap (Imbalance) Proximity
        bool imbSuccess = true;
        CImbalanceDetector imbDetector;
        if(imbDetector.Initialize(symbol, timeframe))
        {
            imbDetector.ScanForImbalances(100);
            int bestBullImb = imbDetector.FindBestBullishImbalance();
            int bestBearImb = imbDetector.FindBestBearishImbalance();
            SImbalance imb;
            if(bestBullImb >= 0 && imbDetector.GetImbalance(bestBullImb, imb))
                features[46] = (imb.top > 0) ? 1.0 - MathMin(1.0, MathAbs(close - imb.top) / imb.top) : 0.0;
            if(bestBearImb >= 0 && imbDetector.GetImbalance(bestBearImb, imb))
                features[47] = (imb.bottom > 0) ? 1.0 - MathMin(1.0, MathAbs(close - imb.bottom) / imb.bottom) : 0.0;
        }
        else
        {
            imbSuccess = false;
        }

        // 48-49: Market Structure State (BOS/CHOCH)
        bool structSuccess = true;
        CStructureEngine structEngine;
        if(structEngine.Initialize())
        {
            structEngine.DetectSwingPoints(symbol, timeframe);
            features[48] = structEngine.IsBullishStructure() ? 1.0 : (structEngine.IsBearishStructure() ? -1.0 : 0.0);
            features[49] = structEngine.GetStructureStrength() / 100.0;
        }
        else
        {
            structSuccess = false;
        }

        // Log advanced feature failures (non-blocking, just diagnostic)
        if(!obSuccess || !imbSuccess || !structSuccess)
        {
            static datetime s_lastAdvFeatLog = 0;
            datetime now = TimeCurrent();
            if(s_lastAdvFeatLog == 0 || (now - s_lastAdvFeatLog) >= 60)
            {
                PrintFormat("[AI-FEATURE] Advanced features partial for %s %s | OB=%s | IMB=%s | STRUCT=%s",
                            symbol, EnumToString(timeframe),
                            obSuccess ? "OK" : "FAIL",
                            imbSuccess ? "OK" : "FAIL",
                            structSuccess ? "OK" : "FAIL");
                s_lastAdvFeatLog = now;
            }
        }

        return true;
    }

    static bool BuildTransformerInput(const string symbol,
                                      const ENUM_TIMEFRAMES timeframe,
                                      double &inputSequence[],
                                      const int dModel = TRANSFORMER_D_MODEL_DEFAULT,
                                      const int sequenceLength = 1)
    {
        if(dModel <= 0 || sequenceLength <= 0)
        {
            Print("[AIFeatureVectorBuilder] ERROR: Invalid parameters - dModel=", dModel, ", sequenceLength=", sequenceLength);
            return false;
        }

        // Validate that dModel is reasonable compared to base feature size
        if(dModel > FEATURE_VECTOR_SIZE * DMODE_BASE_FEATURE_RATIO_WARNING)
        {
            static datetime s_lastDModelWarningTime = 0;
            datetime now = TimeCurrent();
            if(s_lastDModelWarningTime == 0 || (now - s_lastDModelWarningTime) >= 300)
            {
                Print("[AIFeatureVectorBuilder] WARNING: dModel (", dModel, ") is much larger than base features (", FEATURE_VECTOR_SIZE, ")");
                s_lastDModelWarningTime = now;
            }
        }

        int totalSize = dModel * sequenceLength;
        ArrayResize(inputSequence, totalSize);
        ArrayInitialize(inputSequence, 0.0);

        for(int s = 0; s < sequenceLength; s++)
        {
            double stepFeatures[];
            int barShift = MathMax(1, sequenceLength - s);
            if(!BuildNNFeatureVector(symbol, timeframe, stepFeatures, barShift))
                return false;

            int baseSize = ArraySize(stepFeatures);
            if(baseSize <= 0)
                return false;

            for(int i = 0; i < dModel; i++)
            {
                int baseIndex = i % baseSize;
                int prevIndex = (baseIndex > 0) ? (baseIndex - 1) : (baseSize - 1);

                double currentValue = stepFeatures[baseIndex];
                double lagValue = stepFeatures[prevIndex];
                inputSequence[s * dModel + i] = currentValue * TEMPORAL_BLEND_CURRENT + lagValue * TEMPORAL_BLEND_LAG;
            }
        }

        return true;
    }
};

#endif // CORE_AI_FEATURE_VECTOR_BUILDER_MQH
