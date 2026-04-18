# Spec Gaps

- Source commit: `c924d9f7d7e1c156604c9377e0487db48c278353`

## DRAIN
- No exact `DRAIN` token was found in scanned upstream example/docs sources. Reserve the keyword in the lexer/parser and emit a spec-gap diagnostic until better evidence appears.

## FLUSH And PULSES
- `FLUSH` is documented in `docs/language/ERROR_HANDLING.md` and referenced in `todo_mvc_physical/BUILD.bn`.
- `PULSES` appears in upstream documentation and HDL analysis docs, but not in the imported playground P0 examples yet.

## todo_mvc_physical
- Imported assets include `RUN.bn`, `BUILD.bn`, theme files, icons, and research docs.
- `Model/cut(from, remove)` evidence appears in: third_party/boon-upstream/playground/frontend/src/examples/todo_mvc_physical/README.md, third_party/boon-upstream/playground/frontend/src/examples/todo_mvc_physical/docs/3D_API_DESIGN.md, third_party/boon-upstream/playground/frontend/src/examples/todo_mvc_physical/docs/PHYSICALLY_BASED_RENDERING.md
- Treat physical rendering as explicitly tracked but not implemented during early parser/runtime phases.

## Layout And Corpus Quirks
- Upstream examples include shared root files `reference_metadata.json` and `checkbox_test.bn` at the examples root in addition to per-example subdirectories.
- `hw_examples` is a directory of multiple HDL-oriented programs rather than a single `.bn` example.

## Optional Access
- `?`/optional access evidence exists in upstream docs and should be tracked for parser work.
