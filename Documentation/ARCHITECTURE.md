# 🏗️ System Architecture - AI Trading System

## Overview

Modern, modular Python AI subsystem designed for high-frequency trading with MetaTrader 5.

## Design Principles

1. **Modularity**: Each component is independent and replaceable
2. **Resilience**: Multiple fallback mechanisms
3. **Performance**: <5ms total latency for signal generation
4. **Scalability**: Easy to add new models and features
5. **Maintainability**: Clean code, comprehensive logging

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MetaTrader 5 EA                      │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              COMMUNICATION BRIDGE                       │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐             │
│  │ ZeroMQ  │  │  Socket  │  │   File    │             │
│  │(Primary)│→ │(Fallback)│→ │(Last Resort)            │
│  └─────────┘  └──────────┘  └───────────┘             │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              MESSAGE PROTOCOL                           │
│         (JSON Request/Response Format)                  │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              MAIN ORCHESTRATOR                          │
│            (main.py - AITradingSystem)                  │
└────────────────┬────────────────────────────────────────┘
                 │
    ┌────────────┼────────────┬────────────┐
    ▼            ▼            ▼            ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐
│  Data   │ │Feature  │ │ Model   │ │ Signal   │
│ Loader  │ │Engineer │ │Manager  │ │Generator │
└─────────┘ └─────────┘ └─────────┘ └──────────┘
                 │            │            │
                 └────────────┼────────────┘
                              ▼
                    ┌──────────────────┐
                    │   Risk Engine    │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │    Analytics     │
                    └──────────────────┘
```

## Core Components

### 1. Data Loader (`core/data_loader.py`)

**Purpose**: Load and validate market data

**Responsibilities**:
- Parse market data from various formats
- Validate OHLCV data integrity
- Resample to different timeframes
- Handle missing data

**Input**: Dict/DataFrame with OHLCV data
**Output**: Validated pandas DataFrame

### 2. Feature Engineer (`core/feature_engineer.py`)

**Purpose**: Transform raw data into ML features

**Features Generated** (20 total):
- Price-based: returns, momentum, volatility
- Technical: RSI, SMA, trend strength
- Market structure: price position, support/resistance
- Time-based: hour/day encoding, session type
- Volume-based: volume ratio, liquidity

**Input**: DataFrame from DataLoader
**Output**: numpy array (20 features)

### 3. Model Manager (`core/model_manager.py`)

**Purpose**: Manage ML models and inference

**Models Supported**:
- **LightGBM**: Primary model (60% weight)
  - Gradient boosting decision trees
  - Fast inference (<1ms)
  - Excellent for tabular data
  
- **Transformer**: Secondary model (40% weight)
  - Sequence modeling
  - Pattern recognition
  - Slightly slower (~3ms)
  
- **ONNX**: Optional optimized runtime
  - Ultra-fast inference
  - Hardware acceleration
  - Cross-platform

**Ensemble Strategy**: Weighted average of predictions

**Input**: Feature array (20 features)
**Output**: Prediction dict with signal, confidence

### 4. Signal Generator (`core/signal_generator.py`)

**Purpose**: Convert predictions to trading signals

**Logic**:
```
if confidence < min_threshold:
    action = NONE
elif signal > buy_threshold:
    action = BUY
elif signal < sell_threshold:
    action = SELL
else:
    action = NONE
