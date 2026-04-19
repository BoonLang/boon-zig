#!/usr/bin/env python3

from __future__ import annotations

import argparse
import http.server
import json
import socketserver
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", required=True, type=int)
    return parser.parse_args()


def load_physical_render_targets(root: Path) -> dict[str, object]:
    manifest_path = root / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    return dict(manifest.get("physical_render_targets", {}))


def physical_state(physical_render_targets: dict[str, object], example: str, theme: str) -> bytes:
    if example != "todo_mvc_physical":
        raise ValueError(f"unsupported physical example: {example}")
    payload = physical_render_targets.get(theme) or physical_render_targets.get("Professional")
    if payload is None:
        raise ValueError(f"missing physical render target for theme: {theme}")
    return json.dumps(payload).encode("utf-8")


def make_handler(root: Path, physical_render_targets: dict[str, object]):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(root), **kwargs)

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path == "/__boon/physical-state":
                params = parse_qs(parsed.query)
                example = params.get("example", ["todo_mvc_physical"])[0]
                theme = params.get("theme", ["Professional"])[0]
                try:
                    payload = physical_state(physical_render_targets, example, theme)
                except Exception as err:  # noqa: BLE001
                    body = json.dumps({"error": str(err)}).encode("utf-8")
                    self.send_response(500)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            return super().do_GET()

        def log_message(self, format: str, *args):  # noqa: A003
            return

    return Handler


def main() -> int:
    args = parse_args()
    root = Path(args.root)
    physical_render_targets = load_physical_render_targets(root)
    handler = make_handler(root, physical_render_targets)
    class ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    with ReusableTCPServer(("127.0.0.1", args.port), handler) as httpd:
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
