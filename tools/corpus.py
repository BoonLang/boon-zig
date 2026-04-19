#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
UPSTREAM_ROOT = REPO_ROOT / "third_party" / "boon-upstream"
UPSTREAM_EXAMPLES = UPSTREAM_ROOT / "playground" / "frontend" / "src" / "examples"
IMPORTED_EXAMPLES = REPO_ROOT / "examples" / "upstream"
UPSTREAM_OVERRIDES = REPO_ROOT / "examples" / "upstream_overrides"
FIXTURES_DIR = REPO_ROOT / "fixtures"

UPSTREAM_URL = "https://github.com/BoonLang/boon"
PINNED_COMMIT = "c924d9f7d7e1c156604c9377e0487db48c278353"
P0_UPSTREAM = {"counter", "interval", "cells", "todo_mvc", "todo_mvc_physical"}
PLANNED_TERMINAL_P0 = ("pong", "arkanoid")
STATUS = "NOT_STARTED"

HEADLESS_RUNTIME_EVIDENCE: dict[str, dict[str, object]] = {
    "counter": {
        "status": "DONE",
        "notes": [
            "Phase 7 headless verification replays deterministic counter clicks via tests/examples/counter_sequence.json and expects final render `5+`.",
        ],
    },
    "interval": {
        "status": "DONE",
        "notes": [
            "Phase 7 headless verification advances virtual time by 2s and expects exact render `2`.",
        ],
    },
    "cells": {
        "status": "DONE",
        "notes": [
            "Phase 7 headless verification asserts the deterministic initial spreadsheet render; deeper edit semantics stay covered by focused headless tests.",
        ],
    },
    "todo_mvc": {
        "status": "DONE",
        "notes": [
            "Phase 7 headless verification asserts the deterministic initial TodoMVC render; CRUD/filter/edit/remove semantics stay covered by focused headless tests.",
        ],
    },
    "button_hover_test": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the example via plain `run-headless` without a runtime crash.",
        ],
    },
    "button_hover_to_click_test": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the example via plain `run-headless` without a runtime crash.",
        ],
    },
    "cells_dynamic": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the dynamic spreadsheet variant via plain `run-headless`.",
        ],
    },
    "chained_list_remove_bug": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the dedicated chained List/remove regression example via plain `run-headless`.",
        ],
    },
    "checkbox_test": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the checkbox interaction example via plain `run-headless`.",
        ],
    },
    "complex_counter": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the PASS/PASSED user-function counter lane via plain `run-headless`.",
        ],
    },
    "counter_hold": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the HOLD-based counter example via plain `run-headless`.",
        ],
    },
    "filter_checkbox_bug": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the filter/checkbox regression example via plain `run-headless`.",
        ],
    },
    "flight_booker": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the booking form example via plain `run-headless`.",
        ],
    },
    "hello_world": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the hello world example via plain `run-headless`.",
        ],
    },
    "interval_hold": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the timer/HOLD example via plain `run-headless`.",
        ],
    },
    "list_map_block": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the block-mapping list example via plain `run-headless`.",
        ],
    },
    "list_map_external_dep": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the external-dependency list mapping example via plain `run-headless`.",
        ],
    },
    "list_object_state": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the per-item object state example via plain `run-headless`.",
        ],
    },
    "list_retain_remove": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the List/remove add/remove example via plain `run-headless`.",
        ],
    },
    "minimal": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the minimal example via plain `run-headless`.",
        ],
    },
    "pages": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the routing/pages example via plain `run-headless`.",
        ],
    },
    "shopping_list": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the shopping list example via plain `run-headless`.",
        ],
    },
    "switch_hold_test": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the switch/HOLD regression example via plain `run-headless`.",
        ],
    },
    "temperature_converter": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the temperature converter example via plain `run-headless`.",
        ],
    },
    "text_interpolation_update": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the text interpolation update example via plain `run-headless`.",
        ],
    },
    "timer": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the timer example via plain `run-headless`.",
        ],
    },
    "while_function_call": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke boots the WHILE plus function-call example via plain `run-headless`.",
        ],
    },
    "circle_drawer": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the circle drawer example and renders the initial count, with narrow headless support for `List/remove_last` and SVG host nodes.",
        ],
    },
    "crud": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the CRUD example and renders the initial people list after adding inline `WHILE` arm commas, deterministic `Ulid/generate()`, and narrower scoped-subscriber filtering.",
        ],
    },
    "fibonacci": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now renders the expected Fibonacci value after adding scoped `Stream/pulses()` plus scoped `Stream/skip` runtime support.",
        ],
    },
    "hw_examples": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 carries an explicit local correction for the malformed imported `serialadder.bn` source via `examples/upstream_overrides/hw_examples/serialadder.bn` so the HDL corpus can continue through parser/HIR/Flow verification.",
            "This example bucket is still `PARTIAL`, not `DONE`, because `hw_examples` is a directory of HDL-oriented programs rather than one runnable headless/terminal playground entrypoint.",
        ],
    },
    "latest": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the standalone latest example, and focused headless tests cover initial seeding plus both button-update paths.",
        ],
    },
    "layers": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the layered layout example and renders the stacked card labels in the headless host.",
        ],
    },
    "list_retain_count": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the List/retain count example, and focused headless tests cover reactive count updates after enter.",
        ],
    },
    "list_retain_reactive": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the reactive List/retain example, and focused headless tests cover filter toggling semantics.",
        ],
    },
    "then": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the standalone THEN example with scoped timer initialization deferred during global startup.",
        ],
    },
    "todo_mvc_physical": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots RUN.bn through the scene-root path with narrow `Scene/Element/*` and physical host shims.",
        ],
    },
    "when": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the standalone WHEN example with scoped timer initialization deferred during global startup.",
        ],
    },
    "while": {
        "status": "PARTIAL",
        "notes": [
            "Phase 10 headless smoke now boots the standalone WHILE example with scoped timer initialization deferred during global startup.",
        ],
    },
}

