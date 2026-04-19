import argparse
import struct
from pathlib import Path

import numpy as np
import pandas as pd

HEADER_SIZE = 432
COUNT_OFFSET = 0xAC


def _read_prefixed_array(blob: bytes, offset: int, count: int, dtype: str):
    stored_count = struct.unpack_from("<I", blob, offset)[0]
    if stored_count != count:
        raise ValueError(f"Unexpected array count at offset {offset}: {stored_count} != {count}")
    offset += 4
    arr = np.frombuffer(blob, dtype=np.dtype(dtype), count=count, offset=offset).copy()
    return arr, offset + arr.nbytes


def read_mt5_hc(path: Path, symbol: str | None = None) -> pd.DataFrame:
    blob = path.read_bytes()
    count = struct.unpack_from("<I", blob, COUNT_OFFSET)[0]

    times = np.frombuffer(blob, dtype=np.dtype("<u8"), count=count, offset=HEADER_SIZE).copy()
    offset = HEADER_SIZE + times.nbytes

    open_, offset = _read_prefixed_array(blob, offset, count, "<f8")
    high, offset = _read_prefixed_array(blob, offset, count, "<f8")
    low, offset = _read_prefixed_array(blob, offset, count, "<f8")
    close, offset = _read_prefixed_array(blob, offset, count, "<f8")
    tick_volume, offset = _read_prefixed_array(blob, offset, count, "<u8")

    frame = pd.DataFrame(
        {
            "symbol": symbol or path.parent.parent.name,
            "date": pd.to_datetime(times.astype("int64"), unit="s"),
            "open": open_,
            "high": high,
            "low": low,
            "close": close,
            "volume": tick_volume.astype("int64"),
        }
    )
    return frame.dropna().sort_values("date").reset_index(drop=True)


def export_symbol_group(base_dir: Path, symbols: list[str], timeframe: str) -> pd.DataFrame:
    frames = []
    for symbol in symbols:
        cache_path = base_dir / symbol / "cache" / f"{timeframe}.hc"
        if not cache_path.exists():
            print(f"[cache-export] missing: {cache_path}")
            continue
        frame = read_mt5_hc(cache_path, symbol=symbol)
        print(f"[cache-export] {symbol} {timeframe} rows={len(frame)} from {cache_path}")
        frames.append(frame)

    if not frames:
        raise FileNotFoundError("No MT5 cache files were found for the requested symbols.")

    return pd.concat(frames, ignore_index=True).sort_values(["symbol", "date"]).reset_index(drop=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-dir", required=True, help="MT5 history directory containing <symbol>/cache/<TF>.hc")
    parser.add_argument("--symbols", nargs="+", required=True, help="Symbol folders to export")
    parser.add_argument("--timeframe", default="H1", help="Cache timeframe file stem, e.g. H1, M15, H4")
    parser.add_argument("--output", required=True, help="Destination CSV path")
    args = parser.parse_args()

    base_dir = Path(args.base_dir)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    df = export_symbol_group(base_dir, args.symbols, args.timeframe)
    df.to_csv(output, index=False)
    print(f"[cache-export] wrote {len(df)} rows -> {output}")
