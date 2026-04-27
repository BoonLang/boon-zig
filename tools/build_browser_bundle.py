#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
BROWSER_SRC = REPO_ROOT / "browser"
TODO_MVC_PHYSICAL_PATH = "examples/upstream/todo_mvc_physical/RUN.bn"
PHYSICAL_THEME_ACTIONS: tuple[tuple[str, list[list[object]]], ...] = (
    ("Professional", []),
    ("Glassmorphism", [["click_button", 1]]),
    ("Neobrutalism", [["click_button", 2]]),
    ("Neumorphism", [["click_button", 3]]),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--boon-zig-bin", required=True)
    return parser.parse_args()


def capture_render_target(boon_zig_bin: Path, actions: list[list[object]]) -> dict[str, object]:
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump({"actions": actions}, handle)
        handle.write("\n")
        script_path = Path(handle.name)
    try:
        command = [
            str(boon_zig_bin),
            "physical-state",
            TODO_MVC_PHYSICAL_PATH,
            "--script",
            str(script_path),
        ]
        result = subprocess.run(
            command,
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)
    finally:
        script_path.unlink(missing_ok=True)


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for relative in ("index.html", "boon-browser.mjs"):
        shutil.copy2(BROWSER_SRC / relative, out_dir / relative)

    boon_zig_bin = Path(args.boon_zig_bin)
    physical_render_targets = {
        theme_name: capture_render_target(boon_zig_bin, actions)
        for theme_name, actions in PHYSICAL_THEME_ACTIONS
    }

    manifest = {
        "bundle": "boon-zig-browser-host",
        "supported_examples": ["counter", "interval", "cells", "cells_dynamic", "todo_mvc", "todo_mvc_physical"],
        "storage": "IndexedDB primary with in-memory fallback for smoke environments",
        "wasm_host_boundary": "integrated-js-adapter",
        "physical_render_targets": physical_render_targets,
        "physical_render_target_source": {
            "example": TODO_MVC_PHYSICAL_PATH,
            "runner": str(boon_zig_bin),
            "themes": [theme_name for theme_name, _ in PHYSICAL_THEME_ACTIONS],
        },
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"built browser bundle in {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
