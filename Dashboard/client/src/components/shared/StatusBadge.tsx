interface StatusBadgeProps {
  status: 'online' | 'offline' | 'warning';
  label: string;
}

export default function StatusBadge({ status, label }: StatusBadgeProps) {
  const colors = {
    online: 'bg-accent',
    offline: 'bg-text-muted',
    warning: 'bg-rust-30',
  };

  return (
    <div className="flex items-center gap-2">
      <span
        className={`w-2 h-2 ${colors[status]} transition-all duration-200`}
      />
      <span className="text-xs text-text-muted font-medium">{label}</span>
    </div>
  );
}
