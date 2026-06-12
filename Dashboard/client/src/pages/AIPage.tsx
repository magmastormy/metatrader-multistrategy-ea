import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import StatusBadge from '../components/shared/StatusBadge';

export default function AIPage() {
  const { state, isConnected } = useEAState();

  if (!isConnected || !state) {
    return (
      <PageContainer title="AI">
        <p className="text-text-muted">{!isConnected ? 'Connecting...' : 'Waiting for data...'}</p>
      </PageContainer>
    );
  }

  const { ai } = state;

  const adapters = [
    { key: 'ONNX', data: ai.onnx, desc: 'ONNX Runtime inference adapter' },
    { key: 'Ensemble', data: ai.ensemble, desc: 'Ensemble voting adapter' },
    { key: 'Transformer', data: ai.transformer, desc: 'Transformer model adapter' },
    { key: 'NN', data: ai.nn, desc: 'Neural network adapter' },
  ] as const;

  return (
    <PageContainer title="AI">
      <div className="grid grid-cols-2 gap-6">
        {adapters.map(({ key, data, desc }) => (
          <div
            key={key}
            className={`glass-card p-6 transition-all duration-200 hover:scale-[1.02] ${
              data.active ? 'hover:border-accent-cyan/30' : 'opacity-60'
            }`}
          >
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-lg font-bold text-text-primary">{key}</h3>
                <p className="text-text-muted text-xs mt-0.5">{desc}</p>
              </div>
              <StatusBadge status={data.active ? 'online' : 'offline'} label={data.active ? 'Active' : 'Inactive'} />
            </div>

            {data.active ? (
              <div className="grid grid-cols-3 gap-4">
                <StatBox label="Total Votes" value={data.votes?.toString() ?? '—'} />
                <StatBox label="Buy" value={data.buy?.toString() ?? '—'} color="text-accent-green" />
                <StatBox label="Sell" value={data.sell?.toString() ?? '—'} color="text-accent-red" />
                <StatBox label="None" value={data.none?.toString() ?? '—'} />
                <StatBox
                  label="Confidence"
                  value={data.conf !== undefined ? `${(data.conf * 100).toFixed(1)}%` : '—'}
                  color="text-accent-cyan"
                />
                <StatBox
                  label="Accuracy"
                  value={data.accuracy !== undefined ? `${(data.accuracy * 100).toFixed(1)}%` : '—'}
                  color="text-accent-amber"
                />
              </div>
            ) : (
              <div className="py-6 text-center">
                <p className="text-text-muted text-sm">Adapter not active</p>
              </div>
            )}

            {/* Vote distribution bar */}
            {data.active && data.votes && data.votes > 0 && (
              <div className="mt-4">
                <p className="text-text-muted text-[10px] uppercase tracking-wider mb-1">Vote Distribution</p>
                <div className="h-2 bg-surface-600 rounded-full overflow-hidden flex">
                  {data.buy !== undefined && (
                    <div className="h-full bg-accent-green transition-all duration-500" style={{ width: `${(data.buy / data.votes) * 100}%` }} />
                  )}
                  {data.sell !== undefined && (
                    <div className="h-full bg-accent-red transition-all duration-500" style={{ width: `${(data.sell / data.votes) * 100}%` }} />
                  )}
                  {data.none !== undefined && (
                    <div className="h-full bg-surface-500 transition-all duration-500" style={{ width: `${(data.none / data.votes) * 100}%` }} />
                  )}
                </div>
                <div className="flex justify-between text-[10px] text-text-muted mt-1">
                  <span>Buy {data.buy ?? 0}</span>
                  <span>Sell {data.sell ?? 0}</span>
                  <span>None {data.none ?? 0}</span>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </PageContainer>
  );
}

function StatBox({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="bg-surface-700/50 rounded-lg p-3">
      <p className="text-text-muted text-[10px] uppercase tracking-wider">{label}</p>
      <p className={`text-lg font-bold mt-0.5 ${color ?? 'text-text-primary'}`}>{value}</p>
    </div>
  );
}
