"""Vendor the canonical function blocks from ``training_core.py`` into
``mql5_v2.py``.

``mql5_v2.py`` must stay a self-contained Colab script, so the shared
primitives (ATR, triple-barrier labels, uniqueness weights, CUSUM, feature
helpers, CPCV purge/folds) are inlined between ``# @@VENDOR <name>`` markers.
This script re-splices them whenever ``training_core.py`` changes — run it
after editing any ``@@VENDOR-BEGIN`` region, then diff-check ``mql5_v2.py``.
"""

from __future__ import annotations

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORE = HERE / "training_core.py"
TARGET = HERE / "mql5_v2.py"

BEGIN_RE = re.compile(r"# @@VENDOR-BEGIN (\w+)\n(.*?)# @@VENDOR-END \1", re.DOTALL)
SLOT_RE = re.compile(r"# @@VENDOR-SLOT (\w+)\n.*?# @@VENDOR-SLOT-END \1", re.DOTALL)


def main() -> None:
    core = CORE.read_text(encoding="utf-8")
    regions = {name: body for name, body in BEGIN_RE.findall(core)}
    if not regions:
        raise SystemExit("no vendor regions found in training_core.py")

    text = TARGET.read_text(encoding="utf-8")

    def splice(match: re.Match) -> str:
        name = match.group(1)
        if name not in regions:
            raise SystemExit(f"mql5_v2.py requests unknown vendor region: {name}")
        return f"# @@VENDOR-SLOT {name}\n{regions[name]}# @@VENDOR-SLOT-END {name}"

    text, count = SLOT_RE.subn(splice, text)
    TARGET.write_text(text, encoding="utf-8")
    print(f"vendored {count} region(s) into {TARGET.name}: {sorted(regions)}")


if __name__ == "__main__":
    main()
