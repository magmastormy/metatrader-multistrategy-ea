// Per-symbol CTrade pool + magic offsets + EA-owned ticket cache
// Extracted from Core/Trading/TradeManager.mqh (God-Object split).
// This module OWNS three state blocks that used to live directly
// inside CTradeManager:
// 1. m_symbolTrades[] / m_symbolTradeCount   (L10-013)
// one CTrade instance per symbol, so concurrent multi-symbol
// sends never race on a single shared CTrade.
// 2. m_magicOffsets[] / m_magicOffsetCount
// family-specific magic-number differentiation per symbol.
// 3. m_eaOwnedPositionTickets[] / m_eaOwnedPositionCount (L12-008)
// O(1) EA-owned position iteration cache.
// STATE OWNERSHIP: CTradeManager holds this class BY VALUE and
// keeps thin forwarders with the original signatures, so every
// existing call site is textually unchanged.
// NO BACK-POINTER: GetSymbolTrade() needs four CTradeManager
// configuration values (magic / slippage / fill mode / async mode).
// They are passed in as parameters rather than read through a
// back-pointer, keeping this module free of any dependency on
// CTradeManager (same pattern as CPositionStateTracker).
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_MGR_SYMBOL_TRADE_REGISTRY_MQH
#define CORE_TRADING_TRADE_MGR_SYMBOL_TRADE_REGISTRY_MQH

#include <Trade/Trade.mqh>

// Per-symbol magic offset for family-specific magic number differentiation
// (moved verbatim out of CTradeManager's translation unit position; it stays
//  a top-level struct so any existing reference keeps resolving).
struct SSymbolMagicOffset
{
    string   symbol;
    long     magicOffset;
    bool     hasOffset;

    SSymbolMagicOffset()
    {
        symbol      = "";
        magicOffset = 0;
        hasOffset   = false;
    }
};

class CTradeMgrSymbolTradeRegistry
{
private:
    // Per-symbol CTrade instances to avoid race conditions in multi-symbol trading (L10-013)
    struct SSymbolTradeObject {
        string symbol;
        CTrade trade;
        bool initialized;
        SSymbolTradeObject() : symbol(""), trade(), initialized(false) {}
    };
    SSymbolTradeObject m_symbolTrades[];
    int m_symbolTradeCount;

    // Per-symbol magic offset for family-specific magic number differentiation
    SSymbolMagicOffset m_magicOffsets[];
    int m_magicOffsetCount;

    // EA-owned position ticket cache for O(1) position management (L12-008)
    ulong m_eaOwnedPositionTickets[];
    int m_eaOwnedPositionCount;

public:
    CTradeMgrSymbolTradeRegistry() : m_symbolTradeCount(0),
                                     m_magicOffsetCount(0),
                                     m_eaOwnedPositionCount(0)
    {
        ArrayResize(m_symbolTrades, 0);
        ArrayResize(m_magicOffsets, 0);
        ArrayResize(m_eaOwnedPositionTickets, 0);
    }

// Reset the per-symbol CTrade pool (called from Initialize)
    void ResetSymbolTrades()
    {
        // L10-013: Initialize per-symbol CTrade array
        m_symbolTradeCount = 0;
        ArrayResize(m_symbolTrades, 0);
    }

// Release dynamic magic-offset storage (called from Deinit/dtor)
    void FreeMagicOffsets()
    {
        ArrayFree(m_magicOffsets);
    }

// Get or create per-symbol CTrade instance (L10-013)
    CTrade* GetSymbolTrade(const string symbol,
                           const long magicNumber,
                           const uint slippage,
                           const ENUM_ORDER_TYPE_FILLING orderFillMode,
                           const bool useAsyncMode)
    {
        // Search for existing instance
        for(int i = 0; i < m_symbolTradeCount; i++)
        {
            if(m_symbolTrades[i].symbol == symbol)
            {
                if(!m_symbolTrades[i].initialized)
                {
                    m_symbolTrades[i].trade.SetExpertMagicNumber(magicNumber);
                    m_symbolTrades[i].trade.SetDeviationInPoints(slippage);
                    m_symbolTrades[i].trade.SetTypeFilling(orderFillMode);
                    m_symbolTrades[i].trade.SetAsyncMode(useAsyncMode);
                    m_symbolTrades[i].initialized = true;
                }
                return GetPointer(m_symbolTrades[i].trade);
            }
        }

        // Create new instance
        int newSize = m_symbolTradeCount + 1;
        ArrayResize(m_symbolTrades, newSize);
        m_symbolTrades[m_symbolTradeCount].symbol = symbol;
        m_symbolTrades[m_symbolTradeCount].trade.SetExpertMagicNumber(magicNumber);
        m_symbolTrades[m_symbolTradeCount].trade.SetDeviationInPoints(slippage);
        m_symbolTrades[m_symbolTradeCount].trade.SetTypeFilling(orderFillMode);
        m_symbolTrades[m_symbolTradeCount].trade.SetAsyncMode(useAsyncMode);
        m_symbolTrades[m_symbolTradeCount].initialized = true;
        m_symbolTradeCount++;

        return GetPointer(m_symbolTrades[m_symbolTradeCount - 1].trade);
    }

// L10-013: Update all per-symbol CTrade instances
    void UpdatePerSymbolSlippage(const uint slippage)
    {
        for(int i = 0; i < m_symbolTradeCount; i++)
        {
            if(m_symbolTrades[i].initialized)
                m_symbolTrades[i].trade.SetDeviationInPoints(slippage);
        }
    }

