import { useMemo, useEffect, useRef, useState } from 'react';

export function AttentionHeatmap({ attentionWeights, numHeads, seqLen }: { attentionWeights: number[]; numHeads: number; seqLen: number }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [hoveredCell, setHoveredCell] = useState<{ head: number; q: number; k: number; value: number } | null>(null);

  const matrix = useMemo(() => {
    if (!attentionWeights.length || numHeads <= 0 || seqLen <= 0) return null;
    const result: number[][][] = [];
    for (let h = 0; h < numHeads; h++) {
      const headMatrix: number[][] = [];
      for (let q = 0; q < seqLen; q++) {
        const row: number[] = [];
        for (let k = 0; k < seqLen; k++) {
          const idx = h * seqLen * seqLen + q * seqLen + k;
          row.push(attentionWeights[idx] ?? 0);
        }
        headMatrix.push(row);
      }
      result.push(headMatrix);
    }
    return result;
  }, [attentionWeights, numHeads, seqLen]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !matrix) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const cellSize = 8;
    const labelSize = 30;
    const headGap = 20;
    const width = numHeads * (seqLen * cellSize + labelSize) + (numHeads - 1) * headGap + labelSize;
    const height = seqLen * cellSize + labelSize * 2 + 40;

    canvas.width = width * 2;
    canvas.height = height * 2;
    canvas.style.width = width + 'px';
    canvas.style.height = height + 'px';
    ctx.scale(2, 2);

    const draw = () => {
      ctx.clearRect(0, 0, width, height);
      ctx.font = '10px monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';

      if (!matrix) {
        ctx.fillStyle = 'var(--text-3)';
        ctx.fillText('No attention data', width / 2, height / 2);
        return;
      }

      matrix.forEach((headMatrix, h) => {
        const headX = h * (seqLen * cellSize + labelSize + headGap) + labelSize;

        // Head label
        ctx.fillStyle = 'var(--text-2)';
        ctx.fillText(`Head ${h}`, headX + (seqLen * cellSize) / 2, 14);

        // Column indices
        for (let k = 0; k < seqLen; k++) {
          if (k % 5 === 0) {
            ctx.fillStyle = 'var(--text-3)';
            ctx.fillText(k.toString(), headX + k * cellSize + cellSize / 2, labelSize - 4);
          }
        }

        // Row indices & cells
        for (let q = 0; q < seqLen; q++) {
          if (q % 5 === 0) {
            ctx.fillStyle = 'var(--text-3)';
            ctx.textAlign = 'right';
            ctx.fillText(q.toString(), headX - 4, labelSize + q * cellSize + cellSize / 2);
            ctx.textAlign = 'center';
          }

          for (let k = 0; k < seqLen; k++) {
            const value = headMatrix[q][k];
            const x = headX + k * cellSize;
            const y = labelSize + q * cellSize;

            // Color map: blue (low) -> indigo -> violet -> red (high)
            const intensity = Math.min(value * 5, 1);
            const r = Math.round(79 + intensity * (220 - 79));
            const g = Math.round(70 * (1 - intensity));
            const b = Math.round(229 * (1 - intensity) + intensity * 38);
            ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
            ctx.fillRect(x, y, cellSize - 1, cellSize - 1);

            // Hover highlight
            if (hoveredCell && hoveredCell.head === h && hoveredCell.q === q && hoveredCell.k === k) {
              ctx.strokeStyle = '#fff';
              ctx.lineWidth = 1.5;
              ctx.strokeRect(x - 0.5, y - 0.5, cellSize, cellSize);
            }
          }
        }

        // Query/Key labels
        ctx.fillStyle = 'var(--text-2)';
        ctx.font = '9px Inter, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText('Query (t)', headX + (seqLen * cellSize) / 2, labelSize + seqLen * cellSize + 20);
        ctx.save();
        ctx.translate(headX - 12, labelSize + (seqLen * cellSize) / 2);
        ctx.rotate(-Math.PI / 2);
        ctx.fillText('Key (t)', 0, 0);
        ctx.restore();
      });
    };

    draw();
  }, [matrix, numHeads, seqLen, hoveredCell]);

  const handleMouseMove = (e: React.MouseEvent<HTMLCanvasElement>) => {
    if (!matrix) return;
    const canvas = e.currentTarget;
    const rect = canvas.getBoundingClientRect();
    const x = (e.clientX - rect.left) * 2; // scale
    const y = (e.clientY - rect.top) * 2;

    const cellSize = 8;
    const labelSize = 30;
    const headGap = 20;

    for (let h = 0; h < numHeads; h++) {
      const headX = h * (seqLen * cellSize + labelSize + headGap) + labelSize;
      if (x >= headX && x <= headX + seqLen * cellSize && y >= labelSize && y <= labelSize + seqLen * cellSize) {
        const q = Math.floor((y - labelSize) / cellSize);
        const k = Math.floor((x - headX) / cellSize);
        if (q >= 0 && q < seqLen && k >= 0 && k < seqLen) {
          setHoveredCell({ head: h, q, k, value: matrix[h][q][k] });
          return;
        }
      }
    }
    setHoveredCell(null);
  };

  const handleMouseLeave = () => setHoveredCell(null);

  if (!matrix) return <div className="empty">No attention weights available</div>;

  return (
    <div className="card">
      <div className="divider-label">Transformer Self-Attention (last layer)</div>
      <div style={{ position: 'relative' }}>
        <canvas
          ref={canvasRef}
          onMouseMove={handleMouseMove}
          onMouseLeave={handleMouseLeave}
          style={{ width: '100%', maxWidth: '100%', borderRadius: 8, background: 'var(--surface-2)', cursor: 'crosshair' }}
        />
        {hoveredCell && (
          <div className="note" style={{ marginTop: 8, fontFamily: 'monospace', fontSize: 11 }}>
            Head {hoveredCell.head} · Query t={hoveredCell.q} → Key t={hoveredCell.k} = {(hoveredCell.value * 100).toFixed(2)}%
          </div>
        )}
      </div>
      <div className="row" style={{ marginTop: 8, gap: 16, flexWrap: 'wrap', fontSize: 11, color: 'var(--text-3)' }}>
        <span>Blue = low attention · Red = high attention</span>
        <span>Hover cell for details</span>
        <span>SeqLen: {seqLen} · Heads: {numHeads}</span>
      </div>
    </div>
  );
}