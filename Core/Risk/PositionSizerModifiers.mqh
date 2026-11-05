// Pluggable lot-size modifiers for CPositionSizer
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef CORE_RISK_POSITION_SIZER_MODIFIERS_MQH
#define CORE_RISK_POSITION_SIZER_MODIFIERS_MQH

#include "../../IndicatorManager.mqh"
#include "EquityCurveManager.mqh"
#include "VPINFilter.mqh"

// Each modifier adjusts the base lot size computed by CPositionSizer.
class CPositionSizerModifier
{
public:
    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) = 0;
    virtual string GetName() = 0;
    virtual bool IsEnabled() { return true; }
};

// ADX-tiered sizing, carried over from CADXPositionSizing: no trend 0x, weak 0.5x, normal 1.0x, strong 1.3x, very strong 1.5x
class CADXLotModifier : public CPositionSizerModifier
{
private:
    int    m_adxHandle;
    string m_symbol;
    int    m_adxPeriod;

    double m_noTrendThreshold;
    double m_weakThreshold;
    double m_normalThreshold;
    double m_strongThreshold;

    double m_weakMultiplier;
    double m_normalMultiplier;
    double m_strongMultiplier;
    double m_veryStrongMultiplier;

    // Floor applied to tier multipliers > 0 so a no-trend read does not block the trade
        double m_minMultiplier;           // InpAdxMinLotMultiplier
        bool   m_allowNoTrendTrading;   // InpAdxTradeOnNoTrend: false blocks the entry at 0x
        bool   m_lazyInitialized;
        bool   m_handleOwned;           // True only when the handle was created locally (iADX fallback); shared CIndicatorManager handles must never be released

        double GetADX()
    {
        if(m_adxHandle == INVALID_HANDLE) return 0.0;

        double adx[];
        ArraySetAsSeries(adx, true);
        if(CopyBuffer(m_adxHandle, 0, 0, 1, adx) <= 0)
            return 0.0;

        return adx[0];
    }

public:
    CADXLotModifier() :
        m_adxHandle(INVALID_HANDLE),
        m_symbol(""),
        m_adxPeriod(14),
        m_noTrendThreshold(20.0),
        m_weakThreshold(25.0),
        m_normalThreshold(30.0),
        m_strongThreshold(40.0),
        m_weakMultiplier(0.5),
        m_normalMultiplier(1.0),
        m_strongMultiplier(1.3),
        m_veryStrongMultiplier(1.5),
        m_minMultiplier(1.0),        // 1.0x = no adjustment, rather than blocking
        m_allowNoTrendTrading(true),
        m_lazyInitialized(false),
        m_handleOwned(false)
    {}

    ~CADXLotModifier()
    {
        if(m_adxHandle != INVALID_HANDLE && m_handleOwned)
        {
            IndicatorRelease(m_adxHandle);
        }
        m_adxHandle = INVALID_HANDLE;
        m_handleOwned = false;
    }

    bool Initialize(const string symbol, const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
                        const int adxPeriod = 14)
        {
            // Release only handles we own: those borrowed from CIndicatorManager are shared and must survive us
            if(m_adxHandle != INVALID_HANDLE && m_handleOwned)
            {
                IndicatorRelease(m_adxHandle);
            }
            m_adxHandle = INVALID_HANDLE;
            m_handleOwned = false;

            m_symbol = symbol;
            m_adxPeriod = adxPeriod;

            CIndicatorManager* indicatorManager = CIndicatorManager::Instance();
            if(indicatorManager != NULL)
            {
                m_adxHandle = indicatorManager.GetADXHandle(symbol, timeframe, adxPeriod);
                if(m_adxHandle != INVALID_HANDLE)
                    return true;   // borrowed handle: m_handleOwned stays false
            }

            m_adxHandle = iADX(symbol, timeframe, adxPeriod);
            if(m_adxHandle == INVALID_HANDLE)
            {
                Print("[ADX-MODIFIER] Failed to create ADX handle for ", symbol);
                return false;
            }
            m_handleOwned = true;

            return true;
        }

        void SetMinMultiplier(double multiplier)
        {
            m_minMultiplier = MathMax(0.0, MathMin(1.0, multiplier));
        }

        void SetAllowNoTrendTrading(bool allow)
                {
                    m_allowNoTrendTrading = allow;
                }

        // Parameterless initialize for PositionSizer compatibility (lazy init on first symbol)
        bool Initialize()
        {
            m_lazyInitialized = false;
            return true;
        }

