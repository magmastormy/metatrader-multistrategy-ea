import argparse
import os

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

from models import PatchTST, SequenceMLP, iTransformer
from data_pipeline import (
    build_symbol_sequences,
)


def train(model, X_tr, y_tr, X_val, y_val,
          epochs=100, batch=64, lr=3e-4, wd=1e-4, device="cpu"):
    model = model.to(device)
    counts = np.bincount(y_tr, minlength=3)
    wts = torch.tensor(1.0 / (counts + 1), dtype=torch.float32).to(device)
    crit = nn.CrossEntropyLoss(weight=wts)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=wd)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)

    ds = torch.utils.data.TensorDataset(
        torch.tensor(X_tr, dtype=torch.float32),
        torch.tensor(y_tr, dtype=torch.long),
    )
    loader = torch.utils.data.DataLoader(ds, batch_size=batch, shuffle=True, drop_last=True)

    Xv = torch.tensor(X_val, dtype=torch.float32).to(device)
    yv = torch.tensor(y_val, dtype=torch.long).to(device)

    best_acc, best_state = 0.0, None
    for ep in range(epochs):
        model.train()
        for xb, yb in loader:
            xb, yb = xb.to(device), yb.to(device)
            opt.zero_grad()
            loss = crit(model(xb), yb)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
        sched.step()
        model.eval()
        with torch.no_grad():
            acc = (model(Xv).argmax(1) == yv).float().mean().item()
        if acc > best_acc:
            best_acc = acc
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
        if (ep + 1) % 20 == 0:
            print(f"  Ep {ep + 1:3d}  val_acc={acc:.4f}  best={best_acc:.4f}")
    model.load_state_dict(best_state)
    return best_acc


def export_onnx(model, seq_len, n_feat, path):
    model.eval()
    dummy = torch.zeros(1, seq_len, n_feat)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    torch.onnx.export(
        model,
        dummy,
        path,
        opset_version=18,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
        do_constant_folding=True,
        dynamo=False,
        verbose=False,
    )
    print(f"Exported ONNX -> {path}")
    try:
        import onnx

        loaded = onnx.load(path)
        onnx.checker.check_model(loaded)
        print("ONNX structural validation OK")
    except ImportError:
        print("ONNX package not installed; skipped structural validation")

    try:
        import onnxruntime as ort

        sess = ort.InferenceSession(path)
        out = sess.run(None, {"input": np.zeros((1, seq_len, n_feat), np.float32)})
        assert out[0].shape == (1, 3), f"Shape mismatch: {out[0].shape}"
        print("ONNX runtime validation OK")
    except ImportError:
        print("ONNX Runtime not installed; skipped runtime validation")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True,
                    help="CSV with columns: date,open,high,low,close,volume and optional symbol")
    ap.add_argument("--model", default="mlp",
                    choices=["mlp", "patchtst", "itransformer", "ensemble"])
    ap.add_argument("--seq_len", type=int, default=60)
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--output", default="../Resources/model.onnx")
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--k", type=float, default=1.5,
                    help="Triple-barrier ATR multiplier")
    ap.add_argument("--vert", type=int, default=20,
                    help="Triple-barrier vertical bar limit")
    args = ap.parse_args()

    torch.manual_seed(42)
    np.random.seed(42)

    df = pd.read_csv(args.data)
    X_tr, y_tr, X_v, y_v = build_symbol_sequences(
        df,
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
        train_ratio=0.80,
    )
    n_feat = X_tr.shape[2]

    print(f"Train={len(X_tr)}  Val={len(X_v)}  Features={n_feat}")
    print(f"Label dist train: {np.bincount(y_tr)}")

    best_acc, best_model = 0.0, None

    if args.model in ("mlp", "ensemble"):
        print("\n--- SequenceMLP ---")
        model = SequenceMLP(seq_len=args.seq_len, n_features=n_feat)
        acc = train(model, X_tr, y_tr, X_v, y_v,
                    epochs=args.epochs, device=args.device)
        if acc > best_acc:
            best_acc, best_model = acc, model

    if args.model in ("patchtst", "ensemble"):
        print("\n--- PatchTST ---")
        model = PatchTST(seq_len=args.seq_len, n_features=n_feat)
        acc = train(model, X_tr, y_tr, X_v, y_v,
                    epochs=args.epochs, device=args.device)
        if acc > best_acc:
            best_acc, best_model = acc, model

    if args.model in ("itransformer", "ensemble"):
        print("\n--- iTransformer ---")
        model = iTransformer(seq_len=args.seq_len, n_features=n_feat)
        acc = train(model, X_tr, y_tr, X_v, y_v,
                    epochs=args.epochs, device=args.device)
        if acc > best_acc:
            best_acc, best_model = acc, model

    export_onnx(best_model, args.seq_len, n_feat, args.output)
    print(f"\nDone. Best val_acc={best_acc:.4f}  ->  {args.output}")
