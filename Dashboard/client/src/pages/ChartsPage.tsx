import { useRef, useState, useEffect } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer,
  LineChart, Line, BarChart, Bar, ReferenceLine,
  PieChart, Pie, Cell, Legend,
  ScatterChart, Scatter,
} from 'recharts';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';

export default function ChartsPage() {
  const { state, isConnected } = useEAState();
  const [timeframe, setTimeframe] = useState<'1h' | '4h' | '1d' | '1w'>('1h');

  const equityHistoryRef = useRef<{ time: string; equity: number; balance: number; drawdown: number }[]>([]);
  const [, setTick] = useState(0);

  useEffect(() => {
    if (state) {
      const point = {
        time: new Date(state.timestamp).toLocaleTimeString('en-GB', { hour12: false }),
        equity: state.account.equity,
        balance: state.account.balance,
        drawdown: state.risk.current_drawdown_pct,
      };
      equityHistoryRef.current = [...equityHistoryRef.current.slice(-200), point];
      setTick((t) => t + 1);
    }
  }, [state]);

  if (!isConnected || !state) {
    return (
      <PageContainer title="Charts" subtitle="Equity curves, risk history, and performance analytics">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center stagger-enter">
            <div className="w-4 h-4 rounded-full bg-danger mx-auto mb-4 animate-pulse-glow" />
            <p className="text-text-secondary text-lg">{!isConnected ? 'Connecting...' : 'Waiting for data...'}</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  const { account } = state;
  const equityData = equityHistoryRef.current;

  // Generate mock regime history for demo
  const regimeData = Array.from({ length: 50 }, (_, i) => ({
    time: new Date(Date.now() - (49 - i) * 1800000).toLocaleTimeString('en-GB', { hour12: false, hour: '2-digit', minute: '2-digit' }),
    trend: Math.max(0, 25 + Math.sin(i * 0.2) * 15 + Math.random() * 10),
    range: Math.max(0, 40 + Math.sin(i * 0.15) * 10 + Math.random() * 10),
    volatile: Math.max(0, 20 + Math.sin(i * 0.3) * 10 + Math.random() * 10),
    spike: Math.max(0, 5 + Math.sin(i * 0.5) * 5 + Math.random() * 5),
  }));

  return (
    <PageContainer title="Charts" subtitle="Equity, risk, and regime analytics">
      {/* Timeframe Selector */}
      <div className="flex items-center justify-between mb-6 stagger-enter">
        <div className="flex items-center gap-2">
          <span className="text-text-muted text-sm">Timeframe:</span>
          <div className="flex bg-surface-1 rounded-lg p-1" role="radiogroup">
            {(['1h', '4h', '1d', '1w'] as const).map(tf => (
              <button
                key={tf}
                onClick={() => setTimeframe(tf)}
                className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all duration-200 ${
                  timeframe === tf
                    ? 'bg-accent-primary/20 text-accent-primary shadow-sm'
                    : 'text-text-secondary hover:text-text-primary'
                }`}
                role="radio"
                aria-checked={timeframe === tf}
              >
                {tf}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Main Equity Curve */}
      <div className="grid grid-cols-12 gap-6 mb-6">
        <div className="col-span-12 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '0ms' }}>
          <div className="flex items-center justify-between mb-4">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium">Equity Curve</p>
            <div className="flex items-center gap-2 text-xs">
              <span className="flex items-center gap-1 text-text-muted">
                <span className="w-2 h-2 rounded-full bg-accent-primary" /> Equity
              </span>
              <span className="flex items-center gap-1 text-text-muted">
                <span className="w-2 h-2 rounded-full bg-text-muted" /> Balance
              </span>
            </div>
          </div>
          <div className="h-80">
            {equityData.length > 1 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={equityData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="eqGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="rgba(0,212,170,0.3)" />
                      <stop offset="100%" stopColor="rgba(0,212,170,0)" />
                    </linearGradient>
                    <linearGradient id="balGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="rgba(100,116,139,0.1)" />
                      <stop offset="100%" stopColor="rgba(100,116,139,0)" />
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="time" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
                  <YAxis tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} tickFormatter={(v: number) => `$${(v/1000).toFixed(0)}k`} />
                  <Tooltip
                    contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 12, boxShadow: '0 4px 12px rgba(0,0,0,0.3)' }}
                    labelStyle={{ color: '#94a3b8' }}
                    // eslint-disable-next-line @typescript-eslint/no-explicit-any
                    formatter={(value: any, name: any) => [value !== undefined ? `$${value.toFixed(2)}` : '$0.00', name === 'equity' ? 'Equity' : 'Balance']}
                  />
                  <ReferenceLine y={account.balance} stroke="#64748b" strokeDasharray="3 3" label={{ value: 'Balance', position: 'left', fill: '#64748b', fontSize: 10 }} />
                  <Area type="monotone" dataKey="equity" name="Equity" stroke="#00d4aa" fill="url(#eqGrad)" strokeWidth={2} />
                  <Area type="monotone" dataKey="balance" name="Balance" stroke="#64748b" fill="url(#balGrad)" strokeWidth={1} strokeDasharray="4 2" />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex items-center justify-center h-full text-text-muted text-sm">
                Collecting equity data...
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Row 2: Drawdown & Risk Metrics */}
      <div className="grid grid-cols-12 gap-6 mb-6">
        <div className="col-span-12 lg:col-span-6 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '50ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Drawdown Timeline</p>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={equityData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                <defs>
                  <linearGradient id="ddGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="rgba(239,68,68,0.2)" />
                    <stop offset="100%" stopColor="rgba(239,68,68,0)" />
                  </linearGradient>
                </defs>
                <XAxis dataKey="time" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} domain={[0, 'auto']} tickFormatter={(v: number) => `${v.toFixed(1)}%`} />
                <Tooltip contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 11 }} labelStyle={{ color: '#94a3b8' }} // eslint-disable-next-line @typescript-eslint/no-explicit-any
                formatter={(v: any) => [`${(v ?? 0).toFixed(2)}%`, 'Drawdown']} />
                <Area type="monotone" dataKey="drawdown" stroke="#ef4444" fill="url(#ddGrad)" strokeWidth={2} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="col-span-12 lg:col-span-6 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '100ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Risk Budget History</p>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={riskHistory} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                <XAxis dataKey="time" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} domain={[0, 100]} tickFormatter={(v: number) => `${v}%`} />
                <Tooltip contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 11 }} labelStyle={{ color: '#94a3b8' }} />
                <Line type="monotone" dataKey="dailyRisk" name="Daily Risk" stroke="#f59e0b" strokeWidth={2} dot={false} />
                <Line type="monotone" dataKey="exposure" name="Exposure" stroke="#00d4aa" strokeWidth={2} dot={false} strokeDasharray="4 2" />
                <Line type="monotone" dataKey="portfolio" name="Portfolio" stroke="#6366f1" strokeWidth={2} dot={false} strokeDasharray="8 4" />
                <Legend />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      {/* Row 3: Regime Probabilities & Performance Breakdown */}
      <div className="grid grid-cols-12 gap-6 mb-6">
        <div className="col-span-12 lg:col-span-6 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '150ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Regime Probabilities</p>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={regimeData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                <XAxis dataKey="time" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} domain={[0, 100]} tickFormatter={(v: number) => `${v}%`} />
                <Tooltip contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 11 }} labelStyle={{ color: '#94a3b8' }} // eslint-disable-next-line @typescript-eslint/no-explicit-any
                formatter={(v: any) => [`${(v ?? 0).toFixed(0)}%`, 'Probability']} />
                <Area type="monotone" dataKey="trend" name="Trend" stroke="#3b82f6" fill="rgba(59,130,246,0.1)" strokeWidth={2} />
                <Area type="monotone" dataKey="range" name="Range" stroke="#64748b" fill="rgba(100,116,139,0.1)" strokeWidth={2} />
                <Area type="monotone" dataKey="volatile" name="Volatile" stroke="#f97316" fill="rgba(249,115,22,0.1)" strokeWidth={2} />
                <Area type="monotone" dataKey="spike" name="Spike" stroke="#ef4444" fill="rgba(239,68,68,0.1)" strokeWidth={2} />
                <Legend />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="col-span-12 lg:col-span-6 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '200ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Performance Breakdown</p>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={performanceBreakdown} layout="vertical" margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                <XAxis type="number" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <YAxis dataKey="name" type="category" width={140} tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
                <Tooltip contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 11 }} labelStyle={{ color: '#94a3b8' }} />
                <Bar dataKey="value" radius={[0, 4, 4, 0]} barSize={30}>
                  {performanceBreakdown.map((_, i) => (
                    <Cell key={i} fill={i < 4 ? 'rgba(0,212,170,0.8)' : 'rgba(239,68,68,0.8)'} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      {/* Row 4: Trade Distribution & Win/Loss */}
      <div className="grid grid-cols-12 gap-6">
        <div className="col-span-12 lg:col-span-4 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '250ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Trade Duration Distribution</p>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={durationData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                <XAxis dataKey="range" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} tickFormatter={(v: number) => v >= 1000 ? `${(v/1000).toFixed(0)}k` : `${v}`} />
                <Tooltip contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 11 }} labelStyle={{ color: '#94a3b8' }} />
                <Bar dataKey="count" fill="rgba(0,212,170,0.7)" radius={[4, 4, 0, 0]} barSize={40} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="col-span-12 lg:col-span-4 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '300ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Win/Loss Ratio</p>
          <div className="h-64 flex items-center justify-center">
            <ResponsiveContainer width={200} height={200}>
              <PieChart>
                <Pie
                  data={winLossData}
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={80}
                  paddingAngle={2}
                  dataKey="value"
                  nameKey="name"
                  label={({ name, percent }) => `${name} ${((percent ?? 0) * 100).toFixed(0)}%`}
                  labelLine={false}
                >
                  {winLossData.map((_, i) => (
                    <Cell key={i} fill={i === 0 ? 'rgba(16,185,129,0.8)' : 'rgba(239,68,68,0.8)'} />
                  ))}
                </Pie>
                <Tooltip contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 11 }} // eslint-disable-next-line @typescript-eslint/no-explicit-any
                formatter={(v: any) => [`${v} trades`, 'Count']} />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="col-span-12 lg:col-span-4 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '350ms' }}>
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">P&L Scatter by Symbol</p>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <ScatterChart margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                <XAxis type="number" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} name="Duration (min)" />
                <YAxis type="number" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} name="P&L ($)" tickFormatter={(v: number) => `$${v}`} />
                <Tooltip contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 11 }} labelStyle={{ color: '#94a3b8' }} />
                <Scatter name="Trades" data={scatterData} fill="#00d4aa" stroke="#00d4aa" shape="circle" />
              </ScatterChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>
    </PageContainer>
  );
}

// Mock data for charts
const riskHistory = Array.from({ length: 30 }, (_, i) => ({
  time: new Date(Date.now() - (29 - i) * 3600000).toLocaleTimeString('en-GB', { hour12: false, hour: '2-digit', minute: '2-digit' }),
  dailyRisk: Math.max(0, 3 + Math.sin(i * 0.2) * 2 + Math.random() * 1),
  exposure: Math.max(0, 20 + Math.sin(i * 0.25) * 15 + Math.random() * 5),
  portfolio: Math.max(0, 15 + Math.sin(i * 0.3) * 10 + Math.random() * 3),
}));

const performanceBreakdown = [
  { name: 'Win Rate', value: 68.5 },
  { name: 'Profit Factor', value: 2.34 },
  { name: 'Sharpe Ratio', value: 1.45 },
  { name: 'Recovery Factor', value: 3.2 },
  { name: 'Max DD', value: 8.5 },
  { name: 'Avg Loss', value: 120 },
];

const durationData = [
  { range: '< 5m', count: 45 },
  { range: '5-15m', count: 32 },
  { range: '15-30m', count: 28 },
  { range: '30-60m', count: 18 },
  { range: '1-2h', count: 12 },
  { range: '2-4h', count: 8 },
  { range: '4-8h', count: 5 },
  { range: '> 8h', count: 3 },
];

const winLossData = [
  { name: 'Wins', value: 68 },
  { name: 'Losses', value: 32 },
];

const scatterData = Array.from({ length: 50 }, () => ({
  x: Math.random() * 480,
  y: (Math.random() - 0.5) * 400,
}));