//+------------------------------------------------------------------+
//| CorrelationEngine.mqh                                            |
//| Single authoritative correlation computation for the EA runtime  |
//| Phase 2.2: Unifies three divergent correlation implementations   |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_CORRELATION_ENGINE_MQH
#define CORE_RISK_CORRELATION_ENGINE_MQH

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define CORR_ENGINE_MAX_SYMBOLS  20
#define CORR_ENGINE_INVALID_IDX  -1

//+------------------------------------------------------------------+
//| Correlation Engine Class                                         |
//| Computes Pearson correlation on H1 returns over configurable     |
//| lookback. Caches full correlation matrix. Recomputes periodically|
//| (default every 300 seconds), not per-trade.                     |
//| Uses fixed-size arrays, no heap allocation in hot path.         |
//+------------------------------------------------------------------+
class CCorrelationEngine
{
private:
    // Configuration
    int      m_lookback;            // H1 bars for Pearson calculation (default 30)
    int      m_refreshIntervalSec;  // Seconds between matrix rebuilds (default 300)
    double   m_conservativeFallback;// Value returned when data insufficient (default 1.0)

    // Symbol registry (fixed-size)
    string   m_symbols[CORR_ENGINE_MAX_SYMBOLS];
    int      m_symbolCount;

    // Cached correlation matrix [i][j] — upper-triangular stored flat
    double   m_matrix[CORR_ENGINE_MAX_SYMBOLS * CORR_ENGINE_MAX_SYMBOLS];

    // Cache timing
    datetime m_lastRefreshTime;
    bool     m_initialized;

    // Internal helpers
    int      FindSymbolIndex(const string symbol) const;
    int      RegisterSymbol(const string symbol);
    void     ComputeMatrix();
    double   ComputePearson(const string symbol1, const string symbol2) const;
    double   GetCachedCorrelation(int idx1, int idx2) const;

public:
             CCorrelationEngine();
            ~CCorrelationEngine();

    // Initialize with configurable parameters
    bool     Initialize(int lookback = 30, int refreshIntervalSec = 300);

    // Refresh the correlation matrix if enough time has elapsed.
    // Call this from the main loop or before querying correlations.
    void     Refresh();

    // Force an immediate matrix rebuild (e.g., after symbol changes)
    void     ForceRefresh();

    // Primary query API
    double   GetCorrelation(const string sym1, const string sym2);

    // Check if symbol has correlated open positions above threshold
    bool     IsCorrelatedCluster(const string symbol, double threshold = 0.7);

    // Count open positions correlated with the given symbol above threshold
    int      CountCorrelatedPositions(const string symbol, double threshold = 0.7);

    // Clear symbol registry (call on deinit or when symbols change significantly)
    void     Reset();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CCorrelationEngine::CCorrelationEngine() :
    m_lookback(30),
    m_refreshIntervalSec(300),
    m_conservativeFallback(1.0),
    m_symbolCount(0),
    m_lastRefreshTime(0),
    m_initialized(false)
{
    ArrayInitialize(m_matrix, 0.0);
    for(int i = 0; i < CORR_ENGINE_MAX_SYMBOLS; i++)
        m_symbols[i] = "";
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CCorrelationEngine::~CCorrelationEngine()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CCorrelationEngine::Initialize(int lookback, int refreshIntervalSec)
{
    if(lookback < 10)
        lookback = 10;
    if(lookback > 200)
        lookback = 200;
    if(refreshIntervalSec < 30)
        refreshIntervalSec = 30;

    m_lookback = lookback;
    m_refreshIntervalSec = refreshIntervalSec;
    m_symbolCount = 0;
    m_lastRefreshTime = 0;
    m_initialized = true;

    ArrayInitialize(m_matrix, 0.0);
    for(int i = 0; i < CORR_ENGINE_MAX_SYMBOLS; i++)
        m_symbols[i] = "";

    PrintFormat("[CORR-ENGINE] Initialized | Lookback=%d H1 bars | Refresh=%d sec | Conservative fallback=%.1f",
                m_lookback, m_refreshIntervalSec, m_conservativeFallback);

    return true;
}

//+------------------------------------------------------------------+
//| Find symbol index in registry                                    |
//+------------------------------------------------------------------+
int CCorrelationEngine::FindSymbolIndex(const string symbol) const
{
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbols[i] == symbol)
            return i;
    }
    return CORR_ENGINE_INVALID_IDX;
}

