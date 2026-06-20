//+------------------------------------------------------------------+
//| AIFeatureVectorBuilder.mqh                                       |
//| Canonical 57-feature AI input builder for NN / ONNX / sequence   |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_AI_FEATURE_VECTOR_BUILDER_MQH
#define CORE_AI_FEATURE_VECTOR_BUILDER_MQH

#include "../../IndicatorManager.mqh"

#define TRANSFORMER_D_MODEL_DEFAULT         64
#define TRANSFORMER_NUM_HEADS_DEFAULT        4
#define TRANSFORMER_NUM_LAYERS_A_DEFAULT     2
#define TRANSFORMER_D_FF_DEFAULT           128
#define TRANSFORMER_D_FF_B_DEFAULT          96
#define TRANSFORMER_MAX_SEQ_LEN_DEFAULT     60
#define TRANSFORMER_SHORT_SEQ_LEN_DEFAULT   10
#define TRANSFORMER_LR_A_DEFAULT           0.001
#define TRANSFORMER_LR_B_DEFAULT          0.0015
#define FEATURE_VECTOR_SIZE               57
#define TEMPORAL_BLEND_CURRENT            0.85
#define TEMPORAL_BLEND_LAG                0.15
#define DMODE_BASE_FEATURE_RATIO_WARNING   6

class CAIFeatureVectorBuilder
{
private:
    static double ClampValue(const double value, const double minValue, const double maxValue)
    {
        return MathMax(minValue, MathMin(maxValue, value));
    }

    static double SafeLogRatio(const double numerator, const double denominator)
    {
        double base = numerator / (denominator + 1e-9);
        if(base <= 1e-9)
            base = 1e-9;
        return MathLog(base);
    }

    static double SafeLogValue(const double value)
    {
        if(value <= 1e-9)
            return MathLog(1e-9);
        return MathLog(value);
    }

    static double SanitizeFeature(const double value)
    {
        if(!MathIsValidNumber(value))
            return 0.0;
        if(value > 10.0)
            return 10.0;
        if(value < -10.0)
            return -10.0;
        return value;
    }

    static bool IsKillZoneTime(const int hour)
    {
        return (hour >= 2 && hour <= 5) || (hour >= 7 && hour <= 10) || (hour >= 20 && hour <= 23);
    }

    static bool EnsureBars(const string symbol, const ENUM_TIMEFRAMES timeframe, const int barShift, const int requiredLookback)
    {
        // Enforce minimum bar shift of 1 to prevent look-ahead bias
        // Using shift=0 would access the current incomplete bar's close price
        if(barShift < 1)
        {
            static datetime s_lastShiftLog = 0;
            datetime now = TimeCurrent();
            if(s_lastShiftLog == 0 || (now - s_lastShiftLog) >= 300)
            {
                PrintFormat("[AI-FEATURE] WARNING: barShift=%d < 1, using barShift=1 to prevent look-ahead bias", barShift);
                s_lastShiftLog = now;
            }
            return false;
        }

        int requiredBars = barShift + requiredLookback + 5;
        int availableBars = Bars(symbol, timeframe);
        if(availableBars < requiredBars)
        {
            // Attempt to preload more historical data if insufficient
            static datetime s_lastPreloadAttempt = 0;
            datetime now = TimeCurrent();
            
            // Try to load more history (limit attempts to avoid spam)
            if(s_lastPreloadAttempt == 0 || (now - s_lastPreloadAttempt) >= 60)
            {
                PrintFormat("[AI-FEATURE] Preloading history for %s %s | available=%d | required=%d | deficit=%d",
                            symbol, EnumToString(timeframe), availableBars, requiredBars, requiredBars - availableBars);
                
                // Request additional bars from server
                int barsToRequest = requiredBars - availableBars + 100; // Add buffer
                datetime preloadStartTime = iTime(symbol, timeframe, MathMin(availableBars - 1, 1000));
                
                // Force history download by requesting older data
                MqlDateTime dtStart;
                TimeToStruct(preloadStartTime, dtStart);
                dtStart.day -= 30; // Go back 30 days
                datetime newStartTime = StructToTime(dtStart);
                
                // CopyRates will trigger history download if needed
                MqlRates tempRates[];
                int copied = CopyRates(symbol, timeframe, newStartTime, 1, tempRates);
                
                s_lastPreloadAttempt = now;
                
                // Recheck after preload attempt
                availableBars = Bars(symbol, timeframe);
                if(availableBars >= requiredBars)
                {
                    PrintFormat("[AI-FEATURE] History preload successful for %s %s | now available=%d",
                                symbol, EnumToString(timeframe), availableBars);
                    return true;
                }
            }
            
            static datetime s_lastHistoryLog = 0;
            if(s_lastHistoryLog == 0 || (now - s_lastHistoryLog) >= 60)
            {
                PrintFormat("[AI-FEATURE] History not ready for %s %s | available=%d | required=%d | shift=%d",
                            symbol, EnumToString(timeframe), availableBars, requiredBars, barShift);
                s_lastHistoryLog = now;
            }
            return false;
        }
        return true;
    }

