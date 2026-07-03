//+------------------------------------------------------------------+
//| Next-Generation Strategy Brain Integration                       |
//| Local runtime adapter over shared transformer feature paths       |
//|                                                                   |
//| ROLE: Feature provider ONLY. This class produces features and    |
//| uncertainty estimates for the AI adapters (Transformer/Ensemble/  |
//| ONNX). It is NOT a direct live voter. Signals must flow through  |
//| IAIStrategy adapters → EnterpriseStrategyManager consensus.      |
//| Do NOT use GenerateSignal() output as a direct TRADE_SIGNAL.     |
//+------------------------------------------------------------------+
#ifndef NEXTGEN_STRATEGY_BRAIN_MQH
#define NEXTGEN_STRATEGY_BRAIN_MQH

#include <Arrays\ArrayDouble.mqh>
#include <Math\Stat\Math.mqh>
#include "TransformerBrain.mqh"
#include "UncertaintyQuantifier.mqh"
#include "UniversalTransformerService.mqh"
#include "../Core/AI/AIFeatureVectorBuilder.mqh"
#include "../Core/Utils/Enums.mqh"

class CNextGenStrategyBrain
{
private:
    bool m_initialized;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    // AI components
    bool m_usesUniversalTransformer;
    CUncertaintyQuantifier* m_uncertaintyQuantifier;

    // Performance tracking
    double m_totalReturn;
    int m_totalTrades;
    int m_winningTrades;
    datetime m_lastUpdate;

    // AI model parameters
    double m_confidenceThreshold;
    double m_uncertaintyThreshold;
    bool m_useUncertaintyFiltering;

    datetime m_cacheBarTime;
    datetime m_cacheRefreshTime;
    bool m_hasCachedSignal;
    SEnhancedTradeSignal m_cachedSignal;

    datetime GetCurrentBarTime() const
    {
        if(m_symbol == "")
            return 0;
        return iTime(m_symbol, m_timeframe, 0);
    }

    bool NeedsNewInference(const datetime currentBarTime) const
    {
        return (!m_hasCachedSignal ||
                currentBarTime <= 0 ||
                currentBarTime != m_cacheBarTime ||
                m_cacheRefreshTime <= 0 ||
                (TimeCurrent() - m_cacheRefreshTime) >= 10);
    }

    void UpdateSignalCache(const datetime currentBarTime, const SEnhancedTradeSignal &signal)
    {
        m_cachedSignal = signal;
        m_cacheBarTime = currentBarTime;
        m_cacheRefreshTime = TimeCurrent();
        m_hasCachedSignal = true;
    }

    bool WriteCheckpointString(const int fileHandle, const string value)
    {
        int len = (int)StringLen(value);
        FileWriteInteger(fileHandle, len);
        for(int i = 0; i < len; i++)
        {
            ushort ch = (ushort)StringGetCharacter(value, i);
            FileWriteInteger(fileHandle, (int)ch);
        }
        return true;
    }

    void NormalizeScores(double &noneProb, double &buyProb, double &sellProb) const
    {
        noneProb = MathMax(0.0, noneProb);
        buyProb = MathMax(0.0, buyProb);
        sellProb = MathMax(0.0, sellProb);

        double total = noneProb + buyProb + sellProb + 1e-9;
        noneProb /= total;
        buyProb /= total;
        sellProb /= total;
    }

    bool BuildUniversalTransformerPredictions(double &noneProb,
                                              double &buyProb,
                                              double &sellProb)
    {
        double modelInput[];
        const int seqLen = TRANSFORMER_SHORT_SEQ_LEN_DEFAULT;
        if(!CAIFeatureVectorBuilder::BuildTransformerInput(m_symbol,
                                                           m_timeframe,
                                                           modelInput,
                                                           TRANSFORMER_D_MODEL_DEFAULT,
                                                           seqLen))
            return false;

        if(!g_universalTransformerService.IsSymbolRegistered(m_symbol) &&
           !g_universalTransformerService.RegisterSymbol(m_symbol))
            return false;

        double symbolFeatures[];
        if(!g_universalTransformerService.GetSymbolFeatures(m_symbol, modelInput, seqLen, symbolFeatures))
            return false;

        double directional = 0.0;
        double stability = 0.0;
        int limit = MathMin(ArraySize(symbolFeatures), 48);
        for(int i = 0; i < limit; i++)
        {
            double value = symbolFeatures[i];
            directional += value * (((i % 4) < 2) ? 1.0 : -1.0);
            stability += MathAbs(value);
        }

        buyProb = MathMax(0.0, directional);
        sellProb = MathMax(0.0, -directional);
        noneProb = 0.25 + (1.0 / (1.0 + stability));
        NormalizeScores(noneProb, buyProb, sellProb);
        return true;
    }

