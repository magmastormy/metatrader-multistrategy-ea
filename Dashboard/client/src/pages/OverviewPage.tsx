import { useRef, useState, useEffect, useMemo } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer,
  ReferenceLine, ReferenceArea, ReferenceDot,
} from 'recharts';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import StatusBadge from '../components/shared/StatusBadge';
import AnimatedCounter from '../components/shared/AnimatedCounter';
import NeuralNetViz from '../components/shared/NeuralNetViz';

export default function OverviewPage() {
  const { state, alerts, isConnected } = useEAState();
  const equityHistoryRef = useRef<{ time: string; equity: number; balance: number }[]>([]);
  const [, setTick] = useState(0);

  // Use real data from EA - no fallback to mock
  const displayEquityData = equityHistoryRef.current;

  useEffect(() => {
    if (state) {
      const point = {
        time: new Date(state.timestamp).toLocaleTimeString('en-GB', { hour12: false }),
        equity: state.account.equity,
        balance: state.account.balance,
      };
      equityHistoryRef.current = [...equityHistoryRef.current.slice(-99), point];
      setTick((t) => t + 1);
    }
  }, [state]);

  // Calculate drawdown periods
  const drawdownPeriods = useMemo(() => {
    if (displayEquityData.length < 2) return [];
    const periods: { start: string; end: string; depth: number }[] = [];
    let peak = displayEquityData[0].equity;
    let peakTime = displayEquityData[0].time;
    let ddStart: string | null = null;

    for (let i = 1; i < displayEquityData.length; i++) {
      const point = displayEquityData[i];
      if (point.equity > peak) {
        if (ddStart && peak - displayEquityData[i - 1].equity > peak * 0.01) {
          periods.push({ start: ddStart, end: displayEquityData[i - 1].time, depth: ((peak - displayEquityData[i - 1].equity) / peak) * 100 });
        }
        peak = point.equity;
        peakTime = point.time;
        ddStart = null;
      } else {
        const dd = ((peak - point.equity) / peak) * 100;
        if (dd > 1 && !ddStart) ddStart = peakTime;
      }
    }
    if (ddStart) {
      periods.push({ start: ddStart, end: displayEquityData[displayEquityData.length - 1].time, depth: ((peak - displayEquityData[displayEquityData.length - 1].equity) / peak) * 100 });
    }
    return periods;
  }, [displayEquityData]);

  // Extract trade markers from positions
  const tradeMarkers = useMemo(() => {
    if (!state?.positions || state.positions.length === 0 || displayEquityData.length === 0) return [];
    return state.positions.slice(0, 5).map((pos, idx) => ({
      time: displayEquityData[Math.min(idx, displayEquityData.length - 1)]?.time || displayEquityData[displayEquityData.length - 1]?.time,
      equity: pos.open_price > 0 ? pos.open_price : displayEquityData[displayEquityData.length - 1]?.equity,
      profit: pos.profit || 0,
      symbol: pos.symbol || 'UNKNOWN',
      type: pos.type,
    }));
  }, [state?.positions, displayEquityData]);

  if (!isConnected) {
    return (
      <PageContainer title="Overview" subtitle="Dashboard Overview">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center stagger-enter">
            <div className="w-4 h-4 rounded-full bg-danger mx-auto mb-4 animate-pulse-glow" />
            <p className="text-text-secondary text-lg">Connecting...</p>
            <p className="text-text-muted text-sm mt-1">Waiting for WebSocket connection</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  if (!state) {
    return (
      <PageContainer title="Overview" subtitle="Dashboard Overview">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center stagger-enter">
            <div className="w-4 h-4 rounded-full bg-warning mx-auto mb-4 animate-pulse" />
            <p className="text-text-secondary text-lg">Waiting for data...</p>
            <p className="text-text-muted text-sm mt-1">Connected but no state received yet</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  const { account, risk, performance, ai, positions, heartbeat, scalp, execution_mode } = state;
  const equityData = displayEquityData;
  const initialEquity = 50000; // Baseline for reference line

  const adapters = [
    { key: 'ONNX', data: ai.onnx },
    { key: 'Ensemble', data: ai.ensemble },
    { key: 'Transformer', data: ai.transformer },
    { key: 'NN', data: ai.nn },
  ] as const;

  const nn = ai.neural_net;
  const regime = ai.regime;

  return (
    <PageContainer title="Dashboard Overview" subtitle={execution_mode === 'LIVE' ? 'Live Trading Active' : 'Monitoring Mode'}>
      {/* Hero Section - Asymmetric Layout */}
      <div className="grid grid-cols-12 gap-6 mb-6">
        {/* Main Equity Card - Spans wider */}
        <div className="col-span-12 lg:col-span-8 glass-card-accent p-6 hover-lift stagger-enter" style={{ animationDelay: '0ms' }}>
          <div className="flex items-start justify-between mb-4">
            <div>
              <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">Total Equity</p>
              <p className="text-4xl lg:text-5xl font-extrabold text-text-primary text-numeral">
                <AnimatedCounter value={account.equity} decimals={2} prefix="$" />
              </p>
            </div>
            <div className="text-right">
              <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">Balance</p>
              <p className="text-2xl lg:text-3xl font-bold text-text-primary text-numeral">
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
                    <stop offset="0%" stopColor="rgba(0,212,170,0.4)" />
                    <stop offset="100%" stopColor="rgba(0,212,170,0)" />
                  </linearGradient>
                </defs>
                <ReferenceLine y={initialEquity} stroke="#64748b" strokeDasharray="3 3" strokeWidth={1} />
                <Area
                  type="monotone"
                  dataKey="equity"
                  stroke="#00d4aa"
                  fill="url(#heroEquityGrad)"
                  strokeWidth={2}
                  animationDuration={1000}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Quick Stats - Compact vertical stack */}
        <div className="col-span-12 lg:col-span-4 space-y-4">
          <div className="glass-card-warning p-4 hover-lift stagger-enter" style={{ animationDelay: '50ms' }}>
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Free Margin</p>
            <p className="text-2xl lg:text-3xl font-bold text-warning text-numeral">
              <AnimatedCounter value={account.free_margin} decimals={2} prefix="$" />
            </p>
            <div className="mt-2 text-xs text-text-muted">
              Margin Level: <span className="text-text-primary font-semibold">{account.margin_level.toFixed(1)}%</span>
            </div>
          </div>

          <div className={`p-4 hover-lift stagger-enter ${risk.current_drawdown_pct > 5 ? 'glass-card-danger' : 'glass-card'}`} style={{ animationDelay: '100ms' }}>
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Current Drawdown</p>
            <p className="text-2xl lg:text-3xl font-bold text-danger text-numeral">
              <AnimatedCounter value={risk.current_drawdown_pct} decimals={2} suffix="%" />
            </p>
            <div className="mt-2 h-2 bg-surface-2 rounded-full overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-accent-primary via-warning to-danger rounded-full transition-all duration-500"
                style={{ width: `${Math.min(risk.current_drawdown_pct * 10, 100)}%` }}
              />
            </div>
          </div>
        </div>
      </div>

      {/* Middle Row - Varied card sizes */}
      <div className="grid grid-cols-12 gap-6 mb-6">
        {/* Enhanced Equity Curve - Larger */}
        <div className="col-span-12 lg:col-span-7 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '0ms' }}>
          <div className="flex items-center justify-between mb-4">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium">Equity Curve with Trade Markers</p>
            <div className="flex items-center gap-2 text-xs">
              <span className="flex items-center gap-1 text-text-muted">
                <span className="w-2 h-2 rounded-full bg-success" /> Win
              </span>
              <span className="flex items-center gap-1 text-text-muted">
                <span className="w-2 h-2 rounded-full bg-danger" /> Loss
              </span>
            </div>
          </div>
          <div className="h-64">
            {equityData.length > 1 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={equityData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="equityGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="rgba(0,212,170,0.3)" />
                      <stop offset="100%" stopColor="rgba(0,212,170,0)" />
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
                    tickFormatter={(value) => `$${(value / 1000).toFixed(0)}k`}
                  />
                  <Tooltip
                    contentStyle={{
                      background: '#1a1f2e',
                      border: '1px solid rgba(148,163,184,0.1)',
                      borderRadius: 8,
                      fontSize: 12,
                      boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
                    }}
                    labelStyle={{ color: '#94a3b8' }}
                    itemStyle={{ color: '#00d4aa' }}
                    // eslint-disable-next-line @typescript-eslint/no-explicit-any
                    formatter={(value: any, name: any) => [value !== undefined ? `$${value.toFixed(2)}` : '$0.00', name === 'equity' ? 'Equity' : 'Balance']}
                  />
                  <ReferenceLine y={initialEquity} stroke="#64748b" strokeDasharray="3 3" />
                  {/* Drawdown period shading */}
                  {drawdownPeriods.slice(0, 3).map((dd, i) => (
                    <ReferenceArea key={i} x1={dd.start} x2={dd.end} fill="rgba(239, 68, 68, 0.05)" />
                  ))}
                  {/* Trade entry markers */}
                  {tradeMarkers.slice(0, 5).map((trade, i) => (
                    <ReferenceDot
                      key={i}
                      x={trade.time}
                      y={trade.equity}
                      fill={trade.profit >= 0 ? '#10b981' : '#ef4444'}
                      r={5}
                      strokeWidth={2}
                      stroke="#1a1f2e"
                    />
                  ))}
                  <Area
                    type="monotone"
                    dataKey="equity"
                    stroke="#00d4aa"
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
        <div className="col-span-12 lg:col-span-2 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '50ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Risk Budget</p>
          <div className="space-y-4">
            <RiskBar label="Daily" used={risk.daily_risk_used_pct} max={risk.max_daily_risk_pct} />
            <RiskBar label="Entry" used={risk.daily_entry_risk_pct} max={risk.max_daily_risk_pct} />
            <RiskBar label="Exposure" used={risk.open_exposure_pct} max={100} />
            <RiskBar label="Portfolio" used={risk.portfolio_risk_pct} max={100} />
          </div>
        </div>

        {/* Performance Summary - Medium */}
        <div className="col-span-12 lg:col-span-3 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '100ms' }}>
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
        {/* Left: Positions + Heartbeat + Scalp */}
        <div className="col-span-12 lg:col-span-3 space-y-4">
          <div className="glass-card-accent p-4 hover-lift stagger-enter" style={{ animationDelay: '0ms' }}>
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Open Positions</p>
            <p className="text-4xl font-bold text-text-primary text-numeral">
              <AnimatedCounter value={positions.length} decimals={0} />
            </p>
            {positions.length > 0 && (
              <div className="mt-2 text-xs text-text-muted">
                Total P&L:{' '}
                <span className={positions.reduce((s, p) => s + p.profit, 0) >= 0 ? 'text-success' : 'text-danger'}>
                  ${positions.reduce((s, p) => s + p.profit, 0).toFixed(2)}
                </span>
              </div>
            )}
          </div>

          <div className="glass-card p-4 hover-lift stagger-enter" style={{ animationDelay: '50ms' }}>
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Heartbeat Stats</p>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <HeartbeatStat label="Scans" value={heartbeat.scans} />
              <HeartbeatStat label="Signals" value={heartbeat.signals_generated} />
              <HeartbeatStat label="Validated" value={heartbeat.signals_validated} />
              <HeartbeatStat label="Opened" value={heartbeat.trades_opened} color="text-success" />
              <HeartbeatStat label="Shadow" value={heartbeat.shadow_trades} color="text-accent-tertiary" />
              <HeartbeatStat label="Spikes" value={heartbeat.spike_events} color="text-danger" />
            </div>
          </div>

          <div className="glass-card p-4 hover-lift stagger-enter" style={{ animationDelay: '100ms' }}>
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Scalp Mode</p>
            <div className="flex items-center gap-2 mb-3">
              <StatusBadge status={scalp.active ? 'online' : 'offline'} label={scalp.active ? 'Active' : 'Inactive'} size="sm" />
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

        {/* Center-Left: AI Subsystem */}
        <div className="col-span-12 lg:col-span-4 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '150ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">AI Subsystem Status</p>
          <div className="space-y-3">
            {adapters.map(({ key, data }) => (
              <div
                key={key}
                className={`flex items-center justify-between py-2.5 px-3 rounded-lg transition-all duration-200 ${
                  data.active ? 'bg-surface-2/50 hover:bg-surface-2' : 'opacity-50'
                }`}
              >
                <div className="flex items-center gap-3">
                  <StatusBadge status={data.active ? 'online' : 'offline'} label="" size="sm" />
                  <span className="text-text-primary font-semibold text-sm">{key}</span>
                </div>
                <div className="flex items-center gap-3 text-xs">
                  {data.votes !== undefined && (
                    <span className="text-text-muted">Votes: <span className="text-text-primary font-mono">{data.votes}</span></span>
                  )}
                  {data.accuracy !== undefined && (
                    <span className="text-text-muted">Acc: <span className="text-warning font-mono">{(data.accuracy * 100).toFixed(1)}%</span></span>
                  )}
                  {data.conf !== undefined && (
                    <span className="text-text-muted">Conf: <span className="text-accent-primary font-mono">{(data.conf * 100).toFixed(0)}%</span></span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Right: Neural Net Viz + Recent Alerts */}
        <div className="col-span-12 lg:col-span-5 space-y-4">
          {/* Neural Network Visualization */}
          <div className="glass-card p-4 hover-lift stagger-enter" style={{ animationDelay: '200ms' }}>
            <div className="flex items-center justify-between mb-3">
              <p className="text-text-secondary text-xs uppercase tracking-wider font-medium">Neural Network</p>
              <StatusBadge status={nn?.active ? 'online' : 'offline'} label={nn?.active ? 'Live' : 'Off'} size="sm" />
            </div>
            <div className="flex flex-col items-center justify-center">
              <NeuralNetViz
                confidence={nn?.confidence ?? 0.5}
                signal={nn?.signal ?? 'NONE'}
                training={true}
                regime={regime?.current ?? 'RANGE'}
                width={380}
                height={220}
              />
              <div className="flex items-center gap-4 mt-2 text-[10px] text-text-muted">
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-accent-primary" /> Active
                </span>
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-surface-3" /> Inactive
                </span>
                <span className="flex items-center gap-1">
                  <span className="w-2 h-2 rounded-full bg-warning animate-pulse" /> Training
                </span>
              </div>
            </div>
          </div>

          {/* Recent Alerts */}
          <div className="glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '250ms' }}>
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
                    className="flex items-start gap-2.5 text-xs py-2 px-3 rounded-lg hover:bg-surface-2/50 transition-colors duration-150"
                    style={{ animationDelay: `${idx * 30}ms` }}
                  >
                    <span
                      className={`w-2 h-2 rounded-full flex-shrink-0 mt-1 ${
                        a.severity === 'error' ? 'bg-danger' : a.severity === 'warning' ? 'bg-warning' : 'bg-accent-primary'
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
      </div>
    </PageContainer>
  );
}

function RiskBar({ label, used, max }: { label: string; used: number; max: number }) {
  const pct = Math.min((used / max) * 100, 100);
  const color = pct > 80 ? 'bg-danger' : pct > 50 ? 'bg-warning' : 'bg-accent-primary';
  return (
    <div>
      <div className="flex justify-between text-xs mb-1.5">
        <span className="text-text-muted font-medium">{label}</span>
        <span className="text-text-secondary font-mono">{used.toFixed(1)}%</span>
      </div>
      <div className="h-2 bg-surface-2 rounded-full overflow-hidden">
        <div className={`h-full ${color} rounded-full transition-all duration-500 ease-out`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

function MiniStat({ label, value, positive, trend }: { label: string; value: string; positive?: boolean; trend?: 'up' | 'down' | 'neutral' }) {
  return (
    <div className="bg-surface-2/30 rounded-lg p-2.5 hover:bg-surface-2/50 transition-colors duration-200">
      <p className="text-text-muted text-[10px] uppercase tracking-wider mb-0.5">{label}</p>
      <div className="flex items-center gap-1.5">
        <p className={`text-base font-bold ${positive === true ? 'text-success' : positive === false ? 'text-danger' : 'text-text-primary'} text-numeral`}>
          {value}
        </p>
        {trend && (
          <span className={`text-xs ${trend === 'up' ? 'text-success' : trend === 'down' ? 'text-danger' : 'text-text-muted'}`}>
            {trend === 'up' ? '↑' : trend === 'down' ? '↓' : '→'}
          </span>
        )}
      </div>
    </div>
  );
}

function HeartbeatStat({ label, value, color = 'text-text-primary' }: { label: string; value: number; color?: string }) {
  return (
    <div className="bg-surface-2/30 rounded p-2 text-center">
      <p className={`text-sm font-bold ${color} text-numeral`}>{value.toLocaleString()}</p>
      <p className="text-[10px] text-text-muted uppercase tracking-wider">{label}</p>
    </div>
  );
}