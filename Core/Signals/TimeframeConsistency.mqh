//+------------------------------------------------------------------+
//| TimeframeConsistency.mqh                                        |
//| Ensures consistent multi-timeframe signal alignment             |
//| Prevents hedging due to conflicting TF signals                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property version   "1.00"
#property strict

#ifndef TIMEFRAME_CONSISTENCY_MQH
#define TIMEFRAME_CONSISTENCY_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/SignalDiagnostics.mqh"
#include <Arrays/ArrayObj.mqh>

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;

//+------------------------------------------------------------------+
//| Timeframe Signal Structure                                      |
//+------------------------------------------------------------------+
struct STimeframeSignal
{
    ENUM_TIMEFRAMES timeframe;
    ENUM_TRADE_SIGNAL signal;
    double confidence;
    string strategyName;
    datetime timestamp;
    double trendStrength;
    double volatility;
    
    STimeframeSignal()
    {
        timeframe = PERIOD_CURRENT;
        signal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        strategyName = "";
        timestamp = 0;
        trendStrength = 0.0;
        volatility = 0.0;
    }
};

//+------------------------------------------------------------------+
//| Conflict Resolution Mode                                        |
//+------------------------------------------------------------------+
enum ENUM_CONFLICT_RESOLUTION
{
    CONFLICT_RES_NEUTRAL,      // Return neutral signal on conflict
    CONFLICT_RES_STRONGEST,    // Use strongest confidence signal
    CONFLICT_RES_HTF_PRIORITY, // Higher timeframe takes priority
    CONFLICT_RES_LTF_PRIORITY, // Lower timeframe takes priority
    CONFLICT_RES_MAJORITY,     // Majority voting across timeframes
    CONFLICT_RES_WEIGHTED      // Weighted by confidence and timeframe
};

//+------------------------------------------------------------------+
//| Timeframe Consistency Class                                     |
//+------------------------------------------------------------------+
class CTimeframeConsistency
{
private:
    STimeframeSignal m_signals[];
    int              m_signalCount;
    ENUM_CONFLICT_RESOLUTION m_resolutionMode;
    double           m_minAlignmentThreshold;
    bool             m_requireFullAlignment;
    CSignalDiagnostics* m_diagnostics;
    
    // Configuration
    double           m_htfWeight;    // Weight for higher timeframes
    double           m_confidenceThreshold;
    bool             m_preventHedging;
    
    // Statistics
    int              m_totalChecks;
    int              m_conflictsDetected;
    int              m_hedgesPrevented;
    
public:
    CTimeframeConsistency();
    ~CTimeframeConsistency();
    
    // Initialize
    bool Initialize(ENUM_CONFLICT_RESOLUTION mode = CONFLICT_RES_WEIGHTED,
                   double minAlignment = 0.6,
                   bool requireFull = false);
                   
    void SetDiagnostics(CSignalDiagnostics* diag) { m_diagnostics = diag; }
    
    // Add timeframe signal
    void AddTimeframeSignal(ENUM_TIMEFRAMES tf,
                           ENUM_TRADE_SIGNAL signal,
                           double confidence,
                           const string strategyName);
    
    // Process and resolve conflicts
    ENUM_TRADE_SIGNAL ResolveSignals(double &finalConfidence, string &reasoning);
    
    // Check for conflicts
    bool HasConflicts() const;
    int GetConflictCount() const;
    string GetConflictDetails() const;
    
    // Alignment checking
    double CalculateAlignment() const;
    bool IsAligned() const;
    
    // Hedging prevention
    bool WouldCauseHedge(ENUM_TRADE_SIGNAL newSignal) const;
    ENUM_TRADE_SIGNAL PreventHedging(ENUM_TRADE_SIGNAL signal1, 
                                     ENUM_TRADE_SIGNAL signal2);
    
    // Clear signals for new evaluation
    void Reset();
    
    // Configuration
    void SetResolutionMode(ENUM_CONFLICT_RESOLUTION mode) { m_resolutionMode = mode; }
    void SetHTFWeight(double weight) { m_htfWeight = weight; }
    void SetConfidenceThreshold(double threshold) { m_confidenceThreshold = threshold; }
    void EnableHedgePrevention(bool enable) { m_preventHedging = enable; }
    
