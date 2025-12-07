//+------------------------------------------------------------------+
//| ConfluenceEngine.mqh                                             |
//| Calculates trade scores based on weighted confluence factors     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced AI Coding Assistant"
#property version   "1.00"
#property strict

#include "../Utils/Enums.mqh"
#include <Arrays/ArrayDouble.mqh>

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Confluence Engine Class                                          |
//+------------------------------------------------------------------+
class CConfluenceEngine : public CObject
{
private:
    // Weights
    double m_weightHTFBias;
    double m_weightOBUnmitigated;
    double m_weightFVGOverlap;
    double m_weightSweep;
    double m_weightVolume;
    double m_weightSession;
    double m_weightSpread;
    
    // Thresholds
    double m_thresholdKS;
    double m_thresholdHTF;
    
public:
    CConfluenceEngine();
    ~CConfluenceEngine();
    
    void Init(double wHTF, double wOB, double wFVG, double wSweep, double wVol, double wSess, double wSpread, double threshKS, double threshHTF);
    
    double CalculateScore(bool htfAligned, bool obUnmitigated, bool fvgOverlap, bool sweepConfirmed, bool volSpike, bool sessionMatch, bool lowSpread);
    
    bool IsEntryValid(double score, ENUM_TRADING_MODE mode);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CConfluenceEngine::CConfluenceEngine() :
    m_weightHTFBias(30.0),
    m_weightOBUnmitigated(25.0),
    m_weightFVGOverlap(15.0),
    m_weightSweep(20.0),
    m_weightVolume(10.0),
    m_weightSession(5.0),
    m_weightSpread(5.0),
    m_thresholdKS(60.0),
    m_thresholdHTF(70.0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CConfluenceEngine::~CConfluenceEngine()
{
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
void CConfluenceEngine::Init(double wHTF, double wOB, double wFVG, double wSweep, double wVol, double wSess, double wSpread, double threshKS, double threshHTF)
{
    m_weightHTFBias = wHTF;
    m_weightOBUnmitigated = wOB;
    m_weightFVGOverlap = wFVG;
    m_weightSweep = wSweep;
    m_weightVolume = wVol;
    m_weightSession = wSess;
    m_weightSpread = wSpread;
    m_thresholdKS = threshKS;
    m_thresholdHTF = threshHTF;
}

//+------------------------------------------------------------------+
//| Calculate Score                                                  |
//+------------------------------------------------------------------+
double CConfluenceEngine::CalculateScore(bool htfAligned, bool obUnmitigated, bool fvgOverlap, bool sweepConfirmed, bool volSpike, bool sessionMatch, bool lowSpread)
{
    double score = 0.0;
    
    if(htfAligned)      score += m_weightHTFBias;
    if(obUnmitigated)   score += m_weightOBUnmitigated;
    if(fvgOverlap)      score += m_weightFVGOverlap;
    if(sweepConfirmed)  score += m_weightSweep;
    if(volSpike)        score += m_weightVolume;
    if(sessionMatch)    score += m_weightSession;
    if(lowSpread)       score += m_weightSpread;
    
    return MathMin(score, 100.0);
}

//+------------------------------------------------------------------+
//| Check Entry Validity                                             |
//+------------------------------------------------------------------+
bool CConfluenceEngine::IsEntryValid(double score, ENUM_TRADING_MODE mode)
{
    if(mode == TRADING_MODE_KILLER_SCALPER)
        return score >= m_thresholdKS;
        
    if(mode == TRADING_MODE_HTF_FOLLOWER)
        return score >= m_thresholdHTF;
        
    return false;
}
