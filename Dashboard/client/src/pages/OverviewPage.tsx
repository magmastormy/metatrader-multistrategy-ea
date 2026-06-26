import { useRef, useState, useEffect } from 'react';
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine, ReferenceDot, ReferenceArea } from 'recharts';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import MetricCard from '../components/shared/MetricCard';
import StatusBadge from '../components/shared/StatusBadge';
import AnimatedCounter from '../components/shared/AnimatedCounter';

// Inline utility functions for data visualization (no mock data generation)
const calculateDrawdownPeriods = (data: { time: string; equity: number }[]) => {
  if (data.length < 2) return [];
  const periods: { start: string; end: string; depth: number }[] = [];
  let peak = data[0].equity;
  let peakTime = data[0].time;
  let ddStart: string | null = null;
  
  for (let i = 1; i < data.length; i++) {
    const point = data[i];
    if (point.equity > peak) {
      if (ddStart && peak - data[i-1].equity > peak * 0.01) {
        periods.push({ start: ddStart, end: data[i-1].time, depth: ((peak - data[i-1].equity) / peak) * 100 });
      }
      peak = point.equity;
      peakTime = point.time;
      ddStart = null;
    } else {
      const dd = ((peak - point.equity) / peak) * 100;
      if (dd > 1 && !ddStart) {
        ddStart = peakTime;
      }
    }
  }
  if (ddStart) {
    periods.push({ start: ddStart, end: data[data.length-1].time, depth: ((peak - data[data.length-1].equity) / peak) * 100 });
  }
  return periods;
};

const extractTradeMarkers = (data: { time: string; equity: number }[], positions: any[]) => {
  if (!positions || positions.length === 0 || data.length === 0) return [];
  return positions.slice(0, 5).map((pos, idx) => ({
    time: data[Math.min(idx, data.length - 1)]?.time || data[data.length - 1]?.time,
    equity: pos.entry_price > 0 ? pos.entry_price : data[data.length - 1]?.equity,
    profit: pos.profit || 0,
    symbol: pos.symbol || 'UNKNOWN'
  }));
};

