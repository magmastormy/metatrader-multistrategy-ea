//+------------------------------------------------------------------+
//| HarmonicScanner.mqh                                              |
//| Harmonic cross-validation for Elliott Wave projections           |
//+------------------------------------------------------------------+
#property strict

#ifndef __ELLIOTT_HARMONIC_SCANNER_MQH__
#define __ELLIOTT_HARMONIC_SCANNER_MQH__

#include "ZigZagFilter.mqh"

struct SHarmonicPattern
{
    bool                isValid;
    bool                isBullish;
    string              name;
    double              x;
    double              a;
    double              b;
    double              c;
    double              projectedD;
    double              przLow;
    double              przHigh;
    double              confidence;

    SHarmonicPattern() :
        isValid(false),
        isBullish(true),
        name(""),
        x(0.0),
        a(0.0),
        b(0.0),
        c(0.0),
        projectedD(0.0),
        przLow(0.0),
        przHigh(0.0),
        confidence(0.0)
    {
    }
};

class CHarmonicScanner
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    CZigZagFilter*  m_zigzag;
    bool            m_ownZigZag;
    SHarmonicPattern m_patterns[];
    int             m_patternCount;
    double          m_tolerance;

    double ScoreExactRatio(const double actual, const double target) const
    {
        if(target <= 0.0)
            return 0.0;
        double relativeError = MathAbs(actual - target) / target;
        return MathMax(0.0, 1.0 - (relativeError / MathMax(0.05, m_tolerance)));
    }

    double ScoreRangeRatio(const double actual, const double minValue, const double maxValue) const
    {
        double minBound = minValue * (1.0 - m_tolerance);
        double maxBound = maxValue * (1.0 + m_tolerance);
        if(actual < minBound || actual > maxBound)
            return 0.0;

        double midpoint = (minValue + maxValue) * 0.5;
        double halfSpan = MathMax((maxValue - minValue) * 0.5, 0.00001);
        return MathMax(0.0, 1.0 - (MathAbs(actual - midpoint) / (halfSpan * (1.0 + m_tolerance))));
    }

    void AddPattern(const SHarmonicPattern &pattern)
    {
        int size = ArraySize(m_patterns);
        ArrayResize(m_patterns, size + 1);
        m_patterns[size] = pattern;
        m_patternCount = size + 1;
    }

    void EvaluatePatternCandidate(const SZigZagPivot &pX,
                                  const SZigZagPivot &pA,
                                  const SZigZagPivot &pB,
                                  const SZigZagPivot &pC,
                                  const bool isBullish,
                                  const string name,
                                  const double xaTarget,
                                  const double abMin,
                                  const double abMax,
                                  const double bcMin,
                                  const double bcMax,
                                  const double cdMin,
                                  const double cdMax)
    {
        double xa = MathAbs(pA.price - pX.price);
        double ab = MathAbs(pB.price - pA.price);
        double bc = MathAbs(pC.price - pB.price);
        if(xa <= 0.0 || ab <= 0.0 || bc <= 0.0)
            return;

        double abRatio = ab / xa;
        double bcRatio = bc / ab;
        double cdRatioMid = (cdMin + cdMax) * 0.5;

        double abScore = ScoreRangeRatio(abRatio, abMin, abMax);
        double bcScore = ScoreRangeRatio(bcRatio, bcMin, bcMax);
        double cdScore = ScoreRangeRatio(cdRatioMid, cdMin, cdMax);
        if(abScore <= 0.0 || bcScore <= 0.0 || cdScore <= 0.0)
            return;

        double direction = (pA.price > pX.price) ? 1.0 : -1.0;
        double dFromXa = pX.price + ((pA.price - pX.price) * xaTarget);
        double dFromCd = pC.price + (direction * bc * cdRatioMid);

        SHarmonicPattern pattern;
        pattern.isValid = true;
        pattern.isBullish = isBullish;
        pattern.name = name;
        pattern.x = pX.price;
        pattern.a = pA.price;
        pattern.b = pB.price;
        pattern.c = pC.price;
        pattern.projectedD = (dFromXa + dFromCd) * 0.5;
        pattern.przLow = MathMin(dFromXa, dFromCd);
        pattern.przHigh = MathMax(dFromXa, dFromCd);
        pattern.confidence = MathMax(0.0, MathMin(1.0, (abScore + bcScore + cdScore) / 3.0));
        AddPattern(pattern);
    }

    void ScanPatterns()
    {
        ArrayResize(m_patterns, 0);
        m_patternCount = 0;
        if(m_zigzag == NULL)
            return;

        int pivotCount = m_zigzag.GetPivotCount();
        if(pivotCount < 4)
            return;

        int maxOffset = MathMin(pivotCount - 4, 8);
        for(int offset = 0; offset <= maxOffset; offset++)
        {
            SZigZagPivot pX, pA, pB, pC;
            if(!m_zigzag.GetPivotAt(offset, pX) ||
               !m_zigzag.GetPivotAt(offset + 1, pA) ||
               !m_zigzag.GetPivotAt(offset + 2, pB) ||
               !m_zigzag.GetPivotAt(offset + 3, pC))
            {
                continue;
            }

            bool bullishStructure = (pA.price < pX.price && pB.price > pA.price && pC.price < pB.price);
            bool bearishStructure = (pA.price > pX.price && pB.price < pA.price && pC.price > pB.price);
            if(!bullishStructure && !bearishStructure)
                continue;

            bool isBullish = bullishStructure;
            EvaluatePatternCandidate(pX, pA, pB, pC, isBullish, "Gartley", 0.786, 0.55, 0.68, 0.382, 0.886, 1.13, 1.618);
            EvaluatePatternCandidate(pX, pA, pB, pC, isBullish, "Bat",       0.886, 0.382, 0.500, 0.382, 0.886, 1.618, 2.618);
            EvaluatePatternCandidate(pX, pA, pB, pC, isBullish, "Butterfly", 1.272, 0.72, 0.85, 0.382, 0.886, 1.618, 2.240);
            EvaluatePatternCandidate(pX, pA, pB, pC, isBullish, "Crab",      1.618, 0.382, 0.618, 0.382, 0.886, 2.240, 3.618);
        }
    }

