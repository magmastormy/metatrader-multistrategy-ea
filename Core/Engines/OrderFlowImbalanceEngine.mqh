// Order Flow Imbalance (OFI) Proxy Engine
// Proxy OFI from tick data for synthetic CFDs / forex
#property copyright "Enterprise Trading Solutions"
#property version   "1.0"
#property strict

#ifndef ORDER_FLOW_IMBALANCE_ENGINE_MQH
#define ORDER_FLOW_IMBALANCE_ENGINE_MQH

#include "../Utils/Enums.mqh"

struct SOFISnapshot
{
    double   compositeOFI;       // Weighted composite OFI z-score
    double   fastOFI;            // Fast-window OFI z-score
    double   mediumOFI;          // Medium-window OFI z-score
    double   slowOFI;            // Slow-window OFI z-score
    double   buyPressureRatio;   // buy_volume / total_volume [0-1]
    double   totalVolume;        // Cumulative tick volume in current window
    long     tickCount;          // Total ticks processed since init
    ENUM_TRADE_SIGNAL signal;    // Discretised signal (BUY/SELL/NONE)
    datetime timestamp;          // Snapshot time

    SOFISnapshot() :
        compositeOFI(0.0),
        fastOFI(0.0),
        mediumOFI(0.0),
        slowOFI(0.0),
        buyPressureRatio(0.5),
        totalVolume(0.0),
        tickCount(0),
        signal(TRADE_SIGNAL_NONE),
        timestamp(0)
    {}
};

// Per-level rolling window state (Welford + cumulative volumes)
struct SOFIWindowState
{
    int    windowSize;           // Number of ticks in rolling window
    double cumBuyVolume;         // Cumulative buy-pressure volume in window
    double cumSellVolume;        // Cumulative sell-pressure volume in window

    int    head;                 // Next write position
    int    count;                // Items currently in buffer

    // Welford online algorithm state for z-score of OFI_normalized
    long   wCount;              // Number of observations fed to Welford
    double wMean;               // Running mean
    double wM2;                 // Running M2 (sum of squared deviations)

    double lastOFINormalized;   // Most recent OFI_normalized value
    double lastOFIZScore;       // Most recent z-score

    double buyVolumes[];        // Ring buffer of buy volumes per tick
    double sellVolumes[];       // Ring buffer of sell volumes per tick

    SOFIWindowState() :
        windowSize(0),
        cumBuyVolume(0.0),
        cumSellVolume(0.0),
        head(0),
        count(0),
        wCount(0),
        wMean(0.0),
        wM2(0.0),
        lastOFINormalized(0.0),
        lastOFIZScore(0.0)
    {}

    void Init(int size)
    {
        windowSize = size;
        cumBuyVolume = 0.0;
        cumSellVolume = 0.0;
        head = 0;
        count = 0;
        wCount = 0;
        wMean = 0.0;
        wM2 = 0.0;
        lastOFINormalized = 0.0;
        lastOFIZScore = 0.0;
        ArrayResize(buyVolumes, size);
        ArrayResize(sellVolumes, size);
        ArrayInitialize(buyVolumes, 0.0);
        ArrayInitialize(sellVolumes, 0.0);
    }

    void PushTick(double buyVol, double sellVol)
    {
        // Evict oldest entry if buffer is full
        if(count >= windowSize)
        {
            cumBuyVolume  -= buyVolumes[head];
            cumSellVolume -= sellVolumes[head];
        }
        else
        {
            count++;
        }

        buyVolumes[head]  = buyVol;
        sellVolumes[head] = sellVol;
        cumBuyVolume  += buyVol;
        cumSellVolume += sellVol;

        head = (head + 1) % windowSize;

        // Compute OFI_normalized for this window
        double totalVol = cumBuyVolume + cumSellVolume;
        if(totalVol > 0.0)
            lastOFINormalized = (cumBuyVolume - cumSellVolume) / totalVol;
        else
            lastOFINormalized = 0.0;

        // Welford online update for z-score
        wCount++;
        double delta = lastOFINormalized - wMean;
        wMean += delta / (double)wCount;
        double delta2 = lastOFINormalized - wMean;
        wM2 += delta * delta2;

        // Compute z-score (need at least 2 observations for variance)
        if(wCount >= 2 && wM2 > 0.0)
            lastOFIZScore = (lastOFINormalized - wMean) / MathSqrt(wM2 / (double)wCount);
        else
            lastOFIZScore = 0.0;
    }
};

class COrderFlowImbalanceEngine
{
private:
    string            m_symbol;
    int               m_fastWindow;
    int               m_mediumWindow;
    int               m_slowWindow;
    double            m_signalThreshold;
    double            m_weightFast;
    double            m_weightMedium;
    double            m_weightSlow;

    SOFIWindowState   m_fast;
    SOFIWindowState   m_medium;
    SOFIWindowState   m_slow;

    double            m_prevPrice;
    double            m_prevBidAskMid;
    int               m_lastClassification;   // +1 buy, -1 sell, 0 none
    long              m_tickCount;
    datetime          m_lastLogTime;

    SOFISnapshot      m_snapshot;

