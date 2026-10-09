// Decomposition extraction from CSpikeHunterEngine (behaviour
// preserving).
// Owns the two stateless symbol-semantics helpers that resolved
// which way a detected spike is expected to run:
// IsSpikeSymbolDirectionCertain() — PainX / GainX+FlipX /
// Boom / Crash hard mapping
// DetermineSpikeDirection()       — certain mapping first, then
// the Layer-2 detected sign
// Neither touched engine state beyond the symbol name and the
// detected direction sign, so both are plain statics here. The
// ordering of the family checks and the NormalizeInstrumentSymbol-
// Name()/StringFind() BOOM-before-CRASH sequence are reproduced
// verbatim.
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_DIRECTION_MQH
#define CORE_SCALP_SPIKE_HUNTER_DIRECTION_MQH

#include "../Utils/Instruments.mqh"

// CSpikeHunterDirection — stateless spike direction resolution
class CSpikeHunterDirection
{
public:
// Check if symbol has a certain spike direction
// Returns true and sets direction for PainX/Crash/Boom/GainX
   static bool IsSpikeSymbolDirectionCertain(const string symbol, int &direction)
   {
      // PainX: always SELL (-1)
      if(IsPainSyntheticSymbolName(symbol))
      {
         direction = -1;
         return true;
      }

      // GainX/FlipX: always BUY (+1)
      if(IsGainFlipSyntheticSymbolName(symbol))
      {
         direction = 1;
         return true;
      }

      // Boom/Crash: Boom=BUY(+1), Crash=SELL(-1)
      if(IsBoomCrashSyntheticSymbolName(symbol))
      {
         string normalized = NormalizeInstrumentSymbolName(symbol);
         if(StringFind(normalized, "BOOM") >= 0)
         {
            direction = 1;
            return true;
         }
         if(StringFind(normalized, "CRASH") >= 0)
         {
            direction = -1;
            return true;
         }
      }

      // SFX Vol, FX Vol, SwitchX, and others: direction is not certain
      return false;
   }

// Determine spike direction based on symbol type and detection
// detectedDirectionSign is the Layer-2 accumulated direction sign.
   static int DetermineSpikeDirection(const string symbol, int detectedDirectionSign)
   {
      int certainDir = 0;

      if(IsSpikeSymbolDirectionCertain(symbol, certainDir))
         return certainDir;

      // For SFX Vol, FX Vol, SwitchX: use detected direction from Layer 2
      return detectedDirectionSign;
   }
};

#endif // CORE_SCALP_SPIKE_HUNTER_DIRECTION_MQH
