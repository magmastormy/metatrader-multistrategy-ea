"""Safe pickle loading for locally stored model files.

``pickle.load`` executes arbitrary code embedded in the file. Model files are local,
but a swapped or corrupted file would run code at load time. This unpickler only
allows globals from the model/scientific stack; anything else raises.
"""

from __future__ import annotations

import pickle
from typing import Any

_ALLOWED_ROOTS = {
    "numpy",
    "sklearn",
    "scipy",
    "pandas",
    "lightgbm",
    "catboost",
    "xgboost",
    "collections",
    "copyreg",
    "builtins",
    "__builtin__",
}


class SafeUnpickler(pickle.Unpickler):
    def find_class(self, module: str, name: str) -> Any:
        root = module.split(".", 1)[0]
        if root not in _ALLOWED_ROOTS:
            raise pickle.UnpicklingError(f"Blocked unpickle global: {module}.{name}")
        return super().find_class(module, name)


def safe_pickle_load(path: str) -> Any:
    """Load a pickle file allowing only whitelisted model-library globals."""
    with open(path, "rb") as handle:
        return SafeUnpickler(handle).load()
