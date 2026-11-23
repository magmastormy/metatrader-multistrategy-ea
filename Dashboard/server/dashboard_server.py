"""EA Command Center Dashboard Server — FastAPI + WebSocket."""

import asyncio
import json
import logging
from typing import Optional

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from .config import SERVER_HOST, SERVER_PORT, CORS_ORIGINS
from .state_manager import StateManager

logger = logging.getLogger("dashboard")

# ---------------------------------------------------------------------------
# App + state
# ---------------------------------------------------------------------------

app = FastAPI(title="EA Command Center", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

state_manager = StateManager()

# WebSocket client tracking
_ws_clients: set[WebSocket] = set()
_ws_lock = asyncio.Lock()


def _is_allowed_origin(origin: Optional[str]) -> bool:
    if origin is None:
        return True
    normalized_origin = origin.rstrip("/")
    return any(normalized_origin == allowed.rstrip("/") for allowed in CORS_ORIGINS)


# ---------------------------------------------------------------------------
# WebSocket broadcast helper
# ---------------------------------------------------------------------------

async def _broadcast(message: dict) -> None:
    """Send a JSON message to all connected WebSocket clients."""
    payload = json.dumps(message)
    dead: list[WebSocket] = []
    async with _ws_lock:
        for ws in _ws_clients:
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            _ws_clients.discard(ws)


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------

@app.post("/state")
async def receive_state(request: Request):
    """Receive EA state push."""
    if not _is_allowed_origin(request.headers.get("origin")):
        raise HTTPException(status_code=403, detail="Origin not allowed")

    raw = await request.body()
    if not raw:
        logger.warning("Empty state push received")
        raise HTTPException(status_code=422, detail="Empty body")
    try:
        body = json.loads(raw)
    except Exception as e:
        # Find the problematic area
        err_str = str(e)
        char_pos = -1
        if "char" in err_str:
            try:
                char_pos = int(err_str.split("char ")[1].rstrip(")"))
            except:
                pass
        context = ""
        if char_pos > 0:
            start = max(0, char_pos - 50)
            end = min(len(raw), char_pos + 50)
            context = f"\nContext around char {char_pos}: ...{raw[start:end]}..."
        logger.error("JSON parse error: %s | len=%d%s", e, len(raw), context)
        raise HTTPException(status_code=422, detail=f"Invalid JSON: {e}")
    await state_manager.update_state(body)
    await _broadcast({"type": "state", "data": body})
    return {"status": "ok"}


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.get("/api/status")
async def get_status():
    return await state_manager.get_state()


@app.get("/api/positions")
async def get_positions():
    return await state_manager.get_positions()


@app.get("/api/risk")
async def get_risk():
    return await state_manager.get_risk()


@app.get("/api/performance")
async def get_performance():
    return await state_manager.get_performance()


@app.get("/api/consensus/{symbol}")
async def get_consensus(symbol: str):
    return await state_manager.get_consensus(symbol)


@app.get("/api/ai")
async def get_ai():
    return await state_manager.get_ai()


@app.get("/api/strategies")
async def get_strategies():
    return await state_manager.get_strategies()


@app.get("/api/equity-history")
async def get_equity_history():
    return await state_manager.get_equity_history()


@app.get("/api/risk-history")
async def get_risk_history():
    return await state_manager.get_risk_history()


@app.get("/api/logs")
async def get_logs(limit: int = 100, tag: Optional[str] = None):
    return await state_manager.get_logs(limit=limit, tag=tag)


@app.get("/api/alerts")
async def get_alerts(limit: int = 50):
    return await state_manager.get_alerts(limit=limit)


# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    if not _is_allowed_origin(ws.headers.get("origin")):
        await ws.close(code=1008)
        return

    await ws.accept()
    async with _ws_lock:
        _ws_clients.add(ws)

    # Send current state immediately on connect
    current = await state_manager.get_state()
    if current:
        await ws.send_text(json.dumps({"type": "state", "data": current}))

    try:
        while True:
            await ws.receive_text()
            await ws.send_text(json.dumps({
                "type": "error",
                "data": {"message": "The dashboard is read-only; trading commands are not supported."},
            }))

    except WebSocketDisconnect:
        pass
    finally:
        async with _ws_lock:
            _ws_clients.discard(ws)


# ---------------------------------------------------------------------------
# Log tailer integration hook
# ---------------------------------------------------------------------------

async def on_log_entry(entry: dict) -> None:
    """Callback for the log tailer — stores and broadcasts parsed entries."""
    await state_manager.add_log(entry)
    await _broadcast({"type": "log", "data": entry})

    # Generate alerts for critical tags
    tag = entry.get("tag", "")
    if tag in ("SPIKE-ALARM", "EMERGENCY"):
        await state_manager.add_alert("critical", entry.get("raw", ""))
        await _broadcast({"type": "alert", "data": {"level": "critical", "message": entry.get("raw", "")}})
    elif tag == "SIGNAL-REJECTED":
        await state_manager.add_alert("info", entry.get("raw", ""))


# ---------------------------------------------------------------------------
# Run server
# ---------------------------------------------------------------------------

def main() -> None:
    """Run the dashboard server."""
    import uvicorn
    uvicorn.run(
        "server.dashboard_server:app",
        host=SERVER_HOST,
        port=SERVER_PORT,
        reload=False,
        log_level="info",
    )


if __name__ == "__main__":
    main()