    static double GetIndicatorValue(const int handle, const int buffer, const int shift)
    {
        if(handle == INVALID_HANDLE)
            return 0.0;

        if(BarsCalculated(handle) < shift + 1)
            return 0.0;

        double values[1];
        if(CopyBuffer(handle, buffer, shift, 1, values) <= 0)
            return 0.0;

        return MathIsValidNumber(values[0]) ? values[0] : 0.0;
    }

    static double GetCloseAt(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift)
    {
        double value = iClose(symbol, timeframe, shift);
        return MathIsValidNumber(value) ? value : 0.0;
    }

    static double GetHighAt(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift)
    {
        double value = iHigh(symbol, timeframe, shift);
        return MathIsValidNumber(value) ? value : 0.0;
    }

    static double GetLowAt(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift)
    {
        double value = iLow(symbol, timeframe, shift);
        return MathIsValidNumber(value) ? value : 0.0;
    }

    static double GetOpenAt(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift)
    {
        double value = iOpen(symbol, timeframe, shift);
        return MathIsValidNumber(value) ? value : 0.0;
    }

    static double GetVolumeAt(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift)
    {
        long value = iVolume(symbol, timeframe, shift);
        return (double)MathMax(0, value);
    }

    static double GetLogReturn(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift)
    {
        double currentClose = GetCloseAt(symbol, timeframe, shift);
        double prevClose = GetCloseAt(symbol, timeframe, shift + 1);
        if(currentClose <= 0.0 || prevClose <= 0.0)
            return 0.0;
        return MathLog(currentClose / (prevClose + 1e-12));
    }

    static double ComputeVolumeSma(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift, const int period)
    {
        double sum = 0.0;
        int count = 0;
        for(int i = 0; i < period; i++)
        {
            double vol = GetVolumeAt(symbol, timeframe, shift + i);
            sum += vol;
            count++;
        }
        return (count > 0) ? (sum / (double)count) : 0.0;
    }

    static double ComputeRollingMeanClose(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift, const int period)
    {
        double sum = 0.0;
        int count = 0;
        for(int i = 0; i < period; i++)
        {
            double value = GetCloseAt(symbol, timeframe, shift + i);
            if(value <= 0.0)
                continue;
            sum += value;
            count++;
        }
        return (count > 0) ? (sum / (double)count) : 0.0;
    }

    static double ComputeRollingStdClose(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift, const int period, const double mean)
    {
        double sumSq = 0.0;
        int count = 0;
        for(int i = 0; i < period; i++)
        {
            double value = GetCloseAt(symbol, timeframe, shift + i);
            if(value <= 0.0)
                continue;
            double diff = value - mean;
            sumSq += diff * diff;
            count++;
        }
        // Match the Python training pipeline's population standard deviation (ddof=0)
        // so feature cross-checks do not drift between offline and MT5 runtime.
        return (count > 0) ? MathSqrt(sumSq / (double)count + 1e-9) : 0.0;
    }

    static double ComputeRollingZScoreClose(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift, const int period)
    {
        double current = GetCloseAt(symbol, timeframe, shift);
        if(current <= 0.0)
            return 0.0;
        double mean = ComputeRollingMeanClose(symbol, timeframe, shift, period);
        double stddev = ComputeRollingStdClose(symbol, timeframe, shift, period, mean);
        if(stddev <= 1e-9)
            return 0.0;
        return (current - mean) / stddev;
    }

