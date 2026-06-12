"""MT5 log file tailer — watches and parses tagged log entries in real-time."""

import asyncio
import glob
import logging
import os
import re
from datetime import datetime
from typing import Any, Callable, Coroutine, Optional

from .config import LOG_DIR, LOG_POLL_INTERVAL

logger = logging.getLogger("dashboard.log_tailer")

LogCallback = Callable[[dict], Coroutine[Any, Any, None]]

# ---------------------------------------------------------------------------
# Tag parsing patterns
# ---------------------------------------------------------------------------

_TAG_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("HEARTBEAT", re.compile(
        r'\[HEARTBEAT\]\s+scans=(\d+)\s+.*signals_generated=(\d+).*signals_validated=(\d+).*trades_opened=(\d+).*shadow_trades=(\d+).*spike_events=(\d+)'
    )),
    ("CONSENSUS-DIAG", re.compile(
        r'\[CONSENSUS-DIAG\]\s+symbol=(\S+)\s+strategy=(\S+)\s+type=(\S+)\s+Conf=([\d.]+)%?\s+Weight=([\d.]+)\s+Reason=(\S+)'
    )),
    ("AI-VOTE-ONNX", re.compile(
        r'\[AI-VOTE\]\[ONNX\]\s+symbol=(\S+)\s+votes=(\d+)\s+buy=(\d+)\s+sell=(\d+)\s+none=(\d+)\s+conf=([\d.]+)\s+reason=(\S+)'
    )),
    ("AI-VOTE-ENSEMBLE", re.compile(
        r'\[AI-VOTE\]\[Ensemble\]\s+symbol=(\S+)\s+votes=(\d+)\s+buy=(\d+)\s+sell=(\d+)\s+none=(\d+)\s+conf=([\d.]+)\s+reason=(\S+)'
    )),
    ("AI-VOTE-TRANSFORMER", re.compile(
        r'\[AI-VOTE\]\[Transformer\]\s+symbol=(\S+)\s+votes=(\d+)\s+buy=(\d+)\s+sell=(\d+)\s+none=(\d+)\s+conf=([\d.]+)\s+reason=(\S+)'
    )),
    ("SIGNAL-REJECTED", re.compile(
        r'\[SIGNAL-REJECTED\]\s+cycle=(\d+)\s+symbol=(\S+)\s+reason=([^|]+?)(?:\s+conf=([\d.]+))?.*quality=([\d.]+)'
    )),
    ("SHADOW-TRADE", re.compile(
        r'\[SHADOW-TRADE\]\s+cycle=(\d+)\s+symbol=(\S+)\s+signal=(\S+)\s+lot=([\d.]+)\s+conf=([\d.]+)'
    )),
    ("RISK-BUDGET", re.compile(
        r'\[RISK-BUDGET\]\s+.*effective[=/]([\d.]+).*entry[=/]([\d.]+).*mtm[=/]([\d.]+).*open_exposure[=/]([\d.]+)'
    )),
    ("SPIKE-ALARM", re.compile(
        r'\[SPIKE-ALARM\]\s+symbol=(\S+)\s+rate=([\d.]+)\s+baseline=([\d.]+)'
    )),
    ("PYTHON-BRIDGE-DASHBOARD", re.compile(
        r'\[PYTHON-BRIDGE-DASHBOARD\]\s+CONN:(\S+)\s+\|.*VER:(\S+)\s+\|.*REQS:(\d+)\s+\|.*OK:(\d+)\s+\|.*ERR:(\d+)'
    )),
]

# Generic tag extractor for any [TAG] not matched above
_GENERIC_TAG = re.compile(r'\[([A-Z][A-Z0-9_-]+)\]')


def _coerce_numeric(val: str) -> int | float | str:
    """Try to convert a string to int, then float, else keep as string."""
    try:
        return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except ValueError:
        pass
    # Strip trailing % and try again
    if val.endswith('%'):
        try:
            return float(val[:-1])
        except ValueError:
            pass
    return val