    private:
        void EnsureADXHandle(const string symbol, const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
                             const int adxPeriod = 14)
        {
            if(!m_lazyInitialized || m_adxHandle == INVALID_HANDLE || m_symbol != symbol)
            {
                Initialize(symbol, timeframe, adxPeriod);
            }
        }

        virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
                        {
                        EnsureADXHandle(symbol);
                
                        // Symbol changed and reinit failed: pass the lot through unchanged
                        if(symbol != m_symbol)
                            return baseLot;

                        double adx = GetADX();
                        if(adx <= 0.0)
                            return baseLot; // No data — pass through unchanged

                        double multiplier = 0.0;

                        if(adx < m_noTrendThreshold)
                        {
                            if(m_allowNoTrendTrading)
                            {
                                multiplier = 1.0;
                                PrintFormat("[ADX-MODIFIER] %s | ADX=%.1f < noTrendThreshold=%.1f — no adjustment",
                                            symbol, adx, m_noTrendThreshold);
                            }
                            else
                            {
                                multiplier = 0.0;
                                PrintFormat("[ADX-MODIFIER] %s | ADX=%.1f < noTrendThreshold=%.1f | BLOCKED (0x)",
                                            symbol, adx, m_noTrendThreshold);
                            }
                        }
                        else if(adx < m_weakThreshold)
                            multiplier = m_weakMultiplier;
                        else if(adx < m_normalThreshold)
                            multiplier = m_normalMultiplier;
                        else if(adx < m_strongThreshold)
                            multiplier = m_strongMultiplier;
                        else
                            multiplier = m_veryStrongMultiplier;

                        // Above 0.50 this floor cancels the weak tier, so no ADX reading shrinks the lot.
                        if(multiplier > 0.0 && multiplier < m_minMultiplier)
                            multiplier = m_minMultiplier;

                        double adjusted = baseLot * multiplier;

                        PrintFormat("[ADX-MODIFIER] %s | ADX=%.1f | tier_mult=%.2f | lot %.2f->%.2f",
                                    symbol, adx, multiplier, baseLot, adjusted);

                        return adjusted;
                    }

    virtual string GetName() override { return "ADX"; }
};

// Estimates win rate with Beta-Binomial priors and bets a fraction of Kelly (default quarter Kelly 0.25: ~95% of
// growth with 12% DD vs 62% at full Kelly). Confidence is the prior weight: higher confidence = less prior influence.
class CBayesianKellyModifier : public CPositionSizerModifier
{
private:
    double m_alpha;           // Beta prior alpha (win count + prior)
    double m_beta;            // Beta prior beta (loss count + prior)
    double m_kellyFraction;   // Fraction of Kelly to use (0.25 = quarter Kelly)
    double m_avgWinPct;       // Average win as % of risk
    double m_avgLossPct;      // Average loss as % of risk
    int    m_totalTrades;
    int    m_wins;

    double m_priorAlpha;
    double m_priorBeta;

public:
    CBayesianKellyModifier(double kellyFraction = 0.25,
                           double priorAlpha = 2.0,
                           double priorBeta = 2.0) :
        m_alpha(priorAlpha),
        m_beta(priorBeta),
        m_kellyFraction(MathMax(0.01, MathMin(1.0, kellyFraction))),
        m_avgWinPct(1.0),
        m_avgLossPct(1.0),
        m_totalTrades(0),
        m_wins(0),
        m_priorAlpha(priorAlpha),
        m_priorBeta(priorBeta)
    {}

    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        // Warmup: one observation is enough to start adjusting
        if(m_totalTrades <= 0)
            return baseLot;

        double effectiveAlpha, effectiveBeta;
        double confidenceWeight = MathMax(0.0, MathMin(1.0, confidence));
        
        if(confidenceWeight > 0.0)
        {
            double priorWeight = 1.0 - confidenceWeight;
            effectiveAlpha = m_priorAlpha * priorWeight + m_alpha * confidenceWeight;
            effectiveBeta = m_priorBeta * priorWeight + m_beta * confidenceWeight;
        }
        else
        {
            // confidence 0 = full prior
            effectiveAlpha = m_priorAlpha;
            effectiveBeta = m_priorBeta;
        }

        // Posterior mean win rate
        double W = effectiveAlpha / (effectiveAlpha + effectiveBeta);

        double R = (m_avgLossPct > 0.0) ? m_avgWinPct / m_avgLossPct : 1.0;

        // Kelly criterion: K = W - (1-W)/R
        double K = W - ((1.0 - W) / R);

        // Clamp K to [0, 1] — never go above full Kelly
        K = MathMax(0.0, MathMin(1.0, K));

