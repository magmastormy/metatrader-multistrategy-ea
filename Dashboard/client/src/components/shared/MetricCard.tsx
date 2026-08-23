import type { ReactNode } from 'react';
import AnimatedCounter from './AnimatedCounter';

interface MetricCardProps {
  label: string;
  value: number | string;
  decimals?: number;
  prefix?: string;
  suffix?: string;
  change?: number;
  trend?: 'up' | 'down' | 'neutral';
  icon?: ReactNode;
  className?: string;
  size?: 'sm' | 'md';
  onClick?: () => void;
}

export default function MetricCard({
  label, value, decimals = 2, prefix = '', suffix = '',
  change, trend, icon, className = '', size = 'md', onClick,
}: MetricCardProps) {
  const display = typeof value === 'number'
    ? <AnimatedCounter value={value} decimals={decimals} prefix={prefix} suffix={suffix} />
    : <>{prefix}{value}{suffix}</>;

  const trendColor = trend === 'up' ? 'pos' : trend === 'down' ? 'neg' : 'dim';
  const trendIcon = trend === 'up' ? '↑' : trend === 'down' ? '↓' : '';

  return (
    <div
      className={`stat ${size === 'sm' ? 'tight' : ''} ${className}`}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onClick(); } } : undefined}
      style={onClick ? { cursor: 'pointer' } : undefined}
    >
      <div className="stat-row">
        <span className="stat-label">{label}</span>
        {icon && <span className="muted">{icon}</span>}
      </div>
      <div className="stat-value" style={size === 'sm' ? { fontSize: 21 } : undefined}>
        <span className="tnum">{display}</span>
        {change !== undefined && (
          <span className={trendColor} style={{ fontSize: 13, marginLeft: 8, fontWeight: 600 }}>
            {trendIcon} {Math.abs(change).toFixed(2)}%
          </span>
        )}
      </div>
    </div>
  );
}