TERMINAL_GRID_EVIDENCE: dict[str, dict[str, object]] = {
    "counter": {
        "status": "DONE",
        "notes": [
            "Phase 8 terminal-grid verification replays the counter script and compares the snapshot in tests/terminal_grid/counter.expected.",
        ],
    },
    "interval": {
        "status": "DONE",
        "notes": [
            "Phase 8 terminal-grid verification advances virtual time by 2s and compares the snapshot in tests/terminal_grid/interval.expected.",
        ],
    },
    "cells": {
        "status": "DONE",
        "notes": [
            "Phase 8 terminal-grid verification compares the deterministic spreadsheet snapshot in tests/terminal_grid/cells.expected.",
        ],
    },
    "todo_mvc": {
        "status": "DONE",
        "notes": [
            "Phase 8 terminal-grid verification compares the deterministic TodoMVC snapshot in tests/terminal_grid/todo_mvc.expected.",
        ],
    },
}

REPO_P0_HEADLESS_EVIDENCE: dict[str, dict[str, object]] = {
    "pong": {
        "status": "DONE",
        "notes": [
            "Phase 7 headless verification replays the repo-authored Pong lane via tests/examples/pong_sequence.json and expects a scored rally.",
        ],
    },
    "arkanoid": {
        "status": "DONE",
        "notes": [
            "Phase 7 headless verification replays the repo-authored Arkanoid lane via tests/examples/arkanoid_sequence.json and expects one brick break.",
        ],
    },
}

REPO_P0_TERMINAL_GRID_EVIDENCE: dict[str, dict[str, object]] = {
    "pong": {
        "status": "DONE",
        "notes": [
            "Phase 8 terminal-grid verification replays the repo-authored Pong lane and compares the snapshot in tests/terminal_grid/pong.expected.",
        ],
    },
    "arkanoid": {
        "status": "DONE",
        "notes": [
            "Phase 8 terminal-grid verification replays the repo-authored Arkanoid lane and compares the snapshot in tests/terminal_grid/arkanoid.expected.",
        ],
    },
}

PERSISTENCE_EVIDENCE: dict[str, dict[str, object]] = {
    "counter": {
        "status": "DONE",
        "script": "tests/examples/counter_sequence.json",
        "notes": [
            "Scripted Phase 6 CLI persistence verification is implemented with --script and --expect-text.",
        ],
    },
    "counter_hold": {
        "status": "DONE",
        "script": "tests/examples/counter_hold_sequence.json",
        "notes": [
            "Scripted Phase 6 CLI persistence verification covers scalar HOLD restore/clear-state behavior.",
        ],
    },
    "interval": {
        "status": "PARTIAL",
        "script": None,
        "notes": [
            "Headless timer behavior and clear-state infrastructure are green, but there is no example-specific scripted persistence replay yet.",
        ],
    },
    "interval_hold": {
        "status": "PARTIAL",
        "script": None,
        "notes": [
            "Headless HOLD/timer behavior and clear-state infrastructure are green, but there is no example-specific scripted persistence replay yet.",
        ],
    },
}