export default function OverviewPage() {
  const { state, alerts, isConnected } = useEAState();
  const equityHistoryRef = useRef<{ time: string; equity: number }[]>([]);
  const [, setTick] = useState(0);

  // Use only real data from the EA - no fallback to mock data
  const displayEquityData = equityHistoryRef.current;

  useEffect(() => {
    if (state) {
      const point = {
        time: new Date(state.timestamp).toLocaleTimeString('en-GB', { hour12: false }),
        equity: state.account.equity,
      };
      equityHistoryRef.current = [...equityHistoryRef.current.slice(-99), point];
      setTick((t) => t + 1);
    }
  }, [state]);

  // Calculate drawdown periods and trade markers for visualization using inline functions
  const drawdownPeriods = calculateDrawdownPeriods(displayEquityData);
  const tradeMarkers = state?.positions ? extractTradeMarkers(displayEquityData, state.positions) : [];

  if (!isConnected) {
    return (
      <PageContainer title="Overview">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center stagger-enter">
            <div className="w-4 h-4 rounded-full bg-accent-red mx-auto mb-4 animate-pulse" />
            <p className="text-text-secondary text-lg">Connecting...</p>
            <p className="text-text-muted text-sm mt-1">Waiting for WebSocket connection</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  if (!state) {
    return (
      <PageContainer title="Overview">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center stagger-enter">
            <div className="w-4 h-4 rounded-full bg-accent-amber mx-auto mb-4 animate-pulse" />
            <p className="text-text-secondary text-lg">Waiting for data...</p>
            <p className="text-text-muted text-sm mt-1">Connected but no state received yet</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  const { account, risk, performance, ai, positions, heartbeat, scalp } = state;
  const equityData = displayEquityData;
  const initialEquity = 50000; // Baseline for comparison

  const adapters = [
    { key: 'ONNX', data: ai.onnx },
    { key: 'Ensemble', data: ai.ensemble },
    { key: 'Transformer', data: ai.transformer },
    { key: 'NN', data: ai.nn },
  ] as const;

  return (
    <PageContainer title="Dashboard Overview">
      {/* Hero Section - Asymmetric layout */}
      <div className="grid grid-cols-12 gap-6 mb-6">
        {/* Main Equity Card - Spans wider */}
        <div className="col-span-8 card-primary p-6 hover-lift">
          <div className="flex items-start justify-between mb-4">
            <div>
              <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-1">Total Equity</p>
              <p className="display-metric text-numeral">
                <AnimatedCounter value={account.equity} decimals={2} prefix="$" />
              </p>
            </div>
            <div className="text-right">
              <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-1">Balance</p>
              <p className="text-2xl font-bold text-text-primary text-numeral">
                <AnimatedCounter value={account.balance} decimals={2} prefix="$" />
              </p>
            </div>
          </div>
          
          {/* Mini equity chart inline */}
          <div className="h-32 -mx-2">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={equityData.slice(-30)}>
                <defs>
                  <linearGradient id="heroEquityGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="rgba(34,211,238,0.4)" />
                    <stop offset="100%" stopColor="rgba(34,211,238,0)" />
                  </linearGradient>
                </defs>
                <ReferenceLine y={initialEquity} stroke="#64748b" strokeDasharray="3 3" strokeWidth={1} />
                <Area 
                  type="monotone" 
                  dataKey="equity" 
                  stroke="#22d3ee" 
                  fill="url(#heroEquityGrad)" 
                  strokeWidth={2} 
                  animationDuration={1000}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Quick Stats - Compact vertical stack */}
        <div className="col-span-4 space-y-4">
          <div className="card-warning p-4 hover-lift">
            <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-2">Free Margin</p>
            <p className="text-2xl font-bold text-accent-amber text-numeral">
              <AnimatedCounter value={account.free_margin} decimals={2} prefix="$" />
            </p>
            <div className="mt-2 text-xs text-text-muted">
              Margin Level: <span className="text-text-primary font-semibold">{account.margin_level.toFixed(1)}%</span>
            </div>
          </div>
          
          <div className={`p-4 hover-lift ${risk.current_drawdown_pct > 3 ? 'card-critical' : 'glass-card'}`}>
            <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-2">Current Drawdown</p>
            <p className="text-2xl font-bold text-accent-red text-numeral">
              <AnimatedCounter value={risk.current_drawdown_pct} decimals={2} suffix="%" />
            </p>
            <div className="mt-2 h-2 bg-surface-600 rounded-full overflow-hidden">
              <div 
                className="h-full bg-gradient-to-r from-accent-cyan via-accent-amber to-accent-red rounded-full transition-all duration-500"
                style={{ width: `${Math.min(risk.current_drawdown_pct * 10, 100)}%` }}
              />
            </div>
          </div>
        </div>
      </div>

      {/* Middle Row - Varied card sizes */}
      <div className="grid grid-cols-12 gap-6 mb-6">
        {/* Enhanced Equity Curve - Larger */}
        <div className="col-span-7 glass-card p-5 hover-lift">
          <div className="flex items-center justify-between mb-4">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium">Equity Curve with Trade Markers</p>
            <div className="flex items-center gap-2 text-xs">
              <span className="flex items-center gap-1 text-text-muted">
                <span className="w-2 h-2 rounded-full bg-accent-green" /> Win
              </span>
              <span className="flex items-center gap-1 text-text-muted">
                <span className="w-2 h-2 rounded-full bg-accent-red" /> Loss
              </span>
            </div>
          </div>
          <div className="h-64">
            {equityData.length > 1 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={equityData}>
                  <defs>
                    <linearGradient id="equityGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="rgba(34,211,238,0.3)" />
                      <stop offset="100%" stopColor="rgba(34,211,238,0)" />
                    </linearGradient>
                  </defs>
                  <XAxis 
                    dataKey="time" 
                    tick={{ fontSize: 10, fill: '#64748b' }} 
                    axisLine={false} 
                    tickLine={false}
                    interval={Math.floor(equityData.length / 8)}
                  />
                  <YAxis 
                    tick={{ fontSize: 10, fill: '#64748b' }} 
                    axisLine={false} 
                    tickLine={false} 
                    domain={['auto', 'auto']}
                    tickFormatter={(value) => `$${(value/1000).toFixed(0)}k`}
                  />
                  <Tooltip
                    contentStyle={{ 
                      background: '#1a1f2e', 
                      border: '1px solid rgba(148,163,184,0.1)', 
                      borderRadius: 8, 
                      fontSize: 12,
                      boxShadow: '0 4px 12px rgba(0,0,0,0.3)'
                    }}
                    labelStyle={{ color: '#94a3b8' }}
                    itemStyle={{ color: '#22d3ee' }}
                    formatter={(value: number) => [`$${value.toFixed(2)}`, 'Equity']}
                  />
                  <ReferenceLine y={initialEquity} stroke="#64748b" strokeDasharray="3 3" />
                  {/* Drawdown period shading */}
                  {drawdownPeriods.slice(0, 3).map((dd, i) => (
                    <ReferenceArea
                      key={i}
                      x1={dd.start}
                      x2={dd.end}
                      fill="rgba(239, 68, 68, 0.05)"
                    />
                  ))}
                  {/* Trade entry markers */}
                  {tradeMarkers.slice(0, 5).map((trade, i) => (
                    <ReferenceDot
                      key={i}
                      x={trade.time}
                      y={trade.equity}
                      fill={trade.profit >= 0 ? '#22c55e' : '#ef4444'}
                      r={5}
                      strokeWidth={2}
                      stroke="#1a1f2e"
                    />
                  ))}
                  <Area 
                    type="monotone" 
                    dataKey="equity" 
                    stroke="#22d3ee" 
                    fill="url(#equityGrad)" 
                    strokeWidth={2}
                    animationDuration={1500}
                  />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex items-center justify-center h-full text-text-muted text-sm">
                Collecting equity data...
              </div>
            )}
          </div>
        </div>

        {/* Risk Budget - Medium */}
        <div className="col-span-2 glass-card p-5 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Risk Budget</p>
          <div className="space-natural">
            <RiskBar label="Daily" used={risk.daily_risk_used_pct} max={risk.max_daily_risk_pct} />
            <RiskBar label="Entry" used={risk.daily_entry_risk_pct} max={risk.max_daily_risk_pct} />
            <RiskBar label="Exposure" used={risk.open_exposure_pct} max={100} />
            <RiskBar label="Portfolio" used={risk.portfolio_risk_pct} max={100} />
          </div>
        </div>

        {/* Performance Summary - Medium */}
        <div className="col-span-3 glass-card p-5 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Performance Metrics</p>
          <div className="grid grid-cols-2 gap-3">
            <MiniStat label="Win Rate" value={`${(performance.win_rate * 100).toFixed(1)}%`} trend="up" />
            <MiniStat label="Profit Factor" value={performance.profit_factor.toFixed(2)} trend="up" />
            <MiniStat label="Sharpe" value={performance.sharpe_ratio.toFixed(2)} trend="neutral" />
            <MiniStat label="Recovery" value={performance.recovery_factor.toFixed(2)} trend="up" />
            <MiniStat label="Net P/L" value={`$${performance.net_profit.toLocaleString()}`} positive={performance.net_profit >= 0} />
            <MiniStat label="Total Trades" value={performance.total_trades.toString()} />
          </div>
        </div>
      </div>

      {/* Bottom Row - Three columns */}
      <div className="grid grid-cols-12 gap-6">
        {/* Positions + Heartbeat + Scalp - Left column */}
        <div className="col-span-3 space-y-4">
          <div className="card-primary p-4 hover-lift">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Open Positions</p>
            <p className="text-4xl font-bold text-text-primary text-numeral">
              <AnimatedCounter value={positions.length} decimals={0} />
            </p>
            {positions.length > 0 && (
              <div className="mt-2 text-xs text-text-muted">
                Total P&L:{' '}
                <span className={positions.reduce((s, p) => s + p.profit, 0) >= 0 ? 'text-accent-green' : 'text-accent-red'}>
                  ${positions.reduce((s, p) => s + p.profit, 0).toFixed(2)}
                </span>
              </div>
            )}
          </div>
          
          <div className="glass-card p-4 hover-lift">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Heartbeat Stats</p>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <HeartbeatStat label="Scans" value={heartbeat.scans} />
              <HeartbeatStat label="Signals" value={heartbeat.signals_generated} />
              <HeartbeatStat label="Validated" value={heartbeat.signals_validated} />
              <HeartbeatStat label="Opened" value={heartbeat.trades_opened} color="text-accent-green" />
              <HeartbeatStat label="Shadow" value={heartbeat.shadow_trades} color="text-accent-purple" />
              <HeartbeatStat label="Spikes" value={heartbeat.spike_events} color="text-accent-red" />
            </div>
          </div>
          
          <div className="glass-card p-4 hover-lift">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Scalp Mode</p>
            <div className="flex items-center gap-2 mb-3">
              <StatusBadge status={scalp.active ? 'online' : 'offline'} label={scalp.active ? 'Active' : 'Inactive'} />
            </div>
            <div className="space-y-1 text-xs text-text-muted">
              <div className="flex justify-between">
                <span>Positions:</span>
                <span className="text-text-primary font-mono">{scalp.open_positions}/{scalp.max_positions}</span>
              </div>
              <div className="flex justify-between">
                <span>Entries:</span>
                <span className="text-text-primary font-mono">{scalp.total_entries}</span>
              </div>
              <div className="flex justify-between">
                <span>Rejected:</span>
                <span className="text-text-primary font-mono">{scalp.total_rejections}</span>
              </div>
            </div>
          </div>
        </div>

        {/* AI Subsystem - Center-left */}
        <div className="col-span-4 glass-card p-5 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">AI Subsystem Status</p>
          <div className="space-natural">
            {adapters.map(({ key, data }) => (
              <div 
                key={key} 
                className={`flex items-center justify-between py-2.5 px-3 rounded-lg transition-all duration-200 ${
                  data.active ? 'bg-surface-700/50 hover:bg-surface-700' : 'opacity-50'
                }`}
              >
                <div className="flex items-center gap-3">
                  <StatusBadge status={data.active ? 'online' : 'offline'} label="" />
                  <span className="text-text-primary font-semibold text-sm">{key}</span>
                </div>
                <div className="flex items-center gap-3 text-xs">
                  {data.votes !== undefined && (
                    <span className="text-text-muted">
                      Votes: <span className="text-text-primary font-mono">{data.votes}</span>
                    </span>
                  )}
                  {data.accuracy !== undefined && (
                    <span className="text-text-muted">
                      Acc: <span className="text-accent-amber font-mono">{(data.accuracy * 100).toFixed(1)}%</span>
                    </span>
                  )}
                  {data.conf !== undefined && (
                    <span className="text-text-muted">
                      Conf: <span className="text-accent-cyan font-mono">{(data.conf * 100).toFixed(0)}%</span>
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Recent Alerts - Right */}
        <div className="col-span-5 glass-card p-5 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Recent Alerts</p>
          {alerts.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-40 text-text-muted">
              <svg className="w-12 h-12 mb-2 opacity-40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
              </svg>
              <p className="text-sm">No alerts yet</p>
              <p className="text-xs mt-1">System operating normally</p>
            </div>
          ) : (
            <div className="space-y-1.5 max-h-48 overflow-auto pr-2 stagger-enter">
              {alerts.slice(0, 12).map((a, idx) => (
                <div 
                  key={a.id} 
                  className="flex items-start gap-2.5 text-xs py-2 px-3 rounded-lg hover:bg-surface-700/50 transition-colors duration-150"
                  style={{ animationDelay: `${idx * 30}ms` }}
                >
                  <span
                    className={`w-2 h-2 rounded-full flex-shrink-0 mt-1 ${
                      a.severity === 'error' ? 'bg-accent-red' : a.severity === 'warning' ? 'bg-accent-amber' : 'bg-accent-cyan'
                    }`}
                  />
                  <span className="text-text-muted font-mono flex-shrink-0 text-[10px] w-14">
                    {new Date(a.timestamp).toLocaleTimeString('en-GB', { hour12: false })}
                  </span>
                  <span className="text-text-secondary truncate flex-1">{a.message}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </PageContainer>
  );
}

function RiskBar({ label, used, max }: { label: string; used: number; max: number }) {
  const pct = Math.min((used / max) * 100, 100);
  const color = pct > 80 ? 'bg-accent-red' : pct > 50 ? 'bg-accent-amber' : 'bg-accent-cyan';
  return (
    <div>
      <div className="flex justify-between text-xs mb-1.5">
        <span className="text-text-muted font-medium">{label}</span>
        <span className="text-text-secondary font-mono">{used.toFixed(1)}%</span>
      </div>
      <div className="h-2 bg-surface-600 rounded-full overflow-hidden">
        <div 
          className={`h-full ${color} rounded-full transition-all duration-500 ease-out`} 
          style={{ width: `${pct}%` }} 
        />
      </div>
    </div>
  );
}

function MiniStat({ label, value, positive, trend }: { label: string; value: string; positive?: boolean; trend?: 'up' | 'down' | 'neutral' }) {
  return (
    <div className="bg-surface-700/30 rounded-lg p-2.5 hover:bg-surface-700/50 transition-colors duration-200">
      <p className="text-text-muted text-[10px] uppercase tracking-wider mb-0.5">{label}</p>
      <div className="flex items-center gap-1.5">
        <p className={`text-base font-bold ${positive === true ? 'text-accent-green' : positive === false ? 'text-accent-red' : 'text-text-primary'} text-numeral`}>
          {value}
        </p>
        {trend && (
          <span className={`text-xs ${trend === 'up' ? 'text-accent-green' : trend === 'down' ? 'text-accent-red' : 'text-text-muted'}`}>
            {trend === 'up' ? '↑' : trend === 'down' ? '↓' : '→'}
          </span>
        )}
      </div>
    </div>
  );
}

function HeartbeatStat({ label, value, color = 'text-text-primary' }: { label: string; value: number; color?: string }) {
  return (
    <div className="bg-surface-700/30 rounded p-2 text-center">
      <p className={`text-sm font-bold ${color} text-numeral`}>{value.toLocaleString()}</p>
      <p className="text-[10px] text-text-muted uppercase tracking-wider">{label}</p>
    </div>
  );
}
