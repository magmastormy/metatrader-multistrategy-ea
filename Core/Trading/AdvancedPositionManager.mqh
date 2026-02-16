//+------------------------------------------------------------------+
//| AdvancedPositionManager.mqh                                      |
//| Advanced position management with trailing stops, break-even, and partial closes |
//+------------------------------------------------------------------+
#ifndef __ADVANCED_POSITION_MANAGER_MQH__
#define __ADVANCED_POSITION_MANAGER_MQH__

#include "../Utils/Enums.mqh"
#include "../Utils/CommonTypes.mqh"
#include "TradeManager.mqh"

//+------------------------------------------------------------------+
//| Position Management Configuration                                |
//+------------------------------------------------------------------+
struct SPositionManagementConfig
{
    bool enableTrailingStop;
    double trailingStartPips;        // Start trailing after X pips profit
    double trailingStepPips;          // Trailing step in pips
    double trailingDistancePips;     // Trailing distance in pips
    
    bool enableBreakeven;
    double breakevenTriggerPips;     // Move to BE after X pips profit
    double breakevenBufferPips;      // Buffer above/below entry
    
    bool enablePartialClose;
    double partialClose1Pips;        // First partial close at X pips
    double partialClose1Percent;     // Close X% at first level
    double partialClose2Pips;        // Second partial close at X pips
    double partialClose2Percent;     // Close X% at second level
    
    bool enableTimeBasedExit;        // Close positions after X hours
    int maxPositionHours;            // Maximum hours to hold position
};

//+------------------------------------------------------------------+
//| Advanced Position Manager                                        |
//+------------------------------------------------------------------+
class CAdvancedPositionManager
{
private:
    CTradeManager* m_tradeManager;
    SPositionManagementConfig m_config;
    long m_managedMagic;
    
    // Position tracking
    struct SPositionTracker
    {
        ulong ticket;
        datetime openTime;
        double entryPrice;
        double initialSL;
        double initialTP;
        bool breakevenActivated;
        bool partialClose1Done;
        bool partialClose2Done;
        double highestProfit;        // Track highest profit for trailing
    };
    
    SPositionTracker m_trackedPositions[];
    
public:
    CAdvancedPositionManager();
    ~CAdvancedPositionManager();
    
    // Configuration
    void SetConfig(const SPositionManagementConfig &config) { m_config = config; }
    void SetTradeManager(CTradeManager* manager) { m_tradeManager = manager; }
    void SetManagedMagic(const long magicNumber) { m_managedMagic = magicNumber; }
    
    // Main management function
    void ManageAllPositions();
    void ManagePosition(ulong ticket);
    
    // Individual management functions
    bool ApplyTrailingStop(ulong ticket, SPositionTracker &tracker);
    bool ApplyBreakeven(ulong ticket, SPositionTracker &tracker);
    bool ApplyPartialClose(ulong ticket, SPositionTracker &tracker);
    bool ApplyTimeBasedExit(ulong ticket, SPositionTracker &tracker);
    
    // Helper functions
    double GetCurrentProfitPips(ulong ticket);
    double GetHighestProfitPips(ulong ticket, SPositionTracker &tracker);
    double NormalizeCloseVolume(const string symbol, const double volume);
    double ResolveMinimumPipDistance(const string symbol, const double configuredPips, const double stopLevelMultiplier = 1.0);
    bool UpdateTracker(ulong ticket, SPositionTracker &tracker);
    int FindTrackerIndex(ulong ticket);
    bool IsManagedPosition(ulong ticket);
    
