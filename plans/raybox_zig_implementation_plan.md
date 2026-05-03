# Raybox-Zig Implementation Plan

This plan was migrated from the old `raybox-zig` repository into `boon-zig`.
The active Raybox code now lives under `raybox/` in this repository.

This repo exists to build the Zig/SDL/Raybox equivalent of the current Rust Boon playground:

> All upstream Boon playground examples must compile, run, and render through Raybox in both a native window and a browser canvas.

The implementation must not become a generic engine experiment. Keep the stack fixed, implement the required Boon playground behavior, and verify every imported example.

---

## 0. Non-negotiable outcome

The final app is:

```text
boon-playground-raybox
```

It has one UI renderer and one preview renderer:

```text
Boon source project
  -> boon-zig compile/run
  -> DocumentSnapshot or SceneSnapshot
  -> Raybox document adapter
  -> Clay layout
  -> SDL renderer
  -> native window or browser canvas
```

Native and browser must render the same playground shell and the same Boon preview:

```text
native:
  zig build run-raybox

browser:
  zig build run-raybox -Dtarget=wasm32-emscripten
```

The browser preview must not use HTML/DOM rendering. The native preview must not use a separate UI implementation. Both targets use the same Raybox adapter and renderer.

The Boon examples stay Boon programs. Do not manually rewrite examples as Zig widgets.

No green test may be produced by skipping examples, hiding examples, replacing Boon examples with Zig widgets, ignoring LINK events, returning empty snapshots, mutating the corpus manifest into a pass report, or marking unimplemented features as `DONE`. A skipped or unsupported feature must fail verification with an explicit diagnostic.

---

## 1. Fixed v0 technology stack

Use exactly this stack for the first complete implementation:

```text
Language:
  Zig

Platform/app:
  SDL3 through the vendored Zig SDL package

Renderer:
  SDL3 renderer API with CPU-generated 2D geometry

Browser:
  wasm32-emscripten/browser builds through SDL3

Layout:
  Clay

Text:
  FontStash + stb_truetype dynamic bitmap glyph atlas

Rendering:
  CPU-generated 2D geometry + SDL geometry batches
```

### 1.1 Version pins and preconditions

The first implementation must be built and verified against explicit pins. Update these pins deliberately, never implicitly during feature work.

```text
Zig:
  0.17.0-dev.9+046002d1a

Boon corpus:
  BoonLang/boon@c924d9f7d7e1c156604c9377e0487db48c278353

boon-zig:
  Raybox is integrated into this repository and imports the local
  `boon_runtime_host` through `src/root.zig`. Do not pass `-Dboon_zig_path` for
  normal work in this repo.

Clay:
  git commit 0ced4c621fc744e5c575d27c533cee63f7d700ce
  copy this exact clay.h into src/clay/

SDL3 Zig package:
  upstream wrapper: https://github.com/castholm/SDL
  SDL API: 3.4.4
  build.zig.zon dependency URL: git+https://github.com/castholm/SDL.git#c5ba24c694b5d520cdc1d029d8def398690d6894
  build.zig.zon dependency hash: sdl-0.4.2+3.4.4-SDL--kB3pQHKG_4zWG-pH04ZcZZj_IRF7dwMpxNVGwd6

FontStash/stb_truetype:
  FontStash git commit b5ddc9741061343740d85d636d782ed3e07cf7be
  stb git commit 31c1ad37456438565541f4919958214b6e762fb4
  vendor exact headers locally
  local vendored patches are allowed, but must be documented in src/text/README.md

Fonts:
  Inter-Regular.ttf from rsms/inter@e3a3d4c57d5ecc01453a575621882a384c1995a3 (v4.1)
  JetBrainsMono-Regular.ttf from JetBrains/JetBrainsMono@cd5227bd1f61dff3bbd6c814ceaf7ffd95e947d9 (v2.304)
  NotoSans-Regular.ttf from notofonts/latin-greek-cyrillic@cb097900c74b26e6dcab899b4f07b2bc79dd80c4
  vendor these exact TTF files under assets/fonts/ and record their license text in THIRD_PARTY_LICENSES.md
```

The integrated `boon-zig` runtime exposes the structured Raybox runtime bridge
required below. If that API is missing or regresses, fix the generic bridge in
`src/` and keep Raybox in `raybox/`. Do not infer runtime state from private
`boon-zig` internals.

Do not add these before the definition of done passes:

```text
Sokol
raylib
raygui
Dear ImGui
Slang
direct WebGPU
Dawn
wgpu-native
freestanding Wasm
MSDF text
general 3D modeling
3D printing/export
general polygon boolean library
```

This is not because those are bad; it is because this implementation must first finish the Boon playground and the physical TodoMVC example without backend churn.

---

## 2. Source-of-truth corpus

The source of truth is the upstream Rust Boon playground repository at the pinned corpus commit:

```text
BoonLang/boon@c924d9f7d7e1c156604c9377e0487db48c278353
```

The importer reads source files from:

```text
playground/frontend/src/examples/
```

but it selects examples from the Rust playground registry in:

```text
playground/frontend/src/main.rs
```

Import only examples registered in:

```text
EXAMPLE_DATAS
OTHER_EXAMPLE_DATAS
DEBUG_EXAMPLE_DATAS
MULTI_FILE_EXAMPLES
TODO_MVC_PHYSICAL_FILES
```

Do not import non-registry directories for v0, including `hw_examples/`. If upstream contains `.bn` files that are not registered in the playground, write them to the manifest as ignored entries with a concrete reason, not as hidden omissions.

Generate a manifest. The manifest is authoritative. No registered example may be silently skipped.

### 2.1 Current known single-file example groups

The current Rust playground embeds main, other, and debug examples. The generated importer must parse the registry and verify this list at the pinned commit.

```text
minimal
hello_world
interval
interval_hold
counter
complex_counter
counter_hold
fibonacci
layers
shopping_list
pages
todo_mvc

temperature_converter
crud
timer
flight_booker
circle_drawer
cells
cells_dynamic
latest
text_interpolation_update
then
when
while

list_retain_reactive
list_map_external_dep
list_map_block
list_retain_count
list_object_state
list_retain_remove
filter_checkbox_bug
checkbox_test
chained_list_remove_bug
while_function_call
button_hover_test
button_hover_to_click_test
switch_hold_test
```

### 2.2 Current multi-file example

`todo_mvc_physical` is a hard gate. It is not optional and not a placeholder.

The current Rust playground treats it as an 8-file multi-file project:

```text
RUN.bn
BUILD.bn
Generated/Assets.bn
Theme/Theme.bn
Theme/Professional.bn
Theme/Glassmorphism.bn
Theme/Neobrutalism.bn
Theme/Neumorphism.bn
```

Also import its supporting directories:

```text
assets/icons/
docs/
todo_mvc_physical.expected
README.md
```

The imported project must preserve relative paths exactly.

For every selected example, copy all files that belong to that example: `.bn`, `.expected`, reference images, metadata JSON, helper scripts, docs, and asset directories. For ignored upstream entries such as `hw_examples/` and the root-level `checkbox_test.bn`, record:

```json
{
  "path": "hw_examples/",
  "status": "IGNORED",
  "reason": "not registered in Rust playground example registry for v0"
}
```

