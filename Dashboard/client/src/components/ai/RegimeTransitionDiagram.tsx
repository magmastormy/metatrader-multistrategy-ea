import { useMemo, useState, useEffect, useRef } from 'react';
import type { EAAIRegime } from '../../types/ea-state';

interface RegimeNode {
  id: number;
  name: string;
  short: string;
  color: string;
  prob: number;
  x: number;
  y: number;
}

const REGIMES: RegimeNode[] = [
  { id: 0, name: 'Trending', short: 'TREND', color: '#4f46e5', prob: 0, x: 300, y: 100 },
  { id: 1, name: 'Ranging', short: 'RANGE', color: '#15803d', prob: 0, x: 100, y: 200 },
  { id: 2, name: 'Volatile', short: 'VOLAT', color: '#b45309', prob: 0, x: 300, y: 300 },
  { id: 3, name: 'Spike', short: 'SPIKE', color: '#dc2626', prob: 0, x: 500, y: 200 },
];

const DEFAULT_TRANSITIONS = [
  { from: 0, to: 0, prob: 0.70 }, { from: 0, to: 1, prob: 0.05 }, { from: 0, to: 2, prob: 0.20 }, { from: 0, to: 3, prob: 0.05 },
  { from: 1, to: 0, prob: 0.05 }, { from: 1, to: 1, prob: 0.70 }, { from: 1, to: 2, prob: 0.20 }, { from: 1, to: 3, prob: 0.05 },
  { from: 2, to: 0, prob: 0.10 }, { from: 2, to: 1, prob: 0.10 }, { from: 2, to: 2, prob: 0.75 }, { from: 2, to: 3, prob: 0.05 },
  { from: 3, to: 0, prob: 0.10 }, { from: 3, to: 1, prob: 0.10 }, { from: 3, to: 2, prob: 0.20 }, { from: 3, to: 3, prob: 0.60 },
];

