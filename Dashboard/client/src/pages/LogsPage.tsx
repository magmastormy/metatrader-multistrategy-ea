import { useState, useMemo, useEffect, useRef } from 'react';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';

interface LogEntryProps {
  entry: any;
  index: number;
  isExpanded: boolean;
  onToggle: () => void;
}

function LogEntry({ entry, index, isExpanded, onToggle }: LogEntryProps) {
  const tagColors: Record<string, { bg: string; text: string; border: string }> = {
    HEARTBEAT: { bg: 'bg-blue-500/15', text: 'text-blue-400', border: 'border-blue-500/20' },
    'CONSENSUS-DIAG': { bg: 'bg-accent-primary/15', text: 'text-accent-primary', border: 'border-accent-primary/20' },
    'AI-VOTE': { bg: 'bg-accent-tertiary/15', text: 'text-accent-tertiary', border: 'border-accent-tertiary/20' },
    'SIGNAL-REJECTED': { bg: 'bg-warning/15', text: 'text-warning', border: 'border-warning/20' },
    'SHADOW-TRADE': { bg: 'bg-success/15', text: 'text-success', border: 'border-success/20' },
    'SPIKE-ALARM': { bg: 'bg-danger/15', text: 'text-danger', border: 'border-danger/20' },
    TRADE: { bg: 'bg-accent-primary/15', text: 'text-accent-primary', border: 'border-accent-primary/20' },
    SIGNAL: { bg: 'bg-info/15', text: 'text-info', border: 'border-info/20' },
    RISK: { bg: 'bg-warning/15', text: 'text-warning', border: 'border-warning/20' },
    CONSENSUS: { bg: 'bg-accent-primary/15', text: 'text-accent-primary', border: 'border-accent-primary/20' },
    AI: { bg: 'bg-accent-tertiary/15', text: 'text-accent-tertiary', border: 'border-accent-tertiary/20' },
  };

  const tagStyle = tagColors[entry.tag] || { bg: 'bg-surface-3/50', text: 'text-text-secondary', border: 'border-border-default' };
  const level = entry.fields.level || entry.raw.split(' ')[1]?.replace(/[\[\]]/g, '') || 'INFO';
  const levelColors: Record<string, string> = {
    ERROR: 'text-danger',
    WARNING: 'text-warning',
    INFO: 'text-text-secondary',
    DEBUG: 'text-text-muted',
    CRITICAL: 'text-danger font-bold',
  };

  const correlationId = entry.fields.correlation_id || entry.fields.correlationId;
  const symbol = entry.fields.symbol;
  const eventType = entry.fields.event_type || entry.fields.eventType;

  return (
    <div
      className={`px-4 py-3 hover:bg-surface-1/50 transition-colors duration-150 ${isExpanded ? 'bg-surface-1/30' : ''}`}
      onClick={onToggle}
    >
      {/* Header Row */}
      <div className="flex items-center gap-3 mb-1">
        <span className="text-text-muted text-xs font-mono flex-shrink-0 w-20">
          {new Date(entry.timestamp).toLocaleTimeString('en-GB', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })}
        </span>
        <span className={`badge badge-sm ${tagStyle.bg} ${tagStyle.text} ${tagStyle.border} font-mono`}>
          {entry.tag}
        </span>
        <span className={`text-[10px] font-mono ${levelColors[level] || 'text-text-muted'}`}>
          {level}
        </span>
        {symbol && (
          <span className="badge badge-sm badge-info font-mono">{symbol}</span>
        )}
        {eventType && (
          <span className="badge badge-sm badge-outline font-mono text-[10px]">{eventType}</span>
        )}
        {correlationId && (
          <span className="badge badge-sm badge-outline font-mono text-[10px] flex-1 truncate" title={correlationId}>
            🔗 {correlationId}
          </span>
        )}
        <span className="text-text-muted text-[10px] flex-shrink-0 ml-auto">
          #{index + 1}
        </span>
        <button
          onClick={(e) => { e.stopPropagation(); onToggle(); }}
          className="p-1 text-text-muted hover:text-text-primary transition-colors"
          aria-label={isExpanded ? 'Collapse' : 'Expand'}
        >
          <svg className={`w-4 h-4 transition-transform ${isExpanded ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
          </svg>
        </button>
      </div>

      {/* Message Row */}
      <div className="pl-8">
        <div className="text-text-secondary text-xs font-mono leading-relaxed break-all mb-1">
          {entry.raw}
        </div>

        {/* Expanded JSON View */}
        {isExpanded && (
          <div className="mt-2 p-3 bg-surface-0 rounded-lg border border-border-subtle overflow-x-auto animate-fade-in-up">
            <div className="flex items-center justify-between mb-2">
              <span className="text-text-muted text-[10px] uppercase tracking-wider">Structured Data (JSON)</span>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  navigator.clipboard.writeText(JSON.stringify(entry.fields, null, 2));
                }}
                className="btn btn-ghost btn-sm btn-icon text-text-muted hover:text-text-primary"
                title="Copy JSON"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
              </button>
            </div>
            <pre className="text-[10px] font-mono text-text-secondary leading-relaxed max-h-64 overflow-auto whitespace-pre-wrap">
              {JSON.stringify(entry.fields, null, 2)}
            </pre>
          </div>
        )}
      </div>
    </div>
  );
}

export default function LogsPage() {
  const { logs, isConnected } = useEAState();
  const [tagFilter, setTagFilter] = useState<string>('ALL');
  const [search, setSearch] = useState('');
  const [levelFilter, setLevelFilter] = useState<string>('ALL');
  const [autoScroll, setAutoScroll] = useState(true);
  const [expandedEntry, setExpandedEntry] = useState<number | null>(null);
  const logContainerRef = useRef<HTMLDivElement>(null);

  const availableTags = useMemo(() => {
    const tags = new Set<string>();
    logs.forEach((l) => tags.add(l.tag));
    return ['ALL', ...Array.from(tags).sort()];
  }, [logs]);

  const availableLevels = ['ALL', 'ERROR', 'WARNING', 'INFO', 'DEBUG', 'CRITICAL'];

  const filtered = useMemo(() => {
    return logs.filter((l) => {
      if (tagFilter !== 'ALL' && l.tag !== tagFilter) return false;
      if (levelFilter !== 'ALL') {
        const level = l.fields.level || l.raw.split(' ')[1]?.replace(/[\[\]]/g, '');
        if (level !== levelFilter) return false;
      }
      if (search && !l.raw.toLowerCase().includes(search.toLowerCase())) return false;
      return true;
    });
  }, [logs, tagFilter, levelFilter, search]);

  // Auto-scroll to bottom when new logs arrive
  useEffect(() => {
    if (autoScroll && logContainerRef.current) {
      logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
    }
  }, [filtered.length, autoScroll]);

  if (!isConnected) {
    return (
      <PageContainer title="Logs" subtitle="Structured JSON log viewer with correlation IDs">
        <div className="flex items-center justify-center h-[70vh]">
          <div className="text-center stagger-enter">
            <div className="w-4 h-4 rounded-full bg-danger mx-auto mb-4 animate-pulse-glow" />
            <p className="text-text-secondary text-lg">Connecting...</p>
          </div>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer title="Logs" subtitle="Structured JSON log viewer with correlation IDs">
      {/* Toolbar */}
      <div className="glass-card p-4 mb-6 stagger-enter">
        <div className="flex flex-wrap items-center gap-4">
          {/* Tag Filter */}
          <div className="relative">
            <select
              value={tagFilter}
              onChange={(e) => setTagFilter(e.target.value)}
              className="input appearance-none pr-10 bg-surface-2 border-border-default text-text-primary text-sm"
              style={{ width: '200px' }}
            >
              {availableTags.map((tag) => (
                <option key={tag} value={tag}>{tag}</option>
              ))}
            </select>
            <svg className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </div>

          {/* Level Filter */}
          <div className="relative">
            <select
              value={levelFilter}
              onChange={(e) => setLevelFilter(e.target.value)}
              className="input appearance-none pr-10 bg-surface-2 border-border-default text-text-primary text-sm"
              style={{ width: '150px' }}
            >
              {availableLevels.map((level) => (
                <option key={level} value={level}>{level}</option>
              ))}
            </select>
            <svg className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </div>

          {/* Search */}
          <div className="relative flex-1 max-w-md">
            <input
              type="text"
              placeholder="Search logs... (correlation_id, message, symbol)"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="input pl-10 bg-surface-2 border-border-default text-text-primary text-sm"
            />
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted pointer-events-none" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            {search && (
              <button
                onClick={() => setSearch('')}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-primary"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            )}
          </div>

          {/* Stats */}
          <div className="flex items-center gap-6 text-xs text-text-muted ml-auto">
            <span className="font-mono">{filtered.length} / {logs.length} entries</span>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={autoScroll}
                onChange={(e) => setAutoScroll(e.target.checked)}
                className="w-4 h-4 rounded border-border-default text-accent-primary focus:ring-accent-primary"
              />
              <span>Auto-scroll</span>
            </label>
            <button
              onClick={() => { setSearch(''); setTagFilter('ALL'); setLevelFilter('ALL'); }}
              className="btn btn-ghost btn-sm text-text-muted hover:text-text-primary"
            >
              Clear Filters
            </button>
          </div>
        </div>
      </div>

      {/* Log Entries */}
      <div className="glass-card overflow-hidden stagger-enter" style={{ animationDelay: '50ms' }}>
        <div
          ref={logContainerRef}
          className="max-h-[calc(100vh-280px)] overflow-auto"
        >
          {filtered.length === 0 ? (
            <div className="empty-state h-64">
              <svg className="w-16 h-16 mb-4 opacity-40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
              <p className="text-text-secondary text-lg">No log entries</p>
              <p className="text-text-muted text-sm mt-1">Adjust filters or wait for logs...</p>
            </div>
          ) : (
            <div className="divide-y divide-border-subtle">
              {filtered.map((entry, i) => (
                <LogEntry
                  key={`${entry.timestamp}-${i}`}
                  entry={entry}
                  index={i}
                  isExpanded={expandedEntry === i}
                  onToggle={() => setExpandedEntry(expandedEntry === i ? null : i)}
                />
              ))}
            </div>
          )}
        </div>

        {/* Bottom status bar */}
        <div className="p-3 border-t border-border-subtle bg-surface-0/50 flex items-center justify-between text-xs text-text-muted">
          <span>Showing {filtered.length} of {logs.length} entries</span>
          <span className="font-mono">Last: {logs[0]?.timestamp ? new Date(logs[0].timestamp).toLocaleTimeString('en-GB', { hour12: false }) : '—'}</span>
        </div>
      </div>
    </PageContainer>
  );
}