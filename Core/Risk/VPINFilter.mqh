//+------------------------------------------------------------------+
//| VPINFilter.mqh                                                    |
//| Volume-Synchronized Probability of Informed Trading filter        |
//| Detects toxic order flow via volume-bucket imbalance analysis     |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_VPIN_FILTER_MQH
#define CORE_RISK_VPIN_FILTER_MQH

#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Toxicity Regime Enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_VPIN_TOXICITY
{
    VPIN_TOXICITY_LOW      = 0,   // VPIN < 0.3 — safe to trade
    VPIN_TOXICITY_MEDIUM   = 1,   // VPIN 0.3–0.5 — reduce size
    VPIN_TOXICITY_HIGH     = 2,   // VPIN 0.5–0.7 — minimal size
    VPIN_TOXICITY_EXTREME  = 3    // VPIN > 0.7 — kill new positions
};

//+------------------------------------------------------------------+
//| VPIN Snapshot Structure                                           |
//+------------------------------------------------------------------+
struct SVPINSnapshot
{
    double             vpinValue;              // Current VPIN value [0–1]
    ENUM_VPIN_TOXICITY toxicityRegime;         // Current toxicity regime
    double             positionSizeMultiplier; // Size multiplier [0–1]
    int                bucketCount;            // Total buckets allocated
    int                completedBuckets;       // Number of completed buckets
    double             buyVolumeRatio;         // Buy volume / total volume in latest bucket
    datetime           timestamp;              // Snapshot time

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

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define VPIN_MAX_BUCKETS          200   // Rolling window ring-buffer size
#define VPIN_DEFAULT_NUM_BUCKETS  50    // Default number of buckets for VPIN average
#define VPIN_DEFAULT_EXTREME      0.7   // Default extreme toxicity threshold
#define VPIN_WARMUP_BARS          20    // Bars used to auto-calculate bucket volume
#define VPIN_LOG_THROTTLE_SEC     60    // Minimum seconds between throttled log outputs

//+------------------------------------------------------------------+
//| CVPINFilter — VPIN toxicity filter for risk gating                |
//|                                                                   |
//| Uses volume-synchronized buckets (not time buckets) to compute    |
//| the Volume-Synchronized Probability of Informed Trading (VPIN).   |
//| For synthetic CFDs without real LOB data, tick price changes are  |
//| used as proxy for buy/sell classification via the tick rule.      |
//+------------------------------------------------------------------+
class CVPINFilter
{
private:
    // Configuration
    string             m_symbol;               // Traded symbol
    double             m_bucketVolumeSize;     // Volume per bucket (0 = auto-calculate)
    int                m_numBuckets;           // Number of buckets for rolling VPIN average
    double             m_extremeThreshold;     // VPIN level that triggers EXTREME regime

    // Auto-calculation state
    bool               m_bucketSizeAuto;       // True if bucket size should be auto-calculated
    bool               m_bucketSizeResolved;   // True once auto-calculation is complete

    // Tick classification state (tick rule)
    double             m_prevTickPrice;        // Previous tick price for tick rule
    bool               m_prevTickIsBuy;        // Previous tick classification (true=buy, false=sell)
    bool               m_firstTick;            // True until first tick is processed

    // Current bucket accumulation
    double             m_currentBucketBuyVol;  // Buy volume accumulated in current bucket
    double             m_currentBucketSellVol; // Sell volume accumulated in current bucket
    double             m_currentBucketTotalVol;// Total volume accumulated in current bucket

    // Completed bucket imbalances (ring buffer)
    double             m_imbalances[];         // Ring buffer of bucket imbalances
    int                m_imbalanceCapacity;    // Allocated size of ring buffer
    int                m_imbalanceWriteIdx;    // Next write position in ring buffer
    int                m_imbalanceCount;       // Number of imbalances written (up to capacity)

    // VPIN computation result
    double             m_currentVPIN;          // Latest VPIN value
    int                m_completedBuckets;     // Total completed buckets since start

    // Log throttling
    datetime           m_lastLogTime;          // Last time a throttled log was emitted

    //+------------------------------------------------------------------+
    //| Classify tick as buy or sell using tick rule                      |
    //| If price > prev price → buy                                       |
    //| If price < prev price → sell                                      |
    //| If price == prev price → use previous classification              |
    //+------------------------------------------------------------------+
    bool ClassifyTick(double tickPrice)
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
        if(tickPrice > m_prevTickPrice)
            isBuy = true;
        else if(tickPrice < m_prevTickPrice)
            isBuy = false;
        else
            isBuy = m_prevTickIsBuy;  // Same price — inherit previous classification

