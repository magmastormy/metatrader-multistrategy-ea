// Detects toxic order flow via volume-bucket imbalance analysis
#ifndef CORE_RISK_VPIN_FILTER_MQH
#define CORE_RISK_VPIN_FILTER_MQH

#include "../Utils/Enums.mqh"

enum ENUM_VPIN_TOXICITY
{
    VPIN_TOXICITY_LOW      = 0,   // VPIN < 0.3 — safe to trade
    VPIN_TOXICITY_MEDIUM   = 1,   // VPIN 0.3–0.5 — reduce size
    VPIN_TOXICITY_HIGH     = 2,   // VPIN 0.5–0.7 — minimal size
    VPIN_TOXICITY_EXTREME  = 3    // VPIN > 0.7 — kill new positions
};

// How a tick's buy/sell side is attributed
enum ENUM_VPIN_CLASSIFICATION
{
    VPIN_CLASSIFY_TICK_RULE    = 0, // Price change tick rule (default)
    VPIN_CLASSIFY_BID_ASK      = 1, // Use bid/ask spread for classification
    VPIN_CLASSIFY_VOLUME_WEIGHTED = 2 // Weight by tick volume
};

struct SVPINSnapshot
{
    double             vpinValue;              // Current VPIN value [0–1]
    ENUM_VPIN_TOXICITY toxicityRegime;
    double             positionSizeMultiplier;
    int                bucketCount;            // Ring-buffer capacity
    int                completedBuckets;
    double             buyVolumeRatio;         // Buy volume / total volume in latest bucket
    datetime           timestamp;

    SVPINSnapshot() :
        vpinValue(0.0),
        toxicityRegime(VPIN_TOXICITY_LOW),
        positionSizeMultiplier(1.0),
        bucketCount(0),
        completedBuckets(0),
        buyVolumeRatio(0.0),
        timestamp(0)
    {}
};

#define VPIN_MAX_BUCKETS          200   // Rolling window ring-buffer size
#define VPIN_DEFAULT_NUM_BUCKETS  50    // Default number of buckets for VPIN average
#define VPIN_DEFAULT_EXTREME      0.7   // Default extreme toxicity threshold
#define VPIN_WARMUP_BARS          20    // Bars used to auto-calculate bucket volume
#define VPIN_LOG_THROTTLE_SEC     60    // Minimum seconds between throttled log outputs

// VPIN = Volume-Synchronized Probability of Informed Trading: the rolling average of |buy - sell| / volume
// across fixed-VOLUME buckets (not time buckets). Synthetic CFDs have no real LOB data, so the tick rule on
// price changes proxies the buy/sell split. ShouldBlockNewPositions() is the veto but no gate calls it — it is
// read only by this filter's own status line — so the only VPIN effect on live trading is the lot reduction that
// CVPINLotModifier applies from GetPositionSizeMultiplier().
class CVPINFilter
{
private:
    string             m_symbol;
    double             m_bucketVolumeSize;     // Volume per bucket (0 = auto-calculate)
    double             m_bucketSize;
    int                m_numBuckets;           // Buckets in the rolling VPIN average
    double             m_extremeThreshold;     // VPIN level that triggers EXTREME regime

    bool               m_bucketSizeAuto;       // Set when bucketVolumeSize arrived as 0
    bool               m_bucketSizeResolved;   // Cleared again by Reset() while auto

    // Mode written by SetClassificationMode
    ENUM_VPIN_CLASSIFICATION m_classificationMode;

    double             m_prevTickPrice;        // Previous tick price for tick rule
    bool               m_prevTickIsBuy;        // Previous tick classification (true=buy, false=sell)
    bool               m_firstTick;            // True until first tick is processed
    ENUM_VPIN_CLASSIFICATION m_classifyMode;   // Mode read by ClassifyTick (set by the ctor)

