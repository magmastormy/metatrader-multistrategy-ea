from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


class RegimeAwarePolicy:
    """
    Minimal regime-aware policy surface for MAML-PPO style experimentation.
    This is not a full RL trainer; it provides the repo-owned inference and
    adaptation contract expected by a sidecar runtime.
    """

    def __init__(self) -> None:
        self.weights = np.array([0.35, 0.15, 0.20, 0.20, 0.10], dtype=np.float64)

    def act(self, observation: np.ndarray) -> dict:
        obs = np.asarray(observation, dtype=np.float64)
        if obs.size < 5:
            obs = np.pad(obs, (0, 5 - obs.size))
        score = float(np.dot(obs[:5], self.weights))
        buy_prob = float(np.clip(0.5 + score, 0.0, 1.0))
        sell_prob = float(np.clip(0.5 - score, 0.0, 1.0))
        hold_prob = float(max(0.0, 1.0 - max(buy_prob, sell_prob)))
        return {
            "buy_prob": buy_prob,
            "sell_prob": sell_prob,
            "hold_prob": hold_prob,
            "policy_score": score,
        }


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a regime-aware MAML-PPO style policy sidecar.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    payload = json.loads(Path(args.input).read_text(encoding="utf-8"))
    observation = np.asarray(payload.get("observation", []), dtype=np.float64)
    result = RegimeAwarePolicy().act(observation)
    Path(args.output).write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
