import { useEffect, useRef, useMemo } from 'react';

interface Node { x: number; y: number; layer: number; size: number; }
interface Connection { from: number; to: number; weight: number; active: boolean; }
interface Particle { x: number; y: number; targetX: number; targetY: number; progress: number; speed: number; color: string; size: number; }

interface NeuralNetVizProps {
  confidence?: number;
  signal?: string;
  training?: boolean;
  regime?: string;
  width?: number;
  height?: number;
  theme?: string;
}

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '');
  const n = h.length === 3 ? h.split('').map((c) => c + c).join('') : h;
  const int = parseInt(n, 16);
  return [(int >> 16) & 255, (int >> 8) & 255, int & 255];
}

function cssVar(name: string, fallback: string): string {
  if (typeof window === 'undefined') return fallback;
  const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return v || fallback;
}

export default function NeuralNetViz({
  confidence = 0.5, signal = 'NONE', training = false, regime = 'RANGE',
  width = 380, height = 240, theme,
}: NeuralNetVizProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animRef = useRef<number>(0);
  const nodesRef = useRef<Node[]>([]);
  const connectionsRef = useRef<Connection[]>([]);
  const particlesRef = useRef<Particle[]>([]);
  const timeRef = useRef(0);

  const layers = useMemo(() => [65, 32, 16, 8, 3], []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const accent = hexToRgb(cssVar('--accent', '#4f46e5'));
    const pos = hexToRgb(cssVar('--pos', '#15803d'));
    const neg = hexToRgb(cssVar('--neg', '#dc2626'));
    const warn = hexToRgb(cssVar('--warn', '#b45309'));
    const muted = hexToRgb(cssVar('--text-3', '#8a8a93'));

    const signalColor = signal === 'BUY' ? pos : signal === 'SELL' ? neg : muted;
    const regimeColor =
      regime === 'TREND' ? accent : regime === 'VOLAT' ? warn : regime === 'SPIKE' ? neg : muted;

    canvas.width = width * 2;
    canvas.height = height * 2;
    ctx.scale(2, 2);

    const nodes: Node[] = [];
    const padding = 34;
    const layerSpacing = (width - padding * 2) / (layers.length - 1);
    for (let l = 0; l < layers.length; l++) {
      const count = Math.min(layers[l], 11);
      const nodeSpacing = (height - padding * 2) / (count + 1);
      for (let n = 0; n < count; n++) {
        nodes.push({ x: padding + l * layerSpacing, y: padding + (n + 1) * nodeSpacing, layer: l, size: l === layers.length - 1 ? 4.5 : 2.4 });
      }
    }
    nodesRef.current = nodes;

    const connections: Connection[] = [];
    let nodeIdx = 0;
    for (let l = 0; l < layers.length - 1; l++) {
      const cur = Math.min(layers[l], 11);
      const nxt = Math.min(layers[l + 1], 11);
      const curStart = nodeIdx;
      const nxtStart = nodeIdx + cur;
      for (let i = 0; i < cur; i++) {
        for (let j = 0; j < nxt; j++) {
          if (Math.random() < 0.28) {
            connections.push({ from: curStart + i, to: nxtStart + j, weight: Math.random() - 0.5, active: Math.random() < confidence });
          }
        }
      }
      nodeIdx += cur;
    }
    connectionsRef.current = connections;

    const animate = () => {
      timeRef.current += 0.016;
      const t = timeRef.current;
      ctx.clearRect(0, 0, width, height);

      // faint connections
      for (const conn of connectionsRef.current) {
        const a = nodesRef.current[conn.from]; const b = nodesRef.current[conn.to];
        if (!a || !b) continue;
        const alpha = conn.active ? 0.10 + 0.06 * Math.sin(t * 2 + conn.from) : 0.035;
        ctx.beginPath();
        ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
        ctx.strokeStyle = conn.active
          ? `rgba(${signalColor[0]},${signalColor[1]},${signalColor[2]},${alpha})`
          : `rgba(${muted[0]},${muted[1]},${muted[2]},${alpha})`;
        ctx.lineWidth = 0.6 + Math.abs(conn.weight) * 0.4;
        ctx.stroke();
      }

      // training particles
      if (training && Math.random() < 0.12) {
        const act = connectionsRef.current.filter((c) => c.active);
        if (act.length) {
          const c = act[Math.floor(Math.random() * act.length)];
          const a = nodesRef.current[c.from]; const b = nodesRef.current[c.to];
          if (a && b) particlesRef.current.push({
            x: a.x, y: a.y, targetX: b.x, targetY: b.y, progress: 0,
            speed: 0.02 + Math.random() * 0.03,
            color: c.weight > 0 ? `rgba(${accent[0]},${accent[1]},${accent[2]},0.85)` : `rgba(${regimeColor[0]},${regimeColor[1]},${regimeColor[2]},0.85)`,
            size: 1.4 + Math.random() * 1.2,
          });
        }
      }
      particlesRef.current = particlesRef.current.filter((p) => {
        p.progress += p.speed;
        if (p.progress >= 1) return false;
        const e = p.progress < 0.5 ? 2 * p.progress * p.progress : 1 - Math.pow(-2 * p.progress + 2, 2) / 2;
        const px = p.x + (p.targetX - p.x) * e;
        const py = p.y + (p.targetY - p.y) * e;
        ctx.beginPath(); ctx.arc(px, py, p.size, 0, Math.PI * 2);
        ctx.fillStyle = p.color; ctx.fill();
        return true;
      });

      // nodes
      for (const node of nodesRef.current) {
        const pulse = 0.75 + 0.25 * Math.sin(t * 3 + node.x * 0.05 + node.y * 0.03);
        const isActive = node.layer === layers.length - 1 || Math.random() < confidence * 0.25;
        const r = node.size * pulse;
        ctx.beginPath(); ctx.arc(node.x, node.y, r, 0, Math.PI * 2);
        if (node.layer === layers.length - 1) {
          const al = 0.55 + 0.35 * pulse;
          ctx.fillStyle = `rgba(${signalColor[0]},${signalColor[1]},${signalColor[2]},${al})`;
        } else if (node.layer === 0) {
          ctx.fillStyle = `rgba(${muted[0]},${muted[1]},${muted[2]},${0.45})`;
        } else {
          ctx.fillStyle = `rgba(${signalColor[0]},${signalColor[1]},${signalColor[2]},${0.18 + 0.22 * pulse})`;
        }
        ctx.fill();
        // bright core
        ctx.beginPath(); ctx.arc(node.x, node.y, r * 0.4, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(255,255,255,${isActive ? 0.5 : 0.15})`;
        ctx.fill();
      }

      // layer labels
      const names = ['Input', 'Hidden 1', 'Hidden 2', 'Hidden 3', 'Output'];
      ctx.font = '9px ui-monospace, monospace';
      ctx.textAlign = 'center';
      for (let l = 0; l < layers.length; l++) {
        const x = 34 + l * ((width - 68) / (layers.length - 1));
        ctx.fillStyle = `rgba(${muted[0]},${muted[1]},${muted[2]},0.6)`;
        ctx.fillText(names[l], x, height - 6);
      }

      animRef.current = requestAnimationFrame(animate);
    };
    animRef.current = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(animRef.current);
  }, [width, height, layers, confidence, signal, training, regime, theme]);

  return <canvas ref={canvasRef} style={{ width, height }} className="rounded-lg" />;
}
