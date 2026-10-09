import { useState, useCallback, useRef, useEffect } from 'react';
import type { EAState, LogEntry, WSMessage } from '../types/ea-state';
import { useWebSocket } from './useWebSocket';

// Opt-in demo mode: append ?demo to the URL to render the dashboard with
// synthetic data (no EA / WebSocket required). Never active in production.
const DEMO =
  typeof window !== 'undefined' && new URLSearchParams(window.location.search).has('demo');

interface AlertEntry {
  id: number;
  timestamp: string;
  message: string;
  severity: 'info' | 'warning' | 'error';
}

let alertIdCounter = 0;

/* ---------------- demo data ---------------- */
function genDemoState(tick: number): EAState {
  const eq = 51250 + Math.sin(tick / 4) * 650 + tick * 9;
  const balance = 50000 + tick * 8;
  const positions: EAState['positions'] = [
    { ticket: 882413, symbol: 'EURUSD', type: 'BUY', lots: 0.32, open_price: 1.0842, current_price: 1.0861, sl: 1.0810, tp: 1.0900, profit: 62.4, swap: -0.12, open_time: new Date().toISOString(), duration_minutes: 42, strategy: 'MeanReversion-A' },
    { ticket: 882420, symbol: 'GBPUSD', type: 'SELL', lots: 0.21, open_price: 1.2715, current_price: 1.2698, sl: 1.2750, tp: 1.2640, profit: 35.7, swap: 0, open_time: new Date().toISOString(), duration_minutes: 18, strategy: 'Breakout-B' },
    { ticket: 882431, symbol: 'XAUUSD', type: 'BUY', lots: 0.10, open_price: 2341.2, current_price: 2336.8, sl: 2328.0, tp: 2360.0, profit: -44.0, swap: 0, open_time: new Date().toISOString(), duration_minutes: 73, strategy: 'TrendFollow-C' },
  ];
  const strategies: EAState['strategies'] = [
    { name: 'MeanReversion-A', symbol: 'EURUSD', role: 'core', mode: 'ACTIVE', weight: 1.32 },
    { name: 'Breakout-B', symbol: 'GBPUSD', role: 'satellite', mode: 'ACTIVE', weight: 0.94 },
    { name: 'TrendFollow-C', symbol: 'XAUUSD', role: 'core', mode: 'ACTIVE', weight: 1.10 },
    { name: 'Scalper-D', symbol: 'EURUSD', role: 'satellite', mode: 'SHADOW', weight: 0.55 },
    { name: 'VolArb-E', symbol: 'GBPUSD', role: 'hedge', mode: 'ACTIVE', weight: 0.78 },
    { name: 'StatArb-F', symbol: 'XAUUSD', role: 'satellite', mode: 'OFF', weight: 0.40 },
  ];
  const signal = tick % 5 === 0 ? 'SELL' : 'BUY';
  return {
    timestamp: new Date().toISOString(),
    account: { balance, equity: eq, free_margin: balance - eq * 0.2, margin_level: 412 + (tick % 7) },
    positions,
    risk: {
      active_risk_per_trade_pct: 0.85, daily_risk_used_pct: 3.2 + (tick % 3) * 0.4, daily_entry_risk_pct: 1.9,
      daily_mtm_loss_pct: 0.6, open_exposure_pct: 14.5, max_daily_risk_pct: 8, portfolio_risk_pct: 22.3,
      current_drawdown_pct: 2.4 + (tick % 4) * 0.3, conservative_mode: false, emergency_mode: false,
      gate_approved: 184, gate_rejected: 12,
    },
    performance: {
      total_trades: 1247, win_rate: 0.612, profit_factor: 1.84, sharpe_ratio: 1.62,
      max_drawdown: 6.8, recovery_factor: 2.3, net_profit: 18450.5, avg_win: 41.2, avg_loss: -22.6,
    },
    consensus: {
      symbols: {
        EURUSD: { last_signal: signal, confidence: 0.62 + (tick % 3) * 0.05, buy_score: 0.58, sell_score: 0.31, quorum_met: true, veto_code: '', active_strategies: 4, voted_strategies: 4, dominant_cluster: 'momentum' },
        GBPUSD: { last_signal: 'BUY', confidence: 0.55, buy_score: 0.49, sell_score: 0.38, quorum_met: true, veto_code: 'RISK-GUARD', active_strategies: 3, voted_strategies: 2, dominant_cluster: 'mean-revert' },
      },
    },
    ai: {
      onnx: { active: true, votes: 16, conf: 0.71, accuracy: 0.64 },
      ensemble: { active: true, votes: 15, conf: 0.68, accuracy: 0.66 },
      transformer: { active: true, votes: 14, conf: 0.63, accuracy: 0.61 },
      nn: { active: true, votes: 12, conf: 0.59, accuracy: 0.6 },
      neural_net: {
        active: true, signal, confidence: 0.58 + (tick % 4) * 0.04, labels_resolved: 1820 + tick,
        training_steps: 48210 + tick * 3, conformal_quantile: 0.12, conformal_alpha: 0.1,
        asset_class: 1, barrier_k: 1.5, barrier_vert_bars: 24, trade_linked_labels: 9, normalization_ready: true,
      },
      regime: { current: tick % 6 === 0 ? 'VOLAT' : 'RANGE', trend_prob: 0.3, range_prob: 0.45, volatile_prob: 0.18, spike_prob: 0.07 },
      meta_labeler: { features: 24, cooldown: 5, early_stop_patience: 10, recent_win_rate: 0.63, recent_avg_confidence: 0.61, samples_since_train: 42 },
      features_total: 65,
    },
    strategies,
    scalp: { active: true, open_positions: 2, max_positions: 5, total_entries: 38, total_rejections: 11 },
    heartbeat: {
      scans: 1520 + tick * 2, signals_generated: 412 + tick, signals_validated: 388 + tick,
      trades_opened: 37, shadow_trades: 124, spike_events: 9,
    },
    execution_mode: 'LIVE',
    python_bridge: { connected: true, version: '3.2.1', requests: 980 + tick, ok: 972 + tick, errors: 8 },
  };
}

