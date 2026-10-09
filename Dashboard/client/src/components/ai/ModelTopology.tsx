import { useMemo } from 'react';

interface Layer {
  name: string;
  type: string;
  size: number | string;
  activation?: string;
  params?: number | string;
}

interface ModelArch {
  name: string;
  layers: Layer[];
  totalParams: number;
}

const ARCHITECTURES: Record<string, ModelArch> = {
  'Neural Net (MLP)': {
    name: 'Neural Net (MLP)',
    totalParams: 65 * 32 + 32 * 16 + 16 * 8 + 8 * 3 + 32 + 16 + 8 + 3,
    layers: [
      { name: 'Input', type: 'Dense', size: 65, params: 0 },
      { name: 'Hidden 1', type: 'Dense', size: 32, activation: 'ReLU', params: 65 * 32 + 32 },
      { name: 'Hidden 2', type: 'Dense', size: 16, activation: 'ReLU', params: 32 * 16 + 16 },
      { name: 'Hidden 3', type: 'Dense', size: 8, activation: 'ReLU', params: 16 * 8 + 8 },
      { name: 'Output', type: 'Dense', size: 3, activation: 'Softmax', params: 8 * 3 + 3 },
    ],
  },
  'Transformer': {
    name: 'Transformer (Pre-norm)',
    totalParams: 64 * 64 * 3 + 64 * 128 * 2 + 64 * 4 * 2,
    layers: [
      { name: 'Input Proj', type: 'Linear', size: 64, params: 65 * 64 },
      { name: 'LayerNorm', type: 'Norm', size: 64, params: 64 * 2 },
      { name: 'MHA (4 heads)', type: 'Attention', size: 64, params: 64 * 64 * 3 },
      { name: 'Residual + LN', type: 'Residual', size: 64, params: 64 * 2 },
      { name: 'FFN (128)', type: 'FeedForward', size: 128, activation: 'ReLU', params: 64 * 128 * 2 + 128 + 64 },
      { name: 'Residual + LN', type: 'Residual', size: 64, params: 64 * 2 },
      { name: 'Pool (mean)', type: 'Pool', size: 64, params: 0 },
      { name: 'Classification Head', type: 'Linear', size: 3, params: 64 * 3 + 3 },
      { name: 'Pattern Head', type: 'Linear', size: 10, params: 64 * 10 + 10 },
    ],
  },
  'Ensemble': {
    name: 'Ensemble (4 Models)',
    totalParams: 4 * (32 * 32 * 3 + 32 * 96 * 2 + 32 * 4 * 2),
    layers: [
      { name: 'Short-term (20 steps)', type: 'Transformer', size: 32, params: 32 * 32 * 3 + 32 * 96 * 2 },
      { name: 'Medium-term (40 steps)', type: 'Transformer', size: 32, params: 32 * 32 * 3 + 32 * 96 * 2 },
      { name: 'Long-term (60 steps)', type: 'Transformer', size: 32, params: 32 * 32 * 3 + 32 * 96 * 2 },
      { name: 'Vol-focused (30 steps, 8H)', type: 'Transformer', size: 32, params: 32 * 32 * 3 + 32 * 128 * 2 },
      { name: 'Kelly Reweighting', type: 'Meta', size: 4, params: 4 },
      { name: 'HMM Regime (4 states)', type: 'HMM', size: 4, params: 4 * 4 + 4 * 3 },
    ],
  },
  'ONNX': {
    name: 'ONNX Runtime',
    totalParams: 0,
    layers: [
      { name: 'Input', type: 'Tensor', size: '60×65', params: 0 },
      { name: 'Model', type: 'ONNX Graph', size: '?', params: 'External' },
      { name: 'Output', type: 'Logits', size: 3, params: 0 },
      { name: 'Softmax + Temp', type: 'Post', size: 3, params: 0 },
    ],
  },
  'Meta-Labeler': {
    name: 'Meta-Labeler (MLP)',
    totalParams: 24 * 24 + 24 * 2 + 24 + 2,
    layers: [
      { name: 'Input', type: 'Dense', size: 24, params: 0 },
      { name: 'Hidden', type: 'Dense', size: 24, activation: 'ReLU', params: 24 * 24 + 24 },
      { name: 'Output', type: 'Dense', size: 2, activation: 'Sigmoid', params: 24 * 2 + 2 },
    ],
  },
};

export function ModelTopology({ modelName }: { modelName: string }) {
  const arch = useMemo(() => ARCHITECTURES[modelName], [modelName]);

  if (!arch) return <div className="empty">Select a model</div>;

  return (
    <div className="card">
      <div className="divider-label">{arch.name} · {arch.totalParams.toLocaleString()} params</div>
      <div className="stack" style={{ gap: 8 }}>
        {arch.layers.map((layer, i) => (
          <div key={i} className="row between" style={{ padding: '8px 12px', border: '1px solid var(--border)', borderRadius: 8, background: i % 2 === 0 ? 'var(--surface-2)' : 'var(--surface)' }}>
            <div className="row" style={{ gap: 10, alignItems: 'center' }}>
              <span className="strong mono" style={{ fontSize: 13, minWidth: 100 }}>{layer.name}</span>
              <span className="badge">{layer.type}</span>
              {layer.activation && <span className="tag accent">{layer.activation}</span>}
            </div>
            <div className="row" style={{ gap: 12, alignItems: 'center' }}>
              <span className="mono dim" style={{ fontSize: 12 }}>{layer.size}</span>
              {layer.params !== undefined && (
                <span className="mono" style={{ fontSize: 12, color: 'var(--accent)' }}>
                  {typeof layer.params === 'number' ? layer.params.toLocaleString() : layer.params} params
                </span>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}