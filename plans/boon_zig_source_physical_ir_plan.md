# Boon-on-Zig Production Branch Plan v4: `SOURCE`, No Pipe-`LINK`, Physical IR, Zig Compiler, and Zig Playground

**Audience:** Boon / `boon-zig` implementers  
**Purpose:** bootstrap a new `boon-zig` branch toward a production-ready runtime, compiler, and browser/edge playground  
**Status:** standalone branch plan; supersedes v3, the earlier long plan, the short v2 review-resolution file, and the v1/v2 amendments
**Date:** 2026-04-24

---

## 0. Executive summary

This branch should stop treating Boon performance as a surface syntax problem. After the planned `LINK` redesign below, the remaining work is mainly a compiler/runtime architecture problem:

```text
Boon source
→ AST
→ HIR
→ Flow IR
→ Physical IR
→ fast interpreter and/or generated Zig
→ retained host renderer
```

The important language-level change is:

```text
LINK -> SOURCE
remove |> LINK { ... }
keep element: [...] as the single required element bag
store runtime/host interfaces under sources
```

The current `|> LINK { ... }` design makes the language support arbitrary late reference patching:

```boon
remove_completed_button()
|> LINK {
    PASSED.store.elements.remove_completed_button
}
```

This branch removes that operation.

The new model stores **source interfaces** and passes/spreads them into element bags:

```boon
store: [
    sources: [
        remove_completed_button: [
            event: [press: SOURCE]
            hovered: SOURCE
        ]
    ]
]

Element/button(
    element: [
        tag: Button
        ...PASSED.store.sources.remove_completed_button
    ]

    label: TEXT { Clear completed }
)
```

Runtime binding still exists internally. The renderer still binds a concrete button press event to a Boon source slot. The change is that binding is now attached to the concrete element boundary and visible to the compiler as a static source slot, not expressed as arbitrary user-level reference assignment.

The production implementation should then focus on the required six-step practical plan:

1. **Define Physical IR.**
2. **Build a fast Zig interpreter for Physical IR.**
3. **Make terminal/headless examples pass: `counter`, `interval`, `cells`, `cells_dynamic` or equivalent non-UI pipe-link regression, `todo_mvc`, `pong`, and `arkanoid`.**
4. **Add Boon → Zig code generation from the same Physical IR.**
5. **Add retained browser renderer with no Virtual DOM.**
6. **Add required Zig playground support, including Boon → Zig → Wasm/native playground compilation path.**

Phase 6 is required, not optional. If an in-browser Zig compiler is too unstable or too large for the production path, the branch must still ship a playground compile path using the same public playground UI/API, with an edge/server compiler fallback. No silent skip.

---

## 1. Reference inputs and assumptions

This plan is based on the current `boon-zig` planning direction and the current upstream Boon examples.

Important reference files/repos:

- `BoonLang/boon-zig` current `PLAN.md`
- `BoonLang/boon` upstream playground examples
- `playground/frontend/src/examples/todo_mvc/todo_mvc.bn`
- `playground/frontend/src/examples/todo_mvc_physical/RUN.bn`
- MoonZoon/Dominator-style retained DOM / signal-driven UI inspiration

Existing `boon-zig` already emphasizes:

- deterministic reactive graph runtime
- headless/native correctness before browser work
- upstream example import
- parser/HIR/Flow IR/runtime stages
- `PASS/PASSED` lowering
- first-class flow nodes for `LATEST`, `HOLD`, `WHEN`, `THEN`, `WHILE`, `LINK`, `SKIP`, and `BLOCK`
- no dependence of Boon semantics on Zig thread scheduling
- terminal/headless first, browser last

This branch keeps that direction but updates the language model around `LINK`.

### 1.1 v4 review resolutions baked into this file

This v4 document is standalone. It merges the original long branch plan, the v2 corrections, the v3 standalone plan, and the follow-up Codex reviews. Do not read it as a short amendment.

Codex review findings resolved here:

1. **Standalone plan:** the full six-phase implementation plan is included in this file. It does not rely on the short v2 amendment.
2. **Non-UI pipe-link:** legacy computed event routing is not replaced with a channel or publish operation. It must be rewritten to ordinary graph values, returned fields, and list fan-in and existing source-of-truth list combinators.
3. **`interval` and `cells_dynamic`:** `interval` is restored as a hard headless/terminal gate, and `cells_dynamic` or a named equivalent non-UI pipe-link regression is also a hard gate together with `counter`, `cells`, `todo_mvc`, `pong`, and `arkanoid`.
4. **Element identity:** `SOURCE` records do not carry hidden element identity. `Reference[element: ...]` requires a real element value.
5. **Migration grounding:** existing HIR/Flow/runtime link support stays during migration behind a classifier/adapter stage. Canonical Physical IR must not contain generic pipe-link assignment.
6. **Build commands:** every named gate must be added to `build.zig` or mapped explicitly in `WORKLOG.md` to an existing equivalent command.
7. **Pinned corpus metadata:** tracked pin metadata belongs in `fixtures/upstream_pin.json` or another tracked fixtures file, not inside an ignored third-party checkout path.
8. **Terminal host binding metadata:** legacy `link:` / `pulse:` style source references in terminal/game examples must be migrated explicitly, not only pipe-link expressions.
9. **Terminal host binding shape:** terminal metadata fields such as `link:` and `pulse:` consume a concrete `SOURCE` leaf, not a whole button-shaped source record, unless the host boundary schema explicitly says otherwise. Canonical button-like sources are records such as `[event: [press: SOURCE]]`, and terminal metadata points at `.event.press`.
10. **`cells_dynamic` gate:** `cells_dynamic` or a named equivalent non-UI pipe-link regression is a required Phase 3 / DoD gate, not only a test matrix item.
11. **`List/latest` semantics:** list-of-stream fan-in must be specified and tested for empty lists, deterministic ordering, removed items, stale child events, payload shape unification, and implementation in the builtin maps.
12. **Ignored checkout conflict:** if the upstream checkout lives under ignored `third_party/boon-upstream/`, keep the tracked pin in `fixtures/upstream_pin.json` or explicitly unignore only the metadata file.
13. **No accidental API expansion:** `List/update` is not introduced by this plan. If a future source-of-truth update combinator is needed, it requires a separate spec.

---

## 2. High-level branch goals

### 2.1 Primary goal

Build a production-oriented Boon implementation where Boon source can be lowered into a compact typed Physical IR, executed by a fast Zig interpreter, and compiled/transpiled into efficient Zig code.

### 2.2 Secondary goal

Make live examples and playgrounds practical:

- instant feedback through a fast interpreter
- optional/required optimized build path through Boon → Zig
- browser playground support for Boon → Zig → Wasm/native-like output
- fallback edge/server compile mode if browser-hosted Zig compiler is too heavy or unstable

### 2.3 Non-goals for this branch

Do **not** spend time on broad syntax redesign beyond the `SOURCE` change.

Do **not** add explicit Boon type annotations.

Do **not** implement a Virtual DOM.

Do **not** make `List/map` fully user-definable as an ordinary Boon function yet. Keep map/retain/fold-like binder combinators compiler-known until a proper `COMBINATOR` / `EACH` design exists.

Do **not** turn Boon runtime semantics into Zig async task scheduling. Host I/O can be async; Boon graph updates must remain deterministic.

---

## 3. Final language design decisions for this branch

### 3.1 Rename `LINK` to `SOURCE`

Old:

```boon
Element/button(
    element: [event: [press: LINK]]
    label: TEXT { + }
)
```

New:

```boon
Element/button(
    element: [event: [press: SOURCE]]
    label: TEXT { + }
)
```

Meaning:

```text
SOURCE is a compile-time marker for a runtime-provided source of values/events into Boon. It is not an element identity/handle and it must not carry hidden user-space data.
```

A source may represent:

- event pulse, e.g. `event.press`
- event payload, e.g. `event.key_down.key`
- reactive host state, e.g. `hovered`, `focused`
- timer/frame/keyboard/terminal sources when a host boundary schema exposes them

The word `SOURCE` is chosen because the field is a source of runtime/host values into the Boon graph.

Do **not** add new Boon surface keywords to fix legacy pipe-link cases. In particular, this branch must not add:

```text
IDENTITY
CHANNEL
BINDING
PORT
PORTAL
```

Do **not** add event-bus or mutability workaround operations such as:

```text
Source/publish
Source/send
Source/emit
Stream/emit
Event/publish
```

