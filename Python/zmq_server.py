from __future__ import annotations

import argparse
import pickle
import threading
from datetime import datetime, timezone
from typing import Any

import numpy as np
import onnxruntime as ort
import zmq

# Import HTTP server dependencies
try:
    from fastapi import FastAPI, Request, HTTPException
    from fastapi.responses import JSONResponse
    import uvicorn
    HAS_HTTP = True
except ImportError:
    HAS_HTTP = False
    print("Warning: FastAPI/uvicorn not installed. HTTP server will be disabled.")

from doubleadapt_bridge import DoubleAdaptBridge
from maml_ppo_bridge import RegimeAwarePolicy


class SignalServer:
    def __init__(self, patchtst_onnx: str, lgbm_pkl: str, stacker_pkl: str, 
                 zmq_port: int = 5555, http_port: int = 8000, 
                 enable_http: bool = True, heartbeat_timeout: int = 30) -> None:
        self.sess = ort.InferenceSession(patchtst_onnx)
        self.input_name = self.sess.get_inputs()[0].name
        with open(lgbm_pkl, "rb") as handle:
            self.lgbm = pickle.load(handle)
        with open(stacker_pkl, "rb") as handle:
            self.stacker = pickle.load(handle)
        
        # ZMQ setup
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REP)
        self.socket.bind(f"tcp://127.0.0.1:{zmq_port}")
        self.zmq_port = zmq_port
        self.heartbeat_timeout = heartbeat_timeout
        self.last_heartbeat = datetime.now(timezone.utc)
        
        self.doubleadapt = DoubleAdaptBridge()
        self.rl_policy = RegimeAwarePolicy()
        
        # HTTP server setup
        self.enable_http = enable_http and HAS_HTTP
        self.http_port = http_port
        self.http_thread = None
        self.app = None
        if self.enable_http:
            self._setup_http_server()
        
        print(f"Signal server initialized:")
        print(f"  ZMQ endpoint: tcp://127.0.0.1:{self.zmq_port}")
        if self.enable_http:
            print(f"  HTTP endpoint: http://127.0.0.1:{self.http_port}")
        print(f"  Heartbeat timeout: {self.heartbeat_timeout}s")

    def _setup_http_server(self):
        self.app = FastAPI(title="Python Bridge Server", version="1.0.0")
        
        @self.app.post("/predict")
        async def predict_endpoint(request: Request):
            try:
                data = await request.json()
                features = np.asarray(data["features"], dtype=np.float32)
                mode = data.get("mode", "ensemble")
                result = self._process_request(features, mode)
                return JSONResponse(content=result)
            except Exception as exc:
                raise HTTPException(status_code=500, detail=str(exc))
        
        @self.app.get("/health")
        async def health_check():
            return JSONResponse(content={
                "status": "healthy",
                "ts": datetime.now(timezone.utc).isoformat(),
                "last_heartbeat": self.last_heartbeat.isoformat()
            })
        
        @self.app.get("/heartbeat")
        async def heartbeat():
            self.last_heartbeat = datetime.now(timezone.utc)
            return JSONResponse(content={
                "status": "ok",
                "ts": self.last_heartbeat.isoformat()
            })
        
        @self.app.get("/version")
        async def version():
            return JSONResponse(content={
                "version": "1.0.0",
                "major": 1,
                "minor": 0,
                "patch": 0,
                "ts": datetime.now(timezone.utc).isoformat()
            })

    def _process_request(self, features_flat: np.ndarray, mode: str = "ensemble") -> dict:
        try:
            if mode == "doubleadapt":
                return self.predict_doubleadapt(features_flat)
            elif mode == "maml_ppo":
                return self.predict_maml_ppo(features_flat)
            else:
                return self.predict(features_flat)
        except Exception as exc:
            return {"error": str(exc), "ts": datetime.now(timezone.utc).isoformat()}

    def predict(self, features_flat: np.ndarray) -> dict:
        seq, feat = 60, 57
        X_seq = features_flat.reshape(1, seq, feat).astype(np.float32)
        X_flat = features_flat.reshape(1, -1).astype(np.float32)
        logits = self.sess.run(None, {self.input_name: X_seq})[0]
        exp = np.exp(logits - logits.max(axis=1, keepdims=True))
        onnx_probs = exp / exp.sum(axis=1, keepdims=True)
        lgbm_probs = self.lgbm.predict(X_flat)
        meta = self.stacker["scaler"].transform(np.hstack([onnx_probs, lgbm_probs]))
        stack_signal = float(self.stacker["ridge"].predict(meta)[0])
        return {
            "buy_prob": float(onnx_probs[0, 2]),
            "sell_prob": float(onnx_probs[0, 0]),
            "hold_prob": float(onnx_probs[0, 1]),
            "lgbm_buy": float(lgbm_probs[0, 2]),
            "lgbm_sell": float(lgbm_probs[0, 0]),
            "stacker_signal": stack_signal,
            "ts": datetime.now(timezone.utc).isoformat(),
        }

    def predict_doubleadapt(self, features_flat: np.ndarray) -> dict:
        self.doubleadapt.update_distribution(features_flat.reshape(1, -1))
        adapted = self.doubleadapt.adapt(features_flat.reshape(1, -1))
        return {
            "adapted_features": adapted.reshape(-1).tolist(),
            "ts": datetime.now(timezone.utc).isoformat(),
            "mode": "doubleadapt",
        }

    def predict_maml_ppo(self, features_flat: np.ndarray) -> dict:
        result = self.rl_policy.act(features_flat[:5])
        result["ts"] = datetime.now(timezone.utc).isoformat()
        result["mode"] = "maml_ppo"
        return result

    def _run_zmq(self):
        poller = zmq.Poller()
        poller.register(self.socket, zmq.POLLIN)
        
        print(f"ZMQ server listening on tcp://127.0.0.1:{self.zmq_port}")
        
        while True:
            try:
                # Wait for messages with timeout for heartbeat checking
                events = dict(poller.poll(timeout=5000))  # 5 second poll timeout
                
                if self.socket in events:
                    message = self.socket.recv_json()
                    self.last_heartbeat = datetime.now(timezone.utc)
                    
                    # Handle heartbeat
                    if message.get("type") == "heartbeat":
                        self.socket.send_json({
                            "status": "ok",
                            "ts": datetime.now(timezone.utc).isoformat()
                        })
                        continue
                    
                    payload = np.asarray(message["features"], dtype=np.float32)
                    mode = message.get("mode", "ensemble")
                    result = self._process_request(payload, mode)
                    self.socket.send_json(result)
                
            except KeyboardInterrupt:
                print("\nZMQ server shutting down...")
                break
            except Exception as exc:
                print(f"ZMQ error: {exc}")
                try:
                    self.socket.send_json({"error": str(exc)})
                except:
                    pass

    def _run_http(self):
        if self.app and HAS_HTTP:
            print(f"HTTP server listening on http://127.0.0.1:{self.http_port}")
            uvicorn.run(
                self.app, 
                host="127.0.0.1", 
                port=self.http_port, 
                log_level="info",
                limit_concurrency=10
            )

    def run(self) -> None:
        # Start HTTP server in separate thread if enabled
        if self.enable_http:
            self.http_thread = threading.Thread(target=self._run_http, daemon=True)
            self.http_thread.start()
        
        # Run ZMQ server in main thread
        self._run_zmq()

    def shutdown(self):
        print("Shutting down server...")
        try:
            self.socket.close()
        except:
            pass
        try:
            self.context.term()
        except:
            pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve ensemble predictions over ZeroMQ and/or HTTP.")
    parser.add_argument("--patchtst-onnx", required=True)
    parser.add_argument("--lgbm-pkl", required=True)
    parser.add_argument("--stacker-pkl", required=True)
    parser.add_argument("--zmq-port", type=int, default=5555)
    parser.add_argument("--http-port", type=int, default=8000)
    parser.add_argument("--disable-http", action="store_true")
    parser.add_argument("--heartbeat-timeout", type=int, default=30)
    args = parser.parse_args()

    server = SignalServer(
        patchtst_onnx=args.patchtst_onnx,
        lgbm_pkl=args.lgbm_pkl,
        stacker_pkl=args.stacker_pkl,
        zmq_port=args.zmq_port,
        http_port=args.http_port,
        enable_http=not args.disable_http,
        heartbeat_timeout=args.heartbeat_timeout
    )
    
    try:
        server.run()
    except KeyboardInterrupt:
        print("\nReceived shutdown signal")
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
