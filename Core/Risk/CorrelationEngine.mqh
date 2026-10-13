// Single authoritative correlation computation: every consumer queries this engine's GetCorrelation.
#ifndef CORE_RISK_CORRELATION_ENGINE_MQH
#define CORE_RISK_CORRELATION_ENGINE_MQH

#define CORR_ENGINE_MAX_SYMBOLS  20
#define CORR_ENGINE_INVALID_IDX  -1

// Pearson correlation on H1 simple returns over m_lookback bars, cached as a full matrix and
// rebuilt on an interval (default 300s), not per query. Registry and matrix are fixed-size.
class CCorrelationEngine
{
private:
    int      m_lookback;            // H1 bars for Pearson calculation (default 30)
    int      m_refreshIntervalSec;  // Seconds between matrix rebuilds (default 300)
    double   m_conservativeFallback;// Value returned when data insufficient (default 0.0)
    double   m_assetClassThreshold; // L5-016: Correlation threshold for same asset class (default 0.85)
    double   m_crossAssetThreshold; // L5-016: Correlation threshold for different asset classes (default 0.7)

    string   m_symbols[CORR_ENGINE_MAX_SYMBOLS];
    int      m_symbolCount;

    // Cached matrix, flat [i*CORR_ENGINE_MAX_SYMBOLS + j]; ComputeMatrix writes both triangles.
    double   m_matrix[CORR_ENGINE_MAX_SYMBOLS * CORR_ENGINE_MAX_SYMBOLS];

    datetime m_lastRefreshTime;
    bool     m_initialized;

    bool     m_symbolsChanged;

    // Symbols pinned during an in-flight GetCorrelation query: a NEW-entry candidate has no open
    // position, so the prune pass must not remove it (or shift its index) before the matrix read.
    bool     m_pinQueriedSymbols;
    string   m_pinnedSymbolA;
    string   m_pinnedSymbolB;

    int      FindSymbolIndex(const string symbol) const;
    int      RegisterSymbol(const string symbol);
    void     PruneStaleSymbols();  // Batch 119: remove symbols without open positions
    void     ComputeMatrix();
    double   ComputePearson(const string symbol1, const string symbol2) const;
    double   GetCachedCorrelation(int idx1, int idx2) const;

public:
             CCorrelationEngine();
            ~CCorrelationEngine();

    // The asset-class / cross-asset thresholds are stored, logged and echoed by GetConfig only:
    // nothing in this class compares a correlation against them.
    bool     Initialize(int lookback = 30, int refreshIntervalSec = 300,
                        double conservativeFallback = 0.0,
                        double assetClassThreshold = 0.85,
                        double crossAssetThreshold = 0.7);

    // Dead public surface: Refresh, ForceRefresh, SetSymbolsChanged, IsCorrelatedCluster,
    // CountCorrelatedPositions, Reset and GetConfig have no caller outside this file.
    void     Refresh();

    void     ForceRefresh();

    void     SetSymbolsChanged(bool changed) { m_symbolsChanged = changed; }

    double   GetCorrelation(const string sym1, const string sym2);

    bool     IsCorrelatedCluster(const string symbol, double threshold = 0.7);

    int      CountCorrelatedPositions(const string symbol, double threshold = 0.7);

    void     Reset();

    string   GetConfig() const;
};

CCorrelationEngine::CCorrelationEngine() :
    m_lookback(30),
    m_refreshIntervalSec(300),
    m_conservativeFallback(0.0),
    m_assetClassThreshold(0.85),
    m_crossAssetThreshold(0.7),
    m_symbolCount(0),
    m_lastRefreshTime(0),
    m_initialized(false),
    m_symbolsChanged(false)
{
    ArrayInitialize(m_matrix, 0.0);
    for(int i = 0; i < CORR_ENGINE_MAX_SYMBOLS; i++)
        m_symbols[i] = "";
}

