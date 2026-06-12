"""Dashboard server configuration."""

# Server settings
SERVER_HOST = "0.0.0.0"
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

# Command settings
COMMAND_TIMEOUT_SEC = 300    # Commands expire after 5 minutes
COMMAND_PURGE_INTERVAL = 60 # Purge expired commands every 60s

# Log tailer settings
LOG_DIR = ""                 # Empty = auto-detect from MT5 terminal
LOG_POLL_INTERVAL = 0.5      # Fallback polling interval (seconds)
