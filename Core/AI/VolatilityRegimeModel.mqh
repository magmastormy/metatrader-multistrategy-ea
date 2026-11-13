//+------------------------------------------------------------------+
//| VolatilityRegimeModel.mqh                                        |
//| The volatility/regime predictor the features can actually carry.  |
//+------------------------------------------------------------------+
#ifndef CORE_AI_VOLATILITY_REGIME_MODEL_MQH
#define CORE_AI_VOLATILITY_REGIME_MODEL_MQH

// Why this exists
// ---------------
// Two batches of measurement, on 164,035 labelled rows, settled what the 70-feature
// vector is good for:
//   * as a directional target it is noise - every barrier geometry from 0.5 to 3.0 ATR
//     measured between -0.032 and +0.006 edge, and all 114 exported columns were worse
//     than the 70-feature vector (-0.0273), so the information is absent, not misplaced;
//   * as a volatility target it carries real signal - "does the next 5 bars' mean true
//     range exceed the trailing 20-bar median", measured +4.16 points over the majority
//     baseline with 70.8% precision at confidence >= 0.60.
// The MLP the EA can execute (70-32-16-8-3, 2963 params) kept only +0.35 points of that;
// a boosted tree on the same rows keeps +1.0 to +5.4 points per symbol, so the model is
// trained where it wins and exported as plain trees (Tools/nn_vol_model_export.py).
//
// Contract
// --------
//   * artifact: <Common>\Files\EAModels\NN\<SanitizedSymbol>_<int tf>_vol.csv
//   * score = base + learningRate * sum(leaf values along each tree's decision path)
//   * probability expansion = 1 / (1 + exp(-score))
//   * NOTHING here chooses a direction. Two readers consume one number through
//     VolReg_RiskScale(): the entry gate in EAOrchestrator (veto only at an extreme reading)
//     and the risk-per-trade seam in CandidateBuilder (half risk in the confident band).
//     Both fail open on a missing/stale/unreadable model - a volatility model that cannot
//     be loaded must never be able to stop the book or resize it.
//   * the artifact is not a `.bin` checkpoint and is never read by CNeuralNetworkStrategy:
//     the directional net and this model have different targets and must not share a slot.

#include "NNModelStorage.mqh"
#include "../../AIModules/AIConfig.mqh"   // FEATURE_VECTOR_SIZE - resolved by include order until Batch 278

#define VOLREG_MAX_MODELS        32     // one entry per traded symbol; 13 live + headroom
#define VOLREG_RETRY_SECONDS     300    // after a failed load, wait this long before retrying
#define VOLREG_COMPRESSION_MAX   0.25   // half-size below this p(expansion): the
                                        // >=75%-confidence side, 81.5% accurate on the
                                        // Volatility 25 test split (76-87% across symbols)
#define VOLREG_COMPRESSION_VETO  0.15   // hard veto below this: an extreme reading, and the
                                        // only band where refusing the trade outright is
                                        // cheaper than taking it smaller
#define VOLREG_EXPANSION_MIN     0.75   // informational: the mirror threshold; no uplift is
                                        // applied above it, because sizing up on this model
                                        // is a hypothesis nothing has measured yet

struct SVolRegimeModel
{
   string   symbol;
   string   fileName;
   bool     loaded;
   bool     refused;        // load failed; retried no more than once per VOLREG_RETRY_SECONDS
   datetime lastAttempt;
   double   learningRate;
   double   base;
   int      featureCount;
   int      nodeCount;
   int      treeStart[];    // first node index of each tree
   int      nodeFeat[];
   double   nodeThr[];
   int      nodeLeft[];
   int      nodeRight[];
   double   nodeVal[];
   double   prob;          // last evaluated p(expansion); negative = never evaluated
   datetime lastEval;
};

SVolRegimeModel g_volRegModels[VOLREG_MAX_MODELS];
int            g_volRegCount = 0;

//+------------------------------------------------------------------+
//| Locate an existing entry for the symbol, -1 when absent.          |
//+------------------------------------------------------------------+
int VolReg_Find(const string symbol)
{
   for(int i = 0; i < g_volRegCount; i++)
      if(g_volRegModels[i].symbol == symbol)
         return i;
   return -1;
}

string VolReg_FileName(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
   // Same token sanitisation the checkpoints use, so a symbol with spaces/dots resolves
   // to the file the exporter wrote: "Volatility 25 Index" -> "Volatility_25_Index".
   return StringFormat("EAModels\\NN\\%s_%d_vol.csv",
                       NNModelStorage_SanitizeToken(symbol), (int)timeframe);
}