bool CCorrelationEngine::Initialize(int lookback, int refreshIntervalSec,
                                    double conservativeFallback,
                                    double assetClassThreshold,
                                    double crossAssetThreshold)
{
    if(lookback < 10)
        lookback = 10;
    if(lookback > 200)
        lookback = 200;
    if(refreshIntervalSec < 30)
        refreshIntervalSec = 30;

    m_lookback = lookback;
    m_refreshIntervalSec = refreshIntervalSec;
    m_conservativeFallback = MathMax(0.0, MathMin(1.0, conservativeFallback));
    m_assetClassThreshold = MathMax(0.0, MathMin(1.0, assetClassThreshold));
    m_crossAssetThreshold = MathMax(0.0, MathMin(1.0, crossAssetThreshold));
    m_symbolCount = 0;
    m_lastRefreshTime = 0;
    m_initialized = true;
    m_symbolsChanged = false;
    m_pinQueriedSymbols = false;
    m_pinnedSymbolA = "";
    m_pinnedSymbolB = "";

    ArrayInitialize(m_matrix, 0.0);
    for(int i = 0; i < CORR_ENGINE_MAX_SYMBOLS; i++)
        m_symbols[i] = "";

    PrintFormat("[CORR-ENGINE] Initialized | Lookback=%d H1 bars | Refresh=%d sec | Conservative fallback=%.1f | AssetClass=%.2f | CrossAsset=%.2f",
                m_lookback, m_refreshIntervalSec, m_conservativeFallback, m_assetClassThreshold, m_crossAssetThreshold);

    return true;
}

int CCorrelationEngine::FindSymbolIndex(const string symbol) const
{
    for(int i = 0; i < m_symbolCount; i++)
    {
        if(m_symbols[i] == symbol)
            return i;
    }
    return CORR_ENGINE_INVALID_IDX;
}

// Registry full (CORR_ENGINE_MAX_SYMBOLS) returns INVALID_IDX, which GetCorrelation answers with
// m_conservativeFallback.
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

double CCorrelationEngine::GetCachedCorrelation(int idx1, int idx2) const
{
    if(idx1 < 0 || idx1 >= m_symbolCount || idx2 < 0 || idx2 >= m_symbolCount)
        return m_conservativeFallback;

    return m_matrix[idx1 * CORR_ENGINE_MAX_SYMBOLS + idx2];
}

void CCorrelationEngine::ComputeMatrix()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0 || !PositionSelectByTicket(ticket))
            continue;
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        RegisterSymbol(posSymbol);
    }

    for(int i = 0; i < m_symbolCount; i++)
    {
        m_matrix[i * CORR_ENGINE_MAX_SYMBOLS + i] = 1.0;

        for(int j = i + 1; j < m_symbolCount; j++)
        {
            double corr = ComputePearson(m_symbols[i], m_symbols[j]);
            m_matrix[i * CORR_ENGINE_MAX_SYMBOLS + j] = corr;
            m_matrix[j * CORR_ENGINE_MAX_SYMBOLS + i] = corr; // Symmetric
        }
    }
}

void CCorrelationEngine::Refresh()
{
    if(!m_initialized)
        return;

    datetime now = TimeCurrent();
    bool timeElapsed = (m_lastRefreshTime == 0 || (now - m_lastRefreshTime) >= m_refreshIntervalSec);
    
    if(!timeElapsed && !m_symbolsChanged)
        return;

    // Pruned first so symbols with no open position do not occupy registry slots in the rebuild.
    PruneStaleSymbols();

    ComputeMatrix();
    m_lastRefreshTime = now;
    m_symbolsChanged = false; // Reset after rebuild
}

