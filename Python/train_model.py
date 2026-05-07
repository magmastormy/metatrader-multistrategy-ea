from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, Tuple

import numpy as np
import torch
import torch.nn as nn
from scipy.stats import spearmanr

from data_pipeline import PipelineMetadata, build_scaled_dataset_splits
from models import PatchTST, SequenceMLP, iTransformer
from validate_model import run_cpcv


def compute_ic(model: nn.Module, loader, device: str) -> float:
    model.eval()
    scores, returns = [], []
    with torch.no_grad():
        for x, _y, _w, ret in loader:
            probs = torch.softmax(model(x.to(device)), dim=-1).cpu().numpy()
            scores.extend((probs[:, 2] - probs[:, 0]).tolist())
            returns.extend(ret.numpy().tolist())
    ic, _ = spearmanr(scores, returns)
    return float(ic) if not np.isnan(ic) else 0.0


def train_epoch(
    model: nn.Module,
    loader,
    optimizer,
    scheduler,
    criterion,
    device: str,
) -> float:
    model.train()
    total_loss = 0.0
    for x, y, w, _ret in loader:
        x = x.to(device)
        y = y.to(device)
        w = w.to(device)
        optimizer.zero_grad()
        loss = (criterion(model(x), y) * w).mean()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimizer.step()
        scheduler.step()
        total_loss += float(loss.item())
    return total_loss / max(1, len(loader))


def export_onnx(model: nn.Module, seq_len: int, n_feat: int, path: str, opset: int = 12) -> None:
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    model.eval()
    dummy = torch.zeros(1, seq_len, n_feat, dtype=torch.float32)
    torch.onnx.export(
        model,
        dummy,
        str(output),
        opset_version=opset,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
        do_constant_folding=True,
        dynamo=False,
        verbose=False,
    )


def instantiate_models(model_name: str, seq_len: int, n_feat: int) -> Dict[str, nn.Module]:
    candidates: Dict[str, nn.Module] = {}
    if model_name in ("mlp", "ensemble"):
        candidates["mlp"] = SequenceMLP(seq_len=seq_len, n_features=n_feat)
    if model_name in ("patchtst", "ensemble"):
        candidates["patchtst"] = PatchTST(seq_len=seq_len, n_features=n_feat)
    if model_name in ("itransformer", "ensemble"):
        candidates["itransformer"] = iTransformer(seq_len=seq_len, n_features=n_feat)
    return candidates


def build_loader(split, batch_size: int, shuffle: bool):
    from data_pipeline import TradingDataset
    from torch.utils.data import DataLoader

    return DataLoader(TradingDataset(*split[:4]), batch_size=batch_size, shuffle=shuffle, drop_last=False)


def train_candidate(
    name: str,
    model: nn.Module,
    train_split,
    val_split,
    test_split,
    metadata: PipelineMetadata,
    epochs: int,
    batch_size: int,
    lr: float,
    weight_decay: float,
    device: str,
) -> Tuple[float, float, nn.Module]:
    train_loader = build_loader(train_split, batch_size=batch_size, shuffle=True)
    val_loader = build_loader(val_split, batch_size=batch_size, shuffle=False)
    test_loader = build_loader(test_split, batch_size=batch_size, shuffle=False)

    y_train = train_split[1]
    counts = np.bincount(y_train, minlength=3)
    class_weights = torch.tensor(1.0 / np.maximum(counts, 1), dtype=torch.float32, device=device)
    criterion = nn.CrossEntropyLoss(weight=class_weights, reduction="none")

    model = model.to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)
    total_steps = max(1, epochs * max(1, len(train_loader)))
    scheduler = torch.optim.lr_scheduler.OneCycleLR(
        optimizer,
        max_lr=lr,
        total_steps=total_steps,
        pct_start=0.15,
    )

    best_state = None
    best_val_ic = -1e9
    patience = 0

    print(f"\n--- Training {name} ---")
    for epoch in range(epochs):
        loss = train_epoch(model, train_loader, optimizer, scheduler, criterion, device)
        val_ic = compute_ic(model, val_loader, device)
        if val_ic > best_val_ic:
            best_val_ic = val_ic
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            patience = 0
        else:
            patience += 1

        if (epoch + 1) % 10 == 0 or epoch == 0:
            print(f"  epoch={epoch + 1:03d} loss={loss:.5f} val_ic={val_ic:.4f} best_ic={best_val_ic:.4f}")
        if patience >= 20:
            print(f"  early_stop={epoch + 1} patience=20")
            break

    if best_state is not None:
        model.load_state_dict(best_state)
    test_ic = compute_ic(model, test_loader, device)
    print(f"  final_val_ic={best_val_ic:.4f} test_ic={test_ic:.4f} annualization={metadata.annualization:.1f}")
    return best_val_ic, test_ic, model


