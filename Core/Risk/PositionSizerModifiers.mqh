// Pluggable lot-size modifiers for CPositionSizer
// Phase 5: Position Sizer Consolidation
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef CORE_RISK_POSITION_SIZER_MODIFIERS_MQH
#define CORE_RISK_POSITION_SIZER_MODIFIERS_MQH

#include "../../IndicatorManager.mqh"
#include "EquityCurveManager.mqh"
#include "VPINFilter.mqh"

// Abstract modifier interface
// Strategy-specific sizers become parameter providers rather than
// independent calculators. Each modifier adjusts the base lot size
// computed by CPositionSizer.
class CPositionSizerModifier
{
public:
    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) = 0;
    virtual string GetName() = 0;
    virtual bool IsEnabled() { return true; }
};

// Wraps the ADX-tiered logic from CADXPositionSizing.
// Gets ADX value, applies multiplier:
// 0x no trend, 0.5x weak, 1.0x normal, 1.3x strong, 1.5x very
class CADXLotModifier : public CPositionSizerModifier
{
private:
    int    m_adxHandle;
    string m_symbol;
    int    m_adxPeriod;

    // Thresholds (matching CADXPositionSizing defaults)
    double m_noTrendThreshold;      // Below this = no trend
    double m_weakThreshold;         // Weak trend threshold
    double m_normalThreshold;       // Normal trend threshold
    double m_strongThreshold;       // Strong trend threshold

    double m_weakMultiplier;        // 0.5x for weak trends
    double m_normalMultiplier;      // 1.0x for normal trends
    double m_strongMultiplier;      // 1.3x for strong trends
    double m_veryStrongMultiplier;

    // L5-011/L5-008: Minimum multiplier when no trend (prevents 0x blocking trades)
        double m_minMultiplier;
        bool   m_allowNoTrendTrading;   // If false, returns 0 for no trend (blocks trade)
        bool   m_lazyInitialized;       // Track lazy initialization state
        bool   m_handleOwned;           // Batch 152 (M-16): true only when handle was created locally (iADX fallback); shared CIndicatorManager handles must never be released

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
        m_minMultiplier(1.0),        // L5-008: Default 1.0x (no adjustment) instead of blocking
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
            // Release previous handle only if we own it (Batch 152 M-16:
            // handles borrowed from CIndicatorManager are shared and must survive us)
            if(m_adxHandle != INVALID_HANDLE && m_handleOwned)
            {
                IndicatorRelease(m_adxHandle);
            }
            m_adxHandle = INVALID_HANDLE;
            m_handleOwned = false;

            m_symbol = symbol;
            m_adxPeriod = adxPeriod;

            // Try shared indicator manager first
            CIndicatorManager* indicatorManager = CIndicatorManager::Instance();
            if(indicatorManager != NULL)
            {
                m_adxHandle = indicatorManager.GetADXHandle(symbol, timeframe, adxPeriod);
                if(m_adxHandle != INVALID_HANDLE)
                    return true;   // borrowed handle: m_handleOwned stays false
            }

            // Fallback: create own handle
            m_adxHandle = iADX(symbol, timeframe, adxPeriod);
            if(m_adxHandle == INVALID_HANDLE)
            {
                Print("[ADX-MODIFIER] Failed to create ADX handle for ", symbol);
                return false;
            }
            m_handleOwned = true;