    static double ComputeRollingZScoreRange(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift, const int period)
    {
        double current = GetHighAt(symbol, timeframe, shift) - GetLowAt(symbol, timeframe, shift);
        double sum = 0.0;
        double sumSq = 0.0;
        int count = 0;
        for(int i = 0; i < period; i++)
        {
            double value = GetHighAt(symbol, timeframe, shift + i) - GetLowAt(symbol, timeframe, shift + i);
            sum += value;
            sumSq += value * value;
            count++;
        }
        if(count < 2)
            return 0.0;
        double mean = sum / (double)count;
        double variance = (sumSq / (double)count) - (mean * mean);
        double stddev = MathSqrt(MathMax(variance, 0.0) + 1e-9);
        return (current - mean) / stddev;
    }

    static double ComputeRollingZScoreVolume(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift, const int period)
    {
        double current = GetVolumeAt(symbol, timeframe, shift);
        double sum = 0.0;
        double sumSq = 0.0;
        int count = 0;
        for(int i = 0; i < period; i++)
        {
            double value = GetVolumeAt(symbol, timeframe, shift + i);
            sum += value;
            sumSq += value * value;
            count++;
        }
        if(count < 2)
            return 0.0;
        double mean = sum / (double)count;
        double variance = (sumSq / (double)count) - (mean * mean);
        double stddev = MathSqrt(MathMax(variance, 0.0) + 1e-9);
        return (current - mean) / stddev;
    }

    static double ComputeRollingZScoreIndicator(const int handle, const int shift, const int period)
    {
        if(handle == INVALID_HANDLE)
            return 0.0;
        double values[];
        ArrayResize(values, period);
        if(CopyBuffer(handle, 0, shift, period, values) < period)
            return 0.0;

        double current = values[0];
        double sum = 0.0;
        double sumSq = 0.0;
        for(int i = 0; i < period; i++)
        {
            sum += values[i];
            sumSq += values[i] * values[i];
        }

        double mean = sum / (double)period;
        double variance = (sumSq / (double)period) - (mean * mean);
        double stddev = MathSqrt(MathMax(variance, 0.0) + 1e-9);
        return (current - mean) / stddev;
    }

    static double ComputeParkinsonVol(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift, const int period)
    {
        double factor = 1.0 / (4.0 * MathLog(2.0));
        double sum = 0.0;
        int count = 0;
        for(int i = 0; i < period; i++)
        {
            double high = GetHighAt(symbol, timeframe, shift + i);
            double low = GetLowAt(symbol, timeframe, shift + i);
            if(high <= 0.0 || low <= 0.0)
                continue;
            double logHl = MathLog((high + 1e-9) / (low + 1e-9));
            sum += factor * logHl * logHl;
            count++;
        }
        return (count > 0) ? MathSqrt(sum / (double)count) : 0.0;
    }

    static double ComputeCCI(const string symbol, const ENUM_TIMEFRAMES timeframe, const int shift, const int period)
    {
        double tpCurrent = (GetHighAt(symbol, timeframe, shift) +
                            GetLowAt(symbol, timeframe, shift) +
                            GetCloseAt(symbol, timeframe, shift)) / 3.0;

        double tpValues[];
        ArrayResize(tpValues, period);
        double sum = 0.0;
        int count = 0;
        for(int i = 0; i < period; i++)
        {
            double tp = (GetHighAt(symbol, timeframe, shift + i) +
                         GetLowAt(symbol, timeframe, shift + i) +
                         GetCloseAt(symbol, timeframe, shift + i)) / 3.0;
            tpValues[i] = tp;
            sum += tp;
            count++;
        }
        if(count <= 0)
            return 0.0;

        double sma = sum / (double)count;
        double mad = 0.0;
        for(int i = 0; i < count; i++)
            mad += MathAbs(tpValues[i] - sma);
        mad = (count > 0) ? (mad / (double)count) : 0.0;
        if(mad <= 1e-9)
            mad = 1e-9;

        return ((tpCurrent - sma) / (0.015 * mad + 1e-9)) / 200.0;
    }

    static double ComputeAtrRatio(const int numeratorHandle, const int denominatorHandle, const int shift)
    {
        double numerator = GetIndicatorValue(numeratorHandle, 0, shift);
        double denominator = GetIndicatorValue(denominatorHandle, 0, shift);
        if(denominator <= 1e-9)
            return 0.0;
        return numerator / denominator;
    }

