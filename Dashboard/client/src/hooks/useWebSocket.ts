import { useState, useEffect, useRef, useCallback } from 'react';
import type { WSMessage } from '../types/ea-state';

export type ConnectionStatus = 'connecting' | 'connected' | 'disconnected' | 'reconnecting' | 'error';

interface UseWebSocketReturn {
  lastMessage: WSMessage | null;
  isConnected: boolean;
  status: ConnectionStatus;
  send: (data: unknown) => void;
  reconnect: () => void;
}

export function useWebSocket(): UseWebSocketReturn {
  const [lastMessage, setLastMessage] = useState<WSMessage | null>(null);
  const [status, setStatus] = useState<ConnectionStatus>('connecting');
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reconnectDelayRef = useRef(1000);
  const maxReconnectDelay = 30000;
  const reconnectAttemptsRef = useRef(0);
  const maxReconnectAttempts = 10;
  const urlRef = useRef<string>('');

  const buildUrl = useCallback(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.hostname}:8765/ws`;
  }, []);

  const connect = useCallback(() => {
    const wsUrl = buildUrl();
    urlRef.current = wsUrl;

    if (wsRef.current?.readyState === WebSocket.OPEN || wsRef.current?.readyState === WebSocket.CONNECTING) {
      return;
    }

    setStatus('connecting');
    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      setStatus('connected');
      setIsConnectedState(true);
      reconnectDelayRef.current = 1000;
      reconnectAttemptsRef.current = 0;
    };

    ws.onmessage = (event) => {
      try {
        const msg: WSMessage = JSON.parse(event.data);
        setLastMessage(msg);
      } catch {
        setLastMessage({ type: 'log', data: { raw: event.data } });
      }
    };

    ws.onclose = (event) => {
      setIsConnectedState(false);
      wsRef.current = null;

      if (event.wasClean) {
        setStatus('disconnected');
      } else {
        setStatus('reconnecting');
        const delay = reconnectDelayRef.current;
        reconnectTimeoutRef.current = setTimeout(() => {
          reconnectDelayRef.current = Math.min(delay * 2, maxReconnectDelay);
          reconnectAttemptsRef.current += 1;
          if (reconnectAttemptsRef.current >= maxReconnectAttempts) {
            setStatus('error');
            return;
          }
          connect();
        }, delay);
      }
    };

    ws.onerror = () => {
      setStatus('error');
      ws.close();
    };
  }, [buildUrl]);

  const setIsConnectedState = useCallback((connected: boolean) => {
    setStatus(connected ? 'connected' : 'disconnected');
  }, []);

  useEffect(() => {
    connect();
    return () => {
      if (reconnectTimeoutRef.current) clearTimeout(reconnectTimeoutRef.current);
      if (wsRef.current) {
        wsRef.current.onclose = null;
        wsRef.current.close();
      }
    };
  }, [connect]);

  const send = useCallback((data: unknown) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(data));
    }
  }, []);

  const reconnect = useCallback(() => {
    reconnectDelayRef.current = 1000;
    reconnectAttemptsRef.current = 0;
    if (wsRef.current) {
      wsRef.current.onclose = null;
      wsRef.current.close();
    }
    connect();
  }, [connect]);

  return { lastMessage, isConnected: status === 'connected', status, send, reconnect };
}
