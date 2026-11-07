from __future__ import annotations

import numpy as np
from hmmlearn.hmm import GaussianHMM


class RegimeDetector:
    def __init__(self, n_states: int = 2, lookback: int = 500) -> None:
        self.model = GaussianHMM(
            n_components=n_states,
            covariance_type="full",
            n_iter=200,
            random_state=42,
        )
        self.lookback = lookback
        self.fitted = False
        self.trend_state = 0

    def fit(self, returns: np.ndarray) -> None:
        window = returns.reshape(-1, 1)[-self.lookback :]
        self.model.fit(window)
        stds = np.sqrt(self.model.covars_.reshape(-1))
        self.trend_state = int(np.argmax(stds))
        self.fitted = True

    def predict(self, recent_returns: np.ndarray) -> str:
        if not self.fitted:
            return "unknown"
        state = int(self.model.predict(recent_returns.reshape(-1, 1))[-1])
        return "trend" if state == self.trend_state else "chop"