    static double ComputeAutocorrProxyZScore(const string symbol,
                                             const ENUM_TIMEFRAMES timeframe,
                                             const int shift,
                                             const int lag,
                                             const int period)
    {
        double current = GetLogReturn(symbol, timeframe, shift) * GetLogReturn(symbol, timeframe, shift + lag);
        double sum = 0.0;
        double sumSq = 0.0;
        int count = 0;
        for(int i = 0; i < period; i++)
        {
            double value = GetLogReturn(symbol, timeframe, shift + i) *
                           GetLogReturn(symbol, timeframe, shift + i + lag);
            sum += value;
            sumSq += value * value;
            count++;
        }
        if(count < 2)
            return 0.0;
        double mean = sum / (double)count;
        double variance = (sumSq / (double)count) - (mean * mean);
        double stddev = MathSqrt(MathMax(variance, 0.0) + 1e-9);
        return (current - mean) / stddev;
    }

    static bool IsSyntheticSpikeProfileSymbol(const string symbol)
    {
        return (StringFind(symbol, "Volatility") >= 0 ||
                StringFind(symbol, "Boom") >= 0 ||
                StringFind(symbol, "Crash") >= 0 ||
                StringFind(symbol, "Step") >= 0 ||
                StringFind(symbol, "Jump") >= 0 ||
                StringFind(symbol, "PainX") >= 0 ||
                StringFind(symbol, "Pain ") >= 0 ||
                StringFind(symbol, "GainX") >= 0 ||
                StringFind(symbol, "FlipX") >= 0 ||
                StringFind(symbol, "FX Vol") >= 0);
    }

    static double ResolveTickVolume(const MqlTick &tick)
    {
        if(tick.volume_real > 0.0)
            return tick.volume_real;
        return (double)MathMax(0, (long)tick.volume);
    }

    static double ResolveTickTradePrice(const MqlTick &tick)
    {
        if(tick.last > 0.0)
            return tick.last;
        if(tick.bid > 0.0 && tick.ask > 0.0)
            return (tick.bid + tick.ask) * 0.5;
        if(tick.bid > 0.0)
            return tick.bid;
        if(tick.ask > 0.0)
            return tick.ask;
        return 0.0;
    }

    static double ComputeOrderFlowImbalance(const string symbol, const int lookbackTicks = 128)
    {
        MqlTick ticks[];
        int copied = CopyTicks(symbol, ticks, COPY_TICKS_ALL, 0, lookbackTicks);
        if(copied <= 1)
            return 0.0;

        double ofi = 0.0;
        for(int i = 1; i < copied; i++)
        {
            double bidDelta = ticks[i].bid - ticks[i - 1].bid;
            double askDelta = ticks[i].ask - ticks[i - 1].ask;
            double volNow = ResolveTickVolume(ticks[i]);
            double volPrev = ResolveTickVolume(ticks[i - 1]);

            double eBid = 0.0;
            if(bidDelta > 0.0)
                eBid = volNow;
            else if(MathAbs(bidDelta) <= 1e-9)
                eBid = volNow - volPrev;
            else
                eBid = -volPrev;

            double eAsk = 0.0;
            if(askDelta < 0.0)
                eAsk = volNow;
            else if(MathAbs(askDelta) <= 1e-9)
                eAsk = volNow - volPrev;
            else
                eAsk = -volPrev;

            ofi += (eBid - eAsk);
        }

        double scaled = ofi / 1000.0;
        return ClampValue(MathTanh(scaled), -1.0, 1.0);
    }

