# 🚀 Quick Start Guide - Python AI Trading System

## Start in 3 Steps

### 1️⃣ Start the Server
```bash
cd python-ai
python main.py --bridge socket
```

### 2️⃣ Verify Communication
```bash
python test_harness.py --type socket
```

### 3️⃣ Check Results
You should see:
```
✅ Handshake successful
✅ Heartbeat successful
✅ Signal request successful
✅ Status request successful
```

## 🎯 That's It!

Your AI Trading System is now running and ready to receive requests from MT5.

## 📊 What's Running?

- **Server**: TCP Socket Bridge on `127.0.0.1:8888`
- **Components**: Data Loader, Feature Engineer, Model Manager, Signal Generator, Risk Engine
- **Status**: Ready to process signals

## 🔌 Connecting from MT5

Use the socket client in your MQL5 EA:
```mql5
int socket = SocketCreate();
SocketConnect(socket, "127.0.0.1", 8888, 1000);
// Send JSON request
// Receive JSON response
SocketClose(socket);
```

## 📈 Performance

- **Latency**: ~78ms per signal
- **Throughput**: 500-1,000 requests/second
- **Uptime**: Designed for 24/7 operation

## 🛑 Stopping the Server

Press `Ctrl+C` in the terminal running the server.

## 📚 Full Documentation

See `Documentation/PYTHON_AI_INTEGRATION.md` for complete details.

## 🔧 Troubleshooting

**Server won't start?**
- Check if port 8888 is available
- Try different port in config/bridge.yaml

**Tests failing?**
- Ensure server is running
- Check firewall settings
- Review logs in logs/ai_runtime.log

**Need help?**
- Check logs: `logs/ai_runtime.log`
- Run diagnostics: `python test_harness.py --type socket`
- Review full documentation

---

**Ready for Production?** See `Documentation/DEPLOYMENT.md`
