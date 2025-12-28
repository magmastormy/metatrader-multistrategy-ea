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
    bool UpdateTracker(ulong ticket, SPositionTracker &tracker);
    int FindTrackerIndex(ulong ticket);
    
    // Statistics
    int GetManagedPositionsCount() { return ArraySize(m_trackedPositions); }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CAdvancedPositionManager::CAdvancedPositionManager() :
    m_tradeManager(NULL)
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
        if(ticket > 0)
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
        if(!PositionSelectByTicket(m_trackedPositions[i].ticket))
        {
            // Position closed - remove from array
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
    int idx = FindTrackerIndex(ticket);
    if(idx < 0) return;
    
    SPositionTracker tracker = m_trackedPositions[idx];
    
    // Apply management rules in order
    if(m_config.enableBreakeven)
        ApplyBreakeven(ticket, tracker);
    
    if(m_config.enableTrailingStop)
        ApplyTrailingStop(ticket, tracker);
    
    if(m_config.enablePartialClose)
        ApplyPartialClose(ticket, tracker);
    
    if(m_config.enableTimeBasedExit)
        ApplyTimeBasedExit(ticket, tracker);
}

//+------------------------------------------------------------------+
//| Apply Trailing Stop                                              |
//+------------------------------------------------------------------+
bool CAdvancedPositionManager::ApplyTrailingStop(ulong ticket, SPositionTracker &tracker)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    double currentProfitPips = GetCurrentProfitPips(ticket);
    
    // Only start trailing after minimum profit
    if(currentProfitPips < m_config.trailingStartPips)
        return false;
    
    // Update highest profit
    if(currentProfitPips > tracker.highestProfit)
        tracker.highestProfit = currentProfitPips;
    
    // Calculate new stop loss
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double positionPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentSL = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double newSL = 0.0;
    double trailingDistance = m_config.trailingDistancePips * point;
    
    if(posType == POSITION_TYPE_BUY)
    {
        newSL = positionPrice - trailingDistance;
        
        // Only move SL up
        if(currentSL == 0 || newSL > currentSL + m_config.trailingStepPips * point)
        {
            double currentTP = PositionGetDouble(POSITION_TP);
            return m_tradeManager.ModifyPosition(ticket, newSL, currentTP);
        }
    }
    else  // SELL
    {
        newSL = positionPrice + trailingDistance;
        
        // Only move SL down
        if(currentSL == 0 || newSL < currentSL - m_config.trailingStepPips * point)
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
    
    // Only activate after trigger profit
    if(currentProfitPips < m_config.breakevenTriggerPips)
        return false;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double entryPrice = tracker.entryPrice;
    double currentSL = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double newSL = 0.0;
    double buffer = m_config.breakevenBufferPips * point;
    
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
    
    // First partial close
    if(!tracker.partialClose1Done && currentProfitPips >= m_config.partialClose1Pips)
    {
        double closeVolume = NormalizeDouble(volume * m_config.partialClose1Percent / 100.0, 2);
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
       currentProfitPips >= m_config.partialClose2Pips)
    {
        double remainingVolume = PositionGetDouble(POSITION_VOLUME);
        double closeVolume = NormalizeDouble(remainingVolume * m_config.partialClose2Percent / 100.0, 2);
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

#endif // __ADVANCED_POSITION_MANAGER_MQH__