        double kellyLot;
        if(K <= 0.0)
        {
            // Kelly says don't bet — reduce to half
            kellyLot = baseLot * 0.5;
            PrintFormat("[KELLY-ADJUSTMENT] WR=%.2f K=%.2f fraction=%.2f lot_adj=0.50x (Kelly<=0, reduce to half) | conf=%.2f",
                        W, K, m_kellyFraction, confidence);
        }
        else
        {
            double fractionK = K * m_kellyFraction;
            kellyLot = baseLot * fractionK;
            PrintFormat("[KELLY-ADJUSTMENT] WR=%.2f K=%.2f fraction=%.2f lot_adj=%.2fx | conf=%.2f",
                        W, K, m_kellyFraction, fractionK, confidence);
        }

        return kellyLot;
    }

    virtual string GetName() override { return "BayesianKelly"; }

    // Update with trade result — call after each closed trade
    void UpdateTradeResult(bool isWin, double profitPct, double lossPct)
    {
        m_totalTrades++;

        if(isWin)
        {
            m_wins++;
            m_alpha += 1.0;
            if(profitPct > 0.0)
            {
                m_avgWinPct = ((m_avgWinPct * (m_wins - 1)) + profitPct) / m_wins;
            }
        }
        else
        {
            m_beta += 1.0;
            if(lossPct > 0.0)
            {
                int losses = m_totalTrades - m_wins;
                m_avgLossPct = ((m_avgLossPct * (losses - 1)) + lossPct) / losses;
            }
        }
    }

    // Effective Kelly fraction currently in force (K * m_kellyFraction)
    double GetCurrentKellyFraction() const
    {
        if(m_totalTrades <= 0)
            return 0.0;
        double W = m_alpha / (m_alpha + m_beta);
        double R = (m_avgLossPct > 0.0) ? m_avgWinPct / m_avgLossPct : 1.0;
        double K = W - ((1.0 - W) / R);
        K = MathMax(0.0, MathMin(1.0, K));
        return K * m_kellyFraction;
    }

    // Get estimated Bayesian win rate (posterior mean)
    double GetEstimatedWinRate() const
    {
        if(m_totalTrades <= 0)
            return 0.5;  // Prior mean with default alpha=beta=2
        return m_alpha / (m_alpha + m_beta);
    }
};

// Scales the lot by equity vs the curve EMA (below EMA -> reductionFactor). Per-strategy curves, default manager as fallback.
class CEquityCurveLotModifier : public CPositionSizerModifier
{
private:
    struct SStrategyEquityCurve
    {
        string strategyName;
        CEquityCurveManager* manager;
        bool ownsManager; // Whether we own the manager (need to delete)
        
        SStrategyEquityCurve() : strategyName(""), manager(NULL), ownsManager(false) {}
        SStrategyEquityCurve(const string name, CEquityCurveManager* mgr, bool own = false) 
            : strategyName(name), manager(mgr), ownsManager(own) {}
        ~SStrategyEquityCurve() { if(ownsManager && manager != NULL) delete manager; }
    };
    
    SStrategyEquityCurve m_strategyCurves[];
    int m_curveCount;
    
    // Default equity curve manager (fallback for unknown strategies)
    CEquityCurveManager* m_defaultManager;
    bool m_ownsDefaultManager;

    CEquityCurveManager* FindStrategyCurve(const string strategyName) const
    {
        for(int i = 0; i < m_curveCount; i++)
        {
            if(m_strategyCurves[i].strategyName == strategyName)
                return m_strategyCurves[i].manager;
        }
        return NULL;
    }

public:
    CEquityCurveLotModifier() : 
        m_curveCount(0),
        m_defaultManager(NULL),
        m_ownsDefaultManager(false)
    {}

    // Injects an existing manager; ownership is not taken by this ctor
    CEquityCurveLotModifier(CEquityCurveManager* ecm) : 
        m_curveCount(0),
        m_defaultManager(ecm),
        m_ownsDefaultManager(false)
    {}

    bool Initialize(int lookback = 100)
    {
        if(m_defaultManager == NULL)
        {
            m_defaultManager = new CEquityCurveManager(lookback);
            m_ownsDefaultManager = true;
        }
        return (m_defaultManager != NULL);
    }

    ~CEquityCurveLotModifier()
    {
        for(int i = 0; i < m_curveCount; i++)
        {
            if(m_strategyCurves[i].ownsManager && m_strategyCurves[i].manager != NULL)
            {
                delete m_strategyCurves[i].manager;
            }
        }
        if(m_ownsDefaultManager && m_defaultManager != NULL)
        {
            delete m_defaultManager;
        }
    }

