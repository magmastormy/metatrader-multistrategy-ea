//+------------------------------------------------------------------+
//| AdvancedSignalValidator.mqh                                      |
//| Advanced signal validation with confluence, filters, and quality checks |
//+------------------------------------------------------------------+
#ifndef __ADVANCED_SIGNAL_VALIDATOR_MQH__
#define __ADVANCED_SIGNAL_VALIDATOR_MQH__

#include "../Utils/Enums.mqh"
#include "../Utils/CommonTypes.mqh"

//+------------------------------------------------------------------+
//| Signal Validation Result                                         |
//+------------------------------------------------------------------+
struct SSignalValidationResult
{
    bool isValid;
    double qualityScore;  // 0.0 to 1.0
    string reason;
    int strategyConfluence;  // Number of strategies agreeing
    double avgConfidence;
    bool passedSpreadFilter;
    bool passedTimeFilter;
    bool passedVolatilityFilter;
    bool passedSessionFilter;
};

struct SSignalValidationContext
{
    double convictionScore;
    double readinessScore;
    double contextScore;
    double diversityScore;
    double costScore;
    double freshnessScore;
    double directionalQuality;
    double supportRatio;
    int effectiveMinVoters;

    SSignalValidationContext()
    {
        convictionScore = 0.5;
        readinessScore = 0.5;
        contextScore = 0.5;
        diversityScore = 0.5;
        costScore = 0.5;
        freshnessScore = 1.0;
        directionalQuality = 0.0;
        supportRatio = 0.0;
        effectiveMinVoters = 0;
    }
};


struct SSpreadGateState
{
    string symbol;
    double baselineEma;
    datetime lastShockTime;
};

//+------------------------------------------------------------------+
//| Advanced Signal Validator                                        |
//+------------------------------------------------------------------+
class CAdvancedSignalValidator
{
private:
    // Configuration
    int m_minStrategyConfluence;      // Minimum strategies that must agree
    double m_minQualityScore;         // Minimum quality score (0.0-1.0)
    double m_minSignalConfidence;     // Minimum input confidence
    int m_intrabarMinConfluence;      // Intrabar minimum confluence
    double m_intrabarMinQualityScore; // Intrabar minimum quality score
    double m_intrabarMinConfidence;   // Intrabar minimum confidence
    double m_maxSpreadMultiplier;     // Max spread as multiplier of ATR
    double m_maxSpreadToAtrRatio;     // Hard spread/ATR ratio ceiling
    bool m_enableSpreadShockGate;     // Spread shock cooldown gate
    double m_spreadShockMultiplier;   // Spread shock trigger multiple
    int m_spreadShockCooldownSec;     // Cooldown seconds after shock
    bool m_enableTimeFilter;
    bool m_enableSessionFilter;
    bool m_enableVolatilityFilter;
    bool m_enableSpreadFilter;
    bool m_allowSyntheticOffHours;    // Allow synthetics to trade 24/7
    bool m_managerOwnsStructuralAdmission; // When true, validator only enforces exogenous market gates
    SSpreadGateState m_spreadGateStates[];
    
    // Time filter settings
    int m_startHour;                  // Trading start hour (0-23)
    int m_endHour;                    // Trading end hour (0-23)
    bool m_avoidNewsHours;            // Avoid major news hours
    
    // Session filter settings
    bool m_tradeLondonSession;
    bool m_tradeNewYorkSession;
    bool m_tradeTokyoSession;
    bool m_avoidSessionOverlaps;      // Avoid volatile overlaps
    
    // Volatility filter settings
    double m_minVolatility;            // Minimum ATR for trading
    double m_maxVolatility;            // Maximum ATR for trading
    
    // Statistics
    int m_signalsValidated;
    int m_signalsAccepted;
    int m_signalsRejected;
    
public:
    CAdvancedSignalValidator();
    ~CAdvancedSignalValidator();
    
