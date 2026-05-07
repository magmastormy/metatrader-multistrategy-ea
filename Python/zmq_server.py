from __future__ import annotations

import argparse
import pickle
from datetime import datetime, timezone

import numpy as np
import onnxruntime as ort
import zmq

from doubleadapt_bridge import DoubleAdaptBridge
from maml_ppo_bridge import RegimeAwarePolicy


class SignalServer:
    def __init__(self, patchtst_onnx: str, lgbm_pkl: str, stacker_pkl: str, port: int = 5555) -> None:
        self.sess = ort.InferenceSession(patchtst_onnx)
        self.input_name = self.sess.get_inputs()[0].name
        with open(lgbm_pkl, "rb") as handle:
            self.lgbm = pickle.load(handle)
        with open(stacker_pkl, "rb") as handle:
            self.stacker = pickle.load(handle)
        self.socket = zmq.Context().socket(zmq.REP)
        self.socket.bind(f"tcp://127.0.0.1:{port}")
        self.doubleadapt = DoubleAdaptBridge()
        self.rl_policy = RegimeAwarePolicy()
        print(f"Signal server listening on tcp://127.0.0.1:{port}")

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

    def run(self) -> None:
        while True:
            try:
                message = self.socket.recv_json()
                payload = np.asarray(message["features"], dtype=np.float32)
                mode = message.get("mode", "ensemble")
                if mode == "doubleadapt":
                    self.socket.send_json(self.predict_doubleadapt(payload))
                elif mode == "maml_ppo":
                    self.socket.send_json(self.predict_maml_ppo(payload))
                else:
                    self.socket.send_json(self.predict(payload))
            except KeyboardInterrupt:
                break
            except Exception as exc:  # pragma: no cover
                self.socket.send_json({"error": str(exc)})


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve ensemble predictions over ZeroMQ.")
    parser.add_argument("--patchtst-onnx", required=True)
    parser.add_argument("--lgbm-pkl", required=True)
    parser.add_argument("--stacker-pkl", required=True)
    parser.add_argument("--port", type=int, default=5555)
    args = parser.parse_args()

    SignalServer(
        patchtst_onnx=args.patchtst_onnx,
        lgbm_pkl=args.lgbm_pkl,
        stacker_pkl=args.stacker_pkl,
        port=args.port,
    ).run()


if __name__ == "__main__":
    main()