class MT5LogTailer:
    """Watches MT5 log files and parses tagged entries in real-time."""

    def __init__(self, log_dir: str = "", callback: Optional[LogCallback] = None) -> None:
        self._log_dir = log_dir or LOG_DIR
        self._callback = callback
        self._running = False
        self._current_file: Optional[str] = None
        self._file_offset: int = 0

    # -----------------------------------------------------------------------
    # Log file discovery
    # -----------------------------------------------------------------------

    def _discover_log_dir(self) -> Optional[str]:
        """Find the MT5 terminal log directory."""
        if self._log_dir:
            return self._log_dir if os.path.isdir(self._log_dir) else None

        # Search common MT5 log locations
        appdata = os.environ.get("APPDATA", "")
        if not appdata:
            return None

        metaquotes = os.path.join(appdata, "MetaQuotes", "Terminal")
        if not os.path.isdir(metaquotes):
            return None

        # Find the most recently modified Logs directory
        best_dir: Optional[str] = None
        best_mtime: float = 0.0
        for terminal_dir in glob.glob(os.path.join(metaquotes, "*", "Logs")):
            if os.path.isdir(terminal_dir):
                mtime = os.path.getmtime(terminal_dir)
                if mtime > best_mtime:
                    best_mtime = mtime
                    best_dir = terminal_dir

        return best_dir

    def _find_current_log_file(self, log_dir: str) -> Optional[str]:
        """Find the most recent YYYYMMDD.log file."""
        today = datetime.now().strftime("%Y%m%d")
        today_file = os.path.join(log_dir, f"{today}.log")
        if os.path.isfile(today_file):
            return today_file

        # Fall back to most recent .log file
        log_files = glob.glob(os.path.join(log_dir, "*.log"))
        if not log_files:
            return None
        return max(log_files, key=os.path.getmtime)

    # -----------------------------------------------------------------------
    # Parsing
    # -----------------------------------------------------------------------

    def parse_line(self, line: str) -> Optional[dict]:
        """Parse a single log line into structured data."""
        line = line.strip()
        if not line:
            return None

        # Try each specific tag pattern first
        for tag_name, pattern in _TAG_PATTERNS:
            m = pattern.search(line)
            if m:
                fields: dict[str, Any] = {}
                groups = m.groups()
                if tag_name == "HEARTBEAT" and len(groups) >= 6:
                    fields = {
                        "scans": _coerce_numeric(groups[0]),
                        "signals_generated": _coerce_numeric(groups[1]),
                        "signals_validated": _coerce_numeric(groups[2]),
                        "trades_opened": _coerce_numeric(groups[3]),
                        "shadow_trades": _coerce_numeric(groups[4]),
                        "spike_events": _coerce_numeric(groups[5]),
                    }
                elif tag_name == "CONSENSUS-DIAG" and len(groups) >= 6:
                    fields = {
                        "symbol": groups[0],
                        "strategy": groups[1],
                        "type": groups[2],
                        "confidence": _coerce_numeric(groups[3]),
                        "weight": _coerce_numeric(groups[4]),
                        "reason": groups[5],
                    }
                elif tag_name.startswith("AI-VOTE") and len(groups) >= 7:
                    fields = {
                        "symbol": groups[0],
                        "votes": _coerce_numeric(groups[1]),
                        "buy": _coerce_numeric(groups[2]),
                        "sell": _coerce_numeric(groups[3]),
                        "none": _coerce_numeric(groups[4]),
                        "confidence": _coerce_numeric(groups[5]),
                        "reason": groups[6],
                    }
                elif tag_name == "SIGNAL-REJECTED" and len(groups) >= 5:
                    fields = {
                        "cycle": _coerce_numeric(groups[0]),
                        "symbol": groups[1],
                        "reason": groups[2].strip(),
                        "confidence": _coerce_numeric(groups[3]) if groups[3] else 0,
                        "quality": _coerce_numeric(groups[4]),
                    }
                elif tag_name == "SHADOW-TRADE" and len(groups) >= 5:
                    fields = {
                        "cycle": _coerce_numeric(groups[0]),
                        "symbol": groups[1],
                        "signal": groups[2],
                        "lot": _coerce_numeric(groups[3]),
                        "confidence": _coerce_numeric(groups[4]),
                    }
                elif tag_name == "RISK-BUDGET" and len(groups) >= 4:
                    fields = {
                        "effective": _coerce_numeric(groups[0]),
                        "entry": _coerce_numeric(groups[1]),
                        "mtm": _coerce_numeric(groups[2]),
                        "open_exposure": _coerce_numeric(groups[3]),
                    }
                elif tag_name == "SPIKE-ALARM" and len(groups) >= 3:
                    fields = {
                        "symbol": groups[0],
                        "rate": _coerce_numeric(groups[1]),
                        "baseline": _coerce_numeric(groups[2]),
                    }
                elif tag_name == "PYTHON-BRIDGE-DASHBOARD" and len(groups) >= 5:
                    fields = {
                        "connection": groups[0],
                        "version": groups[1],
                        "requests": _coerce_numeric(groups[2]),
                        "ok": _coerce_numeric(groups[3]),
                        "errors": _coerce_numeric(groups[4]),
                    }

                return {
                    "tag": tag_name,
                    "timestamp": datetime.now().isoformat(),
                    "fields": fields,
                    "raw": line,
                }

        # Fallback: extract generic tag name
        m = _GENERIC_TAG.search(line)
        if m:
            return {
                "tag": m.group(1),
                "timestamp": datetime.now().isoformat(),
                "fields": {},
                "raw": line,
            }

        return None

    # -----------------------------------------------------------------------
    # Tailing
    # -----------------------------------------------------------------------

    async def _dispatch(self, entry: dict) -> None:
        """Send parsed entry to callback."""
        if self._callback:
            try:
                await self._callback(entry)
            except Exception as e:
                logger.error("Log callback error: %s", e)

    async def _read_new_lines(self, filepath: str) -> None:
        """Read new lines from the current log file starting at offset."""
        try:
            with open(filepath, "r", encoding="utf-8", errors="replace") as f:
                f.seek(self._file_offset)
                for line in f:
                    entry = self.parse_line(line)
                    if entry:
                        await self._dispatch(entry)
                self._file_offset = f.tell()
        except FileNotFoundError:
            logger.warning("Log file disappeared: %s", filepath)
        except Exception as e:
            logger.error("Error reading log file: %s", e)

    async def start(self) -> None:
        """Start watching log files."""
        self._running = True
        logger.info("MT5 log tailer starting...")

        # Try watchfiles first, fall back to polling
        try:
            from watchfiles import awatch
            await self._run_with_watchfiles(awatch)
        except ImportError:
            logger.info("watchfiles not available, using polling")
            await self._run_with_polling()

    async def stop(self) -> None:
        """Stop watching."""
        self._running = False

    async def _run_with_polling(self) -> None:
        """Fallback: poll log file for new content."""
        while self._running:
            log_dir = self._discover_log_dir()
            if log_dir:
                filepath = self._find_current_log_file(log_dir)
                if filepath:
                    # Handle file rotation
                    if filepath != self._current_file:
                        self._current_file = filepath
                        self._file_offset = 0  # Start from beginning of new file
                        logger.info("Watching log file: %s", filepath)

                    await self._read_new_lines(filepath)

            await asyncio.sleep(LOG_POLL_INTERVAL)

    async def _run_with_watchfiles(self, awatch) -> None:
        """Use watchfiles for efficient file watching."""
        log_dir = self._discover_log_dir()
        if not log_dir:
            logger.warning("No MT5 log directory found, falling back to polling")
            await self._run_with_polling()
            return

        # Initial read of current file
        filepath = self._find_current_log_file(log_dir)
        if filepath:
            self._current_file = filepath
            # Start from end of file (only new entries)
            try:
                self._file_offset = os.path.getsize(filepath)
            except OSError:
                self._file_offset = 0
            logger.info("Watching log file: %s", filepath)

        async for changes in awatch(log_dir):
            if not self._running:
                break

            for change_type, path in changes:
                if not path.endswith(".log"):
                    continue

                # Handle file rotation
                if path != self._current_file:
                    self._current_file = path
                    self._file_offset = 0
                    logger.info("Rotated to new log file: %s", path)

                await self._read_new_lines(path)