    void AddStrategyEquityCurve(const string strategyName, CEquityCurveManager* manager, bool own = false)
    {
        for(int i = 0; i < m_curveCount; i++)
        {
            if(m_strategyCurves[i].strategyName == strategyName)
            {
                if(m_strategyCurves[i].ownsManager && m_strategyCurves[i].manager != NULL)
                    delete m_strategyCurves[i].manager;
                m_strategyCurves[i].manager = manager;
                m_strategyCurves[i].ownsManager = own;
                PrintFormat("[EQUITY-CURVE-MODIFIER] Updated strategy equity curve | %s", strategyName);
                return;
            }
        }
        
        int newSize = m_curveCount + 1;
        ArrayResize(m_strategyCurves, newSize);
        m_strategyCurves[m_curveCount] = SStrategyEquityCurve(strategyName, manager, own);
        m_curveCount++;
        PrintFormat("[EQUITY-CURVE-MODIFIER] Added strategy equity curve | %s", strategyName);
    }

    void SetDefaultManager(CEquityCurveManager* manager, bool own = false)
    {
        if(m_ownsDefaultManager && m_defaultManager != NULL)
            delete m_defaultManager;
        m_defaultManager = manager;
        m_ownsDefaultManager = own;
    }

    void UpdateStrategyEquity(const string strategyName, double equityValue)
    {
        CEquityCurveManager* curve = FindStrategyCurve(strategyName);
        if(curve != NULL)
        {
            curve.Update(equityValue);
            return;
        }
        if(m_defaultManager != NULL)
            m_defaultManager.Update(equityValue);
    }

    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        // AdjustLotSize only receives a symbol, so the strategy curve is inferred, never passed in
        CEquityCurveManager* curve = m_defaultManager;
        
        // Heuristic: strategy name matched as a substring of the symbol
        for(int i = 0; i < m_curveCount; i++)
        {
            if(StringFind(symbol, m_strategyCurves[i].strategyName) >= 0)
            {
                curve = m_strategyCurves[i].manager;
                break;
            }
        }
        
        if(curve == NULL)
            return baseLot;

        double multiplier = curve.GetPositionSizeMultiplier();
        if(MathAbs(multiplier - 1.0) < 0.001)
            return baseLot;

        double adjusted = baseLot * multiplier;
        PrintFormat("[EQUITY-CURVE-MODIFIER] %s | multiplier=%.2f | lot %.2f->%.2f",
                    symbol, multiplier, baseLot, adjusted);
        return adjusted;
    }

    virtual string GetName() override { return "EquityCurve"; }
};

// Targets a fixed annualized volatility, estimated from daily ATR
class CVolatilityTargetingModifier : public CPositionSizerModifier
{
private:
    double m_volatilityTarget;      // Target annualized volatility (e.g., 0.15 = 15%)
    int    m_volatilityLookback;
    int    m_atrHandle;
    string m_atrSymbol;
    int    m_atrPeriod;
    
    double GetATRVolatility(const string symbol)
    {
        if(m_atrHandle == INVALID_HANDLE || m_atrSymbol != symbol)
        {
            if(m_atrHandle != INVALID_HANDLE)
            {
                IndicatorRelease(m_atrHandle);
                m_atrHandle = INVALID_HANDLE;
            }
            // Anchor to D1: the annualization below reads avgATR/price as a DAILY volatility, so PERIOD_CURRENT
            // would make the lot size depend on whatever chart timeframe the EA runs on
            m_atrHandle = iATR(symbol, PERIOD_D1, m_atrPeriod);
            m_atrSymbol = symbol;
            if(m_atrHandle == INVALID_HANDLE)
                return 0.0;
        }
        
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(m_atrHandle, 0, 0, m_volatilityLookback, atr) <= 0)
            return 0.0;
        
        double sumATR = 0.0;
        int count = MathMin(m_volatilityLookback, ArraySize(atr));
        for(int i = 0; i < count; i++)
            sumATR += atr[i];
        double avgATR = sumATR / count;
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return 0.0;
        
        double dailyVol = avgATR / price;
        double annualVol = dailyVol * MathSqrt(252.0);
        
        return annualVol;
    }

