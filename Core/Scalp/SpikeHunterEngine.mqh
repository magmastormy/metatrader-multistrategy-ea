// Spike hunting engine for synthetic CFD indices
// Detects pre-spike conditions and opens trades IN the spike
// direction, independent of existing long-term positions
// DECOMPOSED: CSpikeHunterEngine is now a thin coordinator. The
// implementation lives in focused SpikeHunter* modules, each owning
// one cohesive concern. Every public method below is a signature-
// identical forwarder â€?no behaviour, threshold or log tag changed.
// SpikeHunterTypes.mqh      SSpikeHunterConfig + state structs
// SpikeHunterOverrides.mqh  Batch-102 family override table
// SpikeHunterDirection.mqh  PainX/GainX/Boom/Crash direction map
// SpikeHunterDetector.mqh   symbol registry + 3 detection layers
// SpikeHunterAlerts.mqh     throttled push notifications
// SpikeHunterExecutor.mqh   spike trade gating + execution
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_ENGINE_MQH
#define CORE_SCALP_SPIKE_HUNTER_ENGINE_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include <Trade\Trade.mqh>

class CUnifiedRiskManager;

// Forward declaration for AI adapter (L10-018)
class CAIAdapter;

//--- Decomposed SpikeHunter* modules (each header is self-guarded)
#include "SpikeHunterTypes.mqh"
#include "SpikeHunterOverrides.mqh"
#include "SpikeHunterDirection.mqh"
#include "SpikeHunterDetector.mqh"
#include "SpikeHunterAlerts.mqh"
#include "SpikeHunterExecutor.mqh"

// CSpikeHunterEngine â€?Spike hunting engine for synthetic CFDs
// (coordinator)
class CSpikeHunterEngine
{
private:
   SSpikeHunterConfig              m_config;

   //--- Extracted state owners (held BY VALUE)
   CSpikeHunterDetector            m_detector;   // was m_symbolStates[]/m_symbolCount/m_atrHandles[]/m_familyOverrides[]
   CSpikeHunterAlerts              m_alerts;     // was m_lastPushAlertTick/m_pushAlertCount
   CSpikeHunterExecutor            m_executor;   // was m_baseMagic/m_positionSizer/m_riskManager/m_tradeManager/m_trade/m_aiAdapter

   // Statistics
   int                             m_totalDetections;
   int                             m_totalTradesSkipped;

   //--- Forwarders into CSpikeHunterDetector (signatures unchanged) ---

// Find symbol index in the states array
   int FindSymbolIndex(const string symbol) const { return m_detector.FindSymbolIndex(symbol); }

// Find family override index for a symbol (Batch 102)
   int FindFamilyOverrideIndex(const string symbol) const { return m_detector.FindFamilyOverrideIndex(symbol); }

// Effective (override-aware) parameters for a symbol (Batch 102)
   double GetEffectiveVelocityMultiplier(int idx) const { return m_detector.GetEffectiveVelocityMultiplier(idx); }
   int    GetEffectiveMinConsecutiveTicks(int idx) const { return m_detector.GetEffectiveMinConsecutiveTicks(idx); }
   double GetEffectiveATRCompressionRatio(int idx) const { return m_detector.GetEffectiveATRCompressionRatio(idx); }
   double GetEffectiveSLAtrMultiplier(int idx) const { return m_detector.GetEffectiveSLAtrMultiplier(idx); }
   double GetEffectiveTPAtrMultiplier(int idx) const { return m_detector.GetEffectiveTPAtrMultiplier(idx); }
   int    GetEffectiveMagicOffset(int idx) const { return m_detector.GetEffectiveMagicOffset(idx); }
   int    GetEffectiveCooldownMs(int idx) const { return m_detector.GetEffectiveCooldownMs(idx); }
   int    GetEffectiveMinConfluence(int idx) const { return m_detector.GetEffectiveMinConfluence(idx); }

// Initialize a symbol state slot with defaults
   void InitializeSymbolState(int idx, const string symbol) { m_detector.InitializeSymbolState(idx, symbol); }

// Detection layers 1-3 and confluence count
   void UpdateTickVelocity(int idx) { m_detector.UpdateTickVelocity(idx); }
   void UpdateDirectionAccumulation(int idx, double bid) { m_detector.UpdateDirectionAccumulation(idx, bid); }
   void UpdateATRCompression(int idx) { m_detector.UpdateATRCompression(idx); }
   int  CountConfluence(int idx) const { return m_detector.CountConfluence(idx); }

// Determine spike direction based on symbol type and detection
   int DetermineSpikeDirection(int idx) const
   {
      return CSpikeHunterDirection::DetermineSpikeDirection(m_detector.GetSymbolName(idx),
                                                            m_detector.GetDirectionSign(idx));
   }

// Check if symbol has a certain spike direction
// Returns true and sets direction for PainX/Crash/Boom/GainX
   bool IsSpikeSymbolDirectionCertain(const string symbol, int &direction) const
   {
      return CSpikeHunterDirection::IsSpikeSymbolDirectionCertain(symbol, direction);
   }

// Spike trade gating and execution
   bool CanOpenSpikeTrade(int idx) const { return m_executor.CanOpenSpikeTrade(idx); }
   bool OpenSpikeTrade(int idx, int direction) { return m_executor.OpenSpikeTrade(idx, direction); }

// Send a throttled push notification
   void SendThrottledAlert(const string message) { m_alerts.SendThrottledAlert(message); }

public:
// Constructor
   CSpikeHunterEngine() :
      m_totalDetections(0),
      m_totalTradesSkipped(0)
   {
   }

// Destructor
   ~CSpikeHunterEngine()
   {
      Deinit();
   }

// Initialize the engine with config and dependencies
   bool Init(const SSpikeHunterConfig &config, int baseMagic, CPositionSizer *pSizer, CUnifiedRiskManager *pRiskManager = NULL, CTradeManager *pTradeManager = NULL, CAIAdapter *pAIAdapter = NULL)
   {
      m_config         = config;
      m_detector.SetConfig(config);
      m_alerts.SetConfig(config);
      m_executor.Init(config, baseMagic, pSizer, pRiskManager, pTradeManager, pAIAdapter, GetPointer(m_detector));
      m_detector.ResetSymbolCount();

      PrintFormat("[SPIKE-HUNT-ENGINE] Initialized | velMult=%.1f | minTicks=%d | atrRatio=%.2f | slATR=%.1f | tpATR=%.1f | maxPos=%d | cooldown=%dms | confluence=%d/3 | magicOffset=%d",
                  m_config.velocityMultiplier,
                  m_config.minConsecutiveTicks,
                  m_config.atrCompressionRatio,
                  m_config.slAtrMultiplier,
                  m_config.tpAtrMultiplier,
                  m_config.maxSpikePositions,
                  m_config.cooldownMs,
                  m_config.minConfluence,
                  m_config.magicOffset);

      // Log effective confluence config per symbol family
      m_detector.LogOverridesSummary();

      return true;
   }

// Add a symbol to monitor for spikes
   bool AddSymbol(const string symbol) { return m_detector.AddSymbol(symbol); }

// Release all indicator handles and clean up
   void Deinit()
   {
      m_detector.ReleaseHandles();

      PrintFormat("[SPIKE-HUNT-ENGINE] Deinitialized | detections=%d | trades=%d | skipped=%d | alerts=%d",
                  m_totalDetections, m_executor.GetTotalTradesOpened(), m_totalTradesSkipped, m_alerts.GetAlertCount());
   }

// Process a tick for a given symbol â€?call every tick
   void ProcessTick(const string symbol, double bid, double ask)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      if(!m_detector.IsSymbolActive(idx))
         return;

