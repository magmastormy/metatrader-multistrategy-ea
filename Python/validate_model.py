import numpy as np
from itertools import combinations
from typing import List, Tuple

try:
    import onnxruntime as ort
except ImportError:  # pragma: no cover - optional dependency in local builds
    ort = None


def purge_embargo(train_idx: np.ndarray, test_idx: np.ndarray,
                  purge: int = 5, embargo: int = 5) -> np.ndarray:
    t0, t1 = test_idx.min(), test_idx.max()
    mask = (train_idx < t0 - purge) | (train_idx > t1 + embargo)
    return train_idx[mask]


def cpcv_folds(n: int, n_splits: int = 6,
               n_test: int = 2, purge: int = 5, embargo: int = 5
               ) -> List[Tuple[np.ndarray, np.ndarray]]:
    """Combinatorial Purged Cross-Validation fold generator."""
    groups = np.array_split(np.arange(n), n_splits)
    folds = []
    for test_groups in combinations(range(n_splits), n_test):
        test_idx = np.concatenate([groups[i] for i in test_groups])
        train_idx = np.concatenate([groups[i] for i in range(n_splits)
                                    if i not in test_groups])
        train_idx = purge_embargo(train_idx, test_idx, purge, embargo)
        folds.append((train_idx, test_idx))
    return folds


def psr(sharpe_ratios: np.ndarray, sr_ref: float = 0.0) -> float:
    """Probabilistic Sharpe Ratio at confidence level."""
    from scipy.stats import norm

    mu = sharpe_ratios.mean()
    sig = sharpe_ratios.std(ddof=1) + 1e-9
    z = (mu - sr_ref) / sig * np.sqrt(len(sharpe_ratios))
    return float(norm.cdf(z))


def run_cpcv(model_path: str, X: np.ndarray, y: np.ndarray,
             bar_returns: np.ndarray, n_splits: int = 6,
             annualization: float = 252.0) -> dict:
    """
    Run full CPCV evaluation.

    Args:
        model_path:    Path to .onnx model file.
        X:             (N, seq_len, n_features) float32 array.
        y:             (N,) int64 array - labels in {0,1,2}.
        bar_returns:   (N,) float array - actual log returns per bar.
        n_splits:      Number of CPCV splits (default 6).
        annualization: Bars-per-year for Sharpe scaling.

    Returns dict with keys: sharpe_ratios, mean_sr, p10_sr, psr, deploy_gate.
    DEPLOYMENT GATE: p10_sr > 0 is required before live deployment.
    """
    if ort is None:
        raise ImportError("onnxruntime is required for CPCV validation but is not installed.")
    sess = ort.InferenceSession(model_path)
    folds = cpcv_folds(len(X), n_splits=n_splits)
    sharpe = []

    for _tr_idx, te_idx in folds:
        Xte = X[te_idx].astype(np.float32)
        logits = sess.run(None, {"input": Xte})[0]
        preds = logits.argmax(axis=1) - 1
        rets = preds * bar_returns[te_idx]
        sr = rets.mean() / (rets.std() + 1e-9) * np.sqrt(annualization)
        sharpe.append(float(sr))

    sharpe = np.array(sharpe)
    p10 = float(np.percentile(sharpe, 10))
    result = dict(
        sharpe_ratios=sharpe,
        mean_sr=float(sharpe.mean()),
        p10_sr=p10,
        psr=psr(sharpe),
        deploy_gate=(p10 > 0.0),
    )

    print(f"CPCV Results ({len(folds)} folds):")
    print(f"  Sharpe per fold: {sharpe.round(3)}")
    print(f"  Mean SR: {result['mean_sr']:.3f}  |  10th pct SR: {p10:.3f}  |  PSR: {result['psr']:.3f}")
    print(f"  DEPLOYMENT GATE: {'PASS' if result['deploy_gate'] else 'FAIL'}")
    return result