    // Current bucket accumulation
    double             m_currentBucketBuyVol;
    double             m_currentBucketSellVol;
    double             m_currentBucketTotalVol;// Compared against m_bucketVolumeSize to close a bucket

    // Completed bucket imbalances (ring buffer)
    double             m_imbalances[];
    int                m_imbalanceCapacity;
    int                m_imbalanceWriteIdx;
    int                m_imbalanceCount;       // Written so far, capped at capacity

    double             m_currentVPIN;
    int                m_completedBuckets;     // Buckets closed since construction: the warmup counter

    datetime           m_lastLogTime;

// Mode picks the rule; an unchanged price inherits the previous side
    bool ClassifyTick(double tickPrice, double tickVolume = 0.0, double bid = 0.0, double ask = 0.0)
    {
        if(m_firstTick)
        {
            // No previous price to compare — default to buy
            m_prevTickPrice = tickPrice;
            m_prevTickIsBuy = true;
            m_firstTick = false;
            return true;
        }

        bool isBuy;
        
        switch(m_classifyMode)
        {
            case VPIN_CLASSIFY_BID_ASK:
                if(bid > 0.0 && ask > 0.0)
                {
                    double midPrice = (bid + ask) / 2.0;
                    if(tickPrice > midPrice)
                        isBuy = true;
                    else if(tickPrice < midPrice)
                        isBuy = false;
                    else
                        isBuy = m_prevTickIsBuy;
                }
                else
                {
                    // Fallback to tick rule
                    if(tickPrice > m_prevTickPrice)
                        isBuy = true;
                    else if(tickPrice < m_prevTickPrice)
                        isBuy = false;
                    else
                        isBuy = m_prevTickIsBuy;
                }
                break;
                
            case VPIN_CLASSIFY_VOLUME_WEIGHTED:
                // Behaves like the tick rule here: tickVolume is not read inside the classification itself
                if(tickPrice > m_prevTickPrice)
                    isBuy = true;
                else if(tickPrice < m_prevTickPrice)
                    isBuy = false;
                else
                    isBuy = m_prevTickIsBuy;
                break;
                
            case VPIN_CLASSIFY_TICK_RULE:
            default:
                if(tickPrice > m_prevTickPrice)
                    isBuy = true;
                else if(tickPrice < m_prevTickPrice)
                    isBuy = false;
                else
                    isBuy = m_prevTickIsBuy;  // Same price — inherit previous classification
                break;
        }

        m_prevTickPrice = tickPrice;
        m_prevTickIsBuy = isBuy;
        return isBuy;
    }

// Bucket volume = average tick volume of the first VPIN_WARMUP_BARS bars, halved
    bool AutoCalculateBucketSize()
    {
        if(!SymbolSelect(m_symbol, true))
        {
            PrintFormat("[VPIN] ERROR: Cannot select symbol %s for auto bucket size calculation", m_symbol);
            return false;
        }

        long volumes[];
        int copied = CopyTickVolume(m_symbol, PERIOD_CURRENT, 0, VPIN_WARMUP_BARS, volumes);
        if(copied < VPIN_WARMUP_BARS)
        {
            PrintFormat("[VPIN] WARNING: Only %d bars available for auto bucket size (need %d)", copied, VPIN_WARMUP_BARS);
            if(copied < 5)
                return false;
        }

        long totalVol = 0;
        for(int i = 0; i < copied; i++)
            totalVol += volumes[i];

        double avgVol = (double)totalVol / (double)copied;
        m_bucketVolumeSize = avgVol * 0.5;

        // Floor at 1.0: sub-unit buckets turn VPIN into noise
        if(m_bucketVolumeSize < 1.0)
            m_bucketVolumeSize = 1.0;

        m_bucketSizeResolved = true;
        PrintFormat("[VPIN] Auto bucket size resolved | avgBarVol=%.0f | bucketVol=%.0f | bars=%d",
                    avgVol, m_bucketVolumeSize, copied);
        return true;
    }

// Closes the bucket: imbalance = |buy - sell| / total volume
    void CompleteBucket()
    {
        double totalVol = m_currentBucketBuyVol + m_currentBucketSellVol;
        if(totalVol <= 0.0)
            return;

        double imbalance = MathAbs(m_currentBucketBuyVol - m_currentBucketSellVol) / totalVol;

            m_imbalances[m_imbalanceWriteIdx] = imbalance;
        m_imbalanceWriteIdx = (m_imbalanceWriteIdx + 1) % m_imbalanceCapacity;
        if(m_imbalanceCount < m_imbalanceCapacity)
            m_imbalanceCount++;

        m_completedBuckets++;

        m_currentBucketBuyVol = 0.0;
        m_currentBucketSellVol = 0.0;
        m_currentBucketTotalVol = 0.0;

        // Recompute VPIN as rolling average over last m_numBuckets imbalances
        RecomputeVPIN();
    }

