//+------------------------------------------------------------------+
//| FamilyStrategyWeightMatrix.mqh                                    |
//| Per-family cluster weight multipliers for synthetics              |
//| Implements I1 from problems.md                                    |
//+------------------------------------------------------------------+
#ifndef CORE_ENGINES_FAMILY_STRATEGY_WEIGHT_MATRIX_MQH
#define CORE_ENGINES_FAMILY_STRATEGY_WEIGHT_MATRIX_MQH

#include "../Processing/DerivAssetProfiler.mqh"
#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Per-family cluster weight multipliers                             |
//+------------------------------------------------------------------+
struct SFamilyClusterWeights
{
   double trend;
   double meanReversion;
   double structure;
   double scalp;
};

//+------------------------------------------------------------------+
//| Family Strategy Weight Matrix                                     |
//| Overrides default cluster weights based on detected Deriv family  |
//+------------------------------------------------------------------+
class CFamilyStrategyWeightMatrix
{
private:
   SFamilyClusterWeights m_weights[19]; // indexed by ENUM_DERIV_FAMILY
   bool m_initialized;

   void SetWeights(ENUM_DERIV_FAMILY family, double trend, double meanRev, double structure, double scalp)
   {
      m_weights[family].trend          = trend;
      m_weights[family].meanReversion  = meanRev;
      m_weights[family].structure      = structure;
      m_weights[family].scalp          = scalp;
   }

public:
   CFamilyStrategyWeightMatrix() : m_initialized(false) {}

   void Initialize()
   {
      // Default: equal weights for all families
      for(int i = 0; i < 19; i++)
         SetWeights((ENUM_DERIV_FAMILY)i, 1.0, 1.0, 1.0, 1.0);

      // Crash/Boom: Structure dominates (spike detection + grid recovery)
      //             Suppress mean-reversion (spikes make it dangerous)
      SetWeights(DERIV_CRASH_BOOM, 0.8, 0.4, 1.5, 1.3);

      // Volatility: Mean-reversion + Scalp dominate (continuous movement, NO directional bias)
      //             Suppress trend (no directional bias to follow) and structure (no order blocks/FVG)
      SetWeights(DERIV_VOLATILITY, 0.6, 1.5, 0.5, 1.3);

      // Step: Mean-reversion + Scalp (discrete steps, no trend)
      //       Suppress trend (steps are not trends)
      SetWeights(DERIV_STEP, 0.5, 1.5, 1.0, 1.2);

      // Jump: Scalp + Structure (sharp events similar to Crash/Boom)
      SetWeights(DERIV_JUMP, 0.9, 0.6, 1.4, 1.3);

      // DEX: Scalp dominant (high-frequency discrete movements)
      SetWeights(DERIV_DEX, 0.7, 0.8, 0.9, 1.5);

      // Multi-Step: Mean-reversion + Scalp (similar to Step)
      SetWeights(DERIV_MULTISTEP, 0.5, 1.5, 1.0, 1.2);

      // Exponential: Trend dominant (growth curves)
      SetWeights(DERIV_EXPONENTIAL, 1.5, 0.5, 0.8, 1.0);

      // Hybrid: Structure + Trend (directional bias + sharp events)
      SetWeights(DERIV_HYBRID, 1.3, 0.8, 1.5, 1.1);

      // Range Break: Structure (breakout patterns are structural)
      SetWeights(DERIV_RANGE_BREAK, 1.0, 0.7, 1.6, 1.0);

      // Skew Step: Mean-reversion (biased steps favor mean reversion)
      SetWeights(DERIV_SKEW_STEP, 0.4, 1.6, 0.9, 1.3);

      // Vol Switch: Trend + Scalp (volatility changes create trend opportunities)
      SetWeights(DERIV_VOL_SWITCH, 1.3, 0.7, 0.8, 1.4);

      // Drift Switch: Trend dominant (drift = trend)
      SetWeights(DERIV_DRIFT_SWITCH, 1.5, 0.5, 0.9, 1.1);

      // Trek: Trend + Scalp (directional journey)
      SetWeights(DERIV_TREK, 1.4, 0.6, 0.9, 1.2);

      // Tactical: Balanced (mixed behavior)
      SetWeights(DERIV_TACTICAL, 1.1, 1.0, 1.1, 1.1);

      // Derived: Balanced (mirrors underlying)
      SetWeights(DERIV_DERIVED, 1.0, 1.0, 1.0, 1.0);

      // Stable Spread: Mean-reversion (stable = reverts)
      SetWeights(DERIV_STABLE_SPREAD, 0.6, 1.5, 0.8, 1.1);

      // Pairs Arbitrage: Mean-reversion (pair convergence)
      SetWeights(DERIV_PAIRS_ARBITRAGE, 0.5, 1.6, 0.7, 1.2);

      // Spot Volatility: Trend + Scalp (similar to Volatility)
      SetWeights(DERIV_SPOT_VOLATILITY, 1.3, 0.7, 0.6, 1.4);

      m_initialized = true;

      PrintFormat("[FAMILY-WEIGHT-MATRIX] Initialized for %d Deriv families", 19);
   }

   //+------------------------------------------------------------------+
   //| Get cluster weight multiplier for a given family                 |
   //+------------------------------------------------------------------+
   double GetClusterWeight(ENUM_DERIV_FAMILY family, ENUM_STRATEGY_CLUSTER cluster) const
   {
      if(!m_initialized)
         return 1.0;

      int idx = (int)family;
      if(idx < 0 || idx >= 19)
         return 1.0;

      switch(cluster)
      {
         case TREND_CLUSTER:          return m_weights[idx].trend;
         case MEAN_REVERSION_CLUSTER: return m_weights[idx].meanReversion;
         case STRUCTURE_CLUSTER:      return m_weights[idx].structure;
         case SCALP_CLUSTER:          return m_weights[idx].scalp;
         default:                     return 1.0;
      }
   }

   //+------------------------------------------------------------------+
   //| Get all weights for a family                                     |
   //+------------------------------------------------------------------+
   SFamilyClusterWeights GetFamilyWeights(ENUM_DERIV_FAMILY family) const
   {
      if(!m_initialized || (int)family < 0 || (int)family >= 19)
      {
         SFamilyClusterWeights def;
         def.trend = 1.0; def.meanReversion = 1.0; def.structure = 1.0; def.scalp = 1.0;
         return def;
      }
      return m_weights[(int)family];
   }

   bool IsInitialized() const { return m_initialized; }
};

#endif // CORE_ENGINES_FAMILY_STRATEGY_WEIGHT_MATRIX_MQH