    bool BuildLocalFallbackPredictions(double &noneProb,
                                       double &buyProb,
                                       double &sellProb)
    {
        double features[];
        if(!CAIFeatureVectorBuilder::BuildNNFeatureVector(m_symbol, m_timeframe, features, 1))
            return false;

        if(ArraySize(features) < 31)
            return false;

        double trendBias = features[5] + features[8] + features[10] - 0.5;
        double meanReversion = (features[12] - 0.5) + (features[11] - 0.5);
        double momentum = features[0] + features[22] + features[30];
        double directional = trendBias + 0.5 * meanReversion + 0.75 * momentum;

        buyProb = MathMax(0.0, directional);
        sellProb = MathMax(0.0, -directional);
        noneProb = 0.20 + MathMax(0.0, 1.0 - MathAbs(directional));
        NormalizeScores(noneProb, buyProb, sellProb);
        return true;
    }

public:
    CNextGenStrategyBrain()
    {
        m_initialized = false;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_usesUniversalTransformer = true;
        m_uncertaintyQuantifier = NULL;
        m_totalReturn = 0.0;
        m_totalTrades = 0;
        m_winningTrades = 0;
        m_lastUpdate = 0;
        m_confidenceThreshold = 0.6;
        m_uncertaintyThreshold = 0.4;
        m_useUncertaintyFiltering = true;
        m_cacheBarTime = 0;
        m_cacheRefreshTime = 0;
        m_hasCachedSignal = false;
    }

    ~CNextGenStrategyBrain()
    {
        if(CheckPointer(m_uncertaintyQuantifier) == POINTER_DYNAMIC)
            delete m_uncertaintyQuantifier;
    }

    bool Initialize(string brainSymbol, ENUM_TIMEFRAMES timeframe)
    {
        if(brainSymbol == "" || brainSymbol == NULL)
        {
            Print("[NEXTGEN] Initialize failed: empty symbol");
            return false;
        }
        m_symbol = brainSymbol;
        m_timeframe = timeframe;

        if(m_uncertaintyQuantifier == NULL)
        {
            m_uncertaintyQuantifier = new CUncertaintyQuantifier(100, 0.95);
            if(m_uncertaintyQuantifier == NULL)
                return false;
        }

        if(m_usesUniversalTransformer)
        {
            if(!g_universalTransformerService.IsSymbolRegistered(m_symbol) &&
               !g_universalTransformerService.RegisterSymbol(m_symbol))
            {
                PrintFormat("[NEXTGEN] ERROR: Failed to register symbol %s with universal transformer service", m_symbol);
                return false;
            }
            Print("[NEXTGEN] Using Universal Transformer service for symbol: ", m_symbol);
        }

        m_cacheBarTime = 0;
        m_cacheRefreshTime = 0;
        m_hasCachedSignal = false;
        m_initialized = true;
        Print("NEXTGEN AI Strategy Brain initialized for ", brainSymbol);
        return true;
    }

    bool GenerateSignal(double price, double volume, const double &indicators[],
                        SEnhancedTradeSignal &signal)
    {
        if(!m_initialized)
            return false;

        datetime currentBarTime = GetCurrentBarTime();
        if(!NeedsNewInference(currentBarTime))
        {
            signal = m_cachedSignal;
            return true;
        }

        double noneProb = 0.0;
        double buyProb = 0.0;
        double sellProb = 0.0;
        bool predictionSuccess = false;

        if(m_usesUniversalTransformer)
            predictionSuccess = BuildUniversalTransformerPredictions(noneProb, buyProb, sellProb);

        if(!predictionSuccess)
            predictionSuccess = BuildLocalFallbackPredictions(noneProb, buyProb, sellProb);

        if(!predictionSuccess)
        {
            signal.signal = TRADE_SIGNAL_NONE;
            signal.confidence = 0.0;
            signal.buyProbability = 0.0;
            signal.sellProbability = 0.0;
            signal.uncertainty = 1.0;
            signal.riskAdjustedSize = 0.0;
            signal.reasoning = "AI feature build failed";
            return false;
        }

        NormalizeScores(noneProb, buyProb, sellProb);

        signal.signal = TRADE_SIGNAL_NONE;
        signal.confidence = noneProb;
        signal.buyProbability = buyProb;
        signal.sellProbability = sellProb;
        signal.timestamp = TimeCurrent();
        signal.reasoning = m_usesUniversalTransformer ? "Universal Transformer" : "Feature Builder Fallback";

        if(m_uncertaintyQuantifier != NULL)
        {
            SPredictionWithUncertainty quantified;
            m_uncertaintyQuantifier.UpdatePredictionHistory(MathMax(buyProb, sellProb));

            // Feed realized price return for proper volatility calculation
            double close0 = iClose(m_symbol, m_timeframe, 0);
            double close1 = iClose(m_symbol, m_timeframe, 1);
            if(close1 > 0.0)
            {
                double priceReturn = (close0 - close1) / close1;
                m_uncertaintyQuantifier.UpdateRealizedVolatility(priceReturn);
            }

            if(m_uncertaintyQuantifier.QuantifyUncertainty(buyProb, sellProb, noneProb, quantified))
            {
                signal.uncertainty = quantified.uncertainty;
                signal.riskAdjustedSize = m_uncertaintyQuantifier.GetRiskAdjustedSize(1.0, quantified.uncertainty);
                if(m_useUncertaintyFiltering &&
                   !m_uncertaintyQuantifier.IsPredictionReliable(quantified,
                                                                 m_confidenceThreshold,
                                                                 m_uncertaintyThreshold))
                {
                    signal.reasoning += " [Uncertainty Filtered]";
                    signal.confidence = 0.0;
                    UpdateSignalCache(currentBarTime, signal);
                    return true;
                }
            }
        }
        else
        {
            double entropy = -(buyProb * MathLog(buyProb + 1e-9) +
                               sellProb * MathLog(sellProb + 1e-9) +
                               noneProb * MathLog(noneProb + 1e-9));
            signal.uncertainty = entropy / MathLog(3.0);
            signal.riskAdjustedSize = 1.0 - signal.uncertainty;
        }

        if(buyProb > sellProb && buyProb > noneProb)
        {
            signal.signal = TRADE_SIGNAL_BUY;
            signal.confidence = buyProb;
        }
        else if(sellProb > buyProb && sellProb > noneProb)
        {
            signal.signal = TRADE_SIGNAL_SELL;
            signal.confidence = sellProb;
        }

        if(signal.confidence < m_confidenceThreshold)
        {
            signal.uncertainty = 1.0 - signal.confidence;
            signal.signal = TRADE_SIGNAL_NONE;
            signal.confidence = 0.0;
            signal.reasoning += " [Low Confidence]";
        }

        signal.isValid = (signal.signal != TRADE_SIGNAL_NONE && signal.confidence > 0.0);
        UpdateSignalCache(currentBarTime, signal);
        return true;
    }