    void RecomputeVPIN()
    {
        if(m_imbalanceCount == 0)
        {
            m_currentVPIN = 0.0;
            return;
        }

        int count = MathMin(m_imbalanceCount, m_numBuckets);
        double sum = 0.0;

        // Walk backwards from the most recent entry in the ring buffer
        for(int i = 0; i < count; i++)
        {
            int idx = (m_imbalanceWriteIdx - 1 - i + m_imbalanceCapacity) % m_imbalanceCapacity;
            sum += m_imbalances[idx];
        }

        m_currentVPIN = sum / (double)count;
    }

    ENUM_VPIN_TOXICITY ClassifyToxicity(double vpin) const
    {
        if(vpin >= m_extremeThreshold)
            return VPIN_TOXICITY_EXTREME;
        if(vpin >= 0.5)
            return VPIN_TOXICITY_HIGH;
        if(vpin >= 0.3)
            return VPIN_TOXICITY_MEDIUM;
        return VPIN_TOXICITY_LOW;
    }

// Regime to size multiplier: LOW 1.0, MEDIUM 0.5, HIGH 0.25, EXTREME 0.1
    double ToxicityToMultiplier(ENUM_VPIN_TOXICITY regime) const
    {
        switch(regime)
        {
            case VPIN_TOXICITY_LOW:     return 1.0;
            case VPIN_TOXICITY_MEDIUM:  return 0.5;
            case VPIN_TOXICITY_HIGH:    return 0.25;
            case VPIN_TOXICITY_EXTREME: return 0.1;
            default:                    return 1.0;
        }
    }

// Throttled logging — emits at most once per VPIN_LOG_THROTTLE_SEC
    void ThrottledLog(const string message)
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime > 0 && (now - m_lastLogTime) < VPIN_LOG_THROTTLE_SEC)
            return;
        m_lastLogTime = now;
        PrintFormat("[VPIN] %s", message);
    }

