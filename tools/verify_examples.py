#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
import json


REPO_ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class HeadlessCase:
    name: str
    path: str
    args: tuple[str, ...] = ()
    blocked_reason: str | None = None
    blocked_marker: str | None = None


@dataclass(frozen=True)
class SnapshotCase:
    name: str
    path: str
    expected_path: str
    args: tuple[str, ...] = ()


HEADLESS_P0_CASES: tuple[HeadlessCase, ...] = (
    HeadlessCase(
        name="counter",
        path="examples/upstream/counter/counter.bn",
        args=(
            "--script",
            "tests/examples/counter_sequence.json",
            "--expect-text",
            "5+",
        ),
    ),
    HeadlessCase(
        name="interval",
        path="examples/upstream/interval/interval.bn",
        args=(
            "--virtual-time",
            "2s",
            "--expect-text",
            "2",
        ),
    ),
    HeadlessCase(
        name="cells",
        path="examples/upstream/cells/cells.bn",
        args=(
            "--expect-text",
            "CellsABCDEFGHIJKLMNOPQRSTUVWXYZ151530210315456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100",
        ),
    ),
    HeadlessCase(
        name="todo_mvc",
        path="examples/upstream/todo_mvc/todo_mvc.bn",
        args=(
            "--expect-text",
            "todos\u276fNoElementBuy groceriesNoElementClean room2itemsleftAllActiveCompletedNoElementDouble-click to edit a todoCreated by Martin Kav\u00edkPart of TodoMVC",
        ),
    ),
    HeadlessCase(
        name="pong",
        path="examples/terminal/pong/pong.bn",
        args=(
            "--script",
            "tests/examples/pong_sequence.json",
            "--expect-text",
            "PONGYOU0CPU0STATUSRally########################.....................##.....................##[].................[]##[]..............o..[]##[].................[]##.....................##.....................########################",
        ),
    ),
    HeadlessCase(
        name="arkanoid",
        path="examples/terminal/arkanoid/arkanoid.bn",
        args=(
            "--script",
            "tests/examples/arkanoid_sequence.json",
            "--expect-text",
            "Arkanoid########.....o.....p....######Bricks:2Paddle:1Ball:1Flight",
        ),
    ),
)

TERMINAL_GRID_P0_CASES: tuple[SnapshotCase, ...] = (
    SnapshotCase(
        name="counter",
        path="examples/upstream/counter/counter.bn",
        expected_path="tests/terminal_grid/counter.expected",
        args=(
            "--script",
            "tests/examples/counter_sequence.json",
        ),
    ),
    SnapshotCase(
        name="interval",
        path="examples/upstream/interval/interval.bn",
        expected_path="tests/terminal_grid/interval.expected",
        args=(
            "--virtual-time",
            "2s",
        ),
    ),
    SnapshotCase(
        name="cells",
        path="examples/upstream/cells/cells.bn",
        expected_path="tests/terminal_grid/cells.expected",
    ),
    SnapshotCase(
        name="todo_mvc",
        path="examples/upstream/todo_mvc/todo_mvc.bn",
        expected_path="tests/terminal_grid/todo_mvc.expected",
    ),
    SnapshotCase(
        name="pong",
        path="examples/terminal/pong/pong.bn",
        expected_path="tests/terminal_grid/pong.expected",
        args=(
            "--script",
            "tests/examples/pong_sequence.json",
        ),
    ),
    SnapshotCase(
        name="arkanoid",
        path="examples/terminal/arkanoid/arkanoid.bn",
        expected_path="tests/terminal_grid/arkanoid.expected",
        args=(
            "--script",
            "tests/examples/arkanoid_sequence.json",
        ),
    ),
)


def main() -> int:
    boon_zig_bin, mode, example_filter = parse_args(sys.argv[1:])

    if mode == "headless":
        return verify_headless(boon_zig_bin, example_filter)
    if mode == "terminal-grid":
        return verify_terminal_grid(boon_zig_bin, example_filter)
    if mode == "browser-smoke":
        return verify_browser_smoke(boon_zig_bin, example_filter)
    print("verify-examples currently supports only --headless, --terminal-grid, and --browser-smoke", file=sys.stderr)
    return 2