BROWSER_SMOKE_EVIDENCE: dict[str, dict[str, object]] = {
    "counter": {
        "status": "DONE",
        "notes": [
            "Phase 11 browser smoke runs the generated bundle through tools/browser_smoke.mjs and proves click persistence plus clear-state semantics with IndexedDB-style storage.",
        ],
    },
    "interval": {
        "status": "DONE",
        "notes": [
            "Phase 11 browser smoke runs the generated bundle through tools/browser_smoke.mjs and proves deterministic 2s virtual-time rendering.",
        ],
    },
    "todo_mvc": {
        "status": "DONE",
        "notes": [
            "Phase 11 browser smoke boots the browser TodoMVC host and covers add/toggle/filter/clear-completed persistence semantics.",
            "Phase 12 visual verification compares the rendered browser TodoMVC screenshot against the imported reference image and records a passing similarity score plus diff artifact under tests/browser_visual/.",
        ],
    },
}

FEATURE_PATTERNS: dict[str, re.Pattern[str]] = {
    "FUNCTION": re.compile(r"\bFUNCTION\b"),
    "BLOCK": re.compile(r"\bBLOCK\b"),
    "LIST": re.compile(r"\bLIST(?:\s|\[)"),
    "MAP": re.compile(r"\bMAP\b"),
    "LINK": re.compile(r"\bLINK\b"),
    "LATEST": re.compile(r"\bLATEST\b"),
    "HOLD": re.compile(r"\bHOLD\b"),
    "THEN": re.compile(r"\bTHEN\b"),
    "WHEN": re.compile(r"\bWHEN\b"),
    "WHILE": re.compile(r"\bWHILE\b"),
    "SKIP": re.compile(r"\bSKIP\b"),
    "PASS": re.compile(r"\bPASS\b"),
    "PASSED": re.compile(r"\bPASSED\b"),
    "FLUSH": re.compile(r"\bFLUSH\b"),
    "PULSES": re.compile(r"\bPULSES\b"),
    "UNPLUGGED": re.compile(r"\bUNPLUGGED\b"),
    "NoElement": re.compile(r"\bNoElement\b"),
    "TEXT": re.compile(r"\bTEXT\b"),
    "BITS": re.compile(r"\bBITS(?:\s|\[)"),
    "BYTES": re.compile(r"\bBYTES(?:\s|\[)"),
    "MEMORY": re.compile(r"\bMEMORY(?:\s|\[)"),
    "DRAIN": re.compile(r"\bDRAIN\b"),
    "pipe": re.compile(r"\|>"),
    "wildcard": re.compile(r"\b__\b"),
    "arrow": re.compile(r"=>"),
    "spread": re.compile(r"\.\.\."),
    "optional_access": re.compile(r"\?\.|\w\?"),
    "tagged_object": re.compile(r"\b[A-Z][A-Za-z0-9_]*\[[^\]]*"),
    "dynamic_list": re.compile(r"\bLIST\s*\{"),
    "static_list": re.compile(r"\bLIST\s*\[[^\]]+\]\s*\{"),
}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in {"sync", "verify"}:
        print(
            "usage: python3 tools/corpus.py [sync|verify] [--boon-zig-bin <path>] [--parse-only]",
            file=sys.stderr,
        )
        return 2

    command = sys.argv[1]
    boon_zig_bin, parse_only = parse_options(sys.argv[2:])

    ensure_upstream_ready()

    if command == "sync":
        sync_examples()
        write_fixtures(collect_parse_results(boon_zig_bin))
        return 0

    return verify(boon_zig_bin, parse_only)


def parse_options(args: list[str]) -> tuple[Path | None, bool]:
    boon_zig_bin: Path | None = None
    parse_only = False

    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--boon-zig-bin":
            if index + 1 >= len(args):
                raise SystemExit("--boon-zig-bin requires a path")
            boon_zig_bin = Path(args[index + 1])
            index += 2
            continue
        if arg == "--parse-only":
            parse_only = True
            index += 1
            continue
        raise SystemExit(f"unknown argument: {arg}")

    return boon_zig_bin, parse_only


