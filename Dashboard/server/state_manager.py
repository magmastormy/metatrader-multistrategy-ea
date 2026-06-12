"""In-memory state manager for the EA dashboard."""

import asyncio
import time
from collections import deque
from typing import Any, Optional

from .config import (
    EQUITY_HISTORY_SIZE,
    RISK_HISTORY_SIZE,
    LOG_BUFFER_SIZE,
    ALERT_BUFFER_SIZE,
    COMMAND_TIMEOUT_SEC,
)


class StateManager:
    """Thread-safe in-memory store for EA state with history buffers."""

    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._state: dict[str, Any] = {}
        self._last_update: float = 0.0

        # Time-series history
        self._equity_history: deque[dict] = deque(maxlen=EQUITY_HISTORY_SIZE)
        self._risk_history: deque[dict] = deque(maxlen=RISK_HISTORY_SIZE)
        self._log_entries: deque[dict] = deque(maxlen=LOG_BUFFER_SIZE)
        self._alerts: deque[dict] = deque(maxlen=ALERT_BUFFER_SIZE)

        # Command queue
        self._commands: list[dict] = []
        self._command_counter: int = 0

    async def update_state(self, data: dict) -> None:
        """Update the current EA state from a push."""
        async with self._lock:
            self._state = data
            self._last_update = time.time()

            # Extract equity point for history
            account = data.get("account", {})
            if account:
                self._equity_history.append({
                    "timestamp": data.get("timestamp", ""),
                    "equity": account.get("equity", 0),
                    "balance": account.get("balance", 0),
                    "free_margin": account.get("free_margin", 0),
                })

            # Extract risk point for history
            risk = data.get("risk", {})
            if risk:
                self._risk_history.append({
                    "timestamp": data.get("timestamp", ""),
                    "daily_risk_used_pct": risk.get("daily_risk_used_pct", 0),
                    "open_exposure_pct": risk.get("open_exposure_pct", 0),
                    "current_drawdown_pct": risk.get("current_drawdown_pct", 0),
                    "portfolio_risk_pct": risk.get("portfolio_risk_pct", 0),
                })

    async def get_state(self) -> dict:
        """Get the current full EA state."""
        async with self._lock:
            return dict(self._state)

    async def get_positions(self) -> list:
        """Get open positions."""
        async with self._lock:
            return list(self._state.get("positions", []))

    async def get_risk(self) -> dict:
        """Get risk snapshot."""
        async with self._lock:
            return dict(self._state.get("risk", {}))

    async def get_performance(self) -> dict:
        """Get performance metrics."""
        async with self._lock:
            return dict(self._state.get("performance", {}))

    async def get_consensus(self, symbol: Optional[str] = None) -> dict:
        """Get consensus data, optionally filtered by symbol."""
        async with self._lock:
            consensus = dict(self._state.get("consensus", {}))
            if symbol and "symbols" in consensus:
                symbols = consensus["symbols"]
                if isinstance(symbols, dict) and symbol in symbols:
                    return {"symbol": symbol, **symbols[symbol]}
                return {}
            return consensus

    async def get_ai(self) -> dict:
        """Get AI subsystem status."""
        async with self._lock:
            return dict(self._state.get("ai", {}))

    async def get_strategies(self) -> list:
        """Get strategy registry."""
        async with self._lock:
            return list(self._state.get("strategies", []))

    async def get_equity_history(self) -> list:
        """Get equity curve history."""
        async with self._lock:
            return list(self._equity_history)

    async def get_risk_history(self) -> list:
        """Get risk history."""
        async with self._lock:
            return list(self._risk_history)

    async def add_log(self, entry: dict) -> None:
        """Add a parsed log entry."""
        async with self._lock:
            self._log_entries.append(entry)

    async def get_logs(self, limit: int = 100, tag: Optional[str] = None) -> list:
        """Get recent log entries, optionally filtered by tag."""
        async with self._lock:
            entries = list(self._log_entries)
            if tag:
                entries = [e for e in entries if e.get("tag") == tag]
            return entries[-limit:]

    async def add_alert(self, level: str, message: str) -> None:
        """Add an alert."""
        async with self._lock:
            self._alerts.append({
                "level": level,
                "message": message,
                "timestamp": time.time(),
            })

    async def get_alerts(self, limit: int = 50) -> list:
        """Get recent alerts."""
        async with self._lock:
            return list(self._alerts)[-limit:]

    async def add_command(self, cmd_type: str, params: dict) -> str:
        """Queue a control command for the EA. Returns command ID."""
        async with self._lock:
            self._command_counter += 1
            cmd_id = f"cmd-{self._command_counter:06d}"
            self._commands.append({
                "id": cmd_id,
                "type": cmd_type,
                "params": params,
                "timestamp": time.time(),
            })
            return cmd_id

    async def get_pending_commands(self) -> list:
        """Get pending (unexpired) commands for EA to poll."""
        async with self._lock:
            now = time.time()
            self._commands = [
                c for c in self._commands
                if (now - c["timestamp"]) < COMMAND_TIMEOUT_SEC
            ]
            return list(self._commands)

    async def acknowledge_command(self, cmd_id: str) -> bool:
        """Remove a command after EA acknowledges execution."""
        async with self._lock:
            before = len(self._commands)
            self._commands = [c for c in self._commands if c["id"] != cmd_id]
            return len(self._commands) < before

    @property
    def last_update(self) -> float:
        return self._last_update
