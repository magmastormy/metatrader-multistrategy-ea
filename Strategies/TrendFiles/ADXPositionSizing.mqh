// ADX-Based Adaptive Position Sizing
// Adjusts lot size based on trend strength
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef TREND_ADX_POSITION_SIZING_MQH
#define TREND_ADX_POSITION_SIZING_MQH

#include "../../IndicatorManager.mqh"

enum ENUM_ADX_TIER
{
    ADX_NO_TREND,       // ADX < 20 - no trade
    ADX_WEAK_TREND,     // ADX 20-25 - half size
    ADX_NORMAL_TREND,   // ADX 25-35 - full size
    ADX_STRONG_TREND,   // ADX 35-45 - 1.3x size
    ADX_VERY_STRONG     // ADX > 45 - 1.5x size
};

#include "../../Core/Utils/Instruments.mqh"

class CADXPositionSizing
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    int                 m_adxHandle;
    
    // Configuration
    double              m_weakTrendMultiplier;
    double              m_normalMultiplier;     // 1.0x for normal trends
    double              m_strongMultiplier;     // 1.3x for strong trends
    double              m_veryStrongMultiplier;
    
    // ADX tier boundaries - InitForAssetClass is the only writer
    double              m_noTrendThreshold;     // Below this = no trade
    double              m_weakThreshold;        // Weak trend threshold
    double              m_normalThreshold;      // Normal trend threshold
    double              m_strongThreshold;      // Strong trend threshold
    
    // Internal methods
    double              GetADX();
    ENUM_ADX_TIER       GetADXTier(double adx);
    
public:
// Standardized ADX tiers
// Rationale:
// ADX < 20: No trend - range-bound market, avoid entries
// ADX 20-25: Weak trend - low conviction, use half position size
// ADX 25-30: Normal trend - acceptable strength, full size
// ADX 30-40: Strong trend - high conviction, 1.3x size
// ADX > 40: Very strong trend - maximum conviction, 1.5x size
                        CADXPositionSizing();
                       ~CADXPositionSizing();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    void                Deinit();
    
    // Position sizing
    double              GetPositionSizeMultiplier();
    bool                ShouldTrade();
    bool                IsDirectionallyClear();
    
    ENUM_ADX_TIER       GetCurrentTier();
    
    // Configuration
    void                InitForAssetClass(int assetClass);
};

// Constructor - Uses input parameters for standardized thresholds
CADXPositionSizing::CADXPositionSizing() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_adxHandle(INVALID_HANDLE),
    m_weakTrendMultiplier(0.5),
    m_normalMultiplier(1.0),
    m_strongMultiplier(1.3),
    m_veryStrongMultiplier(1.5),
// Initialize from standardized thresholds (hardcoded for .mqh compatibility)
    m_noTrendThreshold(20.0),
    m_weakThreshold(25.0),
    m_normalThreshold(30.0),
    m_strongThreshold(40.0)
{
}

CADXPositionSizing::~CADXPositionSizing()
{
    Deinit();
}

bool CADXPositionSizing::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    m_adxHandle = CIndicatorManager::Instance().GetADXHandle(symbol, timeframe, 14);
    
    if(m_adxHandle == INVALID_HANDLE)
    {
        Print("[ADXSizing] Failed to create ADX handle");
        return false;
    }
    
    return true;
}

void CADXPositionSizing::Deinit()
{
    // this handle comes from CIndicatorManager's shared cache
    // (GetADXHandle) and is the SAME handle CMultiEMASystem depends on.
    // Releasing it here killed the ADX feed for every consumer after any
    // strategy re-init (OnDeinit->OnInit on TF/input change), freezing EMA
    // updates and silently stopping the whole Trend stack. Every sibling
    // class documents this rule - this was the outlier.
    if(m_adxHandle != INVALID_HANDLE)
    {
        m_adxHandle = INVALID_HANDLE;
    }
}

