export interface EAAccount {
  balance: number;
  equity: number;
  free_margin: number;
  margin_level: number;
}

export interface EAPosition {
  ticket: number;
  symbol: string;
  type: string;
  lots: number;
  open_price: number;
  current_price: number;
  sl: number;
  tp: number;
  profit: number;
  swap: number;
  open_time: string;
  duration_minutes: number;
  strategy: string;
}

export interface EARisk {
  active_risk_per_trade_pct: number;
  daily_risk_used_pct: number;
  daily_entry_risk_pct: number;
  daily_mtm_loss_pct: number;
  open_exposure_pct: number;
  max_daily_risk_pct: number;
  portfolio_risk_pct: number;
  current_drawdown_pct: number;
  conservative_mode: boolean;
  emergency_mode: boolean;
  gate_approved: number;
  gate_rejected: number;
}

export interface EAPerformance {
  total_trades: number;
  win_rate: number;
  profit_factor: number;
  sharpe_ratio: number;
  max_drawdown: number;
  recovery_factor: number;
  net_profit: number;
  avg_win: number;
  avg_loss: number;
}

export interface EAConsensusSymbol {
  last_signal: string;
  confidence: number;
  buy_score: number;
  sell_score: number;
  quorum_met: boolean;
  veto_code: string;
  active_strategies: number;
  voted_strategies: number;
  dominant_cluster: string;
}

export interface EAAIAdapter {
  active: boolean;
  votes?: number;
  buy?: number;
  sell?: number;
  none?: number;
  conf?: number;
  accuracy?: number;
}

export interface EAAINeuralNet {
  active: boolean;
  signal?: string;
  confidence?: number;
  labels_resolved?: number;
  training_steps?: number;
  conformal_quantile?: number;
  conformal_alpha?: number;
  asset_class?: number;
  barrier_k?: number;
  barrier_vert_bars?: number;
  trade_linked_labels?: number;
  normalization_ready?: boolean;
}

export interface EAAIRegime {
  current?: string;
  trend_prob?: number;
  range_prob?: number;
  volatile_prob?: number;
  spike_prob?: number;
}

export interface EAAIMetaLabeler {
  features?: number;
  cooldown?: number;
  early_stop_patience?: number;
  recent_win_rate?: number;
  recent_avg_confidence?: number;
  samples_since_train?: number;
}

export interface EAAI {
  onnx: EAAIAdapter;
  ensemble: EAAIAdapter;
  transformer: EAAIAdapter;
  nn: EAAIAdapter;
  neural_net?: EAAINeuralNet;
  regime?: EAAIRegime;
  meta_labeler?: EAAIMetaLabeler;
  features_total?: number;
}

export interface EAStrategy {
  name: string;
  symbol: string;
  role: string;
  mode: string;
  weight: number;
}

export interface EAScalp {
  active: boolean;
  open_positions: number;
  max_positions: number;
  total_entries: number;
  total_rejections: number;
}

export interface EAHeartbeat {
  scans: number;
  signals_generated: number;
  signals_validated: number;
  trades_opened: number;
  shadow_trades: number;
  spike_events: number;
}

export interface EAPythonBridge {
  connected: boolean;
  version: string;
  requests: number;
  ok: number;
  errors: number;
}

export interface EAState {
  timestamp: string;
  account: EAAccount;
  positions: EAPosition[];
  risk: EARisk;
  performance: EAPerformance;
  consensus: { symbols: Record<string, EAConsensusSymbol> };
  ai: EAAI;
  strategies: EAStrategy[];
  scalp: EAScalp;
  heartbeat: EAHeartbeat;
  execution_mode: string;
  python_bridge: EAPythonBridge;
}

export interface LogEntry {
  tag: string;
  timestamp: string;
  fields: Record<string, unknown>;
  raw: string;
}

export interface WSMessage {
  type: 'state' | 'log' | 'trade' | 'alert';
  data: unknown;
}