void CCorrelationEngine::PruneStaleSymbols()
{
    if(m_symbolCount <= 0)
        return;

    bool hasPosition[];
    ArrayResize(hasPosition, m_symbolCount);
    ArrayInitialize(hasPosition, false);

    for(int p = 0; p < PositionsTotal(); p++)
    {
        if(PositionSelectByTicket(PositionGetTicket(p)))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            int idx = FindSymbolIndex(posSymbol);
            if(idx != CORR_ENGINE_INVALID_IDX)
                hasPosition[idx] = true;
        }
    }

    // Drops symbols with no open position by shifting the registry left. Pinned query symbols
    // survive: a candidate being correlated has no open position yet.
    int writeIdx = 0;
    for(int i = 0; i < m_symbolCount; i++)
    {
        bool isPinned = (m_pinQueriedSymbols &&
                         (m_symbols[i] == m_pinnedSymbolA || m_symbols[i] == m_pinnedSymbolB));
        if(hasPosition[i] || isPinned)
        {
            if(writeIdx != i)
            {
                m_symbols[writeIdx] = m_symbols[i];
            }
            writeIdx++;
        }
    }

    if(writeIdx < m_symbolCount)
    {
        m_symbolCount = writeIdx;
        // Registry indices shifted: force a full rebuild on the next compute.
        m_lastRefreshTime = 0;
        m_symbolsChanged = true;
    }
}

void CCorrelationEngine::ForceRefresh()
{
    if(!m_initialized)
        return;

    ComputeMatrix();
    m_lastRefreshTime = TimeCurrent();
}

// Fail-open by construction: uninitialized engine, missing H1 history and a full registry all
// answer m_conservativeFallback, which PortfolioRiskManager wires as 0.0 (= uncorrelated).
double CCorrelationEngine::GetCorrelation(const string sym1, const string sym2)
{
    if(!m_initialized)
        return m_conservativeFallback;

    if(sym1 == sym2)
        return 1.0;

    int idx1 = RegisterSymbol(sym1);
    int idx2 = RegisterSymbol(sym2);

    if(idx1 == CORR_ENGINE_INVALID_IDX || idx2 == CORR_ENGINE_INVALID_IDX)
        return m_conservativeFallback;

    // Pinned across the refresh so PruneStaleSymbols cannot drop the candidate or shift its index.
    m_pinnedSymbolA = sym1;
    m_pinnedSymbolB = sym2;
    m_pinQueriedSymbols = true;

    datetime now = TimeCurrent();
    if(m_lastRefreshTime == 0 || (now - m_lastRefreshTime) >= m_refreshIntervalSec || m_symbolsChanged)
        Refresh();

    m_pinQueriedSymbols = false;

    // Re-resolve indices: pruning may have shifted slots
    idx1 = FindSymbolIndex(sym1);
    idx2 = FindSymbolIndex(sym2);
    if(idx1 == CORR_ENGINE_INVALID_IDX || idx2 == CORR_ENGINE_INVALID_IDX)
        return m_conservativeFallback;

    return GetCachedCorrelation(idx1, idx2);
}

string CCorrelationEngine::GetConfig() const
{
    return StringFormat("Lookback=%d | Refresh=%ds | Fallback=%.2f | AssetClass=%.2f | CrossAsset=%.2f | Symbols=%d | Initialized=%s",
                        m_lookback, m_refreshIntervalSec, m_conservativeFallback,
                        m_assetClassThreshold, m_crossAssetThreshold, m_symbolCount,
                        m_initialized ? "true" : "false");
}

bool CCorrelationEngine::IsCorrelatedCluster(const string symbol, double threshold)
{
    return (CountCorrelatedPositions(symbol, threshold) > 0);
}

// Counts other symbols' open positions only: positions on the queried symbol itself are skipped.
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

void CCorrelationEngine::Reset()
{
    m_symbolCount = 0;
    ArrayInitialize(m_matrix, 0.0);
    for(int i = 0; i < CORR_ENGINE_MAX_SYMBOLS; i++)
        m_symbols[i] = "";
    m_lastRefreshTime = 0;
}

CCorrelationEngine::~CCorrelationEngine()
{
    m_symbolCount = 0;
    ArrayInitialize(m_matrix, 0.0);
    for(int i = 0; i < CORR_ENGINE_MAX_SYMBOLS; i++)
        m_symbols[i] = "";
}

#endif // CORE_RISK_CORRELATION_ENGINE_MQH
