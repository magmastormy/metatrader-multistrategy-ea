from __future__ import annotations

import numpy as np
from scipy.spatial.distance import mahalanobis


TURBULENCE_THRESHOLD = 3.5


def compute_turbulence(current_returns: np.ndarray, historical_returns: np.ndarray) -> float:
    mu = historical_returns.mean(axis=0)
    cov_inv = np.linalg.pinv(np.cov(historical_returns.T))
    return float(mahalanobis(current_returns, mu, cov_inv))
