interface StatusBadgeProps {
  status: 'online' | 'offline' | 'warning';
  label: string;
}

const statusColors: Record<StatusBadgeProps['status'], string> = {
  online: 'bg-accent-green',
  offline: 'bg-accent-red',
  warning: 'bg-accent-amber',
};

const statusGlow: Record<StatusBadgeProps['status'], string> = {
  online: 'shadow-[0_0_6px_rgba(34,197,94,0.5)]',
  offline: '',
  warning: 'shadow-[0_0_6px_rgba(245,158,11,0.5)]',
};

export default function StatusBadge({ status, label }: StatusBadgeProps) {
  return (
    <div className="flex items-center gap-2">
      <span
        className={`w-2 h-2 rounded-full ${statusColors[status]} ${statusGlow[status]} transition-all duration-200`}
      />
      <span className="text-xs text-text-secondary font-medium">{label}</span>
    </div>
  );
}