```

**SL/TP Calculation**:
- Based on ATR (Average True Range)
- Adjusted by signal strength
- Risk-reward ratio: 1:1.5 to 1:3

**Input**: Prediction + market data
**Output**: Trading signal with SL/TP

### 5. Risk Engine (`core/risk_engine.py`)

**Purpose**: Assess and manage risk

**Risk Factors**:
1. **Confidence Risk**: 1 - model confidence
2. **Volatility Risk**: Market volatility level
3. **Regime Risk**: Market structure (trending vs ranging)
4. **Time Risk**: News events, session changes

**Position Sizing**:
```
position_size = base_size * (1 - risk_score) * confidence
```

**Validation**:
- Check if risk_score < threshold
- Verify confidence > minimum
- Validate position size limits

**Input**: Signal + market data
**Output**: Risk assessment + position size

### 6. Analytics (`core/analytics.py`)

**Purpose**: Track performance and generate reports

**Metrics Tracked**:
- Prediction accuracy
- Signal generation statistics
- Win rate, profit factor
- Sharpe ratio, max drawdown
- Model performance

**Output Formats**:
- JSON logs
- CSV exports
- Text reports

## Communication Layer

### Bridge Hierarchy

1. **ZeroMQ** (Primary)
   - REQ/REP pattern
   - Ultra-low latency (~0.5ms)
   - Requires `pyzmq` package
   - Port 5555 default

2. **TCP Socket** (Secondary)
   - Raw TCP socket
   - Low latency (~2ms)
   - No dependencies
   - Port 8888 default

3. **File-Based** (Fallback)
   - File system communication
   - Higher latency (~100ms)
   - Always available
   - Directories: `signals/`, `requests/`

### Message Protocol

**Request Format**:
```json
{
  "type": "signal_request",
  "timestamp": "2024-12-03T01:30:00",
  "data": {
    "symbol": "XAUUSD",
    "market_data": { ... }
  }
}
```

**Response Format**:
```json
{
  "type": "signal_response",
  "timestamp": "2024-12-03T01:30:00.123",
  "success": true,
  "data": { ... }
}
```

## Data Flow

### Signal Generation Pipeline

1. **MT5 EA** → Request with market data
2. **Bridge** → Receive and parse message
3. **Data Loader** → Validate market data
4. **Feature Engineer** → Extract 20 features
5. **Model Manager** → Ensemble prediction
6. **Signal Generator** → Generate trading signal
7. **Risk Engine** → Assess risk and validate
8. **Analytics** → Log for tracking
9. **Bridge** → Send response to MT5

**Total Latency**: <5ms (ZeroMQ), <10ms (Socket)

## Configuration System

### Configuration Files

1. **model_config.yaml**: Model parameters, thresholds
2. **features.yaml**: Feature engineering settings
3. **bridge.yaml**: Communication settings

### Runtime Configuration

- Models loaded at startup
- Configuration hot-reloadable (planned)
- Environment-based overrides

## Logging Strategy

### Log Levels

- **DEBUG**: Detailed execution traces
- **INFO**: Normal operations
- **WARNING**: Degraded performance
- **ERROR**: Failures (with fallback)
- **CRITICAL**: System-level failures

### Log Files

- `logs/ai_runtime.log`: Main system log
- `logs/model_decisions.log`: Prediction details
- `logs/error.log`: Error tracking
- `logs/trades.jsonl`: Trade history

## Performance Optimization

### Caching

- Feature caching (30s TTL)
- Model output caching
- Configuration caching

### Async Operations

- Bridge runs in separate thread
- Non-blocking message handling
- Async logging

### Memory Management

- Limited history (10,000 items)
- Periodic cleanup
- Efficient data structures

## Error Handling

### Strategy

1. **Graceful Degradation**: Fall back to simpler methods
2. **Retry Logic**: Automatic retries with backoff
3. **Fallback Models**: Rule-based if ML fails
4. **Bridge Fallback**: Auto-switch to backup bridge

### Error Recovery

- Bridge reconnection
- Model reloading
- State preservation

## Security Considerations

1. **Input Validation**: All inputs sanitized
2. **Resource Limits**: Memory, file size limits
3. **Isolation**: Process-level isolation
4. **Logging**: Audit trail of all operations

## Scalability

### Horizontal Scaling

- Multiple instances with load balancing
- Redis for shared state (planned)
- Distributed model serving (planned)

### Vertical Scaling

- GPU acceleration for models
- Multi-threading for parallel requests
- Optimized data structures

## Testing Strategy

1. **Unit Tests**: Individual component tests
2. **Integration Tests**: End-to-end pipeline
3. **Performance Tests**: Latency benchmarks
4. **Stress Tests**: High-load scenarios

## Deployment

### Development
```bash
python main.py --bridge file
```

### Production
```bash
python main.py --bridge zmq
```

### Docker
```bash
docker-compose up -d
```

## Monitoring

- System health endpoint
- Performance metrics
- Error rate tracking
- Model drift detection (planned)

## Future Enhancements

1. **Model Registry**: Centralized model management
2. **A/B Testing**: Compare model versions
3. **Real-time Training**: Online learning
4. **Multi-Asset Support**: Portfolio optimization
5. **Advanced Risk Models**: VaR, CVaR
6. **Web Dashboard**: Real-time monitoring UI

---

**Architecture designed for production trading at scale**
