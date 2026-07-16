
interface StatusBadgeProps {
  status: 'online' | 'offline' | 'warning' | 'danger' | 'pending' | 'active' | 'inactive';
  label?: string;
  size?: 'sm' | 'md' | 'lg';
  showDot?: boolean;
  className?: string;
}

const statusConfig = {
  online: { dot: 'status-online', text: 'text-success', bg: 'bg-success/10', border: 'border-success/20', label: 'Online' },
  offline: { dot: 'status-offline', text: 'text-text-muted', bg: 'bg-surface-2', border: 'border-border-default', label: 'Offline' },
  warning: { dot: 'status-warning', text: 'text-warning', bg: 'bg-warning/10', border: 'border-warning/20', label: 'Warning' },
  danger: { dot: 'status-danger', text: 'text-danger', bg: 'bg-danger/10', border: 'border-danger/20', label: 'Danger' },
  pending: { dot: 'status-warning', text: 'text-warning', bg: 'bg-warning/10', border: 'border-warning/20', label: 'Pending' },
  active: { dot: 'status-online', text: 'text-success', bg: 'bg-success/10', border: 'border-success/20', label: 'Active' },
  inactive: { dot: 'status-offline', text: 'text-text-muted', bg: 'bg-surface-2', border: 'border-border-default', label: 'Inactive' },
};

const sizeClasses = {
  sm: 'px-2 py-0.5 text-[10px] gap-1',
  md: 'px-2.5 py-1 text-xs gap-1.5',
  lg: 'px-3 py-1.5 text-sm gap-2',
};

const dotSizes = {
  sm: 'status-dot-sm',
  md: 'status-dot',
  lg: 'status-dot-lg',
};

export default function StatusBadge({
  status,
  label,
  size = 'md',
  showDot = true,
  className = '',
}: StatusBadgeProps) {
  const config = statusConfig[status];
  const displayLabel = label || config.label;

  return (
    <span
      className={`
        inline-flex items-center font-medium
        ${config.bg} ${config.border} ${config.text}
        rounded-full border
        ${sizeClasses[size]} ${className}
      `}
    >
      {showDot && <span className={`${config.dot} ${dotSizes[size]}`} />}
      {displayLabel}
    </span>
  );
}