//+------------------------------------------------------------------+
//| Read the exported tree ensemble. Returns false on anything odd -  |
//| the caller then leaves entries alone.                             |
//+------------------------------------------------------------------+
bool VolReg_Load(const string symbol)
{
   int idx = VolReg_Find(symbol);
   if(idx < 0)
   {
      if(g_volRegCount >= VOLREG_MAX_MODELS)
         return false;
      idx = g_volRegCount++;
      g_volRegModels[idx].symbol = symbol;
      g_volRegModels[idx].loaded = false;
      g_volRegModels[idx].refused = false;
      g_volRegModels[idx].prob = -1.0;
      g_volRegModels[idx].nodeCount = 0;
   }

   SVolRegimeModel model;   // scratch; copied in field by field below
   model.fileName = VolReg_FileName(symbol, (ENUM_TIMEFRAMES)Period());
   model.lastAttempt = TimeCurrent();

   const int handle = FileOpen(model.fileName, FILE_READ | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      // Not an error worth printing every cycle: the artifact is optional by design.
      PrintFormat("[VOL-REGIME] no model for %s (%s, err=%d) | volatility gate inactive for this symbol",
                  symbol, model.fileName, GetLastError());
      g_volRegModels[idx].refused = true;
      g_volRegModels[idx].lastAttempt = TimeCurrent();
      return false;
   }

   int    nTrees = 0;
   int    treeCount = 0;
   int    nodes = 0;
   double lr = 0.0;
   double baseScore = 0.0;
   int    featureCount = 0;
   int    currentTree = -1;
   int    treeStart[];
   int    nodeFeat[];
   double nodeThr[];
   int    nodeLeft[];
   int    nodeRight[];
   double nodeVal[];

   bool malformed = false;
   while(!FileIsEnding(handle))
   {
      const string f0 = FileReadString(handle);
      if(f0 == "" || f0 == NULL)
         continue;

      if(f0 == "META")
      {
         // META,classes,feature_count,learning_rate,base,tree_count
         FileReadString(handle);                                  // classes (2)
         featureCount = (int)StringToInteger(FileReadString(handle));
         lr           = StringToDouble(FileReadString(handle));
         baseScore    = StringToDouble(FileReadString(handle));
         nTrees       = (int)StringToInteger(FileReadString(handle));
         continue;
      }

      // tree,node,feature,threshold,left,right,value
      const int tree = (int)StringToInteger(f0);
      FileReadString(handle);                                   // node index (implicit order)
      const int    feat   = (int)StringToInteger(FileReadString(handle));
      const double thr    = StringToDouble(FileReadString(handle));
      const int    left   = (int)StringToInteger(FileReadString(handle));
      const int    right  = (int)StringToInteger(FileReadString(handle));
      const double value  = StringToDouble(FileReadString(handle));

      if(tree != currentTree)
      {
         if(tree <= currentTree) { malformed = true; break; }
         currentTree = tree;
         treeCount++;
         ArrayResize(treeStart, treeCount);
         treeStart[treeCount - 1] = nodes;
      }
      if(feat < -1 || feat >= FEATURE_VECTOR_SIZE) { malformed = true; break; }

      ArrayResize(nodeFeat, nodes + 1);
      ArrayResize(nodeThr, nodes + 1);
      ArrayResize(nodeLeft, nodes + 1);
      ArrayResize(nodeRight, nodes + 1);
      ArrayResize(nodeVal, nodes + 1);
      nodeFeat[nodes]  = feat;
      nodeThr[nodes]   = thr;
      nodeLeft[nodes]  = left;
      nodeRight[nodes] = right;
      nodeVal[nodes]   = value;
      nodes++;
   }
   FileClose(handle);

   if(malformed || nodes == 0 || treeCount == 0 || featureCount != FEATURE_VECTOR_SIZE)
   {
      PrintFormat("[VOL-REGIME] %s artifact unusable | trees=%d nodes=%d feats=%d | gate inactive for this symbol",
                  symbol, treeCount, nodes, featureCount);
      g_volRegModels[idx].refused = true;
      g_volRegModels[idx].lastAttempt = TimeCurrent();
      return false;
   }

   g_volRegModels[idx].learningRate = lr;
   g_volRegModels[idx].base         = baseScore;
   g_volRegModels[idx].featureCount = featureCount;
   g_volRegModels[idx].nodeCount    = nodes;
   ArrayResize(g_volRegModels[idx].treeStart, treeCount);
   ArrayCopy(g_volRegModels[idx].treeStart, treeStart);
   ArrayResize(g_volRegModels[idx].nodeFeat, nodes);
   ArrayCopy(g_volRegModels[idx].nodeFeat, nodeFeat);
   ArrayResize(g_volRegModels[idx].nodeThr, nodes);
   ArrayCopy(g_volRegModels[idx].nodeThr, nodeThr);
   ArrayResize(g_volRegModels[idx].nodeLeft, nodes);
   ArrayCopy(g_volRegModels[idx].nodeLeft, nodeLeft);
   ArrayResize(g_volRegModels[idx].nodeRight, nodes);
   ArrayCopy(g_volRegModels[idx].nodeRight, nodeRight);
   ArrayResize(g_volRegModels[idx].nodeVal, nodes);
   ArrayCopy(g_volRegModels[idx].nodeVal, nodeVal);
   g_volRegModels[idx].loaded = true;
   g_volRegModels[idx].refused = false;
   g_volRegModels[idx].prob = -1.0;

   PrintFormat("[VOL-REGIME] loaded %s | trees=%d nodes=%d lr=%.3f base=%.4f",
               symbol, treeCount, nodes, lr, baseScore);
   return true;
}