def ensure_upstream_ready() -> None:
    if not UPSTREAM_ROOT.is_dir():
        UPSTREAM_ROOT.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["git", "clone", UPSTREAM_URL, str(UPSTREAM_ROOT)],
            cwd=REPO_ROOT,
            check=True,
        )

    if not UPSTREAM_EXAMPLES.is_dir():
        raise SystemExit(f"missing upstream examples tree after clone: {UPSTREAM_EXAMPLES}")

    pinned_available = subprocess.run(
        ["git", "cat-file", "-e", f"{PINNED_COMMIT}^{{commit}}"],
        cwd=UPSTREAM_ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0
    if not pinned_available:
        subprocess.run(
            ["git", "fetch", "--all", "--tags", "--prune"],
            cwd=UPSTREAM_ROOT,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    subprocess.run(
        ["git", "checkout", PINNED_COMMIT],
        cwd=UPSTREAM_ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    commit = (
        subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=UPSTREAM_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        .stdout.strip()
    )
    if commit != PINNED_COMMIT:
        raise SystemExit(
            f"expected upstream commit {PINNED_COMMIT}, found {commit}"
        )


def sync_examples() -> None:
    if IMPORTED_EXAMPLES.exists():
        shutil.rmtree(IMPORTED_EXAMPLES)
    shutil.copytree(UPSTREAM_EXAMPLES, IMPORTED_EXAMPLES)
    apply_overrides()


def apply_overrides() -> None:
    if not UPSTREAM_OVERRIDES.is_dir():
        return
    for override in sorted(UPSTREAM_OVERRIDES.rglob("*")):
        if override.is_dir():
            continue
        relative = override.relative_to(UPSTREAM_OVERRIDES)
        destination = IMPORTED_EXAMPLES / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(override, destination)


def verify(boon_zig_bin: Path | None, parse_only: bool) -> int:
    parse_results = collect_parse_results(boon_zig_bin)
    expected_manifest, expected_syntax_inventory, expected_feature_matrix, expected_spec_gaps = (
        render_outputs(parse_results)
    )

    failures: list[str] = []
    if not IMPORTED_EXAMPLES.is_dir():
        failures.append(f"missing imported tree: {IMPORTED_EXAMPLES}")
    else:
        source_files = relative_files(UPSTREAM_EXAMPLES)
        imported_files = relative_files(IMPORTED_EXAMPLES)
        override_files = relative_files(UPSTREAM_OVERRIDES) if UPSTREAM_OVERRIDES.is_dir() else set()
        expected_imported_files = source_files | override_files
        if expected_imported_files != imported_files:
            missing = sorted(expected_imported_files - imported_files)
            extra = sorted(imported_files - expected_imported_files)
            if missing:
                failures.append("missing imported files:\n" + "\n".join(missing[:50]))
            if extra:
                failures.append("unexpected imported files:\n" + "\n".join(extra[:50]))
        else:
            for rel in sorted(expected_imported_files):
                expected_path = override_source_for(rel)
                if file_digest(expected_path) != file_digest(IMPORTED_EXAMPLES / rel):
                    failures.append(f"content mismatch for {rel}")
                    break

    expected_files = {
        FIXTURES_DIR / "corpus_manifest.json": expected_manifest,
        FIXTURES_DIR / "syntax_inventory.json": expected_syntax_inventory,
        FIXTURES_DIR / "feature_matrix.md": expected_feature_matrix,
        FIXTURES_DIR / "spec_gaps.md": expected_spec_gaps,
    }
    for path, expected_text in expected_files.items():
        if not path.is_file():
            failures.append(f"missing fixture: {path.relative_to(REPO_ROOT)}")
            continue
        actual = path.read_text()
        if actual != expected_text:
            failures.append(f"out-of-date fixture: {path.relative_to(REPO_ROOT)}")

    if parse_only and parse_results is None:
        failures.append("parse-only verification requires --boon-zig-bin")

    if failures:
        print("verify-corpus failed", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        print("run: zig build sync-corpus", file=sys.stderr)
        return 1

    if parse_results is not None:
        blocked = [
            result for result in parse_results.values() if not result["ok"]
        ]
        if blocked:
            print(f"verify-corpus ok ({len(blocked)} parser blockers recorded in fixtures)")
            return 0

    print("verify-corpus ok")
    return 0


def write_fixtures(parse_results: dict[str, dict] | None) -> None:
    manifest, syntax_inventory, feature_matrix, spec_gaps = render_outputs(parse_results)
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    (FIXTURES_DIR / "corpus_manifest.json").write_text(manifest)
    (FIXTURES_DIR / "syntax_inventory.json").write_text(syntax_inventory)
    (FIXTURES_DIR / "feature_matrix.md").write_text(feature_matrix)
    (FIXTURES_DIR / "spec_gaps.md").write_text(spec_gaps)


def render_outputs(parse_results: dict[str, dict] | None) -> tuple[str, str, str, str]:
    manifest_obj = build_manifest(parse_results)
    syntax_inventory_obj = build_syntax_inventory()
    feature_matrix_text = build_feature_matrix(manifest_obj["examples"], parse_results is not None)
    spec_gaps_text = build_spec_gaps()
    manifest = json.dumps(manifest_obj, indent=2, sort_keys=False) + "\n"
    syntax_inventory = json.dumps(syntax_inventory_obj, indent=2, sort_keys=False) + "\n"
    return manifest, syntax_inventory, feature_matrix_text, spec_gaps_text


def build_manifest(parse_results: dict[str, dict] | None) -> dict:
    example_dirs = sorted(
        p for p in UPSTREAM_EXAMPLES.iterdir() if p.is_dir()
    )
    entries = [build_example_entry(path, parse_results) for path in example_dirs]
    root_files = []
    for path in sorted(UPSTREAM_EXAMPLES.iterdir()):
        if not path.is_file():
            continue
        rel = str(path.relative_to(UPSTREAM_EXAMPLES))
        root_info = {"path": rel}
        if parse_results is not None and path.suffix == ".bn":
            parse_key = str((IMPORTED_EXAMPLES / rel).relative_to(REPO_ROOT))
            parse_result = parse_results.get(parse_key)
            if parse_result is None:
                root_info["parser_status"] = STATUS
                root_info["parse_message"] = f"missing parse result for {parse_key}"
            else:
                root_info["parser_status"] = "DONE" if parse_result["ok"] else "BLOCKED"
                if not parse_result["ok"]:
                    root_info["parse_message"] = parse_result["message"]
        root_files.append(root_info)
    return {
        "generated_by": "tools/corpus.py",
        "source_repo": {
            "url": UPSTREAM_URL,
            "commit": PINNED_COMMIT,
            "example_root": str(UPSTREAM_EXAMPLES.relative_to(REPO_ROOT)),
            "imported_root": str(IMPORTED_EXAMPLES.relative_to(REPO_ROOT)),
        },
        "planned_p0_repo_examples": [
            build_repo_p0_entry(name, parse_results)
            for name in PLANNED_TERMINAL_P0
        ],
        "shared_root_files": root_files,
        "examples": entries,
    }


def build_example_entry(example_dir: Path, parse_results: dict[str, dict] | None) -> dict:
    rel = example_dir.relative_to(UPSTREAM_EXAMPLES)
    files = sorted(
        str(path.relative_to(example_dir))
        for path in example_dir.rglob("*")
        if path.is_file()
    )
    bn_files = [path for path in files if path.endswith(".bn")]
    expected_files = [path for path in files if path.endswith(".expected")]
    persistence_cases = count_persistence_cases(example_dir, expected_files)
    reference_assets = [
        path
        for path in files
        if path.endswith(".png")
        or path.endswith(".svg")
        or path.endswith(".json")
    ]
    docs = [path for path in files if path.endswith(".md")]
    helper_files = [
        path
        for path in files
        if path.endswith(".sh") or path.endswith(".sv")
    ]

    category = "playground"
    if rel.parts[0] == "hw_examples":
        category = "hardware"
    elif rel.parts[0] == "todo_mvc_physical":
        category = "physical"

    blockers = []
    notes = []
    if not bn_files:
        blockers.append("No .bn source file found under imported example directory.")
    if example_dir.name == "todo_mvc_physical":
        notes.extend(
            [
                "Physical renderer work is tracked separately; import includes docs, themes, assets, BUILD.bn, and RUN.bn.",
                "Model/cut(from, remove) remains an internal renderer TODO in upstream docs.",
            ]
        )
    if example_dir.name == "hw_examples":
        notes.extend(
            [
                "Directory mixes multiple HDL-oriented .bn/.sv programs and analysis docs.",
                "Repo currently carries an explicit local correction in `examples/upstream_overrides/hw_examples/serialadder.bn` so parser/HIR/Flow verification can proceed despite the malformed imported upstream source.",
            ]
        )

    parser_status = STATUS
    overall_status = STATUS
    runtime_status = STATUS
    persistence_status = STATUS
    persistence_script: str | None = None
    if parse_results is not None and bn_files:
        example_results = []
        missing_parse_keys = []
        for rel_path in bn_files:
            parse_key = str((IMPORTED_EXAMPLES / rel / rel_path).relative_to(REPO_ROOT))
            parse_result = parse_results.get(parse_key)
            if parse_result is None:
                missing_parse_keys.append(parse_key)
                continue
            example_results.append(parse_result)
        if missing_parse_keys:
            blockers.extend(
                f"missing parse result for {parse_key}"
                for parse_key in missing_parse_keys
            )
        failed = [result for result in example_results if not result["ok"]]
        if failed:
            parser_status = "BLOCKED"
            overall_status = "BLOCKED"
            blockers.extend(
                f"parser: {result['path']} :: {result['message']}"
                for result in failed
            )
        elif example_results:
            parser_status = "DONE"
            overall_status = "PARTIAL"

    runtime_evidence = HEADLESS_RUNTIME_EVIDENCE.get(example_dir.name)
    if runtime_evidence is not None:
        runtime_status = str(runtime_evidence["status"])
        notes.extend(runtime_evidence["notes"])
        if runtime_status == "BLOCKED":
            overall_status = "BLOCKED"

    terminal_evidence = TERMINAL_GRID_EVIDENCE.get(example_dir.name)
    terminal_status = STATUS
    if terminal_evidence is not None:
        terminal_status = str(terminal_evidence["status"])
        notes.extend(terminal_evidence["notes"])
    elif runtime_evidence is not None:
        if str(runtime_evidence["status"]) == "PARTIAL":
            terminal_status = "PARTIAL"
            notes.append(
                "Phase 10 has headless runtime evidence for this example, but no terminal-grid snapshot/projection is recorded yet."
            )
        elif str(runtime_evidence["status"]) == "BLOCKED":
            terminal_status = "BLOCKED"
            notes.append(
                "Terminal projection is blocked behind the current headless/runtime blocker for this example."
            )

    persistence_evidence = PERSISTENCE_EVIDENCE.get(example_dir.name)
    if persistence_cases != 0:
        if persistence_evidence is not None:
            persistence_status = str(persistence_evidence["status"])
            persistence_script = persistence_evidence["script"]
            notes.extend(persistence_evidence["notes"])
        else:
            notes.append(
                "Imported .expected file(s) declare persistence behavior, but repo-side scripted/example-specific persistence verification is not recorded yet."
            )

    browser_evidence = BROWSER_SMOKE_EVIDENCE.get(example_dir.name)
    browser_status = STATUS
    if browser_evidence is not None:
        browser_status = str(browser_evidence["status"])
        notes.extend(browser_evidence["notes"])
    elif runtime_evidence is not None:
        if str(runtime_evidence["status"]) == "BLOCKED":
            browser_status = "BLOCKED"
            notes.append(
                "Browser work is blocked behind the current runtime/headless blocker for this example."
            )
        else:
            browser_status = "PARTIAL"
            notes.append(
                "Phase 13 records browser status for this example, but no browser smoke/reference comparison is implemented yet."
            )

    return {
        "name": example_dir.name,
        "relative_path": str(rel),
        "source_path": str(example_dir.relative_to(REPO_ROOT)),
        "imported_path": str((IMPORTED_EXAMPLES / rel).relative_to(REPO_ROOT)),
        "category": category,
        "hard_gate": example_dir.name in P0_UPSTREAM,
        "status": overall_status,
        "parser_status": parser_status,
        "runtime_status": runtime_status,
        "persistence_status": persistence_status,
        "persistence_cases": persistence_cases,
        "persistence_script": persistence_script,
        "terminal_status": terminal_status,
        "browser_status": browser_status,
        "bn_files": bn_files,
        "expected_files": expected_files,
        "reference_assets": reference_assets,
        "helper_files": helper_files,
        "docs": docs,
        "all_files": files,
        "blockers": sorted(dict.fromkeys(blockers)),
        "notes": notes,
    }


def build_repo_p0_entry(name: str, parse_results: dict[str, dict] | None) -> dict:
    path = REPO_ROOT / "examples" / "terminal" / name / f"{name}.bn"
    entry = {
        "name": name,
        "category": "terminal_only",
        "hard_gate": True,
        "status": STATUS,
        "runtime_status": STATUS,
        "persistence_status": STATUS,
        "terminal_status": STATUS,
        "browser_status": STATUS,
        "notes": ["Repo-authored terminal example tracked outside the upstream corpus."],
    }
    if path.is_file():
        entry["path"] = str(path.relative_to(REPO_ROOT))
        if parse_results is not None:
            result = parse_results.get(str(path.relative_to(REPO_ROOT)))
            if result is not None:
                entry["parser_status"] = "DONE" if result["ok"] else "BLOCKED"
                entry["status"] = "PARTIAL" if result["ok"] else "BLOCKED"
                if not result["ok"]:
                    entry["notes"].append(result["message"])
            else:
                entry["parser_status"] = STATUS
        else:
            entry["parser_status"] = STATUS

    runtime_evidence = REPO_P0_HEADLESS_EVIDENCE.get(name)
    if runtime_evidence is not None:
        entry["runtime_status"] = str(runtime_evidence["status"])
        entry["notes"].extend(runtime_evidence["notes"])
        if runtime_evidence["status"] == "BLOCKED":
            entry["status"] = "BLOCKED"
        if runtime_evidence["status"] == "DONE" and entry.get("parser_status") == "DONE":
            entry["status"] = "PARTIAL"
        blockers = runtime_evidence.get("blockers")
        if blockers is not None:
            entry["blockers"] = list(blockers)

    terminal_evidence = REPO_P0_TERMINAL_GRID_EVIDENCE.get(name)
    if terminal_evidence is not None:
        entry["terminal_status"] = str(terminal_evidence["status"])
        entry["notes"].extend(terminal_evidence["notes"])
    entry["browser_status"] = "PARTIAL"
    entry["notes"].append(
        "Repo-authored terminal example tracked as browser PARTIAL-by-design; no browser host lane is implemented for it."
    )
    return entry


def build_syntax_inventory() -> dict:
    scan_files = list(UPSTREAM_EXAMPLES.rglob("*.bn"))
    scan_files.extend(UPSTREAM_ROOT.glob("docs/language/**/*.md"))
    scan_files.extend(UPSTREAM_EXAMPLES.rglob("*.md"))

    detections = {}
    for name, pattern in FEATURE_PATTERNS.items():
        matches = []
        for path in scan_files:
            text = path.read_text(errors="replace")
            if pattern.search(text):
                matches.append(str(path.relative_to(REPO_ROOT)))
            if len(matches) >= 5:
                break
        detections[name] = {
            "detected": bool(matches),
            "sample_paths": matches,
        }

    drain_detected = detections["DRAIN"]["detected"]
    return {
        "source_commit": PINNED_COMMIT,
        "scanned_file_count": len(scan_files),
        "detections": detections,
        "summary": {
            "detection_policy": "Presence is based on regex scans over upstream example .bn files and related docs.",
            "drain_status": (
                "No exact DRAIN token found in scanned upstream example/docs sources."
                if not drain_detected
                else "Exact DRAIN token found in scanned upstream sources."
            ),
        },
    }


def build_feature_matrix(entries: list[dict], parser_statuses_present: bool) -> str:
    lines = [
        "# Feature Matrix",
        "",
        f"- Source commit: `{PINNED_COMMIT}`",
        (
            "- Parser status reflects the current `boon-zig parse` pass over imported `.bn` files."
            if parser_statuses_present
            else "- Status values remain `NOT_STARTED` until parser/runtime phases land."
        ),
        "- `P0` marks the upstream hard-gate examples from `PLAN.md`.",
        "",
        "| Example | Category | P0 | Parser | Persist | persist cases | bn | expected | refs/docs | HOLD | LATEST | WHEN | WHILE | THEN | LINK | LIST | TEXT | FLUSH | PULSES |",
        "| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for entry in entries:
        features = scan_entry_features(entry)
        refs_docs = len(entry["reference_assets"]) + len(entry["docs"])
        lines.append(
            "| {name} | {category} | {p0} | {parser_status} | {persistence_status} | {persistence_cases} | {bn} | {expected} | {refs_docs} | {HOLD} | {LATEST} | {WHEN} | {WHILE} | {THEN} | {LINK} | {LIST} | {TEXT} | {FLUSH} | {PULSES} |".format(
                name=entry["name"],
                category=entry["category"],
                p0="yes" if entry["hard_gate"] else "no",
                parser_status=entry["parser_status"],
                persistence_status=entry["persistence_status"],
                persistence_cases=entry["persistence_cases"],
                bn=len(entry["bn_files"]),
                expected=len(entry["expected_files"]),
                refs_docs=refs_docs,
                **features,
            )
        )
    return "\n".join(lines) + "\n"


def scan_entry_features(entry: dict) -> dict[str, str]:
    source_dir = REPO_ROOT / entry["source_path"]
    text_parts = []
    for rel in entry["bn_files"]:
        text_parts.append((source_dir / rel).read_text(errors="replace"))
    text = "\n".join(text_parts)
    return {
        name: ("yes" if pattern.search(text) else "no")
        for name, pattern in {
            "HOLD": FEATURE_PATTERNS["HOLD"],
            "LATEST": FEATURE_PATTERNS["LATEST"],
            "WHEN": FEATURE_PATTERNS["WHEN"],
            "WHILE": FEATURE_PATTERNS["WHILE"],
            "THEN": FEATURE_PATTERNS["THEN"],
            "LINK": FEATURE_PATTERNS["LINK"],
            "LIST": FEATURE_PATTERNS["LIST"],
            "TEXT": FEATURE_PATTERNS["TEXT"],
            "FLUSH": FEATURE_PATTERNS["FLUSH"],
            "PULSES": FEATURE_PATTERNS["PULSES"],
        }.items()
    }


def build_spec_gaps() -> str:
    exact_drain = exact_token_paths("DRAIN")
    model_cut = exact_phrase_paths("Model/cut")
    optional_access = exact_phrase_paths("?")
    lines = [
        "# Spec Gaps",
        "",
        f"- Source commit: `{PINNED_COMMIT}`",
        "",
        "## DRAIN",
    ]
    if exact_drain:
        lines.append(f"- Found exact `DRAIN` token in: {', '.join(exact_drain[:5])}")
    else:
        lines.append(
            "- No exact `DRAIN` token was found in scanned upstream example/docs sources. Reserve the keyword in the lexer/parser and emit a spec-gap diagnostic until better evidence appears."
        )

    lines.extend(
        [
            "",
            "## FLUSH And PULSES",
            "- `FLUSH` is documented in `docs/language/ERROR_HANDLING.md` and referenced in `todo_mvc_physical/BUILD.bn`.",
            "- `PULSES` appears in upstream documentation and HDL analysis docs, but not in the imported playground P0 examples yet.",
            "",
            "## todo_mvc_physical",
            "- Imported assets include `RUN.bn`, `BUILD.bn`, theme files, icons, and research docs.",
            (
                "- `Model/cut(from, remove)` evidence appears in: "
                + ", ".join(model_cut[:5])
            ),
            "- Treat physical rendering as explicitly tracked but not implemented during early parser/runtime phases.",
            "",
            "## Layout And Corpus Quirks",
            "- Upstream examples include shared root files `reference_metadata.json` and `checkbox_test.bn` at the examples root in addition to per-example subdirectories.",
            "- `hw_examples` is a directory of multiple HDL-oriented programs rather than a single `.bn` example.",
        ]
    )

    if optional_access:
        lines.extend(
            [
                "",
                "## Optional Access",
                "- `?`/optional access evidence exists in upstream docs and should be tracked for parser work.",
            ]
        )

    return "\n".join(lines) + "\n"


def exact_token_paths(token: str) -> list[str]:
    pattern = re.compile(rf"\\b{re.escape(token)}\\b")
    paths = []
    for path in list(UPSTREAM_EXAMPLES.rglob("*.bn")) + list(UPSTREAM_ROOT.glob("docs/**/*.md")):
        text = path.read_text(errors="replace")
        if pattern.search(text):
            paths.append(str(path.relative_to(REPO_ROOT)))
    return paths


def exact_phrase_paths(phrase: str) -> list[str]:
    paths = []
    for path in list(UPSTREAM_EXAMPLES.rglob("*")) + list(UPSTREAM_ROOT.glob("docs/**/*.md")):
        if not path.is_file():
            continue
        text = path.read_text(errors="replace")
        if phrase in text:
            paths.append(str(path.relative_to(REPO_ROOT)))
    return paths


def collect_parse_results(boon_zig_bin: Path | None) -> dict[str, dict] | None:
    if boon_zig_bin is None:
        return None
    if not boon_zig_bin.is_file():
        raise SystemExit(f"missing boon-zig binary: {boon_zig_bin}")

    results: dict[str, dict] = {}
    parse_targets = sorted(IMPORTED_EXAMPLES.rglob("*.bn"))
    for name in PLANNED_TERMINAL_P0:
        candidate = REPO_ROOT / "examples" / "terminal" / name / f"{name}.bn"
        if candidate.is_file():
            parse_targets.append(candidate)

    for path in parse_targets:
        rel = str(path.relative_to(REPO_ROOT))
        completed = subprocess.run(
            [str(boon_zig_bin), "parse", rel],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        combined_output = (completed.stderr + completed.stdout).strip()
        results[rel] = {
            "path": rel,
            "ok": completed.returncode == 0,
            "message": combined_output or "parse failed without output",
        }
    return results


def count_persistence_cases(example_dir: Path, expected_files: list[str]) -> int:
    count = 0
    for rel in expected_files:
        text = (example_dir / rel).read_text(errors="replace")
        count += len(re.findall(r"^\[\[persistence\]\]", text, flags=re.MULTILINE))
    return count


def relative_files(root: Path) -> set[str]:
    return {
        str(path.relative_to(root))
        for path in root.rglob("*")
        if path.is_file()
    }


def override_source_for(relative_path: str) -> Path:
    override = UPSTREAM_OVERRIDES / relative_path
    if override.is_file():
        return override
    return UPSTREAM_EXAMPLES / relative_path


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