public:
    CVPINFilter(const string symbol = "", double bucketVolumeSize = 0.0,
                        int numBuckets = VPIN_DEFAULT_NUM_BUCKETS,
                        double extremeThreshold = VPIN_DEFAULT_EXTREME,
                        ENUM_VPIN_CLASSIFICATION classificationMode = VPIN_CLASSIFY_TICK_RULE) :
            m_symbol(symbol),
            m_bucketVolumeSize(bucketVolumeSize),
            m_numBuckets(numBuckets),
            m_extremeThreshold(extremeThreshold),
            m_bucketSizeAuto(bucketVolumeSize <= 0.0),
            m_bucketSizeResolved(bucketVolumeSize > 0.0),
            m_classifyMode(classificationMode),
                        m_prevTickPrice(0.0),
            m_prevTickIsBuy(true),
            m_firstTick(true),
            m_currentBucketBuyVol(0.0),
            m_currentBucketSellVol(0.0),
            m_currentBucketTotalVol(0.0),
            m_imbalanceWriteIdx(0),
            m_imbalanceCount(0),
            m_currentVPIN(0.0),
            m_completedBuckets(0),
            m_lastLogTime(0)
        {
            // numBuckets clamped to 10..VPIN_MAX_BUCKETS, extremeThreshold to 0.30..0.95
            if(m_numBuckets < 10)
                m_numBuckets = 10;
            if(m_numBuckets > VPIN_MAX_BUCKETS)
                m_numBuckets = VPIN_MAX_BUCKETS;
            if(m_extremeThreshold < 0.3)
                m_extremeThreshold = 0.3;
            if(m_extremeThreshold > 0.95)
                m_extremeThreshold = 0.95;

            m_imbalanceCapacity = VPIN_MAX_BUCKETS;
            ArrayResize(m_imbalances, m_imbalanceCapacity);
            ArrayInitialize(m_imbalances, 0.0);

            PrintFormat("[VPIN] Constructed | symbol=%s | bucketVol=%.0f (%s) | numBuckets=%d | extremeThreshold=%.2f | mode=%d",
                        m_symbol, m_bucketVolumeSize,
                        m_bucketSizeAuto ? "auto" : "manual",
                        m_numBuckets, m_extremeThreshold, m_classificationMode);
        }

        void SetClassificationMode(ENUM_VPIN_CLASSIFICATION mode)
        {
            m_classificationMode = mode;
            PrintFormat("[VPIN] Classification mode set to %d", mode);
        }

    ~CVPINFilter()
    {
        ArrayFree(m_imbalances);
    }

// Feed every tick: classifies the side and accumulates bucket volume
// bid/ask matter only to the BID_ASK mode
        void OnTick(double tickPrice, double tickVolume, double bid = 0.0, double ask = 0.0)
        {
            if(m_bucketSizeAuto && !m_bucketSizeResolved)
            {
                if(!AutoCalculateBucketSize())
                {
                    // Cannot resolve yet — skip this tick
                    return;
                }
            }

            bool isBuy = ClassifyTick(tickPrice, tickVolume, bid, ask);

            // Volume proxy: tick volume is 0 on synthetic CFDs and some forex feeds, so each tick counts as 1 unit
            double effectiveVolume = (tickVolume > 0.0) ? tickVolume : 1.0;

            if(isBuy)
                m_currentBucketBuyVol += effectiveVolume;
            else
                m_currentBucketSellVol += effectiveVolume;
            m_currentBucketTotalVol += effectiveVolume;

            // One tick can fill several buckets, so loop and carry the excess into the next one
            while(m_currentBucketTotalVol >= m_bucketVolumeSize && m_bucketVolumeSize > 0.0)
            {
                double excessVolume = m_currentBucketTotalVol - m_bucketVolumeSize;
                double excessRatio  = excessVolume / m_currentBucketTotalVol;

                // Snapshot the side volumes BEFORE CompleteBucket() zeroes them: carrying the zeroed members
                // gave every overflow bucket buy=sell=0 and diluted VPIN in bursts
                double carryBuyVol  = m_currentBucketBuyVol * excessRatio;
                double carrySellVol = m_currentBucketSellVol * excessRatio;

                CompleteBucket();

                if(excessVolume > 0.0)
                {
                    m_currentBucketBuyVol   = carryBuyVol;
                    m_currentBucketSellVol  = carrySellVol;
                    m_currentBucketTotalVol = excessVolume;
                }
                else
                {
                    m_currentBucketBuyVol = 0.0;
                    m_currentBucketSellVol = 0.0;
                    m_currentBucketTotalVol = 0.0;
                }
            }
        }

// Rolling VPIN in [0..1]; 0.0 until warmup completes
    double GetVPIN() const
    {
        return m_currentVPIN;
    }

    ENUM_VPIN_TOXICITY GetToxicityRegime() const
    {
        return ClassifyToxicity(m_currentVPIN);
    }