### 2.3 Manifest format

Generate:

```text
fixtures/corpus_manifest.json
src/playground/generated_example_registry.zig
```

`fixtures/corpus_manifest.json` is static imported source-of-truth metadata. It must not be mutated by verification commands. Each imported example entry must include:

```json
{
  "name": "todo_mvc_physical",
  "kind": "multi_file",
  "source_commit": "c924d9f7d7e1c156604c9377e0487db48c278353",
  "registry_section": "MULTI_FILE_EXAMPLES",
  "entry_file": "RUN.bn",
  "files": [
    "RUN.bn",
    "BUILD.bn",
    "Generated/Assets.bn",
    "Theme/Theme.bn",
    "Theme/Professional.bn",
    "Theme/Glassmorphism.bn",
    "Theme/Neobrutalism.bn",
    "Theme/Neumorphism.bn"
  ],
  "expected": "todo_mvc_physical.expected",
  "assets": [
    "assets/icons/checkbox_active.svg",
    "assets/icons/checkbox_completed.svg"
  ],
  "ignored": false,
  "notes": ""
}
```

Ignored upstream entries are source metadata too:

```json
{
  "path": "hw_examples/",
  "source_commit": "c924d9f7d7e1c156604c9377e0487db48c278353",
  "ignored": true,
  "notes": "not registered in Rust playground example registry for v0"
}
```

Generated verification results go only to:

```text
zig-out/reports/example_status_native.json
zig-out/reports/example_status_web.json
zig-out/reports/physical_visual_native.json
zig-out/reports/physical_visual_web.json
```

Report entries use these statuses:

```text
NOT_STARTED
PARTIAL
BLOCKED
DONE
```

A release requires every non-ignored imported example to be `DONE` in the generated native and web reports for parser, runtime, renderer, native window, and browser canvas.

---

## 3. Repository layout

Use this structure:

```text
raybox-zig/
  AGENTS.md
  build.zig
  build.zig.zon

  assets/
    fonts/
      Inter-Regular.ttf
      JetBrainsMono-Regular.ttf
      NotoSans-Regular.ttf

  fixtures/
    corpus_manifest.json
    expected_action_schema.json
    physical_visual_spec.json

  examples/
    upstream/
      minimal/
      hello_world/
      ...
      todo_mvc_physical/

  src/
    main.zig

    app/
      app.zig
      frame_stats.zig
      input.zig
      time.zig

    boon_adapter/
      boon_runtime_host.zig
      document_snapshot.zig
      document_adapter.zig
      style_resolver.zig
      module_project.zig

    playground/
      playground_app.zig
      example_registry.zig
      project_files.zig
      source_editor.zig
      preview_panel.zig
      expected_runner.zig
      semantic_tree.zig
      persistence.zig
      router.zig

    raybox/
      raybox.zig
      ui.zig
      theme.zig
      widgets.zig
      input_model.zig
      custom_commands.zig

    clay/
      clay_bridge.zig
      clay_impl.c
      clay_config.h
      clay.h

    render/
      renderer.zig
      batcher.zig
      geometry.zig
      rounded_rect.zig
      border.zig
      shadows.zig
      images.zig
      svg_minimal.zig
      colors.zig
      oklch.zig

    text/
      font_manager.zig
      fontstash_backend.zig
      text_measure.zig
      fontstash.h
      stb_truetype.h

    assets/
      asset_loader.zig
      data_uri.zig

    tools/
      import_upstream.zig
      generate_example_registry.zig
      verify_corpus.zig
      verify_text.zig
      verify_examples.zig
      verify_physical_visual.zig
```

Raybox must not implement the Boon parser/runtime. It consumes the local
`boon-zig` runtime/compiler modules through the root build graph.

Plain `zig build ...` commands in `boon-zig` use the local runtime host
automatically. Do not reintroduce a separate `boon_zig` dependency pin for
normal integrated work.

If the required `boon-zig` API is not present, add a small interface proposal in `src/boon_adapter/boon_runtime_host.zig` and fail clearly at compile time. Do not duplicate runtime semantics inside Raybox.

---

## 4. Build commands

Implement these commands:

```bash
zig build run-raybox
zig build run-raybox -Dtarget=wasm32-emscripten
zig build run-raybox
zig build run-raybox -Dtarget=wasm32-emscripten

zig build import-upstream
zig build generate-example-registry
zig build verify-corpus

zig build verify-raybox-text-native
zig build verify-raybox-text-web

zig build verify-raybox-examples-native
zig build verify-raybox-examples-web

zig build verify-raybox-physical-native
zig build verify-raybox-physical-web

zig build test
```

`run-raybox -Dtarget=wasm32-emscripten` must build a web app and serve or open it using the SDL3/Emscripten browser path.

For web builds, use SDL3 on Emscripten. Do not attempt `wasm32-freestanding`.
The browser target defaults to `ReleaseFast` when no explicit `-Doptimize` is
provided; wasm Debug startup is too slow for the interactive smoke budget.

Example, text, and physical verifier commands accept:

```bash
-Dexample=<example-name>
```

`verify-examples-*` and `verify-physical-*` also accept:

```bash
-Dbuild-only=true
```

`-Dbuild-only=true` runs import, `BUILD.bn` execution if present, module resolution, compile, and snapshot creation, but does not execute interactive expected actions.

Examples:

```bash
zig build verify-raybox-examples-native -Dexample=todo_mvc_physical -Dbuild-only=true
zig build verify-raybox-examples-web -Dexample=todo_mvc_physical -Dbuild-only=true
```

---

## 5. App lifecycle

`src/main.zig` contains only the SDL setup/event loop and delegates to `PlaygroundApp`.

```zig
while (running) {
    pollSdlEvents();
    app.frame();
}
```

`PlaygroundApp` owns:

```zig
pub const PlaygroundApp = struct {
    allocator: std.mem.Allocator,

    raybox: Raybox,
    renderer: Renderer,
    clay: ClayBridge,
    fonts: FontManager,
    assets: AssetLoader,

    input: InputState,
    project: ProjectFiles,
    examples: ExampleRegistry,
    runtime: BoonRuntimeHost,
    preview: PreviewPanel,
    editor: SourceEditor,
    persistence: PersistStore,

    frame_stats: FrameStats,
};
```

Per-frame order:

```text
1. collect SDL input events
2. update SDL text-input/IME state when focus changes
3. update playground shell state
4. if run requested, build/compile/run Boon project
5. begin Clay frame
6. declare playground shell UI
7. declare preview UI from DocumentSnapshot/SceneSnapshot
8. end Clay frame
9. render Clay commands through SDL
10. update frame stats
```

---

## 6. Project model and multi-file build

All examples are represented as projects, even single-file examples.

```zig
pub const ProjectFile = struct {
    path: []const u8,
    contents: []const u8,
    generated: bool = false,
};

pub const Project = struct {
    name: []const u8,
    entry_file: []const u8,
    files: []ProjectFile,
    assets_root: ?[]const u8,
};
```

### 6.1 Module resolution

Match the Rust playground behavior for multi-file examples:

```text
- Entry file is not imported as a module.
- BUILD.bn is not imported as a module.
- Every other .bn file becomes an importable module.
- Module name is the basename without .bn.
```

