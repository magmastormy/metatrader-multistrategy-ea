type ModelKey = 'Neural Net (MLP)' | 'Transformer' | 'Ensemble' | 'ONNX' | 'Meta-Labeler';

const MODEL_KEYS: ModelKey[] = ['Neural Net (MLP)', 'Transformer', 'Ensemble', 'ONNX', 'Meta-Labeler'];

export function AIModelSelector({ selected, onSelect }: { selected: ModelKey; onSelect: (m: ModelKey) => void }) {
  return (
    <div className="seg" style={{ marginBottom: 12 }}>
      {MODEL_KEYS.map(m => (
        <button
          key={m}
          className={selected === m ? 'sel' : ''}
          onClick={() => onSelect(m)}
          style={{ borderRight: '1px solid var(--border)' }}
        >
          {m}
        </button>
      ))}
    </div>
  );
}