    int  ClassifyTick(double price, double bidAskMid);
    void ParseCompositeWeights(const string weightsStr);

public:
    COrderFlowImbalanceEngine();
    ~COrderFlowImbalanceEngine();

    void Init(const string symbol,
              int fastWindow = 5,
              int mediumWindow = 20,
              int slowWindow = 100,
              double signalThreshold = 1.5,
              const string compositeWeights = "0.5,0.3,0.2");

    void OnTick(double price, double tickVolume, double bid = 0.0, double ask = 0.0);

    double            GetOFI()           const;
    bool              GetOFILevels(double &fast, double &medium, double &slow) const;
    double            GetBuyPressureRatio() const;
    ENUM_TRADE_SIGNAL GetSignal()        const;
    bool              GetSnapshot(SOFISnapshot &snap) const;
    bool              IsWarmedUp()       const;
    void              Reset();
    void              Deinit();
};

COrderFlowImbalanceEngine::COrderFlowImbalanceEngine() :
    m_symbol(""),
    m_fastWindow(5),
    m_mediumWindow(20),
    m_slowWindow(100),
    m_signalThreshold(1.5),
    m_weightFast(0.5),
    m_weightMedium(0.3),
    m_weightSlow(0.2),
    m_prevPrice(0.0),
    m_prevBidAskMid(0.0),
    m_lastClassification(0),
    m_tickCount(0),
    m_lastLogTime(0)
{
}

COrderFlowImbalanceEngine::~COrderFlowImbalanceEngine()
{
}

void COrderFlowImbalanceEngine::ParseCompositeWeights(const string weightsStr)
{
    m_weightFast   = 0.5;
    m_weightMedium = 0.3;
    m_weightSlow   = 0.2;

    if(weightsStr == "")
        return;

    string parts[];
    ushort separator = StringGetCharacter(",", 0);
    int count = StringSplit(weightsStr, separator, parts);
    if(count >= 1) m_weightFast   = MathMax(0.0, StringToDouble(parts[0]));
    if(count >= 2) m_weightMedium = MathMax(0.0, StringToDouble(parts[1]));
    if(count >= 3) m_weightSlow   = MathMax(0.0, StringToDouble(parts[2]));

    // Normalise so weights sum to 1.0
    double total = m_weightFast + m_weightMedium + m_weightSlow;
    if(total > 0.0)
    {
        m_weightFast   /= total;
        m_weightMedium /= total;
        m_weightSlow   /= total;
    }
    else
    {
        m_weightFast   = 0.5;
        m_weightMedium = 0.3;
        m_weightSlow   = 0.2;
    }
}

void COrderFlowImbalanceEngine::Init(const string symbol,
                                      int fastWindow,
                                      int mediumWindow,
                                      int slowWindow,
                                      double signalThreshold,
                                      const string compositeWeights)
{
    m_symbol          = symbol;
    m_fastWindow      = MathMax(2, fastWindow);
    m_mediumWindow    = MathMax(2, mediumWindow);
    m_slowWindow      = MathMax(2, slowWindow);
    m_signalThreshold = MathMax(0.1, signalThreshold);

    ParseCompositeWeights(compositeWeights);

    m_fast.Init(m_fastWindow);
    m_medium.Init(m_mediumWindow);
    m_slow.Init(m_slowWindow);

    m_prevPrice        = 0.0;
    m_prevBidAskMid    = 0.0;
    m_lastClassification = 0;
    m_tickCount        = 0;
    m_lastLogTime      = 0;
    m_snapshot         = SOFISnapshot();

    PrintFormat("[OFI] INIT | symbol=%s | fast=%d | medium=%d | slow=%d | threshold=%.2f | weights=%.2f,%.2f,%.2f",
                m_symbol, m_fastWindow, m_mediumWindow, m_slowWindow,
                m_signalThreshold, m_weightFast, m_weightMedium, m_weightSlow);
}

// Classify a tick as buy-pressure (+1) or sell-pressure (-1)
int COrderFlowImbalanceEngine::ClassifyTick(double price, double bidAskMid)
{
    if(m_prevPrice <= 0.0)
        return 0;  // First tick — no classification

    if(price > m_prevPrice)
        return 1;   // Uptick → buy pressure
    if(price < m_prevPrice)
        return -1;  // Downtick → sell pressure

    // Price unchanged — try bid-ask midpoint delta
    if(bidAskMid > 0.0 && m_prevBidAskMid > 0.0)
    {
        if(bidAskMid > m_prevBidAskMid)
            return 1;
        if(bidAskMid < m_prevBidAskMid)
            return -1;
    }

    // Still undetermined — use previous classification
    return m_lastClassification;
}