    // Statistics
    double GetConflictRate() const;
    int GetHedgesPrevented() const { return m_hedgesPrevented; }
    
private:
    // Resolution methods
    ENUM_TRADE_SIGNAL ResolveNeutral(double &confidence, string &reasoning);
    ENUM_TRADE_SIGNAL ResolveStrongest(double &confidence, string &reasoning);
    ENUM_TRADE_SIGNAL ResolveHTFPriority(double &confidence, string &reasoning);
    ENUM_TRADE_SIGNAL ResolveLTFPriority(double &confidence, string &reasoning);
    ENUM_TRADE_SIGNAL ResolveMajority(double &confidence, string &reasoning);
    ENUM_TRADE_SIGNAL ResolveWeighted(double &confidence, string &reasoning);
    
    // Helper functions
    int GetTimeframeRank(ENUM_TIMEFRAMES tf) const;
    double GetTimeframeWeight(ENUM_TIMEFRAMES tf) const;
    string TimeframeToString(ENUM_TIMEFRAMES tf) const;
    void LogConflictResolution(const string method, 
                              ENUM_TRADE_SIGNAL result,
                              double confidence);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTimeframeConsistency::CTimeframeConsistency() :
    m_signalCount(0),
    m_resolutionMode(CONFLICT_RES_WEIGHTED),
    m_minAlignmentThreshold(0.6),
    m_requireFullAlignment(false),
    m_diagnostics(NULL),
    m_htfWeight(1.5),
    m_confidenceThreshold(0.5),
    m_preventHedging(false),
    m_totalChecks(0),
    m_conflictsDetected(0),
    m_hedgesPrevented(0)
{
    ArrayResize(m_signals, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTimeframeConsistency::~CTimeframeConsistency()
{
    ArrayFree(m_signals);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CTimeframeConsistency::Initialize(ENUM_CONFLICT_RESOLUTION mode,
                                       double minAlignment,
                                       bool requireFull)
{
    m_resolutionMode = mode;
    m_minAlignmentThreshold = minAlignment;
    m_requireFullAlignment = requireFull;
    
    Print("[TimeframeConsistency] Initialized with mode: ", EnumToString(mode),
          ", Min Alignment: ", minAlignment,
          ", Require Full: ", requireFull);
    
    return true;
}

//+------------------------------------------------------------------+
//| Add Timeframe Signal                                            |
//+------------------------------------------------------------------+
void CTimeframeConsistency::AddTimeframeSignal(ENUM_TIMEFRAMES tf,
                                              ENUM_TRADE_SIGNAL signal,
                                              double confidence,
                                              const string strategyName)
{
    if(signal == TRADE_SIGNAL_NONE) return;
    
    int newSize = m_signalCount + 1;
    ArrayResize(m_signals, newSize);
    
    m_signals[m_signalCount].timeframe = tf;
    m_signals[m_signalCount].signal = signal;
    m_signals[m_signalCount].confidence = confidence;
    m_signals[m_signalCount].strategyName = strategyName;
    m_signals[m_signalCount].timestamp = TimeCurrent();
    
    m_signalCount++;
}

//+------------------------------------------------------------------+
//| Resolve Signals                                                 |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTimeframeConsistency::ResolveSignals(double &finalConfidence, string &reasoning)
{
    if(m_signalCount == 0)
    {
        finalConfidence = 0.0;
        reasoning = "No signals to resolve";
        return TRADE_SIGNAL_NONE;
    }
    
    m_totalChecks++;
    
    // Check for conflicts
    if(HasConflicts())
    {
        m_conflictsDetected++;
        
        if(m_diagnostics != NULL)
        {
            string conflictDetails = GetConflictDetails();
            // Log conflict to diagnostics
            Print("[TimeframeConsistency] Conflict detected: ", conflictDetails);
        }
    }
    
    // Resolve based on selected mode
    ENUM_TRADE_SIGNAL result = TRADE_SIGNAL_NONE;
    
    switch(m_resolutionMode)
    {
        case CONFLICT_RES_NEUTRAL:
            result = ResolveNeutral(finalConfidence, reasoning);
            break;
        case CONFLICT_RES_STRONGEST:
            result = ResolveStrongest(finalConfidence, reasoning);
            break;
        case CONFLICT_RES_HTF_PRIORITY:
            result = ResolveHTFPriority(finalConfidence, reasoning);
            break;
        case CONFLICT_RES_LTF_PRIORITY:
            result = ResolveLTFPriority(finalConfidence, reasoning);
            break;
        case CONFLICT_RES_MAJORITY:
            result = ResolveMajority(finalConfidence, reasoning);
            break;
        case CONFLICT_RES_WEIGHTED:
            result = ResolveWeighted(finalConfidence, reasoning);
            break;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Check for Conflicts                                             |
//+------------------------------------------------------------------+
bool CTimeframeConsistency::HasConflicts() const
{
    if(m_signalCount < 2) return false;
    
    ENUM_TRADE_SIGNAL firstSignal = m_signals[0].signal;
    
    for(int i = 1; i < m_signalCount; i++)
    {
        if(m_signals[i].signal != firstSignal && 
           m_signals[i].signal != TRADE_SIGNAL_NONE)
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Conflict Count                                              |
//+------------------------------------------------------------------+
int CTimeframeConsistency::GetConflictCount() const
{
    int conflicts = 0;
    
    for(int i = 0; i < m_signalCount - 1; i++)
    {
        for(int j = i + 1; j < m_signalCount; j++)
        {
            if(m_signals[i].signal != m_signals[j].signal &&
               m_signals[i].signal != TRADE_SIGNAL_NONE &&
               m_signals[j].signal != TRADE_SIGNAL_NONE)
            {
                conflicts++;
            }
        }
    }
    
    return conflicts;
}

//+------------------------------------------------------------------+
//| Get Conflict Details                                            |
//+------------------------------------------------------------------+
string CTimeframeConsistency::GetConflictDetails() const
{
    string details = "";
    
    for(int i = 0; i < m_signalCount; i++)
    {
        details += TimeframeToString(m_signals[i].timeframe) + ":" +
                  (m_signals[i].signal == TRADE_SIGNAL_BUY ? "BUY" :
                   m_signals[i].signal == TRADE_SIGNAL_SELL ? "SELL" : "NONE") +
                  "(" + DoubleToString(m_signals[i].confidence, 2) + ")";
        
        if(i < m_signalCount - 1) details += " vs ";
    }
    
    return details;
}

//+------------------------------------------------------------------+
//| Calculate Alignment                                             |
//+------------------------------------------------------------------+
double CTimeframeConsistency::CalculateAlignment() const
{
    if(m_signalCount < 2) return 1.0;
    
    int buyCount = 0, sellCount = 0;
    double totalConfidence = 0.0;
    
    for(int i = 0; i < m_signalCount; i++)
    {
        if(m_signals[i].signal == TRADE_SIGNAL_BUY)
        {
            buyCount++;
            totalConfidence += m_signals[i].confidence;
        }
        else if(m_signals[i].signal == TRADE_SIGNAL_SELL)
        {
            sellCount++;
            totalConfidence += m_signals[i].confidence;
        }
    }
    
    int majority = MathMax(buyCount, sellCount);
    double alignment = (double)majority / m_signalCount;
    
    // Weight by average confidence
    if(majority > 0)
    {
        double avgConfidence = totalConfidence / majority;
        alignment *= avgConfidence;
    }
    
    return alignment;
}

//+------------------------------------------------------------------+
//| Check if Aligned                                                |
//+------------------------------------------------------------------+
bool CTimeframeConsistency::IsAligned() const
{
    double alignment = CalculateAlignment();
    
    if(m_requireFullAlignment)
        return alignment >= 1.0;
    else
        return alignment >= m_minAlignmentThreshold;
}

//+------------------------------------------------------------------+
//| Would Cause Hedge                                               |
//+------------------------------------------------------------------+
bool CTimeframeConsistency::WouldCauseHedge(ENUM_TRADE_SIGNAL newSignal) const
{
    // Check if we have opposing signals that would cause hedging
    bool hasBuy = false, hasSell = false;
    
    for(int i = 0; i < m_signalCount; i++)
    {
        if(m_signals[i].signal == TRADE_SIGNAL_BUY) hasBuy = true;
        if(m_signals[i].signal == TRADE_SIGNAL_SELL) hasSell = true;
    }
    
    return (hasBuy && hasSell);
}

//+------------------------------------------------------------------+
//| Prevent Hedging                                                 |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTimeframeConsistency::PreventHedging(ENUM_TRADE_SIGNAL signal1,
                                                       ENUM_TRADE_SIGNAL signal2)
{
    if(signal1 == signal2) return signal1;
    
    if((signal1 == TRADE_SIGNAL_BUY && signal2 == TRADE_SIGNAL_SELL) ||
       (signal1 == TRADE_SIGNAL_SELL && signal2 == TRADE_SIGNAL_BUY))
    {
        m_hedgesPrevented++;
        return TRADE_SIGNAL_NONE; // Neutralize conflicting signals
    }
    
    return signal1; // Return first signal if not conflicting
}

//+------------------------------------------------------------------+
//| Reset                                                            |
//+------------------------------------------------------------------+
void CTimeframeConsistency::Reset()
{
    m_signalCount = 0;
    ArrayResize(m_signals, 0);
}

//+------------------------------------------------------------------+
//| Resolve Neutral                                                 |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTimeframeConsistency::ResolveNeutral(double &confidence, string &reasoning)
{
    if(HasConflicts())
    {
        confidence = 0.0;
        reasoning = "Conflicting signals - returning neutral";
        return TRADE_SIGNAL_NONE;
    }
    
    // All signals agree
    confidence = 0.0;
    for(int i = 0; i < m_signalCount; i++)
        confidence += m_signals[i].confidence;
    confidence /= m_signalCount;
    
    reasoning = "All timeframes aligned";
    return m_signals[0].signal;
}

//+------------------------------------------------------------------+
//| Resolve Strongest                                               |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTimeframeConsistency::ResolveStrongest(double &confidence, string &reasoning)
{
    int strongestIdx = 0;
    double maxConfidence = 0.0;
    
    for(int i = 0; i < m_signalCount; i++)
    {
        if(m_signals[i].confidence > maxConfidence)
        {
            maxConfidence = m_signals[i].confidence;
            strongestIdx = i;
        }
    }
    
    confidence = maxConfidence;
    reasoning = "Strongest signal from " + TimeframeToString(m_signals[strongestIdx].timeframe);
    return m_signals[strongestIdx].signal;
}

//+------------------------------------------------------------------+
//| Resolve HTF Priority                                            |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTimeframeConsistency::ResolveHTFPriority(double &confidence, string &reasoning)
{
    int highestTFIdx = 0;
    int highestRank = 0;
    
    for(int i = 0; i < m_signalCount; i++)
    {
        int rank = GetTimeframeRank(m_signals[i].timeframe);
        if(rank > highestRank)
        {
            highestRank = rank;
            highestTFIdx = i;
        }
    }
    
    confidence = m_signals[highestTFIdx].confidence;
    reasoning = "HTF priority: " + TimeframeToString(m_signals[highestTFIdx].timeframe);
    return m_signals[highestTFIdx].signal;
}

//+------------------------------------------------------------------+
//| Resolve LTF Priority                                            |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTimeframeConsistency::ResolveLTFPriority(double &confidence, string &reasoning)
{
    int lowestTFIdx = 0;
    int lowestRank = 999;
    
    for(int i = 0; i < m_signalCount; i++)
    {
        int rank = GetTimeframeRank(m_signals[i].timeframe);
        if(rank < lowestRank)
        {
            lowestRank = rank;
            lowestTFIdx = i;
        }
    }
    
    confidence = m_signals[lowestTFIdx].confidence;
    reasoning = "LTF priority: " + TimeframeToString(m_signals[lowestTFIdx].timeframe);
    return m_signals[lowestTFIdx].signal;
}

//+------------------------------------------------------------------+
//| Resolve Majority                                                |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTimeframeConsistency::ResolveMajority(double &confidence, string &reasoning)
{
    int buyVotes = 0, sellVotes = 0;
    double buyConfidence = 0.0, sellConfidence = 0.0;
    
    for(int i = 0; i < m_signalCount; i++)
    {
        if(m_signals[i].signal == TRADE_SIGNAL_BUY)
        {
            buyVotes++;
            buyConfidence += m_signals[i].confidence;
        }
        else if(m_signals[i].signal == TRADE_SIGNAL_SELL)
        {
            sellVotes++;
            sellConfidence += m_signals[i].confidence;
        }
    }
    
    if(buyVotes > sellVotes)
    {
        confidence = buyConfidence / buyVotes;
        reasoning = StringFormat("Majority BUY: %d/%d votes", buyVotes, m_signalCount);
        return TRADE_SIGNAL_BUY;
    }
    else if(sellVotes > buyVotes)
    {
        confidence = sellConfidence / sellVotes;
        reasoning = StringFormat("Majority SELL: %d/%d votes", sellVotes, m_signalCount);
        return TRADE_SIGNAL_SELL;
    }
    
    confidence = 0.0;
    reasoning = "No majority consensus";
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Resolve Weighted                                                |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTimeframeConsistency::ResolveWeighted(double &confidence, string &reasoning)
{
    double buyWeight = 0.0, sellWeight = 0.0;
    
    for(int i = 0; i < m_signalCount; i++)
    {
        double tfWeight = GetTimeframeWeight(m_signals[i].timeframe);
        double signalWeight = m_signals[i].confidence * tfWeight;
        
        if(m_signals[i].signal == TRADE_SIGNAL_BUY)
            buyWeight += signalWeight;
        else if(m_signals[i].signal == TRADE_SIGNAL_SELL)
            sellWeight += signalWeight;
    }
    
    if(buyWeight > sellWeight && buyWeight > m_confidenceThreshold)
    {
        confidence = buyWeight / (buyWeight + sellWeight);
        reasoning = StringFormat("Weighted BUY: %.2f vs %.2f", buyWeight, sellWeight);
        return TRADE_SIGNAL_BUY;
    }
    else if(sellWeight > buyWeight && sellWeight > m_confidenceThreshold)
    {
        confidence = sellWeight / (buyWeight + sellWeight);
        reasoning = StringFormat("Weighted SELL: %.2f vs %.2f", sellWeight, buyWeight);
        return TRADE_SIGNAL_SELL;
    }
    
    confidence = 0.0;
    reasoning = "Insufficient weighted consensus";
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Get Timeframe Rank                                              |
//+------------------------------------------------------------------+
int CTimeframeConsistency::GetTimeframeRank(ENUM_TIMEFRAMES tf) const
{
    switch(tf)
    {
        case PERIOD_M1:  return 1;
        case PERIOD_M5:  return 2;
        case PERIOD_M15: return 3;
        case PERIOD_M30: return 4;
        case PERIOD_H1:  return 5;
        case PERIOD_H4:  return 6;
        case PERIOD_D1:  return 7;
        case PERIOD_W1:  return 8;
        case PERIOD_MN1: return 9;
        default: return 0;
    }
}

//+------------------------------------------------------------------+
//| Get Timeframe Weight                                            |
//+------------------------------------------------------------------+
double CTimeframeConsistency::GetTimeframeWeight(ENUM_TIMEFRAMES tf) const
{
    int rank = GetTimeframeRank(tf);
    if(rank >= 5) // H1 and above
        return m_htfWeight;
    else
        return 1.0;
}

//+------------------------------------------------------------------+
//| Timeframe to String                                             |
//+------------------------------------------------------------------+
string CTimeframeConsistency::TimeframeToString(ENUM_TIMEFRAMES tf) const
{
    switch(tf)
    {
        case PERIOD_M1:  return "M1";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN1";
        default: return "Unknown";
    }
}

//+------------------------------------------------------------------+
//| Get Conflict Rate                                               |
//+------------------------------------------------------------------+
double CTimeframeConsistency::GetConflictRate() const
{
    if(m_totalChecks == 0) return 0.0;
    return (double)m_conflictsDetected / m_totalChecks;
}

//+------------------------------------------------------------------+
//| Log Conflict Resolution                                         |
//+------------------------------------------------------------------+
void CTimeframeConsistency::LogConflictResolution(const string method,
                                                 ENUM_TRADE_SIGNAL result,
                                                 double confidence)
{
    if(m_diagnostics != NULL)
    {
        string msg = StringFormat("Resolved using %s: %s (%.2f%%)",
                                method,
                                (result == TRADE_SIGNAL_BUY ? "BUY" : 
                                 result == TRADE_SIGNAL_SELL ? "SELL" : "NONE"),
                                confidence * 100);
        Print("[TimeframeConsistency] ", msg);
    }
}

#endif // TIMEFRAME_CONSISTENCY_MQH
