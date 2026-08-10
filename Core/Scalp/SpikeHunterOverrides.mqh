//+------------------------------------------------------------------+
//| SpikeHunterOverrides.mqh                                         |
//| Decomposition extraction from CSpikeHunterEngine (behaviour      |
//| preserving).                                                     |
//|                                                                  |
//| Owns the Batch-102 family override table that used to be the     |
//| loose member pair:                                               |
//|   CSpikeHunterEngine::m_familyOverrides[]                        |
//|   CSpikeHunterEngine::m_familyOverrideCount                      |
//|                                                                  |
//| Moved logic (verbatim):                                          |
//|   FindFamilyOverrideIndex()                                      |
//|   the eight GetEffectiveXxx() resolvers — here they take the     |
//|   symbol plus the base-config fallback instead of a state index, |
//|   so the table has no dependency on the symbol-state array.      |
//|   SetFamilyOverrides()  (temp-struct resize pattern preserved)   |
//|   the [SPIKE-HUNTER-CONFIG] summary loop out of Init()           |
//|                                                                  |
//| Comparison operators (> 0.0 / > 0) and the hasOverrides gate are |
//| reproduced verbatim, so a zero override still falls back to the  |
//| base config value exactly as before.                             |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_OVERRIDES_MQH
#define CORE_SCALP_SPIKE_HUNTER_OVERRIDES_MQH

#include "SpikeHunterTypes.mqh"

//+------------------------------------------------------------------+
//| CSpikeHunterOverrides — stateful per-symbol override table        |
//+------------------------------------------------------------------+
class CSpikeHunterOverrides
{
private:
   SSpikeHunterFamilyOverrides     m_familyOverrides[];
   int                             m_familyOverrideCount;

public:
   CSpikeHunterOverrides() : m_familyOverrideCount(0) {}

   //--- Accessor (was CSpikeHunterEngine::m_familyOverrideCount)
   int Count() const { return m_familyOverrideCount; }

   //+------------------------------------------------------------------+
   //| Find family override index for a symbol (Batch 102)               |
   //+------------------------------------------------------------------+
   int FindFamilyOverrideIndex(const string symbol) const
   {
      for(int i = 0; i < m_familyOverrideCount; i++)
      {
         if(m_familyOverrides[i].symbol == symbol)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Get effective velocity multiplier for a symbol (Batch 102)        |
   //+------------------------------------------------------------------+
   double GetEffectiveVelocityMultiplier(const string symbol, double baseValue) const
   {
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].velocityMultiplier > 0.0)
         return m_familyOverrides[oi].velocityMultiplier;
      return baseValue;
   }

