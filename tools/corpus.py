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
FIXTURES_DIR = REPO_ROOT / "fixtures"

UPSTREAM_URL = "https://github.com/BoonLang/boon"
PINNED_COMMIT = "c924d9f7d7e1c156604c9377e0487db48c278353"
P0_UPSTREAM = {"counter", "interval", "cells", "todo_mvc", "todo_mvc_physical"}
PLANNED_TERMINAL_P0 = ("pong", "arkanoid")
STATUS = "NOT_STARTED"

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
    if len(sys.argv) != 2 or sys.argv[1] not in {"sync", "verify"}:
        print("usage: python3 tools/corpus.py [sync|verify]", file=sys.stderr)
        return 2

    ensure_upstream_ready()

    if sys.argv[1] == "sync":
        sync_examples()
        write_fixtures()
        return 0

    return verify()


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


def verify() -> int:
    expected_manifest, expected_syntax_inventory, expected_feature_matrix, expected_spec_gaps = (
        render_outputs()
    )

    failures: list[str] = []
    if not IMPORTED_EXAMPLES.is_dir():
        failures.append(f"missing imported tree: {IMPORTED_EXAMPLES}")
    else:
        source_files = relative_files(UPSTREAM_EXAMPLES)
        imported_files = relative_files(IMPORTED_EXAMPLES)
        if source_files != imported_files:
            missing = sorted(source_files - imported_files)
            extra = sorted(imported_files - source_files)
            if missing:
                failures.append("missing imported files:\n" + "\n".join(missing[:50]))
            if extra:
                failures.append("unexpected imported files:\n" + "\n".join(extra[:50]))
        else:
            for rel in sorted(source_files):
                if file_digest(UPSTREAM_EXAMPLES / rel) != file_digest(IMPORTED_EXAMPLES / rel):
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

    if failures:
        print("verify-corpus failed", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        print("run: zig build sync-corpus", file=sys.stderr)
        return 1

    print("verify-corpus ok")
    return 0


def write_fixtures() -> None:
    manifest, syntax_inventory, feature_matrix, spec_gaps = render_outputs()
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    (FIXTURES_DIR / "corpus_manifest.json").write_text(manifest)
    (FIXTURES_DIR / "syntax_inventory.json").write_text(syntax_inventory)
    (FIXTURES_DIR / "feature_matrix.md").write_text(feature_matrix)
    (FIXTURES_DIR / "spec_gaps.md").write_text(spec_gaps)


def render_outputs() -> tuple[str, str, str, str]:
    manifest_obj = build_manifest()
    syntax_inventory_obj = build_syntax_inventory()
    feature_matrix_text = build_feature_matrix(manifest_obj["examples"])
    spec_gaps_text = build_spec_gaps()
    manifest = json.dumps(manifest_obj, indent=2, sort_keys=False) + "\n"
    syntax_inventory = json.dumps(syntax_inventory_obj, indent=2, sort_keys=False) + "\n"
    return manifest, syntax_inventory, feature_matrix_text, spec_gaps_text


def build_manifest() -> dict:
    example_dirs = sorted(
        p for p in UPSTREAM_EXAMPLES.iterdir() if p.is_dir()
    )
    entries = [build_example_entry(path) for path in example_dirs]
    root_files = sorted(
        str(path.relative_to(UPSTREAM_EXAMPLES))
        for path in UPSTREAM_EXAMPLES.iterdir()
        if path.is_file()
    )
    return {
        "generated_by": "tools/corpus.py",
        "source_repo": {
            "url": UPSTREAM_URL,
            "commit": PINNED_COMMIT,
            "example_root": str(UPSTREAM_EXAMPLES.relative_to(REPO_ROOT)),
            "imported_root": str(IMPORTED_EXAMPLES.relative_to(REPO_ROOT)),
        },
        "planned_p0_repo_examples": [
            {
                "name": name,
                "category": "terminal_only",
                "hard_gate": True,
                "status": STATUS,
                "notes": ["Repo-authored terminal example; not present in upstream corpus yet."],
            }
            for name in PLANNED_TERMINAL_P0
        ],
        "shared_root_files": root_files,
        "examples": entries,
    }


def build_example_entry(example_dir: Path) -> dict:
    rel = example_dir.relative_to(UPSTREAM_EXAMPLES)
    files = sorted(
        str(path.relative_to(example_dir))
        for path in example_dir.rglob("*")
        if path.is_file()
    )
    bn_files = [path for path in files if path.endswith(".bn")]
    expected_files = [path for path in files if path.endswith(".expected")]
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
        notes.append("Directory mixes multiple HDL-oriented .bn/.sv programs and analysis docs.")

    return {
        "name": example_dir.name,
        "relative_path": str(rel),
        "source_path": str(example_dir.relative_to(REPO_ROOT)),
        "imported_path": str((IMPORTED_EXAMPLES / rel).relative_to(REPO_ROOT)),
        "category": category,
        "hard_gate": example_dir.name in P0_UPSTREAM,
        "status": STATUS,
        "parser_status": STATUS,
        "runtime_status": STATUS,
        "terminal_status": STATUS,
        "browser_status": STATUS,
        "bn_files": bn_files,
        "expected_files": expected_files,
        "reference_assets": reference_assets,
        "helper_files": helper_files,
        "docs": docs,
        "all_files": files,
        "blockers": blockers,
        "notes": notes,
    }


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


def build_feature_matrix(entries: list[dict]) -> str:
    lines = [
        "# Feature Matrix",
        "",
        f"- Source commit: `{PINNED_COMMIT}`",
        "- Status values remain `NOT_STARTED` until parser/runtime phases land.",
        "- `P0` marks the upstream hard-gate examples from `PLAN.md`.",
        "",
        "| Example | Category | P0 | bn | expected | refs/docs | HOLD | LATEST | WHEN | WHILE | THEN | LINK | LIST | TEXT | FLUSH | PULSES |",
        "| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for entry in entries:
        features = scan_entry_features(entry)
        refs_docs = len(entry["reference_assets"]) + len(entry["docs"])
        lines.append(
            "| {name} | {category} | {p0} | {bn} | {expected} | {refs_docs} | {HOLD} | {LATEST} | {WHEN} | {WHILE} | {THEN} | {LINK} | {LIST} | {TEXT} | {FLUSH} | {PULSES} |".format(
                name=entry["name"],
                category=entry["category"],
                p0="yes" if entry["hard_gate"] else "no",
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


def relative_files(root: Path) -> set[str]:
    return {
        str(path.relative_to(root))
        for path in root.rglob("*")
        if path.is_file()
    }


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
