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
    <header className="flex items-center justify-between px-6 h-14 bg-surface border-b border-border">
      <div className="flex items-center gap-3">
        <h1 className="font-bold text-lg tracking-tight text-text">
          EA Command Center
        </h1>
      </div>

      <div className="flex items-center gap-6">
        <div className="flex items-center gap-2">
          <span
            className={`w-2.5 h-2.5 transition-all duration-300 ${
              isConnected
                ? 'bg-accent animate-pulse-solid'
                : 'bg-text-muted'
            }`}
          />
          <span className="text-xs text-text-muted font-medium">
            {isConnected ? 'Connected' : 'Disconnected'}
          </span>
        </div>

        <span className="font-mono text-sm text-text-muted tabular-nums">
          {clock}
        </span>

        <span
          className={`px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wide border ${
            executionMode === 'LIVE'
              ? 'bg-accent text-bg border-accent'
              : executionMode === 'SHADOW'
                ? 'bg-rust-15 text-rust-30 border-rust-30'
                : 'bg-surface-2 text-text-muted border-border'
          }`}
        >
          {executionMode || 'OFFLINE'}
        </span>
      </div>
    </header>
  );
}
