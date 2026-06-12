import { useRef, useState, useEffect } from 'react';
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import MetricCard from '../components/shared/MetricCard';
import StatusBadge from '../components/shared/StatusBadge';
import AnimatedCounter from '../components/shared/AnimatedCounter';

export default function OverviewPage() {
  const { state, alerts, isConnected } = useEAState();
  const equityHistoryRef = useRef<{ time: string; equity: number }[]>([]);
  const [, setTick] = useState(0);

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

  if (!isConnected) {
    return (
      <PageContainer title="Overview">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center">
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
          <div className="text-center">
            <div className="w-4 h-4 rounded-full bg-accent-amber mx-auto mb-4 animate-pulse" />
            <p className="text-text-secondary text-lg">Waiting for data...</p>
            <p className="text-text-muted text-sm mt-1">Connected but no state received yet</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  const { account, risk, performance, ai, positions, heartbeat, scalp } = state;
  const equityData = equityHistoryRef.current;

  const adapters = [
    { key: 'ONNX', data: ai.onnx },
    { key: 'Ensemble', data: ai.ensemble },
    { key: 'Transformer', data: ai.transformer },
    { key: 'NN', data: ai.nn },
  ] as const;

  return (
    <PageContainer title="Overview">
      {/* Top metrics row */}
      <div className="grid grid-cols-4 gap-4 mb-6">
        <MetricCard label="Balance" value={account.balance} prefix="$" />
        <MetricCard label="Equity" value={account.equity} prefix="$" sparkData={equityData.map((d) => d.equity)} />
        <MetricCard label="Free Margin" value={account.free_margin} prefix="$" />
        <MetricCard label="Drawdown" value={risk.current_drawdown_pct} suffix="%" />
      </div>

      {/* Middle row: equity curve + risk + performance */}
      <div className="grid grid-cols-12 gap-4 mb-6">
        {/* Equity curve */}
        <div className="col-span-7 glass-card p-4">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Equity Curve</p>
          <div className="h-52">
            {equityData.length > 1 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={equityData}>
                  <defs>
                    <linearGradient id="equityGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="rgba(34,211,238,0.3)" />
                      <stop offset="100%" stopColor="rgba(34,211,238,0)" />
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="time" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} domain={['auto', 'auto']} />
                  <Tooltip
                    contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 12 }}
                    labelStyle={{ color: '#94a3b8' }}
                    itemStyle={{ color: '#22d3ee' }}
                  />
                  <Area type="monotone" dataKey="equity" stroke="#22d3ee" fill="url(#equityGrad)" strokeWidth={2} />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex items-center justify-center h-full text-text-muted text-sm">
                Collecting equity data...
              </div>
            )}
          </div>
        </div>

        {/* Risk budget */}
        <div className="col-span-2 glass-card p-4">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Risk Budget</p>
          <div className="space-y-3">
            <RiskBar label="Daily" used={risk.daily_risk_used_pct} max={risk.max_daily_risk_pct} />
            <RiskBar label="Entry" used={risk.daily_entry_risk_pct} max={risk.max_daily_risk_pct} />
            <RiskBar label="Exposure" used={risk.open_exposure_pct} max={100} />
            <RiskBar label="Portfolio" used={risk.portfolio_risk_pct} max={100} />
          </div>
        </div>

        {/* Performance summary */}
        <div className="col-span-3 glass-card p-4">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Performance</p>
          <div className="grid grid-cols-2 gap-3">
            <MiniStat label="Win Rate" value={`${(performance.win_rate * 100).toFixed(1)}%`} />
            <MiniStat label="Profit Factor" value={performance.profit_factor.toFixed(2)} />
            <MiniStat label="Sharpe" value={performance.sharpe_ratio.toFixed(2)} />
            <MiniStat label="Recovery" value={performance.recovery_factor.toFixed(2)} />
            <MiniStat label="Net P/L" value={`$${performance.net_profit.toFixed(0)}`} positive={performance.net_profit >= 0} />
            <MiniStat label="Total Trades" value={performance.total_trades.toString()} />
          </div>
        </div>
      </div>

      {/* Bottom row */}
      <div className="grid grid-cols-12 gap-4">
        {/* Positions + Heartbeat + Scalp */}
        <div className="col-span-3 space-y-4">
          <div className="glass-card p-4">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Open Positions</p>
            <p className="text-3xl font-bold text-text-primary">
              <AnimatedCounter value={positions.length} decimals={0} />
            </p>
          </div>
          <div className="glass-card p-4">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Heartbeat</p>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <MiniStat label="Scans" value={heartbeat.scans.toString()} />
              <MiniStat label="Signals" value={heartbeat.signals_generated.toString()} />
              <MiniStat label="Validated" value={heartbeat.signals_validated.toString()} />
              <MiniStat label="Opened" value={heartbeat.trades_opened.toString()} />
              <MiniStat label="Shadow" value={heartbeat.shadow_trades.toString()} />
              <MiniStat label="Spikes" value={heartbeat.spike_events.toString()} />
            </div>
          </div>
          <div className="glass-card p-4">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Scalp Mode</p>
            <div className="flex items-center gap-2 mb-2">
              <StatusBadge status={scalp.active ? 'online' : 'offline'} label={scalp.active ? 'Active' : 'Inactive'} />
            </div>
            <div className="text-xs text-text-muted">
              {scalp.open_positions}/{scalp.max_positions} positions &middot; {scalp.total_entries} entries &middot; {scalp.total_rejections} rejected
            </div>
          </div>
        </div>

        {/* AI subsystem */}
        <div className="col-span-4 glass-card p-4">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">AI Subsystem</p>
          <div className="space-y-2">
            {adapters.map(({ key, data }) => (
              <div key={key} className="flex items-center justify-between py-1.5 border-b border-surface-600 last:border-0">
                <div className="flex items-center gap-2">
                  <StatusBadge status={data.active ? 'online' : 'offline'} label={key} />
                </div>
                <div className="flex items-center gap-4 text-xs text-text-muted">
                  {data.votes !== undefined && <span>Votes: {data.votes}</span>}
                  {data.accuracy !== undefined && <span>Acc: {(data.accuracy * 100).toFixed(1)}%</span>}
                  {data.conf !== undefined && <span>Conf: {(data.conf * 100).toFixed(0)}%</span>}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Recent alerts */}
        <div className="col-span-5 glass-card p-4">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Recent Alerts</p>
          {alerts.length === 0 ? (
            <p className="text-text-muted text-sm">No alerts yet</p>
          ) : (
            <div className="space-y-1 max-h-48 overflow-auto">
              {alerts.slice(0, 15).map((a) => (
                <div key={a.id} className="flex items-center gap-2 text-xs py-1 border-b border-surface-700 last:border-0">
                  <span
                    className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${
                      a.severity === 'error' ? 'bg-accent-red' : a.severity === 'warning' ? 'bg-accent-amber' : 'bg-accent-cyan'
                    }`}
                  />
                  <span className="text-text-muted font-mono flex-shrink-0">
                    {new Date(a.timestamp).toLocaleTimeString('en-GB', { hour12: false })}
                  </span>
                  <span className="text-text-secondary truncate">{a.message}</span>
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
      <div className="flex justify-between text-xs mb-1">
        <span className="text-text-muted">{label}</span>
        <span className="text-text-secondary font-mono">{used.toFixed(1)}%</span>
      </div>
      <div className="h-1.5 bg-surface-600 rounded-full overflow-hidden">
        <div className={`h-full ${color} rounded-full transition-all duration-500`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

function MiniStat({ label, value, positive }: { label: string; value: string; positive?: boolean }) {
  return (
    <div>
      <p className="text-text-muted text-[10px] uppercase tracking-wider">{label}</p>
      <p className={`text-sm font-semibold ${positive === true ? 'text-accent-green' : positive === false ? 'text-accent-red' : 'text-text-primary'}`}>
        {value}
      </p>
    </div>
  );
}