//+------------------------------------------------------------------+
//| Evaluate on the raw 70 features (the same values the CSV carried).|
//+------------------------------------------------------------------+
void VolReg_Feed(const string symbol, const double &features[])
{
   if(ArraySize(features) < FEATURE_VECTOR_SIZE)
      return;

   int idx = VolReg_Find(symbol);
   if(idx < 0)
      if(!VolReg_Load(symbol))
         return;
   idx = VolReg_Find(symbol);

   if(!g_volRegModels[idx].loaded)
   {
      if(g_volRegModels[idx].refused &&
         TimeCurrent() - g_volRegModels[idx].lastAttempt < VOLREG_RETRY_SECONDS)
         return;
      if(!VolReg_Load(symbol))
         return;
      idx = VolReg_Find(symbol);
      if(!g_volRegModels[idx].loaded)
         return;
   }

   double score = g_volRegModels[idx].base;
   const int trees = ArraySize(g_volRegModels[idx].treeStart);
   for(int t = 0; t < trees; t++)
   {
      int node = g_volRegModels[idx].treeStart[t];
      int guard = 0;
      while(node >= 0 && node < g_volRegModels[idx].nodeCount && guard++ < 64)
      {
         if(g_volRegModels[idx].nodeFeat[node] < 0)
         {
            score += g_volRegModels[idx].learningRate * g_volRegModels[idx].nodeVal[node];
            break;
         }
         const int feat = g_volRegModels[idx].nodeFeat[node];
         node = (features[feat] <= g_volRegModels[idx].nodeThr[node])
                ? g_volRegModels[idx].nodeLeft[node]
                : g_volRegModels[idx].nodeRight[node];
      }
   }

   g_volRegModels[idx].prob = 1.0 / (1.0 + MathExp(-score));
   g_volRegModels[idx].lastEval = TimeCurrent();
}

//+------------------------------------------------------------------+
//| -1.0 = no model, no evaluation, or a stale reading: no veto.       |
//+------------------------------------------------------------------+
double VolReg_Probability(const string symbol)
{
   const int idx = VolReg_Find(symbol);
   if(idx < 0 || !g_volRegModels[idx].loaded)
      return -1.0;
   if(g_volRegModels[idx].lastEval <= 0)
      return -1.0;
   if(TimeCurrent() - g_volRegModels[idx].lastEval > 3600)
      return -1.0;   // an hour-old reading is not a description of the next 5 bars
   return g_volRegModels[idx].prob;
}

//+------------------------------------------------------------------+
//| One number, one meaning, two readers.                             |
//|   -1.0 = nothing known                  -> leave the trade as it is|
//|    0.0 = extreme compression           -> do not enter at all     |
//|    0.5 = confident compression         -> enter at half risk      |
//|    1.0 = otherwise                     -> unchanged               |
//| The point of the half-size band is that a veto teaches the book    |
//| nothing: this EA has taken zero orders for thirteen batches, and a |
//| model allowed only to subtract entries would keep it at zero. Half  |
//| risk still produces trades to measure.                              |
//+------------------------------------------------------------------+
double VolReg_RiskScale(const string symbol)
{
   const double p = VolReg_Probability(symbol);
   if(p < 0.0)
      return -1.0;
   if(p <= VOLREG_COMPRESSION_VETO)
      return 0.0;
   if(p <= VOLREG_COMPRESSION_MAX)
      return 0.5;
   return 1.0;
}

#endif // CORE_AI_VOLATILITY_REGIME_MODEL_MQH
//+------------------------------------------------------------------+