//+------------------------------------------------------------------+
//| Register a symbol, return its index                              |
//+------------------------------------------------------------------+
int CCorrelationEngine::RegisterSymbol(const string symbol)
{
    int existingIdx = FindSymbolIndex(symbol);
    if(existingIdx != CORR_ENGINE_INVALID_IDX)
        return existingIdx;

    if(m_symbolCount >= CORR_ENGINE_MAX_SYMBOLS)
    {
        PrintFormat("[CORR-ENGINE] Symbol registry full (%d) — cannot register %s",
                    CORR_ENGINE_MAX_SYMBOLS, symbol);
        return CORR_ENGINE_INVALID_IDX;
    }

    m_symbols[m_symbolCount] = symbol;
    m_symbolCount++;
    return m_symbolCount - 1;
}

//+------------------------------------------------------------------+
//| Compute Pearson correlation between two symbols on H1 returns    |
//+------------------------------------------------------------------+
double CCorrelationEngine::ComputePearson(const string symbol1, const string symbol2) const
{
    if(symbol1 == "" || symbol2 == "")
        return m_conservativeFallback;
    if(symbol1 == symbol2)
        return 1.0;

    if(!SymbolSelect(symbol1, true) || !SymbolSelect(symbol2, true))
        return m_conservativeFallback;

    double prices1[];
    double prices2[];

    if(CopyClose(symbol1, PERIOD_H1, 0, m_lookback, prices1) < m_lookback ||
       CopyClose(symbol2, PERIOD_H1, 0, m_lookback, prices2) < m_lookback)
        return m_conservativeFallback;

    // Compute log returns
    int n = m_lookback - 1;
    double sum1 = 0.0, sum2 = 0.0, sum12 = 0.0, sum1sq = 0.0, sum2sq = 0.0;

    for(int i = 1; i < m_lookback; i++)
    {
        if(prices1[i - 1] <= 0.0 || prices2[i - 1] <= 0.0)
            return m_conservativeFallback;

        double ret1 = (prices1[i] - prices1[i - 1]) / prices1[i - 1];
        double ret2 = (prices2[i] - prices2[i - 1]) / prices2[i - 1];

        sum1   += ret1;
        sum2   += ret2;
        sum12  += ret1 * ret2;
        sum1sq += ret1 * ret1;
        sum2sq += ret2 * ret2;
    }

    double numerator   = n * sum12 - sum1 * sum2;
    double denominator = MathSqrt((n * sum1sq - sum1 * sum1) * (n * sum2sq - sum2 * sum2));

    if(denominator <= 0.0)
        return m_conservativeFallback;

    double correlation = numerator / denominator;

    // Clamp to [-1, 1] for numerical safety
    if(correlation > 1.0)  correlation = 1.0;
    if(correlation < -1.0) correlation = -1.0;

    return correlation;
}

//+------------------------------------------------------------------+
//| Get cached correlation value by matrix indices                   |
//+------------------------------------------------------------------+
double CCorrelationEngine::GetCachedCorrelation(int idx1, int idx2) const
{
    if(idx1 < 0 || idx1 >= m_symbolCount || idx2 < 0 || idx2 >= m_symbolCount)
        return m_conservativeFallback;

    return m_matrix[idx1 * CORR_ENGINE_MAX_SYMBOLS + idx2];
}