Non-UI computed event routing must be represented as ordinary graph values, returned fields, and list fan-in and existing source-of-truth list combinators. The runtime may have internal physical node IDs, source slot IDs, retained node IDs, list item keys, and mapped-scope IDs, but those are implementation details and must not leak into Boon user-space values.

### 3.2 Remove `|> LINK { ... }`

Old pattern:

```boon
store: [
    elements: [
        save_button: LINK
    ]
]

save_button()
|> LINK {
    store.elements.save_button
}
```

New pattern:

```boon
store: [
    sources: [
        save_button: [
            event: [press: SOURCE]
            hovered: SOURCE
        ]
    ]
]

save_button(sources: store.sources.save_button)
```

Then inside the component:

```boon
FUNCTION save_button(sources) {
    Element/button(
        element: [
            ...sources
        ]

        style: [
            font: [line: [underline: sources.hovered]]
        ]

        label: TEXT { Save }
    )
}
```

Or inline:

```boon
Element/button(
    element: [
        tag: Button
        ...store.sources.save_button
    ]

    label: TEXT { Save }
)
```

Important: the removed pipe-link form was also used in some examples for non-UI computed event routing. Do **not** replace those uses with a mutable channel, `Source/publish`, or a new keyword. During migration, classify legacy pipe-link uses and rewrite non-UI computed routing into ordinary returned graph fields and list fan-in and existing source-of-truth list combinators. Details are in the migration and `List/latest` sections below.

### 3.3 Keep `element` as the single element bag

Do **not** split built-in element constructors into:

```boon
Element/button(
    element: [...]
    sources: ...
)
```

All function parameters are required in Boon, and built-in constructors should not alternate between `element` and `sources` forms.

Keep:

```boon
Element/button(
    element: [
        tag: Button
        event: [press: SOURCE]
        hovered: SOURCE
    ]

    label: TEXT { Save }
)
```

and:

```boon
Element/button(
    element: [
        tag: Button
        ...sources
    ]

    label: TEXT { Save }
)
```

Meaning:

```text
element = bag of optional element-level parameters
SOURCE = runtime source marker inside that element bag
sources = reusable/stored subset of an element bag containing SOURCE leaves
```

This lets `element` remain a single required argument to `Element/*` constructors.

### 3.4 Use `sources` as the storage field name

Old:

```boon
store: [
    elements: [
        remove_completed_button: LINK
    ]
]
```

New:

```boon
store: [
    sources: [
        remove_completed_button: [
            event: [press: SOURCE]
            hovered: SOURCE
        ]
    ]
]
```

For per-item UI sources:

```boon
FUNCTION new_todo(title) {
    [
        sources: [
            remove_todo_button: [
                event: [press: SOURCE]
                hovered: SOURCE
            ]

            edit_input: [
                event: [
                    change: SOURCE
                    key_down: SOURCE
                    blur: SOURCE
                ]
            ]

            title_label: [
                event: [double_click: SOURCE]
            ]

            checkbox: [
                event: [click: SOURCE]
            ]
        ]

        title: ...
        editing: ...
        completed: ...
    ]
}
```

Read as:

```text
store.sources = source interfaces observed by app-level state/controller logic
todo.sources = source interfaces observed by one todo item
```

These do not own concrete UI nodes. They are source slots/interfaces.

### 3.5 No `EXPOSE`, no `PORT`, no explicit Boon types

This branch should not introduce:

```boon
EXPOSE
PORT
PORT[Text]
SOURCE[Text]
```

No explicit type annotations should be required in Boon.

All source and value types should be inferred from:

- Boon/Zig boundary schemas
- usage
- record shapes
- list operations
- pattern arms
- arithmetic/text operations

The typed boundary lives in Zig, not Boon.

### 3.6 Local variables in functions require `BLOCK`

Do not write function-local declarations directly unless current grammar supports them.

Use:

```boon
FUNCTION new_todo_input() {
    BLOCK {
        sources: PASSED.store.sources.new_todo_title_text_input

        Element/text_input(
            element: [
                ...sources
            ]

            text:
                LATEST {
                    Text/empty()
                    sources.event.change.text
                    PASSED.store.title_to_add |> THEN { Text/empty() }
                }

            ...
        )
    }
}
```

Not:

```boon
FUNCTION new_todo_input() {
    sources: PASSED.store.sources.new_todo_title_text_input

    Element/text_input(...)
}
```

---

## 4. `SOURCE` semantics

### 4.1 `SOURCE` is a marker, not a normal value

This is valid:

```boon
sources: [
    save_button: [
        event: [press: SOURCE]
        hovered: SOURCE
    ]
]
```

This is not valid:

```boon
x: SOURCE + 1
```

`SOURCE` marks a source slot leaf. It does not evaluate to a normal value on its own.

### 4.2 Source interface records

A record containing `SOURCE` leaves is a **source interface record**.

A source interface record is not an element value. It does not secretly carry an element identity. `Reference[element: ...]` must receive an actual element value created by an `Element/*` expression, not a source interface record.

Example:

```boon
[
    event: [
        key_down: SOURCE
        change: SOURCE
    ]

    focused: SOURCE
]
```

The compiler gives this source interface a static shape and static source slots.

### 4.3 Source interfaces can be stored

Valid:

```boon
store: [
    sources: [
        new_todo_input: [
            event: [
                key_down: SOURCE
                change: SOURCE
            ]
        ]
    ]
]
```

### 4.4 Source interfaces can be passed

Valid:

```boon
new_todo_title_text_input(
    sources: PASSED.store.sources.new_todo_input
)
```

### 4.5 Source interfaces can be spread into `element`

Valid:

```boon
Element/text_input(
    element: [
        tag: Input
        ...sources
    ]

    label: Hidden[text: TEXT { New todo }]
)
```

Also valid when no extra element options are needed:

```boon
Element/text_input(
    element: [
        ...sources
    ]

    label: Hidden[text: TEXT { New todo }]
)
```

Potential shorthand if parser supports direct source record as element bag:

```boon
Element/text_input(
    element: sources
    label: Hidden[text: TEXT { New todo }]
)
```

The canonical emitted/pretty-printed form should prefer the spread form when clarity matters:

```boon
element: [
    ...sources
]
```

### 4.6 Source interfaces can be read

Valid after the source interface has been declared:

```boon
store.sources.new_todo_input.event.key_down.key
```

The runtime value may be:

```text
plugged and emitted
unplugged
stale event ignored
no output / SKIP depending on flow combinator
```

The exact observable behavior must be defined in tests.

### 4.7 Source interfaces do not own concrete UI

This is crucial.

```boon
store.sources.remove_completed_button
```

does **not** mean the store owns the concrete button element.

It means the store owns a stable source slot/interface.

The concrete UI node is owned by the document/page/component branch that renders it.

If the branch disappears, the source slot becomes unplugged.

### 4.8 Binding rules

A source slot can have:

| State | Meaning |
|---|---|
| zero active binders | allowed; source is unplugged |
| one active binder | normal |
| multiple active binders in same active branch | compile error or runtime debug assertion |
| multiple mutually exclusive binders with same inferred shape | allowed |
| multiple mutually exclusive binders with incompatible inferred shape | compile error |

Example allowed:

```boon
compact
|> WHILE {
    True =>
        compact_save_button(
            sources: PASSED.store.sources.save_button
        )

    False =>
        full_save_button(
            sources: PASSED.store.sources.save_button
        )
}
```

Only if both bind the same source shape and compatible host types.

Example rejected:

```boon
mode
|> WHILE {
    InputMode =>
        Element/text_input(
            element: [
                ...PASSED.store.sources.control
            ]
        )

    ButtonMode =>
        Element/button(
            element: [
                ...PASSED.store.sources.control
            ]
        )
}
```

unless the declared source interface is compatible with both constructors.

### 4.9 Stale events

If a concrete element was removed but an event arrives late, it must be ignored deterministically.

Each active binding should carry a generation/binding ID:

```text
SourceSlot {
    semantic_id
    physical_index
    state: unplugged | plugged(binding_id)
}
```

Event dispatch should validate:

```text
incoming_event.binding_id == source_slot.current_binding_id
```

If not, drop or trace as stale.

### 4.10 Static shape requirement

Any record containing `SOURCE` leaves must have statically known shape.

Allowed:

```boon
element: [
    tag: Button
    ...sources
]
```

if `sources` has statically known fields.

Discouraged/rejected in source-bearing records:

```boon
element: [
    ...condition |> WHEN {
        True => [hovered: SOURCE]
        False => []
    }
]
```

