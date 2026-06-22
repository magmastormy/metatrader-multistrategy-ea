import { useEffect, useRef } from 'react';

interface RegimeGlowProps {
  regime: string;
  confidence: number;
  size?: number;
}

export default function RegimeGlow({ regime, confidence, size = 120 }: RegimeGlowProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animRef = useRef<number>(0);

  const regimeColors: Record<string, [number, number, number]> = {
    TREND: [59, 130, 246],
    RANGE: [107, 114, 128],
    VOLAT: [249, 115, 22],
    SPIKE: [239, 68, 68],
  };

  const color = regimeColors[regime] ?? regimeColors.RANGE;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    canvas.width = size * 2;
    canvas.height = size * 2;
    ctx.scale(2, 2);

    const particles: { x: number; y: number; vx: number; vy: number; life: number; maxLife: number; size: number }[] = [];
    const cx = size / 2;
    const cy = size / 2;
    const maxRadius = size / 2 - 10;

    const animate = () => {
      ctx.clearRect(0, 0, size, size);

      const t = Date.now() * 0.001;

      // Outer ring glow
      for (let i = 3; i >= 0; i--) {
        const radius = maxRadius - i * 4;
        const alpha = 0.03 + 0.02 * Math.sin(t * 2 + i);
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, Math.PI * 2);
        ctx.strokeStyle = `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${alpha})`;
        ctx.lineWidth = 2;
        ctx.stroke();
      }

      // Central glow
      const glowSize = maxRadius * 0.6 * (0.8 + 0.2 * Math.sin(t * 1.5));
      const glowGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, glowSize);
      glowGrad.addColorStop(0, `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${0.15 * confidence})`);
      glowGrad.addColorStop(0.5, `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${0.05 * confidence})`);
      glowGrad.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = glowGrad;
      ctx.fillRect(0, 0, size, size);

      // Orbiting particles
      if (Math.random() < 0.3 * confidence) {
        const angle = Math.random() * Math.PI * 2;
        const speed = 0.5 + Math.random() * 1.5;
        particles.push({
          x: cx + Math.cos(angle) * maxRadius * 0.3,
          y: cy + Math.sin(angle) * maxRadius * 0.3,
          vx: Math.cos(angle + Math.PI / 2) * speed,
          vy: Math.sin(angle + Math.PI / 2) * speed,
          life: 0,
          maxLife: 60 + Math.random() * 60,
          size: 1 + Math.random() * 2,
        });
      }

      // Update and draw particles
      for (let i = particles.length - 1; i >= 0; i--) {
        const p = particles[i];
        p.x += p.vx;
        p.y += p.vy;
        p.life++;

        if (p.life > p.maxLife) {
          particles.splice(i, 1);
          continue;
        }

        const lifeRatio = p.life / p.maxLife;
        const alpha = lifeRatio < 0.2 ? lifeRatio / 0.2 : 1 - (lifeRatio - 0.2) / 0.8;

        // Particle glow
        const pGrad = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.size * 3);
        pGrad.addColorStop(0, `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${alpha * 0.8})`);
        pGrad.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.fillStyle = pGrad;
        ctx.fillRect(p.x - p.size * 3, p.y - p.size * 3, p.size * 6, p.size * 6);

        // Particle core
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size * (1 - lifeRatio * 0.5), 0, Math.PI * 2);
        ctx.fillStyle = `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${alpha})`;
        ctx.fill();
      }

      // Keep particle count manageable
      if (particles.length > 50) {
        particles.splice(0, particles.length - 50);
      }

      // Center label
      ctx.font = 'bold 14px Consolas';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = `rgba(${color[0]}, ${color[1]}, ${color[2]}, 0.9)`;
      ctx.fillText(regime, cx, cy - 6);

      ctx.font = '10px Consolas';
      ctx.fillStyle = 'rgba(148, 163, 184, 0.7)';
      ctx.fillText(`${(confidence * 100).toFixed(0)}%`, cx, cy + 10);

      animRef.current = requestAnimationFrame(animate);
    };

    animRef.current = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(animRef.current);
  }, [regime, confidence, size, color]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width: size, height: size }}
      className="rounded-full"
    />
  );
}
