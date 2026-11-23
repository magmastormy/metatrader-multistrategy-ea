from __future__ import annotations

import json
import pickle
from pathlib import Path
from typing import Callable, Optional, Sequence, Tuple

import numpy as np
import pandas as pd
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
    annualization). Timestamps are dropped; use ``load_split_full`` when the
    caller needs them (e.g. to persist a model's training range)."""
    X_tr, X_va, X_te, y_tr, y_va, y_te, _ts_tr, _ts_va, _ts_te, metadata = load_split_full(
        csv, seq_len=seq_len, k=k, vert=vert, family_id=family_id,
        asset_class=asset_class, scaler_output=scaler_output,
    )
    return X_tr, X_va, X_te, y_tr, y_va, y_te, metadata


def load_split_full(
    csv: str,
    seq_len: int = 60,
    k: float = 1.5,
    vert: int = 20,
    family_id: int = -1,
    asset_class: int = -1,
    scaler_output: Optional[str] = None,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray,
           np.ndarray, np.ndarray, np.ndarray, PipelineMetadata]:
    """Like ``load_split`` but also returns the per-split label timestamps
    (``ts_tr``, ``ts_va``, ``ts_te``) so trainers can persist each model's
    training range for stacker decontamination."""
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
    return (X_tr, X_va, X_te, train[1], val[1], test[1],
            train[4], val[4], test[4], metadata)


def _meta_path(model_path: str) -> Path:
    return Path(str(model_path) + ".trainmeta.json")


def save_train_meta(
    model_path: str,
    ts_train: np.ndarray,
    ts_val: Optional[np.ndarray] = None,
    **extra,
) -> str:
    """Write ``<model>.trainmeta.json`` recording the time range each base
    model was fit on, so ``stacker_fit_indices`` can exclude in-sample rows
    when fitting the meta-learner."""
    ts_train = np.asarray(ts_train)
    meta = {
        "model": Path(str(model_path)).name,
        "n_train": int(len(ts_train)),
        "train_start": str(pd.Timestamp(ts_train.min())),
        "train_end": str(pd.Timestamp(ts_train.max())),
    }
    if ts_val is not None and len(ts_val):
        ts_val = np.asarray(ts_val)
        meta["n_val"] = int(len(ts_val))
        meta["val_start"] = str(pd.Timestamp(ts_val.min()))
        meta["val_end"] = str(pd.Timestamp(ts_val.max()))
    meta.update({k: v for k, v in extra.items() if v is not None})
    out = _meta_path(model_path)
    out.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return str(out)


def load_train_meta(model_path: str) -> Optional[dict]:
    path = _meta_path(model_path)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _ts_to_ns(ts: np.ndarray) -> np.ndarray:
    return (
        np.asarray(pd.to_datetime(pd.Series(ts)).astype("int64") // 10**9, dtype=np.int64)
        * 10**9
    )


def stacker_fit_indices(
    ts_all: np.ndarray,
    n_train_rows: int,
    model_paths: Sequence[str],
) -> np.ndarray:
    """Row indices of ``X_all`` safe for fitting the ridge meta-learner.

    Baseline is the validation region (``>= n_train_rows``): every base model
    trained on the train split, so train-row predictions are in-sample. Each
    documented ``.trainmeta.json`` ``train_end`` then tightens the mask by
    timestamp, which matters when base models were fit on different splits
    (different ``seq_len``/``family_id``/``asset_class`` produce different row
    sets over the same bars). Models without metadata are assumed to share
    this split - the val-only bound already excludes their train rows.
    """
    ts_ns = _ts_to_ns(np.asarray(ts_all))
    mask = np.zeros(len(ts_all), dtype=bool)
    mask[n_train_rows:] = True

    missing: list = []
    cutoff: Optional[int] = None
    for path in model_paths:
        if not path:
            continue
        meta = load_train_meta(path)
        end = meta.get("train_end") if meta else None
        if end is None:
            missing.append(Path(str(path)).name)
            continue
        end_ns = np.datetime64(end).astype("datetime64[ns]").astype(np.int64)
        cutoff = int(end_ns) if cutoff is None else max(cutoff, int(end_ns))

    if cutoff is not None:
        mask &= ts_ns > cutoff
    idx = np.flatnonzero(mask)
    if len(idx) == 0:
        idx = np.arange(n_train_rows, len(ts_all))
        print("stacker: metadata-clean mask is empty; fell back to val rows only")
    if missing:
        print(f"stacker: no .trainmeta.json for {missing}; assumed same-split")
    return idx



def report_trained_model(model, X_te: np.ndarray, y_te: np.ndarray,
                         pkl_output: str, label: str,
                         metadata: Optional[PipelineMetadata] = None) -> float:
    """Predict on the test split, score IC, pickle the model and print the standard
    ``trained=`` line shared by every trainer script. Returns the test IC."""
    preds = model.predict_proba(X_te) if hasattr(model, "predict_proba") else model.predict(X_te)
    ic = compute_test_ic(preds, y_te)
    save_pickle(model, pkl_output)
    samples = ""
    if metadata is not None:
        samples = f" samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size}"
    print(f"trained={label}{samples} test_ic={float(ic):.4f} pkl={pkl_output}")
    return ic


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


def get_onnx_probs(path: str, X: np.ndarray) -> np.ndarray:
    """Class probabilities from an ONNX sequence model."""
    import onnxruntime as ort
    from scipy.special import softmax

    sess = ort.InferenceSession(path)
    name = sess.get_inputs()[0].name
    logits = sess.run(None, {name: X.astype(np.float32)})[0]
    return softmax(logits, axis=1)


def train_oof_stacker(
    csv: str,
    seq_len: int = 60,
    k: float = 1.5,
    vert: int = 20,
    patchtst_onnx: str = "",
    lgbm_pkl: str = "",
    catboost_pkl: Optional[str] = None,
    xgboost_pkl: Optional[str] = None,
    family_id: int = -1,
) -> dict:
    """Train the ridge stacker over ONNX + LightGBM + optional CatBoost/XGBoost outputs.

    Shared by ``train_stacker.py`` and ``train_deriv_stacker.py``. Returns a dict with
    ``ridge``, ``scaler`` and per-model ``test_ic`` values.
    """
    from scipy.stats import spearmanr
    from sklearn.linear_model import Ridge
    from sklearn.preprocessing import StandardScaler

    train, val, test, _metadata = build_scaled_dataset_splits(
        csv,
        seq_len=seq_len,
        k=k,
        vertical_bars=vert,
        family_id=family_id,
    )

    X_all = np.concatenate([train[0], val[0]], axis=0)
    y_all = np.concatenate([train[1], val[1]], axis=0)
    ts_all = np.concatenate([train[4], val[4]], axis=0)
    X_test = test[0]
    r_test = test[3]

    lgbm = safe_pickle_load(lgbm_pkl)

    catboost = None
    if catboost_pkl is not None:
        catboost = safe_pickle_load(catboost_pkl)

    xgboost = None
    if xgboost_pkl is not None:
        xgboost = safe_pickle_load(xgboost_pkl)

    n_base = 2  # onnx + lgbm minimum
    if catboost is not None:
        n_base += 1
    if xgboost is not None:
        n_base += 1
    n_cols = n_base * 3

    X_all_flat = X_all.reshape(len(X_all), -1)
    X_test_flat = X_test.reshape(len(X_test), -1)
    onnx_probs = get_onnx_probs(patchtst_onnx, X_all)
    lgbm_probs = lgbm.predict(X_all_flat)

    # Fill meta-features for EVERY row. The old fold loop only wrote TimeSeriesSplit
    # validation indices, leaving the first block all zeros; the base predictions are
    # already computed for all rows, so there is no reason to drop them. Predictions
    # on rows inside a base model's own training range remain in-sample - the meta-
    # fit below excludes them via recorded .trainmeta.json ranges where available.
    meta_parts = [onnx_probs, lgbm_probs]
    if catboost is not None:
        meta_parts.append(catboost.predict_proba(X_all_flat))
    if xgboost is not None:
        meta_parts.append(xgboost.predict_proba(X_all_flat))
    meta_X = np.concatenate(meta_parts, axis=1).astype(np.float32)
    assert meta_X.shape == (len(X_all), n_cols)
    assert not np.all(meta_X == 0.0, axis=1).any(), "meta_X still has all-zero rows"

    # Fit the meta-learner only on rows that are out-of-sample for EVERY base
    # model: the validation region baseline (train-row base predictions are
    # in-sample) tightened by each model's recorded .trainmeta.json train_end,
    # which keeps the fit honest when bases were trained on different splits.
    n_train_rows = len(train[0])
    fit_idx = stacker_fit_indices(
        ts_all, n_train_rows,
        [patchtst_onnx, lgbm_pkl, catboost_pkl, xgboost_pkl],
    )
    print(f"stacker: fitting ridge on {len(fit_idx)}/{len(X_all)} rows "
          f"(val region + post-training-range)")
    scaler = StandardScaler().fit(meta_X[fit_idx])
    ridge = Ridge(alpha=1.0).fit(scaler.transform(meta_X[fit_idx]),
                               (y_all[fit_idx] == 2).astype(float))

    test_onnx = get_onnx_probs(patchtst_onnx, X_test)
    test_lgbm = lgbm.predict(X_test_flat)
    test_parts = [test_onnx, test_lgbm]
    if catboost is not None:
        test_parts.append(catboost.predict_proba(X_test_flat))
    if xgboost is not None:
        test_parts.append(xgboost.predict_proba(X_test_flat))
    stack_signal = ridge.predict(scaler.transform(np.hstack(test_parts)))

    test_ic = {
        "onnx": float(spearmanr(test_onnx[:, 2] - test_onnx[:, 0], r_test)[0]),
        "lgbm": float(spearmanr(test_lgbm[:, 2] - test_lgbm[:, 0], r_test)[0]),
        "catboost": None,
        "xgboost": None,
        "stacker": float(spearmanr(stack_signal, r_test)[0]),
    }
    if catboost is not None:
        test_ic["catboost"] = float(spearmanr(test_parts[2][:, 2] - test_parts[2][:, 0], r_test)[0])
    if xgboost is not None:
        test_ic["xgboost"] = float(spearmanr(test_parts[-1][:, 2] - test_parts[-1][:, 0], r_test)[0])

    return {"ridge": ridge, "scaler": scaler, "test_ic": test_ic}


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
