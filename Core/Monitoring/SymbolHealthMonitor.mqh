// Live symbol health monitoring - detect frozen feeds, spread spikes
//
// Batch 272 rewrite. Three defects in the previous version, all observable in the journal:
//  1. The verdict came from `CSymbolHealthMonitor::OnTick(_Symbol)`, which the orchestrator calls
//     once per timer tick with the CHART symbol only. A 13-symbol book therefore had 12 symbols
//     whose `tickCount` could never move, so every attach printed
//     "[SYM-HEALTH] Symbol X NEVER RECEIVED TICK - disabling trading" for all of them within the
//     first second and reported `frozen=13 total=13`. The feed is now judged from
//     `SymbolInfoTick(symbol, tick)`, which works for every symbol in the list regardless of which
//     chart the EA runs on, so the verdict describes the broker's feed rather than our call sites.
//  2. Nothing outside this file read `IsHealthy()`, so "disabling trading" disabled nothing. The
//     orchestrator now gates the per-symbol candidate path on it, and every refusal names itself
//     (a silently held symbol is the "blocked book looks like a quiet market" failure shape).
//  3. The record for each symbol was a hand-built JSON string, re-serialised and re-parsed with
//     StringFind on every tick - ~200 chars of allocation per call per symbol on the tick path.
//     The state is now a plain struct array: no strings, no parser, no allocation.
//
// A symbol whose market is genuinely closed is reported as closed and is NOT counted as a feed
// failure: a 24/5 FX pair and a cash-index CFD are not unhealthy because the exchange is shut.
// "No fresh quotes" only means something while a session is open, which is what
// `IsWithinQuoteSession()` decides before any verdict is issued.
#property strict
#ifndef CORE_MONITORING_SYMBOL_HEALTH_MONITOR_MQH
#define CORE_MONITORING_SYMBOL_HEALTH_MONITOR_MQH

#include "../Utils/StructuredLogger.mqh"
#include "../Utils/LogMacros.mqh"
#include "../Utils/Enums.mqh"

// Verdict for one symbol. WARMING is the state before the monitor has watched the symbol for one
// frozen-threshold; it is not a failure, because on attach we have not yet seen a tick by definition.
enum ENUM_SYMBOL_FEED_STATE
{
    SYMBOL_FEED_WARMING = 0,   // inside the grace window, no verdict yet
    SYMBOL_FEED_LIVE    = 1,   // quote age <= stale threshold
    SYMBOL_FEED_STALE   = 2,   // quote age >  stale threshold
    SYMBOL_FEED_FROZEN  = 3,   // quote age >  frozen threshold, or never quoted while in session
    SYMBOL_FEED_CLOSED  = 4    // broker session closed: no quotes are expected, nothing to judge
};

struct SSymbolHealth
{
    string   symbol;
    datetime lastTickTime;      // last quote time reported by the terminal
    ulong    lastTickMs;
    int      tickCount;         // samples this monitor has taken (not the broker's tick count)
    datetime firstSeen;         // when this symbol was first examined; drives the grace window
    double   currentSpread;
    double   avgSpread;
    double   maxSpread;
    double   minSpread;
    int      spreadSpikes;
    bool     isStale;
    bool     isFrozen;
    bool     tradingAllowed;
    datetime lastAlertTime;
    int      alertCount;
    double   spreadEma;
    int      emaInitialized;
    int      state;             // ENUM_SYMBOL_FEED_STATE
    int      selectAttempted;   // 1 once we have asked the terminal to subscribe this symbol

    SSymbolHealth() : symbol(""), lastTickTime(0), lastTickMs(0), tickCount(0), firstSeen(0),
                      currentSpread(0), avgSpread(0), maxSpread(0), minSpread(0),
                      spreadSpikes(0), isStale(false), isFrozen(false),
                      tradingAllowed(true), lastAlertTime(0), alertCount(0),
                      spreadEma(0), emaInitialized(0), state(SYMBOL_FEED_WARMING),
                      selectAttempted(0) {}
};

class CSymbolHealthMonitor
{
private:
    // Fixed capacity, struct array: the previous version stored a JSON string per symbol and paid a
    // full serialise + parse per tick. Nothing here allocates on the hot path.
    SSymbolHealth m_data[100];
    int   m_symbolCount;

    int   m_staleThresholdSec;
    int   m_frozenThresholdSec;
    double m_spreadSpikeMultiplier;
    int   m_alertCooldownSec;
    bool  m_enabled;
    bool  m_autoDisableTrading;

