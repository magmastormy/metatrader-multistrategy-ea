# EA Dashboard Client

React, TypeScript, and Vite frontend for the MetaTrader EA dashboard. Live telemetry flows through the local FastAPI service in `Dashboard/server`, which listens on `127.0.0.1:8765`. The dashboard is read-only; change settings and stop trades in MetaTrader.

## Run locally

Start the backend from the repository root:

```bash
python -m pip install -r Dashboard/server/requirements.txt
python -m Dashboard.server.dashboard_server
```

In a second terminal, start the frontend from `Dashboard/client`:

```bash
npm install
npm run dev
```

The frontend connects to the WebSocket at `ws://<browser-host>:8765/ws`; Vite proxies API requests to the same local service. Run the frontend checks from `Dashboard/client`:

```bash
npm run build
npm run lint
```

## Data and display limits

- Add `?demo` only to a development URL to view synthetic sample data. Production builds ignore this flag; demo values are not account or EA telemetry.
- The EA does not publish transformer attention weights, regime transition matrices, or stage-level pipeline gate outcomes. The dashboard reports these as unavailable rather than fabricating them.
- The model architecture selector changes a local visualization only; it does not change the running EA configuration.
- Live state is only as current as the backend connection to the EA. Confirm the connection status and source logs before using the dashboard for operational decisions.
