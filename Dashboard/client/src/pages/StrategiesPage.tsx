import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import StatusBadge from '../components/shared/StatusBadge';

export default function StrategiesPage() {
  const { state, isConnected } = useEAState();

  if (!isConnected || !state) {
    return (
      <PageContainer title="Strategies">
        <p className="text-text-muted">{!isConnected ? 'Connecting...' : 'Waiting for data...'}</p>
      </PageContainer>
    );
  }

  const { strategies, consensus } = state;

  return (
    <PageContainer title="Strategies">
      <div className="grid grid-cols-12 gap-6">
        {/* Strategy registry */}
        <div className="col-span-7">
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Strategy Registry</h3>
          <div className="space-y-2">
            {strategies.map((s, i) => (
              <div
                key={`${s.name}-${s.symbol}-${i}`}
                className="glass-card p-3 flex items-center justify-between hover:border-accent-cyan/30 transition-all duration-200"
              >
                <div className="flex items-center gap-3">
                  <span className="text-text-primary font-semibold text-sm">{s.name}</span>
                  <span className="text-text-muted text-xs font-mono">{s.symbol}</span>
                </div>
                <div className="flex items-center gap-4">
                  <span className="text-xs text-text-muted">{s.role}</span>
                  <span
                    className={`px-2 py-0.5 rounded text-xs font-medium ${
                      s.mode === 'ACTIVE'
                        ? 'bg-accent-green/15 text-accent-green'
                        : s.mode === 'SHADOW'
                          ? 'bg-accent-amber/15 text-accent-amber'
                          : 'bg-surface-600/50 text-text-muted'
                    }`}
                  >
                    {s.mode}
                  </span>
                  <span className="text-xs text-text-secondary font-mono w-16 text-right">
                    W: {s.weight.toFixed(2)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Consensus summary */}
        <div className="col-span-5">
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Consensus Summary</h3>
          <div className="space-y-2">
            {Object.entries(consensus.symbols).map(([symbol, data]) => (
              <div key={symbol} className="glass-card p-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-text-primary font-semibold text-sm">{symbol}</span>
                  <StatusBadge
                    status={data.quorum_met ? 'online' : 'warning'}
                    label={data.quorum_met ? 'Quorum' : 'No Quorum'}
                  />
                </div>
                <div className="grid grid-cols-3 gap-2 text-xs">
                  <div>
                    <p className="text-text-muted">Signal</p>
                    <p className={`font-semibold ${data.last_signal === 'BUY' ? 'text-accent-green' : data.last_signal === 'SELL' ? 'text-accent-red' : 'text-text-secondary'}`}>
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
                    <p className="text-accent-green font-mono">{data.buy_score.toFixed(2)}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Sell Score</p>
                    <p className="text-accent-red font-mono">{data.sell_score.toFixed(2)}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Cluster</p>
                    <p className="text-text-secondary">{data.dominant_cluster}</p>
                  </div>
                </div>
                <div className="mt-2 text-[10px] text-text-muted">
                  {data.voted_strategies}/{data.active_strategies} strategies voted
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </PageContainer>
  );
}
