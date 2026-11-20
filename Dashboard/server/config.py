"""Dashboard server configuration."""

# Server settings
SERVER_HOST = "127.0.0.1"
SERVER_PORT = 8765

# CORS origins (Vite dev server defaults)
CORS_ORIGINS = [
    "http://localhost:5173",
    "http://localhost:5174",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:5174",
]

# Buffer sizes
EQUITY_HISTORY_SIZE = 2880   # ~4h at 5s intervals
RISK_HISTORY_SIZE = 2880
LOG_BUFFER_SIZE = 1000
ALERT_BUFFER_SIZE = 50

# Log tailer settings
LOG_DIR = ""                 # Empty = auto-detect from MT5 terminal
LOG_POLL_INTERVAL = 0.5      # Fallback polling interval (seconds)
