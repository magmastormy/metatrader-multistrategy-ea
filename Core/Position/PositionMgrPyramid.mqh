//+------------------------------------------------------------------+
//| PositionMgrPyramid.mqh                                           |
//| Extracted from PositionManager.mqh (Phase I decomposition)       |
//|                                                                  |
//| STATEFUL module: owns the pyramiding configuration plus the      |
//| SPyramidState ledger and performs layer additions / cleanup.     |
//| Bodies are copied verbatim from CPositionManager - zero          |
//| behaviour change. SPyramidState stays a NESTED PRIVATE struct    |
//| (as it was inside CPositionManager) so it adds no global symbol. |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_POSITION_POSITION_MGR_PYRAMID_MQH
#define CORE_POSITION_POSITION_MGR_PYRAMID_MQH

#include "../Trading/TradeManager.mqh"     // CTradeManager (complete type, called by pointer)
#include "PositionMgrMagicFilter.mqh"      // CPositionMgrMagicFilter::IsEAOwnedMagic

//+------------------------------------------------------------------+
//| CPositionMgrPyramid                                              |
//+------------------------------------------------------------------+
class CPositionMgrPyramid
{
private:
    // Pyramiding config
    bool                    m_pyramidingEnabled;
    double                  m_pyramidingStepPips;
    double                  m_pyramidingSizeMultiplier;
    int                     m_pyramidingMaxLayers;

    // State
    struct SPyramidState
    {
        ulong       baseTicket;
        int         layer;
        double      entryPrice;
        double      nextStepPips;
        double      baseLotSize;
        bool        active;

        SPyramidState() : baseTicket(0), layer(0), entryPrice(0), nextStepPips(0), baseLotSize(0), active(false) {}
    };

    SPyramidState           m_pyramidStates[];
    int                     m_pyramidStateCount;

    // Find pyramid state by base ticket
    int FindPyramidState(ulong baseTicket)
    {
        for(int i = 0; i < m_pyramidStateCount; i++)
            if(m_pyramidStates[i].baseTicket == baseTicket && m_pyramidStates[i].active)
                return i;
        return -1;
    }

    void CleanupPyramidStates()
    {
        // L8-017: SPyramidState contains only basic data types (ulong, int, double, bool)
        // No indicator handles, order tickets, or dynamic arrays to release.
        // This method simply removes states where the base position no longer exists.
        int write = 0;
        for(int i = 0; i < m_pyramidStateCount; i++)
        {
            if(!m_pyramidStates[i].active)
            {
                continue;
            }

            // Check if base position still exists
            bool positionExists = false;
            for(int j = 0; j < PositionsTotal(); j++)
            {
                ulong ticket = PositionGetTicket(j);
                if(ticket == m_pyramidStates[i].baseTicket)
                {
                    positionExists = true;
                    break;
                }
            }

            if(!positionExists)
            {
                PrintFormat("[PYRAMID] Base position %d closed, releasing pyramid state", m_pyramidStates[i].baseTicket);
                m_pyramidStates[i].active = false;
                continue;
            }

            if(write != i)
                m_pyramidStates[write] = m_pyramidStates[i];
            write++;
        }
        m_pyramidStateCount = write;
    }

public:
    CPositionMgrPyramid() :
        m_pyramidingEnabled(false), m_pyramidingStepPips(50.0), m_pyramidingSizeMultiplier(1.5),
        m_pyramidingMaxLayers(3),
        m_pyramidStateCount(0)
    {
        ArrayResize(m_pyramidStates, 0);
    }

    ~CPositionMgrPyramid()
    {
        // Arrays auto-cleanup
    }

    //--- Mirrors CPositionManager::ConfigurePyramiding()
    void Configure(bool enabled, double stepPips, double sizeMult, int maxLayers)
    {
        m_pyramidingEnabled = enabled; m_pyramidingStepPips = stepPips;
        m_pyramidingSizeMultiplier = sizeMult; m_pyramidingMaxLayers = maxLayers;
    }

    bool IsEnabled() const { return m_pyramidingEnabled; }

    int GetStateCount() const { return m_pyramidStateCount; }

    // --- Pyramiding ---
    void ManagePyramiding(CTradeManager* tradeManager, const int magicNumber)
    {
        if(!m_pyramidingEnabled) return;

        // Implementation similar to PositionLifecycleManager
        // Iterate positions, check profit, add layers
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPositionMgrMagicFilter::IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double lotSize = PositionGetDouble(POSITION_VOLUME);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0) point = 0.00001;

            double profitPips = (type == POSITION_TYPE_BUY)
                ? (currentPrice - openPrice) / point
                : (openPrice - currentPrice) / point;

            int stateIdx = FindPyramidState(ticket);
            if(stateIdx < 0)
            {
                // Create new pyramid state
                SPyramidState state;
                state.baseTicket = ticket;
                state.layer = 0;
                state.entryPrice = openPrice;
                state.nextStepPips = m_pyramidingStepPips;
                state.baseLotSize = lotSize;
                state.active = true;

                if(m_pyramidStateCount >= ArraySize(m_pyramidStates))
                    ArrayResize(m_pyramidStates, m_pyramidStateCount + 10);
                m_pyramidStates[m_pyramidStateCount] = state;
                m_pyramidStateCount++;
                stateIdx = m_pyramidStateCount - 1;
            }

            SPyramidState state = m_pyramidStates[stateIdx];

            if(state.active && state.layer < m_pyramidingMaxLayers && profitPips >= state.nextStepPips)
            {
                double pyramidLotSize = state.baseLotSize * MathPow(m_pyramidingSizeMultiplier, state.layer + 1);
                pyramidLotSize = NormalizeDouble(pyramidLotSize, 2);

                ENUM_ORDER_TYPE orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                string comment = "Pyramid Layer " + IntegerToString(state.layer + 1);

                if(tradeManager.OpenPosition(symbol, orderType, pyramidLotSize, 0.0, 0.0, 0.0, comment, 0))
                {
                    PrintFormat("[PYRAMID] Added layer %d to %s | ticket=%d | lot=%.2f | profit=%.0f pips",
                                state.layer + 1, symbol, ticket, pyramidLotSize, profitPips);

                    state.layer++;
                    state.nextStepPips = profitPips + m_pyramidingStepPips;
                    m_pyramidStates[stateIdx] = state;
                }
            }
        }

        CleanupPyramidStates();
    }
};

#endif // CORE_POSITION_POSITION_MGR_PYRAMID_MQH