    bool UpdatePerformance(double tradeReturn, bool isWin)
    {
        m_totalTrades++;
        m_totalReturn += tradeReturn;
        if(isWin)
            m_winningTrades++;
        m_lastUpdate = TimeCurrent();

        if(m_usesUniversalTransformer && m_symbol != "")
        {
            double performance = isWin ? 1.0 : 0.0;
            g_universalTransformerService.UpdateSymbolPerformance(m_symbol, performance);
        }

        return true;
    }

    void GetPerformanceStats(double &totalReturn, double &winRate, int &brainTotalTrades)
    {
        totalReturn = m_totalReturn;
        brainTotalTrades = m_totalTrades;
        winRate = (m_totalTrades > 0) ? (double)m_winningTrades / m_totalTrades : 0.0;
    }

    double GetAccuracy()
    {
        return (m_totalTrades > 0) ? (double)m_winningTrades / m_totalTrades : 0.0;
    }

    int GetTradeCount()
    {
        return m_totalTrades;
    }

    bool SaveAIState(string filename)
    {
        int handle = FileOpen(filename, FILE_WRITE | FILE_BIN);
        if(handle == INVALID_HANDLE)
            return false;

        WriteCheckpointString(handle, m_symbol);
        FileWriteInteger(handle, (int)m_timeframe);
        FileWriteDouble(handle, m_totalReturn);
        FileWriteInteger(handle, m_totalTrades);
        FileWriteInteger(handle, m_winningTrades);
        FileWriteLong(handle, (long)m_lastUpdate);
        FileWriteDouble(handle, m_confidenceThreshold);
        FileWriteDouble(handle, m_uncertaintyThreshold);
        FileWriteInteger(handle, m_useUncertaintyFiltering ? 1 : 0);

        FileClose(handle);
        return true;
    }

    string GenerateAIReport()
    {
        string report = "=== NextGen AI Strategy Brain Report ===\n";
        report += StringFormat("Symbol: %s\n", m_symbol);
        report += StringFormat("Timeframe: %s\n", EnumToString(m_timeframe));
        report += StringFormat("Total Trades: %d\n", m_totalTrades);
        report += StringFormat("Win Rate: %.2f%%\n", GetAccuracy() * 100.0);
        report += StringFormat("Total Return: %.2f\n", m_totalReturn);
        report += StringFormat("Uses Universal Transformer: %s\n", m_usesUniversalTransformer ? "YES" : "NO");

        if(m_usesUniversalTransformer)
        {
            double symbolPerformance = g_universalTransformerService.GetSymbolPerformance(m_symbol);
            report += StringFormat("Symbol Performance Score: %.3f\n", symbolPerformance);
        }

        return report;
    }

    double GetCurrentUncertainty()
    {
        if(m_uncertaintyQuantifier == NULL)
            return 1.0;

        double avgUnc, maxUnc, avgErr;
        int samples;
        m_uncertaintyQuantifier.GetUncertaintyStats(avgUnc, maxUnc, avgErr, samples);
        return avgUnc;
    }

    bool IsInitialized() const
    {
        return m_initialized;
    }

    string GetRuntimeMode() const
    {
        return m_usesUniversalTransformer ? "UNIVERSAL_TRANSFORMER" : "LOCAL_PROCESSING";
    }

    void SetUseUniversalTransformer(bool useUniversal)
    {
        m_usesUniversalTransformer = useUniversal;
    }

    bool IsUsingUniversalTransformer() const
    {
        return m_usesUniversalTransformer;
    }
};

#endif // __NEXTGEN_STRATEGY_BRAIN_MQH__