            return true;
        }

        // L5-011/L5-008: Configuration methods for minimum multiplier and no-trend trading
        void SetMinMultiplier(double multiplier)
        {
            m_minMultiplier = MathMax(0.0, MathMin(1.0, multiplier));
        }

        void SetAllowNoTrendTrading(bool allow)
                {
                    m_allowNoTrendTrading = allow;
                }

                // L5-008: Explicit blocking control for no-trend conditions
                void SetBlockOnNoTrend(bool block)
                {
                    m_allowNoTrendTrading = !block;
                }

                void SetThresholds(double noTrend, double weak, double normal, double strong)
        {
            m_noTrendThreshold = noTrend;
            m_weakThreshold = weak;
            m_normalThreshold = normal;
            m_strongThreshold = strong;
        }

    void SetMultipliers(double weak, double normal, double strong, double veryStrong)
        {
            m_weakMultiplier = weak;
            m_normalMultiplier = normal;
            m_strongMultiplier = strong;
            m_veryStrongMultiplier = veryStrong;
        }

        // Parameterless initialize for PositionSizer compatibility (lazy init on first symbol)
        bool Initialize()
        {
            m_lazyInitialized = false;
            return true;
        }

    private:
        // Lazy initialization helper
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
                        // Lazy initialization: ensure ADX handle exists for this symbol
                        EnsureADXHandle(symbol);
                
                        // If symbol changed and we couldn't reinitialize, pass through
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
                                multiplier = 1.0;  // L5-008: Return baseLot unchanged (1.0x) when ADX < threshold
                                PrintFormat("[ADX-MODIFIER] %s | ADX=%.1f < noTrendThreshold=%.1f — no adjustment",
                                            symbol, adx, m_noTrendThreshold);
                            }
                            else
                            {
                                multiplier = 0.0; // Block trade
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

                        // Apply minimum multiplier floor
                        if(multiplier > 0.0 && multiplier < m_minMultiplier)
                            multiplier = m_minMultiplier;

                        double adjusted = baseLot * multiplier;

                        PrintFormat("[ADX-MODIFIER] %s | ADX=%.1f | tier_mult=%.2f | lot %.2f->%.2f",
                                    symbol, adx, multiplier, baseLot, adjusted);

                        return adjusted;
                    }

    virtual string GetName() override { return "ADX"; }
};

// Bayesian Kelly Lot Modifier
// Uses Beta-Binomial conjugate priors to estimate win rate, then applies the Kelly Criterion with a configurable
// fraction. Quarter Kelly (0.25) is the default: ~95% of growth with 12% DD vs 62% at full Kelly. Self-contained.
// L5-013: confidence is the prior weight for the Bayesian update - higher confidence = less prior weight.
class CBayesianKellyModifier : public CPositionSizerModifier
{
private:
    // Beta-Binomial conjugate priors
    double m_alpha;           // Beta prior alpha (win count + prior)
    double m_beta;            // Beta prior beta (loss count + prior)
    double m_kellyFraction;   // Fraction of Kelly to use (0.25 = quarter Kelly)
    double m_avgWinPct;       // Average win as % of risk
    double m_avgLossPct;      // Average loss as % of risk
    int    m_totalTrades;     // Total trades observed
    int    m_wins;            // Win count

    // L5-013: Confidence-weighted prior strength: higher confidence = less prior weight = more conservative
    double m_priorAlpha;      // Prior alpha (wins)
    double m_priorBeta;       // Prior beta (losses)

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

    // CPositionSizerModifier interface
    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        // Need at least 1 trade observation to adjust
        if(m_totalTrades <= 0)
            return baseLot;

        // L5-013: Use confidence as prior weight (high confidence = weaker prior influence)
        double effectiveAlpha, effectiveBeta;
        double confidenceWeight = MathMax(0.0, MathMin(1.0, confidence));
        
        if(confidenceWeight > 0.0)
        {
            // Blend observed stats with prior based on confidence
            double priorWeight = 1.0 - confidenceWeight;
            effectiveAlpha = m_priorAlpha * priorWeight + m_alpha * confidenceWeight;
            effectiveBeta = m_priorBeta * priorWeight + m_beta * confidenceWeight;
        }
        else
        {
            // No confidence provided = use full prior
            effectiveAlpha = m_priorAlpha;
            effectiveBeta = m_priorBeta;
        }

        // Bayesian posterior mean win rate with confidence-weighted prior
        double W = effectiveAlpha / (effectiveAlpha + effectiveBeta);

        // Win/loss ratio R
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
            // Apply fraction of Kelly
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
            m_alpha += 1.0;  // Beta-Binomial conjugate update
            if(profitPct > 0.0)
            {
                // Running average of win percentage
                m_avgWinPct = ((m_avgWinPct * (m_wins - 1)) + profitPct) / m_wins;
            }
        }
        else
        {
            m_beta += 1.0;   // Beta-Binomial conjugate update
            if(lossPct > 0.0)
            {
                int losses = m_totalTrades - m_wins;
                m_avgLossPct = ((m_avgLossPct * (losses - 1)) + lossPct) / losses;
            }
        }
    }

    // Get current effective Kelly fraction (K * m_kellyFraction)
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