Examples:

```text
Theme/Theme.bn          -> module Theme
Theme/Professional.bn   -> module Professional
Theme/Glassmorphism.bn  -> module Glassmorphism
Generated/Assets.bn     -> module Assets
```

Functions must be callable as:

```text
Theme/material(...)
Professional/get(...)
Assets/icon()
```

If any imported module lexes, parses, or resolves incorrectly, compilation fails. Do not silently omit a module. If two module files produce the same basename module name, fail with a collision diagnostic that names both relative file paths.

### 6.2 Build file execution

If a project contains `BUILD.bn`, `Run` must execute it before compiling the entry file.

For `todo_mvc_physical`, implement enough build-host builtins to execute `BUILD.bn`:

```text
Directory/entries()
File/read_text()
File/write_text(path, text)
Url/encode()
Text/join_lines()
List/retain()
List/sort_by()
List/map()
List/count()
Log/info()
Log/error()
Build/succeed()
Build/fail()
FLUSH
FLUSHED
```

The build script must run against an in-memory project VFS with access to imported `assets/icons/`.

Build host semantics for v0:

```text
Directory/entries(path):
  - accepts relative paths such as ./assets/icons
  - resolves inside the project VFS only
  - returns LIST of records sorted by raw relative path before any List/sort_by()
  - each record has:
      path: "./assets/icons/<filename>"
      file_name: "<filename>"
      file_stem: "<filename without final extension>"
      extension: "<extension without dot>"
      is_file: True
      is_directory: False

File/read_text(path):
  - resolves relative to project root
  - returns Ok[text: <utf8 text>] or ReadError[message: <text>]

File/write_text(path, text):
  - writes into the in-memory VFS
  - creates parent directories in the VFS if needed
  - returns Ok or WriteError[message: <text>]

Url/encode(text):
  - UTF-8 percent-encodes every byte except ASCII alphanumeric and - _ . ~ / :
  - spaces become %20, not +
  - # becomes %23
  - returns Ok[encoded: <text>] or EncodeError[message: <text>]

Text/join_lines(list):
  - joins text items with "\n" and no extra trailing newline

List/sort_by(item, key):
  - stable ascending bytewise UTF-8 ordering

Build/succeed() / Build/fail():
  - stop BUILD.bn execution with success/failure status
  - logs remain available to the playground diagnostic panel

FLUSH / FLUSHED:
  - implement the upstream build-script behavior needed by BUILD.bn
  - FLUSH exits the current expression with an error-like value
  - FLUSHED propagates transparently through expression boundaries
```

Verification for `todo_mvc_physical`:

```text
1. Run BUILD.bn.
2. Confirm Generated/Assets.bn is written.
3. Normalize CRLF to LF for both files and confirm generated output exactly matches the checked-in Generated/Assets.bn text.
4. Use the generated file for RUN.bn compilation.
```

The generated assets file must expose:

```text
Assets/icon().checkbox_active
Assets/icon().checkbox_completed
```

---

## 7. Runtime bridge contract

Raybox receives snapshots, not AST nodes or private runtime values. `boon-zig` must expose this public bridge before Raybox implements the adapter.

```zig
pub const BoonRuntimeHost = struct {
    pub fn init(
        allocator: std.mem.Allocator,
        persist: *PersistStore,
        route: *RouteStore,
        time: *TimeSource,
    ) !BoonRuntimeHost;

    pub fn deinit(self: *BoonRuntimeHost) void;
    pub fn loadProject(self: *BoonRuntimeHost, project: Project) !void;
    pub fn runBuildFile(self: *BoonRuntimeHost) !BuildResult;
    pub fn compileEntry(self: *BoonRuntimeHost) !CompileResult;
    pub fn start(self: *BoonRuntimeHost) !RuntimeOutput;
    pub fn dispatch(self: *BoonRuntimeHost, event: PreviewEvent) !RuntimeOutput;
    pub fn tick(self: *BoonRuntimeHost, now_ms: u64) !RuntimeOutput;
    pub fn clearState(self: *BoonRuntimeHost, project_name: []const u8) !void;
};
```

If `boon-zig` does not expose this API yet, implement it in `boon-zig` first and then pin `raybox-zig` to that commit. Raybox-zig must not introspect `boon-zig` private internals and must not reimplement parser/runtime semantics.

All slices returned from bridge calls are owned by the `BoonRuntimeHost` until the next mutating host call unless a type explicitly says it is caller-owned. Returned snapshots must be immutable, self-contained views for the current revision.

```zig
pub const BuildResult = union(enum) {
    not_present,
    ok: BuildSummary,
    diagnostics: []Diagnostic,
};

pub const CompileResult = union(enum) {
    ok: CompiledProject,
    diagnostics: []Diagnostic,
};

pub const RuntimeOutput = union(enum) {
    document: DocumentSnapshot,
    scene: SceneSnapshot,
    diagnostics: []Diagnostic,
};

pub const TimeSource = union(enum) {
    real,
    virtual: *VirtualClock,
};

pub const VirtualClock = struct {
    now_ms: u64,
    pub fn advance(self: *VirtualClock, delta_ms: u64) void;
};
```

Time rules:

```text
Interactive playground:
  uses TimeSource.real

Expected runner:
  uses TimeSource.virtual

wait action:
  advances virtual time
  calls BoonRuntimeHost.tick(now_ms)
  pumps frames until runtime, semantic tree, and render trace are quiescent
```

This is required for `interval`, `interval_hold`, `timer`, and every `.expected` file that uses `wait`.

`PreviewEvent` is the input event union defined in section 16. `BoonRuntimeHost.dispatch` is the only path from Raybox UI input back into Boon `LINK` ports.

Snapshot data:

```zig
pub const DocumentSnapshot = struct {
    revision: u64,
    root: ValueId,
    values: []const RuntimeValue,
    events: []const EventBinding,
    timers: []const TimerBinding,
    route: []const u8,
};

pub const SceneSnapshot = struct {
    revision: u64,
    root: ValueId,
    values: []const RuntimeValue,
    lights: []const LightValue,
    geometry: RuntimeValue,
    events: []const EventBinding,
    timers: []const TimerBinding,
    route: []const u8,
};

pub const RuntimeValue = union(enum) {
    none,
    number: f64,
    bool: bool,
    text: []const u8,
    symbol: []const u8,
    list: []const ValueId,
    record: []const RecordField,
    element: ElementNode,
};

pub const ElementNode = struct {
    kind: []const u8,
    args: []const RecordField,
    stable_id: []const u8,
};

pub const EventBinding = struct {
    id: LinkId,
    source_value: ValueId,
    event_name: []const u8,
};

pub const Diagnostic = struct {
    severity: enum { info, warning, err },
    file_path: ?[]const u8,
    span: ?SourceSpan,
    message: []const u8,
};
```

Host stores are provided by Raybox, but runtime semantics stay inside `boon-zig`.