    static double ComputeTimeSinceLastSpikeNormalized(const string symbol, const int lookbackTicks = 256)
    {
        if(!IsSyntheticSpikeProfileSymbol(symbol))
            return 1.0;

        MqlTick ticks[];
        int copied = CopyTicks(symbol, ticks, COPY_TICKS_ALL, 0, lookbackTicks);
        if(copied <= 2)
            return 1.0;

        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001;

        double baseline = 0.0;
        int baselineCount = 0;
        for(int i = 1; i < copied; i++)
        {
            double currPrice = ResolveTickTradePrice(ticks[i]);
            double prevPrice = ResolveTickTradePrice(ticks[i - 1]);
            if(currPrice <= 0.0 || prevPrice <= 0.0)
                continue;

            baseline += MathAbs(currPrice - prevPrice);
            baselineCount++;
        }

        double avgMove = (baselineCount > 0) ? (baseline / (double)baselineCount) : 0.0;
        double spikeThreshold = MathMax(point * 10.0, avgMove * 5.0);
        if(spikeThreshold <= 0.0)
            spikeThreshold = point * 10.0;

        for(int i = copied - 1; i >= 1; i--)
        {
            double currPrice = ResolveTickTradePrice(ticks[i]);
            double prevPrice = ResolveTickTradePrice(ticks[i - 1]);
            if(currPrice <= 0.0 || prevPrice <= 0.0)
                continue;

            double move = MathAbs(currPrice - prevPrice);
            if(move >= spikeThreshold)
            {
                int ticksSinceSpike = copied - 1 - i;
                return ClampValue((double)ticksSinceSpike / (double)MathMax(1, copied - 1), 0.0, 1.0);
            }
        }

        return 1.0;
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

        if(!EnsureBars(symbol, timeframe, barShift, 150))
            return false;

        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return false;

        double close = GetCloseAt(symbol, timeframe, barShift);
        double open = GetOpenAt(symbol, timeframe, barShift);
        double high = GetHighAt(symbol, timeframe, barShift);
        double low = GetLowAt(symbol, timeframe, barShift);
        double volume = GetVolumeAt(symbol, timeframe, barShift);
        if(close <= 0.0 || high <= 0.0 || low <= 0.0)
            return false;

        int hEma8 = ind.GetMAHandle(symbol, timeframe, 8, 0, MODE_EMA, PRICE_CLOSE);
        int hEma21 = ind.GetMAHandle(symbol, timeframe, 21, 0, MODE_EMA, PRICE_CLOSE);
        int hEma50 = ind.GetMAHandle(symbol, timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
        int hEma100 = ind.GetMAHandle(symbol, timeframe, 100, 0, MODE_EMA, PRICE_CLOSE);
        int hSma200 = ind.GetMAHandle(symbol, timeframe, 200, 0, MODE_SMA, PRICE_CLOSE);
        int hRsi14 = ind.GetRSIHandle(symbol, timeframe, 14, PRICE_CLOSE);
        int hRsi7 = ind.GetRSIHandle(symbol, timeframe, 7, PRICE_CLOSE);
        int hAtr14 = ind.GetATRHandle(symbol, timeframe, 14);
        int hAtr50 = ind.GetATRHandle(symbol, timeframe, 50);
        int hAtr5 = ind.GetATRHandle(symbol, timeframe, 5);
        int hBands = ind.GetBandsHandle(symbol, timeframe, 20, 0, 2.0, PRICE_CLOSE);
        int hMacd = ind.GetMACDHandle(symbol, timeframe, 12, 26, 9, PRICE_CLOSE);
        int hCci = ind.GetCCIHandle(symbol, timeframe, 14, PRICE_CLOSE);

        double atr14 = GetIndicatorValue(hAtr14, 0, barShift);
        double atr50 = GetIndicatorValue(hAtr50, 0, barShift);
        double atr5 = GetIndicatorValue(hAtr5, 0, barShift);
        double ema8 = GetIndicatorValue(hEma8, 0, barShift);
        double ema21 = GetIndicatorValue(hEma21, 0, barShift);
        double ema50 = GetIndicatorValue(hEma50, 0, barShift);
        double ema100 = GetIndicatorValue(hEma100, 0, barShift);
        double ma200 = GetIndicatorValue(hSma200, 0, barShift);
        double rsi14 = GetIndicatorValue(hRsi14, 0, barShift) / 100.0;
        double rsi7 = GetIndicatorValue(hRsi7, 0, barShift) / 100.0;
        double rsi14Lag1 = GetIndicatorValue(hRsi14, 0, barShift + 1) / 100.0;
        double rsi14Lag3 = GetIndicatorValue(hRsi14, 0, barShift + 3) / 100.0;
        double bbUpper = GetIndicatorValue(hBands, 1, barShift);
        double bbLower = GetIndicatorValue(hBands, 2, barShift);
        double bbUpperLag1 = GetIndicatorValue(hBands, 1, barShift + 1);
        double bbLowerLag1 = GetIndicatorValue(hBands, 2, barShift + 1);
        double bbUpperLag3 = GetIndicatorValue(hBands, 1, barShift + 3);
        double bbLowerLag3 = GetIndicatorValue(hBands, 2, barShift + 3);
        double bbMid = (bbUpper + bbLower) * 0.5;
        double macdMain = GetIndicatorValue(hMacd, 0, barShift);
        double macdSignal = GetIndicatorValue(hMacd, 1, barShift);
        double macdLag1 = GetIndicatorValue(hMacd, 0, barShift + 1) -
                          GetIndicatorValue(hMacd, 1, barShift + 1);
        double cci = GetIndicatorValue(hCci, 0, barShift);

        double logRet = GetLogReturn(symbol, timeframe, barShift);
        double normRet = (atr14 > 1e-9) ? (logRet / (atr14 + 1e-9)) : 0.0;
        double bbPctB = (bbUpper - bbLower > 1e-9) ? ((close - bbLower) / (bbUpper - bbLower + 1e-9)) : 0.5;
        double bbPctBLag1 = (bbUpperLag1 - bbLowerLag1 > 1e-9) ?
                            ((GetCloseAt(symbol, timeframe, barShift + 1) - bbLowerLag1) / (bbUpperLag1 - bbLowerLag1 + 1e-9)) :
                            0.5;
        double bbPctBLag3 = (bbUpperLag3 - bbLowerLag3 > 1e-9) ?
                            ((GetCloseAt(symbol, timeframe, barShift + 3) - bbLowerLag3) / (bbUpperLag3 - bbLowerLag3 + 1e-9)) :
                            0.5;
        double bbWidth = (bbMid > 1e-9) ? ((bbUpper - bbLower) / (bbMid + 1e-9)) : 0.0;
        double macdHistNorm = macdMain - macdSignal;
        if(atr14 > 1e-9)
            macdHistNorm /= (atr14 + 1e-9);
        else
            macdHistNorm = 0.0;

        datetime barTime = iTime(symbol, timeframe, barShift);
        MqlDateTime dt;
        TimeToStruct(barTime, dt);
        double dow = (double)dt.day_of_week / 6.0;
        double hod = (double)dt.hour / 23.0;
        double barRange = high - low;
        double volSma20 = ComputeVolumeSma(symbol, timeframe, barShift, 20);

        features[0] = logRet;
        features[1] = normRet;
        features[2] = (barRange > 1e-9) ? ((close - low) / (barRange + 1e-9)) : 0.5;
        features[3] = SafeLogValue(volume + 1.0);
        features[4] = (close > 1e-9) ? (atr14 / (close + 1e-9)) : 0.0;
        features[5] = SafeLogRatio(close, ema8);
        features[6] = SafeLogRatio(close, ema21);
        features[7] = SafeLogRatio(close, ema50);
        features[8] = SafeLogRatio(ema8, ema21);
        features[9] = SafeLogRatio(ema21, ema50);
        features[10] = rsi14;
        features[11] = rsi7;
        features[12] = bbPctB;
        features[13] = bbWidth;
        features[14] = macdHistNorm;
        features[15] = ComputeAtrRatio(hAtr14, hAtr50, barShift);
        features[16] = ComputeParkinsonVol(symbol, timeframe, barShift, 14);
        features[17] = (volSma20 > 1e-9) ? (volume / (volSma20 + 1e-9)) : 0.0;
        features[18] = MathSin(2.0 * M_PI * dow);
        features[19] = MathCos(2.0 * M_PI * dow);
        features[20] = MathSin(2.0 * M_PI * hod);
        features[21] = MathCos(2.0 * M_PI * hod);
        features[22] = GetLogReturn(symbol, timeframe, barShift + 1);
        features[23] = GetLogReturn(symbol, timeframe, barShift + 5);
        features[24] = GetLogReturn(symbol, timeframe, barShift + 20);
        features[25] = ComputeRollingZScoreClose(symbol, timeframe, barShift, 20);
        features[26] = ComputeRollingZScoreClose(symbol, timeframe, barShift, 50);
        features[27] = (close > 1e-9) ? (barRange / (close + 1e-9)) : 0.0;
        features[28] = ComputeRollingZScoreRange(symbol, timeframe, barShift, 20);
        features[29] = ComputeCCI(symbol, timeframe, barShift, 14);
        features[30] = (atr14 > 1e-9) ? (GetLogReturn(symbol, timeframe, barShift + 2) / (atr14 + 1e-9)) : 0.0;
        features[31] = (atr14 > 1e-9) ? (GetLogReturn(symbol, timeframe, barShift + 3) / (atr14 + 1e-9)) : 0.0;
        features[32] = (atr14 > 1e-9) ? (GetLogReturn(symbol, timeframe, barShift + 5) / (atr14 + 1e-9)) : 0.0;
        features[33] = (atr14 > 1e-9) ? (GetLogReturn(symbol, timeframe, barShift + 8) / (atr14 + 1e-9)) : 0.0;
        features[34] = (atr14 > 1e-9) ? (GetLogReturn(symbol, timeframe, barShift + 13) / (atr14 + 1e-9)) : 0.0;
        features[35] = ComputeRollingZScoreVolume(symbol, timeframe, barShift, 20);
        features[36] = rsi14Lag1;
        features[37] = rsi14Lag3;
        features[38] = bbPctBLag1;
        features[39] = bbPctBLag3;
        features[40] = ComputeRollingZScoreIndicator(hRsi14, barShift, 20);
        features[41] = ComputeRollingZScoreIndicator(hRsi7, barShift, 20);
        features[42] = macdHistNorm;
        features[43] = (atr14 > 1e-9) ? (macdLag1 / (atr14 + 1e-9)) : 0.0;
        features[44] = ComputeAtrRatio(hAtr14, hAtr5, barShift);
        features[45] = ComputeRollingZScoreIndicator(hAtr14, barShift, 20);
        features[46] = GetLogReturn(symbol, timeframe, barShift + 10);
        features[47] = GetLogReturn(symbol, timeframe, barShift + 15);
        features[48] = (atr14 > 1e-9) ? ((close - ema100) / (atr14 + 1e-9)) : 0.0;
        features[49] = (atr14 > 1e-9) ? ((close - ma200) / (atr14 + 1e-9)) : 0.0;
        features[50] = ComputeAutocorrProxyZScore(symbol, timeframe, barShift, 1, 20);
        features[51] = ComputeAutocorrProxyZScore(symbol, timeframe, barShift, 5, 20);
        features[52] = (atr50 > 1e-9) ? ((close - ema100) / (atr50 + 1e-9)) : 0.0;
        features[53] = ComputeRollingZScoreVolume(symbol, timeframe, barShift, 50);
        features[54] = (atr14 > 1e-9) ? (atr50 / (atr14 + 1e-9)) : 0.0;
        features[55] = ComputeOrderFlowImbalance(symbol, 128);
        features[56] = ComputeTimeSinceLastSpikeNormalized(symbol, 256);

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            features[i] = SanitizeFeature(features[i]);

        return true;
    }

    static bool BuildTransformerInput(const string symbol,
                                      const ENUM_TIMEFRAMES timeframe,
                                      double &inputSequence[],
                                      const int dModel = TRANSFORMER_D_MODEL_DEFAULT,
                                      const int sequenceLength = TRANSFORMER_SHORT_SEQ_LEN_DEFAULT)
    {
        if(dModel <= 0 || sequenceLength <= 0)
            return false;

        if(dModel > FEATURE_VECTOR_SIZE * DMODE_BASE_FEATURE_RATIO_WARNING)
        {
            static datetime s_lastDModelWarning = 0;
            datetime now = TimeCurrent();
            if(s_lastDModelWarning == 0 || (now - s_lastDModelWarning) >= 300)
            {
                PrintFormat("[AI-FEATURE] WARNING | dModel=%d is much larger than base feature width=%d",
                            dModel, FEATURE_VECTOR_SIZE);
                s_lastDModelWarning = now;
            }
        }

        int totalSize = dModel * sequenceLength;
        ArrayResize(inputSequence, totalSize);
        ArrayInitialize(inputSequence, 0.0);

        for(int step = 0; step < sequenceLength; step++)
        {
            int barShift = MathMax(1, sequenceLength - step);
            double stepFeatures[];
            if(!BuildNNFeatureVector(symbol, timeframe, stepFeatures, barShift))
                return false;

            int baseSize = ArraySize(stepFeatures);
            if(baseSize <= 0)
                return false;

            for(int i = 0; i < dModel; i++)
            {
                int currentIndex = i % baseSize;
                int lagIndex = (currentIndex + 1) % baseSize;
                double currentValue = stepFeatures[currentIndex];
                double lagValue = stepFeatures[lagIndex];
                inputSequence[step * dModel + i] =
                    (currentValue * TEMPORAL_BLEND_CURRENT) +
                    (lagValue * TEMPORAL_BLEND_LAG);
            }
        }

        return true;
    }
};

#endif // CORE_AI_FEATURE_VECTOR_BUILDER_MQH
