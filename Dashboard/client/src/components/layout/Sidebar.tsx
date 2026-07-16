import { NavLink, useLocation } from 'react-router-dom';
import {
  LayoutDashboard,
  Braces,
  Layers,
  Brain,
  Shield,
  Cpu,
  Terminal,
  Settings,
  Activity,
  ChevronRight,
} from 'lucide-react';
import { useState, useEffect } from 'react';

const navItems = [
  { to: '/', icon: LayoutDashboard, label: 'Overview', badge: null },
  { to: '/charts', icon: Braces, label: 'Charts', badge: null },
  { to: '/positions', icon: Layers, label: 'Positions', badge: null },
  { to: '/strategies', icon: Brain, label: 'Strategies', badge: null },
  { to: '/risk', icon: Shield, label: 'Risk', badge: null },
  { to: '/ai', icon: Cpu, label: 'AI Monitor', badge: null },
  { to: '/logs', icon: Terminal, label: 'Logs', badge: null },
  { to: '/control', icon: Settings, label: 'Control', badge: null },
] as const;

export default function Sidebar() {
  const location = useLocation();
  const [expanded, setExpanded] = useState(false);
  const [hovered, setHovered] = useState(false);

  useEffect(() => {
    setExpanded(location.pathname !== '/');
  }, [location]);

  const isActive = (to: string) => location.pathname === to || (to !== '/' && location.pathname.startsWith(to));

  return (
    <nav
      className="fixed left-0 top-0 z-40 flex flex-col h-screen bg-surface-0 border-r border-border-subtle transition-all duration-300 ease-out"
      style={{ width: expanded || hovered ? '16rem' : '4rem' }}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      {/* Brand */}
      <div className="flex items-center justify-between h-14 px-4 border-b border-border-subtle">
        <div className="flex items-center gap-3">
          <div className="flex items-center justify-center w-8 h-8 rounded-lg bg-gradient-to-br from-accent-primary to-accent-secondary">
            <Activity className="w-5 h-5 text-text-inverse" strokeWidth={2.5} />
          </div>
          {expanded || hovered ? (
            <span className="font-display font-bold text-lg text-text-primary tracking-tight">
              EA Command
            </span>
          ) : null}
        </div>
        <button
          onClick={() => setExpanded(!expanded)}
          className="flex items-center justify-center w-8 h-8 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-2 transition-colors duration-200"
          aria-label={expanded ? 'Collapse sidebar' : 'Expand sidebar'}
        >
          <ChevronRight className={`w-4 h-4 transition-transform duration-300 ${expanded ? 'rotate-180' : ''}`} />
        </button>
      </div>

      {/* Navigation */}
      <div className="flex-1 overflow-y-auto py-4 px-2 space-y-1">
        {navItems.map(({ to, icon: Icon, label, badge }) => {
          const active = isActive(to);
          return (
            <NavLink
              key={to}
              to={to}
              end={to === '/'}
              className={({ isActive }) => `
                relative group flex items-center gap-3 px-3 py-2.5 rounded-xl transition-all duration-200 ease-out
                ${isActive
                  ? 'bg-gradient-to-r from-accent-primary/10 to-accent-secondary/10 text-accent-primary border border-accent-primary/20 shadow-glow-sm'
                  : 'text-text-tertiary hover:text-text-primary hover:bg-surface-2'
                }
                ${expanded || hovered ? '' : 'justify-center'}
              `}
              title={expanded || hovered ? undefined : label}
            >
              <Icon className="w-5 h-5 flex-shrink-0" strokeWidth={2} />
              {(expanded || hovered) && (
                <>
                  <span className="font-medium text-sm truncate">{label}</span>
                  <span className="ml-auto" />
                  {badge && (
                    <span className="badge badge-sm badge-primary">
                      {badge}
                    </span>
                  )}
                </>
              )}
              {active && (expanded || hovered) && (
                <div className="absolute left-0 top-1/2 -translate-y-1/2 w-1 h-6 bg-accent-primary rounded-r-full" />
              )}
            </NavLink>
          );
        })}
      </div>

      {/* Footer - Connection Status */}
      <div className="p-4 border-t border-border-subtle">
        {(expanded || hovered) && (
          <div className="flex items-center gap-3 p-3 rounded-lg bg-surface-1 border border-border-subtle animate-fade-in-up">
            <div className="flex items-center gap-2">
              <div className="status-dot status-dot-sm status-online status-pulse" />
              <span className="text-xs font-medium text-text-primary">Live</span>
            </div>
            <span className="text-xs text-text-muted flex-1 truncate">Connected to EA</span>
          </div>
        )}
        {!expanded && !hovered && (
          <div className="flex justify-center">
            <div className="status-dot status-dot-sm status-online status-pulse" title="Connected" />
          </div>
        )}
      </div>
    </nav>
  );
}