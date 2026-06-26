import { useState, useMemo } from 'react';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';

const TAG_COLORS: Record<string, string> = {
  HEARTBEAT: 'text-blue-400',
  'CONSENSUS-DIAG': 'text-accent',
  'AI-VOTE': 'text-accent-2',
  'SIGNAL-REJECTED': 'text-rust-30',
  'SHADOW-TRADE': 'text-accent',
  'SPIKE-ALARM': 'text-accent-2',
};

const TAG_BG: Record<string, string> = {
  HEARTBEAT: 'bg-blue-400/10',
  'CONSENSUS-DIAG': 'bg-accent-10',
  'AI-VOTE': 'bg-rust-10',
  'SIGNAL-REJECTED': 'bg-rust-10',
  'SHADOW-TRADE': 'bg-accent-10',
  'SPIKE-ALARM': 'bg-rust-10',
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
          className="bg-surface text-text text-sm px-3 py-2 border border-border focus:border-accent focus:outline-none transition-colors duration-200"
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
          className="flex-1 bg-surface text-text text-sm px-3 py-2 border border-border focus:border-accent focus:outline-none placeholder:text-text-muted transition-colors duration-200"
        />
        <span className="text-text-muted text-xs font-mono">{filtered.length} entries</span>
      </div>

      {/* Log list */}
      <div className="bg-surface border border-border overflow-hidden">
        <div className="max-h-[calc(100vh-220px)] overflow-auto">
          {filtered.length === 0 ? (
            <div className="p-8 text-center text-text-muted text-sm">No log entries</div>
          ) : (
            filtered.map((entry, i) => {
              const tagColor = TAG_COLORS[entry.tag] ?? 'text-text-muted';
              const tagBg = TAG_BG[entry.tag] ?? 'bg-surface-2';
              return (
                <div
                  key={`${entry.timestamp}-${i}`}
                  className="flex items-start gap-3 px-4 py-2 border-b border-border last:border-0 hover:bg-surface-2/30 transition-colors duration-150"
                >
                  <span className="text-text-muted text-xs font-mono flex-shrink-0 mt-0.5 w-20">
                    {new Date(entry.timestamp).toLocaleTimeString('en-GB', { hour12: false })}
                  </span>
                  <span
                    className={`text-xs font-bold uppercase px-1.5 py-0.5 flex-shrink-0 ${tagColor} ${tagBg}`}
                  >
                    {entry.tag}
                  </span>
                  <span className="text-text-muted text-xs font-mono break-all leading-relaxed">
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
