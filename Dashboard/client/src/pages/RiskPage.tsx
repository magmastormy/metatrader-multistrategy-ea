import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import AnimatedCounter from '../components/shared/AnimatedCounter';

export default function RiskPage() {
  const { state, isConnected } = useEAState();

  if (!isConnected || !state) {
    return (
      <PageContainer title="Risk">
        <p className="text-text-muted">{!isConnected ? 'Connecting...' : 'Waiting for data...'}</p>
      </PageContainer>
    );
  }

  const { risk } = state;

  return (
    <PageContainer title="Risk">
      <div className="grid grid-cols-12 gap-6">
        {/* Risk gauges */}
        <div className="col-span-8 space-y-6">
          <GaugeBar
            label="Daily Risk Used"
            value={risk.daily_risk_used_pct}
            max={risk.max_daily_risk_pct}
            detail={`${risk.daily_risk_used_pct.toFixed(2)}% / ${risk.max_daily_risk_pct.toFixed(2)}%`}
          />
          <GaugeBar
            label="Daily Entry Risk"
            value={risk.daily_entry_risk_pct}
            max={risk.max_daily_risk_pct}
            detail={`${risk.daily_entry_risk_pct.toFixed(2)}% of ${risk.max_daily_risk_pct.toFixed(2)}% budget`}
          />
          <GaugeBar
            label="Open Exposure"
            value={risk.open_exposure_pct}
            max={100}
            detail={`${risk.open_exposure_pct.toFixed(2)}% of portfolio`}
          />
          <GaugeBar
            label="Portfolio Risk"
            value={risk.portfolio_risk_pct}
            max={100}
            detail={`${risk.portfolio_risk_pct.toFixed(2)}%`}
          />

          {/* Drawdown indicator */}
          <div className="bg-surface border border-border p-5">
            <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-3">Current Drawdown</p>
            <div className="flex items-end gap-4">
              <span className="text-4xl font-bold text-accent-2">
                <AnimatedCounter value={risk.current_drawdown_pct} suffix="%" />
              </span>
              <div className="flex-1">
                <div className="h-3 bg-surface-2 overflow-hidden">
                  <div
                    className="h-full transition-all duration-500"
                    style={{
                      width: `${Math.min(risk.current_drawdown_pct, 100)}%`,
                      background: `linear-gradient(90deg, #c8f53a, #e8541a)`,
                    }}
                  />
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Mode badges + gate stats */}
        <div className="col-span-4 space-y-4">
          <div className="bg-surface border border-border p-5">
            <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-4">Mode Status</p>
            <div className="space-y-3">
              <ModeBadge label="Conservative Mode" active={risk.conservative_mode} />
              <ModeBadge label="Emergency Mode" active={risk.emergency_mode} />
            </div>
          </div>

          <div className="bg-surface border border-border p-5">
            <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-4">Risk Gate</p>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-text-muted text-xs">Approved</p>
                <p className="text-accent text-2xl font-bold">
                  <AnimatedCounter value={risk.gate_approved} decimals={0} />
                </p>
              </div>
              <div>
                <p className="text-text-muted text-xs">Rejected</p>
                <p className="text-accent-2 text-2xl font-bold">
                  <AnimatedCounter value={risk.gate_rejected} decimals={0} />
                </p>
              </div>
            </div>
            <div className="mt-3">
              <div className="h-2 bg-surface-2 overflow-hidden flex">
                <div
                  className="h-full bg-accent transition-all duration-500"
                  style={{ width: `${risk.gate_approved / Math.max(risk.gate_approved + risk.gate_rejected, 1) * 100}%` }}
                />
                <div
                  className="h-full bg-accent-2 transition-all duration-500"
                  style={{ width: `${risk.gate_rejected / Math.max(risk.gate_approved + risk.gate_rejected, 1) * 100}%` }}
                />
              </div>
            </div>
          </div>

          <div className="bg-surface border border-border p-5">
            <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-3">Active Risk Per Trade</p>
            <p className="text-3xl font-bold text-accent">
              <AnimatedCounter value={risk.active_risk_per_trade_pct} suffix="%" />
            </p>
          </div>

          <div className="bg-surface border border-border p-5">
            <p className="text-text-muted text-xs uppercase tracking-wider font-medium mb-3">Daily MtM Loss</p>
            <p className="text-3xl font-bold text-accent-2">
              <AnimatedCounter value={risk.daily_mtm_loss_pct} suffix="%" />
            </p>
          </div>
        </div>
      </div>
    </PageContainer>
  );
}

function GaugeBar({ label, value, max, detail }: { label: string; value: number; max: number; detail: string }) {
  const pct = Math.min((value / max) * 100, 100);
  const color = pct > 80 ? '#e8541a' : pct > 50 ? '#c8f53a' : '#8a8a8a';
  return (
    <div className="bg-surface border border-border p-5">
      <div className="flex justify-between items-center mb-2">
        <p className="text-text-muted text-xs uppercase tracking-wider font-medium">{label}</p>
        <span className="text-text-muted text-xs font-mono">{detail}</span>
      </div>
      <div className="h-3 bg-surface-2 overflow-hidden">
        <div
          className="h-full transition-all duration-500"
          style={{ width: `${pct}%`, backgroundColor: color }}
        />
      </div>
    </div>
  );
}

function ModeBadge({ label, active }: { label: string; active: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-text-muted text-sm">{label}</span>
      <span
        className={`px-3 py-1 text-xs font-bold uppercase ${
          active
            ? 'bg-rust-15 text-accent-2 border border-accent-2/30 animate-pulse-solid'
            : 'bg-surface-2 text-text-muted border border-border'
        }`}
      >
        {active ? 'ACTIVE' : 'OFF'}
      </span>
    </div>
  );
}
