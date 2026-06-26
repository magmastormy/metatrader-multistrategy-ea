import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import AnimatedCounter from '../components/shared/AnimatedCounter';

export default function PositionsPage() {
  const { state, isConnected } = useEAState();

  if (!isConnected) {
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
        <div className="bg-surface border border-border p-8 text-center">
          <p className="text-text-muted">No open positions</p>
          <p className="text-text-muted text-sm mt-1">Positions will appear here when trades are opened</p>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer title="Positions">
      <div className="bg-surface border border-border overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border">
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
                className="border-b border-border last:border-0 hover:bg-surface-2 transition-colors duration-200"
              >
                <td className="px-4 py-3 font-mono text-text-muted">{p.ticket}</td>
                <td className="px-4 py-3 font-semibold text-text">{p.symbol}</td>
                <td className="px-4 py-3">
                  <span
                    className={`px-2 py-0.5 text-xs font-bold ${
                      p.type === 'BUY'
                        ? 'bg-accent-15 text-accent'
                        : 'bg-rust-15 text-accent-2'
                    }`}
                  >
                    {p.type}
                  </span>
                </td>
                <td className="px-4 py-3 text-right font-mono text-text">{p.lots.toFixed(2)}</td>
                <td className="px-4 py-3 text-right font-mono text-text-muted">{p.open_price.toFixed(5)}</td>
                <td className="px-4 py-3 text-right font-mono text-text">{p.current_price.toFixed(5)}</td>
                <td className={`px-4 py-3 text-right font-mono font-semibold ${p.profit >= 0 ? 'text-accent' : 'text-accent-2'}`}>
                  <AnimatedCounter value={p.profit} decimals={2} prefix="$" />
                </td>
                <td className="px-4 py-3 text-right text-text-muted text-xs">
                  {formatDuration(p.duration_minutes)}
                </td>
                <td className="px-4 py-3 text-text-muted text-xs">{p.strategy}</td>
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
  const h = Math.floor(mi