```zig
pub const PersistStore = struct {
    ptr: *anyopaque,
    read: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8) anyerror!?[]u8,
    write: *const fn (ptr: *anyopaque, key: []const u8, value: []const u8) anyerror!void,
    deletePrefix: *const fn (ptr: *anyopaque, prefix: []const u8) anyerror!void,
};

pub const RouteStore = struct {
    ptr: *anyopaque,
    current: *const fn (ptr: *anyopaque) []const u8,
    goTo: *const fn (ptr: *anyopaque, route: []const u8) anyerror!void,
};
```

The Boon runtime owns:

```text
lexing
parsing
module resolution
evaluation
reactive graph
LATEST/HOLD/THEN/WHEN/LINK
timers
router state
persistence
event ordering
stable runtime IDs
expected behavior of generated values
```

Raybox owns:

```text
layout
hit testing
text input rendering
focus visuals
mouse/keyboard capture
semantic UI tree
rendering
mapping UI events back to Boon LINK ports
native/browser host backing stores
test-only semantic/render traces
```

Unsupported runtime features must produce explicit diagnostics. The final definition of done requires all imported examples to pass.

---

## 8. Playground shell

The playground shell is also Raybox UI, not DOM.

Required panels:

```text
example sidebar
file tabs
source editor
toolbar
preview panel
diagnostic/output panel
debug frame stats overlay
```

Toolbar actions:

```text
Run
Clear State
Reset Example
Toggle Layout: split / preview-only / code-only
Preview Size
```

Example sidebar sections:

```text
Main
Other
Debug
Multi-file
```

Source editor requirements:

```text
monospace font
line numbers
cursor
selection
copy/paste
scrolling
keyboard editing
basic syntax coloring
error span highlighting
multi-file tabs
dirty file indicator
```

This editor does not need to be a full IDE. It must edit `.bn` files well enough to run playground examples in native and browser.

---

## 9. Clay bridge

Create one Clay context for the playground shell and preview.

```zig
pub const ClayBridge = struct {
    memory: []u8,
    context: *c.Clay_Context,

    pub fn init(allocator: Allocator, fonts: *FontManager) !ClayBridge;
    pub fn beginFrame(self: *ClayBridge, input: InputState, width: f32, height: f32, dt: f32) void;
    pub fn endFrame(self: *ClayBridge) c.Clay_RenderCommandArray;
};
```

Frame sequence:

```text
Clay_SetLayoutDimensions
Clay_SetPointerState
Clay_UpdateScrollContainers
Clay_BeginLayout
declare Raybox UI
Clay_EndLayout
```

Clay text measurement must call `FontManager.measure`. Clay strings are not guaranteed to be null-terminated, so always pass explicit slices.

Do not expose Clay directly to the Boon adapter. The adapter emits Raybox semantic UI nodes.

---

## 10. Raybox UI API

Raybox exposes a semantic API to the playground and Boon adapter.

```zig
pub const Ui = struct {
    pub fn beginRoot(self: *Ui, id: StableId, opts: RootOptions) void;
    pub fn panel(self: *Ui, id: StableId, opts: PanelOptions, body: fn (*Ui) void) void;
    pub fn row(self: *Ui, id: StableId, opts: LayoutOptions, body: fn (*Ui) void) void;
    pub fn column(self: *Ui, id: StableId, opts: LayoutOptions, body: fn (*Ui) void) void;
    pub fn label(self: *Ui, id: StableId, text: []const u8, opts: TextOptions) void;
    pub fn button(self: *Ui, id: StableId, text: []const u8, opts: ButtonOptions) bool;
    pub fn textInput(self: *Ui, id: StableId, state: *TextInputState, opts: TextInputOptions) TextInputEvent;
    pub fn checkbox(self: *Ui, id: StableId, checked: bool, opts: CheckboxOptions) CheckboxEvent;
    pub fn select(self: *Ui, id: StableId, state: *SelectState, opts: SelectOptions) SelectEvent;
    pub fn slider(self: *Ui, id: StableId, value: f64, opts: SliderOptions) SliderEvent;
    pub fn svgSurface(self: *Ui, id: StableId, opts: SvgOptions, body: fn (*Ui) void) SvgEvent;
};
```

Use stable IDs everywhere. For list items, prefer Boon-provided identity such as todo item ID. Do not use transient list index IDs when the item has a durable ID.

---

## 11. Boon element mapping

The Boon adapter must support these values and elements.

### 11.1 Root values

```text
Document/new(root: value)      -> document preview root
Scene/new(root, lights, geometry) -> physical scene preview root
plain number/text/bool root    -> debug/value label
list root                      -> vertical child list
record root                    -> debug/value panel unless recognized as element/style
```

### 11.2 Element mapping

```text
Element/stripe                 -> row or column container
Scene/Element/stripe           -> row or column container with physical style
Element/container              -> panel/block
Scene/Element/block            -> panel/block with physical style
Element/stack                  -> absolute/layered container
Element/text                   -> text node
Scene/Element/text             -> text node with relief/depth support
Element/paragraph              -> wrapped text block
Scene/Element/paragraph        -> wrapped physical text block
Element/link                   -> text/link button
Scene/Element/link             -> physical text/link button
Element/label                  -> label wrapper and hit target
Scene/Element/label            -> physical label wrapper and hit target
Element/button                 -> button
Scene/Element/button           -> raised physical button
Element/text_input             -> text input
Scene/Element/text_input       -> recessed physical text input
Element/checkbox               -> checkbox
Scene/Element/checkbox         -> recessed physical checkbox
Element/select                 -> select/dropdown
Element/slider                 -> slider
Element/svg                    -> bounded SVG-like surface
Element/svg_circle             -> circle primitive inside SVG surface
Hidden[text: ...]              -> semantic label, not visible text
Reference[element: ...]        -> semantic accessible label reference
NoElement                      -> no rendered node
```

### 11.3 Style mapping

Support these style fields immediately:

```text
width
height
size
Fill
minimum
maximum
padding
gap
align row/column
background color
background url
font size
font weight
font style
font color
line underline/strike
rounded_corners
border width/color
borders per side
disabled
hovered
focus
scrollbars
transform/move_closer
transform/move_further
move.closer
move.further
move.up
move.down
move.left
move.right
rotate
depth
material
relief
spring_range
```

### 11.4 Colors

Implement OKLCH to sRGB conversion.

Support:

```text
Oklch[lightness: L]
Oklch[lightness: L, chroma: C, hue: H]
hex colors
rgba colors
named text values used by examples
```

All internal renderer colors are premultiplied RGBA.

---

## 12. Physical TodoMVC is a hard gate

`todo_mvc_physical` must render and interact nicely. Do not defer its physical features.

### 12.1 Required project behavior

The example must:

```text
load as a multi-file project
run BUILD.bn
generate Generated/Assets.bn
compile RUN.bn with module files
render Scene/new(...)
show theme buttons
show mode toggle
add todos
toggle todos
filter todos
clear completed
edit todo on double click
show/delete button on hover
switch themes
switch light/dark mode
persist state
clear state
```

The physical adapter must explicitly support source patterns used by `RUN.bn`:

```text
element.hovered: LINK
event.press
event.click
event.double_click
event.blur
event.change.text
event.key_down.key
focus: True
Reference[element: ...]
Hidden[text: ...]
Scene/Element/link
Scene/Element/paragraph
tag fields such as Header, Footer, Section, and H1
rotate
background: [url: ...]
```

