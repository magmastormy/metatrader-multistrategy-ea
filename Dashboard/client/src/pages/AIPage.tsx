import { useRef, useState, useEffect } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer,
} from 'recharts';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';
import StatusBadge from '../components/shared/StatusBadge';
import NeuralNetViz from '../components/shared/NeuralNetViz';
import RegimeGlow from '../components/shared/RegimeGlow';

export default function AIPage() {
  const { state, isConnected } = useEAState();
  const confHistoryRef = useRef<{ time: string; confidence: number; conformal: number }[]>([]);
  const regimeHistoryRef = useRef<{ time: string; trend: number; range: number; volatile: number; spike: number }[]>([]);
  const [, setTick] = useState(0);

  useEffect(() => {
    if (state?.ai?.neural_net) {
      const now = new Date(state.timestamp).toLocaleTimeString('en-GB', { hour12: false });
      const nn = state.ai.neural_net;
      const regime = state.ai.regime;

      confHistoryRef.current = [
        ...confHistoryRef.current.slice(-49),
        { time: now, confidence: nn.confidence ?? 0, conformal: nn.conformal_quantile ?? 0 },
      ];

      if (regime) {
        regimeHistoryRef.current = [
          ...regimeHistoryRef.current.slice(-49),
          {
            time: now,
            trend: (regime.trend_prob ?? 0.25) * 100,
            range: (regime.range_prob ?? 0.25) * 100,
            volatile: (regime.volatile_prob ?? 0.25) * 100,
            spike: (regime.spike_prob ?? 0.25) * 100,
          },
        ];
      }
      setTick((t) => t + 1);
    }
  }, [state]);

  if (!isConnected || !state) {
    return (
      <PageContainer title="AI Monitoring" subtitle="Neural Network & Regime Analysis">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center">
            <div className={`w-4 h-4 rounded-full mx-auto mb-4 animate-pulse ${!isConnected ? 'bg-danger' : 'bg-warning'}`} />
            <p className="text-text-secondary text-lg">{!isConnected ? 'Connecting...' : 'Waiting for data...'}</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  const { ai } = state;
  const nn = ai.neural_net;
  const regime = ai.regime;
  const meta = ai.meta_labeler;

  const nnActive = nn?.active ?? false;
  const confData = confHistoryRef.current;

  const signalColor = nn?.signal === 'BUY' ? 'text-success' : nn?.signal === 'SELL' ? 'text-danger' : 'text-text-muted';

  return (
    <PageContainer title="AI Monitoring" subtitle="Neural Network, Regime Detection & Adapter Status">
      {/* Top metrics */}
      <div className="grid grid-cols-2 md:grid-cols-6 gap-4 mb-6 stagger-enter" style={{ animationDelay: '0ms' }}>
        <div className="glass-card p-4 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">Neural Signal</p>
          <p className="text-2xl font-bold text-text-primary">{nn?.signal ?? '—'}</p>
        </div>
        <div className="glass-card p-4 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">Confidence</p>
          <p className="text-2xl font-bold text-text-primary">{nn?.confidence !== undefined ? `${(nn.confidence * 100).toFixed(1)}%` : '—'}</p>
        </div>
        <div className="glass-card p-4 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">Conformal Q</p>
          <p className="text-2xl font-bold text-text-primary">{nn?.conformal_quantile !== undefined ? nn.conformal_quantile.toFixed(3) : '—'}</p>
        </div>
        <div className="glass-card p-4 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">Regime</p>
          <p className="text-2xl font-bold text-text-primary">{regime?.current ?? '—'}</p>
        </div>
        <div className="glass-card p-4 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">Labels Resolved</p>
          <p className="text-2xl font-bold text-text-primary">{nn?.labels_resolved?.toString() ?? '—'}</p>
        </div>
        <div className="glass-card p-4 hover-lift">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">Training Steps</p>
          <p className="text-2xl font-bold text-text-primary">{nn?.training_steps?.toString() ?? '—'}</p>
        </div>
      </div>

      {/* Charts row */}
      <div className="grid grid-cols-12 gap-4 mb-6 stagger-enter" style={{ animationDelay: '50ms' }}>
        {/* Neural Network Visualization */}
        <div className="col-span-12 lg:col-span-5 glass-card p-4 flex flex-col items-center justify-center">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Neural Network</p>
          <NeuralNetViz
            confidence={nn?.confidence ?? 0.5}
            signal={nn?.signal ?? 'NONE'}
            training={true}
            regime={regime?.current ?? 'RANGE'}
            width={380}
            height={240}
          />
          <div className="flex items-center gap-4 mt-2 text-[10px] text-text-muted">
            <span className="flex items-center gap-1">
              <span className="w-2 h-2 rounded-full bg-accent-primary" /> Active
            </span>
            <span className="flex items-center gap-1">
              <span className="w-2 h-2 rounded-full bg-surface-4" /> Inactive
            </span>
            <span className="flex items-center gap-1">
              <span className="w-2 h-2 rounded-full bg-warning animate-pulse" /> Training
            </span>
          </div>
        </div>

        {/* Regime Glow */}
        <div className="col-span-12 lg:col-span-3 glass-card p-4 flex flex-col items-center justify-center">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-2">Market Regime</p>
          <RegimeGlow
            regime={regime?.current ?? 'RANGE'}
            confidence={Math.max(regime?.trend_prob ?? 0.25, regime?.range_prob ?? 0.25, regime?.volatile_prob ?? 0.25, regime?.spike_prob ?? 0.25)}
            size={160}
          />
          <div className="grid grid-cols-2 gap-x-6 gap-y-1 mt-3 text-[10px]">
            <span className="text-blue-400">Trend: {((regime?.trend_prob ?? 0.25) * 100).toFixed(0)}%</span>
            <span className="text-gray-400">Range: {((regime?.range_prob ?? 0.25) * 100).toFixed(0)}%</span>
            <span className="text-orange-400">Volatile: {((regime?.volatile_prob ?? 0.25) * 100).toFixed(0)}%</span>
            <span className="text-red-400">Spike: {((regime?.spike_prob ?? 0.25) * 100).toFixed(0)}%</span>
          </div>
        </div>

        {/* Confidence + Conformal chart */}
        <div className="col-span-12 lg:col-span-4 glass-card p-4">
          <div className="flex items-center justify-between mb-3">
            <p className="text-text-secondary text-xs uppercase tracking-wider font-medium">Confidence Timeline</p>
            <StatusBadge status={nnActive ? 'online' : 'offline'} label={nnActive ? 'Live' : 'Off'} size="sm" />
          </div>
          <div className="h-52">
            {confData.length > 1 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={confData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="confGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="rgba(0,212,170,0.3)" />
                      <stop offset="100%" stopColor="rgba(0,212,170,0)" />
                    </linearGradient>
                    <linearGradient id="conformalGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="rgba(249,115,22,0.3)" />
                      <stop offset="100%" stopColor="rgba(249,115,22,0)" />
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="time" tick={{ fontSize: 9, fill: '#64748b' }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fontSize: 9, fill: '#64748b' }} axisLine={false} tickLine={false} domain={[0, 1]} />
                  <Tooltip
                    contentStyle={{ background: '#1a1f2e', border: '1px solid rgba(148,163,184,0.1)', borderRadius: 8, fontSize: 11 }}
                    labelStyle={{ color: '#94a3b8' }}
                  />
                  <Area type="monotone" dataKey="confidence" name="Conf" stroke="#00d4aa" fill="url(#confGrad)" strokeWidth={2} />
                  <Area type="monotone" dataKey="conformal" name="CQ" stroke="#f97316" fill="url(#conformalGrad)" strokeWidth={1.5} strokeDasharray="4 2" />
                </AreaChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex items-center justify-center h-full text-text-muted text-sm">Collecting...</div>
            )}
          </div>
        </div>
      </div>

      {/* Bottom row: NN details + Meta-labeler + Adapters */}
      <div className="grid grid-cols-12 gap-4 stagger-enter" style={{ animationDelay: '100ms' }}>
        {/* Neural Network details */}
        <div className="col-span-12 lg:col-span-4 glass-card p-4">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Neural Network</p>
          <div className="space-y-2">
            <DetailRow label="Signal" value={nn?.signal ?? '—'} color={signalColor} />
            <DetailRow label="Confidence" value={nn?.confidence !== undefined ? `${(nn.confidence * 100).toFixed(1)}%` : '—'} />
            <DetailRow label="Conformal Q" value={nn?.conformal_quantile?.toFixed(3) ?? '—'} />
            <DetailRow label="Conformal α" value={nn?.conformal_alpha?.toFixed(4) ?? '—'} />
            <DetailRow label="Asset Class" value={nn?.asset_class?.toString() ?? '—'} />
            <DetailRow label="Barrier K" value={nn?.barrier_k?.toFixed(2) ?? '—'} />
            <DetailRow label="Vert Bars" value={nn?.barrier_vert_bars?.toString() ?? '—'} />
            <DetailRow label="Trade-Linked" value={nn?.trade_linked_labels?.toString() ?? '—'} />
            <DetailRow label="Norm Ready" value={nn?.normalization_ready ? 'YES' : 'NO'} />
            <DetailRow label="Labels Resolved" value={nn?.labels_resolved?.toString() ?? '—'} />
            <DetailRow label="Training Steps" value={nn?.training_steps?.toString() ?? '—'} />
          </div>
        </div>

        {/* Meta-labeler */}
        <div className="col-span-12 lg:col-span-4 glass-card p-4">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">Meta-Labeler (24 Features)</p>
          <div className="space-y-2">
            <DetailRow label="Features" value={meta?.features?.toString() ?? '—'} />
            <DetailRow label="Cooldown" value={meta?.cooldown?.toString() ?? '—'} />
            <DetailRow label="Early Stop Patience" value={meta?.early_stop_patience?.toString() ?? '—'} />
            <DetailRow label="Recent Win Rate" value={meta?.recent_win_rate !== undefined ? `${(meta.recent_win_rate * 100).toFixed(1)}%` : '—'} />
            <DetailRow label="Avg Confidence" value={meta?.recent_avg_confidence !== undefined ? `${(meta.recent_avg_confidence * 100).toFixed(1)}%` : '—'} />
            <DetailRow label="Samples Since Train" value={meta?.samples_since_train?.toString() ?? '—'} />
          </div>
          <div className="mt-4 pt-3 border-t border-border-subtle">
            <p className="text-text-muted text-[10px] uppercase tracking-wider mb-2">Input Features</p>
            <div className="grid grid-cols-2 gap-1 text-[10px] text-text-muted">
              <span>[0] Confidence</span>
              <span>[1-4] Regime</span>
              <span>[5] Vol Ratio</span>
              <span>[6-9] Probs</span>
              <span>[10] Conformal</span>
              <span>[11] Win Rate</span>
              <span>[12] Avg Conf</span>
              <span>[13-22] Features</span>
              <span>[23] Momentum</span>
              <span className="text-accent-primary">Total: 24</span>
            </div>
          </div>
        </div>

        {/* AI Adapters */}
        <div className="col-span-12 lg:col-span-4 glass-card p-4">
          <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-3">AI Adapters</p>
          <div className="space-y-3">
            {[
              { key: 'ONNX', data: ai.onnx },
              { key: 'Ensemble', data: ai.ensemble },
              { key: 'Transformer', data: ai.transformer },
              { key: 'NN', data: ai.nn },
            ].map(({ key, data }) => (
              <div key={key} className="flex items-center justify-between py-2 border-b border-border-subtle last:border-0">
                <div className="flex items-center gap-2">
                  <StatusBadge status={data.active ? 'online' : 'offline'} label={key} size="sm" />
                </div>
                <div className="flex items-center gap-3 text-xs text-text-muted">
                  {data.votes !== undefined && <span>Votes: {data.votes}</span>}
                  {data.conf !== undefined && <span>Conf: {(data.conf * 100).toFixed(0)}%</span>}
                  {data.accuracy !== undefined && <span>Acc: {(data.accuracy * 100).toFixed(1)}%</span>}
                </div>
              </div>
            ))}
          </div>
          <div className="mt-4 pt-3 border-t border-border-subtle">
            <p className="text-text-muted text-[10px] uppercase tracking-wider mb-2">Features: {ai.features_total ?? 65}</p>
            <div className="text-[10px] text-text-muted space-y-0.5">
              <p>57 base + 8 candlestick patterns</p>
              <p className="text-accent-primary">PinBar Engulf Doji Hammer</p>
              <p className="text-accent-primary">Shooting Star Morning/Evening</p>
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
}

function DetailRow({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="flex justify-between items-center py-1 border-b border-surface-600/50 last:border-0">
      <span className="text-text-muted text-xs">{label}</span>
      <span className={`text-xs font-mono ${color ?? 'text-text-primary'}`}>{value}</span>
    </div>
  );
}