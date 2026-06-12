import { useState, useCallback, useRef, useEffect } from 'react';
import type { EAState, LogEntry, WSMessage } from '../types/ea-state';
import { useWebSocket } from './useWebSocket';

interface AlertEntry {
  id: number;
  timestamp: string;
  message: string;
  severity: 'info' | 'warning' | 'error';
}

interface UseEAStateReturn {
  state: EAState | null;
  logs: LogEntry[];
  alerts: AlertEntry[];
  isConnected: boolean;
  sendCommand: (command: string, params?: Record<string, unknown>) => void;
}

let alertIdCounter = 0;

export function useEAState(): UseEAStateReturn {
  const { lastMessage, isConnected, send } = useWebSocket();
  const [state, setState] = useState<EAState | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [alerts, setAlerts] = useState<AlertEntry[]>([]);
  const processedRef = useRef<WSMessage | null>(null);

  const addAlert = useCallback((message: string, severity: AlertEntry['severity'] = 'info') => {
    const id = ++alertIdCounter;
    setAlerts((prev) => {
      const next = [{ id, timestamp: new Date().toISOString(), message, severity }, ...prev];
      return next.slice(0, 50);
    });
  }, []);

  useEffect(() => {
    if (!lastMessage || lastMessage === processedRef.current) return;
    processedRef.current = lastMessage;

    switch (lastMessage.type) {
      case 'state':
        setState(lastMessage.data as EAState);
        break;
      case 'log': {
        const entry = lastMessage.data as LogEntry;
        setLogs((prev) => [entry, ...prev].slice(0, 500));
        break;
      }
      case 'alert': {
        const data = lastMessage.data as { message?: string; severity?: string };
        addAlert(data.message ?? 'Unknown alert', (data.severity as AlertEntry['severity']) ?? 'info');
        break;
      }
      case 'trade': {
        const tradeData = lastMessage.data as { action?: string; symbol?: string };
        addAlert(`Trade: ${tradeData.action ?? 'update'} ${tradeData.symbol ?? ''}`.trim(), 'info');
        break;
      }
    }
  }, [lastMessage, addAlert]);

  const sendCommand = useCallback((command: string, params?: Record<string, unknown>) => {
    send({ command, ...params });
  }, [send]);

  return { state, logs, alerts, isConnected, sendCommand };
}
