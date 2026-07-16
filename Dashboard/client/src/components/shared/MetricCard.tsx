import type { ReactNode } from 'react';
import AnimatedCounter from './AnimatedCounter';

interface MetricCardProps {
  label: string;
  value: number | string;
  decimals?: number;
  prefix?: string;
  suffix?: string;
  change?: number;
  changeLabel?: string;
  sparkData?: number[];
  trend?: 'up' | 'down' | 'neutral';
  icon?: ReactNode;
  className?: string;
  variant?: 'default' | 'primary' | 'warning' | 'danger' | 'glass';
  size?: 'sm' | 'md' | 'lg';
  onClick?: () => void;
}

export default function MetricCard({
  label,
  value,
  decimals = 2,
  prefix = '',
  suffix = '',
  change,
  changeLabel,
  sparkData,
  trend,
  icon,
  className = '',
  variant = 'default',
  size = 'md',
  onClick,
}: MetricCardProps) {
  const displayValue = typeof value === 'number'
    ? <AnimatedCounter value={value} decimals={decimals} prefix={prefix} suffix={suffix} />
    : <>{prefix}{value}{suffix}</>;

  const variantClasses = {
    default: 'bg-surface-1 border-border-subtle',
    primary: 'bg-gradient-to-br from-accent-primary/5 to-surface-1 border-accent-primary/20',
    warning: 'bg-gradient-to-br from-accent-amber/5 to-surface-1 border-accent-amber/20 border-l-3 border-l-accent-amber/40',
    danger: 'bg-gradient-to-br from-accent-red/5 to-surface-1 border-accent-red/20',
    glass: 'bg-surface-1/50 backdrop-blur-md border-border-subtle',
  };

  const sizeClasses = {
    sm: 'p-3',
    md: 'p-4',
    lg: 'p-5',
  };

  const trendColor = trend === 'up' ? 'text-accent-green' : trend === 'down' ? 'text-accent-red' : 'text-text-muted';
  const trendIcon = trend === 'up' ? '↑' : trend === 'down' ? '↓' : '→';

  return (
    <div
      className={`
        metric-card ${variantClasses[variant]} ${sizeClasses[size]} ${className}
        ${onClick ? 'cursor-pointer hover-lift' : 'hover-lift'}
      `}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onClick(); }} : undefined}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1.5">
            {icon && <span className="text-text-muted shrink-0">{icon}</span>}
            <p className="text-xs font-medium text-text-muted uppercase tracking-wider truncate">{label}</p>
            {trend && (
              <span className={`text-xs font-semibold ${trendColor} whitespace-nowrap`}>
                {trendIcon}
              </span>
            )}
          </div>
          <div className="flex items-end gap-2 flex-wrap">
            <span className="text-mono text-numeral font-bold">
              {size === 'lg' ? 'text-3xl' : size === 'md' ? 'text-2xl' : 'text-xl'}
              {displayValue}
            </span>
            {change !== undefined && (
              <span className={`text-xs font-semibold mb-1 ${change >= 0 ? 'text-accent-green' : 'text-accent-red'}`}>
                {change >= 0 ? '▲' : '▼'} {Math.abs(change).toFixed(2)}%
              </span>
            )}
          </div>
          {changeLabel && (
            <p className="text-[10px] text-text-muted mt-1">{changeLabel}</p>
          )}
        </div>
      </div>

      {sparkData && sparkData.length > 1 && (
        <div className="mt-3 -mx-4 -mb-4 px-4 pb-3" aria-hidden="true">
          <Sparkline data={sparkData} variant={variant} />
        </div>
      )}
    </div>
  );
}

interface SparklineProps {
  data: number[];
  variant?: string;
}

function Sparkline({ data, variant }: SparklineProps) {
  if (data.length < 2) return null;

  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const width = 100;
  const height = 30;
  const stepX = width / (data.length - 1);

  const points = data.map((v, i) => ({
    x: i * stepX,
    y: height - ((v - min) / range) * (height - 4) - 2,
  }));

  const linePath = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(2)},${p.y.toFixed(2)}`).join(' ');
  const areaPath = `${linePath} L${width},${height} L0,${height} Z`;

  const variantColors = {
    primary: { stroke: 'var(--color-accent-primary)', fill: 'rgba(0, 212, 170, 0.15)' },
    warning: { stroke: 'var(--color-warning)', fill: 'rgba(245, 158, 11, 0.15)' },
    danger: { stroke: 'var(--color-danger)', fill: 'rgba(239, 68, 68, 0.15)' },
    default: { stroke: 'var(--color-accent-primary)', fill: 'rgba(0, 212, 170, 0.1)' },
    glass: { stroke: 'var(--color-accent-primary)', fill: 'rgba(0, 212, 170, 0.1)' },
  };

  const colors = variantColors[variant as keyof typeof variantColors] || variantColors.default;

  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="w-full h-8" preserveAspectRatio="none" aria-hidden="true">
      <defs>
        <linearGradient id={`spark-${Math.random().toString(36).slice(2)}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={colors.fill} stopOpacity={1} />
          <stop offset="100%" stopColor={colors.fill} stopOpacity={0} />
        </linearGradient>
      </defs>
      <path d={areaPath} fill={`url(#spark-${Math.random().toString(36).slice(2)})`} />
      <path d={linePath} stroke={colors.stroke} strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}