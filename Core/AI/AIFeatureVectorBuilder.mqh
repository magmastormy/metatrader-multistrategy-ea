//+------------------------------------------------------------------+
//| AIFeatureVectorBuilder.mqh                                       |
//| Shared AI feature construction for NN/Transformer/Ensemble paths |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_AI_FEATURE_VECTOR_BUILDER_MQH
#define CORE_AI_FEATURE_VECTOR_BUILDER_MQH

// AI Model Configuration Constants
#define TRANSFORMER_D_MODEL_DEFAULT        128
#define TRANSFORMER_NUM_HEADS_DEFAULT       8
#define TRANSFORMER_NUM_LAYERS_A_DEFAULT    4
#define TRANSFORMER_D_FF_DEFAULT           512
#define TRANSFORMER_D_FF_B_DEFAULT          384
#define TRANSFORMER_DROPOUT_DEFAULT         64
#define TRANSFORMER_LR_A_DEFAULT           0.001
#define TRANSFORMER_LR_B_DEFAULT          0.0015
#define FEATURE_VECTOR_SIZE               25
#define TEMPORAL_BLEND_CURRENT            0.85
#define TEMPORAL_BLEND_LAG                0.15
#define DMODE_BASE_FEATURE_RATIO_WARNING   6

#include "../../IndicatorManager.mqh"

class CAIFeatureVectorBuilder
{
private:
    static double GetIndicatorValue(const int handle, const int buffer, const int shift)
    {
        if(handle == INVALID_HANDLE)
            return 0.0;

        double value[1];
        if(CopyBuffer(handle, buffer, shift, 1, value) > 0)
            return value[0];

        return 0.0;
    }

    static double GetNormalizedValue(const double minValue, const double maxValue, const double value)
    {
        double range = maxValue - minValue;
        if(range == 0.0)
            return 0.0;
        return (value - minValue) / range;
    }

    static bool IsKillZoneTime(const int hour)
    {
        // Match NeuralNetworkStrategy session semantics.
        return (hour >= 2 && hour <= 5) || (hour >= 7 && hour <= 10) || (hour >= 20 && hour <= 23);
    }

public:
    static bool BuildNNFeatureVector(const string symbol, const ENUM_TIMEFRAMES timeframe, double &features[])
    {
        ArrayResize(features, FEATURE_VECTOR_SIZE);
        ArrayInitialize(features, 0.0);

        if(symbol == "")
            return false;

        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return false;

        double close = iClose(symbol, timeframe, 1);
        if(close <= 0.0)
            close = SymbolInfoDouble(symbol, SYMBOL_BID);

        double open = iOpen(symbol, timeframe, 1);
        double high = iHigh(symbol, timeframe, 1);
        double low = iLow(symbol, timeframe, 1);
        double closePrev = iClose(symbol, timeframe, 2);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001;

        double maFast = GetIndicatorValue(ind.GetMAHandle(symbol, timeframe, 9, 0, MODE_EMA, PRICE_CLOSE), 0, 1);
        double maSlow = GetIndicatorValue(ind.GetMAHandle(symbol, timeframe, 21, 0, MODE_EMA, PRICE_CLOSE), 0, 1);
        double ema200 = GetIndicatorValue(ind.GetMAHandle(symbol, timeframe, 200, 0, MODE_EMA, PRICE_CLOSE), 0, 1);
        double adx = GetIndicatorValue(ind.GetADXHandle(symbol, timeframe, 14), 0, 1);
        double rsi = GetIndicatorValue(ind.GetRSIHandle(symbol, timeframe, 14, PRICE_CLOSE), 0, 1);
        double rsiPrev = GetIndicatorValue(ind.GetRSIHandle(symbol, timeframe, 14, PRICE_CLOSE), 0, 2);
        double atrFast = GetIndicatorValue(ind.GetATRHandle(symbol, timeframe, 14), 0, 1);
        double atrSlow = GetIndicatorValue(ind.GetATRHandle(symbol, timeframe, 50), 0, 1);
        double bbUpper = GetIndicatorValue(ind.GetBandsHandle(symbol, timeframe, 20, 0, 2.0, PRICE_CLOSE), 1, 1);
        double bbLower = GetIndicatorValue(ind.GetBandsHandle(symbol, timeframe, 20, 0, 2.0, PRICE_CLOSE), 2, 1);
        double macdMain = GetIndicatorValue(ind.GetMACDHandle(symbol, timeframe, 12, 26, 9, PRICE_CLOSE), 0, 1);
        double macdSignal = GetIndicatorValue(ind.GetMACDHandle(symbol, timeframe, 12, 26, 9, PRICE_CLOSE), 1, 1);
        double cci = GetIndicatorValue(ind.GetCCIHandle(symbol, timeframe, 14, PRICE_CLOSE), 0, 1);

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
        long volume = iVolume(symbol, timeframe, 1);
        long volumePrev = iVolume(symbol, timeframe, 2);
        features[10] = (volume > volumePrev) ? 1.0 : 0.0;
        features[11] = (rsi > 50.0 && volume > volumePrev) ? 1.0 : 0.0;
        double high20 = iHigh(symbol, timeframe, iHighest(symbol, timeframe, MODE_HIGH, 20, 1));
        double low20 = iLow(symbol, timeframe, iLowest(symbol, timeframe, MODE_LOW, 20, 1));
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
        double highPrev = iHigh(symbol, timeframe, 2);
        double lowPrev = iLow(symbol, timeframe, 2);
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

        double baseFeatures[];
        if(!BuildNNFeatureVector(symbol, timeframe, baseFeatures))
        {
            Print("[AIFeatureVectorBuilder] ERROR: Failed to build base feature vector");
            return false;
        }

        int baseSize = ArraySize(baseFeatures);
        if(baseSize <= 0)
        {
            Print("[AIFeatureVectorBuilder] ERROR: Base feature vector is empty");
            return false;
        }

        // Validate that dModel is reasonable compared to base feature size
        if(dModel > baseSize * DMODE_BASE_FEATURE_RATIO_WARNING)
        {
            static datetime s_lastDModelWarningTime = 0;
            datetime now = TimeCurrent();
            if(s_lastDModelWarningTime == 0 || (now - s_lastDModelWarningTime) >= 300)
            {
                Print("[AIFeatureVectorBuilder] WARNING: dModel (", dModel, ") is much larger than base features (", baseSize, ")");
                s_lastDModelWarningTime = now;
            }
        }

        int totalSize = dModel * sequenceLength;
        ArrayResize(inputSequence, totalSize);
        ArrayInitialize(inputSequence, 0.0);

        for(int s = 0; s < sequenceLength; s++)
        {
            for(int i = 0; i < dModel; i++)
            {
                // Use modulo to cycle through base features when dModel > baseSize
                // This creates a repeating pattern with slight variations
                int baseIndex = i % baseSize;
                int prevIndex = (baseIndex + baseSize - 1) % baseSize;
                
                double currentValue = baseFeatures[baseIndex];
                double lagValue = baseFeatures[prevIndex];
                
                // Blend current value with lagged value for temporal context
                inputSequence[s * dModel + i] = currentValue * TEMPORAL_BLEND_CURRENT + lagValue * TEMPORAL_BLEND_LAG;
            }
        }

        return true;
    }
};

#endif // CORE_AI_FEATURE_VECTOR_BUILDER_MQH