const DEMO_TAGS = ['HEARTBEAT', 'CONSENSUS-DIAG', 'AI-VOTE', 'SIGNAL-REJECTED', 'SHADOW-TRADE', 'TRADE', 'RISK'];
function genDemoLogs(): LogEntry[] {
  const out: LogEntry[] = [];
  for (let i = 0; i < 14; i++) {
    const tag = DEMO_TAGS[i % DEMO_TAGS.length];
    const ts = new Date(Date.now() - i * 4200).toISOString();
    out.push({
      tag,
      timestamp: ts,
      fields: { level: i % 9 === 0 ? 'WARNING' : 'INFO', symbol: ['EURUSD', 'GBPUSD', 'XAUUSD'][i % 3], event_type: tag.split('-')[0] },
      raw: `[${ts}] [${tag}] symbol=${(['EURUSD', 'GBPUSD', 'XAUUSD'] as const)[i % 3]} consensus_quorum=true veto=none confidence=${(0.5 + (i % 4) * 0.08).toFixed(2)}`,
    });
  }
  return out;
}

/* ---------------- hook ---------------- */
export function useEAState(): {
  state: EAState | null;
  logs: LogEntry[];
  alerts: AlertEntry[];
  isConnected: boolean;
  connectionStatus: 'connecting' | 'connected' | 'disconnected' | 'reconnecting' | 'error';
  reconnect: () => void;
  sendCommand: (command: string, params?: Record<string, unknown>) => void;
} {
  const { lastMessage, isConnected: wsConnected, status: wsStatus, send, reconnect } = useWebSocket();
  const [state, setState] = useState<EAState | null>(DEMO ? genDemoState(0) : null);
  const [logs, setLogs] = useState<LogEntry[]>(DEMO ? genDemoLogs() : []);
  const [alerts, setAlerts] = useState<AlertEntry[]>([]);
  const processedRef = useRef<WSMessage | null>(null);
  const demoTick = useRef(0);

  const addAlert = useCallback((message: string, severity: AlertEntry['severity'] = 'info') => {
    const id = ++alertIdCounter;
    setAlerts((prev) => [{ id, timestamp: new Date().toISOString(), message, severity }, ...prev].slice(0, 50));
  }, []);

  useEffect(() => {
    if (!lastMessage || lastMessage === processedRef.current) return;
    processedRef.current = lastMessage;
    switch (lastMessage.type) {
      case 'state':
        setState(lastMessage.data as EAState);
        break;
      case 'log': {
        const entry = lastMessage.data as LogEntry;
        setLogs((prev) => [entry, ...prev].slice(0, 500));
        break;
      }
      case 'alert': {
        const data = lastMessage.data as { message?: string; severity?: string };
        addAlert(data.message ?? 'Unknown alert', (data.severity as AlertEntry['severity']) ?? 'info');
        break;
      }
      case 'trade': {
        const tradeData = lastMessage.data as { action?: string; symbol?: string };
        addAlert(`Trade: ${tradeData.action ?? 'update'} ${tradeData.symbol ?? ''}`.trim(), 'info');
        break;
      }
    }
  }, [lastMessage, addAlert]);

  // Demo loop — only runs when ?demo is present.
  useEffect(() => {
    if (!DEMO) return;
    const id = setInterval(() => {
      demoTick.current += 1;
      setState(genDemoState(demoTick.current));
      if (demoTick.current % 3 === 0) {
        const tag = DEMO_TAGS[demoTick.current % DEMO_TAGS.length];
        const ts = new Date().toISOString();
        setLogs((prev) => [
          {
            tag, timestamp: ts,
            fields: { level: demoTick.current % 11 === 0 ? 'WARNING' : 'INFO', symbol: 'EURUSD', event_type: tag.split('-')[0] },
            raw: `[${ts}] [${tag}] heartbeat scan complete signals=${(400 + demoTick.current).toString()} quorum=true`,
          },
          ...prev,
        ].slice(0, 500));
      }
    }, 1600);
    return () => clearInterval(id);
  }, []);

  const sendCommand = useCallback((command: string, params?: Record<string, unknown>) => {
    if (DEMO) { addAlert(`[demo] ${command}${params ? ' ' + JSON.stringify(params) : ''}`); return; }
    send({ command, ...params });
  }, [send, addAlert]);

  return { state, logs, alerts, isConnected: DEMO ? true : wsConnected, connectionStatus: DEMO ? 'connected' : wsStatus, reconnect, sendCommand };
}
