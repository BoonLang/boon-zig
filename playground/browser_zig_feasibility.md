# Browser Zig Compiler Feasibility

Status for this branch: **evaluated, not integrated**.

The current branch target is Zig `0.17.0-dev.9+046002d1a`. The active
playground path therefore uses the local/edge-compatible Zig fallback exposed by
`/__boon/playground/compile`.

Findings checked on 2026-04-24:

- `zigtools/playground` proves that an in-browser Zig playground is feasible in
  principle and provides compiler/LSP support in WebAssembly.
  Source: https://github.com/zigtools/playground
- The current `zigtools/playground` README requires Zig `0.16.0` for its build,
  while this repo targets a newer 0.17 dev compiler. Vendoring that path here
  would introduce a toolchain mismatch.
- The live Zigtools playground still warns that Zig's self-hosted WebAssembly
  backend is experimental.
  Source: https://playground.zigtools.org/

Decision:

- Keep the browser/editor API stable.
- Ship the local/edge-compatible compile endpoint first.
- Do not vendor a browser Zig compiler blob in this branch until the compiler
  package can be pinned to the repo's Zig version and cached with explicit size
  and latency budgets.

Next browser-Zig step:

- Prototype the Zigtools compiler-worker approach in a separate spike using the
  repo's exact Zig version.
- If that spike cannot produce a maintainable compiler bundle, keep the same
  browser UI/API and deploy the fallback behind an edge/server compiler.