    // Configuration
    void SetMinConfluence(int minConfluence) { m_minStrategyConfluence = minConfluence; }
    void SetMinQualityScore(double minScore) { m_minQualityScore = minScore; }
    void SetMinSignalConfidence(double minConfidence) { m_minSignalConfidence = minConfidence; }
    void SetValidationProfiles(int newBarConfluence,
                               double newBarQuality,
                               double newBarConfidence,
                               int intrabarConfluence,
                               double intrabarQuality,
                               double intrabarConfidence)
    {
        m_minStrategyConfluence = MathMax(1, newBarConfluence);
        m_minQualityScore = MathMax(0.0, MathMin(1.0, newBarQuality));
        m_minSignalConfidence = MathMax(0.0, MathMin(1.0, newBarConfidence));
        m_intrabarMinConfluence = MathMax(1, intrabarConfluence);
        m_intrabarMinQualityScore = MathMax(0.0, MathMin(1.0, intrabarQuality));
        m_intrabarMinConfidence = MathMax(0.0, MathMin(1.0, intrabarConfidence));
    }
    void SetMaxSpreadMultiplier(double multiplier) { m_maxSpreadMultiplier = multiplier; }
    void EnableTimeFilter(bool enable, int startHour = 0, int endHour = 23) 
    { 
        m_enableTimeFilter = enable; 
        m_startHour = startHour;
        m_endHour = endHour;
    }
    void EnableSessionFilter(bool enable, bool london = true, bool newyork = true, bool tokyo = true)
    {
        m_enableSessionFilter = enable;
        m_tradeLondonSession = london;
        m_tradeNewYorkSession = newyork;
        m_tradeTokyoSession = tokyo;
    }
    void EnableVolatilityFilter(bool enable, double minVol = 0.0, double maxVol = 100.0)
    {
        m_enableVolatilityFilter = enable;
        m_minVolatility = minVol;
        m_maxVolatility = maxVol;
    }
    void EnableSpreadFilter(bool enable, double maxSpreadMultiplier = 2.0)
    {
        m_enableSpreadFilter = enable;
        m_maxSpreadMultiplier = maxSpreadMultiplier;
    }
    void ConfigureCostViability(double maxSpreadToAtrRatio,
                                bool enableSpreadShockGate,
                                double spreadShockMultiplier,
                                int spreadShockCooldownSec)
    {
        m_maxSpreadToAtrRatio = MathMax(0.01, maxSpreadToAtrRatio);
        m_enableSpreadShockGate = enableSpreadShockGate;
        m_spreadShockMultiplier = MathMax(1.1, spreadShockMultiplier);
        m_spreadShockCooldownSec = MathMax(5, spreadShockCooldownSec);
    }
    void SetAllowSyntheticOffHours(bool allow) { m_allowSyntheticOffHours = allow; }
    void SetManagerOwnedAdmission(bool owned) { m_managerOwnsStructuralAdmission = owned; }
    
    // Main validation function
    SValidationResult ValidateSignal(
        const string symbol,
        ENUM_TRADE_SIGNAL signal,
        double confidence,
        int strategyConfluence,
        double atrValue,
        ENUM_VALIDATION_PROFILE profile,
        const SSignalValidationContext &context
    );
    
    // Individual filter checks
    bool CheckSpreadFilter(const string symbol, double atrValue, string &rejectReason);
    bool CheckTimeFilter(const string symbol = "");
    bool CheckSessionFilter(const string symbol = "");
    bool CheckVolatilityFilter(const string symbol, double atrValue);
    
private:
    // Helper function
    bool IsSyntheticSymbol(const string symbol);
    int FindSpreadGateStateIndex(const string symbol) const;
    int EnsureSpreadGateState(const string symbol);
    double CalculateSpreadPrice(const string symbol) const;
    
    // Quality score calculation
    double CalculateQualityScore(
        double confidence,
        int strategyConfluence,
        bool passedFilters,
        const SSignalValidationContext &context
    );
    
    // Statistics
    void GetStatistics(int &validated, int &accepted, int &rejected)
    {
        validated = m_signalsValidated;
        accepted = m_signalsAccepted;
        rejected = m_signalsRejected;
    }
    
