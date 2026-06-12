import { useState, useMemo } from 'react';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';

const TAG_COLORS: Record<string, string> = {
  HEARTBEAT: 'text-blue-400',
  'CONSENSUS-DIAG': 'text-accent-cyan',
  'AI-VOTE': 'text-accent-purple',
  'SIGNAL-REJECTED': 'text-accent-amber',
  'SHADOW-TRADE': 'text-accent-green',
  'SPIKE-ALARM': 'text-accent-red',
};

const TAG_BG: Record<string, string> = {
  HEARTBEAT: 'bg-blue-400/10',
  'CONSENSUS-DIAG': 'bg-accent-cyan/10',
  'AI-VOTE': 'bg-accent-purple/10',
  'SIGNAL-REJECTED': 'bg-accent-amber/10',
  'SHADOW-TRADE': 'bg-accent-green/10',
  'SPIKE-ALARM': 'bg-accent-red/10',
};

export default function LogsPage() {
  const { logs, isConnected } = useEAState();
  const [tagFilter, setTagFilter] = useState<string>('ALL');
  const [search, setSearch] = useState('');

  const availableTags = useMemo(() => {
    const tags = new Set<string>();
    logs.forEach((l) => tags.add(l.tag));
    return ['ALL', ...Array.from(tags).sort()];
  }, [logs]);

  const filtered = useMemo(() => {
    return logs.filter((l) => {
      if (tagFilter !== 'ALL' && l.tag !== tagFilter) return false;
      if (search && !l.raw.toLowerCase().includes(search.toLowerCase())) return false;
      return true;
    });
  }, [logs, tagFilter, search]);

  if (!isConnected) {
    return (
      <PageContainer title="Logs">
        <p className="text-text-muted">Connecting...</p>
      </PageContainer>
    );
  }

  return (
    <PageContainer title="Logs">
      {/* Filters */}
      <div className="flex items-center gap-4 mb-4">
        <select
          value={tagFilter}
          onChange={(e) => setTagFilter(e.target.value)}
          className="bg-surface-700 text-text-primary text-sm rounded-lg px-3 py-2 border border-surface-600 focus:border-accent-cyan focus:outline-none transition-colors duration-200"
        >
          {availableTags.map((tag) => (
            <option key={tag} value={tag}>
              {tag}
            </option>
          ))}
        </select>
        <input
          type="text"
          placeholder="Search logs..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="flex-1 bg-surface-700 text-text-primary text-sm rounded-lg px-3 py-2 border border-surface-600 focus:border-accent-cyan focus:outline-none placeholder:text-text-muted transition-colors duration-200"
        />
        <span className="text-text-muted text-xs font-mono">{filtered.length} entries</span>
      </div>

      {/* Log list */}
      <div className="glass-card overflow-hidden">
        <div className="max-h-[calc(100vh-220px)] overflow-auto">
          {filtered.length === 0 ? (
            <div className="p-8 text-center text-text-muted text-sm">No log entries</div>
          ) : (
            filtered.map((entry, i) => {
              const tagColor = TAG_COLORS[entry.tag] ?? 'text-text-secondary';
              const tagBg = TAG_BG[entry.tag] ?? 'bg-surface-600/50';
              return (
                <div
                  key={`${entry.timestamp}-${i}`}
                  className="flex items-start gap-3 px-4 py-2 border-b border-surface-700 last:border-0 hover:bg-surface-700/30 transition-colors duration-150"
                >
                  <span className="text-text-muted text-xs font-mono flex-shrink-0 mt-0.5 w-20">
                    {new Date(entry.timestamp).toLocaleTimeString('en-GB', { hour12: false })}
                  </span>
                  <span
                    className={`text-xs font-bold uppercase px-1.5 py-0.5 rounded flex-shrink-0 ${tagColor} ${tagBg}`}
                  >
                    {entry.tag}
                  </span>
                  <span className="text-text-secondary text-xs font-mono break-all leading-relaxed">
                    {entry.raw}
                  </span>
                </div>
              );
            })
          )}
        </div>
      </div>
    </PageContainer>
  );
}