def verify_headless(boon_zig_bin: Path, example_filter: str) -> int:
    if example_filter == "p0":
        return verify_headless_cases(boon_zig_bin, HEADLESS_P0_CASES)
    if example_filter == "all":
        return verify_manifest_headless(boon_zig_bin)
    return verify_manifest_headless(boon_zig_bin, only_name=example_filter)


def verify_terminal_grid(boon_zig_bin: Path, example_filter: str) -> int:
    if example_filter == "p0":
        return verify_terminal_grid_cases(boon_zig_bin, TERMINAL_GRID_P0_CASES)
    if example_filter == "all":
        return verify_manifest_terminal_grid(boon_zig_bin)
    return verify_manifest_terminal_grid(boon_zig_bin, only_name=example_filter)


def verify_browser_smoke(boon_zig_bin: Path, example_filter: str) -> int:
    if example_filter == "all":
        return verify_manifest_browser_smoke(boon_zig_bin)

    if example_filter not in {"counter", "interval", "cells", "cells_dynamic", "todo_mvc", "todo_mvc_physical"}:
        print("verify-examples browser smoke currently supports only --filter counter, --filter interval, --filter cells, --filter cells_dynamic, --filter todo_mvc, --filter todo_mvc_physical, or --all", file=sys.stderr)
        return 2

    command = ["node", "tools/browser_smoke.mjs", example_filter]
    result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        print("verify-examples failed", file=sys.stderr)
        print(render_failure(example_filter, command, result), file=sys.stderr)
        return 1

    stdout = result.stdout.strip()
    if stdout:
        print(stdout)
    print("verify-examples ok (1 passed, 0 exact blockers recorded)")
    return 0


