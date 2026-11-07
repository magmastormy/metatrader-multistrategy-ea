from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class DoubleAdaptState:
    feature_mean: np.ndarray
    feature_std: np.ndarray
    alpha: float = 0.05


class DoubleAdaptBridge:
    """
    Lightweight production-side approximation of a DoubleAdapt bridge.
    It maintains a rolling distribution adapter and exposes adapted features
    for downstream models or sidecars.
    """

    def __init__(self, n_features: int = 57, alpha: float = 0.05) -> None:
        self.state = DoubleAdaptState(
            feature_mean=np.zeros(n_features, dtype=np.float64),
            feature_std=np.ones(n_features, dtype=np.float64),
            alpha=alpha,
        )

    def update_distribution(self, features: np.ndarray) -> None:
        x = np.asarray(features, dtype=np.float64)
        if x.ndim == 2:
            mean = x.mean(axis=0)
            std = x.std(axis=0, ddof=0)
        else:
            mean = x
            std = np.ones_like(mean)
        self.state.feature_mean = (1.0 - self.state.alpha) * self.state.feature_mean + self.state.alpha * mean
        self.state.feature_std = (1.0 - self.state.alpha) * self.state.feature_std + self.state.alpha * np.maximum(std, 1e-6)

    def adapt(self, features: np.ndarray) -> np.ndarray:
        x = np.asarray(features, dtype=np.float64)
        return (x - self.state.feature_mean) / np.maximum(self.state.feature_std, 1e-6)

    def snapshot(self) -> dict:
        return {
            "alpha": self.state.alpha,
            "feature_mean": self.state.feature_mean.tolist(),
            "feature_std": self.state.feature_std.tolist(),
        }

    def save(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(self.snapshot(), indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Adapt live MT5 features using a DoubleAdapt-style distribution bridge.")
    parser.add_argument("--input", required=True, help="JSON file containing {'features': [[...], ...]} or {'features': [...]} .")
    parser.add_argument("--output", required=True, help="Output JSON file for adapted features.")
    parser.add_argument("--state-output", default=None, help="Optional output JSON state snapshot.")
    args = parser.parse_args()

    payload = json.loads(Path(args.input).read_text(encoding="utf-8"))
    bridge = DoubleAdaptBridge()
    features = np.asarray(payload["features"], dtype=np.float64)
    bridge.update_distribution(features)
    adapted = bridge.adapt(features)

    Path(args.output).write_text(json.dumps({"adapted_features": adapted.tolist()}, indent=2), encoding="utf-8")
    if args.state_output:
        bridge.save(args.state_output)


if __name__ == "__main__":
    main()
