import { useEffect, useState } from 'react';
import { Network, Sun, Moon } from 'lucide-react';
import Dashboard from './Dashboard';
import { useEAState } from './hooks/useEAState';

const SECTIONS: [string, string][] = [
  ['overview', 'Overview'], ['positions', 'Positions'], ['strategies', 'Strategies'],
  ['risk', 'Risk'], ['ai', 'AI'], ['logs', 'Logs'], ['control', 'Control'],
];

export default function App() {
  const { isConnected, state } = useEAState();
  const [theme, setTheme] = useState<string>(() => (document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light'));
  const [active, setActive] = useState('overview');
  const [clock, setClock] = useState('');

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try { localStorage.setItem('ea-theme', theme); } catch { /* ignore */ }
  }, [theme]);

  useEffect(() => {
    const id = setInterval(() => setClock(new Date().toLocaleTimeString('en-GB', { hour12: false })), 1000);
    return () => clearInterval(id);
  }, []);

  // lightweight scroll-spy to highlight the current section in the nav
  useEffect(() => {
    const obs = new IntersectionObserver(
      (entries) => entries.forEach((e) => { if (e.isIntersecting) setActive(e.target.id); }),
      { rootMargin: '-45% 0px -50% 0px', threshold: 0 },
    );
    SECTIONS.forEach(([id]) => { const el = document.getElementById(id); if (el) obs.observe(el); });
    return () => obs.disconnect();
  }, []);

  const mode = state?.execution_mode ?? '—';
  const modeCls = mode === 'LIVE' ? 'live' : mode === 'SHADOW' ? 'shadow' : mode === 'OFF' ? 'off' : '';

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark"><Network size={20} strokeWidth={2} /></span>
          <div>
            <div className="brand-name">EA Dashboard</div>
            <div className="brand-sub">Multi-Strategy Autonomous</div>
          </div>
        </div>

        <nav className="topnav">
          {SECTIONS.map(([id, label]) => (
            <a key={id} href={`#${id}`} className={active === id ? 'active' : ''}>{label}</a>
          ))}
        </nav>

        <div className="topbar-spacer" />

        <div className="topbar-status">
          <span className="status-pill">
            <span className={`dot ${isConnected ? 'on pulse' : 'off'}`} />
            <span className="label">{isConnected ? 'Live' : 'Offline'}</span>
          </span>
          <span className={`mode-chip ${modeCls}`}>{mode}</span>
          <span className="clock">{clock}</span>
          <button className="icon-btn" onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')} aria-label="Toggle theme">
            {theme === 'dark' ? <Sun size={17} /> : <Moon size={17} />}
          </button>
        </div>
      </header>

      <Dashboard theme={theme} />

      <footer className="page" style={{ paddingTop: 0, paddingBottom: 28, borderTop: '1px solid var(--border-faint)' }}>
        <div className="between" style={{ paddingTop: 16 }}>
          <span className="muted" style={{ fontSize: 12 }}>Multi-Strategy Autonomous EA · Dashboard</span>
          <span className="muted mono" style={{ fontSize: 11 }}>ws://{window.location.hostname}:8765</span>
        </div>
      </footer>
    </div>
  );
}
