//+------------------------------------------------------------------+
//| PositionManager.mqh                                              |
//| Position lifecycle management - breakeven, trailing, SRE,        |
//| structural invalidation, safe mode operations                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#ifndef CORE_POSITION_MANAGER_MQH
#define CORE_POSITION_MANAGER_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Utils/Instruments.mqh"
#include "../Cache/ATRCache.mqh"
#include "../Engines/MarketAnalysis.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Risk/PortfolioRiskManager.mqh"

#define MAX_POSITION_STATES 100
#define MAX_TRAILING_STATES 500

// Position state tracking for modification cooldowns
struct SPositionState
{
    ulong ticket;
    double lastSL;
    double lastTP;
    datetime lastModified;
    datetime breakevenSetTime;
    datetime trailingActivatedTime;
    int breakevenLevel;
    bool breakevenDone;
    bool trailingActive;

    SPositionState() : ticket(0), lastSL(0), lastTP(0), lastModified(0),
                       breakevenSetTime(0), trailingActivatedTime(0), breakevenLevel(0),
                       breakevenDone(false), trailingActive(false) {}
};

// Trailing stop state per position
struct STrailingState
{
    ulong positionTicket;
    double highestPrice;    // For BUY trailing
    double lowestPrice;     // For SELL trailing
    double currentTrailSL;
    datetime lastUpdate;
    bool isATRBased;
    double atrMultiplier;

    STrailingState() : positionTicket(0), highestPrice(0), lowestPrice(0),
                       currentTrailSL(0), lastUpdate(0), isATRBased(false), atrMultiplier(2.0) {}
};

class CPositionManager
{
private:
    CTrade m_trade;
    CPositionInfo m_positionInfo;
    CSymbolInfo m_symbolInfo;
    CATRCache m_atrCache;

    // Dependencies
    CUnifiedRiskManager* m_unifiedRiskManager;
    CPortfolioRiskManager* m_portfolioRiskManager;
    CMarketAnalysis* m_marketAnalysis;
    CEnhancedErrorHandler* m_errorHandler;

    // Position states for modification tracking
    SPositionState m_positionStates[MAX_POSITION_STATES];
    int m_stateCount;

    // Trailing states
    STrailingState m_trailingStates[MAX_TRAILING_STATES];
    int m_trailingCount;

    // Configuration
    int m_minModifyIntervalSec;
    bool m_useATRTrailingDefault;
    double m_defaultATRMultiplier;

    // Statistics
    int m_totalBreakevenMoves;
    int m_totalTrailingActivations;
    int m_totalSRETriggers;
    int m_totalStructuralInvalidations;
    int m_totalSafeModeClosures;

public:
    // Configuration structures
    struct SREConfig
    {
        double breathingRoomPips;
        double lastStandZonePips;
        bool profitGuardEnabled;
        double profitGuardThreshold;

        SREConfig() : breathingRoomPips(20), lastStandZonePips(50),
                      profitGuardEnabled(true), profitGuardThreshold(0.25) {}
    };

    struct LifecycleConfig
    {
        double breakevenBuffer;
        double trailingDistance;
        double trailingStep;
        bool useATRTrailing;
        double atrMultiplier;
        bool safeModeEnabled;
        int safeModePartialPercent;

        LifecycleConfig() : breakevenBuffer(20), trailingDistance(50), trailingStep(10),
                           useATRTrailing(false), atrMultiplier(2.0), safeModeEnabled(false),
                           safeModePartialPercent(50) {}
    };

    struct SafeModeConfig
    {
        bool enabled;
        double maxRiskPerTrade;
        double maxDailyDrawdown;
        int maxPositions;

        SafeModeConfig() : enabled(false), maxRiskPerTrade(0.5), maxDailyDrawdown(3.0), maxPositions(2) {}
    };