// Size multiplier in [0.1..1.0]; 1.0 through warmup, so no shrink before there is data
    double GetPositionSizeMultiplier() const
    {
        if(!IsWarmedUp())
            return 1.0;

        return ToxicityToMultiplier(ClassifyToxicity(m_currentVPIN));
    }

// THE VETO: true once VPIN reaches m_extremeThreshold, so no new positions may be opened
    bool ShouldBlockNewPositions() const
    {
        if(!IsWarmedUp())
            return false;

        return (m_currentVPIN >= m_extremeThreshold);
    }

// Warmup needs m_numBuckets completed buckets; below that every read is a neutral default
    bool IsWarmedUp() const
    {
        return (m_completedBuckets >= m_numBuckets);
    }

    SVPINSnapshot GetSnapshot() const
    {
        SVPINSnapshot snap;
        snap.vpinValue = m_currentVPIN;
        snap.toxicityRegime = ClassifyToxicity(m_currentVPIN);
        snap.positionSizeMultiplier = GetPositionSizeMultiplier();
        snap.bucketCount = m_imbalanceCapacity;
        snap.completedBuckets = m_completedBuckets;

        double totalVol = m_currentBucketBuyVol + m_currentBucketSellVol;
        snap.buyVolumeRatio = (totalVol > 0.0) ? (m_currentBucketBuyVol / totalVol) : 0.0;
        snap.timestamp = TimeCurrent();
        return snap;
    }

    void LogDiagnostics()
    {
        ENUM_VPIN_TOXICITY regime = ClassifyToxicity(m_currentVPIN);
        string regimeStr = "";
        switch(regime)
        {
            case VPIN_TOXICITY_LOW:     regimeStr = "LOW";      break;
            case VPIN_TOXICITY_MEDIUM:  regimeStr = "MEDIUM";   break;
            case VPIN_TOXICITY_HIGH:    regimeStr = "HIGH";     break;
            case VPIN_TOXICITY_EXTREME: regimeStr = "EXTREME";  break;
            default:                    regimeStr = "UNKNOWN";  break;
        }

        double mult = GetPositionSizeMultiplier();
        bool warmedUp = IsWarmedUp();

        string msg = StringFormat("VPIN=%.4f | regime=%s | mult=%.2f | buckets=%d/%d | warmedUp=%s | blockNew=%s",
                                  m_currentVPIN, regimeStr, mult,
                                  m_completedBuckets, m_numBuckets,
                                  warmedUp ? "Y" : "N",
                                  ShouldBlockNewPositions() ? "Y" : "N");

        ThrottledLog(msg);
    }

// Wipes tick/bucket state: call on deinit or when the symbol changes
    void Reset()
    {
        m_prevTickPrice = 0.0;
        m_prevTickIsBuy = true;
        m_firstTick = true;
        m_currentBucketBuyVol = 0.0;
        m_currentBucketSellVol = 0.0;
        m_currentBucketTotalVol = 0.0;
        m_imbalanceWriteIdx = 0;
        m_imbalanceCount = 0;
        m_currentVPIN = 0.0;
        m_completedBuckets = 0;
        m_lastLogTime = 0;

        ArrayInitialize(m_imbalances, 0.0);

        // Re-trigger auto-calculation if originally configured that way
        if(m_bucketSizeAuto)
            m_bucketSizeResolved = false;

        PrintFormat("[VPIN] Reset | symbol=%s", m_symbol);
    }

    void Deinit()
    {
        // m_imbalances[] is the only owned dynamic storage
        ArrayFree(m_imbalances);
        m_imbalanceCount = 0;
        m_imbalanceWriteIdx = 0;
        m_currentVPIN = 0.0;
        m_completedBuckets = 0;
        m_symbol = "";
        m_numBuckets = 0;
        m_bucketSize = 0.0;
    }
};

#endif // CORE_RISK_VPIN_FILTER_MQH
