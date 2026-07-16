import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import StatusBadge from '../components/shared/StatusBadge';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';

export default function StrategiesPage() {
  const { state, isConnected } = useEAState();

  if (!isConnected || !state) {
    return (
      <PageContainer title="Strategies" subtitle="Strategy Registry & Consensus">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center stagger-enter">
            <div className={`w-4 h-4 rounded-full mx-auto mb-4 animate-pulse ${!isConnected ? 'bg-danger' : 'bg-warning'}`} />
            <p className="text-text-secondary text-lg">{!isConnected ? 'Connecting...' : 'Waiting for data...'}</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  const { strategies, consensus } = state;

  // Group strategies by symbol
  const strategiesBySymbol = strategies.reduce((acc, s) => {
    if (!acc[s.symbol]) acc[s.symbol] = [];
    acc[s.symbol].push(s);
    return acc;
  }, {} as Record<string, typeof strategies>);

  const symbols = Object.keys(strategiesBySymbol);

  return (
    <PageContainer title="Strategies" subtitle={`${strategies.length} strategies across ${symbols.length} symbols`}>
      {/* Strategy Registry */}
      <div className="grid grid-cols-12 gap-6 mb-6">
        <div className="col-span-12 lg:col-span-7 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '0ms' }}>
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Strategy Registry</h3>
          <div className="space-y-3">
            {symbols.map(symbol => (
              <div key={symbol} className="space-y-2">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-text-primary font-semibold text-sm">{symbol}</span>
                  <span className="text-text-muted text-xs font-mono">{strategiesBySymbol[symbol].length} strategies</span>
                </div>
                {strategiesBySymbol[symbol].map((s, i) => (
                  <div
                    key={`${s.name}-${s.symbol}-${i}`}
                    className="glass-card p-3 flex items-center justify-between hover:border-border-emphasis transition-all duration-200"
                  >
                    <div className="flex items-center gap-3">
                      <span className="text-text-primary font-semibold text-sm">{s.name}</span>
                      <span className="text-text-muted text-xs font-mono">{s.symbol}</span>
                    </div>
                    <div className="flex items-center gap-4">
                      <span className="text-xs text-text-muted">{s.role}</span>
                      <StatusBadge
                        status={s.mode === 'ACTIVE' ? 'online' : s.mode === 'SHADOW' ? 'warning' : 'offline'}
                        label={s.mode}
                        size="sm"
                      />
                      <span className="text-xs text-text-secondary font-mono w-16 text-right">
                        W: {s.weight.toFixed(2)}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>

        {/* Consensus Summary */}
        <div className="col-span-12 lg:col-span-5 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '100ms' }}>
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Consensus Summary</h3>
          <div className="space-y-3">
            {Object.entries(consensus.symbols).map(([symbol, data]) => (
              <div key={symbol} className="glass-card p-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-text-primary font-semibold text-sm">{symbol}</span>
                  <StatusBadge
                    status={data.quorum_met ? 'online' : 'warning'}
                    label={data.quorum_met ? 'Quorum' : 'No Quorum'}
                    size="sm"
                  />
                </div>
                <div className="grid grid-cols-3 gap-2 text-xs mb-2">
                  <div>
                    <p className="text-text-muted">Signal</p>
                    <p className={`font-semibold ${data.last_signal === 'BUY' ? 'text-success' : data.last_signal === 'SELL' ? 'text-danger' : 'text-text-secondary'}`}>
                      {data.last_signal}
                    </p>
                  </div>
                  <div>
                    <p className="text-text-muted">Confidence</p>
                    <p className="text-text-primary font-semibold">{(data.confidence * 100).toFixed(1)}%</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Veto</p>
                    <p className="text-text-secondary font-mono text-[10px]">{data.veto_code || '—'}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Buy Score</p>
                    <p className="text-success font-mono">{data.buy_score.toFixed(2)}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Sell Score</p>
                    <p className="text-danger font-mono">{data.sell_score.toFixed(2)}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Cluster</p>
                    <p className="text-text-secondary">{data.dominant_cluster}</p>
                  </div>
                </div>
                <div className="text-[10px] text-text-muted">
                  {data.voted_strategies}/{data.active_strategies} strategies voted
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Strategy Weight Distribution Chart */}
      <div className="grid grid-cols-12 gap-6">
        <div className="col-span-12 glass-card p-5 hover-lift stagger-enter" style={{ animationDelay: '150ms' }}>
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Strategy Weight Distribution</h3>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={strategies} layout="vertical">
                <XAxis type="number" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <YAxis
                  dataKey="name"
                  type="category"
                  width={160}
                  tick={{ fontSize: 11, fill: '#94a3b8' }}
                  axisLine={false}
                  tickLine={false}
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
                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                  formatter={(value: any) => [value !== undefined ? `${value.toFixed(2)}` : '0.00', 'Weight']}
                />
                <Bar
                  dataKey="weight"
                  name="Weight"
                  radius={[0, 4, 4, 0]}
                  barSize={28}
                >
                  {strategies.map((s, i) => (
                    <Cell key={i} fill={s.mode === 'ACTIVE' ? 'rgba(0, 212, 170, 0.8)' : s.mode === 'SHADOW' ? 'rgba(245, 158, 11, 0.8)' : 'rgba(100, 116, 139, 0.5)'} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>
    </PageContainer>
  );
}