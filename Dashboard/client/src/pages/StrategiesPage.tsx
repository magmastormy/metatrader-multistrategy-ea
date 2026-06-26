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
          <h3 className="text-text-muted text-xs uppercase tracking-wider font-medium mb-3">Strategy Registry</h3>
          <div className="space-y-2">
            {strategies.map((s, i) => (
              <div
                key={`${s.name}-${s.symbol}-${i}`}
                className="bg-surface border border-border p-3 flex items-center justify-between hover:border-accent/30 transition-all duration-200"
              >
                <div className="flex items-center gap-3">
                  <span className="text-text font-semibold text-sm">{s.name}</span>
                  <span className="text-text-muted text-xs font-mono">{s.symbol}</span>
                </div>
                <div className="flex items-center gap-4">
                  <span className="text-xs text-text-muted">{s.role}</span>
                  <span
                    className={`px-2 py-0.5 text-xs font-medium ${
                      s.mode === 'ACTIVE'
                        ? 'bg-accent-15 text-accent'
                        : s.mode === 'SHADOW'
                          ? 'bg-rust-15 text-accent-2'
                          : 'bg-surface-2 text-text-muted'
                    }`}
                  >
                    {s.mode}
                  </span>
                  <span className="text-xs text-text-muted font-mono w-16 text-right">
                    W: {s.weight.toFixed(2)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Consensus summary */}
        <div className="col-span-5">
          <h3 className="text-text-muted text-xs uppercase tracking-wider font-medium mb-3">Consensus Summary</h3>
          <div className="space-y-2">
            {Object.entries(consensus.symbols).map(([symbol, data]) => (
              <div key={symbol} className="bg-surface border border-border p-3">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-text font-semibold text-sm">{symbol}</span>
                  <StatusBadge
                    status={data.quorum_met ? 'online' : 'warning'}
                    label={data.quorum_met ? 'Quorum' : 'No Quorum'}
                  />
                </div>
                <div className="grid grid-cols-3 gap-2 text-xs">
                  <div>
                    <p className="text-text-muted">Signal</p>
                    <p className={`font-semibold ${data.last_signal === 'BUY' ? 'text-accent' : data.last_signal === 'SELL' ? 'text-accent-2' : 'text-text-muted'}`}>
                      {data.last_signal}
                    </p>
                  </div>
                  <div>
                    <p className="text-text-muted">Confidence</p>
                    <p className="text-text font-semibold">{(data.confidence * 100).toFixed(1)}%</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Veto</p>
                    <p className="text-text-muted font-mono text-[10px]">{data.veto_code || '—'}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Buy Score</p>
                    <p className="text-accent font-mono">{data.buy_score.toFixed(2)}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Sell Score</p>
                    <p className="text-accent-2 font-mono">{data.sell_score.toFixed(2)}</p>
                  </div>
                  <div>
                    <p className="text-text-muted">Cluster</p>
                    <p className="text-text-muted">{data.dominant_cluster}</p>
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