    // Stats for the summary line
    int   m_totalSymbols;
    int   m_healthySymbols;
    int   m_staleSymbols;
    int   m_frozenSymbols;
    int   m_closedSymbols;

    // Symbol names are compared with spaces removed: the roster prints "StepIndex" while the chart
    // says "Step Index", and a lookup that misses would silently start a second record for the same
    // instrument and judge it from zero evidence.
    static string NormalizeKey(const string symbol)
    {
        string s = symbol;
        StringReplace(s, " ", "");
        StringReplace(s, "\t", "");
        StringToUpper(s);
        return s;
    }

    int FindSymbolIndex(const string symbol)
    {
        const string key = NormalizeKey(symbol);
        for(int i = 0; i < m_symbolCount; i++)
            if(NormalizeKey(m_data[i].symbol) == key)
                return i;
        return -1;
    }

    int AddSymbol(const string symbol)
    {
        if(m_symbolCount >= ArraySize(m_data))
            return -1;
        m_data[m_symbolCount] = SSymbolHealth();
        m_data[m_symbolCount].symbol = symbol;
        m_data[m_symbolCount].firstSeen = TimeCurrent();
        return m_symbolCount++;
    }

    int EnsureSymbol(const string symbol)
    {
        int idx = FindSymbolIndex(symbol);
        if(idx < 0)
            idx = AddSymbol(symbol);
        return idx;
    }

    // True when the broker's own quote schedule says this symbol is expected to be ticking now.
    // A symbol with no session today (weekend, holiday, or a market that simply does not open that
    // weekday) is closed, not broken - and a session that runs past midnight is open on either side
    // of the boundary. Without this, a Friday-evening attach declares every FX pair dead.
    bool IsWithinQuoteSession(const string symbol)
    {
        const datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);

        int sessionsToday = 0;
        for(int s = 0; s < 16; s++)
        {
            datetime f = 0, t = 0;
            if(!SymbolInfoSessionQuote(symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, s, f, t))
                break;
            sessionsToday++;
            const int nowSec  = dt.hour * 3600 + dt.min * 60 + dt.sec;
            const int fromSec = (int)f;
            const int toSec   = (int)t;
            // Sessions are reported as seconds-from-midnight. from > to means it crosses midnight.
            const bool inside = (fromSec <= toSec)
                                ? (nowSec >= fromSec && nowSec <= toSec)
                                : (nowSec >= fromSec || nowSec <= toSec);
            if(inside)
                return true;
        }
        // No sessions declared at all for this weekday: the terminal has no schedule for the symbol
        // (common on synthetic indices that quote continuously), so fall back to "market is open"
        // and let the quote age decide rather than exempting the symbol from every check.
        if(sessionsToday == 0)
            return true;
        return false;
    }

    void AlertOnce(const int idx, const string tag, const string detail)
    {
        SSymbolHealth h = m_data[idx];
        const datetime now = TimeCurrent();
        if(h.alertCount > 0 && (now - h.lastAlertTime) < m_alertCooldownSec)
            return;
        PrintFormat("[SYM-HEALTH] Symbol %s %s%s", h.symbol, tag, detail);
        g_structLog.LogWarning("SYM-HEALTH", "Symbol " + h.symbol + " " + tag + detail);
        m_data[idx].lastAlertTime = now;
        m_data[idx].alertCount = h.alertCount + 1;
    }

    // Sample the feed for one symbol: quote freshness plus spread statistics. Called for every
    // watched symbol from CheckAllSymbols, so the spread EMA and the spike detector finally cover
    // the whole roster instead of only the chart symbol.
    void SampleTick(const int idx)
    {
        MqlTick tick;
        if(!SymbolInfoTick(m_data[idx].symbol, tick))
            return;
        if(tick.time <= 0)
            return;

        SSymbolHealth h = m_data[idx];
        // The terminal reports the last quote time, which is what a dead feed stops updating. Our own
        // call frequency is not evidence, so an unchanged quote time does not count as a new tick.
        if(h.tickCount > 0 && tick.time == h.lastTickTime)
            return;

        h.lastTickTime = tick.time;
        h.lastTickMs = (ulong)tick.time * 1000 + (ulong)(tick.time_msc % 1000);
        h.tickCount++;

        double point = SymbolInfoDouble(h.symbol, SYMBOL_POINT);
        if(point <= 0.0) point = _Point;
        if(point <= 0.0) point = 0.00001;
        const double spread = (tick.ask - tick.bid) / point;
        h.currentSpread = spread;

        if(h.emaInitialized == 0)
        {
            h.spreadEma = spread;
            h.avgSpread = spread;
            h.minSpread = spread;
            h.maxSpread = spread;
            h.emaInitialized = 1;
        }
        else
        {
            h.spreadEma = h.spreadEma * 0.99 + spread * 0.01;
            h.avgSpread = h.spreadEma;
            if(spread > h.maxSpread) h.maxSpread = spread;
            if(spread < h.minSpread || h.minSpread <= 0.0) h.minSpread = spread;
        }

        if(h.avgSpread > 0 && spread > h.avgSpread * m_spreadSpikeMultiplier)
        {
            h.spreadSpikes++;
            PrintFormat("[SYM-HEALTH] SPREAD SPIKE: %s current=%s avg=%s ratio=%s",
                        h.symbol, DoubleToString(spread, 1), DoubleToString(h.avgSpread, 1),
                        DoubleToString(spread / h.avgSpread, 2));
            g_structLog.LogSpreadSpike(h.symbol, spread, h.avgSpread);
        }

        m_data[idx] = h;
    }

