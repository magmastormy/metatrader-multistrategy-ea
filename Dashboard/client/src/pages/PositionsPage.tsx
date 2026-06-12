import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import AnimatedCounter from '../components/shared/AnimatedCounter';

export default function PositionsPage() {
  const { state, isConnected } = useEAState();

  if (!isConnected || !state) {
    return (
      <PageContainer title="Positions">
        <p className="text-text-muted">{!isConnected ? 'Connecting...' : 'Waiting for data...'}</p>
      </PageContainer>
    );
  }

  const { positions } = state;

  if (positions.length === 0) {
    return (
      <PageContainer title="Positions">
        <div className="glass-card p-8 text-center">
          <p className="text-text-secondary">No open positions</p>
          <p className="text-text-muted text-sm mt-1">Positions will appear here when trades are opened</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer title="Positions">
      <div className="glass-card overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-surface-600">
              <th className="text-left text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">Ticket</th>
              <th className="text-left text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">Symbol</th>
              <th className="text-left text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">Type</th>
              <th className="text-right text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">Lots</th>
              <th className="text-right text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">Open Price</th>
              <th className="text-right text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">Current</th>
              <th className="text-right text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">P&L</th>
              <th className="text-right text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">Duration</th>
              <th className="text-left text-text-muted text-xs uppercase tracking-wider font-medium px-4 py-3">Strategy</th>
            </tr>
          </thead>
          <tbody>
            {positions.map((p) => (
              <tr
                key={p.ticket}
                className="border-b border-surface-700 last:border-0 hover:bg-surface-700/50 transition-colors duration-200"
              >
                <td className="px-4 py-3 font-mono text-text-secondary">{p.ticket}</td>
                <td className="px-4 py-3 font-semibold text-text-primary">{p.symbol}</td>
                <td className="px-4 py-3">
                  <span
                    className={`px-2 py-0.5 rounded text-xs font-bold ${
                      p.type === 'BUY'
                        ? 'bg-accent-green/15 text-accent-green'
                        : 'bg-accent-red/15 text-accent-red'
                    }`}
                  >
                    {p.type}
                  </span>
                </td>
                <td className="px-4 py-3 text-right font-mono text-text-primary">{p.lots.toFixed(2)}</td>
                <td className="px-4 py-3 text-right font-mono text-text-secondary">{p.open_price.toFixed(5)}</td>
                <td className="px-4 py-3 text-right font-mono text-text-primary">{p.current_price.toFixed(5)}</td>
                <td className={`px-4 py-3 text-right font-mono font-semibold ${p.profit >= 0 ? 'text-accent-green' : 'text-accent-red'}`}>
                  <AnimatedCounter value={p.profit} decimals={2} prefix="$" />
                </td>
                <td className="px-4 py-3 text-right text-text-muted text-xs">
                  {formatDuration(p.duration_minutes)}
                </td>
                <td className="px-4 py-3 text-text-secondary text-xs">{p.strategy}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </PageContainer>
  );
}

function formatDuration(minutes: number): string {
  if (minutes < 60) return `${minutes}m`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h < 24) return `${h}h ${m}m`;
  const d = Math.floor(h / 24);
  const rh = h % 24;
  return `${d}d ${rh}h`;
}