// Wraps CEquityCurveManager to scale lot size by equity position vs its EMA (below EMA -> reductionFactor).
// L5-014: Added per-strategy equity curve support
class CEquityCurveLotModifier : public CPositionSizerModifier
{
private:
    // Map of strategy name to equity curve manager
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

    // Constructor with default equity curve manager (backward compatibility)
    CEquityCurveLotModifier(CEquityCurveManager* ecm) : 
        m_curveCount(0),
        m_defaultManager(ecm),
        m_ownsDefaultManager(false)
    {}

    // Initialize with equity curve lookback period
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
        // Clean up owned managers
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

    // Set default equity curve manager (fallback)
    void SetDefaultManager(CEquityCurveManager* manager, bool own = false)
    {
        if(m_ownsDefaultManager && m_defaultManager != NULL)
            delete m_defaultManager;
        m_defaultManager = manager;
        m_ownsDefaultManager = own;
    }

    // Update equity for a specific strategy
    void UpdateStrategyEquity(const string strategyName, double equityValue)
    {
        CEquityCurveManager* curve = FindStrategyCurve(strategyName);
        if(curve != NULL)
        {
            curve.Update(equityValue);
            return;
        }
        // Fallback to default
        if(m_defaultManager != NULL)
            m_defaultManager.Update(equityValue);
    }

    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        // The strategy name should be passed in the symbol parameter or via a different mechanism
        // For now, we use the default manager if no strategy-specific curve is found
        // This would need to be integrated with the strategy identification system
        CEquityCurveManager* curve = m_defaultManager;
        
        // Try to find strategy-specific curve from the symbol name if it contains strategy info
        // This is a simple heuristic - in production, this should come from the trade request
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
            return baseLot;  // No adjustment needed

        double adjusted = baseLot * multiplier;
        PrintFormat("[EQUITY-CURVE-MODIFIER] %s | multiplier=%.2f | lot %.2f->%.2f",
                    symbol, multiplier, baseLot, adjusted);
        return adjusted;
    }

    virtual string GetName() override { return "EquityCurve"; }
};

// Volatility Targeting Lot Modifier
// Adjusts position size to target a specific annualized volatility (ATR-based estimation)
class CVolatilityTargetingModifier : public CPositionSizerModifier
{
private:
    double m_volatilityTarget;      // Target annualized volatility (e.g., 0.15 = 15%)
    int    m_volatilityLookback;    // Lookback period for volatility calculation
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
            // Batch 152 (M-15): anchor to D1 — the annualization below assumes
            // avgATR/price is a DAILY volatility; using PERIOD_CURRENT made the
            // resulting lot size depend on the chart timeframe the EA runs on.
            m_atrHandle = iATR(symbol, PERIOD_D1, m_atrPeriod);
            m_atrSymbol = symbol;
            if(m_atrHandle == INVALID_HANDLE)
                return 0.0;
        }
        
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(m_atrHandle, 0, 0, m_volatilityLookback, atr) <= 0)
            return 0.0;
        
        // ATR is average true range, we need to convert to volatility
        double sumATR = 0.0;
        int count = MathMin(m_volatilityLookback, ArraySize(atr));
        for(int i = 0; i < count; i++)
            sumATR += atr[i];
        double avgATR = sumATR / count;
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double price = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(price <= 0.0) return 0.0;
        
        double dailyVol = avgATR / price;
        // Annualized volatility (sqrt of trading days)
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
        
        // Clamp ratio to reasonable bounds (0.25x to 2.0x)
        volRatio = MathMax(0.25, MathMin(2.0, volRatio));
        
        double adjusted = baseLot * volRatio;
        
        PrintFormat("[VOL-TARGET-MODIFIER] %s | currentVol=%.4f | target=%.4f | ratio=%.2f | lot %.2f->%.2f",
                    symbol, currentVol, m_volatilityTarget, volRatio, baseLot, adjusted);
        
        return adjusted;
    }

    virtual string GetName() override { return "VolatilityTarget"; }
};

// Wraps CVPINFilter to scale lot size based on VPIN toxicity
// L5-024: Supports multiple classification modes
// L5-025: Handles bucket overflow carry
class CVPINLotModifier : public CPositionSizerModifier
{
private:
    CVPINFilter* m_vpinFilter;
    bool         m_ownsFilter;

public:
    CVPINLotModifier() :
        m_vpinFilter(NULL),
        m_ownsFilter(false),
        m_defaultSymbol(""),
        m_defaultBucketVolumeSize(0.0),
        m_defaultNumBuckets(VPIN_DEFAULT_NUM_BUCKETS),
        m_defaultExtremeThreshold(VPIN_DEFAULT_EXTREME),
        m_defaultClassificationMode(VPIN_CLASSIFY_TICK_RULE),
        m_lazyInitialized(false)
    {}