unless the compiler can normalize both branches into one static shape.

Rule:

```text
SOURCE-containing records must lower to a statically known source shape.
```

---

## 5. Syntax migration rules

### 5.1 Simple inline source

Before:

```boon
increment_button: Element/button(
    element: [event: [press: LINK]]
    style: []
    label: TEXT { + }
)
```

After:

```boon
increment_button: Element/button(
    element: [event: [press: SOURCE]]
    style: []
    label: TEXT { + }
)
```

### 5.2 Stored element holes

Before:

```boon
store: [
    elements: [
        remove_completed_button: LINK
    ]
]
```

After:

```boon
store: [
    sources: [
        remove_completed_button: [
            event: [press: SOURCE]
            hovered: SOURCE
        ]
    ]
]
```

The source shape must be explicit in Boon source, but the leaf types are inferred from host boundary schemas.

### 5.3 Pipe-link removal

Before:

```boon
remove_completed_button()
|> LINK {
    PASSED.store.elements.remove_completed_button
}
```

After:

```boon
remove_completed_button(
    sources: PASSED.store.sources.remove_completed_button
)
```

Inside the component:

```boon
FUNCTION remove_completed_button(sources) {
    Element/button(
        element: [
            ...sources
        ]

        style: [
            font: [line: [underline: sources.hovered]]
        ]

        label: TEXT { Clear completed }
    )
}
```

### 5.4 Pass-through with `PASS/PASSED`

For app-specific leaf functions, prefer `PASS/PASSED` to avoid long plumbing:

```boon
FUNCTION remove_completed_button() {
    BLOCK {
        sources: PASSED.store.sources.remove_completed_button

        Element/button(
            element: [
                ...sources
            ]

            style: [
                font: [line: [underline: sources.hovered]]
            ]

            label: TEXT { Clear completed }
        )
    }
}
```

For reusable components, use an explicit `sources` parameter:

```boon
FUNCTION filter_button(filter, sources) {
    Element/button(
        element: [
            ...sources
        ]

        label:
            filter
            |> WHEN {
                All => TEXT { All }
                Active => TEXT { Active }
                Completed => TEXT { Completed }
            }
    )
}
```

### 5.5 `store.elements` → `store.sources`

Before:

```boon
PASSED.store.elements.filter_buttons.all.event.press
```

After:

```boon
PASSED.store.sources.filter_buttons.all.event.press
```

### 5.6 `todo.todo_elements` → `todo.sources`

Before:

```boon
todo.todo_elements.remove_todo_button.event.press
```

After:

```boon
todo.sources.remove_todo_button.event.press
```

### 5.7 Compatibility during migration

The branch should have two modes:

#### Canonical mode

Only accepts:

```text
SOURCE
no |> LINK { ... }
```

#### Legacy import/migration mode

May accept upstream legacy examples long enough to rewrite them:

```text
LINK as deprecated alias of SOURCE
|> LINK { ... } recognized only by migration tooling, not by production compiler
```

The production parser should eventually reject `|> LINK { ... }` with a targeted diagnostic:

```text
pipe LINK assignment was removed.
Declare a source interface and pass/spread it into the element bag instead.
```

### 5.8 Legacy terminal host binding metadata

Some terminal/game examples use legacy source references outside `|> LINK { ... }`, for example host metadata fields such as:

```boon
link: store.elements.up_button
pulse: store.elements.tick_button
```

These are not pipe-link expressions, but they are still legacy `LINK`/`elements` source-reference sites. The migration must handle them explicitly.

#### Canonical terminal source shape

Terminal metadata fields such as `link:` and `pulse:` consume a **source leaf**, not a whole element/button source record, unless the exact host boundary schema explicitly says it consumes a record.

Canonical button-like source records should therefore look like the browser/UI form:

```boon
store: [
    sources: [
        up_button: [event: [press: SOURCE]]
        tick_button: [event: [press: SOURCE]]
    ]
]
```

Then terminal host metadata points to the concrete leaf:

```boon
-- terminal/host constructor names are examples; use the actual boundary schema.
Terminal/button(
    link: store.sources.up_button.event.press
    ...
)

Terminal/button(
    pulse: store.sources.tick_button.event.press
    ...
)
```

If a boundary truly represents a bare non-button source, the source may be declared as a leaf, but that must come from the boundary schema:

```boon
store: [
    sources: [
        timer_tick: SOURCE
    ]
]

Timer/interval(
    pulse: store.sources.timer_tick
    ...
)
```

Do not mix these two forms implicitly. A button/control record is not automatically a source leaf.

Rules:

- Host-specific metadata arguments such as `link:` and `pulse:` may remain as constructor parameters when they are part of the terminal/timer boundary schema.
- Their values must point to a concrete `SOURCE` leaf unless the boundary schema explicitly says the parameter consumes a source record.
- Button-like controls should expose `event.press: SOURCE`; metadata such as `link:` / `pulse:` should usually refer to `.event.press`.
- They do not imply a second source-binding mechanism. They are boundary-specific names for consuming a source leaf.
- The migration classifier must scan for legacy source paths outside pipe-link expressions, including terminal examples such as `pong` and `arkanoid`.
- If a host metadata field points to a concrete element value, a source record where a leaf is required, or an incompatible source payload, emit a diagnostic and require an explicit rewrite based on the host schema.
- Add regression tests that cover legacy shapes such as `link: store.elements.up_button` and `pulse: store.elements.tick_button` and verify the canonical rewrite to `store.sources.<name>.event.press` where appropriate.

### 5.9 Legacy non-UI pipe-link migration

Some existing pipe-link uses route computed events rather than binding UI elements. Do not replace these with a channel or publish/emit operation.

Preferred rewrite patterns:

1. Return the computed event/value from the child component as an ordinary field.
2. Derive the parent event/value from child fields.
3. For dynamic lists, use `List/map` plus `List/latest` or an existing source-of-truth list operator such as `List/remove` or another compiler-known list combinator already present in the repo. Do not introduce `List/update` in this branch without a separate spec.

Example shape:

```boon
cell_views:
    cells
    |> List/map(cell, new: cell_view(cell: cell))

cell_committed:
    cell_views
    |> List/map(view, new: view.committed)
    |> List/latest()
```

If the downstream code needs to know which item emitted, map the child event into an explicit payload before fan-in:

```boon
remove_requests:
    todo_views
    |> List/map(view, new:
        view.remove_requested
        |> THEN { [todo: view.todo] }
    )
    |> List/latest()
```

No hidden runtime identity is exposed. The payload contains exactly what user code explicitly returns.

---

## 6. Parser and formatter changes

### 6.1 Lexer

Add keyword:

```text
SOURCE
```

Either remove `LINK` from canonical keyword set or keep it as a legacy-only token.

### 6.2 Parser

Remove production parser support for:

```boon
expr |> LINK { target }
```

Canonical parse should reject it.

Add or confirm support for record spread:

```boon
[
    tag: Button
    ...sources
]
```

### 6.3 AST

Represent `SOURCE` as a marker expression only allowed in source interface contexts.

Possible AST node:

```zig
pub const Expr = union(enum) {
    source_marker,
    record,
    spread,
    call,
    ...
};
```

### 6.4 Context validation

After parse, validate:

```text
SOURCE occurs only in source-bearing record/interface contexts.
SOURCE is not used as a normal arithmetic/text/list value.
SOURCE-containing records have statically known shape after spread normalization.
```

### 6.5 Formatter

Formatter should print canonical source bags as:

```boon
sources: [
    save_button: [
        event: [press: SOURCE]
        hovered: SOURCE
    ]
]
```

For element calls, formatter should preserve or normalize to:

```boon
element: [
    tag: Button
    ...sources
]
```

---

## 7. HIR and Flow IR changes

### 7.1 Remove generic pipe-link assignment from canonical IR

Do not keep a canonical node like:

```text
LinkAssign(value_expr, target_path)
```

That is the dynamic operation being removed.

### 7.1a Add a legacy adapter/classifier stage before deletion

Do not delete existing HIR/Flow/runtime link support as the first implementation step. Existing examples still rely on legacy forms. Add a migration/classifier stage that runs after parsing legacy syntax and before canonical Flow IR / Physical IR emission.

Classifier result kinds:

```text
LegacyUiSourceBinding
LegacyTerminalHostSourceMetadata
LegacyComputedGraphBacklink
LegacyUnsupportedDynamicLink
```

Required behavior:

- `LegacyUiSourceBinding` rewrites to `sources` records spread into `element`.
- `LegacyTerminalHostSourceMetadata` rewrites `store.elements.*` style source paths to `store.sources.*` when the host schema confirms the argument consumes a source slot.
- `LegacyComputedGraphBacklink` must not become a channel. It must be rewritten manually or by a migration helper into returned fields plus list fan-in and existing source-of-truth list combinators.
- `LegacyUnsupportedDynamicLink` produces a precise diagnostic and keeps the example marked `BLOCKED` or `PARTIAL` in the corpus manifest until rewritten.

This adapter lets current passing examples survive while canonical syntax and Physical IR move away from generic pipe-link assignment.

### 7.2 Add source interface nodes

HIR/Flow should represent:

```text
SourceInterface
SourceField
SourceSlot
SourceShape
ElementBindingSite
```

Example conceptual shape:

```zig
pub const SourceShape = struct {
    fields: []SourceField,
};

pub const SourceField = struct {
    name: InternedName,
    kind: SourceFieldKind,
};

pub const SourceFieldKind = union(enum) {
    nested: SourceShapeId,
    source_leaf: SourceLeafId,
};
```

### 7.3 Element binding site

When the compiler sees:

```boon
Element/button(
    element: [
        tag: Button
        ...sources
    ]

    label: TEXT { Save }
)
```

lower to:

```text
ElementNode {
    kind: button
    element_options: { tag: Button }
    source_interface: sources_shape
    binding_site_id: ...
}
```

The element constructor and host schema determine which source fields are valid.

### 7.4 Source path lowering

Access:

```boon
store.sources.save_button.event.press
```

should lower to a static source slot, not a runtime field lookup:

```text
SourceSlotId(physical = 42, semantic = store.sources.save_button.event.press)
```

### 7.5 Inferred source payload types

The host boundary schema gives source leaf types.

For example:

```text
Element/text_input.event.change.text -> Text
Element/text_input.event.key_down.key -> Key
Element/text_input.event.key_down.text -> Text
Element/text_input.event.blur -> Pulse
Element/text_input.event.focus -> Pulse
Element/button.event.press -> Pulse
Element/button.hovered -> Bool
```

No Boon annotation needed.

### 7.6 Source binding compatibility

When multiple possible element constructors bind the same source interface, unify:

```text
field names
nested shape
source payload type
source cardinality/pulse semantics
boundary element kind/schema compatibility
```

Reject incompatible binders.

---

## 8. Type and shape inference strategy

### 8.1 No explicit types in Boon

Boon code should remain annotation-free.

Do not introduce:

```boon
SOURCE[Text]
PORT[Unit]
count: I64
items: LIST[Todo]
```

### 8.2 Boundary schemas are typed

The Boon/Zig host boundary must be strongly typed.

Example schema concept:

```zig
pub const text_input_schema = ElementSchema{
    .name = "Element/text_input",
    .sources = .{
        .event = .{
            .change = SourceEvent(.{ .text = Text }),
            .key_down = SourceEvent(.{
                .key = Key,
                .text = Text,
            }),
            .blur = SourcePulse,
            .focus = SourcePulse,
        },
        .hovered = SourceBool,
        .focused = SourceBool,
    },
    .options = ...,
};
```

### 8.3 Inference sources

The compiler infers from:

- host schemas
- builtin schemas
- arithmetic operations
- text templates
- list combinators
- record field access
- `WHEN`/`WHILE` branch unification
- `SOURCE` binding sites

### 8.4 Compile errors instead of dynamic fallback in hot/source paths

If a source shape cannot be inferred statically, reject.

If a list element shape cannot be inferred statically in a compiled hot path, reject or force slow generic path explicitly in diagnostics.

### 8.5 Spreads

Spreads should be normalized early.

Example:

```boon
element: [
    tag: Button
    ...sources
]
```

HIR normalized:

```text
element_options: { tag = Button }
source_interface: sources
```

If a spread may contribute `SOURCE` fields but has dynamic/unknown shape, reject.

---

## 9. Runtime model after `SOURCE`

### 9.1 Source slots

Source leaves become runtime slots:

```zig
pub const SourceState = union(enum) {
    unplugged,
    plugged: BindingId,
};

pub const SourceSlot = struct {
    semantic_id: SemanticId,
    physical_index: u32,
    state: SourceState,
    payload_type: TypeId,
};
```

### 9.2 Binding

When a concrete element mounts:

```text
mount ButtonNode #17
bind ButtonNode.press -> SourceSlot #42
bind ButtonNode.hovered -> SourceSlot #43
```

When it unmounts:

```text
unplug SourceSlot #42 if current binding belongs to ButtonNode #17
unplug SourceSlot #43 if current binding belongs to ButtonNode #17
```

### 9.3 Event dispatch

When host event arrives:

```text
event source_slot_id = #42
event binding_id = #99
```

Runtime checks:

```text
source_slot[#42].state == plugged(#99)
```

If true, enqueue event.

If false, ignore as stale and optionally trace.

### 9.4 No string lookup in hot path

Never dispatch hot events using:

```text
"store.sources.save_button.event.press"
```

Use numeric slot IDs.

Keep semantic string paths only for:

- diagnostics
- trace logs
- debug UI
- migration metadata
- source maps

### 9.5 Source absence

An unplugged source is not a crash.

It participates in graph semantics as:

```text
no event emitted
UNPLUGGED if explicitly observed
SKIP if transformed through event combinators
```

Define exact behavior per combinator in tests.

---

## 10. Retained UI renderer strategy

### 10.1 No Virtual DOM

The renderer should not rebuild a virtual tree and diff it.

Target model:

```text
create retained node once
wire source/event slots directly
wire dynamic text/style/property dependencies directly
on change: patch exact node/property/text/child list
```

This is inspired by MoonZoon/Dominator-style signal-driven UI: avoid Virtual DOM diffing and apply direct updates to real retained nodes.

### 10.2 UI blueprint

Boon UI should lower to a static-ish blueprint:

```text
ElementNode #17:
    kind = button
    static tag/options
    source bindings
    dynamic style dependencies
    dynamic label dependencies
    child/list dependencies
```

### 10.3 Dirty patches

Runtime should emit patches like:

```text
SetText(node_id, text)
SetStyleField(node_id, style_field_id, value)
SetProperty(node_id, property_id, value)
InsertChild(parent_id, index, node_id)
RemoveChild(parent_id, node_id)
MoveChild(parent_id, from, to)
BindSource(node_id, source_slot_id)
UnbindSource(node_id, source_slot_id)
```

### 10.4 List rendering

For:

```boon
todos |> List/map(item, new: todo_item(todo: item))
```

renderer must use stable item keys.

No full list rebuild unless unavoidable.

Required internal list handles/keys:

```text
ListId
ItemId
MapSiteId
MappedScopeId(parent_list, item_id, map_site)
```

### 10.5 Browser renderer

Browser renderer should be retained DOM:

```text
NodeId -> actual DOM node
StyleFieldId -> direct style/property patch
SourceSlot -> event listener binding
```

No Virtual DOM.

### 10.6 Terminal renderer

Terminal renderer is also retained:

```text
NodeId -> terminal layout/render node
dirty grid regions
deterministic snapshots
virtual input events
```

---

## 11. Physical IR

Physical IR is the key missing architecture layer.

### 11.1 Why Physical IR

Flow IR preserves Boon semantics.

Physical IR is where the compiler removes friendly/dynamic syntax and creates a fast execution layout.

Flow IR answers:

```text
what does this Boon program mean?
```

Physical IR answers:

```text
which slots, arrays, queues, functions, and binding tables execute it?
```

### 11.2 Required Physical IR contents

Physical IR should contain:

```text
typed value slots
typed source slots
state/HOLD slots
branch activation tables
list key/scope tables
map/retain scope tables
dependency edges
dirty propagation instructions
host binding tables
render blueprint nodes
stable semantic IDs
fast physical IDs
source maps for diagnostics
```

### 11.3 Semantic ID vs physical ID

Keep both:

```text
semantic_id = stable across code changes where possible; used for persistence/migration/debug
physical_id = compact optimized slot/index; used in hot runtime
```

Do not use semantic string paths as hot IDs.

### 11.4 Example Physical IR sketch

For:

```boon
increment_button: Element/button(
    element: [event: [press: SOURCE]]
    label: TEXT { + }
)

counter:
    LATEST {
        0
        increment_button.event.press |> THEN { 1 }
    }
    |> Math/sum()
```

Physical IR might include:

```text
SourceSlot #0: increment_button.event.press : Pulse
ValueSlot #1: counter_increment_event : I64 event
StateSlot #2: Math/sum accumulator : I64
RenderNode #3: Button
RenderText #4: "+"
Binding: RenderNode #3 press -> SourceSlot #0
Instruction: on SourceSlot #0, emit 1 into ValueSlot #1
Instruction: on ValueSlot #1, add to StateSlot #2
```

---

## 12. Required practical plan

The user-requested practical plan is mandatory for this branch.

This v3 file is standalone. It intentionally keeps the six-phase branch plan below even though the repository root `PLAN.md` may use a different larger phase numbering. When working from this file, use the six phases here as the implementation driver for this branch. Map each branch phase to the root worklog when needed.

All commands named in acceptance criteria must be treated as required deliverables. If a command does not exist yet, add it to `build.zig` or explicitly map it in `WORKLOG.md` to an existing command with equivalent coverage. Do not leave phase gates as imaginary commands.

### Phase 1. Define Physical IR

**Goal:** add a compact physical representation below Flow IR.

Required work:

1. Create `physical_ir.zig`.
2. Define:
   - `PhysicalProgram`
   - `PhysicalSlot`
   - `SourceSlot`
   - `StateSlot`
   - `Instruction`
   - `DependencyEdge`
   - `BranchTable`
   - `ListTable`
   - `RenderBlueprint`
   - `SemanticId`
   - `PhysicalId`
3. Add lowering:
   - Flow IR → Physical IR
4. Add golden tests:
   - `counter`
   - `complex_counter` after migration
   - `todo_mvc` source interface slices
   - `list_map_block`
   - `while`
   - `text_interpolation_update`
5. Add diagnostics for:
   - invalid `SOURCE`
   - legacy `|> LINK`
   - incompatible source binding
   - dynamic source shape
   - multiple active binders

Acceptance criteria:

```text
zig build test-physical-ir
```

or equivalent command passes.

Golden tests show static numeric source slots for `SOURCE` fields.

No generic pipe-link assignment exists in canonical Physical IR.

### Phase 2. Build fast Zig interpreter for Physical IR

**Goal:** execute Physical IR without dynamic name lookup.

Required work:

1. Implement typed slot arrays.
2. Implement explicit dirty/event queue.
3. Implement source slot state:
   - unplugged
   - plugged(binding_id)
4. Implement `HOLD` state arenas.
5. Implement `LATEST`, `THEN`, `WHEN`, `WHILE`, `SKIP`, `BLOCK`.
6. Implement `PASS/PASSED` lowering before runtime.
7. Implement list key/scope preservation:
   - list IDs
   - item IDs
   - generational IDs
   - mapped scope reuse
8. Implement deterministic virtual time.
9. Implement `List/latest` fan-in with stale child event rejection.
10. Implement trace log.
11. Implement persistence behind runtime interface, but allow disabled persistence for benchmarks/playground.

Acceptance criteria:

```text
zig build test-runtime
zig build test-headless-counter
zig build test-headless-list-keys
zig build test-headless-while
```

No hot runtime path uses string keys for source dispatch or value lookup.

### Phase 3. Make terminal/headless examples pass

**Goal:** prove correctness on representative examples before browser work.

Required examples:

```text
counter
interval
cells
cells_dynamic or equivalent non-UI pipe-link regression
todo_mvc
pong
arkanoid
```

Required hosts:

```text
headless
terminal deterministic snapshot backend
interactive terminal smoke where relevant
```

Required work:

1. Import/migrate upstream examples.
2. Add `SOURCE` canonical versions.
3. Add terminal projections where browser visuals cannot be exact.
4. Implement virtual keyboard/mouse/input events.
5. Implement terminal grid snapshot renderer.
6. Add deterministic tests for:
   - counter clicks and persistence on/off
   - interval deterministic virtual-time ticks, pause/reset if applicable, no real-time flakiness
   - cells formulas, edits, enter/escape, recomputation
   - cells_dynamic or equivalent non-UI pipe-link regression using `List/latest` fan-in, removed-item stale-event rejection, and no event-bus/publish workaround
   - todo_mvc add/edit/toggle/remove/filter
   - pong frames/keyboard/score/reset
   - arkanoid ball/paddle/bricks/reset

Acceptance criteria:

```text
zig build verify-examples-headless
zig build verify-examples-terminal
```

Each required example is marked `DONE` in the corpus manifest with evidence.

### Phase 4. Add Boon → Zig codegen from the same Physical IR

**Goal:** compile Boon to efficient Zig using Physical IR, not by translating source syntax naively.

Required work:

1. Create codegen module:
   - `codegen_zig.zig`
2. Emit:
   - app state struct
   - typed slots
   - source slot table
   - render blueprint table
   - update functions
   - event dispatch functions
   - branch activation functions
   - list/map scope structs
3. Reuse hand-written runtime library for:
   - queues
   - source slot binding
   - retained rendering abstractions
   - persistence
   - host services
4. Generate source maps:
   - Boon span → generated Zig span
   - SemanticId → Boon source path
5. Generate readable-but-fast Zig:
   - compact arrays where possible
   - typed structs for records/lists where possible
   - no generated string lookups in hot path
6. Add compile tests:
   - generated Zig builds
   - generated Zig runs same headless tests as interpreter
   - generated Zig passes benchmark smoke tests

Acceptance criteria:

```text
zig build test-codegen-zig
zig build run-generated-counter
zig build run-generated-todo-mvc-headless
```

Generated Zig must pass the same semantic tests as the interpreter for required examples.

### Phase 5. Add retained browser renderer

**Goal:** browser UI with direct patches, no Virtual DOM.

Required work:

1. Implement browser renderer abstraction:
   - node creation
   - direct text/style/property patches
   - event/source binding
   - child list operations
2. Keep retained node table:
   - `RenderNodeId -> DOM node`
   - source binding IDs
   - dirty fields
3. Integrate with Wasm host boundary.
4. Add browser smoke tests:
   - counter
   - todo_mvc
   - cells subset
5. Add visual regression tests for `todo_mvc`.
6. Make browser renderer share the same source slot semantics as terminal/headless.

Acceptance criteria:

```text
zig build test-browser-smoke
zig build test-browser-visual
```

Browser updates must not rebuild the whole document tree per event.

### Phase 6. Add required Zig playground support

**Goal:** provide production playground support for Boon → Zig compilation.

This phase is required.

The branch must support at least one complete playground compile path:

#### Preferred path

```text
browser editor
→ Boon parser/lowerer
→ Physical IR
→ generated Zig
→ Zig compiler running in browser worker
→ Wasm output
→ preview
```

#### Required fallback if browser Zig compiler is not viable

```text
browser editor
→ Boon parser/lowerer
→ Physical IR
→ generated Zig
→ edge/server Zig compiler
→ Wasm output
→ preview
```

The UI/API should be the same so the compiler location can change without changing user workflow.

Required work:

1. Prototype browser-hosted Zig compiler:
   - evaluate `zig.wasm` / WASI-based compiler options
   - run inside Web Worker
   - cache compiler artifacts
   - cancel stale compile jobs
2. Add edge/server fallback:
   - same request/response shape
   - deterministic cache keys
   - sandboxed compile
   - timeout and size limits
3. Add playground modes:
   - instant interpreter preview
   - compile-to-Zig preview
   - generated Zig viewer
   - diagnostics viewer
4. Add source maps:
   - Boon error mapping
   - generated Zig error mapping back to Boon where possible
5. Add compile/test examples:
   - `counter`
   - `todo_mvc`
   - `cells` subset or headless mode
6. Add size/performance budgets:
   - compiler bundle size
   - generated Zig size
   - compile latency
   - Wasm output size
7. Document which compiler path is active:
   - browser Zig
   - edge/server Zig
   - local Zig

Acceptance criteria:

```text
playground can run counter through Boon → Zig → Wasm/native preview
playground can run todo_mvc through Boon → Zig → Wasm/browser preview or approved fallback
generated Zig can be inspected
Boon diagnostics map to Boon source
phase is marked DONE, not skipped
```

---

## 13. Example migration sketches

### 13.1 Counter

Canonical new form:

```boon
document: Document/new(root: Element/stripe(
    element: []
    direction: Column
    gap: 0
    style: []

    items: LIST {
        counter
        increment_button
    }
))

counter:
    LATEST {
        0
        increment_button.event.press |> THEN { 1 }
    }
    |> Math/sum()

increment_button: Element/button(
    element: [event: [press: SOURCE]]
    style: []
    label: TEXT { + }
)
```

