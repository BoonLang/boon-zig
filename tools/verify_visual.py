#!/usr/bin/env python3

from __future__ import annotations

import argparse
import math
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.request import urlopen

from PIL import Image, ImageChops


REPO_ROOT = Path(__file__).resolve().parent.parent
REFERENCE = REPO_ROOT / "examples" / "upstream" / "todo_mvc" / "reference_700x700_(1400x1400).png"
OUTPUT_DIR = REPO_ROOT / "tests" / "browser_visual"
PORT = 4173
SIMILARITY_THRESHOLD = 0.83


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--filter")
    group.add_argument("--all-with-reference-assets", action="store_true")
    return parser.parse_args()


def wait_for_server(url: str) -> None:
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            with urlopen(url) as response:
                if response.status == 200:
                    return
        except Exception:
            time.sleep(0.1)
    raise SystemExit(f"server did not start: {url}")


def compare_images(current_path: Path, diff_path: Path) -> float:
    reference = Image.open(REFERENCE).convert("RGBA")
    current = Image.open(current_path).convert("RGBA")
    if current.size != reference.size:
        raise SystemExit(f"unexpected screenshot size {current.size}, expected {reference.size}")

    diff = ImageChops.difference(reference, current)
    diff.save(diff_path)

    histogram = diff.histogram()
    channels = 4
    total_pixels = reference.size[0] * reference.size[1]
    sum_squares = 0.0
    for channel in range(channels):
        offset = channel * 256
        for value in range(256):
            count = histogram[offset + value]
            sum_squares += count * (value ** 2)
    rms = math.sqrt(sum_squares / (total_pixels * channels))
    return 1.0 - (rms / 255.0)


def main() -> int:
    args = parse_args()
    if args.all_with_reference_assets:
        targets = ["todo_mvc"]
    elif args.filter == "todo_mvc":
        targets = ["todo_mvc"]
    else:
        print("verify-visual currently supports only --filter todo_mvc or --filter all-with-reference-assets", file=sys.stderr)
        return 2

    subprocess.run(
        [
            "python3",
            "tools/build_browser_bundle.py",
            "--out-dir",
            "zig-out/browser",
            "--boon-zig-bin",
            "zig-out/bin/boon-zig",
        ],
        cwd=REPO_ROOT,
        check=True,
    )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    results: list[tuple[str, float, Path, Path]] = []

    with tempfile.TemporaryDirectory(prefix="boon-zig-http-") as _:
        server = subprocess.Popen(
            ["python3", "-m", "http.server", str(PORT), "--directory", "zig-out/browser"],
            cwd=REPO_ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            wait_for_server(f"http://127.0.0.1:{PORT}/index.html")
            for target in targets:
                current_path = OUTPUT_DIR / f"{target}.current.png"
                diff_path = OUTPUT_DIR / f"{target}.diff.png"
                subprocess.run(
                    [
                        "python3",
                        "tools/capture_browser_screenshot.py",
                        "--url",
                        f"http://127.0.0.1:{PORT}/index.html?example={target}&visual=1",
                        "--output",
                        str(current_path),
                    ],
                    cwd=REPO_ROOT,
                    check=True,
                )
                similarity = compare_images(current_path, diff_path)
                if similarity < SIMILARITY_THRESHOLD:
                    print(
                        f"verify-visual failed: {target} similarity {similarity:.4f} below threshold {SIMILARITY_THRESHOLD:.2f}",
                        file=sys.stderr,
                    )
                    print(f"reference={REFERENCE}", file=sys.stderr)
                    print(f"current={current_path}", file=sys.stderr)
                    print(f"diff={diff_path}", file=sys.stderr)
                    return 1
                results.append((target, similarity, current_path, diff_path))
        finally:
            server.terminate()
            server.wait(timeout=5)

    for target, similarity, current_path, diff_path in results:
        print(f"PASS {target} similarity {similarity:.4f}")
        print(f"current={current_path}")
        print(f"diff={diff_path}")
    print(f"verify-visual ok ({len(results)} passed)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