export function RegimeTransitionDiagram({ regime, hmmTransitions }: { regime?: EAAIRegime; hmmTransitions?: number[][] }) {
  const [hoveredNode, setHoveredNode] = useState<number | null>(null);

  const nodes = useMemo(() => {
    if (!regime) return REGIMES.map(r => ({ ...r, prob: 0.25 }));
    return REGIMES.map(r => ({
      ...r,
      prob: r.id === 0 ? (regime.trend_prob ?? 0.25)
        : r.id === 1 ? (regime.range_prob ?? 0.25)
        : r.id === 2 ? (regime.volatile_prob ?? 0.25)
        : (regime.spike_prob ?? 0.25),
    }));
  }, [regime]);

  const transitions = useMemo(() => {
    if (hmmTransitions && hmmTransitions.length === 4) {
      return hmmTransitions.flatMap((row, i) =>
        row.map((prob, j) => ({ from: i, to: j, prob }))
      );
    }
    return DEFAULT_TRANSITIONS;
  }, [hmmTransitions]);

  const currentRegime = useMemo(() => {
    return nodes.reduce((a, b) => (b.prob > a.prob ? b : a), nodes[0]).id;
  }, [nodes]);

  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    if (!canvasRef.current) {
      canvasRef.current = document.createElement('canvas');
      canvasRef.current.width = 600;
      canvasRef.current.height = 400;
    }
    const ctx = canvasRef.current.getContext('2d');
    if (!ctx) return;

    const draw = () => {
      ctx.clearRect(0, 0, 600, 400);

      // Draw transitions
      transitions.forEach(t => {
        if (t.prob < 0.02) return;
        const from = nodes[t.from];
        const to = nodes[t.to];
        const isActive = from.id === currentRegime || to.id === currentRegime;

        ctx.beginPath();
        ctx.moveTo(from.x, from.y);
        // Curved line for self-transitions
        if (from.id === to.id) {
          ctx.quadraticCurveTo(from.x + 60, from.y - 60, to.x, to.y);
        } else {
          const midX = (from.x + to.x) / 2;
          const midY = (from.y + to.y) / 2;
          const dx = to.x - from.x;
          const dy = to.y - from.y;
          const perpX = -dy * 0.3;
          const perpY = dx * 0.3;
          ctx.quadraticCurveTo(midX + perpX, midY + perpY, to.x, to.y);
        }

        ctx.strokeStyle = isActive ? 'rgba(79, 70, 229, 0.6)' : 'rgba(140, 140, 150, 0.25)';
        ctx.lineWidth = isActive ? 2 : 1;
        ctx.setLineDash(isActive ? [] : [4, 4]);
        ctx.stroke();
        ctx.setLineDash([]);

        // Arrow head
        const angle = Math.atan2(to.y - from.y, to.x - from.x);
        const headLen = 10;
        ctx.beginPath();
        ctx.moveTo(to.x - headLen * Math.cos(angle - 0.3), to.y - headLen * Math.sin(angle - 0.3));
        ctx.lineTo(to.x, to.y);
        ctx.lineTo(to.x - headLen * Math.cos(angle + 0.3), to.y - headLen * Math.sin(angle + 0.3));
        ctx.fillStyle = ctx.strokeStyle;
        ctx.fill();

        // Label
        if (t.prob > 0.1 || isActive) {
          const labelX = (from.x + to.x) / 2 + (from.id === to.id ? 80 : 0);
          const labelY = (from.y + to.y) / 2 + (from.id === to.id ? -80 : 0);
          ctx.fillStyle = isActive ? '#4f46e5' : '#8a8a93';
          ctx.font = '10px monospace';
          ctx.textAlign = 'center';
          ctx.fillText((t.prob * 100).toFixed(0) + '%', labelX, labelY);
        }
      });

      // Draw nodes
      nodes.forEach(node => {
        const isCurrent = node.id === currentRegime;
        const isHovered = hoveredNode === node.id;

        // Outer glow for current regime
        if (isCurrent) {
          ctx.beginPath();
          ctx.arc(node.x, node.y, 50, 0, Math.PI * 2);
          const gradient = ctx.createRadialGradient(node.x, node.y, 30, node.x, node.y, 50);
          gradient.addColorStop(0, node.color + '40');
          gradient.addColorStop(1, node.color + '00');
          ctx.fillStyle = gradient;
          ctx.fill();
        }

        // Node circle
        ctx.beginPath();
        ctx.arc(node.x, node.y, isCurrent ? 36 : 32, 0, Math.PI * 2);
        ctx.fillStyle = isCurrent ? node.color : (isHovered ? node.color + 'CC' : node.color + 'EE');
        ctx.fill();

        // Border
        ctx.strokeStyle = isCurrent ? '#fff' : 'rgba(255,255,255,0.5)';
        ctx.lineWidth = isCurrent ? 3 : 1;
        ctx.stroke();

        // Probability ring
        if (node.prob > 0) {
          ctx.beginPath();
          ctx.arc(node.x, node.y, isCurrent ? 40 : 36, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * node.prob);
          ctx.strokeStyle = '#fff';
          ctx.lineWidth = 4;
          ctx.lineCap = 'round';
          ctx.stroke();
        }

        // Label
        ctx.fillStyle = '#fff';
        ctx.font = `bold ${isCurrent ? '13' : '11'}px Inter, sans-serif`;
        ctx.textAlign = 'center';
        ctx.fillText(node.short, node.x, node.y + 4);

        // Probability text
        ctx.fillStyle = 'rgba(255,255,255,0.9)';
        ctx.font = '10px monospace';
        ctx.fillText((node.prob * 100).toFixed(1) + '%', node.x, node.y + 22);
      });
    };

    draw();
  }, [nodes, transitions, currentRegime, hoveredNode]);

  return (
    <div className="card" style={{ position: 'relative' }}>
      <div className="divider-label">HMM Regime Transitions (learned)</div>
      <div style={{ position: 'relative', height: 400 }}>
        <canvas
          ref={canvasRef}
          width={600}
          height={400}
          style={{ width: '100%', height: '100%', borderRadius: 8, background: 'var(--surface-2)' }}
          onMouseMove={(e) => {
            const rect = e.currentTarget.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            const node = nodes.find(n => Math.hypot(x - n.x * rect.width / 600, y - n.y * rect.height / 400) < 30);
            setHoveredNode(node?.id ?? null);
          }}
          onMouseLeave={() => setHoveredNode(null)}
        />
      </div>
      <div className="netlegend" style={{ marginTop: 12 }}>
        {nodes.map(n => (
          <span key={n.id} className="li" style={{ color: n.id === currentRegime ? n.color : 'var(--text-2)' }}>
            <span className="sw" style={{ background: n.color, width: 10, height: 10, borderRadius: '50%' }} />
            {n.name} {(n.prob * 100).toFixed(1)}%
          </span>
        ))}
      </div>
    </div>
  );
}