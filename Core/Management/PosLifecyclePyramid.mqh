// Pyramiding state tracking + layer-add lifecycle extracted from
// PositionLifecycleManager.mqh (Phase H — God Object decomposition)
// Owns: CPyramidState registry + pyramiding configuration.
// Behaviour preserved 1:1 — no logic changes.
#ifndef POS_LIFECYCLE_PYRAMID_MQH
#define POS_LIFECYCLE_PYRAMID_MQH

#include "..\Trading\TradeManager.mqh"
#include "PosLifecycleMagicFilter.mqh"

// AGGRESSIVE: Pyramid state tracking
// NOTE: Using 'class' (not 'struct') because MQL5 does not allow pointers
// to 'struct' types (error 299: "class type expected"). Only class-typed
// objects may be referenced by pointer.
class CPyramidState
{
public:
    int    layer;              // Current pyramid layer (0 = base position)
    double entryPrice;         // Entry price of base position
    double nextStepPips;       // Profit threshold for next pyramid layer
    double baseLotSize;        // Base lot size for calculating pyramid layers
    ulong  baseTicket;         // Base position ticket
    bool   active;             // Whether pyramiding is active for this position

    CPyramidState(void)
    {
        layer = 0;
        entryPrice = 0.0;
        nextStepPips = 0.0;
        baseLotSize = 0.0;
        baseTicket = 0;
        active = false;
    }
};

// Stateful module — held BY VALUE by CPositionLifecycleManager.
class CPosLifecyclePyramid
{
private:
    // AGGRESSIVE: Pyramiding config
    bool   m_pyramidingEnabled;
    double m_pyramidingStepPips;
    double m_pyramidingSizeMultiplier;
    int    m_pyramidingMaxLayers;

    CPyramidState* m_pyramidStates[];  // Array indexed by position ticket
    int            m_pyramidStateCount;

public:
    CPosLifecyclePyramid() :
        m_pyramidingEnabled(false),
        m_pyramidingStepPips(50.0),
        m_pyramidingSizeMultiplier(1.5),
        m_pyramidingMaxLayers(3),
        m_pyramidStateCount(0)
    {}

    ~CPosLifecyclePyramid()
    {
        // Clean up pyramid states
        for(int i = 0; i < m_pyramidStateCount; i++)
        {
            if(CheckPointer(m_pyramidStates[i]) == POINTER_DYNAMIC)
                delete m_pyramidStates[i];
        }
        m_pyramidStateCount = 0;
        ArrayFree(m_pyramidStates);
    }

    //--- AGGRESSIVE: Configure pyramiding
    void Configure(bool enabled, double stepPips, double sizeMultiplier, int maxLayers)
    {
        m_pyramidingEnabled = enabled;
        m_pyramidingStepPips = stepPips;
        m_pyramidingSizeMultiplier = sizeMultiplier;
        m_pyramidingMaxLayers = maxLayers;
    }

    bool IsEnabled() const { return m_pyramidingEnabled; }

    //--- AGGRESSIVE: Pyramiding management
    void ManagePyramiding(CTradeManager* tradeManager, const int magicBase, const int magicMax)
    {
        if(!m_pyramidingEnabled)
            return;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPosLifecycleMagicFilter::IsLifecycleManaged(PositionGetInteger(POSITION_MAGIC),
                                                             PositionGetString(POSITION_COMMENT),
                                                             magicBase, magicMax)) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double lotSize = PositionGetDouble(POSITION_VOLUME);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0) point = 0.00001;

            // Calculate profit in pips
            double profitPips = 0.0;
            if(type == POSITION_TYPE_BUY)
                profitPips = (currentPrice - openPrice) / point;
            else
                profitPips = (openPrice - currentPrice) / point;

            // Find or create pyramid state for this position
            CPyramidState* state = GetPyramidState(ticket);
            if(state == NULL)
            {
                // Initialize pyramid state for new position
                state = CreatePyramidState(ticket, openPrice, lotSize);
                if(state == NULL) continue;
            }

            // Check if we should add a pyramid layer
            if(state.active && state.layer < m_pyramidingMaxLayers && profitPips >= state.nextStepPips)
            {
                // Calculate pyramid lot size
                double pyramidLotSize = state.baseLotSize * MathPow(m_pyramidingSizeMultiplier, state.layer + 1);
                pyramidLotSize = NormalizeDouble(pyramidLotSize, 2);

                // Send pyramid order
                ENUM_ORDER_TYPE orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                string comment = "Pyramid Layer " + IntegerToString(state.layer + 1);
                double entryPriceZero = 0.0;
                double slPipsZero = 0.0;
                double tpPipsZero = 0.0;
                uint magicZero = 0;
                if(tradeManager.OpenPosition(symbol, orderType, pyramidLotSize, entryPriceZero, slPipsZero, tpPipsZero, comment, magicZero))
                {
                    PrintFormat("[PYRAMID] Added layer %d to %s | ticket=%d | lot=%.2f | profit=%.0f pips",
                                state.layer + 1, symbol, ticket, pyramidLotSize, profitPips);

                    // Update pyramid state
                    state.layer++;
                    state.nextStepPips = profitPips + m_pyramidingStepPips;
                }
            }
        }

        // Clean up pyramid states for closed positions
        CleanupPyramidStates();
    }

    //--- AGGRESSIVE: Get pyramid state for a position
    CPyramidState* GetPyramidState(ulong ticket)
    {
        for(int i = 0; i < m_pyramidStateCount; i++)
        {
            if(CheckPointer(m_pyramidStates[i]) == POINTER_DYNAMIC &&
               m_pyramidStates[i].baseTicket == ticket &&
               m_pyramidStates[i].active)
                return m_pyramidStates[i];
        }
        return NULL;
    }

    //--- AGGRESSIVE: Create pyramid state for new position
    CPyramidState* CreatePyramidState(ulong ticket, double entryPrice, double lotSize)
    {
        // Resize array if needed
        if(m_pyramidStateCount >= ArraySize(m_pyramidStates))
            ArrayResize(m_pyramidStates, m_pyramidStateCount + 10);

        CPyramidState* state = new CPyramidState();
        state.layer = 0;
        state.entryPrice = entryPrice;
        state.nextStepPips = m_pyramidingStepPips;
        state.baseLotSize = lotSize;
        state.baseTicket = ticket;
        state.active = true;

        m_pyramidStates[m_pyramidStateCount] = state;
        m_pyramidStateCount++;
        return state;
    }

    //--- AGGRESSIVE: Clean up pyramid states for closed positions
    void CleanupPyramidStates()
    {
        int write = 0;
        for(int i = 0; i < m_pyramidStateCount; i++)
        {
            if(CheckPointer(m_pyramidStates[i]) != POINTER_DYNAMIC)
            {
                // Skip invalid entries, free slot
                continue;
            }

            if(!m_pyramidStates[i].active)
            {
                // Already marked inactive, remove
                delete m_pyramidStates[i];
                m_pyramidStates[i] = NULL;
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
                // Base position closed, free and drop
                PrintFormat("[PYRAMID] Base position %d closed, releasing pyramid state",
                            m_pyramidStates[i].baseTicket);
                delete m_pyramidStates[i];
                m_pyramidStates[i] = NULL;
                continue;
            }

            // Keep, compact
            if(write != i)
                m_pyramidStates[write] = m_pyramidStates[i];
            write++;
        }
        // Null out any remaining slots beyond `write`
        for(int i = write; i < m_pyramidStateCount; i++)
            m_pyramidStates[i] = NULL;
        m_pyramidStateCount = write;
    }
};

#endif // POS_LIFECYCLE_PYRAMID_MQH