def main() -> None:
    parser = argparse.ArgumentParser(description="Train an ONNX-exportable MT5 sequence model.")
    parser.add_argument("--csv", "--data", dest="csv", required=True)
    parser.add_argument("--model", default="patchtst", choices=["mlp", "patchtst", "itransformer", "ensemble"])
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--output", default="../Resources/model.onnx")
    parser.add_argument("--scaler-output", default=None)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    parser.add_argument("--cpcv-splits", type=int, default=6)
    parser.add_argument("--min-ic", type=float, default=0.02)
    parser.add_argument("--force-export", action="store_true")
    args = parser.parse_args()

    torch.manual_seed(42)
    np.random.seed(42)

    scaler_output = args.scaler_output
    if scaler_output is None:
        scaler_output = str(Path(args.output).with_name("scaler.bin"))

    train_split, val_split, test_split, metadata = build_scaled_dataset_splits(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
        scaler_output=scaler_output,
    )

    print(
        f"train={metadata.train_size} val={metadata.val_size} test={metadata.test_size} "
        f"features={metadata.n_features} annualization={metadata.annualization:.1f}"
    )

    candidates = instantiate_models(args.model, metadata.seq_len, metadata.n_features)
    best_name = ""
    best_val_ic = -1e9
    best_test_ic = -1e9
    best_model = None

    for name, model in candidates.items():
        val_ic, test_ic, trained = train_candidate(
            name=name,
            model=model,
            train_split=train_split,
            val_split=val_split,
            test_split=test_split,
            metadata=metadata,
            epochs=args.epochs,
            batch_size=args.batch_size,
            lr=args.lr,
            weight_decay=args.weight_decay,
            device=args.device,
        )
        if val_ic > best_val_ic:
            best_name = name
            best_val_ic = val_ic
            best_test_ic = test_ic
            best_model = trained

    if best_model is None:
        raise RuntimeError("No model candidates were trained.")

    temp_output = Path(args.output).with_suffix(".tmp.onnx")
    export_onnx(best_model, metadata.seq_len, metadata.n_features, str(temp_output))

    X_all = np.concatenate([train_split[0], val_split[0], test_split[0]], axis=0)
    y_all = np.concatenate([train_split[1], val_split[1], test_split[1]], axis=0)
    returns_all = np.concatenate([train_split[3], val_split[3], test_split[3]], axis=0)
    cpcv = run_cpcv(
        model_path=str(temp_output),
        X=X_all,
        y=y_all,
        bar_returns=returns_all,
        n_splits=args.cpcv_splits,
        annualization=metadata.annualization,
    )

    deploy_ok = best_test_ic >= args.min_ic and cpcv["deploy_gate"]
    if deploy_ok or args.force_export:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        temp_output.replace(output)
        print(
            f"exported={output} model={best_name} val_ic={best_val_ic:.4f} "
            f"test_ic={best_test_ic:.4f} force_export={args.force_export}"
        )
    else:
        temp_output.unlink(missing_ok=True)
        raise SystemExit(
            f"Deployment gate failed: test_ic={best_test_ic:.4f} min_ic={args.min_ic:.4f} "
            f"cpcv_pass={cpcv['deploy_gate']}"
        )


if __name__ == "__main__":
    main()
