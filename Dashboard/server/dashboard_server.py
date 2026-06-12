"""EA Command Center Dashboard Server — FastAPI + WebSocket."""

import asyncio
import json
import logging
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from .config import SERVER_HOST, SERVER_PORT, CORS_ORIGINS, COMMAND_PURGE_INTERVAL
from .state_manager import StateManager

logger = logging.getLogger("dashboard")

# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class StatePushBody(BaseModel):
    """EA state push payload — flexible to accept any JSON."""
    model_config = {"extra": "allow"}

class CommandBody(BaseModel):
    type: str
    params: dict = {}


# ---------------------------------------------------------------------------
# App + state
# ---------------------------------------------------------------------------

app = FastAPI(title="EA Command Center", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

state_manager = StateManager()

# WebSocket client tracking
_ws_clients: set[WebSocket] = set()
_ws_lock = asyncio.Lock()


# ---------------------------------------------------------------------------
# Background: purge expired commands
# ---------------------------------------------------------------------------

async def _purge_expired_commands() -> None:
    """Periodically purge expired commands."""
    while True:
        await asyncio.sleep(COMMAND_PURGE_INTERVAL)
        await state_manager.get_pending_commands()  # side-effect: purges expired


@app.on_event("startup")
async def _startup() -> None:
    asyncio.create_task(_purge_expired_commands())


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
async def receive_state(body: dict):
    """Receive EA state push."""
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
# Control endpoints
# ---------------------------------------------------------------------------

@app.post("/api/control/command")
async def queue_command(body: CommandBody):
    cmd_id = await state_manager.add_command(body.type, body.params)
    return {"id": cmd_id, "type": body.type, "params": body.params}


@app.get("/api/control/commands")
async def get_pending_commands():
    commands = await state_manager.get_pending_commands()
    return {"commands": commands}


@app.post("/api/control/ack/{cmd_id}")
async def ack_command(cmd_id: str):
    found = await state_manager.acknowledge_command(cmd_id)
    if not found:
        raise HTTPException(status_code=404, detail="Command not found")
    return {"status": "acknowledged"}


# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    async with _ws_lock:
        _ws_clients.add(ws)

    # Send current state immediately on connect
    current = await state_manager.get_state()
    if current:
        await ws.send_text(json.dumps({"type": "state", "data": current}))

    try:
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            msg_type = msg.get("type")

            if msg_type == "command":
                cmd_type = msg.get("data", {}).get("type", "")
                cmd_params = msg.get("data", {}).get("params", {})
                cmd_id = await state_manager.add_command(cmd_type, cmd_params)
                await ws.send_text(json.dumps({
                    "type": "command_queued",
                    "data": {"id": cmd_id, "type": cmd_type, "params": cmd_params},
                }))

            elif msg_type == "subscribe":
                # Future: channel-based subscription filtering
                pass

            elif msg_type == "unsubscribe":
                pass

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
        "Dashboard.server.dashboard_server:app",
        host=SERVER_HOST,
        port=SERVER_PORT,
        reload=False,
        log_level="info",
    )


if __name__ == "__main__":
    main()
