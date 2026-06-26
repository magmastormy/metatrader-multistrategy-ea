# Dashboard Data Pipeline Enhancement Plan

## Problem Statement
The current dashboard data pipeline in `DashboardBridge.mqh` pushes mostly **placeholder data** to the dashboard server. Critical sections like risk, performance, consensus, AI adapters, strategies, scalp monitoring, heartbeat, and Python bridge status are all hardcoded with zeros/empty values instead of pulling from the actual EA runtime state.

## Current Architecture

### Data Flow
```
MT5 EA (MultiStrategyAutonomousEA.mq5)
    └── CDashboardBridge (DashboardBridge.mqh)
        └── BuildStateJson() ← Currently returns placeholders
            └── HTTP POST /state → FastAPI Server (dashboard_server.py)
                └── StateManager (state_manager.py)
                    └── WebSocket Broadcast → React Client
```

### Global Objects Available in EA
From `MultiStrategyAutonomousEA.mq5`:
- `unifiedRiskManager` (CUnifiedRiskManager) - Full risk state available via `GetSnapshot()`
- `performanceAnalytics` (CPerformanceAnalytics) - Performance metrics via `GetPerformanceMetrics()`
- `aiNextGenBrain` (CNextGenStrategyBrain) - AI brain status
- `g_strategyRegistry` (CStrategyRegistry) - Registered strategies
- `g_consensusCache` (CConsensusCache) - Consensus data
- `g_neuralNetStrategies[]` - Neural network strategies
- Various heartbeat counters and scan statistics

## Solution: Wire Real Data to Dashboard

### Phase 1: Modify DashboardBridge.mqh

#### 1.1 Add External Object References
Add external declarations to access EA's global objects:
```mql5
// External references to EA global objects
extern CUnifiedRiskManager* g_pUnifiedRiskManager;
extern CPerformanceAnalytics* g_pPerformanceAnalytics;
extern CNextGenStrategyBrain* g_pAIBrain;
extern CStrategyRegistry* g_pStrategyRegistry;
extern CConsensusCache* g_pConsensusCache;
```

#### 1.2 Enhance BuildStateJson() Method
Replace placeholder sections with actual data extraction:

**Risk Section:**
```mql5
if(CheckPointer(g_pUnifiedRiskManager) != POINTER_INVALID)
{
   SUnifiedRiskSnapshot riskSnap = g_pUnifiedRiskManager.GetSnapshot();
   json += "\"risk\":{";
   json += "\"active_risk_per_trade_pct\":" + DoubleToString(riskSnap.activeRiskPerTradePercent, 2) + ",";
   json += "\"daily_risk_used_pct\":" + DoubleToString(riskSnap.dailyRiskUsedPercent, 2) + ",";
   json += "\"daily_entry_risk_pct\":" + DoubleToString(riskSnap.dailyEntryRiskUsedPercent, 2) + ",";
   json += "\"daily_mtm_loss_pct\":" + DoubleToString(riskSnap.dailyMarkToMarketLossPercent, 2) + ",";
   json += "\"open_exposure_pct\":" + DoubleToString(riskSnap.openExposureRiskPercent, 2) + ",";
   json += "\"max_daily_risk_pct\":" + DoubleToString(riskSnap.maxDailyRiskPercent, 2) + ",";
   json += "\"portfolio_risk_pct\":" + DoubleToString(riskSnap.portfolioRiskPercent, 2) + ",";
   json += "\"current_drawdown_pct\":" + DoubleToString(riskSnap.currentDrawdownPercent, 2) + ",";
   json += "\"conservative_mode\":" + (riskSnap.conservativeMode ? "true" : "false") + ",";
   json += "\"emergency_mode\":" + (riskSnap.emergencyMode ? "true" : "false") + ",";
   json += "\"gate_approved\":" + IntegerToString(riskSnap.gateApprovedCount) + ",";
   json += "\"gate_rejected\":" + IntegerToString(riskSnap.gateRejectedCount);
   json += "},";
}
```

