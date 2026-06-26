import { useEffect, useRef, useMemo } from 'react';

interface Node {
  x: number;
  y: number;
  layer: number;
  activation: number;
  size: number;
}

interface Connection {
  from: number;
  to: number;
  weight: number;
  active: boolean;
}

interface Particle {
  x: number;
  y: number;
  targetX: number;
  targetY: number;
  progress: number;
  speed: number;
  color: string;
  size: number;
}

interface NeuralNetVizProps {
  confidence?: number;
  signal?: string;
  training?: boolean;
  regime?: string;
  width?: number;
  height?: number;
}

export default function NeuralNetViz({
  confidence = 0.5,
  signal = 'NONE',
  training = false,
  regime = 'RANGE',
  width = 400,
  height = 300,
}: NeuralNetVizProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animRef = useRef<number>(0);
  const nodesRef = useRef<Node[]>([]);
  const connectionsRef = useRef<Connection[]>([]);
  const particlesRef = useRef<Particle[]>([]);
  const timeRef = useRef(0);

  const layers = useMemo(() => [65, 32, 16, 8, 3], []);

  const signalColor = signal === 'BUY' ? [34, 211, 238] : signal === 'SELL' ? [239, 68, 68] : [148, 163, 184];
  const regimeColor = regime === 'TREND' ? [59, 130, 246] : regime === 'VOLAT' ? [249, 115, 22] : regime === 'SPIKE' ? [239, 68, 68] : [107, 114, 128];

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    canvas.width = width * 2;
    canvas.height = height * 2;
    ctx.scale(2, 2);

    // Generate nodes
    const nodes: Node[] = [];
    const padding = 40;
    const layerSpacing = (width - padding * 2) / (layers.length - 1);

    for (let l = 0; l < layers.length; l++) {
      const count = Math.min(layers[l], 12); // Cap visible nodes
      const nodeSpacing = (height - padding * 2) / (count + 1);
      for (let n = 0; n < count; n++) {
        nodes.push({
          x: padding + l * layerSpacing,
          y: padding + (n + 1) * nodeSpacing,
          layer: l,
          activation: Math.random(),
          size: l === layers.length - 1 ? 6 : 3 + (1 - l / layers.length) * 2,
        });
      }
    }
    nodesRef.current = nodes;

    // Generate connections
    const connections: Connection[] = [];
    let nodeIdx = 0;
    for (let l = 0; l < layers.length - 1; l++) {
      const currentCount = Math.min(layers[l], 12);
      const nextCount = Math.min(layers[l + 1], 12);
      const currentStart = nodeIdx;
      const nextStart = nodeIdx + currentCount;
      for (let i = 0; i < currentCount; i++) {
        for (let j = 0; j < nextCount; j++) {
          if (Math.random() < 0.3) { // Sparse connections for visual clarity
            connections.push({
              from: currentStart + i,
              to: nextStart + j,
              weight: (Math.random() - 0.5) * 2,
              active: Math.random() < confidence,
            });
          }
        }
      }
      nodeIdx += currentCount;
    }
    connectionsRef.current = connections;

    // Animation loop
    const animate = () => {
      timeRef.current += 0.016;
      const t = timeRef.current;

      ctx.clearRect(0, 0, width, height);

      // Background glow
      const bgGrad = ctx.createRadialGradient(width / 2, height / 2, 0, width / 2, height / 2, width / 2);
      bgGrad.addColorStop(0, `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, 0.03)`);
      bgGrad.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = bgGrad;
      ctx.fillRect(0, 0, width, height);

      // Draw connections
      for (const conn of connectionsRef.current) {
        const fromNode = nodesRef.current[conn.from];
        const toNode = nodesRef.current[conn.to];
        if (!fromNode || !toNode) continue;

        const alpha = conn.active ? 0.15 + 0.1 * Math.sin(t * 2 + conn.from) : 0.04;
        const weight = Math.abs(conn.weight);
        ctx.beginPath();
        ctx.moveTo(fromNode.x, fromNode.y);
        ctx.lineTo(toNode.x, toNode.y);
        ctx.strokeStyle = conn.active
          ? `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, ${alpha})`
          : `rgba(100, 100, 120, ${alpha})`;
        ctx.lineWidth = 0.5 + weight * 0.5;
        ctx.stroke();
      }

      // Spawn particles on active connections
      if (training && Math.random() < 0.15) {
        const activeConns = connectionsRef.current.filter(c => c.active);
        if (activeConns.length > 0) {
          const conn = activeConns[Math.floor(Math.random() * activeConns.length)];
          const fromNode = nodesRef.current[conn.from];
          const toNode = nodesRef.current[conn.to];
          if (fromNode && toNode) {
            particlesRef.current.push({
              x: fromNode.x,
              y: fromNode.y,
              targetX: toNode.x,
              targetY: toNode.y,
              progress: 0,
              speed: 0.02 + Math.random() * 0.03,
              color: conn.weight > 0
                ? `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, 0.9)`
                : `rgba(${regimeColor[0]}, ${regimeColor[1]}, ${regimeColor[2]}, 0.9)`,
              size: 1.5 + Math.random() * 1.5,
            });
          }
        }
      }

      // Update and draw particles
      particlesRef.current = particlesRef.current.filter(p => {
        p.progress += p.speed;
        if (p.progress >= 1) return false;

        const ease = p.progress < 0.5 ? 2 * p.progress * p.progress : 1 - Math.pow(-2 * p.progress + 2, 2) / 2;
        const px = p.x + (p.targetX - p.x) * ease;
        const py = p.y + (p.targetY - p.y) * ease;

        // Glow
        const glowGrad = ctx.createRadialGradient(px, py, 0, px, py, p.size * 3);
        glowGrad.addColorStop(0, p.color);
        glowGrad.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.fillStyle = glowGrad;
        ctx.fillRect(px - p.size * 3, py - p.size * 3, p.size * 6, p.size * 6);

        // Core
        ctx.beginPath();
        ctx.arc(px, py, p.size, 0, Math.PI * 2);
        ctx.fillStyle = p.color;
        ctx.fill();

        return true;
      });

      // Draw nodes
      for (const node of nodesRef.current) {
        const pulse = 0.7 + 0.3 * Math.sin(t * 3 + node.x * 0.05 + node.y * 0.03);
        const isActive = node.layer === layers.length - 1 || Math.random() < confidence * 0.3;

        // Outer glow
        if (isActive) {
          const glowSize = node.size * 4 * pulse;
          const glowGrad = ctx.createRadialGradient(node.x, node.y, 0, node.x, node.y, glowSize);
          glowGrad.addColorStop(0, `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, 0.15)`);
          glowGrad.addColorStop(1, 'rgba(0,0,0,0)');
          ctx.fillStyle = glowGrad;
          ctx.fillRect(node.x - glowSize, node.y - glowSize, glowSize * 2, glowSize * 2);
        }

        // Node body
        const nodeSize = node.size * pulse;
        ctx.beginPath();
        ctx.arc(node.x, node.y, nodeSize, 0, Math.PI * 2);

        if (node.layer === layers.length - 1) {
          // Output layer — colored by signal
          const outputAlpha = 0.6 + 0.4 * pulse;
          ctx.fillStyle = `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, ${outputAlpha})`;
        } else if (node.layer === 0) {
          // Input layer — dim
          ctx.fillStyle = `rgba(100, 116, 139, ${0.4 + 0.2 * pulse})`;
        } else {
          // Hidden layers — activation-based
          const activation = 0.3 + 0.7 * (0.5 + 0.5 * Math.sin(t * 2 + node.x * 0.1));
          ctx.fillStyle = `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, ${activation * 0.6})`;
        }
        ctx.fill();

        // Inner bright core
        ctx.beginPath();
        ctx.arc(node.x, node.y, nodeSize * 0.4, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(255, 255, 255, ${isActive ? 0.6 : 0.2})`;
        ctx.fill();
      }

      // Layer labels
      const layerNames = ['Input', 'Hidden 1', 'Hidden 2', 'Hidden 3', 'Output'];
      ctx.font = '9px Consolas';
      ctx.textAlign = 'center';
      for (let l = 0; l < layers.length; l++) {
        const x = 40 + l * ((width - 80) / (layers.length - 1));
        ctx.fillStyle = 'rgba(148, 163, 184, 0.5)';
        ctx.fillText(layerNames[l], x, height - 8);
        ctx.fillStyle = 'rgba(100, 116, 139, 0.4)';
        ctx.fillText(`${Math.min(layers[l], 12)} neurons`, x, height - 20);
      }

      // Training indicator
      if (training) {
        const trainPulse = 0.5 + 0.5 * Math.sin(t * 4);
        ctx.fillStyle = `rgba(34, 211, 238, ${trainPulse * 0.3})`;
        ctx.fillRect(0, 0, width, 2);
      }

      animRef.current = requestAnimationFrame(animate);
    };

    animRef.current = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(animRef.current);
    };
  }, [width, height, layers, confidence, signal, training, regime, signalColor, regimeColor]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width, height }}
      className="rounded-lg"
    />
  );
}
