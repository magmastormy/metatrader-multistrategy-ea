//+------------------------------------------------------------------+
//| VolumeProfileEngine.mqh                                          |
//| Volume Profile with POC, Value Area, HVN/LVN detection           |
//| For forex markets only                                           |
//+------------------------------------------------------------------+
#ifndef CORE_ENGINES_VOLUME_PROFILE_ENGINE_MQH
#define CORE_ENGINES_VOLUME_PROFILE_ENGINE_MQH

#define VP_MAX_LEVELS 500

struct SVolumeProfileResult
{
    double poc;
    double pocVolume;
    double vah;
    double val;
    double valueAreaVol;
    double totalVolume;
    int    levelCount;
    bool   isValid;
};

class CVolumeProfileEngine
{
private:
    string m_symbol;
    int    m_lookbackSessions;
    int    m_priceResolution;
    double m_valueAreaPercent;

    double m_levelPrices[];
    double m_levelVolumes[];
    int    m_levelCount;

    SVolumeProfileResult m_lastResult;
    bool     m_initialized;

    void ResetLevels()
    {
        ArrayResize(m_levelPrices, VP_MAX_LEVELS);
        ArrayResize(m_levelVolumes, VP_MAX_LEVELS);
        ArrayInitialize(m_levelPrices, 0);
        ArrayInitialize(m_levelVolumes, 0);
        m_levelCount = 0;
    }

    int FindOrCreateLevel(double price)
    {
        double resolution = m_priceResolution * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double roundedPrice = NormalizeDouble(MathRound(price / resolution) * resolution,
                                              (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));

        for(int i = 0; i < m_levelCount; i++)
        {
            if(MathAbs(m_levelPrices[i] - roundedPrice) < resolution * 0.5)
            {
                m_levelVolumes[i] += 1;
                return i;
            }
        }

        if(m_levelCount < VP_MAX_LEVELS)
        {
            m_levelPrices[m_levelCount] = roundedPrice;
            m_levelVolumes[m_levelCount] = 1;
            m_levelCount++;
            return m_levelCount - 1;
        }
        return -1;
    }

public:
    CVolumeProfileEngine() : m_symbol(""), m_lookbackSessions(20),
        m_priceResolution(20), m_valueAreaPercent(70.0),
        m_levelCount(0), m_initialized(false)
    {
        ZeroMemory(m_lastResult);
    }

    bool Initialize(string symbol, int lookback = 20, int resolution = 20, double valueAreaPct = 70.0)
    {
        m_symbol = symbol;
        m_lookbackSessions = lookback;
        m_priceResolution = resolution;
        m_valueAreaPercent = valueAreaPct;
        ResetLevels();
        m_initialized = true;
        Print("[VP-ENGINE] Initialized | symbol=", symbol, " | lookback=", lookback, " | resolution=", resolution, " pips");
        return true;
    }

    SVolumeProfileResult Calculate()
    {
        ZeroMemory(m_lastResult);
        if(!m_initialized) return m_lastResult;

        ResetLevels();

        int totalBars = Bars(m_symbol, PERIOD_CURRENT);
        int maxBars = MathMin(totalBars, 2000);

        for(int i = 1; i < maxBars; i++)
        {
            FindOrCreateLevel(GetTypicalPrice(i));
        }

        if(m_levelCount < 10)
        {
            m_lastResult.isValid = false;
            return m_lastResult;
        }

        // Sort by volume to find POC
        int sortedIndices[];
        ArrayResize(sortedIndices, m_levelCount);
        for(int i = 0; i < m_levelCount; i++) sortedIndices[i] = i;

        for(int i = 0; i < m_levelCount - 1; i++)
        {
            for(int j = i + 1; j < m_levelCount; j++)
            {
                if(m_levelVolumes[sortedIndices[j]] > m_levelVolumes[sortedIndices[i]])
                {
                    int temp = sortedIndices[i];
                    sortedIndices[i] = sortedIndices[j];
                    sortedIndices[j] = temp;
                }
            }
        }

        m_lastResult.poc = m_levelPrices[sortedIndices[0]];
        m_lastResult.pocVolume = m_levelVolumes[sortedIndices[0]];

        double totalVol = 0;
        for(int i = 0; i < m_levelCount; i++)
            totalVol += m_levelVolumes[i];
        m_lastResult.totalVolume = totalVol;

        double targetVol = totalVol * m_valueAreaPercent / 100.0;
        double accumulatedVol = m_levelVolumes[sortedIndices[0]];

        int vaHighIdx = sortedIndices[0];
        int vaLowIdx = sortedIndices[0];

        for(int step = 1; step < m_levelCount && accumulatedVol < targetVol; step++)
        {
            double bestAboveVol = 0, bestBelowVol = 0;
            int bestAboveIdx = -1, bestBelowIdx = -1;

            for(int i = 0; i < m_levelCount; i++)
            {
                if(m_levelPrices[i] > m_levelPrices[vaHighIdx] && m_levelVolumes[i] > bestAboveVol)
                {
                    bestAboveVol = m_levelVolumes[i];
                    bestAboveIdx = i;
                }
                if(m_levelPrices[i] < m_levelPrices[vaLowIdx] && m_levelVolumes[i] > bestBelowVol)
                {
                    bestBelowVol = m_levelVolumes[i];
                    bestBelowIdx = i;
                }
            }

            if(bestAboveIdx >= 0 && bestAboveVol >= bestBelowVol)
            {
                vaHighIdx = bestAboveIdx;
                accumulatedVol += bestAboveVol;
            }
            else if(bestBelowIdx >= 0)
            {
                vaLowIdx = bestBelowIdx;
                accumulatedVol += bestBelowVol;
            }
            else break;
        }

        m_lastResult.vah = m_levelPrices[vaHighIdx];
        m_lastResult.val = m_levelPrices[vaLowIdx];
        m_lastResult.valueAreaVol = accumulatedVol;
        m_lastResult.levelCount = m_levelCount;
        m_lastResult.isValid = true;

        return m_lastResult;
    }

    double GetTypicalPrice(int shift)
    {
        return (iHigh(m_symbol, PERIOD_CURRENT, shift) +
                iLow(m_symbol, PERIOD_CURRENT, shift) +
                iClose(m_symbol, PERIOD_CURRENT, shift)) / 3.0;
    }

    bool IsInsideValueArea(double price)
    {
        if(!m_lastResult.isValid) return false;
        return (price >= m_lastResult.val && price <= m_lastResult.vah);
    }

    bool IsAboveValueArea(double price)
    {
        if(!m_lastResult.isValid) return false;
        return price > m_lastResult.vah;
    }

    bool IsBelowValueArea(double price)
    {
        if(!m_lastResult.isValid) return false;
        return price < m_lastResult.val;
    }

    double GetDistanceFromPOC(double price)
    {
        if(!m_lastResult.isValid) return 0;
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(point <= 0) return 0;
        return MathAbs(price - m_lastResult.poc) / point;
    }

    bool IsInitialized() const { return m_initialized; }
    SVolumeProfileResult GetLastResult() const { return m_lastResult; }
};

#endif // CORE_ENGINES_VOLUME_PROFILE_ENGINE_MQH
