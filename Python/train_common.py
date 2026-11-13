from __future__ import annotations

import pickle
from pathlib import Path
from typing import Callable, Optional, Tuple

import numpy as np
from scipy.stats import spearmanr

from data_pipeline import PipelineMetadata, build_scaled_dataset_splits


FAMILY_PREFIXES = [
    "crashboom", "volatility", "step", "jump", "dex",
    "multistep", "exponential", "hybrid", "rangebreak",
    "skewstep", "volswitch", "driftswitch", "trek",
    "tactical", "derived", "stablespread", "pairsarbitrage", "spotvolatility",
]

ASSET_CLASS_NAMES = {
    0: "forex",
    1: "metals",
    2: "indices",
    3: "energies",
}

ASSET_CLASS_IDS = {name: fid for fid, name in ASSET_CLASS_NAMES.items()}



def adjust_seq_len_for_family(family_id: int, seq_len: int) -> int:
    """Jump (3) and DEX (4) families use longer sequences."""
    if family_id in (3, 4) and seq_len == 60:
        return 120
    return seq_len


def load_split(
    csv: str,
    seq_len: int = 60,
    k: float = 1.5,
    vert: int = 20,
    family_id: int = -1,
    asset_class: int = -1,
    scaler_output: Optional[str] = None,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, PipelineMetadata]:
    """Load a CSV, build scaled dataset splits, and return flattened train/val/test arrays plus metadata.

    The split/labeling logic itself lives entirely in
    ``data_pipeline.build_scaled_dataset_splits``; this helper only flattens the
    sequence tensors into 2-D feature matrices so gradient-boosting trainers can
    consume them, and returns the shared metadata (sizes, feature count,
    annualization).
    """
    train, val, test, metadata = build_scaled_dataset_splits(
        csv,
        seq_len=seq_len,
        k=k,
        vertical_bars=vert,
        family_id=family_id,
        asset_class=asset_class,
        scaler_output=scaler_output,
    )
    X_tr = train[0].reshape(len(train[0]), -1)
    X_va = val[0].reshape(len(val[0]), -1)
    X_te = test[0].reshape(len(test[0]), -1)
    y_tr, y_va, y_te = train[1], val[1], test[1]
    return X_tr, X_va, X_te, y_tr, y_va, y_te, metadata



def compute_test_ic(preds: np.ndarray, y_te: np.ndarray) -> float:
    """Spearman rank IC of (probability of class 2 minus probability of class 0)
    against the forward returns held in ``y_te``."""
    value, _ = spearmanr(preds[:, 2] - preds[:, 0], y_te)
    return float(value)


def save_pickle(model, output: str) -> str:
    """Pickle ``model`` to ``output`` and return the path used."""
    with open(output, "wb") as handle:
        pickle.dump(model, handle)
    return output


def export_onnx(
    converter: str,
    model,
    output: str,
    n_features: int,
    model_name: str,
) -> None:
    """Best-effort ONNX export via onnxmltools using a model-specific converter.

    ``converter`` is one of ``"xgboost"``, ``"lightgbm"`` or ``"catboost"`` and
    selects ``onnxmltools.convert_<converter>``.
    """
    try:
        import onnxmltools
        from onnxmltools.convert.common.data_types import FloatTensorType

        convert_fn = getattr(onnxmltools, f"convert_{converter}")
        onnx_model = convert_fn(
            model,
            name=model_name,
            initial_types=[("float_input", FloatTensorType([None, n_features]))],
            target_opset=12,
        )
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        onnxmltools.utils.save_model(onnx_model, output)
        print(f"onnx={output}")
    except ImportError:
        print(f"onnxmltools not installed; skipped ONNX export for {model_name}")