public:
                    CHarmonicScanner() :
                        m_symbol(""),
                        m_timeframe(PERIOD_CURRENT),
                        m_zigzag(NULL),
                        m_ownZigZag(false),
                        m_patternCount(0),
                        m_tolerance(0.12)
                    {
                        ArrayResize(m_patterns, 0);
                    }

                   ~CHarmonicScanner()
                    {
                        Deinit();
                    }

    bool Initialize(const string symbol, const ENUM_TIMEFRAMES timeframe, CZigZagFilter* zigzag = NULL)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_patternCount = 0;
        ArrayResize(m_patterns, 0);

        if(zigzag != NULL)
        {
            m_zigzag = zigzag;
            m_ownZigZag = false;
            return true;
        }

        m_zigzag = new CZigZagFilter();
        if(m_zigzag == NULL)
            return false;

        if(!m_zigzag.Initialize(symbol, timeframe))
        {
            delete m_zigzag;
            m_zigzag = NULL;
            return false;
        }

        m_ownZigZag = true;
        return true;
    }

    void Deinit()
    {
        if(m_ownZigZag && m_zigzag != NULL)
        {
            delete m_zigzag;
            m_zigzag = NULL;
        }
        ArrayResize(m_patterns, 0);
        m_patternCount = 0;
    }

    void Update()
    {
        if(m_ownZigZag && m_zigzag != NULL)
            m_zigzag.Update(250);
        ScanPatterns();
    }

    bool FindBestHarmonic(const bool bullish, SHarmonicPattern &pattern) const
    {
        double bestConfidence = 0.0;
        int bestIdx = -1;

        for(int i = 0; i < ArraySize(m_patterns); i++)
        {
            if(!m_patterns[i].isValid || m_patterns[i].isBullish != bullish)
                continue;

            if(m_patterns[i].confidence > bestConfidence)
            {
                bestConfidence = m_patterns[i].confidence;
                bestIdx = i;
            }
        }

        if(bestIdx < 0)
            return false;

        pattern = m_patterns[bestIdx];
        return true;
    }
};

#endif // __ELLIOTT_HARMONIC_SCANNER_MQH__
