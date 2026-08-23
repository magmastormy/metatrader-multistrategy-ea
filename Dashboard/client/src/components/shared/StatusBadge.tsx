interface StatusBadgeProps {
  status: 'online' | 'offline' | 'warning' | 'danger' | 'pending' | 'active' | 'inactive';
  label?: string;
  showDot?: boolean;
  className?: string;
}

// Maps the legacy status vocabulary to the minimal badge system.
const map: Record<StatusBadgeProps['status'], { cls: string; dot: string; def: string }> = {
  online:  { cls: 'on',    dot: 'on',   def: 'Online' },
  active:  { cls: 'on',    dot: 'on',   def: 'Active' },
  offline: { cls: '',      dot: 'off',  def: 'Offline' },
  inactive: { cls: '',     dot: 'off',  def: 'Inactive' },
  warning: { cls: 'warn',  dot: 'warn', def: 'Warning' },
  danger:  { cls: 'neg',   dot: 'warn', def: 'Danger' },
  pending: { cls: 'warn',  dot: 'warn', def: 'Pending' },
};

export default function StatusBadge({ status, label, showDot = true, className = '' }: StatusBadgeProps) {
  const m = map[status];
  return (
    <span className={`badge ${m.cls} ${className}`}>
      {showDot && <span className={`dot ${m.dot}`} />}
      {label ?? m.def}
    </span>
  );
}
