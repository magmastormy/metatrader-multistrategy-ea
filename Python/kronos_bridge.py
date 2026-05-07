from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib import request


class KronosBridge:
    """
    Thin HTTP bridge for an external Kronos-like model service.
    The endpoint is expected to accept JSON payloads and return
    buy/sell/hold probabilities or a directional score.
    """

    def __init__(self, endpoint: str) -> None:
        self.endpoint = endpoint.rstrip("/")

    def predict(self, payload: dict) -> dict:
        body = json.dumps(payload).encode("utf-8")
        req = request.Request(
            self.endpoint,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with request.urlopen(req, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Proxy MT5 features to an external Kronos-style model endpoint.")
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    payload = json.loads(Path(args.input).read_text(encoding="utf-8"))
    result = KronosBridge(args.endpoint).predict(payload)
    Path(args.output).write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
