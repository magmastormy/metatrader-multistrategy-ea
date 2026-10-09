import { useMemo } from 'react';
import type { EAAI, EAAINeuralNet, EAAIRegime } from '../../types/ea-state';

interface FlowStage {
  id: string;
  label: string;
  detail: string;
  status: 'active' | 'pending' | 'blocked' | 'bypassed';
  metric?: string;
  color: string;
}

export function SignalFlowDiagram({ ai, nn, regime }: { ai?: EAAI; nn?: EAAINeuralNet; regime?: EAAIRegime }) {
  const stages = useMemo((): FlowStage[] => {
    const isActive = ai?.neural_net?.active ?? false;
    const conf = ai?.neural_net?.confidence ?? 0;
    const conformalQ = ai?.neural_net?.conformal_quantile ?? 0;
    const metaWinRate = ai?.meta_labeler?.recent_win_rate ?? 0;
    const normReady = ai?.neural_net?.normalization_ready ?? false;

    return [
      {
        id: 'features',
        label: 'Feature Vector',
        detail: `65 features (RSI, ATR, Vol, ROC, patterns...) ${normReady ? '✓' : '✗'} normalized`,
        status: normReady ? 'active' : 'pending',
        color: '#4f46e5',
      },
      {
        id: 'neural-net',
        label: 'Neural Net (MLP)',
        detail: `65→32→16→8→3 | Conf: ${(conf * 100).toFixed(1)}% | Signal: ${ai?.neural_net?.signal ?? 'NONE'}`,
        status: isActive && conf > 0 ? 'active' : isActive ? 'pending' : 'bypassed',
        metric: conf > 0 ? `${(conf * 100).toFixed(1)}%` : undefined,
        color: '#4f46e5',
      },
      {
        id: 'conformal',
        label: 'Conformal Prediction',
        detail: `Quantile: ${(conformalQ * 100).toFixed(1)}% | α: ${(ai?.neural_net?.conformal_alpha ?? 0.05).toFixed(2)}`,
        status: isActive && conf > 0 ? (conformalQ < 0.5 ? 'active' : 'blocked') : 'bypassed',
        metric: `${(conformalQ * 100).toFixed(1)}%`,
        color: conformalQ < 0.5 ? '#15803d' : '#dc2626',
      },
      {
        id: 'meta-labeler',
        label: 'Meta-Labeler',
        detail: `Win Rate: ${(metaWinRate * 100).toFixed(1)}% | Cooldown: ${ai?.meta_labeler?.cooldown ?? 0} | Thresh: 52%`,
        status: isActive && conf > 0 ? (metaWinRate > 0.52 ? 'active' : 'blocked') : 'bypassed',
        metric: `${(metaWinRate * 100).toFixed(1)}% WR`,
        color: metaWinRate > 0.52 ? '#15803d' : '#dc2626',
      },
      {
        id: 'regime',
        label: 'Regime Filter',
        detail: `Current: ${regime?.current ?? 'RANGE'} | Trend: ${((regime?.trend_prob ?? 0) * 100).toFixed(0)}% Range: ${((regime?.range_prob ?? 0) * 100).toFixed(0)}%`,
        status: 'active',
        color: '#b45309',
      },
      {
        id: 'consensus',
        label: 'Consensus Vote',
        detail: `Ensemble: ${ai?.ensemble?.active ? '✓' : '✗'} | Transformer: ${ai?.transformer?.active ? '✓' : '✗'} | ONNX: ${ai?.onnx?.active ? '✓' : '✗'}`,
        status: 'active',
        color: '#4f46e5',
      },
    ];
  }, [ai, nn, regime]);

  return (
    <div className="card">
      <div className="divider-label">AI Signal Pipeline</div>
      <div className="stack" style={{ gap: 0 }}>
        {stages.map((stage, i) => (
          <div
            key={stage.id}
            style={{
              display: 'flex',
              alignItems: 'center',
              padding: '14px 16px',
              borderBottom: i < stages.length - 1 ? '1px solid var(--border-faint)' : 'none',
              background: i % 2 === 0 ? 'var(--surface)' : 'var(--surface-2)',
              position: 'relative',
            }}
          >
            {/* Connection line */}
            {i > 0 && (
              <div style={{
                position: 'absolute',
                left: 30,
                top: -16,
                bottom: -16,
                width: 2,
                background: 'linear-gradient(var(--border-faint), var(--accent-weak))',
                zIndex: 0,
              }} />
            )}

            {/* Stage number / status dot */}
            <div style={{
              position: 'relative',
              zIndex: 1,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              width: 64,
            }}>
              <div
                className={`status-dot ${stage.status}`}
                style={{
                  width: 14,
                  height: 14,
                  border: '2px solid var(--surface)',
                  boxShadow: stage.status === 'active' ? `0 0 8px ${stage.color}` : undefined,
                }}
              />
              <span className="mono dim" style={{ fontSize: 9, marginTop: 4, textAlign: 'center' }}>
                {i + 1}
              </span>
            </div>

            {/* Stage content */}
            <div style={{ flex: 1, minWidth: 0, zIndex: 1, paddingLeft: 16 }}>
              <div className="row between" style={{ gap: 12, marginBottom: 4 }}>
                <span className="strong" style={{ fontSize: 13 }}>{stage.label}</span>
                {stage.metric && (
                  <span className={`mono ${stage.status === 'blocked' ? 'neg' : stage.status === 'active' ? 'pos' : 'dim'}`} style={{ fontSize: 12 }}>
                    {stage.metric}
                  </span>
                )}
              </div>
              <span className="dim mono" style={{ fontSize: 11 }}>{stage.detail}</span>
            </div>

            {/* Status badge */}
            <div style={{ zIndex: 1, paddingLeft: 16 }}>
              <span className={`badge ${stage.status === 'active' ? 'on' : stage.status === 'blocked' ? 'neg' : stage.status === 'pending' ? 'warn' : ''}`}>
                {stage.status === 'active' ? 'PASS' : stage.status === 'blocked' ? 'BLOCKED' : stage.status === 'pending' ? 'WAIT' : 'BYPASS'}
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}