**Performance Section:**
```mql5
if(CheckPointer(g_pPerformanceAnalytics) != POINTER_INVALID)
{
   SPerformanceMetrics perf = g_pPerformanceAnalytics.GetPerformanceMetrics();
   json += "\"performance\":{";
   json += "\"total_trades\":" + IntegerToString(perf.totalTrades) + ",";
   json += "\"win_rate\":" + DoubleToString(perf.winRate, 2) + ",";
   json += "\"profit_factor\":" + DoubleToString(perf.profitFactor, 3) + ",";
   json += "\"sharpe_ratio\":" + DoubleToString(perf.sharpeRatio, 3) + ",";
   json += "\"max_drawdown\":" + DoubleToString(perf.maxDrawdown, 2) + ",";
   json += "\"recovery_factor\":" + DoubleToString(perf.recoveryFactor, 3) + ",";
   json += "\"net_profit\":" + DoubleToString(perf.totalProfit, 2) + ",";
   json += "\"avg_win\":" + DoubleToString(perf.averageWin, 2) + ",";
   json += "\"avg_loss\":" + DoubleToString(perf.averageLoss, 2);
   json += "},";
}
```

**AI Adapters Section:**
```mql5
json += "\"ai\":{";
// ONNX adapter status
json += "\"onnx\":{\"active\":" + (g_pAIBrain != NULL && g_pAIBrain.IsONNXActive() ? "true" : "false");
if(g_pAIBrain != NULL)
{
   // Get AI vote stats
   int votes, buy, sell, none;
   double conf;
   g_pAIBrain.GetONNXVoteStats(votes, buy, sell, none, conf);
   json += ",\"votes\":" + IntegerToString(votes);
   json += ",\"buy\":" + IntegerToString(buy);
   json += ",\"sell\":" + IntegerToString(sell);
   json += ",\"none\":" + IntegerToString(none);
   json += ",\"conf\":" + DoubleToString(conf, 3);
}
json += "},";

// Ensemble adapter
json += "\"ensemble\":{\"active\":" + (g_pAIBrain != NULL && g_pAIBrain.IsEnsembleActive() ? "true" : "false") + "},";

// Transformer adapter  
json += "\"transformer\":{\"active\":" + (g_pAIBrain != NULL && g_pAIBrain.IsTransformerActive() ? "true" : "false") + "},";

// Neural Network adapter
json += "\"nn\":{\"active\":" + (ArraySize(g_neuralNetStrategies) > 0 ? "true" : "false") + "}";
json += "},";
```

**Strategies Section:**
```mql5
json += "\"strategies\":[";
if(CheckPointer(g_pStrategyRegistry) != POINTER_INVALID)
{
   // Iterate through registered strategies
   // Extract name, symbol, role, mode, weight for each
}
json += "],";
```

**Heartbeat Section:**
```mql5
// Use actual counter variables from EA
json += "\"heartbeat\":{";
json += "\"scans\":" + IntegerToString(g_scansCount) + ",";
json += "\"signals_generated\":" + IntegerToString(g_signalsGenerated) + ",";
json += "\"signals_validated\":" + IntegerToString(g_signalsValidated) + ",";
json += "\"trades_opened\":" + IntegerToString(g_tradesOpened) + ",";
json += "\"shadow_trades\":" + IntegerToString(g_shadowTrades) + ",";
json += "\"spike_events\":" + IntegerToString(g_spikeEvents);
json += "},";
```

### Phase 2: Update MultiStrategyAutonomousEA.mq5

#### 2.1 Set External Pointers in OnInit()
```mql5
int OnInit()
{
   // ... existing initialization ...
   
   // Wire dashboard bridge to global objects
   if(g_dashboardBridge != NULL)
   {
      g_dashboardBridge.SetRiskManager(&unifiedRiskManager);
      g_dashboardBridge.SetPerformanceAnalytics(&performanceAnalytics);
      g_dashboardBridge.SetAIBrain(&aiNextGenBrain);
      g_dashboardBridge.SetStrategyRegistry(&g_strategyRegistry);
      g_dashboardBridge.SetConsensusCache(&g_consensusCache);
   }
   
   // ... rest of initialization ...
}
```

#### 2.2 Expose Heartbeat Counters
Add getter methods or make counters accessible:
```mql5
// Add to DashboardBridge class
void SetHeartbeatCounters(int* scans, int* signalsGen, int* signalsVal, 
                          int* tradesOpened, int* shadowTrades, int* spikeEvents);
```

### Phase 3: Enhanced Consensus Data

#### 3.1 Add Consensus Symbol Iteration
Create method in DashboardBridge to iterate consensus cache:
```mql5
string BuildConsensusJson()
{
   string json = "{\"symbols\":{";
   if(CheckPointer(g_pConsensusCache) != POINTER_INVALID)
   {
      // Iterate through cached consensus results
      // Format: "EURUSD": {"last_signal": "BUY", "confidence": 85.5, ...}
   }
   json += "}}";
   return json;
}
```