Its `.expected` file must pass natively and in browser.

### 12.2 Required physical UI projection

Use a 2.5D physical projection in WebGL2. It must be visually attractive and deterministic.

For v0, Raybox implements a deterministic 2.5D projection of Boon's physical UI semantics. It does not implement full 3D geometry, true PBR, SDF text, or general `Model/cut`. It must still visually communicate the same intent: raised buttons, recessed inputs, recessed checkboxes, shadows, bevels, glass, glow, and theme distinction.

Implement these style effects:

```text
depth:
  controls bevel strength, shadow strength, and highlight strength

move closer:
  raises the element above its parent; casts a drop shadow

move further:
  recesses the element into its parent; creates an inset shadow

relief: Raised
  text or element appears lifted

relief: Carved[wall: N]
  text or element appears cut into the surface

material.color:
  base color

material.gloss:
  controls highlight strength and surface softness

material.shine:
  adds a secondary clearcoat highlight

material.metal:
  adds subtle colored highlight tint; keep small

material.glow:
  emits focus/active glow

material.transparency:
  makes surfaces translucent while preserving readability

material.refraction:
  approximated by glass highlight and tinted translucent surface
```

Use this visibility-preserving transparency mapping:

```text
if material.transparency is absent:
    alpha = 1.0
else:
    alpha = clamp(1.0 - material.transparency * 0.55, 0.35, 0.9)
```

This keeps Glassmorphism visibly glassy without making the app unreadable.

### 12.3 Required lighting projection

Support at least:

```text
Light/directional
Light/ambient
Light/spot target: FocusedElement
```

Projection rules:

```text
Directional light:
  determines drop-shadow direction, bevel highlight side, and bevel shadow side.

Ambient light:
  softens contrast and adjusts shadow opacity.

Spot light on FocusedElement:
  produces a subtle glow around the focused input/control.
```

Use theme light values. Do not ignore `Theme/lights()`.

### 12.4 Required physical element recipes

#### Scene/Element/stripe and Scene/Element/block

For any element with material/depth/move:

```text
1. draw drop shadow if z > 0
2. draw rounded body
3. draw bevel highlight and bevel shadow
4. draw border/focus/glow if present
5. draw children
```

#### Scene/Element/button

Buttons are raised.

```text
rest:
  body + bevel + small shadow

hovered:
  stronger highlight and slightly higher z if spring_range.extend > 0

pressed:
  lower z and reduced shadow if press/active state is available
```

#### Scene/Element/text_input

Text inputs are recessed.

```text
1. outer rounded body
2. inner cutout well based on padding
3. inner shadow
4. glossy/tinted floor
5. placeholder or text
6. caret and selection
7. focus glow when focused
```

#### Scene/Element/checkbox

Checkboxes are recessed controls.

```text
1. outer rounded/pill body
2. inner well
3. icon from background url or checkmark vector
4. hover/focus glow
```

#### Scene/Element/text with relief

For `relief: Raised`:

```text
draw shadow/offset text layer
draw main text
draw highlight text layer if depth >= 2
```

For `relief: Carved[wall: N]`:

```text
draw dark inset offset
draw main text slightly recessed
draw light upper-edge highlight
```

### 12.5 Theme visual requirements

All four themes must look distinct.

#### Professional

```text
soft rounded edges
subtle shadows
low/medium gloss
warm header color
polished but conservative visual style
```

#### Glassmorphism

```text
translucent panels
visible background through surfaces
bright glass highlights
soft blue/purple tint
selected Glass button has visible outline
```

#### Neobrutalism

```text
high contrast
harder shadows
bold accent colors
square/sharp corners except pill-specific controls
strong outline/edge presence
```

#### Neumorphism

```text
low contrast monochrome surfaces
soft shadows and highlights
gentle rounded edges
controls still readable
```

### 12.6 Physical visual verification

Implement:

```bash
zig build verify-raybox-physical-native
zig build verify-raybox-physical-web
```

The verifier must run `todo_mvc_physical.expected` and also capture deterministic preview screenshots at:

```text
1000x900 @ scale 1.0
1000x900 @ scale 2.0
```

Required screenshots:

```text
Professional Light initial
Professional Light with two todos
Professional Dark with one todo completed
Glassmorphism Dark
Neobrutalism Light
Neumorphism Light
```

The verifier must also inspect the semantic/render tree. Do not use OCR.

Required assertions:

```text
title "todos" is visible and large
new todo input starts focused
input is visibly recessed: has inner shadow command
main card has non-zero drop shadow command
buttons have raised physical commands
checkboxes have recessed physical commands
theme buttons are visible
selected theme button has outline or selected visual
mode toggle changes label between Dark mode and Light mode
Glass theme surfaces have alpha < 1.0
Neobrutalism main card corner radius is 0 or visually sharp
Neumorphism shadow blur radius is greater than Professional's
at least one glow command exists for focused input
checkbox_completed icon renders after completion
```

Hard gate:

```text
todo_mvc_physical.expected passes
semantic tree assertions pass
render command trace assertions pass
```

Screenshots and image diffs are regression artifacts. They are recorded and compared against tolerance, but a pixel mismatch alone is not a hard failure unless the semantic/render trace assertions also fail. This avoids backend-specific rasterization differences between native and browser SDL backends.

Write visual artifacts to:

```text
zig-out/verification/physical/<target>/<example>/<scenario>/
```

Each scenario directory contains:

```text
semantic_tree.json
render_trace.json
screenshot.png
native_vs_web.diff.png
report.json
```

`fixtures/physical_visual_spec.json` defines native/browser image tolerance:

```json
{
  "max_mean_abs_channel_delta": 2.5,
  "max_percent_pixels_over_delta_16": 0.5,
  "ignored_margin_px": 1,
  "ignore_fully_transparent_pixels": true,
  "compare_region": "preview_viewport_only"
}
```

Native verification uses a fixed-size SDL test harness. The native verifier must:

```text
1. create the app with a deterministic viewport and device scale
2. run the selected example with TimeSource.virtual
3. dispatch expected actions through the same input path as the app
4. read semantic_tree.json and render_trace.json directly
5. optionally capture preview viewport screenshots
```

Browser verification uses Playwright Chromium with the Emscripten/WebGL2 build. The web verifier must:

```text
1. launch the Emscripten/WebGL2 build
2. reset localStorage/sessionStorage/IndexedDB test data unless a persistence sequence is running
3. wait for fonts, assets, runtime, and one rendered frame to become quiescent
4. drive expected actions through a test bridge exposed by the Wasm app
5. read semantic_tree.json and render_trace.json from the test bridge
6. capture screenshots from the canvas preview viewport only
```

The browser test bridge is:

```js
window.__rayboxTest = {
  runExample(name),
  clearState(name),
  dispatch(action),
  semanticTree(),
  renderTrace(),
  frameStats(),
  screenshotPng()
};
```

The test bridge may expose diagnostics, semantic tree, render trace, route, readiness, and screenshot commands. It must not render the preview with DOM nodes.

---

## 13. Renderer implementation

### 13.1 Renderer command handling

Render Clay commands:

```text
CLAY_RENDER_COMMAND_TYPE_RECTANGLE
CLAY_RENDER_COMMAND_TYPE_BORDER
CLAY_RENDER_COMMAND_TYPE_TEXT
CLAY_RENDER_COMMAND_TYPE_IMAGE
CLAY_RENDER_COMMAND_TYPE_SCISSOR_START
CLAY_RENDER_COMMAND_TYPE_SCISSOR_END
CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_START
CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_END
CLAY_RENDER_COMMAND_TYPE_CUSTOM
```

Raybox custom commands:

```zig
pub const CustomKind = enum(u32) {
    shadow,
    inner_shadow,
    cutout_rounded_rect,
    bevel,
    glow,
    outline,
    caret,
    selection,
    svg_circle,
    svg_path,
};
```

Every custom command must also be recorded in a test-only render trace:

```zig
pub const RenderTraceCommand = struct {
    node_id: StableId,
    kind: CustomKind,
    rect: Rect,
    radius: CornerRadius,
    color: ColorPremul,
    z: f32 = 0,
    blur_radius: f32 = 0,
    spread: f32 = 0,
    offset: Vec2 = .{ .x = 0, .y = 0 },
    alpha: f32 = 1,
    outline_width: f32 = 0,
    icon_name: ?[]const u8 = null,
};
```

The verifier reads this trace for physical assertions. Do not infer physical state from pixels when a command-level assertion is available.

### 13.2 Renderer resources

```zig
pub const Renderer = struct {
    pass_action: sg.PassAction,

    solid_pipeline: sg.Pipeline,
    image_pipeline: sg.Pipeline,
    text_pipeline: sg.Pipeline,
    blur_h_pipeline: sg.Pipeline,
    blur_v_pipeline: sg.Pipeline,

    vertex_buffer: sg.Buffer,
    index_buffer: sg.Buffer,

    white_texture: sg.Image,

    batcher: Batcher,
    shadows: ShadowCache,
    images: ImageCache,
};
```

Ownership:

```text
Renderer owns pipelines, buffers, batcher, shadow cache, and image cache.
FontManager owns the glyph atlas sg.Image and texture updates.
Renderer asks FontManager for the current glyph atlas image when drawing text.
ShadowCache owns shadow render targets/textures.
ImageCache owns decoded SVG/image textures.
```

Vertex format:

```zig
pub const Vertex2D = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    color: u32, // premultiplied RGBA8
};
```

Flush batch when:

```text
pipeline changes
texture changes
scissor changes
vertex capacity exceeded
index capacity exceeded
```

Renderer hot-path rules:

```text
No heap allocations in renderer hot path after init except frame arena allocation.
All Clay custom command data lives in a per-frame arena.
No pointers to stack data may be passed through Clay customData.
Frame stats record draw batches, vertices, indices, glyph uploads, shadow cache hits/misses, and frame arena high-water mark.
```

After warmup, `todo_mvc_physical` idle frames must report:

```text
zero glyph uploads
zero shadow regenerations
zero heap allocations in render path outside the frame arena
```

### 13.3 Premultiplied alpha

Use premultiplied alpha everywhere.

Blend mode:

```text
src_rgb = one
dst_rgb = one_minus_src_alpha
src_alpha = one
dst_alpha = one_minus_src_alpha
```

Every CPU color conversion must premultiply before writing vertex colors.

### 13.4 Geometry functions

Implement CPU geometry:

```zig
pub fn emitRect(batch: *Batcher, rect: Rect, color: ColorPremul) void;

pub fn emitRoundedRect(
    batch: *Batcher,
    rect: Rect,
    radius: CornerRadius,
    color: ColorPremul,
) void;

pub fn emitBorder(
    batch: *Batcher,
    rect: Rect,
    radius: CornerRadius,
    width: BorderWidth,
    color: ColorPremul,
) void;

pub fn emitImageQuad(
    batch: *Batcher,
    rect: Rect,
    uv: Rect,
    color: ColorPremul,
) void;

pub fn emitCutoutRoundedRect(
    batch: *Batcher,
    outer: Rect,
    inner: Rect,
    outer_radius: CornerRadius,
    inner_radius: CornerRadius,
    color: ColorPremul,
) void;
```

Rounded rectangles are CPU-generated triangle geometry. Use:

```text
segments per quarter circle: 12
antialias fringe: 1 physical pixel
```

Independent borders must support:

```zig
pub const BorderWidth = struct {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
};
```

### 13.5 Shadows

Implement cached shadows for rounded rectangles.

```zig
pub const ShadowCmd = struct {
    rect: Rect,
    radius: CornerRadius,
    blur_radius: f32,
    spread: f32,
    offset: Vec2,
    color: ColorPremul,
    cache_id: u64,
};
```

Shadow generation:

```text
1. render rounded-rect alpha mask to offscreen texture
2. blur horizontally
3. blur vertically
4. cache final shadow texture
5. composite behind element
```

Movement does not invalidate the cache. Shape, radius, blur radius, spread, and device scale invalidate the cache.

Shadow clipping policy:

```text
Shadows obey active scroll/scissor clips.
Top-level card/panel shadows may extend outside element bounds when the parent is not clipped.
Shadow command bounds are rect expanded by spread + blur radius + abs(offset).
```

Layering policy:

```text
1. drop shadow
2. body
3. bevel/highlight
4. children
5. focus/glow
6. overlay
```

`Element/stack` maps to Clay floating/local absolute placement. Children render in declaration order unless an explicit z/order value exists. Transforms apply after layout.

### 13.6 Shaders

Use a single shader file first:

```text
The SDL renderer consumes the CPU trace geometry directly through `SDL_RenderGeometry`.
Do not add a shader language, shader generator, or separate graphics backend before
the definition of done passes.

---

## 14. Text system

Use FontStash + stb_truetype.

Core fonts are embedded with `@embedFile` so Clay can measure text on the first frame without an async loading race:

```text
assets/fonts/Inter-Regular.ttf
assets/fonts/JetBrainsMono-Regular.ttf
assets/fonts/NotoSans-Regular.ttf
```

Load example assets/images through the existing Zig asset pipeline, not through renderer-specific async asset APIs. Core UI/editor/preview fonts must stay embedded and available on the first frame.

```zig
pub const FontManager = struct {
    stash: *FONScontext,
    atlas_texture: SDL_Texture,
    atlas_dirty: bool,

    fonts: std.StringHashMap(FontId),

    pub fn init(renderer: *Renderer) !FontManager;
    pub fn loadFontBytes(self: *FontManager, name: []const u8, bytes: []const u8) !FontId;
    pub fn requestFont(self: *FontManager, path: []const u8, name: []const u8) void;
    pub fn measure(self: *FontManager, text: []const u8, font: FontId, size: f32) Dimensions;
    pub fn draw(self: *FontManager, batcher: *Batcher, text: []const u8, pos: Vec2, style: TextStyle) void;
};
```

Do not pregenerate Unicode ranges. Cache only glyphs actually drawn.

Use an RGBA8 glyph atlas initially, not R8, to avoid cross-backend texture-format surprises. Missing glyph fallback order:

```text
requested font
NotoSans-Regular
replacement glyph
```

Required test string in native and web:

```text
Příliš žluťoučký kůň úpěl ďábelské ódy.
```

The text system must support:

```text
normal font
monospace font
font size
font color
italic placeholder approximation
underline
strikethrough
selection background
caret
```

If FontStash lacks shaping needed for a current example, add the smallest deterministic shaping support required for that example. Czech text must render correctly with the dynamic atlas.

---

## 15. Images and SVG subset

Implement `background: [url: ...]` for the assets used by current examples.

Required input forms:

```text
data:image/svg+xml;utf8,...
relative asset path
```

Implement `assets/data_uri.zig`:

```text
detect data URI
percent-decode UTF-8 payload
return media type and bytes
```

Implement `render/svg_minimal.zig` for the subset needed by `todo_mvc_physical` generated icons:

```text
<svg width height viewBox>
<circle cx cy r fill stroke stroke-width>
<path fill d="M ... L ... l ... z">
```

The parser must tolerate the exact generated icon shape:

```text
xmlns attributes
self-closing tags
negative and multi-number viewBox values
percent-decoded # color values
fill="none"
compact path commands without spaces, such as M72 25L42 71 27 56l-4 4 20 20 34-52z
repeated coordinate pairs after M/L/l
stroke and fill colors in hex form
stroke-linecap
stroke-linejoin
none
currentColor
```

Required path commands:

```text
M
L
l
H
V
h
v
C if present in imported icons
Z/z
```

`verify-corpus` must decode every generated data URI and parse every imported `todo_mvc_physical` icon SVG through `svg_minimal.zig`. If unsupported SVG syntax appears, `verify-corpus` fails with the exact file and unsupported token.

For `checkbox_active`, render a stroked circle.

For `checkbox_completed`, render the stroked circle and filled check path.

This minimal SVG renderer is also used by Raybox image backgrounds. Do not add a full SVG dependency.

---

## 16. Input and semantic tree

Every interactive node must be recorded in a semantic tree.

```zig
pub const RenderedNode = struct {
    id: StableId,
    source_id: []const u8,
    role: Role,
    text: []const u8,
    placeholder: []const u8,
    value: []const u8,
    bounds: Rect,
    visible: bool,
    focused: bool,
    hovered: bool,
    checked: ?bool,
    disabled: bool,
    enabled: bool,
    selected: bool,
    outline_visible: bool,
    input_typeable: bool,
    input_index: ?usize,
    button_index: ?usize,
    checkbox_index: ?usize,
    select_index: ?usize,
    slider_index: ?usize,
    url: []const u8,
};
```

The expected runner uses this tree, not OCR.

Input events:

```zig
pub const PreviewEvent = union(enum) {
    press: LinkId,
    click: LinkId,
    double_click: LinkId,
    hover: struct { link: LinkId, hovered: bool },
    change_text: struct { link: LinkId, text: []const u8 },
    key_down: struct { link: LinkId, key: Key, text: []const u8 },
    blur: LinkId,
    focus: LinkId,
    checkbox_change: struct { link: LinkId, checked: bool },
    select_change: struct { link: LinkId, value: []const u8 },
    slider_change: struct { link: LinkId, value: f64 },
    svg_click: struct { link: LinkId, x: f32, y: f32 },
};
```

The playground shell and preview share the same input system. Focus must be explicit and deterministic.

---

## 17. Persistence and router

Persistence and routing semantics belong to `boon-zig`. Raybox provides deterministic native/browser backing stores through the bridge callbacks in section 7.

### 17.1 Persistence

```text
// Concrete implementation of the callback-shaped PersistStore from section 7.
read(key) -> ?[]u8
write(key, value) -> void
deletePrefix(prefix) -> void
```

Native backing:

```text
.zig-cache/raybox-zig/state/<project-name>/
```

Browser backing:

```text
localStorage keys prefixed with raybox-zig:<project-name>:
```

For v0, browser persistence uses `localStorage` because the playground examples need synchronous host callbacks. The key namespace is:

```text
raybox-zig:<project-name>:<boon-runtime-key>
```

Do not let Raybox interpret Boon state payloads. Store and return opaque bytes/text exactly as `boon-zig` supplies them.

Browser storage uses Emscripten `EM_JS` helpers or equivalent externs:

```zig
extern fn rb_local_storage_get(key_ptr: [*]const u8, key_len: usize, out: *JsStringHandle) bool;
extern fn rb_local_storage_set(key_ptr: [*]const u8, key_len: usize, val_ptr: [*]const u8, val_len: usize) void;
extern fn rb_local_storage_delete_prefix(prefix_ptr: [*]const u8, prefix_len: usize) void;
```

Clear State must delete the current example/project state and rerun the preview.

### 17.2 Router

Implement route host API:

```text
// Concrete implementation of the callback-shaped RouteStore from section 7.
current() -> []const u8
goTo(route) -> void
```

Native uses in-memory route state.

Browser updates the URL query/hash without reloading.

Browser route and external URL calls use Emscripten `EM_JS` helpers or equivalent externs:

```zig
extern fn rb_route_current(out: *JsStringHandle) bool;
extern fn rb_route_go_to(route_ptr: [*]const u8, route_len: usize) void;
extern fn rb_open_url(url_ptr: [*]const u8, url_len: usize) void;
```

The route host must be synchronous from the runtime perspective:

```text
RouteStore.current() returns the route visible to the current runtime tick.
RouteStore.goTo(route) updates host route state, updates browser URL on web, and schedules a rerender without page reload.
Route persistence, if any, is a boon-zig runtime decision; Raybox only stores requested keys.
```

`pages.bn` must pass.

---

## 18. Expected runner

Parse upstream `.expected` files. Do not invent a new format.

Parse these TOML sections/fields:

```text
[test]
category
description
skip_engines

[output]
text
match

[timing]
timeout
initial_delay
poll_interval

[[sequence]]
description
actions
expect
expect_match

[[persistence]]
description
actions
expect
expect_match
```

`skip_engines` is informational unless it explicitly names `Raybox`. The pinned v0 corpus must pass in Raybox even when an expected file skips older upstream engines such as `Actors`, `DD`, or `Wasm`.

`verify-corpus` must parse all imported `.expected` files and emit:

```text
fixtures/expected_action_schema.json
```

If an unknown action exists, `verify-corpus` fails and prints the example name, action name, and line/span. Do not hand-maintain the action list without this discovery check.

Support these actions:

```text
assert_button_disabled
assert_button_enabled
assert_button_has_outline
assert_cells_cell_text
assert_cells_row_visible
assert_checkbox_checked
assert_checkbox_count
assert_checkbox_unchecked
assert_contains
assert_focused
assert_focused_input_value
assert_input_empty
assert_input_not_typeable
assert_input_typeable
assert_input_value
assert_input_placeholder
assert_not_contains
assert_not_focused
assert_toggle_all_darker
assert_url