    // Statistics
    int GetManagedPositionsCount() { return ArraySize(m_trackedPositions); }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CAdvancedPositionManager::CAdvancedPositionManager() :
    m_tradeManager(NULL),
    m_managedMagic(0)
{
    // Default configuration
    m_config.enableTrailingStop = true;
    m_config.trailingStartPips = 20.0;
    m_config.trailingStepPips = 5.0;
    m_config.trailingDistancePips = 15.0;
    
    m_config.enableBreakeven = true;
    m_config.breakevenTriggerPips = 15.0;
    m_config.breakevenBufferPips = 5.0;
    
    m_config.enablePartialClose = true;
    m_config.partialClose1Pips = 30.0;
    m_config.partialClose1Percent = 50.0;  // Close 50% at 30 pips
    m_config.partialClose2Pips = 60.0;
    m_config.partialClose2Percent = 25.0;  // Close 25% more at 60 pips (75% total)
    
    m_config.enableTimeBasedExit = false;
    m_config.maxPositionHours = 24;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CAdvancedPositionManager::~CAdvancedPositionManager()
{
}

//+------------------------------------------------------------------+
//| Manage All Positions                                             |
//+------------------------------------------------------------------+
void CAdvancedPositionManager::ManageAllPositions()
{
    if(m_tradeManager == NULL) return;
    
    // Update tracked positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && IsManagedPosition(ticket))
        {
            int idx = FindTrackerIndex(ticket);
            if(idx < 0)
            {
                // New position - add to tracking
                if(PositionSelectByTicket(ticket))
                {
                    int newSize = ArraySize(m_trackedPositions) + 1;
                    ArrayResize(m_trackedPositions, newSize);
                    
                    m_trackedPositions[newSize - 1].ticket = ticket;
                    m_trackedPositions[newSize - 1].openTime = (datetime)PositionGetInteger(POSITION_TIME);
                    m_trackedPositions[newSize - 1].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                    m_trackedPositions[newSize - 1].initialSL = PositionGetDouble(POSITION_SL);
                    m_trackedPositions[newSize - 1].initialTP = PositionGetDouble(POSITION_TP);
                    m_trackedPositions[newSize - 1].breakevenActivated = false;
                    m_trackedPositions[newSize - 1].partialClose1Done = false;
                    m_trackedPositions[newSize - 1].partialClose2Done = false;
                    m_trackedPositions[newSize - 1].highestProfit = 0.0;
                }
            }
            else
            {
                // Update existing tracker
                UpdateTracker(ticket, m_trackedPositions[idx]);
                ManagePosition(ticket);
            }
        }
    }
    
    // Remove closed positions from tracking
    for(int i = ArraySize(m_trackedPositions) - 1; i >= 0; i--)
    {
        ulong trackedTicket = m_trackedPositions[i].ticket;
        bool shouldRemove = true;

        if(PositionSelectByTicket(trackedTicket))
        {
            if(m_managedMagic <= 0 || PositionGetInteger(POSITION_MAGIC) == m_managedMagic)
                shouldRemove = false;
        }

        if(shouldRemove)
        {
            // Position closed or not managed by this EA - remove from array
            int newSize = ArraySize(m_trackedPositions) - 1;
            for(int j = i; j < newSize; j++)
                m_trackedPositions[j] = m_trackedPositions[j + 1];
            ArrayResize(m_trackedPositions, newSize);
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Position                                                  |
//+------------------------------------------------------------------+
void CAdvancedPositionManager::ManagePosition(ulong ticket)
{
    if(!IsManagedPosition(ticket))
        return;

    int idx = FindTrackerIndex(ticket);
    if(idx < 0) return;

    // Apply management rules in order
    if(m_config.enableBreakeven)
        ApplyBreakeven(ticket, m_trackedPositions[idx]);
    
    if(m_config.enableTrailingStop)
        ApplyTrailingStop(ticket, m_trackedPositions[idx]);
    
    if(m_config.enablePartialClose)
        ApplyPartialClose(ticket, m_trackedPositions[idx]);
    
    if(m_config.enableTimeBasedExit)
        ApplyTimeBasedExit(ticket, m_trackedPositions[idx]);
}

//+------------------------------------------------------------------+
//| Apply Trailing Stop                                              |
//+------------------------------------------------------------------+
bool CAdvancedPositionManager::ApplyTrailingStop(ulong ticket, SPositionTracker &tracker)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    double currentProfitPips = GetCurrentProfitPips(ticket);
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    double trailingStartPips = ResolveMinimumPipDistance(symbol, m_config.trailingStartPips, 1.5);
    
    // Only start trailing after minimum profit
    if(currentProfitPips < trailingStartPips)
        return false;
    
    // Update highest profit
    if(currentProfitPips > tracker.highestProfit)
        tracker.highestProfit = currentProfitPips;
    
    // Calculate new stop loss
    double positionPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentSL = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double newSL = 0.0;
    double stopLevelPips = MathMax((double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL), 10.0);
    double trailingDistancePips = ResolveMinimumPipDistance(symbol, m_config.trailingDistancePips, 1.2);
    double trailingStepPips = MathMax(m_config.trailingStepPips, stopLevelPips * 0.25);
    double trailingDistance = trailingDistancePips * point;
    double trailingStep = trailingStepPips * point;
    
    if(posType == POSITION_TYPE_BUY)
    {
        newSL = positionPrice - trailingDistance;
        
        // Only move SL up
        if(currentSL == 0 || newSL > currentSL + trailingStep)
        {
            double currentTP = PositionGetDouble(POSITION_TP);
            return m_tradeManager.ModifyPosition(ticket, newSL, currentTP);
        }
    }
    else  // SELL
    {
        newSL = positionPrice + trailingDistance;
        
        // Only move SL down
        if(currentSL == 0 || newSL < currentSL - trailingStep)
        {
            double currentTP = PositionGetDouble(POSITION_TP);
            return m_tradeManager.ModifyPosition(ticket, newSL, currentTP);
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Apply Breakeven                                                  |
//+------------------------------------------------------------------+
bool CAdvancedPositionManager::ApplyBreakeven(ulong ticket, SPositionTracker &tracker)
{
    if(tracker.breakevenActivated) return false;
    if(!PositionSelectByTicket(ticket)) return false;
    
    double currentProfitPips = GetCurrentProfitPips(ticket);
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double breakevenTriggerPips = ResolveMinimumPipDistance(symbol, m_config.breakevenTriggerPips, 1.5);
    
    // Only activate after trigger profit
    if(currentProfitPips < breakevenTriggerPips)
        return false;
    
    double entryPrice = tracker.entryPrice;
    double currentSL = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double newSL = 0.0;
    double bufferPips = ResolveMinimumPipDistance(symbol, m_config.breakevenBufferPips, 1.1);
    double buffer = bufferPips * point;
    
    if(posType == POSITION_TYPE_BUY)
    {
        newSL = entryPrice + buffer;
        
        // Only move if better than current SL
        if(currentSL == 0 || newSL > currentSL)
        {
            double currentTP = PositionGetDouble(POSITION_TP);
            if(m_tradeManager.ModifyPosition(ticket, newSL, currentTP))
            {
                tracker.breakevenActivated = true;
                return true;
            }
        }
    }
    else  // SELL
    {
        newSL = entryPrice - buffer;
        
        // Only move if better than current SL
        if(currentSL == 0 || newSL < currentSL)
        {
            double currentTP = PositionGetDouble(POSITION_TP);
            if(m_tradeManager.ModifyPosition(ticket, newSL, currentTP))
            {
                tracker.breakevenActivated = true;
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Apply Partial Close                                              |
//+------------------------------------------------------------------+
bool CAdvancedPositionManager::ApplyPartialClose(ulong ticket, SPositionTracker &tracker)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    double currentProfitPips = GetCurrentProfitPips(ticket);
    double volume = PositionGetDouble(POSITION_VOLUME);
    string symbol = PositionGetString(POSITION_SYMBOL);
    double stopLevelPips = MathMax((double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL), 10.0);
    double partialClose1Trigger = ResolveMinimumPipDistance(symbol, m_config.partialClose1Pips, 2.0);
    double partialClose2Trigger = ResolveMinimumPipDistance(symbol, m_config.partialClose2Pips, 3.0);
    if(partialClose2Trigger < partialClose1Trigger + stopLevelPips)
        partialClose2Trigger = partialClose1Trigger + stopLevelPips;
    
    // First partial close
    if(!tracker.partialClose1Done && currentProfitPips >= partialClose1Trigger)
    {
        double closeVolume = NormalizeCloseVolume(symbol, volume * m_config.partialClose1Percent / 100.0);
        if(closeVolume >= SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN))
        {
            if(m_tradeManager.ClosePositionPartial(ticket, closeVolume, "Partial Close 1"))
            {
                tracker.partialClose1Done = true;
                return true;
            }
        }
    }
    
    // Second partial close
    if(tracker.partialClose1Done && !tracker.partialClose2Done && 
       currentProfitPips >= partialClose2Trigger)
    {
        double remainingVolume = PositionGetDouble(POSITION_VOLUME);
        double closeVolume = NormalizeCloseVolume(symbol, remainingVolume * m_config.partialClose2Percent / 100.0);
        if(closeVolume >= SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN))
        {
            if(m_tradeManager.ClosePositionPartial(ticket, closeVolume, "Partial Close 2"))
            {
                tracker.partialClose2Done = true;
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Apply Time Based Exit                                            |
//+------------------------------------------------------------------+
bool CAdvancedPositionManager::ApplyTimeBasedExit(ulong ticket, SPositionTracker &tracker)
{
    if(!m_config.enableTimeBasedExit) return false;
    if(!PositionSelectByTicket(ticket)) return false;
    
    datetime timeNow = TimeCurrent();
    int hoursOpen = (int)((timeNow - tracker.openTime) / 3600);
    
    if(hoursOpen >= m_config.maxPositionHours)
    {
        // Close position due to time limit
        return m_tradeManager.ClosePosition(ticket);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Current Profit in Pips                                      |
//+------------------------------------------------------------------+
double CAdvancedPositionManager::GetCurrentProfitPips(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return 0.0;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double posPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double profitPips = 0.0;
    if(posType == POSITION_TYPE_BUY)
        profitPips = (posPrice - entryPrice) / point;
    else
        profitPips = (entryPrice - posPrice) / point;
    
    return profitPips;
}

//+------------------------------------------------------------------+
//| Get Highest Profit in Pips                                      |
//+------------------------------------------------------------------+
double CAdvancedPositionManager::GetHighestProfitPips(ulong ticket, SPositionTracker &tracker)
{
    double currentProfit = GetCurrentProfitPips(ticket);
    if(currentProfit > tracker.highestProfit)
        tracker.highestProfit = currentProfit;
    
    return tracker.highestProfit;
}

double CAdvancedPositionManager::NormalizeCloseVolume(const string symbol, const double volume)
{
    if(volume <= 0.0)
        return 0.0;

    double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    if(stepVol <= 0.0)
        stepVol = 0.01;

    int volumeDigits = 0;
    double stepProbe = stepVol;
    while(volumeDigits < 8 && MathAbs(stepProbe - MathRound(stepProbe)) > 1e-8)
    {
        stepProbe *= 10.0;
        volumeDigits++;
    }

    double normalized = MathFloor((volume + 1e-12) / stepVol) * stepVol;
    normalized = NormalizeDouble(normalized, volumeDigits);
    normalized = MathMin(normalized, maxVol);

    if(normalized < minVol)
        return 0.0;

    return normalized;
}

double CAdvancedPositionManager::ResolveMinimumPipDistance(const string symbol, const double configuredPips, const double stopLevelMultiplier)
{
    double effectivePips = MathMax(0.0, configuredPips);
    double stopLevelPoints = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double multiplier = MathMax(1.0, stopLevelMultiplier);
    double brokerFloorPips = MathMax(10.0, stopLevelPoints * multiplier);
    if(effectivePips < brokerFloorPips)
        effectivePips = brokerFloorPips;
    return effectivePips;
}

//+------------------------------------------------------------------+
//| Update Tracker                                                   |
//+------------------------------------------------------------------+
bool CAdvancedPositionManager::UpdateTracker(ulong ticket, SPositionTracker &tracker)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    // Update highest profit
    double currentProfit = GetCurrentProfitPips(ticket);
    if(currentProfit > tracker.highestProfit)
        tracker.highestProfit = currentProfit;
    
    return true;
}

//+------------------------------------------------------------------+
//| Find Tracker Index                                               |
//+------------------------------------------------------------------+
int CAdvancedPositionManager::FindTrackerIndex(ulong ticket)
{
    for(int i = 0; i < ArraySize(m_trackedPositions); i++)
    {
        if(m_trackedPositions[i].ticket == ticket)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Check if position belongs to managed magic scope                 |
//+------------------------------------------------------------------+
bool CAdvancedPositionManager::IsManagedPosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
        return false;

    if(m_managedMagic <= 0)
        return true;

    return (PositionGetInteger(POSITION_MAGIC) == m_managedMagic);
}

#endif // __ADVANCED_POSITION_MANAGER_MQH__