### Phase 4: Python Bridge Status

#### 4.1 Wire Python Bridge Stats
```mql5
// In DashboardBridge, add reference to Python bridge
extern CPythonBridge* g_pPythonBridge;

// In BuildStateJson():
json += "\"python_bridge\":{";
if(CheckPointer(g_pPythonBridge) != POINTER_INVALID)
{
   json += "\"connected\":" + (g_pPythonBridge.IsConnected() ? "true" : "false") + ",";
   json += "\"version\":\"" + g_pPythonBridge.GetVersion() + "\",";
   json += "\"requests\":" + IntegerToString(g_pPythonBridge.GetRequestCount()) + ",";
   json += "\"ok\":" + IntegerToString(g_pPythonBridge.GetSuccessCount()) + ",";
   json += "\"errors\":" + IntegerToString(g_pPythonBridge.GetErrorCount());
}
else
{
   json += "\"connected\":false,\"version\":\"\",\"requests\":0,\"ok\":0,\"errors\":0";
}
json += "},";
```

### Phase 5: Server-Side Enhancements

#### 5.1 Add Data Enrichment Endpoints
Add new REST endpoints in `dashboard_server.py`:
```python
@app.get("/api/risk/snapshot")
async def get_risk_snapshot():
    """Get current risk snapshot with full details."""
    return await state_manager.get_risk_snapshot()

@app.get("/api/performance/detailed")
async def get_detailed_performance():
    """Get detailed performance metrics including trade history."""
    return await state_manager.get_detailed_performance()

@app.get("/api/consensus/all")
async def get_all_consensus():
    """Get consensus data for all symbols."""
    return await state_manager.get_all_consensus()

@app.get("/api/ai/status")
async def get_ai_status():
    """Get detailed AI subsystem status."""
    return await state_manager.get_ai_status()
```

#### 5.2 Enhance State Manager
Add methods to store and retrieve enriched data:
```python
async def update_risk_snapshot(self, data: dict) -> None:
    async with self._lock:
        self._risk_snapshot = data
        
async def get_risk_snapshot(self) -> dict:
    async with self._lock:
        return dict(self._risk_snapshot)
```

### Phase 6: Client-Side Integration

#### 6.1 Update TypeScript Types
Ensure `ea-state.ts` types match the enhanced data structure.

#### 6.2 Create New Hooks
```typescript
// useRiskSnapshot.ts
export function useRiskSnapshot() {
  const [snapshot, setSnapshot] = useState<RiskSnapshot | null>(null);
  
  useEffect(() => {
    // Fetch from /api/risk/snapshot
  }, []);
  
  return { snapshot, isLoading };
}
```

## Implementation Priority

1. **CRITICAL** - Risk & Performance data (immediate impact)
2. **HIGH** - Heartbeat & Python bridge status (operational visibility)
3. **HIGH** - AI adapter status (ML visibility)
4. **MEDIUM** - Strategies registry (architecture visibility)
5. **MEDIUM** - Consensus data (decision transparency)
6. **LOW** - Additional REST endpoints (nice-to-have)

## Testing Strategy

1. **Unit Tests**: Mock EA objects and verify JSON output
2. **Integration Tests**: Run EA in strategy tester, verify dashboard updates
3. **E2E Tests**: Full stack test with React dashboard rendering real data

## Expected Outcomes

- Dashboard shows **real-time risk metrics** instead of zeros
- Performance analytics reflect **actual trading results**
- AI subsystem status shows **active adapters and confidence levels**
- Heartbeat displays **actual scan/trade counts**
- Python bridge shows **connection health and request stats**
- Consensus data reveals **symbol-level decision making**

## Files to Modify

1. `/workspace/Core/Utils/DashboardBridge.mqh` - Main enhancement
2. `/workspace/MultiStrategyAutonomousEA.mq5` - Wire global objects
3. `/workspace/Dashboard/server/state_manager.py` - Store enriched data
4. `/workspace/Dashboard/server/dashboard_server.py` - New endpoints
5. `/workspace/Dashboard/client/src/types/ea-state.ts` - Type updates
6. `/workspace/Dashboard/client/src/hooks/useEAState.ts` - Hook enhancements

## Timeline Estimate

- Phase 1 (DashboardBridge): 2-3 hours
- Phase 2 (EA wiring): 1-2 hours
- Phase 3-4 (Consensus/Python): 2 hours
- Phase 5 (Server): 1 hour
- Phase 6 (Client): 1 hour
- Testing: 2 hours

**Total: ~9-11 hours**