public:
    CVolatilityTargetingModifier() :
        m_volatilityTarget(0.15),
        m_volatilityLookback(252),
        m_atrHandle(INVALID_HANDLE),
        m_atrSymbol(""),
        m_atrPeriod(14)
    {}

    ~CVolatilityTargetingModifier()
    {
        if(m_atrHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
        }
    }

    bool Initialize(double volatilityTarget = 0.15, int volatilityLookback = 252)
    {
        m_volatilityTarget = MathMax(0.01, MathMin(1.0, volatilityTarget));
        m_volatilityLookback = MathMax(10, MathMin(500, volatilityLookback));
        return true;
    }

    void SetTargetVolatility(double target)
    {
        m_volatilityTarget = MathMax(0.01, MathMin(1.0, target));
    }

    void SetLookback(int lookback)
    {
        m_volatilityLookback = MathMax(10, MathMin(500, lookback));
    }

    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        double currentVol = GetATRVolatility(symbol);
        if(currentVol <= 0.0)
            return baseLot; // No data, pass through unchanged
        
        double volRatio = m_volatilityTarget / currentVol;
        
        // Vol ratio clamped to 0.25x-2.0x
        volRatio = MathMax(0.25, MathMin(2.0, volRatio));
        
        double adjusted = baseLot * volRatio;
        
        PrintFormat("[VOL-TARGET-MODIFIER] %s | currentVol=%.4f | target=%.4f | ratio=%.2f | lot %.2f->%.2f",
                    symbol, currentVol, m_volatilityTarget, volRatio, baseLot, adjusted);
        
        return adjusted;
    }

    virtual string GetName() override { return "VolatilityTarget"; }
};

// Scales the lot by CVPINFilter toxicity; classification mode and bucket-overflow carry live inside the filter.
// The filters belong to the math hub, which is the only thing that feeds a CVPINFilter ticks. A filter
// created here would sit at zero completed buckets forever, so IsWarmedUp() would never turn true and the
// toxicity shrink would never apply.
class CVPINLotModifier : public CPositionSizerModifier
{
private:
    string       m_filterSymbols[];
    CVPINFilter* m_filters[];
    string       m_noFilterLogged;

    CVPINFilter* FilterFor(const string symbol)
    {
        for(int i = 0; i < ArraySize(m_filterSymbols); i++)
            if(m_filterSymbols[i] == symbol)
                return m_filters[i];
        return NULL;
    }

public:
    CVPINLotModifier() : m_noFilterLogged("") {}

    // The hub keeps ownership; this class holds references only.
    void RegisterFilter(const string symbol, CVPINFilter* filter)
    {
        if(symbol == "" || filter == NULL)
            return;
        for(int i = 0; i < ArraySize(m_filterSymbols); i++)
        {
            if(m_filterSymbols[i] == symbol)
            {
                m_filters[i] = filter;
                return;
            }
        }
        const int n = ArraySize(m_filterSymbols);
        if(ArrayResize(m_filterSymbols, n + 1) != n + 1 || ArrayResize(m_filters, n + 1) != n + 1)
        {
            PrintFormat("[VPIN-MODIFIER] filter table resize failed at %d entries - toxicity sizing stays off for %s",
                        n, symbol);
            return;
        }
        m_filterSymbols[n] = symbol;
        m_filters[n] = filter;
    }

    int FilterCount() const { return ArraySize(m_filterSymbols); }

    // Parameterless Initialize() for the PositionSizer contract
    bool Initialize()
    {
        ArrayResize(m_filterSymbols, 0);
        ArrayResize(m_filters, 0);
        m_noFilterLogged = "";
        return true;
    }

    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        CVPINFilter* filter = FilterFor(symbol);
        if(filter == NULL)
        {
            if(m_noFilterLogged != symbol)
            {
                m_noFilterLogged = symbol;
                PrintFormat("[VPIN-MODIFIER] %s | no hub VPIN filter registered | lot unchanged (%.4f)", symbol, baseLot);
            }
            return baseLot;
        }

        // Not warmed up: lot unchanged
        if(!filter.IsWarmedUp())
            return baseLot;

        double multiplier = filter.GetPositionSizeMultiplier();

        // Confidence blends the multiplier toward 1.0; clamped 0.10-1.00, so VPIN can only shrink the lot
        double effectiveMultiplier = 1.0 + (multiplier - 1.0) * confidence;
        effectiveMultiplier = MathMax(0.1, MathMin(1.0, effectiveMultiplier));

        double adjusted = baseLot * effectiveMultiplier;

        PrintFormat("[VPIN-MODIFIER] %s | VPIN=%.4f | mult=%.2f | conf=%.2f | lot %.2f->%.2f",
                    symbol, filter.GetVPIN(), multiplier, confidence, baseLot, adjusted);

        return adjusted;
    }

    virtual string GetName() override { return "VPIN"; }
};


#endif // CORE_RISK_POSITION_SIZER_MODIFIERS_MQH
