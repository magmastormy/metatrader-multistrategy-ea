import { NavLink } from 'react-router-dom';
import {
  LayoutDashboard,
  CandlestickChart,
  Layers,
  Brain,
  Shield,
  Cpu,
  Terminal,
  Settings,
} from 'lucide-react';

const navItems = [
  { to: '/', icon: LayoutDashboard, label: 'Overview' },
  { to: '/charts', icon: CandlestickChart, label: 'Charts' },
  { to: '/positions', icon: Layers, label: 'Positions' },
  { to: '/strategies', icon: Brain, label: 'Strategies' },
  { to: '/risk', icon: Shield, label: 'Risk' },
  { to: '/ai', icon: Cpu, label: 'AI' },
  { to: '/logs', icon: Terminal, label: 'Logs' },
  { to: '/control', icon: Settings, label: 'Control' },
];

export default function Sidebar() {
  return (
    <nav className="flex flex-col items-center gap-1 py-4 w-16 min-h-screen bg-surface border-r border-border">
      <div className="mb-4 text-accent font-bold text-lg tracking-tight">EA</div>
      {navItems.map(({ to, icon: Icon, label }) => (
        <NavLink
          key={to}
          to={to}
          end={to === '/'}
          className={({ isActive }) =>
            `group relative flex items-center justify-center w-10 h-10 transition-all duration-200 ` +
            (isActive
              ? 'bg-accent text-bg'
              : 'text-text-muted hover:bg-surface-2 hover:text-text')
          }
        >
          <Icon size={20} />
          <span className="absolute left-full ml-3 px-2 py-1 text-xs font-medium bg-surface-2 text-text opacity-0 pointer-events-none group-hover:opacity-100 transition-opacity duration-200 whitespace-nowrap z-50">
            {label}
          </span>
        </NavLink>
      ))}
    </nav>
  );
}