    ~CVPINLotModifier()
    {
        if(m_ownsFilter && m_vpinFilter != NULL)
        {
            delete m_vpinFilter;
            m_vpinFilter = NULL;
        }
    }

    // Parameterless initialize for PositionSizer compatibility
    bool Initialize()
    {
        // Store defaults for lazy initialization
        m_defaultSymbol = "";
        m_defaultBucketVolumeSize = 0.0;
        m_defaultNumBuckets = VPIN_DEFAULT_NUM_BUCKETS;
        m_defaultExtremeThreshold = VPIN_DEFAULT_EXTREME;
        m_defaultClassificationMode = VPIN_CLASSIFY_TICK_RULE;
        m_lazyInitialized = false;
        return true;
    }

    // Full initialize with symbol
    bool Initialize(const string symbol, double bucketVolumeSize = 0.0,
                    int numBuckets = VPIN_DEFAULT_NUM_BUCKETS,
                    double extremeThreshold = VPIN_DEFAULT_EXTREME,
                    ENUM_VPIN_CLASSIFICATION classificationMode = VPIN_CLASSIFY_TICK_RULE)
    {
        m_defaultSymbol = symbol;
        m_defaultBucketVolumeSize = bucketVolumeSize;
        m_defaultNumBuckets = numBuckets;
        m_defaultExtremeThreshold = extremeThreshold;
        m_defaultClassificationMode = classificationMode;
        m_lazyInitialized = true;
        
        if(symbol != "")
        {
            EnsureFilterCreated(symbol);
        }
        return true;
    }

    // Allow passing an existing filter (caller retains ownership)
    void SetVPINFilter(CVPINFilter* filter)
    {
        if(m_ownsFilter && m_vpinFilter != NULL)
        {
            delete m_vpinFilter;
        }
        m_vpinFilter = filter;
        m_ownsFilter = false;
    }

private:
    // Lazy initialization helper
    void EnsureFilterCreated(const string symbol)
    {
        if(m_vpinFilter == NULL && (m_lazyInitialized || symbol != ""))
        {
            string filterSymbol = (symbol != "") ? symbol : m_defaultSymbol;
            if(filterSymbol != "")
            {
                m_vpinFilter = new CVPINFilter(filterSymbol, m_defaultBucketVolumeSize, m_defaultNumBuckets, m_defaultExtremeThreshold, m_defaultClassificationMode);
                m_ownsFilter = true;
            }
        }
    }

    // Lazy initialization state
    string m_defaultSymbol;
    double m_defaultBucketVolumeSize;
    int    m_defaultNumBuckets;
    double m_defaultExtremeThreshold;
    ENUM_VPIN_CLASSIFICATION m_defaultClassificationMode;
    bool   m_lazyInitialized;

public:
    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        // Lazy initialization: create filter for this symbol if not already created
        EnsureFilterCreated(symbol);
        
        if(m_vpinFilter == NULL)
            return baseLot;
        
        double multiplier = m_vpinFilter.GetPositionSizeMultiplier();
        
        // If not warmed up, return base lot unchanged
        if(!m_vpinFilter.IsWarmedUp())
            return baseLot;
        
        // Apply confidence weighting to the VPIN adjustment
        // High confidence = trust VPIN more, low confidence = less VPIN influence
        double effectiveMultiplier = 1.0 + (multiplier - 1.0) * confidence;
        effectiveMultiplier = MathMax(0.1, MathMin(1.0, effectiveMultiplier));
        
        double adjusted = baseLot * effectiveMultiplier;
        
        PrintFormat("[VPIN-MODIFIER] %s | VPIN=%.4f | mult=%.2f | conf=%.2f | lot %.2f->%.2f",
                    symbol, m_vpinFilter.GetVPIN(), multiplier, confidence, baseLot, adjusted);
        
        return adjusted;
    }

    virtual string GetName() override { return "VPIN"; }
};

#endif // CORE_RISK_POSITION_SIZER_MODIFIERS_MQH
