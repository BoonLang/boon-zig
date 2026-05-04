# Genericity Gate

`zig build verify-genericity` is the hard gate for user-authored Boon app support outside the checked-in examples.

The gate uses fixtures under `fixtures/generic_apps/` instead of `examples/upstream/` or the Raybox example registry:

- `source_counter/app.bn` verifies parser, HIR, Flow IR, Physical IR, physical runtime state updates, Zig code generation, and a compiled generated binary.
- `single_document/app.bn` verifies a plain user-authored document can run through the headless/browser served-source render path.
- `multi_module/RUN.bn` plus `multi_module/Widgets.bn` verifies `BoonRuntimeHost` can load and compile arbitrary multi-file projects with module-qualified function calls.

The gate also checks production source for old example-shaped shortcuts: generated `AppState` adapters, source-slot switch dispatch, `Assets`-only module emission, `Theme`-specific module rewrite branches, browser physical-state restrictions, browser example-name host inputs, Raybox app/adapter example-name branches, Raybox projection text heuristics, and shell hint branches keyed by example name.

Run it with:

```sh
zig build verify-genericity
```

For broader coverage, run:

```sh
zig build test
zig build test-codegen-zig
zig build test-raybox
zig build test-browser-smoke
zig build -Dbuild-only=true verify-raybox-examples-native
zig build -Dbuild-only=true verify-raybox-physical-native
```

The remaining example-name references are curated example registries, tests, fixtures, expected-output data, and visual-demo tooling. They must not be used as compiler/runtime dispatch keys for user-authored apps.
