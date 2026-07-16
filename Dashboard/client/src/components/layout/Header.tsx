import { useState, useEffect } from 'react';
import { Bell, Settings, ChevronDown, User, LogOut, Terminal, Zap, Shield } from 'lucide-react';
import { useEAState } from '../../hooks/useEAState';

interface HeaderProps {
  isConnected: boolean;
  executionMode: string;
}

export default function Header({ isConnected, executionMode }: HeaderProps) {
  const [clock, setClock] = useState('');
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const { state, alerts } = useEAState();
  const [unreadCount, setUnreadCount] = useState(0);

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      setClock(now.toLocaleTimeString('en-GB', { hour12: false, second: '2-digit' }));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    setUnreadCount(alerts.filter(a => a.severity === 'error' || a.severity === 'warning').length);
  }, [alerts]);

  const getModeConfig = () => {
    switch (executionMode) {
      case 'LIVE':
        return { label: 'LIVE', className: 'mode-live', icon: Zap, color: 'text-accent-green' };
      case 'SHADOW':
        return { label: 'SHADOW', className: 'mode-shadow', icon: Shield, color: 'text-accent-amber' };
      case 'PAPER':
        return { label: 'PAPER', className: 'mode-paper', icon: Terminal, color: 'text-accent-cyan' };
      default:
        return { label: 'OFFLINE', className: 'mode-offline', icon: Shield, color: 'text-text-muted' };
    }
  };

  const modeConfig = getModeConfig();
  const ModeIcon = modeConfig.icon;

  return (
    <header className="header">
      <div className="header-left">
        <h1 className="header-title">Command Center</h1>
        {state && (
          <span className="header-subtitle">
            {state.account.equity.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} USD
          </span>
        )}
      </div>

      <div className="header-center">
        <div className="clock-container">
          <span className="clock">{clock}</span>
          <span className="timezone">UTC</span>
        </div>
      </div>

      <div className="header-right">
        {/* Connection Status */}
        <div className="connection-status">
          <div className={`status-indicator ${isConnected ? 'connected' : 'disconnected'}`}>
            <span className="status-dot" />
          </div>
          <span className="status-text">{isConnected ? 'Connected' : 'Disconnected'}</span>
        </div>

        {/* Execution Mode Badge */}
        <div className={`mode-badge ${modeConfig.className}`}>
          <ModeIcon className={`w-3 h-3 ${modeConfig.color}`} strokeWidth={2.5} />
          <span className="mode-label">{modeConfig.label}</span>
        </div>

        {/* Notifications */}
        <div className="relative">
          <button
            className="icon-btn"
            onClick={() => setNotificationsOpen(!notificationsOpen)}
            aria-label={`Notifications${unreadCount > 0 ? ` (${unreadCount})` : ''}`}
            aria-expanded={notificationsOpen}
          >
            <Bell className="w-5 h-5" strokeWidth={2} />
            {unreadCount > 0 && (
              <span className="notification-badge">{unreadCount > 9 ? '9+' : unreadCount}</span>
            )}
          </button>

          {notificationsOpen && (
            <div className="dropdown notifications-dropdown animate-scale-in">
              <div className="dropdown-header">
                <h3 className="dropdown-title">Alerts</h3>
                {unreadCount > 0 && (
                  <button className="btn-text-sm" onClick={() => setUnreadCount(0)}>Mark all read</button>
                )}
              </div>
              <div className="dropdown-divider" />
              <div className="dropdown-content">
                {alerts.slice(0, 10).map((alert) => (
                  <div
                    key={alert.id}
                    className={`notification-item ${alert.severity}`}
                  >
                    <div className="notification-icon">
                      <span className={`severity-dot severity-${alert.severity}`} />
                    </div>
                    <div className="notification-content">
                      <p className="notification-message">{alert.message}</p>
                      <span className="notification-time">
                        {new Date(alert.timestamp).toLocaleTimeString('en-GB', { hour12: false })}
                      </span>
                    </div>
                  </div>
                ))}
                {alerts.length === 0 && (
                  <div className="empty-state">
                    <Bell className="w-8 h-8 text-text-muted" strokeWidth={1.5} />
                    <p className="empty-text">No alerts</p>
                    <p className="empty-subtext">System operating normally</p>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

        {/* User Menu */}
        <div className="relative">
          <button
            className="user-btn"
            onClick={() => setUserMenuOpen(!userMenuOpen)}
            aria-expanded={userMenuOpen}
            aria-label="User menu"
          >
            <div className="user-avatar">
              <User className="w-4 h-4" strokeWidth={2.5} />
            </div>
            <span className="user-name">Trader</span>
            <ChevronDown className="w-4 h-4" strokeWidth={2.5} />
          </button>

          {userMenuOpen && (
            <div className="dropdown user-dropdown animate-scale-in">
              <div className="dropdown-header user-info">
                <div className="user-avatar-lg">
                  <User className="w-5 h-5" strokeWidth={2.5} />
                </div>
                <div>
                  <p className="user-name-lg">Trader</p>
                  <p className="user-role">Multi-Strategy EA</p>
                </div>
              </div>
              <div className="dropdown-divider" />
              <div className="dropdown-content">
                <button className="dropdown-item">
                  <Settings className="w-4 h-4" strokeWidth={2} />
                  <span>Settings</span>
                </button>
                <button className="dropdown-item">
                  <Terminal className="w-4 h-4" strokeWidth={2} />
                  <span>Logs</span>
                </button>
                <div className="dropdown-divider" />
                <button className="dropdown-item danger">
                  <LogOut className="w-4 h-4" strokeWidth={2} />
                  <span>Disconnect</span>
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}