click_button
click_button_near_text
click_checkbox
click_text
dblclick_cells_cell
dblclick_text
focus_input
hover_text
key
select_option
set_focused_input_value
set_input_value
set_slider_value
type
clear_states
run
wait
```

Action semantics:

```text
Text actions match visible semantic-tree text after layout, not source text.
Index-based actions use zero-based indexes unless the upstream expected file describes a human-facing row/cell coordinate.
assert_url checks RouteStore.current() and, in browser, the visible URL path/hash.
set_* actions replace the control value and emit the corresponding Boon change event.
type appends text to the focused input and emits change events deterministically.
key emits key_down with the current focused input value.
wait advances virtual time in native verifier and browser verifier; do not depend on wall-clock sleeping.
```

For `todo_mvc_physical.expected`, the following must pass:

```text
input starts focused
input is typeable
add first todo
add second todo
complete first todo
active filter hides completed todo
return to all todos
clear completed removes checked todo
toggle dark mode button label
switch to Glass theme
selected Glass button has outline
```

Expected runner algorithm:

```text
1. Load example project.
2. Clear state unless the expected file says otherwise.
3. Run project.
4. Wait for stable/quiescent runtime state.
5. Execute each action against semantic tree.
6. After each sequence, assert expected text or semantic property.
7. Capture failures with:
   - current example name
   - action index
   - semantic tree dump
   - frame stats
   - screenshot path
```

---

## 19. Example implementation order

### Phase 0 — Dependency pins and Boon bridge preflight

Deliver:

```text
Zig/tool dependency pins recorded
upstream Boon corpus commit recorded
boon-zig dependency pinned
boon-zig exposes BoonRuntimeHost bridge
Raybox build fails clearly if required bridge API is missing
```

Acceptance:

```bash
zig build test
```

### Phase 1 — Build + SDL + Clay shell

Deliver:

```text
native window opens
browser canvas opens
screen clears
basic playground shell renders
Clay root layout works
frame stats render
```

Acceptance:

```bash
zig build run-raybox
zig build run-raybox -Dtarget=wasm32-emscripten
```

### Phase 2 — Corpus import and registry

Deliver:

```text
import upstream examples
generate corpus_manifest.json
generate example registry Zig file
import todo_mvc_physical full tree
```

Acceptance:

```bash
zig build import-upstream
zig build generate-example-registry
zig build verify-corpus
```

### Phase 3 — Renderer primitives

Deliver:

```text
solid rect
rounded rect
independent borders
scissor clipping
premultiplied alpha
basic image quad
custom command plumbing
```

Acceptance:

```bash
zig build test
zig build run-raybox
```

### Phase 4 — Text system

Deliver:

```text
embed core fonts with @embedFile
dynamic glyph atlas
RGBA8 glyph atlas
font fallback
Clay text measurement
text rendering
caret
selection
Czech test string
```

Acceptance:

```bash
zig build verify-raybox-text-native
zig build verify-raybox-text-web
```

### Phase 5 — Boon runtime bridge

Deliver:

```text
boon-zig dependency wired
single-file project compile/run
RuntimeOutput document/scene adapter
diagnostic display
host persistence callbacks
host route callbacks
virtual clock callback
```

Acceptance examples:

```text
minimal
hello_world
counter
```

### Phase 6 — Core UI elements and events

Deliver:

```text
stripe
block/container
text
paragraph
label
button
checkbox
text_input
LINK routing
focus model
keyboard text editing
hover
double-click
router events
persistence clear/rerun behavior
```

Acceptance examples:

```text
counter
counter_hold
shopping_list
todo_mvc
checkbox_test
button_hover_test
button_hover_to_click_test
```

### Phase 7 — Build scripts and multi-file modules

Deliver:

```text
Project VFS
BUILD.bn execution
module resolution
Generated/Assets.bn generation
data URI support
minimal SVG support
BUILD.bn host result/error shapes
```

Acceptance:

```bash
zig build verify-raybox-examples-native -Dexample=todo_mvc_physical -Dbuild-only=true
zig build verify-raybox-examples-web -Dexample=todo_mvc_physical -Dbuild-only=true
```

### Phase 8 — Physical renderer projection

Deliver:

```text
Scene/new support
Theme/lights support
Theme/geometry support
depth/elevation projection
materials
gloss/shine/metal/glow/transparency
raised buttons
recessed text inputs
recessed checkboxes
bevels
drop shadows
inner shadows
glass highlights
theme switching visuals
```

Acceptance:

```bash
zig build verify-raybox-physical-native
zig build verify-raybox-physical-web
```

### Phase 9 — Remaining example coverage

Deliver remaining controls and features:

```text
select
slider
svg
svg_circle
timers
scroll containers
cells editing behavior
```

Acceptance:

```bash
zig build verify-raybox-examples-native
zig build verify-raybox-examples-web
```

---

## 20. Final definition of done

The implementation is complete only when all commands pass:

```bash
zig build test
zig build verify-corpus
zig build verify-raybox-text-native
zig build verify-raybox-text-web
zig build verify-raybox-examples-native
zig build verify-raybox-examples-web
zig build verify-raybox-examples-native -Dexample=todo_mvc_physical -Dbuild-only=true
zig build verify-raybox-examples-web -Dexample=todo_mvc_physical -Dbuild-only=true
zig build verify-raybox-physical-native
zig build verify-raybox-physical-web
zig build run-raybox
zig build run-raybox -Dtarget=wasm32-emscripten
```

Required final state:

```text
Every upstream playground registry example is in corpus_manifest.json.
Every ignored upstream entry has ignored=true and a non-empty reason.
Verification results are written to zig-out/reports/, not back into corpus_manifest.json.
Every non-ignored example is DONE in example_status_native.json and example_status_web.json.
All dependency and corpus pins are recorded.
boon-zig exposes the required public BoonRuntimeHost bridge.
Every example compiles through boon-zig.
Every example renders through Raybox.
Every example works in a native SDL window.
Every example works in the browser SDL canvas.
No preview path uses DOM rendering.
No example is rewritten manually as Zig UI.
No example is silently skipped.
todo_mvc_physical runs as an 8-file project.
todo_mvc_physical BUILD.bn generates assets.
todo_mvc_physical expected script passes.
todo_mvc_physical physical visual verifier passes.
Native and browser screenshots/diffs are written as regression artifacts with tolerance metadata.
```

---

## 21. Reference links for implementors

Use these as implementation references:

```text
Boon upstream:
https://github.com/BoonLang/boon

Rust playground main source:
https://github.com/BoonLang/boon/blob/main/playground/frontend/src/main.rs

todo_mvc_physical directory:
https://github.com/BoonLang/boon/tree/main/playground/frontend/src/examples/todo_mvc_physical

todo_mvc_physical RUN.bn:
https://raw.githubusercontent.com/BoonLang/boon/main/playground/frontend/src/examples/todo_mvc_physical/RUN.bn

todo_mvc_physical BUILD.bn:
https://raw.githubusercontent.com/BoonLang/boon/main/playground/frontend/src/examples/todo_mvc_physical/BUILD.bn

todo_mvc_physical expected:
https://raw.githubusercontent.com/BoonLang/boon/main/playground/frontend/src/examples/todo_mvc_physical/todo_mvc_physical.expected

Physical rendering docs:
https://raw.githubusercontent.com/BoonLang/boon/main/playground/frontend/src/examples/todo_mvc_physical/docs/PHYSICALLY_BASED_RENDERING.md

SDL:
https://github.com/libsdl-org/SDL

SDL Zig package:
https://github.com/castholm/SDL

Clay:
https://github.com/nicbarker/clay

FontStash:
https://github.com/memononen/fontstash
```
