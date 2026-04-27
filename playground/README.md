# Boon Zig Playground Compile Path

The active playground compiler path on this branch is the local Zig fallback.
It uses the same request/response shape intended for an edge/server compiler:

```text
browser editor
-> Boon parser/lowerer
-> Physical IR
-> generated Zig
-> local Zig compiler fallback
-> native preview output
```

Browser-hosted `zig.wasm` is not integrated yet. The browser playground UI is
served at `index.html?playground=1` and exposes interpreter preview, compile to
Zig, generated Zig inspection, and diagnostics display. The smoke gate for the
active fallback path is:

```sh
zig build test-playground-compile
```

When served through `boon-zig serve-browser`, the UI calls
`/__boon/playground/compile`. That endpoint accepts the editor source, generates
Zig, compiles it through the local Zig fallback, runs the native preview, and
returns generated Zig plus diagnostics in the same JSON shape intended for an
edge/server compiler.

The browser bundle manifest reports the active compiler path under the
`playground` field so the UI/API can keep the same workflow when the compiler
location moves from local fallback to edge/server or browser worker.
