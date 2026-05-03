## Git Safety

- Do not revert, commit, or perform destructive git operations unless the user explicitly tells you to do so.
- Treat commands like `git reset`, `git checkout --`, `git restore`, rebases, force-pushes, and history rewrites as destructive unless the user explicitly requests them.
- If cleanup or rollback seems helpful, stop and ask instead of doing it implicitly.

## Build Validation

- After changing Zig source, do not trust `zig-out/bin/boon-zig` to reflect the latest code unless you explicitly rebuilt and verified that binary for this exact check.
- Prefer `zig build run -- ...` for validation commands during active iteration so the current code is used.
- If you intentionally use `zig-out/bin/boon-zig`, state that choice and why it is safe.

## Example Run Commands

- After any change that affects a Boon example, include two run commands in the final response.
- The first command should be a `cd ...` command so the user can run it from a newly opened terminal window.
- The second command should be the direct run command for the example, for example:
  - `cd /home/martinkavik/repos/boon-zig`
  - `zig build run -- run examples/terminal/cells/cells.bn`

## Tooling Preference

- Use Zig for repo automation, helper scripts, data extraction, and expectation updates.
- Use shell only for simple command orchestration and one-liners.
- Do not use Python in this repo unless the user explicitly asks for it.

## Window Launching

- On this COSMIC desktop, any command, test, script, or tool that opens a
  visible native or browser window must launch the window-creating command
  through `cosmic-background-launch -- <command> [args...]`.
- Keep `cosmic-background-launch` as close as possible to the process that
  actually creates the window so the child inherits
  `COSMIC_BACKGROUND_LAUNCH_ID`. Prior local implementation notes live in
  `~/repos/pop*` and `~/repos/cosmic-comp`.
- Headless browser capture commands that do not create visible windows may stay
  headless, but if they are changed to visible/manual mode, wrap the browser
  process with `cosmic-background-launch --`.

## Raybox Renderer

- Raybox now lives in this repository under `raybox/`. Continue Boon runtime,
  transpiler, playground, and renderer work here instead of in the old
  sibling `raybox-zig` checkout.
- Core Boon runtime/compiler code under `src/` must stay renderer-neutral. It
  may expose generic host/runtime bridges, but it must not import SDL or
  `raybox/`.
- Raybox code may import the local Boon runtime host through `src/root.zig`.
  Plain `zig build ...` commands use this local module; do not pass
  `-Dboon_zig_path` for normal work in this repo.
- Native Raybox uses SDL3 for window/input/timing and 2D rendering. Browser
  Raybox targets use SDL3 through wasm32-emscripten.
- Do not add Sokol, raylib, Dear ImGui, Slang, WebGPU, Dawn, wgpu-native,
  freestanding Wasm, MSDF, 3D modeling, 3D printing, or a general polygon
  boolean library.

Useful Raybox commands:

```sh
zig build run-raybox
zig build bench-raybox-native
zig build verify-raybox-native-events
zig build verify-raybox-examples-native
zig build verify-raybox-physical-native
zig build verify-raybox-text-native
zig build test-raybox
zig build screenshot-raybox-native
```
