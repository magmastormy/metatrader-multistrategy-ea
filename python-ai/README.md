# 🔥 Modern AI Trading System

A production-ready, modular, and scalable AI trading system for MetaTrader 5.

## 🚀 Features

- **Lightweight Models**: Optimized for speed and low resource usage (LightGBM, ONNX, Distilled Transformer).
- **Robust Bridge**: ZeroMQ (Primary) and TCP Socket (Secondary) communication.
- **Handshake Protocol**: Ensures version compatibility and system readiness.
- **Caching**: LRU cache for sub-millisecond inference on repeated data.
- **Structured Logging**: Clear, timestamped logs for easy debugging.

## 🛠️ Installation

1.  **Install Python 3.10+**
2.  **Install Dependencies**:
    ```bash
    pip install -r requirements.txt
    ```

## 🏃 Usage

### Start the Server
```bash
python main.py --bridge auto
```
Options: `--bridge [zmq|socket|file]`

### Run Tests
```bash
python test_harness.py --type [zmq|socket]
```

## 🔌 API Protocol

All messages are JSON-formatted.

### Handshake
**Request**:
```json
{
  "type": "handshake",
  "data": { "version": "MQL5-1.0" }
}
```
**Response**:
```json
{
  "type": "handshake_response",
  "success": true,
  "data": { "status": "ready", "version": "2.0.0", "models_loaded": ["lgbm", "onnx"] }
}
```

### Heartbeat
**Request**:
```json
{ "type": "heartbeat", "data": {} }
```
**Response**:
```json
{ "type": "heartbeat_response", "success": true, "data": { "status": "alive" } }
```

### Signal Request
**Request**:
```json
{
  "type": "signal_request",
  "data": {
    "symbol": "EURUSD",
    "market_data": { ... }
  }
}
```

## 📂 Structure

- `core/`: AI logic (Data Loader, Feature Engineering, Model Manager).
- `bridge/`: Communication logic (ZMQ, Socket, File).
- `models/`: Trained models (Pickle, ONNX, PT).
- `logs/`: Runtime logs.

## 🔗 MQL5 Integration

See `MQL5_INTEGRATION.md` for a complete code snippet to connect your EA.