    CPositionManager() : m_minModifyIntervalSec(5), m_useATRTrailingDefault(false),
                         m_defaultATRMultiplier(2.0), m_stateCount(0), m_trailingCount(0),
                         m_totalBreakevenMoves(0), m_totalTrailingActivations(0),
                         m_totalSRETriggers(0), m_totalStructuralInvalidations(0),
                         m_totalSafeModeClosures(0)
    {
        ZeroMemory(m_positionStates);
        ZeroMemory(m_trailingStates);
    }

    ~CPositionManager() {}

    // Dependencies
    void SetDependencies(CUnifiedRiskManager* risk, CPortfolioRiskManager* portfolio,
                         CMarketAnalysis* market, CEnhancedErrorHandler* handler)
    {
        m_unifiedRiskManager = risk;
        m_portfolioRiskManager = portfolio;
        m_marketAnalysis = market;
        m_errorHandler = handler;
    }

    // Initialize with trade object
    bool Initialize()
    {
        m_trade.SetExpertMagicNumber(0);
        m_trade.SetDeviationInPoints(20);
        m_trade.SetTypeFilling(ORDER_FILLING_FOK);
        return true;
    }

    // Main position management entry point
    void ManageAllPositions(const LifecycleConfig &config, const SREConfig &sreConfig,
                           const SafeModeConfig &safeConfig);

    // Individual position management
    bool ManagePosition(const ulong ticket, const LifecycleConfig &config,
                       const SREConfig &sreConfig, const SafeModeConfig &safeConfig);

    // Breakeven
    bool MoveToBreakeven(const ulong ticket, const double bufferPips);
    bool CheckBreakevenCondition(const ulong ticket, const double bufferPips);
    int FindPositionState(ulong ticket);

    // Trailing stop
    bool SetTrailingStop(const ulong ticket, const double distance, const double step,
                        const bool useATR = false, const double atrMult = 2.0);
    bool UpdateTrailingStop(const ulong ticket);
    bool CheckTrailingCondition(const ulong ticket, const double distance, const double step,
                               const bool useATR, const double atrMult);

    // Signal Reversal Exit (SRE)
    bool CheckSRECondition(const ulong ticket, const double breathingRoomPips,
                          const double lastStandZonePips, const bool profitGuardEnabled,
                          const double profitGuardThreshold);
    bool ExecuteSRE(const ulong ticket, const string reason);

    // Structural Invalidation
    bool CheckStructuralInvalidation(const ulong ticket);
    bool ExecuteStructuralInvalidation(const ulong ticket, const string reason);

    // Safe Mode
    bool CheckSafeMode(const string symbol, const SafeModeConfig &config);
    bool ExecuteSafeModeClosures(const SafeModeConfig &config);

    // Utility
    double GetUnrealizedPips(const ulong ticket);
    double GetPositionRiskPercent(const ulong ticket);
    void UpdatePositionState(const ulong ticket, const double sl, const double tp);
    void RemovePositionState(int index);

    // Statistics
    void GetStatistics(int &breakevenMoves, int &trailingActivations, 
                       int &sreTriggers, int &structuralInvalidations, int &safeModeClosures) const
    {
        breakevenMoves = m_totalBreakevenMoves;
        trailingActivations = m_totalTrailingActivations;
        sreTriggers = m_totalSRETriggers;
        structuralInvalidations = m_totalStructuralInvalidations;
        safeModeClosures = m_totalSafeModeClosures;
    }

    // Configuration
    void SetMinModifyIntervalSec(int seconds) { m_minModifyIntervalSec = MathMax(1, seconds); }
    void SetDefaultATRTrailing(bool useATR, double mult = 2.0) 
    { 
        m_useATRTrailingDefault = useATR; 
        m_defaultATRMultiplier = mult; 
    }

private:
    // Internal helpers
    bool ModifyPositionStops(const ulong ticket, const double newSL, const double newTP);
    double CalculateATRTrailingDistance(const string symbol, double atrMult);
    int FindTrailingState(ulong ticket);
    bool IsModificationCooldownExpired(ulong ticket);
    void LogPositionAction(const string action, const ulong ticket, const string details = "");
};

#endif // CORE_POSITION_MANAGER_MQH