        m_prevTickPrice = tickPrice;
        m_prevTickIsBuy = isBuy;
        return isBuy;
    }

    //+------------------------------------------------------------------+
    //| Auto-calculate bucket volume size from average bar tick volume    |
    //| Uses the first VPIN_WARMUP_BARS to compute average tick volume,  |
    //| then sets bucket size = avgVolume * 0.5                           |
    //+------------------------------------------------------------------+
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

        // Floor at a reasonable minimum to avoid degenerate tiny buckets
        if(m_bucketVolumeSize < 1.0)
            m_bucketVolumeSize = 1.0;

        m_bucketSizeResolved = true;
        PrintFormat("[VPIN] Auto bucket size resolved | avgBarVol=%.0f | bucketVol=%.0f | bars=%d",
                    avgVol, m_bucketVolumeSize, copied);
        return true;
    }

    //+------------------------------------------------------------------+
    //| Complete current bucket and push imbalance into ring buffer       |
    //+------------------------------------------------------------------+
    void CompleteBucket()
    {
        double totalVol = m_currentBucketBuyVol + m_currentBucketSellVol;
        if(totalVol <= 0.0)
            return;

        double imbalance = MathAbs(m_currentBucketBuyVol - m_currentBucketSellVol) / totalVol;

        // Store in ring buffer
        m_imbalances[m_imbalanceWriteIdx] = imbalance;
        m_imbalanceWriteIdx = (m_imbalanceWriteIdx + 1) % m_imbalanceCapacity;
        if(m_imbalanceCount < m_imbalanceCapacity)
            m_imbalanceCount++;

        m_completedBuckets++;

        // Reset current bucket
        m_currentBucketBuyVol = 0.0;
        m_currentBucketSellVol = 0.0;
        m_currentBucketTotalVol = 0.0;

        // Recompute VPIN as rolling average over last m_numBuckets imbalances
        RecomputeVPIN();
    }

    //+------------------------------------------------------------------+
    //| Recompute VPIN from ring buffer                                   |
    //+------------------------------------------------------------------+
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

    //+------------------------------------------------------------------+
    //| Classify VPIN value into toxicity regime                          |
    //+------------------------------------------------------------------+
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

    //+------------------------------------------------------------------+
    //| Map toxicity regime to position size multiplier                   |
    //+------------------------------------------------------------------+
    double ToxicityToMultiplier(ENUM_VPIN_TOXICITY regime) const
    {
        switch(regime)
        {
            case VPIN_TOXICITY_LOW:     return 1.0;
            case VPIN_TOXICITY_MEDIUM:  return 0.5;
            case VPIN_TOXICITY_HIGH:    return 0.25;
            case VPIN_TOXICITY_EXTREME: return 0.0;
            default:                    return 1.0;
        }
    }

    //+------------------------------------------------------------------+
    //| Throttled logging — emits at most once per VPIN_LOG_THROTTLE_SEC |
    //+------------------------------------------------------------------+
    void ThrottledLog(const string message)
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime > 0 && (now - m_lastLogTime) < VPIN_LOG_THROTTLE_SEC)
            return;
        m_lastLogTime = now;
        PrintFormat("[VPIN] %s", message);
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //| @param symbol           — trading symbol                          |
    //| @param bucketVolumeSize — volume per bucket (0 = auto-calculate)  |
    //| @param numBuckets       — number of buckets for VPIN average      |
    //| @param extremeThreshold — VPIN level triggering EXTREME regime    |
    //+------------------------------------------------------------------+
    CVPINFilter(const string symbol = "", double bucketVolumeSize = 0.0,
                int numBuckets = VPIN_DEFAULT_NUM_BUCKETS,
                double extremeThreshold = VPIN_DEFAULT_EXTREME) :
        m_symbol(symbol),
        m_bucketVolumeSize(bucketVolumeSize),
        m_numBuckets(numBuckets),
        m_extremeThreshold(extremeThreshold),
        m_bucketSizeAuto(bucketVolumeSize <= 0.0),
        m_bucketSizeResolved(bucketVolumeSize > 0.0),
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
        // Clamp parameters to safe ranges
        if(m_numBuckets < 10)
            m_numBuckets = 10;
        if(m_numBuckets > VPIN_MAX_BUCKETS)
            m_numBuckets = VPIN_MAX_BUCKETS;
        if(m_extremeThreshold < 0.3)
            m_extremeThreshold = 0.3;
        if(m_extremeThreshold > 0.95)
            m_extremeThreshold = 0.95;

        // Allocate ring buffer — store up to VPIN_MAX_BUCKETS imbalances
        m_imbalanceCapacity = VPIN_MAX_BUCKETS;
        ArrayResize(m_imbalances, m_imbalanceCapacity);
        ArrayInitialize(m_imbalances, 0.0);

        PrintFormat("[VPIN] Constructed | symbol=%s | bucketVol=%.0f (%s) | numBuckets=%d | extremeThreshold=%.2f",
                    m_symbol, m_bucketVolumeSize,
                    m_bucketSizeAuto ? "auto" : "manual",
                    m_numBuckets, m_extremeThreshold);
    }

    //+------------------------------------------------------------------+
    //| Destructor                                                        |
    //+------------------------------------------------------------------+
    ~CVPINFilter()
    {
        ArrayFree(m_imbalances);
    }

    //+------------------------------------------------------------------+
    //| OnTick — call every tick to classify and accumulate volume        |
    //| @param tickPrice — current tick price                             |
    //| @param tickVolume — current tick volume                           |
    //+------------------------------------------------------------------+
    void OnTick(double tickPrice, double tickVolume)
    {
        // Auto-calculate bucket size on first ticks if needed
        if(m_bucketSizeAuto && !m_bucketSizeResolved)
        {
            if(!AutoCalculateBucketSize())
            {
                // Cannot resolve yet — skip this tick
                return;
            }
        }

        // Classify tick direction
        bool isBuy = ClassifyTick(tickPrice);

        // When tick volume is 0 (synthetic CFDs, some forex), use unit volume per tick
        double effectiveVolume = (tickVolume > 0.0) ? tickVolume : 1.0;

        // Accumulate into current bucket
        if(isBuy)
            m_currentBucketBuyVol += effectiveVolume;
        else
            m_currentBucketSellVol += effectiveVolume;
        m_currentBucketTotalVol += effectiveVolume;

        // Check if bucket is complete
        if(m_currentBucketTotalVol >= m_bucketVolumeSize)
            CompleteBucket();
    }

    //+------------------------------------------------------------------+
    //| Get current VPIN value                                            |
    //| Returns 0.0 during warmup (insufficient completed buckets)        |
    //+------------------------------------------------------------------+
    double GetVPIN() const
    {
        return m_currentVPIN;
    }

    //+------------------------------------------------------------------+
    //| Get current toxicity regime                                       |
    //+------------------------------------------------------------------+
    ENUM_VPIN_TOXICITY GetToxicityRegime() const
    {
        return ClassifyToxicity(m_currentVPIN);
    }

    //+------------------------------------------------------------------+
    //| Get position size multiplier based on toxicity [0.0–1.0]         |
    //| Returns 1.0 during warmup (safe default)                          |
    //+------------------------------------------------------------------+
    double GetPositionSizeMultiplier() const
    {
        // Warmup guard — not enough data, default to safe (full size)
        if(!IsWarmedUp())
            return 1.0;

        return ToxicityToMultiplier(ClassifyToxicity(m_currentVPIN));
    }

    //+------------------------------------------------------------------+
    //| Should block new positions — true if VPIN > extreme threshold     |
    //+------------------------------------------------------------------+
    bool ShouldBlockNewPositions() const
    {
        if(!IsWarmedUp())
            return false;

        return (m_currentVPIN >= m_extremeThreshold);
    }

    //+------------------------------------------------------------------+
    //| Check if filter has completed warmup (enough buckets for VPIN)    |
    //+------------------------------------------------------------------+
    bool IsWarmedUp() const
    {
        return (m_completedBuckets >= m_numBuckets);
    }

    //+------------------------------------------------------------------+
    //| Get full VPIN snapshot for diagnostics                            |
    //+------------------------------------------------------------------+
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

    //+------------------------------------------------------------------+
    //| Emit throttled diagnostic log                                     |
    //+------------------------------------------------------------------+
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

    //+------------------------------------------------------------------+
    //| Reset all state (call on deinit or symbol change)                 |
    //+------------------------------------------------------------------+
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
};

#endif // CORE_RISK_VPIN_FILTER_MQH
