// Decomposition extraction from CFastScalpEngine (behaviour
// preserving).
// Owns the scalp position tracking array that used to be two loose
// members on CFastScalpEngine:
// SScalpPositionState m_scalpPositions[20]; int m_scalpPositionCount;
// Moved methods (bodies verbatim):
// RegisterScalpPosition(), RemoveScalpPosition(),
// FindScalpPositionState(), CountScalpPositions(),
// IsScalpPosition()
// CountScalpPositions()/IsScalpPosition() scan the terminal, not
// the local array, so they are `static`.
// Element mutation is exposed through MarkPartialClosed() /
// MarkBreakevenSet() because MQL5 cannot return a struct by
// reference; callers read a snapshot via GetState() and mirror the
// flag locally, which reproduces the original in-place semantics.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_POSITION_TRACKER_MQH
#define CORE_SCALP_FAST_SCALP_POSITION_TRACKER_MQH

#include "FastScalpTypes.mqh"

// CFastScalpPositionTracker — stateful scalp position registry
class CFastScalpPositionTracker
{
private:
   // Scalp position tracking (moved verbatim from CFastScalpEngine)
   SScalpPositionState       m_scalpPositions[20];
   int                       m_scalpPositionCount;

public:
   CFastScalpPositionTracker() : m_scalpPositionCount(0)
   {
      // Batch 152 (S-M-04): field-wise reset - ZeroMemory corrupts the string
      // member's reference count (see SScalpPositionState::Reset).
      for(int i = 0; i < ArraySize(m_scalpPositions); i++)
         m_scalpPositions[i].Reset();
   }

   //--- Number of tracked scalp positions
   int Count() const { return m_scalpPositionCount; }

   //--- Destructor-time reset (was `m_scalpPositionCount = 0;`)
   void Reset() { m_scalpPositionCount = 0; }

   //--- Ticket of the tracked slot at `index` (0 when out of range)
   ulong TicketAt(int index) const
   {
      if(index < 0 || index >= m_scalpPositionCount)
         return 0;
      return m_scalpPositions[index].ticket;
   }

   //--- Snapshot of the tracked slot at `index`
   bool GetState(int index, SScalpPositionState &outState) const
   {
      if(index < 0 || index >= m_scalpPositionCount)
         return false;
      outState = m_scalpPositions[index];
      return true;
   }

   //--- In-place flag mutation (was `m_scalpPositions[i].partialClosed = true;`)
   void MarkPartialClosed(int index)
   {
      if(index < 0 || index >= m_scalpPositionCount)
         return;
      m_scalpPositions[index].partialClosed = true;
   }

   //--- In-place flag mutation (was `m_scalpPositions[i].breakevenSet = true;`)
   void MarkBreakevenSet(int index)
   {
      if(index < 0 || index >= m_scalpPositionCount)
         return;
      m_scalpPositions[index].breakevenSet = true;
   }

// Register a scalp position in the tracking array
   void RegisterScalpPosition(ulong ticket, string symbol, double entryPrice,
                               double sl, double tp, double oneRPrice)
   {
      if(m_scalpPositionCount >= ArraySize(m_scalpPositions))
         return;

      m_scalpPositions[m_scalpPositionCount].ticket          = ticket;
      m_scalpPositions[m_scalpPositionCount].symbol          = symbol;
      m_scalpPositions[m_scalpPositionCount].breakevenSet    = false;
      m_scalpPositions[m_scalpPositionCount].partialClosed   = false;
      m_scalpPositions[m_scalpPositionCount].entryPrice      = entryPrice;
      m_scalpPositions[m_scalpPositionCount].originalSL      = sl;
      m_scalpPositions[m_scalpPositionCount].originalTP      = tp;
      m_scalpPositions[m_scalpPositionCount].oneRProfitPrice = oneRPrice;
      m_scalpPositionCount++;
   }

// Remove a scalp position from tracking by ticket
   void RemoveScalpPosition(ulong ticket)
   {
      for(int i = 0; i < m_scalpPositionCount; i++)
      {
         if(m_scalpPositions[i].ticket == ticket)
         {
            // Shift remaining
            for(int j = i; j < m_scalpPositionCount - 1; j++)
               m_scalpPositions[j] = m_scalpPositions[j + 1];
            m_scalpPositionCount--;
            // Clear last slot (field-wise - Batch 152 S-M-04)
            m_scalpPositions[m_scalpPositionCount].Reset();
            return;
         }
      }
   }

   int FindScalpPositionState(ulong ticket) const
   {
      for(int i = 0; i < m_scalpPositionCount; i++)
      {
         if(m_scalpPositions[i].ticket == ticket)
            return i;
      }
      return -1;
   }

// Count positions with "SCALP" in comment
   static int CountScalpPositions()
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionSelectByTicket(ticket))
         {
            string comment = PositionGetString(POSITION_COMMENT);
            // Batch 170: prefix, not substring. "ATR-SCALP" contains "SCALP", so the
            // old test made this engine claim the ATR scalp engine's positions - and
            // FastScalpExit would then close them.
            if(StringFind(comment, "SCALP") == 0)
               count++;
         }
      }
      return count;
   }

// Check if a position is a scalp position
   static bool IsScalpPosition(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
         return false;
      string comment = PositionGetString(POSITION_COMMENT);
      return (StringFind(comment, "SCALP") == 0);
   }
};

#endif // CORE_SCALP_FAST_SCALP_POSITION_TRACKER_MQH
