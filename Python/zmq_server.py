from __future__ import annotations

import argparse
import pickle
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

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
from data_pipeline import get_feature_count, BASE_FEATURE_COUNT, DERIV_FAMILY_COUNT

# Family ID mapping aligned with MQL5 ENUM_DERIV_FAMILY
FAMILY_IDS = {
    "CRASH": 0, "BOOM": 0,
    "VOLATILITY": 1, "SFX VOL": 1, "FX VOL": 1,
    "STEP": 2,
    "JUMP": 3,
    "DEX": 4,
    "MULTISTEP": 5, "MULTI STEP": 5,
    "EXPONENTIAL": 6, "GROWTH": 6,
    "HYBRID": 7,
    "RANGE BREAK": 8,
    "SKEW STEP": 9,
    "VOL SWITCH": 10,
    "DRIFT SWITCH": 11,
    "TREK": 12,
    "TACTICAL": 13,
    "DERIVED": 14,
    "STABLE SPREAD": 15,
    "PAIRS ARBITRAGE": 16,
    "SPOT VOLATILITY": 17,
}

FAMILY_PREFIXES = [
    "crashboom", "volatility", "step", "jump", "dex",
    "multistep", "exponential", "hybrid", "rangebreak",
    "skewstep", "volswitch", "driftswitch", "trek",
    "tactical", "derived", "stablespread", "pairsarbitrage", "spotvolatility",
]

FAMILY_NAMES = [
    "CrashBoom", "Volatility", "Step", "Jump", "DEX",
    "MultiStep", "Exponential", "Hybrid", "RangeBreak",
    "SkewStep", "VolSwitch", "DriftSwitch", "Trek",
    "Tactical", "Derived", "StableSpread", "PairsArbitrage", "SpotVolatility",
]

# Batch 103: Asset class mapping aligned with MQL5 ENUM_ASSET_CLASS
ASSET_CLASS_NAMES = {
    0: "forex",
    1: "metals",
    2: "indices",
    3: "energies",
    4: "deriv_crashboom",
    5: "deriv_volatility",
    6: "deriv_step",
    7: "deriv_jump",
    8: "deriv_dex",
    9: "universal",
}

ASSET_CLASS_FEATURE_COUNTS = {
    0: 60,   # Forex: 57 + 3
    1: 61,   # Metals: 57 + 4
    2: 61,   # Indices: 57 + 4
    3: 60,   # Energies: 57 + 3
    4: 70,   # Deriv CrashBoom
    5: 70,   # Deriv Volatility
    6: 70,   # Deriv Step
    7: 70,   # Deriv Jump
    8: 70,   # Deriv DEX
    9: 57,   # Universal
}