def verify_manifest_browser_smoke(boon_zig_bin: Path) -> int:
    manifest = load_manifest()
    failures: list[str] = []
    blocked = 0
    passed = 0
    partial = 0
    runnable = {"counter", "interval", "cells", "cells_dynamic", "todo_mvc", "todo_mvc_physical"}

    entries = list(manifest["examples"]) + list(manifest.get("planned_p0_repo_examples", []))
    for entry in entries:
        name = str(entry["name"])
        browser_status = str(entry.get("browser_status", "NOT_STARTED"))

        if browser_status == "DONE":
            if name not in runnable:
                failures.append(f"- {name}: browser_status is DONE but no browser smoke runner exists")
                continue
            command = ["node", "tools/browser_smoke.mjs", name]
            result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
            if result.returncode != 0:
                failures.append(render_failure(name, command, result))
                continue
            passed += 1
            print(f"PASS {name}")
            continue

        if browser_status == "BLOCKED":
            blocked += 1
            blockers = entry.get("blockers") or []
            reason = blockers[0] if blockers else "blocked in manifest"
            print(f"BLOCKED {name}: {reason}")
            continue

        if browser_status == "PARTIAL":
            partial += 1
            print(f"PARTIAL {name}")
            continue

        failures.append(f"- {name}: browser_status is {browser_status}; Phase 13 requires DONE/PARTIAL/BLOCKED evidence")

    if failures:
        print("verify-examples failed", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(f"verify-examples ok ({passed} passed, {partial} partial, {blocked} exact blockers recorded)")
    return 0


def verify_headless_cases(boon_zig_bin: Path, cases: tuple[HeadlessCase, ...]) -> int:
    failures: list[str] = []
    blocked = 0
    passed = 0

    for case in cases:
        if case.blocked_reason is not None:
            path = REPO_ROOT / case.path
            text = path.read_text(errors="replace")
            if case.blocked_marker is None or case.blocked_marker not in text:
                failures.append(
                    f"{case.name}: expected blocker marker {case.blocked_marker!r} in {case.path}, but it is no longer present"
                )
                continue
            blocked += 1
            print(f"BLOCKED {case.name}: {case.blocked_reason}")
            continue

        command = [str(boon_zig_bin), "run-headless", case.path, *case.args]
        result = subprocess.run(
            command,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            failures.append(render_failure(case.name, command, result))
            continue
        passed += 1
        print(f"PASS {case.name}")

    if failures:
        print("verify-examples failed", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(
        f"verify-examples ok ({passed} passed, {blocked} exact blockers recorded)"
    )
    return 0


def verify_terminal_grid_cases(boon_zig_bin: Path, cases: tuple[SnapshotCase, ...]) -> int:
    failures: list[str] = []
    passed = 0

    for case in cases:
        expected_text = (REPO_ROOT / case.expected_path).read_text()
        if expected_text.endswith("\n"):
            expected_text = expected_text[:-1]
        command = [
            str(boon_zig_bin),
            "snapshot",
            case.path,
            *case.args,
            "--expect-text",
            expected_text,
        ]
        result = subprocess.run(
            command,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            failures.append(render_failure(case.name, command, result))
            continue
        passed += 1
        print(f"PASS {case.name}")

    if failures:
        print("verify-examples failed", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(f"verify-examples ok ({passed} passed, 0 exact blockers recorded)")
    return 0


def load_manifest() -> dict:
    return json.loads((REPO_ROOT / "fixtures" / "corpus_manifest.json").read_text())


def example_bn_path(entry: dict) -> str | None:
    if "path" in entry:
        return str(entry["path"])
    imported = entry.get("imported_path")
    bn_files = entry.get("bn_files") or []
    if imported and len(bn_files) == 1:
        return f"{imported}/{bn_files[0]}"
    return None


def verify_manifest_headless(boon_zig_bin: Path, only_name: str | None = None) -> int:
    manifest = load_manifest()
    failures: list[str] = []
    blocked = 0
    passed = 0
    partial = 0

    known_cases = {case.name: case for case in HEADLESS_P0_CASES}
    entries = list(manifest["examples"]) + list(manifest.get("planned_p0_repo_examples", []))
    matched = False
    for entry in entries:
        name = str(entry["name"])
        if only_name is not None and name != only_name:
            continue
        matched = True
        runtime_status = str(entry.get("runtime_status", "NOT_STARTED"))
        path = example_bn_path(entry)

        if runtime_status == "DONE":
            if path is None:
                failures.append(f"- {name}: runtime_status is DONE but no single .bn path is available")
                continue
            known = known_cases.get(name)
            command = [str(boon_zig_bin), "run-headless", path]
            if known is not None:
                command.extend(known.args)
            result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
            if result.returncode != 0:
                failures.append(render_failure(name, command, result))
                continue
            passed += 1
            print(f"PASS {name}")
            continue

        if runtime_status == "BLOCKED":
            blocked += 1
            blockers = entry.get("blockers") or []
            reason = blockers[0] if blockers else "blocked in manifest"
            print(f"BLOCKED {name}: {reason}")
            continue

        if runtime_status == "PARTIAL":
            partial += 1
            print(f"PARTIAL {name}")
            continue

        failures.append(f"- {name}: runtime_status is {runtime_status}; Phase 10 requires DONE/PARTIAL/BLOCKED evidence")

    if only_name is not None and not matched:
        print(f"verify-examples failed\n- {only_name}: no manifest entry matched this filter", file=sys.stderr)
        return 1

    if failures:
        print("verify-examples failed", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(f"verify-examples ok ({passed} passed, {partial} partial, {blocked} exact blockers recorded)")
    return 0


def terminal_expected_path(name: str) -> str | None:
    candidate = REPO_ROOT / "tests" / "terminal_grid" / f"{name}.expected"
    if candidate.is_file():
        return str(candidate.relative_to(REPO_ROOT))
    return None


def verify_manifest_terminal_grid(boon_zig_bin: Path, only_name: str | None = None) -> int:
    manifest = load_manifest()
    failures: list[str] = []
    blocked = 0
    passed = 0
    partial = 0

    known_cases = {case.name: case for case in TERMINAL_GRID_P0_CASES}
    entries = list(manifest["examples"]) + list(manifest.get("planned_p0_repo_examples", []))
    matched = False
    for entry in entries:
        name = str(entry["name"])
        if only_name is not None and name != only_name:
            continue
        matched = True
        terminal_status = str(entry.get("terminal_status", "NOT_STARTED"))
        path = example_bn_path(entry)

        if terminal_status == "DONE":
            if path is None:
                failures.append(f"- {name}: terminal_status is DONE but no single .bn path is available")
                continue
            known = known_cases.get(name)
            expected_path = terminal_expected_path(name) if known is None else known.expected_path
            if expected_path is None:
                failures.append(f"- {name}: terminal_status is DONE but no snapshot expectation exists")
                continue
            expected_text = (REPO_ROOT / expected_path).read_text()
            if expected_text.endswith("\n"):
                expected_text = expected_text[:-1]
            command = [str(boon_zig_bin), "snapshot", path]
            if known is not None:
                command.extend(known.args)
            command.extend(("--expect-text", expected_text))
            result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
            if result.returncode != 0:
                failures.append(render_failure(name, command, result))
                continue
            passed += 1
            print(f"PASS {name}")
            continue

        if terminal_status == "BLOCKED":
            blocked += 1
            blockers = entry.get("blockers") or []
            reason = blockers[0] if blockers else "blocked in manifest"
            print(f"BLOCKED {name}: {reason}")
            continue

        if terminal_status == "PARTIAL":
            partial += 1
            print(f"PARTIAL {name}")
            continue

        failures.append(f"- {name}: terminal_status is {terminal_status}; Phase 10 requires DONE/PARTIAL/BLOCKED evidence")

    if failures:
        print("verify-examples failed", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    if only_name is not None and not matched:
        print(f"verify-examples failed\n- {only_name}: no manifest entry matched this filter", file=sys.stderr)
        return 1

    print(f"verify-examples ok ({passed} passed, {partial} partial, {blocked} exact blockers recorded)")
    return 0


def parse_args(args: list[str]) -> tuple[Path, str, str]:
    boon_zig_bin: Path | None = None
    mode: str | None = None
    example_filter = "p0"

    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--boon-zig-bin":
            if index + 1 >= len(args):
                raise SystemExit("--boon-zig-bin requires a path")
            boon_zig_bin = Path(args[index + 1])
            index += 2
            continue
        if arg == "--headless":
            mode = "headless"
            index += 1
            continue
        if arg == "--terminal-grid":
            mode = "terminal-grid"
            index += 1
            continue
        if arg == "--browser-smoke":
            mode = "browser-smoke"
            index += 1
            continue
        if arg == "--filter":
            if index + 1 >= len(args):
                raise SystemExit("--filter requires a value")
            example_filter = args[index + 1]
            index += 2
            continue
        if arg == "--all":
            example_filter = "all"
            index += 1
            continue
        raise SystemExit(f"unknown argument: {arg}")

    if boon_zig_bin is None:
        raise SystemExit("--boon-zig-bin is required")
    if mode is None:
        raise SystemExit("verification mode is required (for now: --headless)")
    return boon_zig_bin, mode, example_filter


def render_failure(
    name: str,
    command: list[str],
    result: subprocess.CompletedProcess[str],
) -> str:
    lines = [
        f"- {name}: command failed",
        f"  command: {' '.join(command)}",
        f"  exit: {result.returncode}",
    ]
    if result.stdout.strip():
        lines.append("  stdout:")
        lines.extend(f"    {line}" for line in result.stdout.strip().splitlines())
    if result.stderr.strip():
        lines.append("  stderr:")
        lines.extend(f"    {line}" for line in result.stderr.strip().splitlines())
    return "\n".join(lines)


if __name__ == "__main__":
    raise SystemExit(main())
