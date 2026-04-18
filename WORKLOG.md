# WORKLOG

## 2026-04-18

### Phase 0 - Complete

- Started repository bootstrap from `PLAN.md`.
- Switched local Zig toolchain from `0.15.2` to `0.17.0-dev.9+046002d1a` via `/home/martinkavik/zig`.
- Added the initial Zig project skeleton, baseline CLI, build graph, test wiring, `.gitignore`, and directory layout.
- Commands run:
  - `zig version`
  - `zig build`
  - `zig build test`
  - `zig build run -- --help`
- Result: all Phase 0 verification commands passed on Zig `0.17.0-dev.9+046002d1a`.
- Files changed:
  - `build.zig`
  - `build.zig.zon`
  - `.gitignore`
  - `src/`
  - `tests/`
  - `examples/`
  - `fixtures/`
  - `third_party/.gitkeep`
- Risks:
  - Zig `0.17.0-dev` ties package fingerprints to package identity more strictly than expected; custom package naming in `build.zig.zon` will need care until the toolchain stabilizes.

### Phase 1 - Complete

- Added `tools/corpus.py` to clone or reuse the pinned upstream Boon checkout, sync the upstream example tree into `examples/upstream`, and generate the corpus fixtures.
- Imported the upstream corpus from `BoonLang/boon` commit `c924d9f7d7e1c156604c9377e0487db48c278353`.
- Generated:
  - `fixtures/corpus_manifest.json`
  - `fixtures/syntax_inventory.json`
  - `fixtures/feature_matrix.md`
  - `fixtures/spec_gaps.md`
- Commands run:
  - `python3 tools/corpus.py sync`
  - `zig build sync-corpus`
  - `zig build verify-corpus`
- Result: `verify-corpus` passed. The manifest includes every current upstream example directory, shared root files, planned terminal-only P0 examples, P0 hard gates, `todo_mvc` reference assets, and `todo_mvc_physical` TODO tracking.
- Notable findings:
  - Exact `DRAIN` evidence was not found in scanned upstream example/docs sources, so it is tracked as a reserved-spec-gap item.
  - Upstream has layout quirks, including `checkbox_test.bn` and `reference_metadata.json` at the examples root plus the `hw_examples` multi-program directory.
- Next step: begin Phase 2 by implementing the lexer, parser, AST, formatter, and parser-oriented corpus checks on top of the imported examples.