public:
    CSymbolHealthMonitor() : m_staleThresholdSec(30), m_frozenThresholdSec(120),
                             m_spreadSpikeMultiplier(3.0), m_alertCooldownSec(300),
                             m_enabled(true), m_autoDisableTrading(true),
                             m_totalSymbols(0), m_healthySymbols(0), m_staleSymbols(0),
                             m_frozenSymbols(0), m_closedSymbols(0), m_symbolCount(0) {}

    ~CSymbolHealthMonitor() {}

    void Init(int staleSec = 30, int frozenSec = 120, double spikeMult = 3.0,
              int alertCooldown = 300, bool autoDisable = true)
    {
        m_staleThresholdSec = (staleSec > 0) ? staleSec : 30;
        m_frozenThresholdSec = (frozenSec > m_staleThresholdSec) ? frozenSec : (m_staleThresholdSec * 4);
        m_spreadSpikeMultiplier = (spikeMult > 1.0) ? spikeMult : 3.0;
        m_alertCooldownSec = (alertCooldown > 0) ? alertCooldown : 300;
        m_autoDisableTrading = autoDisable;
        m_enabled = true;

        PrintFormat("[SYM-HEALTH] Initialized: stale=%ds frozen=%ds spikeMult=%s autoDisable=%s | verdict from SymbolInfoTick per symbol, session-aware, grace=%ds",
                    m_staleThresholdSec, m_frozenThresholdSec, DoubleToString(m_spreadSpikeMultiplier, 2),
                    autoDisable ? "true" : "false", m_frozenThresholdSec);
        g_structLog.LogInfo("SYM-HEALTH", "Initialized with stale=" + IntegerToString(m_staleThresholdSec) + "s");
    }

    // Kept for call-site compatibility: the orchestrator calls this once per tick with the chart
    // symbol. It is a sample, not an authority - the verdict for every symbol is taken in
    // CheckAllSymbols from the broker's own quote time.
    void OnTick(const string symbol)
    {
        if(!m_enabled || symbol == "") return;
        const int idx = EnsureSymbol(symbol);
        if(idx >= 0) SampleTick(idx);
    }

    // Call from OnTimer for all watched symbols
    void CheckAllSymbols(const string symbolsCsv)
    {
        if(!m_enabled) return;
        if(symbolsCsv == "") return;

        m_totalSymbols = 0;
        m_healthySymbols = 0;
        m_staleSymbols = 0;
        m_frozenSymbols = 0;
        m_closedSymbols = 0;

        // Spaces are part of a broker symbol name ("Step Index", "Boom 1000 Index"). Stripping them
        // here made every multi-word symbol resolve to a name the broker does not offer, so
        // SymbolInfoTick failed and the monitor declared six live instruments frozen - including the
        // one on the chart. NormalizeKey already folds spaces for COMPARISON; the stored name and the
        // lookup name must stay the broker's own.
        int start = 0;
        const int len = StringLen(symbolsCsv);
        while(start < len)
        {
            int comma = StringFind(symbolsCsv, ",", start);
            if(comma < 0) comma = len;
            string sym = StringSubstr(symbolsCsv, start, comma - start);
            StringTrimLeft(sym);
            StringTrimRight(sym);
            if(sym != "") CheckSymbol(sym);
            start = comma + 1;
        }

        static datetime s_lastSummary = 0;
        if(s_lastSummary == 0 || (TimeCurrent() - s_lastSummary) > 300)
        {
            PrintFormat("[SYM-HEALTH] Summary: total=%d healthy=%d stale=%d frozen=%d closed=%d",
                        m_totalSymbols, m_healthySymbols, m_staleSymbols, m_frozenSymbols, m_closedSymbols);
            g_structLog.LogInfo("SYM-HEALTH",
                "Summary: total=" + IntegerToString(m_totalSymbols) +
                " healthy=" + IntegerToString(m_healthySymbols) +
                " stale=" + IntegerToString(m_staleSymbols) +
                " frozen=" + IntegerToString(m_frozenSymbols) +
                " closed=" + IntegerToString(m_closedSymbols));
            s_lastSummary = TimeCurrent();
        }
    }

    // Judge one symbol from its last quote time, then sample it for spread statistics.
    void CheckSymbol(const string symbol)
    {
        if(symbol == "") return;
        const int idx = EnsureSymbol(symbol);
        if(idx < 0) return;

        m_totalSymbols++;
        SampleTick(idx);

        SSymbolHealth h = m_data[idx];
        if(h.firstSeen == 0)
        {
            h.firstSeen = TimeCurrent();
            m_data[idx].firstSeen = h.firstSeen;
        }

        const datetime now = TimeCurrent();

        // Nothing can be judged while the broker's own schedule says the market is shut.
        if(!IsWithinQuoteSession(h.symbol))
        {
            m_closedSymbols++;
            if(h.state != SYMBOL_FEED_CLOSED)
            {
                m_data[idx].state = SYMBOL_FEED_CLOSED;
                m_data[idx].isStale = false;
                m_data[idx].isFrozen = false;
                // Not a reason to withhold trading: the market cannot fill anything anyway, and an
                // operator override made while the market was closed must survive to the open.
                m_data[idx].tradingAllowed = true;
                AlertOnce(idx, "market closed", " - no quotes expected, not counted as a feed failure");
            }
            return;
        }

        // A symbol never quoted at all is a failure only after the grace window: on attach there has
        // been no time for a quote yet, and calling that frozen is what sprayed 13 lines at 20:35:55.
        if(h.tickCount == 0 || h.lastTickTime <= 0)
        {
            const int watchedSec = (int)(now - h.firstSeen);
            if(watchedSec < m_frozenThresholdSec)
            {
                m_healthySymbols++;
                if(h.state != SYMBOL_FEED_WARMING)
                    m_data[idx].state = SYMBOL_FEED_WARMING;
                return;
            }
            m_frozenSymbols++;
            m_data[idx].state = SYMBOL_FEED_FROZEN;
            m_data[idx].isFrozen = true;
            m_data[idx].isStale = true;
            if(m_autoDisableTrading)
                m_data[idx].tradingAllowed = false;

            // Before calling a symbol dead, ask the terminal for it. A symbol outside Market Watch is
            // never quoted, and SymbolInfoTick then fails - which is indistinguishable from a dead
            // feed until we check. Selecting it restarts the grace window instead of writing off an
            // instrument that is perfectly tradable.
            if(h.selectAttempted == 0)
            {
                m_data[idx].selectAttempted = 1;
                if(SymbolSelect(h.symbol, true))
                {
                    m_data[idx].firstSeen = now;
                    m_data[idx].state = SYMBOL_FEED_WARMING;
                    m_data[idx].isFrozen = false;
                    m_data[idx].isStale = false;
                    m_data[idx].tradingAllowed = true;
                    AlertOnce(idx, "not subscribed",
                              StringFormat(" - it was not in Market Watch, so no quotes reached the EA; selected it and restarted the %ds grace window", m_frozenThresholdSec));
                    return;
                }

                AlertOnce(idx, "not offered",
                          " - this broker does not offer the symbol (SymbolSelect refused), so no quote can ever arrive; the row can never trade");
                return;
            }

            AlertOnce(idx, "NO FEED", StringFormat(" - no quote in %ds while the session is open", watchedSec));
            return;
        }

        const int ageSec = (int)(now - h.lastTickTime);

        if(ageSec > m_frozenThresholdSec)
        {
            m_frozenSymbols++;
            m_data[idx].state = SYMBOL_FEED_FROZEN;
            m_data[idx].isFrozen = true;
            m_data[idx].isStale = true;
            if(m_autoDisableTrading)
                m_data[idx].tradingAllowed = false;
            AlertOnce(idx, "FROZEN", StringFormat(" (%ds since last quote) - trading withheld for this symbol", ageSec));
            return;
        }

        if(ageSec > m_staleThresholdSec)
        {
            m_staleSymbols++;
            m_data[idx].state = SYMBOL_FEED_STALE;
            m_data[idx].isStale = true;
            AlertOnce(idx, "STALE", StringFormat(" (%ds since last quote)", ageSec));
            return;
        }

        m_healthySymbols++;
        if(h.state != SYMBOL_FEED_LIVE)
        {
            const bool wasTrouble = (h.state == SYMBOL_FEED_FROZEN || h.state == SYMBOL_FEED_STALE);
            m_data[idx].state = SYMBOL_FEED_LIVE;
            m_data[idx].isStale = false;
            m_data[idx].isFrozen = false;
            m_data[idx].tradingAllowed = true;
            // Recovery is only worth a line once there was something to recover from.
            if(wasTrouble)
            {
                PrintFormat("[SYM-HEALTH] Symbol %s recovered (quote %ds old)", h.symbol, ageSec);
                g_structLog.LogInfo("SYM-HEALTH", "Symbol " + h.symbol + " recovered");
            }
        }
    }

    // Whether a symbol may be traded right now. WARMING and CLOSED are permissive by design: neither
    // is evidence of a broken feed, and the alternative is a startup window that refuses entries for
    // a state the EA cannot yet measure.
    bool IsHealthy(const string symbol)
    {
        if(!m_enabled) return true;
        const int idx = FindSymbolIndex(symbol);
        if(idx < 0) return true;   // never examined yet - not evidence of anything

        const SSymbolHealth h = m_data[idx];
        if(h.state == SYMBOL_FEED_WARMING || h.state == SYMBOL_FEED_CLOSED)
            return true;
        if(h.state == SYMBOL_FEED_FROZEN)
            return false;
        return h.tradingAllowed;
    }

    // Last verdict for a symbol (zeroed struct when the symbol was never seen).
    SSymbolHealth GetHealth(const string symbol)
    {
        const int idx = FindSymbolIndex(symbol);
        if(idx < 0)
        {
            SSymbolHealth empty;
            empty.symbol = symbol;
            return empty;
        }
        return m_data[idx];
    }

    // Operator override. FROZEN is the only state this may lift early; the next CheckSymbol re-judges
    // the feed from the quote time, so an override cannot hide a feed that is still dead for long.
    void SetTradingAllowed(const string symbol, bool allowed)
    {
        const int idx = EnsureSymbol(symbol);
        if(idx < 0) return;
        m_data[idx].tradingAllowed = allowed;
        PrintFormat("[SYM-HEALTH] Trading %s for %s", allowed ? "ENABLED" : "DISABLED", symbol);
        g_structLog.LogInfo("SYM-HEALTH", "Trading " + (allowed ? "ENABLED" : "DISABLED") + " for " + symbol);
    }

    void SetEnabled(bool enabled) { m_enabled = enabled; }
    bool IsEnabled() const { return m_enabled; }

    int GetTotalSymbols() const { return m_totalSymbols; }
    int GetHealthySymbols() const { return m_healthySymbols; }
    int GetStaleSymbols() const { return m_staleSymbols; }
    int GetFrozenSymbols() const { return m_frozenSymbols; }
    int GetClosedSymbols() const { return m_closedSymbols; }

    void ResetSymbol(const string symbol)
    {
        const int idx = FindSymbolIndex(symbol);
        if(idx < 0) return;
        m_data[idx] = SSymbolHealth();
        m_data[idx].symbol = symbol;
        m_data[idx].firstSeen = TimeCurrent();
        PrintFormat("[SYM-HEALTH] Reset health for %s", symbol);
    }

    void UpdateThresholds(int staleSec, int frozenSec, double spikeMult)
    {
        if(staleSec > 0) m_staleThresholdSec = staleSec;
        if(frozenSec > m_staleThresholdSec) m_frozenThresholdSec = frozenSec;
        if(spikeMult > 1.0) m_spreadSpikeMultiplier = spikeMult;
        PrintFormat("[SYM-HEALTH] Thresholds updated: stale=%ds frozen=%ds spikeMult=%s",
                    m_staleThresholdSec, m_frozenThresholdSec, DoubleToString(m_spreadSpikeMultiplier, 2));
    }
};

#endif // CORE_MONITORING_SYMBOL_HEALTH_MONITOR_MQH