//+------------------------------------------------------------------+
//| Compute the full correlation matrix                              |
//+------------------------------------------------------------------+
void CCorrelationEngine::ComputeMatrix()
{
    // Register all currently open position symbols
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0 || !PositionSelectByTicket(ticket))
            continue;
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        RegisterSymbol(posSymbol);
    }

    // Compute pairwise Pearson correlations
    for(int i = 0; i < m_symbolCount; i++)
    {
        // Diagonal: self-correlation = 1.0
        m_matrix[i * CORR_ENGINE_MAX_SYMBOLS + i] = 1.0;

        for(int j = i + 1; j < m_symbolCount; j++)
        {
            double corr = ComputePearson(m_symbols[i], m_symbols[j]);
            m_matrix[i * CORR_ENGINE_MAX_SYMBOLS + j] = corr;
            m_matrix[j * CORR_ENGINE_MAX_SYMBOLS + i] = corr; // Symmetric
        }
    }
}

//+------------------------------------------------------------------+
//| Refresh if enough time has elapsed                               |
//+------------------------------------------------------------------+
void CCorrelationEngine::Refresh()
{
    if(!m_initialized)
        return;

    datetime now = TimeCurrent();
    if(m_lastRefreshTime > 0 && (now - m_lastRefreshTime) < m_refreshIntervalSec)
        return;

    ComputeMatrix();
    m_lastRefreshTime = now;
}

//+------------------------------------------------------------------+
//| Force immediate matrix rebuild                                   |
//+------------------------------------------------------------------+
void CCorrelationEngine::ForceRefresh()
{
    if(!m_initialized)
        return;

    ComputeMatrix();
    m_lastRefreshTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Get correlation between two symbols                              |
//+------------------------------------------------------------------+
double CCorrelationEngine::GetCorrelation(const string sym1, const string sym2)
{
    if(!m_initialized)
        return m_conservativeFallback;

    if(sym1 == sym2)
        return 1.0;

    // Ensure symbols are registered
    int idx1 = RegisterSymbol(sym1);
    int idx2 = RegisterSymbol(sym2);

    if(idx1 == CORR_ENGINE_INVALID_IDX || idx2 == CORR_ENGINE_INVALID_IDX)
        return m_conservativeFallback;

    // If matrix is stale, refresh it
    datetime now = TimeCurrent();
    if(m_lastRefreshTime == 0 || (now - m_lastRefreshTime) >= m_refreshIntervalSec)
        Refresh();

    return GetCachedCorrelation(idx1, idx2);
}

//+------------------------------------------------------------------+
//| Check if symbol has correlated open positions above threshold    |
//+------------------------------------------------------------------+
bool CCorrelationEngine::IsCorrelatedCluster(const string symbol, double threshold)
{
    return (CountCorrelatedPositions(symbol, threshold) > 0);
}

//+------------------------------------------------------------------+
//| Count open positions correlated with symbol above threshold      |
//+------------------------------------------------------------------+
int CCorrelationEngine::CountCorrelatedPositions(const string symbol, double threshold)
{
    if(!m_initialized)
        return 0;

    int count = 0;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0 || !PositionSelectByTicket(ticket))
            continue;

        string posSymbol = PositionGetString(POSITION_SYMBOL);
        if(posSymbol == symbol)
            continue;

        double corr = MathAbs(GetCorrelation(symbol, posSymbol));
        if(corr > threshold)
            count++;
    }

    return count;
}

//+------------------------------------------------------------------+
//| Reset symbol registry and matrix                                 |
//+------------------------------------------------------------------+
void CCorrelationEngine::Reset()
{
    m_symbolCount = 0;
    ArrayInitialize(m_matrix, 0.0);
    for(int i = 0; i < CORR_ENGINE_MAX_SYMBOLS; i++)
        m_symbols[i] = "";
    m_lastRefreshTime = 0;
}

#endif // CORE_RISK_CORRELATION_ENGINE_MQH