void COrderFlowImbalanceEngine::OnTick(double price, double tickVolume, double bid, double ask)
{
    if(price <= 0.0)
        return;

    double bidAskMid = 0.0;
    if(bid > 0.0 && ask > 0.0)
        bidAskMid = (bid + ask) / 2.0;

    int classification = ClassifyTick(price, bidAskMid);

    // When tick volume is 0 (synthetic CFDs, some forex), use unit volume per tick
    double effectiveVolume = (tickVolume > 0.0) ? tickVolume : 1.0;
    double buyVol  = 0.0;
    double sellVol = 0.0;
    if(classification > 0)
        buyVol  = effectiveVolume;
    else if(classification < 0)
        sellVol = effectiveVolume;
    // classification == 0: no volume added (first tick or truly neutral)

    m_lastClassification = classification;
    m_prevPrice       = price;
    m_prevBidAskMid   = bidAskMid;
    m_tickCount++;

    m_fast.PushTick(buyVol, sellVol);
    m_medium.PushTick(buyVol, sellVol);
    m_slow.PushTick(buyVol, sellVol);

    double compositeOFI = m_weightFast   * m_fast.lastOFIZScore
                        + m_weightMedium * m_medium.lastOFIZScore
                        + m_weightSlow   * m_slow.lastOFIZScore;

    // Buy pressure ratio from slow (widest) window
    double totalVol = m_slow.cumBuyVolume + m_slow.cumSellVolume;
    double buyPressureRatio = (totalVol > 0.0) ? (m_slow.cumBuyVolume / totalVol) : 0.5;

    ENUM_TRADE_SIGNAL sig = TRADE_SIGNAL_NONE;
    if(compositeOFI > m_signalThreshold)
        sig = TRADE_SIGNAL_BUY;
    else if(compositeOFI < -m_signalThreshold)
        sig = TRADE_SIGNAL_SELL;

    m_snapshot.compositeOFI    = compositeOFI;
    m_snapshot.fastOFI         = m_fast.lastOFIZScore;
    m_snapshot.mediumOFI       = m_medium.lastOFIZScore;
    m_snapshot.slowOFI         = m_slow.lastOFIZScore;
    m_snapshot.buyPressureRatio = buyPressureRatio;
    m_snapshot.totalVolume     = totalVol;
    m_snapshot.tickCount       = m_tickCount;
    m_snapshot.signal          = sig;
    m_snapshot.timestamp       = TimeCurrent();

    // Throttled logging — at most once per 60 seconds
    datetime now = TimeCurrent();
    if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
    {
        PrintFormat("[OFI] %s | composite=%.3f | fast=%.3f | medium=%.3f | slow=%.3f | buyRatio=%.3f | vol=%.0f | ticks=%d | signal=%s | warmup=%s",
                    m_symbol,
                    compositeOFI,
                    m_fast.lastOFIZScore,
                    m_medium.lastOFIZScore,
                    m_slow.lastOFIZScore,
                    buyPressureRatio,
                    totalVol,
                    m_tickCount,
                    EnumToString(sig),
                    IsWarmedUp() ? "YES" : "NO");
        m_lastLogTime = now;
    }
}

double COrderFlowImbalanceEngine::GetOFI() const
{
    return m_snapshot.compositeOFI;
}

bool COrderFlowImbalanceEngine::GetOFILevels(double &fast, double &medium, double &slow) const
{
    fast   = m_snapshot.fastOFI;
    medium = m_snapshot.mediumOFI;
    slow   = m_snapshot.slowOFI;
    return IsWarmedUp();
}

double COrderFlowImbalanceEngine::GetBuyPressureRatio() const
{
    return m_snapshot.buyPressureRatio;
}

ENUM_TRADE_SIGNAL COrderFlowImbalanceEngine::GetSignal() const
{
    if(!IsWarmedUp())
        return TRADE_SIGNAL_NONE;
    return m_snapshot.signal;
}

bool COrderFlowImbalanceEngine::GetSnapshot(SOFISnapshot &snap) const
{
    snap = m_snapshot;
    return IsWarmedUp();
}

// Warmup guard — need at least slowWindow ticks
bool COrderFlowImbalanceEngine::IsWarmedUp() const
{
    return (m_tickCount >= m_slowWindow);
}

void COrderFlowImbalanceEngine::Reset()
{
    m_fast.Init(m_fastWindow);
    m_medium.Init(m_mediumWindow);
    m_slow.Init(m_slowWindow);

    m_prevPrice         = 0.0;
    m_prevBidAskMid     = 0.0;
    m_lastClassification = 0;
    m_tickCount         = 0;
    m_lastLogTime       = 0;
    m_snapshot          = SOFISnapshot();

    PrintFormat("[OFI] RESET | symbol=%s", m_symbol);
}

void COrderFlowImbalanceEngine::Deinit()
{
    // COrderFlowImbalanceEngine owns dynamic arrays in SOFIWindowState structs
    ArrayFree(m_fast.buyVolumes);
    ArrayFree(m_fast.sellVolumes);
    ArrayFree(m_medium.buyVolumes);
    ArrayFree(m_medium.sellVolumes);
    ArrayFree(m_slow.buyVolumes);
    ArrayFree(m_slow.sellVolumes);
    
    m_fast.windowSize = 0;
    m_medium.windowSize = 0;
    m_slow.windowSize = 0;
    m_fast.count = 0;
    m_medium.count = 0;
    m_slow.count = 0;
    
    m_symbol = "";
    m_tickCount = 0;
    m_snapshot = SOFISnapshot();
}

#endif // ORDER_FLOW_IMBALANCE_ENGINE_MQH