class SignalServer:
    def __init__(self, patchtst_onnx: str = "", lgbm_pkl: str = "", stacker_pkl: str = "",
                 model_dir: str = "",
                 zmq_port: int = 5555, http_port: int = 8000,
                 enable_http: bool = True, heartbeat_timeout: int = 30) -> None:
        # Universal model (backward compatible)
        self.sess: Optional[ort.InferenceSession] = None
        self.input_name: str = ""
        self.lgbm: Any = None
        self.stacker: Any = None
        self._has_universal = False

        if patchtst_onnx and lgbm_pkl and stacker_pkl:
            self.sess = ort.InferenceSession(patchtst_onnx)
            self.input_name = self.sess.get_inputs()[0].name
            with open(lgbm_pkl, "rb") as handle:
                self.lgbm = pickle.load(handle)
            with open(stacker_pkl, "rb") as handle:
                self.stacker = pickle.load(handle)
            self._has_universal = True

        # Family-specific models
        self.family_models: Dict[int, dict] = {}
        self.model_dir = Path(model_dir) if model_dir else None

        if self.model_dir and self.model_dir.is_dir():
            for family_id in range(DERIV_FAMILY_COUNT):
                loaded = self._load_family_models(family_id)
                if loaded:
                    self.family_models[family_id] = loaded

        # Batch 103: Asset-class-specific models (non-Deriv)
        self.asset_class_models: Dict[int, dict] = {}
        if self.model_dir and self.model_dir.is_dir():
            for ac_id in range(4):  # 0=Forex, 1=Metals, 2=Indices, 3=Energies
                loaded = self._load_asset_class_models(ac_id)
                if loaded:
                    self.asset_class_models[ac_id] = loaded

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
        if self._has_universal:
            print(f"  Universal model: loaded")
        if self.family_models:
            print(f"  Family models: {len(self.family_models)} families loaded")
            for fid, models in self.family_models.items():
                print(f"    Family {fid} ({FAMILY_NAMES[fid]}): {list(models.keys())}")
        if self.asset_class_models:
            print(f"  Asset class models: {len(self.asset_class_models)} classes loaded")
            for ac_id, models in self.asset_class_models.items():
                print(f"    Asset class {ac_id} ({ASSET_CLASS_NAMES[ac_id]}): {list(models.keys())}")
        print(f"  Heartbeat timeout: {self.heartbeat_timeout}s")

    def _load_family_models(self, family_id: int) -> dict:
        """Load ONNX + GBDT models for a specific Deriv family."""
        if not self.model_dir:
            return {}
        prefix = FAMILY_PREFIXES[family_id]
        models: dict = {}

        onnx_path = self.model_dir / f"{prefix}_patchtst.onnx"
        if onnx_path.exists():
            models["onnx"] = ort.InferenceSession(str(onnx_path))
            models["onnx_input"] = models["onnx"].get_inputs()[0].name

        for gbdt_type in ["catboost", "xgboost", "lgbm"]:
            gbdt_path = self.model_dir / f"{prefix}_{gbdt_type}.pkl"
            if gbdt_path.exists():
                with open(gbdt_path, "rb") as f:
                    models[gbdt_type] = pickle.load(f)

        stacker_path = self.model_dir / f"{prefix}_stacker.pkl"
        if stacker_path.exists():
            with open(stacker_path, "rb") as f:
                models["stacker"] = pickle.load(f)

        return models

    def _load_asset_class_models(self, asset_class: int) -> dict:
        """Load models for a non-Deriv asset class (forex, metals, indices, energies)."""
        if not self.model_dir:
            return {}
        family_name = ASSET_CLASS_NAMES.get(asset_class, "universal")
        models: dict = {}

        onnx_path = self.model_dir / family_name / "model.onnx"
        if onnx_path.exists():
            models["onnx"] = ort.InferenceSession(str(onnx_path))
            models["onnx_input"] = models["onnx"].get_inputs()[0].name

        for gbdt_type in ["catboost", "xgboost", "lgbm"]:
            gbdt_path = self.model_dir / family_name / f"{gbdt_type}.pkl"
            if gbdt_path.exists():
                with open(gbdt_path, "rb") as f:
                    models[gbdt_type] = pickle.load(f)

        stacker_path = self.model_dir / family_name / "stacker.pkl"
        if stacker_path.exists():
            with open(stacker_path, "rb") as f:
                models["stacker"] = pickle.load(f)

        return models

    @staticmethod
    def _detect_family_from_symbol(symbol: str) -> int:
        """Extract family ID from symbol name (sent by MQL5)."""
        sym_upper = symbol.upper()
        # Sort by key length descending so longer matches take priority
        for key, fid in sorted(FAMILY_IDS.items(), key=lambda x: -len(x[0])):
            if key in sym_upper:
                return fid
        return -1

    def _setup_http_server(self):
        self.app = FastAPI(title="Python Bridge Server", version="1.1.0")

        @self.app.post("/predict")
        async def predict_endpoint(request: Request):
            try:
                data = await request.json()
                features = np.asarray(data["features"], dtype=np.float32)
                mode = data.get("mode", "ensemble")
                family_id = data.get("family_id", -1)
                symbol = data.get("symbol", "")
                asset_class = data.get("asset_class", -1)
                result = self._process_request(features, mode, family_id=family_id, symbol=symbol, asset_class=asset_class)
                return JSONResponse(content=result)
            except Exception as exc:
                raise HTTPException(status_code=500, detail=str(exc))

        @self.app.get("/health")
        async def health_check():
            return JSONResponse(content={
                "status": "healthy",
                "ts": datetime.now(timezone.utc).isoformat(),
                "last_heartbeat": self.last_heartbeat.isoformat(),
                "families_loaded": len(self.family_models),
                "asset_classes_loaded": len(self.asset_class_models),
                "universal_loaded": self._has_universal,
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
                "version": "1.1.0",
                "major": 1,
                "minor": 1,
                "patch": 0,
                "ts": datetime.now(timezone.utc).isoformat()
            })

        @self.app.get("/families")
        async def list_families():
            families = {}
            for fid in range(DERIV_FAMILY_COUNT):
                models = self.family_models.get(fid, {})
                families[str(fid)] = {
                    "name": FAMILY_NAMES[fid],
                    "prefix": FAMILY_PREFIXES[fid],
                    "models_loaded": list(models.keys()),
                    "feature_count": get_feature_count(fid),
                }
            return JSONResponse(content={
                "families": families,
                "universal_loaded": self._has_universal,
                "ts": datetime.now(timezone.utc).isoformat(),
            })

        @self.app.get("/family/{family_id}")
        async def family_status(family_id: int):
            if not 0 <= family_id < DERIV_FAMILY_COUNT:
                raise HTTPException(status_code=404, detail=f"Family ID {family_id} not found")
            models = self.family_models.get(family_id, {})
            return JSONResponse(content={
                "family_id": family_id,
                "name": FAMILY_NAMES[family_id],
                "prefix": FAMILY_PREFIXES[family_id],
                "models_loaded": list(models.keys()),
                "feature_count": get_feature_count(family_id),
                "ts": datetime.now(timezone.utc).isoformat(),
            })

    def _process_request(self, features_flat: np.ndarray, mode: str = "ensemble",
                         family_id: int = -1, symbol: str = "", asset_class: int = -1) -> dict:
        try:
            # Batch 103: Route by asset class for non-Deriv instruments
            if 0 <= asset_class <= 3 and asset_class in self.asset_class_models:
                return self._predict_asset_class(features_flat, asset_class, mode)

            # Family detection from symbol if family_id not provided
            if family_id == -1 and symbol:
                family_id = self._detect_family_from_symbol(symbol)

            # Route to family-specific model if available
            if family_id >= 0 and family_id in self.family_models:
                return self._predict_family(features_flat, family_id, mode)

            # Fallback to universal model
            if mode == "doubleadapt":
                return self.predict_doubleadapt(features_flat)
            elif mode == "maml_ppo":
                return self.predict_maml_ppo(features_flat)
            else:
                return self.predict(features_flat)
        except Exception as exc:
            return {"error": str(exc), "ts": datetime.now(timezone.utc).isoformat()}

    def predict(self, features_flat: np.ndarray) -> dict:
        seq, feat = 60, BASE_FEATURE_COUNT
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

    def _predict_family(self, features_flat: np.ndarray, family_id: int, mode: str) -> dict:
        """Family-specific prediction with Deriv feature expansion."""
        models = self.family_models[family_id]

        # Determine sequence length and feature count for this family
        seq_len = 120 if family_id in (3, 4) else 60  # Jump/DEX use 120
        feat_count = get_feature_count(family_id)  # 83 for Deriv families

        result: dict = {
            "family_id": family_id,
            "family_name": FAMILY_NAMES[family_id],
            "ts": datetime.now(timezone.utc).isoformat(),
        }

        # ONNX predictions if available
        if "onnx" in models:
            X_seq = features_flat.reshape(1, seq_len, feat_count).astype(np.float32)
            logits = models["onnx"].run(None, {models["onnx_input"]: X_seq})[0]
            exp = np.exp(logits - logits.max(axis=1, keepdims=True))
            onnx_probs = exp / exp.sum(axis=1, keepdims=True)
            result["onnx_buy"] = float(onnx_probs[0, 2])
            result["onnx_sell"] = float(onnx_probs[0, 0])
            result["onnx_hold"] = float(onnx_probs[0, 1])
            # Also set top-level buy/sell/hold from ONNX
            result["buy_prob"] = float(onnx_probs[0, 2])
            result["sell_prob"] = float(onnx_probs[0, 0])
            result["hold_prob"] = float(onnx_probs[0, 1])

        # GBDT predictions if available
        X_flat = features_flat.reshape(1, -1).astype(np.float32)
        for gbdt_name in ["catboost", "xgboost", "lgbm"]:
            if gbdt_name in models:
                try:
                    probs = models[gbdt_name].predict_proba(X_flat)
                    result[f"{gbdt_name}_buy"] = float(probs[0, 2])
                    result[f"{gbdt_name}_sell"] = float(probs[0, 0])
                except Exception:
                    # Fallback: try predict() for LightGBM which returns probabilities directly
                    probs = models[gbdt_name].predict(X_flat)
                    if probs.ndim == 1:
                        result[f"{gbdt_name}_buy"] = float(probs[0])
                        result[f"{gbdt_name}_sell"] = 1.0 - float(probs[0])
                    else:
                        result[f"{gbdt_name}_buy"] = float(probs[0, 2])
                        result[f"{gbdt_name}_sell"] = float(probs[0, 0])

        # Family-specific stacking if available
        if "stacker" in models:
            stacker = models["stacker"]
            n_base = stacker.get("n_base_models", 2)
            meta_parts = []
            # ONNX probs
            if "onnx_buy" in result:
                meta_parts.extend([
                    result.get("onnx_buy", 0.5),
                    result.get("onnx_sell", 0.5),
                    result.get("onnx_hold", 0.5),
                ])
            else:
                meta_parts.extend([0.5, 0.5, 0.5])
            # LGBM probs
            meta_parts.extend([
                result.get("lgbm_buy", 0.5),
                result.get("lgbm_sell", 0.5),
                1.0 - result.get("lgbm_buy", 0.5) - result.get("lgbm_sell", 0.5),
            ])
            # CatBoost probs
            if "catboost_buy" in result:
                meta_parts.extend([
                    result.get("catboost_buy", 0.5),
                    result.get("catboost_sell", 0.5),
                    1.0 - result.get("catboost_buy", 0.5) - result.get("catboost_sell", 0.5),
                ])
            # XGBoost probs
            if "xgboost_buy" in result:
                meta_parts.extend([
                    result.get("xgboost_buy", 0.5),
                    result.get("xgboost_sell", 0.5),
                    1.0 - result.get("xgboost_buy", 0.5) - result.get("xgboost_sell", 0.5),
                ])
            meta_feats = np.array([meta_parts]).reshape(1, -1)
            scaled = stacker["scaler"].transform(meta_feats)
            result["stacker_signal"] = float(stacker["ridge"].predict(scaled)[0])

        return result

    def _predict_asset_class(self, features_flat: np.ndarray, asset_class: int, mode: str) -> dict:
        """Asset-class-specific prediction for non-Deriv instruments (Batch 103)."""
        models = self.asset_class_models[asset_class]
        feat_count = ASSET_CLASS_FEATURE_COUNTS.get(asset_class, 57)
        seq_len = 60  # Standard sequence length for non-Deriv

        result: dict = {
            "asset_class": asset_class,
            "asset_class_name": ASSET_CLASS_NAMES.get(asset_class, "unknown"),
            "ts": datetime.now(timezone.utc).isoformat(),
        }

        # ONNX predictions if available
        if "onnx" in models:
            X_seq = features_flat.reshape(1, seq_len, feat_count).astype(np.float32)
            logits = models["onnx"].run(None, {models["onnx_input"]: X_seq})[0]
            exp = np.exp(logits - logits.max(axis=1, keepdims=True))
            onnx_probs = exp / exp.sum(axis=1, keepdims=True)
            result["onnx_buy"] = float(onnx_probs[0, 2])
            result["onnx_sell"] = float(onnx_probs[0, 0])
            result["buy_prob"] = float(onnx_probs[0, 2])
            result["sell_prob"] = float(onnx_probs[0, 0])
            result["hold_prob"] = float(onnx_probs[0, 1])

        # GBDT predictions
        X_flat = features_flat.reshape(1, -1).astype(np.float32)
        for gbdt_name in ["lgbm", "catboost", "xgboost"]:
            if gbdt_name in models:
                try:
                    probs = models[gbdt_name].predict_proba(X_flat)
                    result[f"{gbdt_name}_buy"] = float(probs[0, 2])
                    result[f"{gbdt_name}_sell"] = float(probs[0, 0])
                except Exception:
                    probs = models[gbdt_name].predict(X_flat)
                    if probs.ndim == 1:
                        result[f"{gbdt_name}_buy"] = float(probs[0])
                        result[f"{gbdt_name}_sell"] = 1.0 - float(probs[0])
                    else:
                        result[f"{gbdt_name}_buy"] = float(probs[0, 2])
                        result[f"{gbdt_name}_sell"] = float(probs[0, 0])

        # Stacking if available
        if "stacker" in models:
            stacker = models["stacker"]
            meta_parts = []
            if "onnx_buy" in result:
                meta_parts.extend([result.get("onnx_buy", 0.5), result.get("onnx_sell", 0.5), result.get("onnx_hold", 0.5)])
            else:
                meta_parts.extend([0.5, 0.5, 0.5])
            for gbdt in ["lgbm", "catboost", "xgboost"]:
                if f"{gbdt}_buy" in result:
                    meta_parts.extend([result[f"{gbdt}_buy"], result[f"{gbdt}_sell"], 1.0 - result[f"{gbdt}_buy"] - result[f"{gbdt}_sell"]])
            meta_feats = np.array([meta_parts]).reshape(1, -1)
            scaled = stacker["scaler"].transform(meta_feats)
            result["stacker_signal"] = float(stacker["ridge"].predict(scaled)[0])

        return result

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
                events = dict(poller.poll(timeout=5000))

                if self.socket in events:
                    message = self.socket.recv_json()
                    self.last_heartbeat = datetime.now(timezone.utc)

                    if message.get("type") == "heartbeat":
                        self.socket.send_json({
                            "status": "ok",
                            "ts": datetime.now(timezone.utc).isoformat()
                        })
                        continue

                    payload = np.asarray(message["features"], dtype=np.float32)
                    mode = message.get("mode", "ensemble")
                    family_id = message.get("family_id", -1)
                    symbol = message.get("symbol", "")
                    asset_class = message.get("asset_class", -1)
                    result = self._process_request(payload, mode, family_id=family_id, symbol=symbol, asset_class=asset_class)
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
        if self.enable_http:
            self.http_thread = threading.Thread(target=self._run_http, daemon=True)
            self.http_thread.start()
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
    # Universal model args (backward compatible)
    parser.add_argument("--patchtst-onnx", default="")
    parser.add_argument("--lgbm-pkl", default="")
    parser.add_argument("--stacker-pkl", default="")
    # Family-aware model directory
    parser.add_argument("--model-dir", default="",
                        help="Directory containing family-specific models ({prefix}_*.onnx/pkl)")
    parser.add_argument("--zmq-port", type=int, default=5555)
    parser.add_argument("--http-port", type=int, default=8000)
    parser.add_argument("--disable-http", action="store_true")
    parser.add_argument("--heartbeat-timeout", type=int, default=30)
    args = parser.parse_args()

    if not args.model_dir and not (args.patchtst_onnx and args.lgbm_pkl and args.stacker_pkl):
        parser.error("Either --model-dir or all of --patchtst-onnx, --lgbm-pkl, --stacker-pkl are required")

    server = SignalServer(
        patchtst_onnx=args.patchtst_onnx,
        lgbm_pkl=args.lgbm_pkl,
        stacker_pkl=args.stacker_pkl,
        model_dir=args.model_dir,
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