    void UpdatePerSymbolMagicNumber(const long magicNumber)
    {
        for(int i = 0; i < m_symbolTradeCount; i++)
        {
            if(m_symbolTrades[i].initialized)
                m_symbolTrades[i].trade.SetExpertMagicNumber(magicNumber);
        }
    }

    void UpdatePerSymbolFillMode(const ENUM_ORDER_TYPE_FILLING mode)
    {
        for(int i = 0; i < m_symbolTradeCount; i++)
        {
            if(m_symbolTrades[i].initialized)
                m_symbolTrades[i].trade.SetTypeFilling(mode);
        }
    }

    void UpdatePerSymbolAsyncMode(const bool enabled)
    {
        for(int i = 0; i < m_symbolTradeCount; i++)
        {
            if(m_symbolTrades[i].initialized)
                m_symbolTrades[i].trade.SetAsyncMode(enabled);
        }
    }

    void SetMagicOffsetForSymbol(const string symbol, int offset)
    {
        // Find existing
        for(int i = 0; i < m_magicOffsetCount; i++)
        {
            if(m_magicOffsets[i].symbol == symbol)
            {
                m_magicOffsets[i].magicOffset = offset;
                m_magicOffsets[i].hasOffset = true;
                return;
            }
        }
        // Add new using temp struct pattern for string members
        int newSize = m_magicOffsetCount + 1;
        SSymbolMagicOffset tempOffsets[];
        ArrayResize(tempOffsets, newSize);
        for(int i = 0; i < m_magicOffsetCount; i++)
            tempOffsets[i] = m_magicOffsets[i];
        ArrayResize(m_magicOffsets, newSize);
        for(int i = 0; i < m_magicOffsetCount; i++)
            m_magicOffsets[i] = tempOffsets[i];
        m_magicOffsets[m_magicOffsetCount].symbol = symbol;
        m_magicOffsets[m_magicOffsetCount].magicOffset = offset;
        m_magicOffsets[m_magicOffsetCount].hasOffset = true;
        m_magicOffsetCount++;
    }

    int GetMagicOffsetForSymbol(const string symbol) const
    {
        for(int i = 0; i < m_magicOffsetCount; i++)
        {
            if(m_magicOffsets[i].symbol == symbol && m_magicOffsets[i].hasOffset)
                return (int)m_magicOffsets[i].magicOffset;
        }
        return 0;
    }

// EA-owned position ticket cache helpers (L12-008)
    void AddEAOwnedPosition(ulong ticket)
    {
        if(ticket == 0) return;

        // Check if already in cache
        for(int i = 0; i < m_eaOwnedPositionCount; i++)
        {
            if(m_eaOwnedPositionTickets[i] == ticket)
                return; // Already cached
        }

        int newSize = m_eaOwnedPositionCount + 1;
        ArrayResize(m_eaOwnedPositionTickets, newSize);
        m_eaOwnedPositionTickets[m_eaOwnedPositionCount] = ticket;
        m_eaOwnedPositionCount++;
    }

    void RemoveEAOwnedPosition(ulong ticket)
    {
        if(ticket == 0) return;

        for(int i = 0; i < m_eaOwnedPositionCount; i++)
        {
            if(m_eaOwnedPositionTickets[i] == ticket)
            {
                // Shift remaining elements
                for(int j = i; j < m_eaOwnedPositionCount - 1; j++)
                {
                    m_eaOwnedPositionTickets[j] = m_eaOwnedPositionTickets[j + 1];
                }
                m_eaOwnedPositionCount--;
                ArrayResize(m_eaOwnedPositionTickets, m_eaOwnedPositionCount);
                return;
            }
        }
    }

    void ClearEAOwnedPositions()
    {
        m_eaOwnedPositionCount = 0;
        ArrayResize(m_eaOwnedPositionTickets, 0);
    }

    int GetEAOwnedPositionCount() const
    {
        return m_eaOwnedPositionCount;
    }

    ulong GetEAOwnedPositionTicket(int index) const
    {
        if(index >= 0 && index < m_eaOwnedPositionCount)
            return m_eaOwnedPositionTickets[index];
        return 0;
    }
};

#endif // CORE_TRADING_TRADE_MGR_SYMBOL_TRADE_REGISTRY_MQH
//+------------------------------------------------------------------+