// Get ADX Value
double CADXPositionSizing::GetADX()
{
    if(m_adxHandle == INVALID_HANDLE) return 0;
    
    double adx[];
    ArraySetAsSeries(adx, true);
    
    if(CopyBuffer(m_adxHandle, 0, 0, 1, adx) <= 0)
        return 0;
    
    return adx[0];
}

ENUM_ADX_TIER CADXPositionSizing::GetADXTier(double adx)
{
    if(adx < m_noTrendThreshold)
        return ADX_NO_TREND;
    else if(adx < m_weakThreshold)
        return ADX_WEAK_TREND;
    else if(adx < m_normalThreshold)
        return ADX_NORMAL_TREND;
    else if(adx < m_strongThreshold)
        return ADX_STRONG_TREND;
    else
        return ADX_VERY_STRONG;
}

ENUM_ADX_TIER CADXPositionSizing::GetCurrentTier()
{
    return GetADXTier(GetADX());
}

bool CADXPositionSizing::ShouldTrade()
{
    return (GetADX() >= m_noTrendThreshold);
}

// Is Directionally Clear (Regime Lockout)
bool CADXPositionSizing::IsDirectionallyClear()
{
    if(m_adxHandle == INVALID_HANDLE) return false;
    
    double pDI[1], mDI[1], adxMain[1];
    if(CopyBuffer(m_adxHandle, 0, 0, 1, adxMain) <= 0 ||
       CopyBuffer(m_adxHandle, 1, 0, 1, pDI) <= 0 ||
       CopyBuffer(m_adxHandle, 2, 0, 1, mDI) <= 0)
    {
        return false;
    }
    
    // ADX must be above minimum threshold
    if(adxMain[0] < m_noTrendThreshold) return false;
    
    // There must be a clear separation between bulls (+DI) and bears (-DI).
    // Tangled DI lines mean high-volatility chop (ranging trap).
    // Lowered from 5.0 to 2.0 for synthetic CFDs where DI lines are typically close
    double diSpread = MathAbs(pDI[0] - mDI[0]);
    if(diSpread < 2.0) return false; // Chop zone lockout
    
    return true;
}

double CADXPositionSizing::GetPositionSizeMultiplier()
{
    ENUM_ADX_TIER tier = GetCurrentTier();
    
    switch(tier)
    {
        case ADX_NO_TREND:      return 0.0;  // No trade
        case ADX_WEAK_TREND:    return m_weakTrendMultiplier;
        case ADX_NORMAL_TREND:  return m_normalMultiplier;
        case ADX_STRONG_TREND:  return m_strongMultiplier;
        case ADX_VERY_STRONG:   return m_veryStrongMultiplier;
        default:                return 0.0;
    }
}

// Initialize ADX thresholds based on asset class
// Synthetics have lower ADX due to algorithmic price generation
void CADXPositionSizing::InitForAssetClass(int assetClass)
{
    switch(assetClass)
    {
        case ASSET_FOREX:
        case ASSET_METALS:
            m_noTrendThreshold = 20.0;
            m_weakThreshold = 25.0;
            m_normalThreshold = 30.0;
            m_strongThreshold = 35.0;
            break;

        case ASSET_DERIV_CRASHBOOM:
        case ASSET_DERIV_VOLATILITY:
        case ASSET_DERIV_STEP:
        case ASSET_DERIV_JUMP:
        case ASSET_DERIV_DEX:
            // Synthetics have lower ADX due to algorithmic generation
            m_noTrendThreshold = 15.0;
            m_weakThreshold = 20.0;
            m_normalThreshold = 25.0;
            m_strongThreshold = 30.0;
            break;

        case ASSET_INDICES:
            m_noTrendThreshold = 18.0;
            m_weakThreshold = 23.0;
            m_normalThreshold = 28.0;
            m_strongThreshold = 33.0;
            break;

        default:
            // Keep defaults (20/25/30/40)
            break;
    }
}

#endif // __TREND_ADX_POSITION_SIZING_MQH__