      // Update all three detection layers
      UpdateTickVelocity(idx);
      UpdateDirectionAccumulation(idx, bid);
      UpdateATRCompression(idx);

      m_detector.SetConfluenceCount(idx, CountConfluence(idx));

      // Check if spike is confirmed
      if(m_detector.GetConfluenceCount(idx) < GetEffectiveMinConfluence(idx))
      {
         // Diagnostic: log near-miss confluence once per minute per symbol
         m_detector.LogNearMissDiagnostic(idx);
         return;
      }

      // Spike detected â€?record detection time for long-term cooldown
      m_detector.MarkSpikeDetected(idx);
      m_totalDetections++;

      int direction = DetermineSpikeDirection(idx);
      if(direction == 0)
      {
         PrintFormat("[SPIKE-HUNT-DETECT] %s confluence=%d/3 but no direction determined â€?skipping",
                     symbol, m_detector.GetConfluenceCount(idx));
         m_totalTradesSkipped++;
         return;
      }

      string dirStr = (direction == 1) ? "BUY" : "SELL";
      m_detector.LogSpikeDetected(idx, dirStr);

      // Send push alert
      string alertMsg = "SPIKE DETECTED: " + symbol + " " + dirStr +
                        " (" + IntegerToString(m_detector.GetConfluenceCount(idx)) + "/3 confluence)";
      SendThrottledAlert(alertMsg);

      // Check if we can open a trade
      if(!CanOpenSpikeTrade(idx))
      {
         PrintFormat("[SPIKE-HUNT-SKIP] %s â€?cooldown or max positions reached", symbol);
         m_totalTradesSkipped++;
         return;
      }

      OpenSpikeTrade(idx, direction);
   }

// Check if a symbol is in spike cooldown for long-term entries
// Clears the cooldown flag if expired
   bool IsSymbolInSpikeCooldown(const string symbol)
   {
      return m_detector.IsSymbolInSpikeCooldown(symbol, m_config.spikeCooldownForLongTermMs);
   }

// Count active spike positions (positions with SPIKE-HUNT comment)
   int GetActiveSpikePositions() const { return CSpikeHunterExecutor::GetActiveSpikePositions(); }

// Get total spike detections
   int GetTotalDetections() const { return m_totalDetections; }

// Get total spike trades opened
   int GetTotalTradesOpened() const { return m_executor.GetTotalTradesOpened(); }
   int GetTotalTradesSkipped() const { return m_totalTradesSkipped; }

   const SSpikeHunterConfig GetConfig() const { return m_config; }

// Set family-specific overrides for a symbol (Batch 102)
   void SetFamilyOverrides(const string symbol, double velMult, int minTicks, double atrRatio,
                           double slMult, double tpMult, int magicOff, int cooldown, int minConf)
   {
      m_detector.SetFamilyOverrides(symbol, velMult, minTicks, atrRatio, slMult, tpMult,
                                    magicOff, cooldown, minConf);
   }

   void PrintDiagnostics()
   {
      PrintFormat("[SPIKE-HUNT-DIAG] symbols=%d | detections=%d | trades=%d | skipped=%d | alerts=%d | activePos=%d",
                  m_detector.GetSymbolCount(),
                  m_totalDetections,
                  m_executor.GetTotalTradesOpened(),
                  m_totalTradesSkipped,
                  m_alerts.GetAlertCount(),
                  GetActiveSpikePositions());

      m_detector.PrintSymbolDiagnostics();
   }
};

#endif // CORE_SCALP_SPIKE_HUNTER_ENGINE_MQH
