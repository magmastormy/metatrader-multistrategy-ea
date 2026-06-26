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
  liveDataRate?: number; // 0-1, controls how "alive" the network feels
}

export default function NeuralNetViz({
  confidence = 0.5,
  signal = 'NONE',
  training = false,
  regime = 'RANGE',
  width = 400,
  height = 300,
  liveDataRate = 0.8,
}: NeuralNetVizProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animRef = useRef<number>(0);
  const nodesRef = useRef<Node[]>([]);
  const connectionsRef = useRef<Connection[]>([]);
  const particlesRef = useRef<Particle[]>([]);
  const timeRef = useRef(0);
  const dataPulseRef = useRef(0);

  const layers = useMemo(() => [65, 32, 16, 8, 3], []);

  // Brutalist color palette
  const acidGreen = [200, 245, 58];
  const rustOrange = [232, 84, 26];
  const slateGray = [138, 138, 138];
  const boneWhite = [240, 234, 216];
  
  const regimeColors: Record<string, number[]> = {
    TREND: [59, 130, 246],
    RANGE: slateGray,
    VOLAT: rustOrange,
    SPIKE: rustOrange,
  };
  const regimeColor = regimeColors[regime] ?? slateGray;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    canvas.width = width * 2;
    canvas.height = height * 2;
    ctx.scale(2, 2);

    // Generate nodes with sharp rectangular forms
    const nodes: Node[] = [];
    const padding = 30;
    const layerSpacing = (width - padding * 2) / (layers.length - 1);

    for (let l = 0; l < layers.length; l++) {
      const count = Math.min(layers[l], 10); // Cap visible nodes for density
      const nodeSpacing = (height - padding * 2) / (count + 1);
      for (let n = 0; n < count; n++) {
        nodes.push({
          x: padding + l * layerSpacing,
          y: padding + (n + 1) * nodeSpacing,
          layer: l,
          activation: Math.random(),
          size: l === layers.length - 1 ? 5 : 2.5 + (1 - l / layers.length) * 2,
        });
      }
    }
    nodesRef.current = nodes;

    // Generate connections - denser for more activity
    const connections: Connection[] = [];
    let nodeIdx = 0;
    for (let l = 0; l < layers.length - 1; l++) {
      const currentCount = Math.min(layers[l], 10);
      const nextCount = Math.min(layers[l + 1], 10);
      const currentStart = nodeIdx;
      const nextStart = nodeIdx + currentCount;
      for (let i = 0; i < currentCount; i++) {
        for (let j = 0; j < nextCount; j++) {
          if (Math.random() < 0.4) { // More connections for visual activity
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
      dataPulseRef.current += 0.02 * liveDataRate; // Data pulse speeds up with live data
      const t = timeRef.current;
      const dataPulse = dataPulseRef.current;

      ctx.clearRect(0, 0, width, height);

      // Subtle background grid
      ctx.strokeStyle = 'rgba(42, 42, 42, 0.3)';
      ctx.lineWidth = 0.5;
      for (let gx = 0; gx < width; gx += 20) {
        ctx.beginPath();
        ctx.moveTo(gx, 0);
        ctx.lineTo(gx, height);
        ctx.stroke();
      }
      for (let gy = 0; gy < height; gy += 20) {
        ctx.beginPath();
        ctx.moveTo(0, gy);
        ctx.lineTo(width, gy);
        ctx.stroke();
      }

      // Draw connections with data flow animation
      for (const conn of connectionsRef.current) {
        const fromNode = nodesRef.current[conn.from];
        const toNode = nodesRef.current[conn.to];
        if (!fromNode || !toNode) continue;

        // Connection pulses with data flow
        const dataFlow = Math.sin(dataPulse * 2 + conn.from * 0.5) * 0.5 + 0.5;
        const alpha = conn.active 
          ? 0.12 + 0.08 * dataFlow 
          : 0.03;
        const weight = Math.abs(conn.weight);
        
        ctx.beginPath();
        ctx.moveTo(fromNode.x, fromNode.y);
        ctx.lineTo(toNode.x, toNode.y);
        ctx.strokeStyle = conn.active
          ? `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, ${alpha})`
          : `rgba(80, 80, 80, ${alpha})`;
        ctx.lineWidth = 0.5 + weight * 0.8;
        ctx.stroke();
      }

      // Spawn particles more frequently when training/live
      const spawnRate = training ? 0.25 * liveDataRate : 0.08;
      if (Math.random() < spawnRate) {
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
              speed: 0.03 + Math.random() * 0.04 * liveDataRate,
              color: conn.weight > 0
                ? `rgba(${acidGreen[0]}, ${acidGreen[1]}, ${acidGreen[2]}, 0.95)`
                : `rgba(${rustOrange[0]}, ${rustOrange[1]}, ${rustOrange[2]}, 0.95)`,
              size: 2 + Math.random() * 2,
            });
          }
        }
      }

      // Update and draw particles with trail effect
      particlesRef.current = particlesRef.current.filter(p => {
        p.progress += p.speed;
        if (p.progress >= 1) return false;

        const ease = p.progress < 0.5 ? 2 * p.progress * p.progress : 1 - Math.pow(-2 * p.progress + 2, 2) / 2;
        const px = p.x + (p.targetX - p.x) * ease;
        const py = p.y + (p.targetY - p.y) * ease;

        // Particle trail
        const trailLen = 8 * liveDataRate;
        const trailAngle = Math.atan2(p.targetY - p.y, p.targetX - p.x);
        for (let ti = 0; ti < trailLen; ti++) {
          const tx = px - Math.cos(trailAngle) * ti * 0.5;
          const ty = py - Math.sin(trailAngle) * ti * 0.5;
          const trailAlpha = (1 - ti / trailLen) * 0.4;
          ctx.fillStyle = p.color.replace('0.95', trailAlpha.toFixed(2));
          ctx.fillRect(tx - p.size * 0.5, ty - p.size * 0.5, p.size, p.size);
        }

        // Particle core - sharp square
        ctx.fillStyle = p.color;
        ctx.fillRect(px - p.size, py - p.size, p.size * 2, p.size * 2);

        return true;
      });

      // Draw nodes as sharp squares
      for (const node of nodesRef.current) {
        const basePulse = 0.8 + 0.2 * Math.sin(t * 3 + node.x * 0.05 + node.y * 0.03);
        const dataPulseEffect = 1 + 0.3 * Math.sin(dataPulse * 3 + node.layer);
        const pulse = basePulse * dataPulseEffect;
        const isActive = node.layer === layers.length - 1 || Math.random() < confidence * 0.4;

        // Node glow when active
        if (isActive) {
          const glowSize = node.size * 5 * pulse;
          const glowGrad = ctx.createRadialGradient(node.x, node.y, 0, node.x, node.y, glowSize);
          glowGrad.addColorStop(0, `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, 0.12)`);
          glowGrad.addColorStop(1, 'rgba(0,0,0,0)');
          ctx.fillStyle = glowGrad;
          ctx.fillRect(node.x - glowSize, node.y - glowSize, glowSize * 2, glowSize * 2);
        }

        // Node body - sharp rectangle
        const nodeSize = node.size * pulse;
        const halfSize = nodeSize;
        
        if (node.layer === layers.length - 1) {
          // Output layer — acid green for BUY, rust for SELL
          const outputAlpha = 0.7 + 0.3 * pulse;
          ctx.fillStyle = `rgba(${signalColor[0]}, ${signalColor[1]}, ${signalColor[2]}, ${outputAlpha})`;
        } else if (node.layer === 0) {
          // Input layer — slate gray
          ctx.fillStyle = `rgba(${slateGray[0]}, ${slateGray[1]}, ${slateGray[2]}, ${0.5 + 0.3 * pulse})`;
        } else {
          // Hidden layers — pulsing with data
          const activation = 0.4 + 0.6 * (0.5 + 0.5 * Math.sin(t * 2 + node.x * 0.1 + dataPulse));
          ctx.fillStyle = `rgba(${acidGreen[0]}, ${acidGreen[1]}, ${acidGreen[2]}, ${activation * 0.5})`;
        }
        ctx.fillRect(node.x - halfSize, node.y - halfSize, halfSize * 2, halfSize * 2);

        // Inner bright core - smaller square
        const coreSize = nodeSize * 0.35;
        ctx.fillStyle = `rgba(${boneWhite[0]}, ${boneWhite[1]}, ${boneWhite[2]}, ${isActive ? 0.8 : 0.3})`;
        ctx.fillRect(node.x - coreSize, node.y - coreSize, coreSize * 2, coreSize * 2);
      }

      // Layer labels - monospace, uppercase
      const layerNames = ['INPUT', 'HIDDEN 1', 'HIDDEN 2', 'HIDDEN 3', 'OUTPUT'];
      ctx.font = 'bold 8px "JetBrains Mono", Consolas, monospace';
      ctx.textAlign = 'center';
      for (let l = 0; l < layers.length; l++) {
        const x = 30 + l * ((width - 60) / (layers.length - 1));
        ctx.fillStyle = 'rgba(138, 138, 138, 0.6)';
        ctx.fillText(layerNames[l], x, height - 12);
        ctx.fillStyle = 'rgba(138, 138, 138, 0.3)';
        ctx.fillText(`${Math.min(layers[l], 10)} N`, x, height - 4);
      }

      // Live data indicator bar at top
      const liveAlpha = 0.3 + 0.2 * Math.sin(dataPulse * 4);
      ctx.fillStyle = `rgba(${acidGreen[0]}, ${acidGreen[1]}, ${acidGreen[2]}, ${liveAlpha})`;
      ctx.fillRect(0, 0, width, 1);
      
      // Training indicator - rust orange bar
      if (training) {
        const trainPulse = 0.5 + 0.5 * Math.sin(t * 4);
        ctx.fillStyle = `rgba(${rustOrange[0]}, ${rustOrange[1]}, ${rustOrange[2]}, ${trainPulse * 0.4})`;
        ctx.fillRect(0, height - 1, width, 1);
      }

      animRef.current = requestAnimationFrame(animate);
    };

    animRef.current = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(animRef.current);
    };
  }, [width, height, layers, confidence, signal, training, regime, liveDataRate, acidGreen, rustOrange, slateGray, boneWhite, signalColor, regimeColor]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width, height }}
      className="sharp-corners"
    />
  );
}