### 13.2 Complex counter

Old pipe-link style:

```boon
counter_button(label: TEXT { - })
|> LINK { PASSED.store.elements.decrement_button }
```

New source style:

```boon
store: [
    sources: [
        decrement_button: [event: [press: SOURCE], hovered: SOURCE]
        increment_button: [event: [press: SOURCE], hovered: SOURCE]
    ]

    counter:
        0
        |> HOLD counter {
            LATEST {
                sources.decrement_button.event.press |> THEN { counter - 1 }
                sources.increment_button.event.press |> THEN { counter + 1 }
            }
        }
]

FUNCTION root_element() {
    Element/stripe(
        element: []
        direction: Row
        gap: 15
        style: [align: Center]

        items: LIST {
            counter_button(
                sources: PASSED.store.sources.decrement_button
                label: TEXT { - }
            )

            PASSED.store.counter

            counter_button(
                sources: PASSED.store.sources.increment_button
                label: TEXT { + }
            )
        }
    )
}

FUNCTION counter_button(sources, label) {
    Element/button(
        element: [
            ...sources
        ]

        style: [
            width: 45
            rounded_corners: Fully

            background: [
                color: Oklch[
                    lightness:
                        sources.hovered
                        |> WHEN {
                            True => 0.85
                            False => 0.75
                        }

                    chroma: 0.07
                    hue: 320
                ]
            ]
        ]

        label: label
    )
}
```

### 13.3 TodoMVC top-level source store

```boon
store: [
    sources: [
        filter_buttons: [
            all: [event: [press: SOURCE], hovered: SOURCE]
            active: [event: [press: SOURCE], hovered: SOURCE]
            completed: [event: [press: SOURCE], hovered: SOURCE]
        ]

        remove_completed_button: [
            event: [press: SOURCE]
            hovered: SOURCE
        ]

        toggle_all_checkbox: [
            event: [click: SOURCE]
        ]

        new_todo_title_text_input: [
            event: [
                change: SOURCE
                key_down: SOURCE
                blur: SOURCE
                focus: SOURCE
            ]
        ]
    ]

    title_to_add:
        sources.new_todo_title_text_input.event.key_down.key
        |> WHEN {
            Enter => BLOCK {
                trimmed:
                    sources.new_todo_title_text_input.event.key_down.text
                    |> Text/trim()

                trimmed
                |> Text/is_not_empty()
                |> WHEN {
                    True => trimmed
                    False => SKIP
                }
            }

            __ => SKIP
        }

    navigation_result:
        LATEST {
            sources.filter_buttons.all.event.press |> THEN { TEXT { / } }
            sources.filter_buttons.active.event.press |> THEN { TEXT { /active } }
            sources.filter_buttons.completed.event.press |> THEN { TEXT { /completed } }
        }
        |> Router/go_to()
]
```

### 13.4 TodoMVC text input

```boon
FUNCTION new_todo_title_text_input() {
    BLOCK {
        sources: PASSED.store.sources.new_todo_title_text_input

        Element/text_input(
            element: [
                ...sources
            ]

            label: Hidden[text: TEXT { What needs to be done? }]

            text:
                LATEST {
                    Text/empty()
                    sources.event.change.text
                    PASSED.store.title_to_add |> THEN { Text/empty() }
                }

            placeholder: [
                text: TEXT { What needs to be done? }
            ]

            focus: True
        )
    }
}
```

### 13.5 TodoMVC per-item sources

```boon
FUNCTION new_todo(title) {
    [
        sources: [
            remove_todo_button: [
                event: [press: SOURCE]
                hovered: SOURCE
            ]

            editing_todo_title_element: [
                event: [
                    change: SOURCE
                    key_down: SOURCE
                    blur: SOURCE
                ]
            ]

            todo_title_element: [
                event: [double_click: SOURCE]
            ]

            todo_checkbox: [
                event: [click: SOURCE]
            ]
        ]

        title:
            LATEST {
                title

                sources.editing_todo_title_element.event.change.text
                |> WHEN {
                    changed_text =>
                        changed_text
                        |> Text/is_not_empty()
                        |> WHEN {
                            True => changed_text
                            False => SKIP
                        }
                }
            }

        editing:
            False
            |> HOLD state {
                LATEST {
                    sources.todo_title_element.event.double_click |> THEN { True }

                    sources.editing_todo_title_element.event.key_down.key
                    |> WHEN {
                        Enter => False
                        Escape => False
                        __ => SKIP
                    }

                    sources.editing_todo_title_element.event.blur |> THEN { False }
                }
            }

        completed:
            False
            |> HOLD state {
                LATEST {
                    sources.todo_checkbox.event.click |> THEN { state |> Bool/not() }

                    store.sources.toggle_all_checkbox.event.click
                    |> THEN { store.all_completed |> Bool/not() }
                }
            }
    ]
}
```

### 13.6 TodoMVC per-item view

`Reference[element: ...]` must receive an actual element value, not a `sources` record. Therefore the title label should be bound to a local element value before it is referenced by the checkbox.

```boon
FUNCTION todo_item(todo) {
    BLOCK {
        title_label:
            Element/label(
                element: [
                    ...todo.sources.todo_title_element
                ]

                style: [
                    width: Fill

                    font: [
                        size: 24

                        color:
                            todo.completed
                            |> WHILE {
                                True => Oklch[lightness: 0.647]
                                False => Oklch[lightness: 0.42]
                            }

                        line: [strikethrough: todo.completed]
                    ]
                ]

                label: todo.title
            )

        edit_input:
            Element/text_input(
                element: [
                    ...todo.sources.editing_todo_title_element
                ]

                label: Hidden[text: TEXT { Edit todo }]
                text: ...
                focus: True
            )

        checkbox:
            Element/checkbox(
                element: [
                    ...todo.sources.todo_checkbox
                ]

                label: Reference[element: title_label]
                checked: todo.completed
                icon: ...
            )

        Element/stripe(
            element: [hovered: SOURCE]
            direction: Row
            gap: 10

            items: LIST {
                checkbox

                todo.editing
                |> WHILE {
                    True => edit_input
                    False => title_label
                }

                element.hovered
                |> WHILE {
                    True => remove_todo_button(
                        sources: todo.sources.remove_todo_button
                    )

                    False => NoElement
                }
            }
        )
    }
}
```

Important rules:

- `todo.sources.todo_title_element` is only a source bag.
- `title_label` is the actual element value.
- `Reference[element: title_label]` is valid.
- `Reference[element: todo.sources.todo_title_element]` is invalid.
- Runtime retained node handles are internal Physical IR data, not hidden Boon values.

---

## 14. List combinators and custom functions

### 14.1 `List/map` binder is not `SOURCE`

Do not use `SOURCE` or `LINK` for map binders.

This:

```boon
items |> List/map(item, new: todo_item(todo: item))
```

means:

```text
for each item, bind lexical item variable
```

It is not a runtime source interface.

### 14.2 Keep `List/map` compiler-known for now

A normal Boon function cannot introduce a special call-site binder like `item` unless the language gets a custom combinator feature.

So for this branch:

```text
List/map, List/retain, List/fold, List/latest, etc. are compiler-known builtins.
```

User functions can wrap them:

```boon
FUNCTION visible_todos(todos, selected_filter) {
    todos
    |> List/retain(
        todo,
        if:
            selected_filter
            |> WHILE {
                All => True
                Active => todo.completed |> Bool/not()
                Completed => todo.completed
            }
    )
}
```

But users cannot define a brand-new map-like binder as an ordinary function yet.

### 14.3 `List/latest` fan-in semantics

`List/latest` is required because removing generic pipe-link cannot leave dynamic child-to-parent computed events without a graph-native replacement. It is a compiler-known dynamic fan-in combinator, not a user-defined event bus.

Input shape:

```boon
streams |> List/latest()
```

where `streams` is a list whose items are reactive/event values with compatible payload shapes. If the parent needs item context, the child stream must be mapped to an explicit payload before fan-in:

```boon
views
|> List/map(view, new:
    view.remove_requested
    |> THEN { [todo: view.todo] }
)
|> List/latest()
```

Required semantics:

1. **Empty list**: emits nothing. It is not an error.
2. **Added item**: subscribes to the new child stream after the item and mapped scope are created. No same-turn feedback should be observable unless an explicit host/source event occurs after the binding becomes active.
3. **Removed item**: unsubscribes before removed-child events can affect later turns. Late events from removed item scopes are stale and ignored.
4. **Reordered item**: keeps the child's mapped scope and `HOLD` state by stable list item key; only output ordering changes.
5. **Multiple child emissions in one atomic turn**: emit deterministically in list order as observed at the beginning of the fan-in delivery phase, with stable item key as tie-breaker if needed. Do not use hash-map order.
6. **Payload**: output exactly the child payload. There is no implicit item ID or hidden identity in the user value.
7. **Compatibility**: all child payload shapes must unify statically. If they do not, produce a compile error.
8. **Backpressure/coalescing**: `List/latest` itself must not silently drop child emissions. If a downstream `LATEST` or `HOLD` collapses several events according to normal Boon turn semantics, that behavior belongs to the downstream combinator and must be tested separately.

Operational lowering requirements:

- Add `List/latest` deliberately to the parser/lowering/runtime builtin map and Zig codegen support. Do not assume it already exists.
- Lower the input list to a fan-in table keyed by `(list_id, map_site_id, stable_item_key, item_generation)`.
- Each child subscription records the item generation active at subscription time.
- A delivery from a child whose item generation no longer matches is stale and must be ignored.
- Empty fan-in has no current value and emits no event. It must not emit `[]`, `False`, `UNPLUGGED`, or a synthetic placeholder.
- Multiple child deliveries in one turn are delivered in deterministic list order based on the list snapshot at the beginning of the fan-in delivery phase. If two deliveries come from the same item in the same turn, preserve normal source delivery order for that item.
- Reordering a list does not recreate mapped child scopes. It only changes deterministic fan-in order for later multi-child turns.
- Removing an item tears down its fan-in subscription before later turns. Queued deliveries from the removed item are rejected by generation/epoch checks.
- Payload values contain no implicit item identity. If user code needs the item/cell/todo, it must return it explicitly in the payload.

Required tests:

```text
list_latest_empty_emits_nothing
list_latest_single_child_forwards_payload
list_latest_multiple_children_deterministic_order
list_latest_removed_child_stale_event_ignored
list_latest_reordered_child_preserves_state
list_latest_payload_shape_mismatch_diagnostic
list_latest_with_todo_remove_payload
list_latest_cells_dynamic_fan_in_regression
```

Implementation notes:

- `List/latest` may not currently exist in every runtime builtin map. Add it deliberately to parser/lowering/runtime/codegen instead of assuming it exists.
- The fast interpreter should lower it to a list fan-in table keyed by list ID + map site + item key, not to dynamic source lookup.
- The Zig backend should emit static fan-in code where possible and reuse existing source-of-truth list operation code where needed, with a compact runtime table for dynamic lists.

### 14.4 Future feature

If needed later, design a separate construct. This branch must not introduce `List/update` or another new source-of-truth update operator without a separate spec:

```text
COMBINATOR
EACH
FOR
```

Do not overload `SOURCE`.

---

## 15. Ownership and lifetime rules

### 15.1 Source interfaces are non-owning

`store.sources.*` and `todo.sources.*` do not own elements.

They are stable source slots/interfaces.

### 15.2 UI branches own concrete nodes

The owner of a concrete element is the document/page/component branch that renders it.

When a branch disappears:

```text
concrete element unmounts
source slot unplugged
late events ignored
state owned by that branch destroyed unless explicitly held elsewhere
```

### 15.3 Domain store should not own UI nodes

This branch should lint against storing concrete `Element/*` values in long-lived domain stores unless explicitly intended.

Good:

```boon
store: [
    sources: [...]
    todos: ...
]
```

Bad or suspicious:

```boon
store: [
    save_button: Element/button(...)
]
```

### 15.4 Source of truth vs derived lists

This remains a semantic issue that must be represented in IR.

For source-of-truth chains, `List/retain` / remove-like operations may destroy item ownership.

For derived views, they must only filter.

Example:

```boon
todos_after_remove:
    todos_after_append
    |> List/remove(item, on: item.sources.remove_todo_button.event.press)
```

is source-of-truth mutation.

Example:

```boon
todos
|> List/retain(item, if: item.completed)
|> List/count()
```

is derived filtering/counting.

Physical IR must distinguish these cases.

---

## 16. Diagnostics to add

### 16.1 Legacy pipe-link

Input:

```boon
button() |> LINK { store.elements.button }
```

Diagnostic:

```text
`|> LINK { ... }` was removed.

Declare a source interface:

    store: [
        sources: [
            button: [event: [press: SOURCE]]
        ]
    ]

Then pass it into the component:

    button(sources: store.sources.button)

or spread it into the element bag:

    Element/button(element: [...store.sources.button])
```

### 16.1a Legacy terminal host source reference

Diagnostic when a terminal/timer/game host field still points to `store.elements.*` or another legacy `LINK` path:

```text
legacy terminal host source reference

`link:` / `pulse:` host metadata must point to a `SOURCE` slot under `sources`.
Rewrite `store.elements.tick_button` to `store.sources.tick_button.event.press` and declare that slot as `[event: [press: SOURCE]]`, using the host boundary schema to infer payload type.
```

### 16.2 `LINK` keyword in canonical mode

Input:

```boon
event: [press: LINK]
```

Diagnostic:

```text
`LINK` was renamed to `SOURCE`.
Use `event: [press: SOURCE]`.
```

Legacy mode may auto-rewrite.

### 16.3 `SOURCE` in non-source expression

Input:

```boon
x: SOURCE + 1
```

Diagnostic:

```text
`SOURCE` marks a runtime source field and cannot be used as a normal value.
Put it inside a source interface record and bind it through an element bag.
```

### 16.4 Dynamic source shape

Input:

```boon
element: [
    ...condition |> WHEN {
        True => [hovered: SOURCE]
        False => []
    }
]
```

Diagnostic:

```text
SOURCE-bearing element records must have statically known shape.
Move the conditional outside the source declaration or declare both branches with compatible source shape.
```

### 16.5 Multiple active binders

Input:

```boon
Element/button(element: [...store.sources.save_button])
Element/button(element: [...store.sources.save_button])
```

Diagnostic:

```text
source slot `store.sources.save_button` is bound by multiple active elements.
Use distinct source slots or make the binders mutually exclusive.
```

---

## 17. Test matrix

### 17.1 Syntax tests

- `SOURCE` parses.
- `LINK` rejected in canonical mode.
- `LINK` accepted only in legacy migration mode.
- `|> LINK { ... }` rejected in canonical mode.
- record spread in `element` bag parses.
- `SOURCE` in invalid expression rejected.

### 17.2 HIR/Flow tests

- source interfaces lower to explicit source slots.
- element spread of source interface creates binding site.
- no pipe-link assignment node exists.
- `PASS/PASSED` source access lowers to explicit slots.
- `BLOCK` dependencies resolve without runtime maps.

### 17.3 Physical IR tests

- `counter` has fixed source slot for press.
- `complex_counter` has two source slots for decrement/increment.
- `todo_mvc` has fixed source slots for:
  - new todo input key down/change/blur/focus
  - filter buttons press/hover
  - remove completed press/hover
  - per-item checkbox/title/edit/remove events
- `WHILE` branch source binding/unbinding is deterministic.
- list map scopes are stable across append/remove/filter.

### 17.3a List fan-in tests

Required `List/latest` tests:

```text
list_latest_empty_emits_nothing
list_latest_single_child_forwards_payload
list_latest_multiple_children_deterministic_order
list_latest_removed_child_stale_event_ignored
list_latest_reordered_child_preserves_state
list_latest_payload_shape_mismatch_diagnostic
list_latest_with_todo_remove_payload
list_latest_cells_dynamic_fan_in_regression
```

### 17.4 Runtime tests

- stale events ignored.
- unplugged sources do not crash.
- multiple active binder debug assertion.
- mutually exclusive compatible binders work.
- incompatible binders compile error.
- source payload types inferred from host schemas.

### 17.5 Renderer tests

- retained terminal snapshot updates exact cells/regions.
- retained browser renderer patches text/style/property without full tree rebuild.
- list item removal preserves state of remaining items.
- TodoMVC interactions pass.

### 17.6 Zig codegen tests

- generated Zig builds for `counter`.
- generated Zig builds for `todo_mvc`.
- generated Zig runtime output matches interpreter.
- generated Zig has no hot string lookups for source dispatch.
- generated Zig can be inspected in playground.

### 17.7 Playground tests

