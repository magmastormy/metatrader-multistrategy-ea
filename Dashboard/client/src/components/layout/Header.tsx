import { useState, useEffect } from 'react';

interface HeaderProps {
  isConnected: boolean;
  executionMode: string;
}

export default function Header({ isConnected, executionMode }: HeaderProps) {
  const [clock, setClock] = useState('');

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      setClock(now.toLocaleTimeString('en-GB', { hour12: false }));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  return (
    <header className="flex items-center justify-between px-6 h-14 bg-surface-800 border-b border-surface-600">
      <div className="flex items-center gap-3">
        <h1 className="font-bold text-lg tracking-tight text-text-primary">
          EA Command Center
        </h1>
      </div>

      <div className="flex items-center gap-6">
        <div className="flex items-center gap-2">
          <span
            className={`w-2.5 h-2.5 rounded-full transition-all duration-300 ${
              isConnected
                ? 'bg-accent-green animate-pulse-glow'
                : 'bg-accent-red'
            }`}
          />
          <span className="text-xs text-text-secondary font-medium">
            {isConnected ? 'Connected' : 'Disconnected'}
          </span>
        </div>

        <span className="font-mono text-sm text-text-secondary tabular-nums">
          {clock}
        </span>

        <span
          className={`px-2.5 py-0.5 rounded-full text-xs font-semibold uppercase tracking-wide ${
            executionMode === 'LIVE'
              ? 'bg-accent-green/15 text-accent-green border border-accent-green/30'
              : executionMode === 'SHADOW'
                ? 'bg-accent-amber/15 text-accent-amber border border-accent-amber/30'
                : 'bg-surface-600/50 text-text-secondary border border-surface-500'
          }`}
        >
          {executionMode || 'OFFLINE'}
        </span>
      </div>
    </header>
  );
}