   //+------------------------------------------------------------------+
   //| Get effective min consecutive ticks for a symbol (Batch 102)      |
   //+------------------------------------------------------------------+
   int GetEffectiveMinConsecutiveTicks(const string symbol, int baseValue) const
   {
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].minConsecutiveTicks > 0)
         return m_familyOverrides[oi].minConsecutiveTicks;
      return baseValue;
   }

   //+------------------------------------------------------------------+
   //| Get effective ATR compression ratio for a symbol (Batch 102)      |
   //+------------------------------------------------------------------+
   double GetEffectiveATRCompressionRatio(const string symbol, double baseValue) const
   {
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].atrCompressionRatio > 0.0)
         return m_familyOverrides[oi].atrCompressionRatio;
      return baseValue;
   }

   //+------------------------------------------------------------------+
   //| Get effective SL ATR multiplier for a symbol (Batch 102)          |
   //+------------------------------------------------------------------+
   double GetEffectiveSLAtrMultiplier(const string symbol, double baseValue) const
   {
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].slAtrMultiplier > 0.0)
         return m_familyOverrides[oi].slAtrMultiplier;
      return baseValue;
   }

   //+------------------------------------------------------------------+
   //| Get effective TP ATR multiplier for a symbol (Batch 102)          |
   //+------------------------------------------------------------------+
   double GetEffectiveTPAtrMultiplier(const string symbol, double baseValue) const
   {
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].tpAtrMultiplier > 0.0)
         return m_familyOverrides[oi].tpAtrMultiplier;
      return baseValue;
   }

   //+------------------------------------------------------------------+
   //| Get effective magic offset for a symbol (Batch 102)               |
   //+------------------------------------------------------------------+
   int GetEffectiveMagicOffset(const string symbol, int baseValue) const
   {
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].magicOffset > 0)
         return m_familyOverrides[oi].magicOffset;
      return baseValue;
   }

   //+------------------------------------------------------------------+
   //| Get effective cooldown for a symbol (Batch 102)                   |
   //+------------------------------------------------------------------+
   int GetEffectiveCooldownMs(const string symbol, int baseValue) const
   {
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].cooldownMs > 0)
         return m_familyOverrides[oi].cooldownMs;
      return baseValue;
   }

   //+------------------------------------------------------------------+
   //| Get effective min confluence for a symbol (Batch 102)             |
   //+------------------------------------------------------------------+
   int GetEffectiveMinConfluence(const string symbol, int baseValue) const
   {
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].minConfluence > 0)
         return m_familyOverrides[oi].minConfluence;
      return baseValue;
   }

   //+------------------------------------------------------------------+
   //| Set family-specific overrides for a symbol (Batch 102)            |
   //+------------------------------------------------------------------+
   void SetFamilyOverrides(const string symbol, double velMult, int minTicks, double atrRatio,
                           double slMult, double tpMult, int magicOff, int cooldown, int minConf)
   {
      // Check if override already exists for this symbol
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0)
      {
         // Update existing override
         m_familyOverrides[oi].velocityMultiplier  = velMult;
         m_familyOverrides[oi].minConsecutiveTicks = minTicks;
         m_familyOverrides[oi].atrCompressionRatio = atrRatio;
         m_familyOverrides[oi].slAtrMultiplier     = slMult;
         m_familyOverrides[oi].tpAtrMultiplier     = tpMult;
         m_familyOverrides[oi].magicOffset         = magicOff;
         m_familyOverrides[oi].cooldownMs          = cooldown;
         m_familyOverrides[oi].minConfluence       = minConf;
         m_familyOverrides[oi].hasOverrides        = true;
         PrintFormat("[SPIKE-HUNT-FAMILY] Updated overrides for %s: vel=%.1f ticks=%d atrRatio=%.2f sl=%.1f tp=%.1f magic=%d cooldown=%d conf=%d",
                     symbol, velMult, minTicks, atrRatio, slMult, tpMult, magicOff, cooldown, minConf);
         return;
      }

      // Add new override using temp struct pattern for string members
      int newSize = m_familyOverrideCount + 1;
      SSpikeHunterFamilyOverrides tempOverrides[];
      ArrayResize(tempOverrides, newSize);
      for(int i = 0; i < m_familyOverrideCount; i++)
         tempOverrides[i] = m_familyOverrides[i];
      ArrayResize(m_familyOverrides, newSize);
      for(int i = 0; i < m_familyOverrideCount; i++)
         m_familyOverrides[i] = tempOverrides[i];

      m_familyOverrides[m_familyOverrideCount].symbol                = symbol;
      m_familyOverrides[m_familyOverrideCount].velocityMultiplier    = velMult;
      m_familyOverrides[m_familyOverrideCount].minConsecutiveTicks   = minTicks;
      m_familyOverrides[m_familyOverrideCount].atrCompressionRatio   = atrRatio;
      m_familyOverrides[m_familyOverrideCount].slAtrMultiplier       = slMult;
      m_familyOverrides[m_familyOverrideCount].tpAtrMultiplier       = tpMult;
      m_familyOverrides[m_familyOverrideCount].magicOffset           = magicOff;
      m_familyOverrides[m_familyOverrideCount].cooldownMs            = cooldown;
      m_familyOverrides[m_familyOverrideCount].minConfluence         = minConf;
      m_familyOverrides[m_familyOverrideCount].hasOverrides          = true;
      m_familyOverrideCount++;

      PrintFormat("[SPIKE-HUNT-FAMILY] Set overrides for %s: vel=%.1f ticks=%d atrRatio=%.2f sl=%.1f tp=%.1f magic=%d cooldown=%d conf=%d",
                  symbol, velMult, minTicks, atrRatio, slMult, tpMult, magicOff, cooldown, minConf);
   }

   //+------------------------------------------------------------------+
   //| Log effective confluence config per symbol family                 |
   //| (was the trailing block of CSpikeHunterEngine::Init)              |
   //+------------------------------------------------------------------+
   void LogConfigSummary(int baseMinConfluence) const
   {
      PrintFormat("[SPIKE-HUNTER-CONFIG] Base minConfluence=%d/3 | familyOverrides=%d",
                  baseMinConfluence, m_familyOverrideCount);
      for(int i = 0; i < m_familyOverrideCount; i++)
      {
         if(m_familyOverrides[i].hasOverrides)
         {
            int effConf = (m_familyOverrides[i].minConfluence > 0) ? m_familyOverrides[i].minConfluence : baseMinConfluence;
            PrintFormat("[SPIKE-HUNTER-CONFIG] %s | effectiveMinConfluence=%d/3 (override=%d base=%d)",
                        m_familyOverrides[i].symbol, effConf,
                        m_familyOverrides[i].minConfluence, baseMinConfluence);
         }
      }
   }
};

#endif // CORE_SCALP_SPIKE_HUNTER_OVERRIDES_MQH