- browser editor can run interpreter preview.
- browser/editor can generate Zig.
- playground can compile at least `counter` through Zig path.
- playground can compile or approved-fallback compile `todo_mvc`.
- errors map back to Boon source.

---

## 18. Benchmark plan

### 18.1 Benchmark modes

Run benchmarks in at least these modes:

```text
fast interpreter, persistence disabled
fast interpreter, persistence enabled
generated Zig, persistence disabled
generated Zig, persistence enabled
browser retained renderer
terminal retained renderer
```

### 18.2 Benchmark scenarios

Required:

- counter burst clicks
- TodoMVC add 100/1000 items
- TodoMVC toggle all
- TodoMVC filter switching
- TodoMVC remove completed
- cells formula recomputation
- list map/retain churn
- WHILE branch switching
- text interpolation updates

### 18.3 Metrics

Track:

```text
parse time
HIR/Flow lowering time
Physical IR lowering time
interpreter execution time per event
generated Zig compile time
generated Zig runtime per event
renderer patch count
DOM/node allocation count
source binding count
source stale event drops
memory usage
Wasm size
playground compile latency
```

### 18.4 Performance principles

- no string/hash lookup in hot source dispatch
- no full UI rebuild per event
- no Virtual DOM diffing
- no actor allocation per small expression update
- no generic tagged values where fixed layout is inferred
- no list remap destroying stable item scopes

---

## 19. Repo structure additions

Add or update:

```text
src/
  physical_ir.zig
  lower_physical.zig
  codegen_zig.zig
  source_shape.zig
  source_bindings.zig
  runtime/
    physical_interpreter.zig
    slots.zig
    source_slots.zig
    list_keys.zig
    branch_activation.zig
  render/
    retained_document.zig
    retained_terminal.zig
    retained_browser_dom.zig
  tools/
    migrate_link_to_source.zig
    verify_no_pipe_link.zig
    inspect_physical_ir.zig
  playground/
    compiler_worker/
    edge_compile/
    generated_zig_viewer/
fixtures/
  source_migration/
  physical_ir_golden/
  generated_zig_golden/
  upstream_pin.json
```

Update:

```text
PLAN.md
WORKLOG.md
fixtures/syntax_inventory.json
fixtures/feature_matrix.md
fixtures/corpus_manifest.json
fixtures/upstream_pin.json
```

Pinned corpus metadata rule:

- The upstream checkout directory may live under `third_party/boon-upstream/` and may remain ignored by `.gitignore`.
- The tracked pin must live outside ignored third-party checkout paths, preferably `fixtures/upstream_pin.json`.
- `fixtures/upstream_pin.json` must include at least:

```json
{
  "repo": "https://github.com/BoonLang/boon",
  "commit": "<exact upstream commit>",
  "tree_hash": "<computed imported corpus hash>",
  "generated_at": "<iso timestamp>",
  "notes": "Pinned corpus used for this branch."
}
```

Do not require a tracked `third_party/boon-upstream/COMMIT` file unless `.gitignore` explicitly unignores that metadata path.

---

## 20. Worklog expectations

Every implementation session must update `WORKLOG.md` with:

```text
phase/subphase
files changed
commands run
pass/fail results
remaining risks
blockers
next exact step
```

Do not mark a phase complete without evidence.

For each upstream example, manifest status must be one of:

```text
DONE
PARTIAL
BLOCKED
NOT_STARTED
```

No silent skips.

---

## 21. Definition of done

This branch is done when:

1. Canonical Boon syntax uses `SOURCE`, not `LINK`.
2. Canonical Boon syntax has no `|> LINK { ... }`.
3. `store.sources` / `todo.sources` migration works for TodoMVC and physical TodoMVC patterns.
4. `SOURCE` source slots lower to static Physical IR.
5. Physical IR exists and has golden tests.
6. Fast interpreter executes Physical IR without hot string lookup.
7. `List/latest` dynamic fan-in has runtime and codegen tests for empty lists, ordering, removed items, stale events, and payload shape mismatch.
8. Required headless/terminal examples pass:
   - `counter`
   - `interval`
   - `cells`
   - `cells_dynamic` or named equivalent non-UI pipe-link regression
   - `todo_mvc`
   - `pong`
   - `arkanoid`
9. Boon → Zig codegen exists from the same Physical IR.
10. Generated Zig passes semantic tests for at least `counter` and `todo_mvc`.
11. Browser renderer is retained and does not use Virtual DOM.
12. Browser smoke/visual tests pass for required UI examples.
13. Required Zig playground support exists:
    - interpreter preview
    - generated Zig view
    - compile-to-Zig path
    - Boon → Zig → Wasm/native preview via browser Zig or edge/server fallback
14. Diagnostics map to Boon source.
15. No hidden element identity exists in source records; `Reference[element: ...]` accepts real element values only.
16. No new user-facing `IDENTITY`, `CHANNEL`, `Source/publish`, `Stream/emit`, or event-bus workaround exists.
17. Worklog and corpus manifest show no skipped required items.

---

## 22. Open questions to resolve during implementation

### 22.1 Direct `element: sources` shorthand

Should this be canonical?

```boon
Element/button(
    element: sources
)
```

or should formatter always expand to:

```boon
Element/button(
    element: [
        ...sources
    ]
)
```

Recommendation:

```text
parser may accept both
formatter should prefer element: [...sources] for clarity
```

### 22.2 Element references and source records

Resolved for v3:

```text
sources records are not element values
Reference[element: ...] accepts real element values only
no IDENTITY keyword
no hidden element handle inside sources
```

Use local element values or explicit returned element fields when a component needs to pass an element reference outward.

Valid:

```boon
BLOCK {
    title_label: Element/label(...)

    Element/checkbox(
        element: [...]
        label: Reference[element: title_label]
        checked: todo.completed
    )
}
```

Invalid:

```boon
Reference[element: todo.sources.title_label]
```

Internal retained node IDs are Physical IR/runtime implementation details only.

### 22.3 Compatibility with upstream examples

Should upstream exact corpus be stored as legacy source and generated canonical source side-by-side?

Recommendation:

```text
yes
```

Use:

```text
examples/upstream_legacy/
examples/upstream_canonical/
```

or manifest fields:

```text
legacy_source_path
canonical_source_path
migration_status
```

### 22.4 Browser Zig compiler feasibility

Browser Zig compiler must be evaluated. If too unstable/heavy, use edge/server fallback but keep the playground compile API identical.

Phase 6 remains required either way.

---

## 23. Suggested first implementation steps

1. Create branch.
2. Add this document as `PLAN_SOURCE_PHYSICAL_IR.md` or merge into `PLAN.md`.
3. Update syntax inventory:
   - add `SOURCE`
   - mark `LINK` legacy
   - mark `|> LINK` removed
4. Add migration tool skeleton.
5. Add parser tests for `SOURCE`.
6. Add canonical counter example.
7. Add source interface shape lowering.
8. Add first Physical IR golden for counter.
9. Update `WORKLOG.md`.
10. Continue with Phase 1.

---

## 24. Core mantra

```text
Friendly Boon source.
Strict static lowering.
Typed physical slots.
Retained UI.
Generated Zig.
No arbitrary pipe-link patching.
No Virtual DOM.
No hot string lookup.
```


---

## 24.1 Corpus pinning vs external links

External reference URLs are context only. The implementation source of truth for upstream Boon examples is the pinned imported corpus recorded in `fixtures/upstream_pin.json` and `fixtures/corpus_manifest.json`. Do not depend on mutable `main` URLs during implementation or verification.

---

## 25. External references

These are planning inputs, not normative specifications:

- Boon-on-Zig current plan: https://raw.githubusercontent.com/BoonLang/boon-zig/main/PLAN.md
- Boon upstream repository: https://github.com/BoonLang/boon
- Current TodoMVC example: https://raw.githubusercontent.com/BoonLang/boon/main/playground/frontend/src/examples/todo_mvc/todo_mvc.bn
- Current physical TodoMVC example: https://raw.githubusercontent.com/BoonLang/boon/main/playground/frontend/src/examples/todo_mvc_physical/RUN.bn
- Zig downloads / current releases: https://ziglang.org/download/
- Browser Zig compiler/playground reference: https://github.com/zigtools/playground
- WASI Zig compiler reference: https://github.com/Afirium/wasi-zigc
- Dominator crate reference: https://crates.io/crates/dominator
- MoonZoon signal/no-Virtual-DOM article: https://dev.to/martinkavik/moonzoon-dev-news-3-signals-react-like-hooks-optimizations-39lp
