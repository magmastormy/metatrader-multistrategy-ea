import type { ReactNode } from 'react';
import AnimatedCounter from './AnimatedCounter';

interface MetricCardProps {
  label: string;
  value: number;
  decimals?: number;
  prefix?: string;
  suffix?: string;
  change?: number;
  sparkData?: number[];
  children?: ReactNode;
}

export default function MetricCard({
  label,
  value,
  decimals = 2,
  prefix = '',
  suffix = '',
  change,
  sparkData,
}: MetricCardProps) {
  return (
    <div className="glass-card p-4 transition-all duration-200 hover:scale-[1.02] hover:border-accent-cyan/30 hover:shadow-[0_0_20px_rgba(34,211,238,0.1)]">
      <p className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-1">
        {label}
      </p>
      <div className="flex items-end gap-2">
        <span className="text-2xl font-bold text-text-primary">
          <AnimatedCounter value={value} decimals={decimals} prefix={prefix} suffix={suffix} />
        </span>
        {change !== undefined && (
          <span
            className={`text-xs font-semibold mb-1 ${
              change >= 0 ? 'text-accent-green' : 'text-accent-red'
            }`}
          >
            {change >= 0 ? '▲' : '▼'} {Math.abs(change).toFixed(2)}%
          </span>
        )}
      </div>
      {sparkData && sparkData.length > 1 && (
        <svg
          viewBox="0 0 100 30"
          className="w-full h-8 mt-2"
          preserveAspectRatio="none"
        >
          <defs>
            <linearGradient id={`spark-${label}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="rgba(34,211,238,0.3)" />
              <stop offset="100%" stopColor="rgba(34,211,238,0)" />
            </linearGradient>
          </defs>
          <path
            d={sparkLinePath(sparkData)}
            fill={`url(#spark-${label})`}
            stroke="rgba(34,211,238,0.6)"
            strokeWidth="1.5"
          />
        </svg>
      )}
    </div>
  );
}

function sparkLinePath(data: number[]): string {
  if (data.length < 2) return '';
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const step = 100 / (data.length - 1);

  const points = data.map((v, i) => ({
    x: i * step,
    y: 30 - ((v - min) / range) * 28,
  }));

  const line = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x},${p.y}`).join(' ');
  const area = `${line} L100,30 L0,30 Z`;
  return area;
}
