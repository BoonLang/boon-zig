#!/usr/bin/env python3

from __future__ import annotations

import argparse
import subprocess


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    command = [
        "chromium",
        "--headless",
        "--disable-gpu",
        "--hide-scrollbars",
        "--run-all-compositor-stages-before-draw",
        "--virtual-time-budget=3000",
        "--force-device-scale-factor=2",
        "--window-size=700,700",
        f"--screenshot={args.output}",
        args.url,
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(result.stderr or result.stdout or f"chromium screenshot failed: {result.returncode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