    void ResetStatistics()
    {
        m_signalsValidated = 0;
        m_signalsAccepted = 0;
        m_signalsRejected = 0;
    }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CAdvancedSignalValidator::CAdvancedSignalValidator() :
    m_minStrategyConfluence(2),
    m_minQualityScore(0.65),
    m_minSignalConfidence(0.60),
    m_intrabarMinConfluence(1),
    m_intrabarMinQualityScore(0.75),
    m_intrabarMinConfidence(0.70),
    m_maxSpreadMultiplier(2.0),       // Max spread = 2x ATR
    m_maxSpreadToAtrRatio(0.25),
    m_enableSpreadShockGate(true),
    m_spreadShockMultiplier(2.5),
    m_spreadShockCooldownSec(30),
    m_enableTimeFilter(true),
    m_enableSessionFilter(true),
    m_enableVolatilityFilter(true),
    m_enableSpreadFilter(true),
    m_allowSyntheticOffHours(true),   // Allow synthetics to trade 24/7 by default
    m_managerOwnsStructuralAdmission(true),
    m_startHour(1),                   // Start at 1 AM
    m_endHour(22),                    // End at 10 PM
    m_avoidNewsHours(true),
    m_tradeLondonSession(true),
    m_tradeNewYorkSession(true),
    m_tradeTokyoSession(true),
    m_avoidSessionOverlaps(false),    // Allow overlaps (good liquidity)
    m_minVolatility(0.0),
    m_maxVolatility(100.0),
    m_signalsValidated(0),
    m_signalsAccepted(0),
    m_signalsRejected(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CAdvancedSignalValidator::~CAdvancedSignalValidator()
{
}

//+------------------------------------------------------------------+
//| Validate Signal                                                  |
//+------------------------------------------------------------------+
SValidationResult CAdvancedSignalValidator::ValidateSignal(
    const string symbol,
    ENUM_TRADE_SIGNAL signal,
    double confidence,
    int strategyConfluence,
    double atrValue,
    ENUM_VALIDATION_PROFILE profile,
    const SSignalValidationContext &context)
{
    SValidationResult result;
    result.isValid = false;
    result.qualityScore = 0.0;
    result.reason = "";
    result.strategyConfluence = strategyConfluence;
    result.avgConfidence = confidence;
    result.passedSpreadFilter = true;
    result.passedTimeFilter = true;
    result.passedVolatilityFilter = true;
    result.passedSessionFilter = true;
    
    m_signalsValidated++;

    // Input validation
    if(confidence < 0.0 || confidence > 1.0)
    {
        result.reason = StringFormat("Invalid confidence: %.2f (must be 0-1)", confidence);
        return result;
    }
    
    if(strategyConfluence < 0)
    {
        result.reason = StringFormat("Invalid confluence: %d (must be >= 0)", strategyConfluence);
        return result;
    }
    
    if(atrValue <= 0.0)
    {
        result.reason = StringFormat("Invalid ATR: %.5f (must be > 0)", atrValue);
        return result;
    }

    int requiredConfluence = m_minStrategyConfluence;
    double requiredQuality = m_minQualityScore;
    double requiredConfidence = m_minSignalConfidence;

    if(profile == VALIDATION_PROFILE_INTRABAR)
    {
        requiredConfluence = m_intrabarMinConfluence;
        requiredQuality = m_intrabarMinQualityScore;
        requiredConfidence = m_intrabarMinConfidence;
    }

    int effectiveRequiredConfluence = requiredConfluence;
    if(context.effectiveMinVoters > 0)
        effectiveRequiredConfluence = MathMax(1, MathMin(requiredConfluence, context.effectiveMinVoters));

    double supportingEvidence = (MathMax(0.0, MathMin(1.0, context.readinessScore)) +
                                 MathMax(0.0, MathMin(1.0, context.contextScore)) +
                                 MathMax(0.0, MathMin(1.0, context.costScore))) / 3.0;
    bool nearConfluencePacket = (strategyConfluence >= MathMax(1, effectiveRequiredConfluence - 1));
    bool strongSingleVoterPacket = (profile == VALIDATION_PROFILE_NEW_BAR &&
                                    strategyConfluence == 1 &&
                                    effectiveRequiredConfluence == 1 &&
                                    confidence >= MathMax(0.0, requiredConfidence - 0.05) &&
                                    context.directionalQuality >= 0.55 &&
                                    context.supportRatio >= 0.20 &&
                                    context.readinessScore >= 0.72 &&
                                    context.contextScore >= 0.70 &&
                                    context.costScore >= 0.65);

    // Structural signal admission belongs to manager consensus. Validator is
    // responsible only for exogenous market gates unless legacy mode is re-enabled.

    // 0. Check spread filter
    if(m_enableSpreadFilter)
    {
        string spreadRejectReason = "";
        result.passedSpreadFilter = CheckSpreadFilter(symbol, atrValue, spreadRejectReason);
        if(!result.passedSpreadFilter)
        {
            result.reason = (spreadRejectReason != "") ? spreadRejectReason : "Spread too wide";
            m_signalsRejected++;
            return result;
        }
    }
    
    // 1. Check time filter
    if(m_enableTimeFilter)
    {
        result.passedTimeFilter = CheckTimeFilter(symbol);
        if(!result.passedTimeFilter)
        {
            result.reason = "Outside trading hours";
            m_signalsRejected++;
            return result;
        }
    }
    
    // 2. Check session filter
    if(m_enableSessionFilter)
    {
        result.passedSessionFilter = CheckSessionFilter(symbol);
        if(!result.passedSessionFilter)
        {
            result.reason = "Not in active trading session";
            m_signalsRejected++;
            return result;
        }
    }
    
    // 3. Check volatility filter
    if(m_enableVolatilityFilter && atrValue > 0)
    {
        result.passedVolatilityFilter = CheckVolatilityFilter(symbol, atrValue);
        if(!result.passedVolatilityFilter)
        {
            result.reason = "Volatility out of range";
            m_signalsRejected++;
            return result;
        }
    }
    
    // 4. Calculate quality score for telemetry / downstream sizing context
    bool allFiltersPassed = result.passedSpreadFilter && result.passedTimeFilter && 
                           result.passedSessionFilter && result.passedVolatilityFilter;
    
    result.qualityScore = CalculateQualityScore(confidence, strategyConfluence, allFiltersPassed, context);

    if(!m_managerOwnsStructuralAdmission)
    {
        if(confidence < requiredConfidence)
        {
            double confidenceGap = requiredConfidence - confidence;
            bool confidenceSoftPass = (confidenceGap <= 0.08 &&
                                       ((context.convictionScore >= 0.62 &&
                                         context.readinessScore >= 0.58 &&
                                         context.contextScore >= 0.60) ||
                                        (nearConfluencePacket &&
                                         supportingEvidence >= 0.70 &&
                                         context.costScore >= 0.65)));
            if(!confidenceSoftPass)
            {
                result.reason = StringFormat("Confidence below profile threshold: %.2f < %.2f",
                                            confidence, requiredConfidence);
                m_signalsRejected++;
                return result;
            }
        }

        if(strategyConfluence < effectiveRequiredConfluence)
        {
            bool confluenceSoftPass = ((effectiveRequiredConfluence - strategyConfluence) == 1 &&
                                       ((context.convictionScore >= 0.68 &&
                                         context.diversityScore >= 0.40) ||
                                        strongSingleVoterPacket));
            if(!confluenceSoftPass)
            {
                result.reason = StringFormat("Insufficient confluence: %d < %d strategies",
                                            strategyConfluence, effectiveRequiredConfluence);
                m_signalsRejected++;
                return result;
            }
        }

        if(result.qualityScore < requiredQuality)
        {
            double qualityGap = requiredQuality - result.qualityScore;
            bool qualitySoftPass = (qualityGap <= 0.08 &&
                                    ((strongSingleVoterPacket &&
                                      supportingEvidence >= 0.74 &&
                                      context.convictionScore >= 0.30 &&
                                      confidence >= MathMax(0.0, requiredConfidence - 0.02)) ||
                                     (nearConfluencePacket &&
                                      supportingEvidence >= 0.80 &&
                                      context.convictionScore >= 0.40 &&
                                      confidence >= requiredConfidence)));
            if(!qualitySoftPass)
            {
                result.reason = StringFormat("Quality score too low: %.2f < %.2f",
                                            result.qualityScore, requiredQuality);
                m_signalsRejected++;
                return result;
            }
        }
    }
    
    // Signal is valid!
    result.isValid = true;
    result.reason = m_managerOwnsStructuralAdmission
                    ? StringFormat("VALID_EXOGENOUS | Confluence: %d | Quality: %.2f | Conf: %.2f",
                                   strategyConfluence, result.qualityScore, confidence)
                    : StringFormat("VALID | Confluence: %d | Quality: %.2f | Conf: %.2f",
                                   strategyConfluence, result.qualityScore, confidence);
    m_signalsAccepted++;
    
    return result;
}

//+------------------------------------------------------------------+
//| Check Spread Filter                                             |
//+------------------------------------------------------------------+
int CAdvancedSignalValidator::FindSpreadGateStateIndex(const string symbol) const
{
    for(int i = 0; i < ArraySize(m_spreadGateStates); i++)
    {
        if(m_spreadGateStates[i].symbol == symbol)
            return i;
    }
    return -1;
}

int CAdvancedSignalValidator::EnsureSpreadGateState(const string symbol)
{
    int index = FindSpreadGateStateIndex(symbol);
    if(index >= 0)
        return index;

    index = ArraySize(m_spreadGateStates);
    ArrayResize(m_spreadGateStates, index + 1);
    m_spreadGateStates[index].symbol = symbol;
    m_spreadGateStates[index].baselineEma = 0.0;
    m_spreadGateStates[index].lastShockTime = 0;
    return index;
}

double CAdvancedSignalValidator::CalculateSpreadPrice(const string symbol) const
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double spread = 0.0;
    if(ask > 0.0 && bid > 0.0 && ask >= bid)
        spread = ask - bid;
    else
        spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;

    if(!MathIsValidNumber(spread) || spread < 0.0)
        spread = 0.0;

    return spread;
}

bool CAdvancedSignalValidator::CheckSpreadFilter(const string symbol, double atrValue, string &rejectReason)
{
    rejectReason = "";
    if(atrValue <= 0)
        return true;  // Skip if no ATR

    int stateIndex = EnsureSpreadGateState(symbol);
    if(stateIndex < 0)
        return true;

    double spread = CalculateSpreadPrice(symbol);
    double maxSpreadByMultiplier = atrValue * m_maxSpreadMultiplier;
    double maxSpreadByRatio = atrValue * m_maxSpreadToAtrRatio;
    double maxSpread = MathMin(maxSpreadByMultiplier, maxSpreadByRatio);

    double baseline = m_spreadGateStates[stateIndex].baselineEma;
    if(baseline <= 0.0)
        baseline = spread;
    else
        baseline = (0.9 * baseline) + (0.1 * spread);
    m_spreadGateStates[stateIndex].baselineEma = baseline;

    if(m_enableSpreadShockGate)
    {
        if(baseline > 0.0 && spread > (baseline * m_spreadShockMultiplier))
            m_spreadGateStates[stateIndex].lastShockTime = TimeCurrent();

        if(m_spreadGateStates[stateIndex].lastShockTime > 0 &&
           (TimeCurrent() - m_spreadGateStates[stateIndex].lastShockTime) <= m_spreadShockCooldownSec)
        {
            rejectReason = StringFormat("Spread shock cooldown active: spread=%.5f baseline=%.5f trigger=%.5f",
                                        spread,
                                        baseline,
                                        baseline * m_spreadShockMultiplier);
            return false;
        }
    }

    if(spread > maxSpread)
    {
        double spreadToAtr = (atrValue > 0.0) ? (spread / atrValue) : 0.0;
        rejectReason = StringFormat("Spread too wide: spread=%.5f max=%.5f atr=%.5f ratio=%.3f",
                                    spread,
                                    maxSpread,
                                    atrValue,
                                    spreadToAtr);
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Check Time Filter                                                |
//+------------------------------------------------------------------+
bool CAdvancedSignalValidator::CheckTimeFilter(const string symbol = "")
{
    // If synthetic indices and off-hours allowed, bypass time filter
    if(m_allowSyntheticOffHours && IsSyntheticSymbol(symbol))
        return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int currentHour = dt.hour;
    
    // Check trading hours (1 AM - 10 PM GMT by default)
    if(m_startHour <= m_endHour)
    {
        if(currentHour < m_startHour || currentHour >= m_endHour)
            return false;
    }
    else  // Overnight hours (e.g., 22 to 2)
    {
        if(currentHour < m_startHour && currentHour >= m_endHour)
            return false;
    }
    
    // Avoid major news hours using absolute GMT time instead of broker-local server time.
    if(m_avoidNewsHours)
    {
        int gmtHour = dt.hour;
        if(gmtHour == 13 || gmtHour == 15 || gmtHour == 19 || gmtHour == 20)
        {
            if(dt.min >= 25 && dt.min <= 35)  // 5-minute window around news
                return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Session Filter                                             |
//+------------------------------------------------------------------+
bool CAdvancedSignalValidator::CheckSessionFilter(const string symbol = "")
{
    // If synthetic indices and off-hours allowed, bypass session filter
    if(m_allowSyntheticOffHours && IsSyntheticSymbol(symbol))
        return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int gmtHour = dt.hour;
    
    // Tokyo session: 00:00-09:00 GMT
    if(m_tradeTokyoSession && gmtHour >= 0 && gmtHour < 9)
        return true;
    
    // London session: 08:00-17:00 GMT
    if(m_tradeLondonSession && gmtHour >= 8 && gmtHour < 17)
        return true;
    
    // New York session: 13:00-22:00 GMT
    if(m_tradeNewYorkSession && gmtHour >= 13 && gmtHour < 22)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Symbol is Synthetic Index                               |
//+------------------------------------------------------------------+
bool CAdvancedSignalValidator::IsSyntheticSymbol(const string symbol)
{
    if(symbol == "") return false;
    
    // Check for broker-specific synthetic products that trade 24/7 or outside regular FX sessions.
    if(StringFind(symbol, "Vol") >= 0  ||      // Vol 10, Vol 25, Vol 50, etc.
       StringFind(symbol, "Step") >= 0 ||      // Step Index variants
       StringFind(symbol, "Boom") >= 0 ||      // Boom 1000, Boom 500
       StringFind(symbol, "Crash") >= 0 ||     // Crash 1000, Crash 500
       StringFind(symbol, "Jump") >= 0 ||      // Jump 10, Jump 25, etc.
       StringFind(symbol, "PainX") >= 0 ||     // Weltrade synthetic family
       StringFind(symbol, "Pain ") >= 0 ||     // Additional naming variant
       StringFind(symbol, "SFX Vol") >= 0 ||
       StringFind(symbol, "FX Vol") >= 0 ||
       StringFind(symbol, "GainX") >= 0 ||
       StringFind(symbol, "FlipX") >= 0)
    {
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check Volatility Filter                                          |
//+------------------------------------------------------------------+
bool CAdvancedSignalValidator::CheckVolatilityFilter(const string symbol, double atrValue)
{
    if(atrValue <= 0) return true;
    
    // Synthetic indices have naturally extreme ATR relative to price.
    // Their volatility characteristics are fundamentally different from forex,
    // so percentage-based ATR filtering produces systematic false rejections.
    if(IsSyntheticSymbol(symbol)) return true;
    
    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    if(price <= 0) return true;
    
    double atrPercent = (atrValue / price) * 100.0;
    
    return (atrPercent >= m_minVolatility && atrPercent <= m_maxVolatility);
}

//+------------------------------------------------------------------+
//| Calculate Quality Score                                          |
//+------------------------------------------------------------------+
double CAdvancedSignalValidator::CalculateQualityScore(
    double confidence,
    int strategyConfluence,
    bool passedFilters,
    const SSignalValidationContext &context)
{
    double score = 0.0;
    
    // Validate inputs - handle NaN and extreme values
    if(!MathIsValidNumber(confidence) || confidence < 0.0 || confidence > 1.0)
        confidence = 0.0;
    
    // Confidence component
    score += confidence * 0.20;
    
    // Confluence component
    double confluenceScore = MathMin(1.0, MathMax(0.0, strategyConfluence / 5.0));
    score += confluenceScore * 0.10;
    
    // Decision-path components from consensus and pipeline evidence with NaN protection
    double convictionScore = MathIsValidNumber(context.convictionScore) ? context.convictionScore : 0.0;
    double readinessScore = MathIsValidNumber(context.readinessScore) ? context.readinessScore : 0.0;
    double contextScore = MathIsValidNumber(context.contextScore) ? context.contextScore : 0.0;
    double diversityScore = MathIsValidNumber(context.diversityScore) ? context.diversityScore : 0.0;
    double freshnessScore = MathIsValidNumber(context.freshnessScore) ? context.freshnessScore : 0.0;
    double costScore = MathIsValidNumber(context.costScore) ? context.costScore : 0.0;
    double directionalQuality = MathIsValidNumber(context.directionalQuality) ? context.directionalQuality : 0.0;
    double supportRatio = MathIsValidNumber(context.supportRatio) ? context.supportRatio : 0.0;
    
    score += MathMax(0.0, MathMin(1.0, convictionScore)) * 0.12;
    score += MathMax(0.0, MathMin(1.0, readinessScore)) * 0.08;
    score += MathMax(0.0, MathMin(1.0, contextScore)) * 0.08;
    score += MathMax(0.0, MathMin(1.0, diversityScore)) * 0.07;
    score += MathMax(0.0, MathMin(1.0, freshnessScore)) * 0.03;
    score += MathMax(0.0, MathMin(1.0, costScore)) * 0.05;
    score += MathMax(0.0, MathMin(1.0, directionalQuality)) * 0.15;
    score += MathMax(0.0, MathMin(1.0, supportRatio)) * 0.07;
    
    // Filter component
    if(passedFilters)
        score += 0.05;
    
    // Ensure final score is valid and in range [0, 1]
    if(!MathIsValidNumber(score))
        score = 0.0;
    
    return MathMax(0.0, MathMin(1.0, score));
}

#endif // __ADVANCED_SIGNAL_VALIDATOR_MQH__
