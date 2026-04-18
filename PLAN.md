# Boon-on-Zig implementation plan for interactive Codex CLI

This file is intended to be the only bootstrap document in a new GitHub repository. Put it at the repository root as `PLAN.md`, start interactive Codex CLI, select `gpt-5.4` with high reasoning effort in the interactive UI, and tell Codex to read this file and begin. Do **not** require `.codex/config.toml`, `AGENTS.md`, or any other bootstrap file unless Codex later proves a repo-local config is genuinely useful.

The work is intentionally split into resumable phases because interactive Codex sessions may stop too early. Every session must continue from the earliest incomplete phase, update `WORKLOG.md`, and leave the repository in a verified state or with a concrete blocker.

---

## 0. Highest-priority outcome

Build a Zig implementation of Boon that can parse, run, test, and render the current Boon playground corpus, with this priority order:

1. **Native/headless correctness first**: parser, lowering, flow runtime, deterministic event simulation, persistence, and example tests.
2. **Terminal renderer second**: fast native feedback loop controlled from the terminal. This must prove that Boon works outside the browser.
3. **Browser renderer last**: browser tests are slow; only run them after headless and terminal tests are already green.

The most important examples are hard gates:

| Priority | Example | Required host(s) | Required result |
|---:|---|---|---|
| P0 | `counter` | headless, terminal, browser smoke later | Exact upstream semantics: `0+`, clicks increment, persistence survives restart, clear-state resets. |
| P0 | `interval` | headless, terminal | Deterministic virtual-time timer increments. No real-time flakiness in tests. |
| P0 | `cells` | headless, terminal | Current upstream Boon code imported exactly; spreadsheet semantics and terminal interaction tested. |
| P0 | `pong` | headless, terminal | New Boon terminal example authored in this repo; deterministic keyboard/frame tests. |
| P0 | `arkanoid` | headless, terminal | New Boon terminal example authored in this repo; deterministic ball, paddle, brick tests. |
| P0 | `todo_mvc` | headless, terminal semantic smoke, browser visual final | Browser visual must match the official upstream reference image/metadata as closely as measurable. |
| P1 | all other current playground examples | headless, terminal where meaningful, browser final smoke | No current upstream example may be silently skipped. |
| P1 | `todo_mvc_physical` | parse/headless first, terminal doc/projection, browser/3D later | Track physical renderer TODOs including `Model/cut(from, remove)` and SDF boolean subtraction. |

---

## 1. Start and resume prompt for interactive Codex

Use this **same prompt** to start the repo and to resume when Codex stops prematurely:

```text
Read PLAN.md first. If WORKLOG.md exists, read it too. Then inspect the repo.

You are implementing Boon-on-Zig in interactive Codex CLI.
Continue from the earliest incomplete phase/subphase in PLAN.md. If nothing exists yet, begin at Phase 0.
Do not ask for confirmation. Do not jump ahead. Do not treat a partial patch as enough.

Before editing, briefly state the current phase/subphase and a short plan.
Then implement exactly that phase/subphase.

Rules:
- Keep changes minimal and local to the current phase/subphase.
- Run the verification commands required by that phase before stopping.
- If tests fail, keep fixing until they pass or until you hit a concrete blocker.
- If blocked, stop cleanly and update WORKLOG.md with the exact blocker, evidence, commands run, current failures, and the exact next step.
- If not blocked, update WORKLOG.md with the phase/subphase, files changed, commands run, pass/fail results, remaining risks, and the exact next step.
- Never silently skip a playground example. Every upstream example must appear in the manifest as DONE, PARTIAL, BLOCKED, or NOT_STARTED with a reason.
- Browser tests are last. Prefer parser, headless, and terminal verification before browser work.
- `LIST { ... }` is the main dynamic/software list form. `LIST[8] { ... }`, `BITS[8]`, `BYTES[4]`, and `MEMORY[16]` are fixed/static/HDL-oriented unless evidence says otherwise.
```

---

## 2. Final verification prompt

Use this when you believe the implementation is complete:

```text
Read PLAN.md and WORKLOG.md. Perform a full completion audit against every phase, hard gate, example, and definition-of-done item in PLAN.md.

Do not only inspect the last phase. Compare the whole repository to the whole plan.
Run all relevant verification commands.

For each phase, each P0/P1 example, and each final definition-of-done item, mark it:
- DONE
- PARTIAL
- NOT DONE
- BLOCKED

For DONE items, provide concrete evidence: files, tests, commands, snapshots, manifests, or logs.
For PARTIAL/NOT DONE/BLOCKED items, list the exact missing pieces and the next phase/subphase to continue.

Fix only tiny obvious low-risk issues inline. Do not start a large new implementation during the audit.
Update WORKLOG.md with the audit summary, commands run, pass/fail results, remaining gaps ordered by importance, and exact next recommended step.
```

---

## 3. Non-negotiable project decisions

### 3.1 Fresh repository workflow

The user wants to create a fresh GitHub repository and add this file as `PLAN.md`. Therefore:

- Do not require repo-scoped `.codex/config.toml`.
- Do not require `AGENTS.md`.
- Do create `WORKLOG.md` during Phase 0.
- Do keep all repo-specific instructions in this file unless the project genuinely outgrows it.

### 3.2 Zig version and async/runtime approach

Target **Zig 0.16.x**.

Use `std.Io` at host boundaries: timers, terminal input, filesystem persistence, browser-dev tooling, sockets if any, and later browser/wasm glue.

Baseline backend:

- `Io.Threaded` is the required supported backend for native work.
- Keep host services `std.Io`-generic.
- Do not let Boon semantics depend on Zig thread scheduling.
- Boon’s core runtime must remain a deterministic reactive graph runtime.

Experimental backend:

- Add `Io.Evented` only as an opt-in experimental smoke lane after native/headless/terminal correctness is stable.
- It may be valuable for green-thread-style host tasks, timers, and future high-concurrency hosts.
- Problems to expect: incomplete functions, weaker test coverage, changing APIs, stack-size issues, performance cliffs, and missing networking support in Zig 0.16.
- Do not block P0/P1 work on `Io.Evented`.

### 3.3 Storage choice

Use storage in this order:

1. Native/headless: deterministic file-backed store under `.zig-cache/boon-state` or a test temp directory.
2. Terminal/native interactive: file-backed store with explicit state directory flag.
3. Browser: IndexedDB or OPFS/structured async storage.

Do **not** make LocalStorage the main browser persistence backend. LocalStorage may exist only as a compatibility importer/exporter for old playground states.

### 3.4 Testing order

Browser automation is slow and fragile, so it is deliberately last.

The required validation ladder is:

1. Lexer/parser unit tests.
2. HIR/Flow IR golden tests.
3. Runtime unit tests.
4. Headless example tests with virtual time and virtual input.
5. Terminal renderer snapshot tests using a headless grid backend.
6. Interactive terminal manual smoke tests.
7. Browser wasm/dom smoke tests.
8. Browser visual regression tests, especially `todo_mvc`.

### 3.5 `LIST` semantics

`LIST { ... }` is the normal dynamic/software list. It can grow/shrink and is used in current software examples.

`LIST[8] { ... }`, `LIST[__] { ... }`, `BITS[8]`, `BYTES[4]`, and `MEMORY[16]` are fixed-size/static/HDL-oriented or compile-time-size-aware forms.

The implementation must make this distinction visible in parser, IR, runtime, diagnostics, docs, and tests.

---

## 4. Sources of truth

Use a pinned upstream checkout of `https://github.com/BoonLang/boon` as the corpus and reference source.

Create this local mirror structure:

```text
third_party/boon-upstream/
examples/upstream/              # exact imported .bn/.expected/reference assets
examples/terminal/              # terminal-adapted or terminal-only examples
examples/new/                   # repo-authored examples, e.g. pong and arkanoid if not placed under terminal
fixtures/
  corpus_manifest.json
  syntax_inventory.json
  feature_matrix.md
  spec_gaps.md
```

Discovery rules:

- Discover every current upstream playground example under `playground/frontend/src/examples`.
- Import every `.bn`, `.expected`, reference image, metadata JSON, and helper script that belongs to those examples.
- Generate `fixtures/corpus_manifest.json` from the upstream tree.
- Never manually hard-code the corpus list as final. The manifest is generated from the pinned upstream checkout.
- The manifest must record source path, imported path, category, status, parser status, runtime status, terminal status, browser status, blockers, and notes.

Known current examples observed during planning include, but are not limited to:

```text
button_hover_test
button_hover_to_click_test
cells
cells_dynamic
chained_list_remove_bug
checkbox_test
circle_drawer
complex_counter
counter
counter_hold
crud
fibonacci
filter_checkbox_bug
flight_booker
hello_world
hw_examples
interval
interval_hold
latest
layers
list_map_block
list_map_external_dep
list_object_state
list_retain_count
list_retain_reactive
list_retain_remove
minimal
pages
shopping_list
switch_hold_test
temperature_converter
text_interpolation_update
then
timer
todo_mvc
todo_mvc_physical
when
while
while_function_call
```

This list is only a seed for sanity-checking. The generated manifest is authoritative.

---

## 5. Language and feature inventory to implement

Codex must create `fixtures/syntax_inventory.json` and `fixtures/feature_matrix.md` by reading upstream docs, lexer/parser code, examples, and TODOs.

The implementation must cover at least the following.

### 5.1 Syntax and lexical items

From current parser/lexer evidence and docs:

- Delimiters: `(`, `)`, `{`, `}`, `[`, `]`.
- Comments: `-- comment`.
- Numbers: integer/decimal, negative numbers.
- Identifiers: snake_case variables/functions; PascalCase tags/tagged objects.
- Pipe: `|>`.
- Wildcard: `__`.
- Arm arrow: `=>`.
- Field/namespace dot: `.`.
- Record/tag field colon: `:`.
- Comma where current examples permit it inside compact records/styles.
- Spread: `...overrides`.
- Comparators: `==`, `=/=`, `>`, `>=`, `<`, `<=`.
- Arithmetic: `+`, `-`, `*`, `/`.
- Optional field access postfix: `?` for `UNPLUGGED` handling.
- TEXT literals: `TEXT { ... }`, plus hash-escaped forms like `TEXT #{ ... }` and `TEXT ##{ ... }`.
- Tagged objects: `Tag[field: value]`.
- Records: `[field: value]` and nested records.
- Dynamic lists: `LIST { ... }`.
- Fixed/static/HDL lists: `LIST[8] { ... }`, `LIST[__] { ... }`.
- Hardware-oriented collections: `BITS[N]`, `BYTES[N]`, `MEMORY[N]`.

### 5.2 Keywords and combinators

Implement or reserve with explicit status:

- `FUNCTION`
- `BLOCK`
- `LIST`
- `MAP`
- `LINK`
- `LATEST`
- `HOLD`
- `THEN`
- `WHEN`
- `WHILE`
- `SKIP`
- `PASS`
- `PASSED`
- `FLUSH`
- `PULSES`
- `UNPLUGGED`
- `NoElement`
- `TEXT`
- `BITS`
- `BYTES`
- `MEMORY`
- `DRAIN`

`DRAIN` is a user-reported keyword/feature and must be included in the plan even if current upstream `main` does not expose it. During Phase 1, search the pinned upstream checkout, docs, branches if available locally, TODOs, and examples for `DRAIN`, `Drain`, and `drain`. If semantics are found, implement them from evidence. If no evidence is found, reserve `DRAIN` in the lexer/parser, add a spec gap entry, and do not invent final semantics without evidence. It must appear in diagnostics as `reserved keyword DRAIN: semantics not yet discovered` rather than as an unknown identifier.

### 5.3 Function and module rules

- Functions are root-level only.
- Functions are not first-class.
- User functions use `FUNCTION snake_case(...) { ... }`.
- Builtins/modules use `Module/function(...)`, e.g. `Document/new()`, `Element/button()`, `List/map()`.
- Function arguments must be named except the piped first argument.
- Function arguments are newline-separated. Existing compact upstream examples may be minified; parser must accept them.
- No default arguments.
- PASS/PASSED are implicit environment threading and must be lowered explicitly in HIR.

### 5.4 Flow semantics

Implement these as first-class graph/runtime nodes, not as ordinary eager function calls:

- `LATEST`: latest event/value with deterministic ordering and migration identity.
- `HOLD state { ... }`: durable state actor with previous state available inside the block.
- `WHEN`: event snapshot / pattern match.
- `THEN`: trigger mapping that ignores input value.
- `WHILE`: live conditional branch / live subscription switching.
- `LINK`: non-owning reference edge/event port wiring.
- `SKIP`: no-output/filter signal.
- `BLOCK`: dependency graph, not sequential statements.
- `FLUSH`: discover exact semantics from upstream; at minimum parse and represent in IR.
- `DRAIN`: discover exact semantics or reserve with a spec gap.
- `PULSES`: counted pulses for iteration, as documented.

### 5.5 Builtin libraries needed by examples

Implement only what is required by imported and new examples, but track missing functions explicitly.

Likely modules:

- `Document`
- `Element`
- `Timer`
- `Duration`
- `Math`
- `List`
- `Text`
- `Bool`
- `Router`
- `Ulid`
- `Terminal`
- `Canvas`
- `Keyboard`
- `Scene`
- `Theme`
- `Model`
- `Lights`

For list operations, support at least:

- `List/map`
- `List/retain`
- `List/filter` as alias or separate if examples require it
- `List/append`
- `List/count`
- `List/get`
- `List/set`
- `List/range`
- `List/sum`
- `List/any`
- `List/all`
- `List/latest`
- `List/flatten`
- `List/fold`
- `List/chain`

Important `List/retain` behavior:

- In a source-of-truth chain, it can permanently remove/destroy items.
- As a derived view from an existing list variable, it filters non-destructively.
- This distinction must be represented in Flow IR and tests.

---

## 6. Architecture

### 6.1 Repository structure

Create this structure unless a phase discovers a better minimal equivalent:

```text
build.zig
build.zig.zon
src/
  main.zig
  cli.zig
  lexer.zig
  parser.zig
  ast.zig
  fmt.zig
  diag.zig
  hir.zig
  lower.zig
  flow_ir.zig
  infer.zig
  runtime/
    value.zig
    actor.zig
    scheduler.zig
    graph.zig
    ownership.zig
    persist.zig
    stdlib.zig
    host.zig
    host_headless.zig
    host_terminal.zig
    host_browser.zig
    trace.zig
  render/
    document.zig
    terminal_grid.zig
    terminal_interactive.zig
    browser_dom.zig
    canvas2d.zig
  tools/
    import_upstream.zig
    verify_corpus.zig
    verify_examples.zig
    verify_visual.zig
examples/
  upstream/
  terminal/
  new/
fixtures/
  corpus_manifest.json
  syntax_inventory.json
  feature_matrix.md
  spec_gaps.md
tests/
  lexer/
  parser/
  hir/
  flow/
  runtime/
  examples/
  terminal_snapshots/
  browser_visual/
WORKLOG.md
```

### 6.2 Compiler pipeline

```text
source .bn
  -> tokens
  -> AST with spans
  -> HIR normalized forms
  -> Flow IR graph
  -> runtime graph instance
  -> host renderer/output
```

Normalize early:

- `x |> F(a: b)` -> call with piped first argument.
- `THEN { body }` -> trigger/snapshot node ignoring input.
- `WHEN`/`WHILE` arms -> explicit pattern nodes.
- `PASS`/`PASSED` -> explicit environment capture/lookup.
- `LINK` -> explicit reference/port edges.
- `TEXT` interpolation -> structured template with dependencies.
- `LIST` dynamic/static distinction -> explicit list kind.

### 6.3 Runtime model

The runtime is a deterministic reactive graph, not a Zig-async task graph.

Core properties:

- Stable actor/node IDs derived from source span + semantic path + migration hash.
- Single-owner state hierarchy.
- Non-owning `LINK` references.
- Durable state per stateful node.
- Explicit event queue.
- Virtual time for tests.
- Deterministic event ordering.
- Trace log for every emitted value, skipped value, actor update, link resolution, and persistence write.

### 6.4 Host abstraction

Define host services behind interfaces:

- clock/timers
- input events
- persistence
- rendering sink
- logging/tracing
- random/ULID generation
- browser-specific routing/storage later

Native/headless and terminal hosts must work before browser host.

---

## 7. Terminal renderer strategy

The terminal renderer is a primary development tool, not a toy.

### 7.1 Two backends

Implement two terminal backends:

1. **Headless grid backend**
   - No real TTY.
   - Renders to deterministic `[]Cell` / string snapshots.
   - Used by CI and Codex-controlled tests.
   - Must support simulated key/mouse/input events.

2. **Interactive TUI backend**
   - Real terminal for manual play/debug.
   - Prefer `libvaxis` because it is a mature Zig TUI library with TTY, Vaxis, and event loop primitives.
   - If `libvaxis` has Zig 0.16 incompatibilities, fall back to a small internal ANSI/raw-mode backend or another clearly documented Zig TUI option.
   - Keep the renderer interface independent from the chosen TUI library.

### 7.2 Required terminal components

Support enough to run priority examples:

- text labels
- buttons
- text input
- checkbox/toggle
- row/column stripe layout
- scroll viewport
- table/grid viewport for `cells`
- canvas grid for `pong` and `arkanoid`
- event focus model
- key events
- click/mouse events if the terminal supports them, plus keyboard fallback
- virtual frame/tick events

### 7.3 Terminal adaptation rules

For upstream browser examples:

- Prefer rendering the same Boon `Document`/`Element` tree through a terminal projection.
- Do not rewrite upstream `.bn` unless the example is explicitly terminal-only.
- Where a browser-only visual is impossible in terminal, create a deterministic semantic projection and record the limitation in the manifest.
- P0 examples must have explicit `.expected` terminal specs.

For new terminal games:

- They must be written in Boon, not hard-coded in Zig.
- Zig only provides `Terminal`, `Canvas`, `Timer`, `Keyboard`, and runtime services.
- Tests must simulate frames and key events deterministically.

---

## 8. P0 example source requirements

### 8.1 `counter` exact upstream source

Import the current upstream source exactly, then let the formatter create a pretty copy if desired. The semantic fixture must remain equivalent to:

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
    element: [event: [press: LINK]]
    style: []
    label: TEXT { + }
)
```

Required tests:

- Initial text: `0+`.
- Click increment: `1+`.
- Click again: `2+`.
- Burst three clicks: `5+`.
- Restart with persisted state: still `5+`.
- Clear state and restart: `0+`.

### 8.2 `interval` exact upstream source

Import exact upstream source. Semantic fixture:

```boon
document:
    Duration[seconds: 1]
    |> Timer/interval()
    |> THEN { 1 }
    |> Math/sum()
    |> Document/new()
```

Required tests:

- Use virtual time only.
- Initial output before one second: `0` or no tick according to upstream expected file. Record exact behavior in manifest.
- Advance virtual time 1s: output increments by 1.
- Advance 5s total: output increments deterministically to expected count.
- No wall-clock sleeps in tests.

### 8.3 `cells` exact upstream source

Import `playground/frontend/src/examples/cells/cells.bn` exactly. Do not hand-rewrite it in the initial port.

The current upstream code is a 7GUIs Cells spreadsheet example with:

- 26 columns A-Z.
- 100 rows.
- Double-click edit.
- Enter commit.
- Escape cancel.
- Blur exit.
- Reactive formulas.
- Default formulas including values in A1/A2/A3, `=add(A1, A2)`, and `=sum(A1:A3)`.

Required terminal projection:

- Render column headers A-Z and row labels.
- Render at least a viewport of the 26x100 grid.
- Support keyboard navigation.
- Support edit mode.
- Support Enter commit and Escape cancel.
- Test formula recomputation headlessly and in terminal snapshots.

Required tests:

- Initial A1=5, A2=10, A3=15.
- B1 computes 15 from `=add(A1, A2)`.
- C1 computes 30 from `=sum(A1:A3)`.
- Editing A1 updates B1 and C1 reactively.
- Escape cancels edit.
- Enter commits edit.
- Overrides list persists and is migrated via stable state IDs.

### 8.4 New terminal `pong` example

Create `examples/terminal/pong/pong.bn` and `examples/terminal/pong/pong.expected`.

Codex may adjust this code only to fix parser/runtime compatibility, but the final committed example must remain Boon code with equivalent semantics. Do not replace it with Zig game logic.

```boon
-- Terminal Pong. Host APIs required: Terminal/key_down, Timer/interval, Terminal/canvas, Canvas/rect, Canvas/text.
-- Controls: W/S for left paddle, ArrowUp/ArrowDown for right paddle, Space resets after game over.

screen_width: 80
screen_height: 24
frame:
    Duration[milliseconds: 50]
    |> Timer/interval()

key:
    LATEST {
        NoKey
        Terminal/key_down()
        frame |> THEN { NoKey }
    }

game:
    initial_game(width: screen_width, height: screen_height)
    |> HOLD state {
        frame |> THEN {
            next_game(state: state, key: key)
        }
    }

document:
    game
    |> render_game()

FUNCTION initial_game(width, height) {
    [
        width: width
        height: height
        left_score: 0
        right_score: 0
        left_paddle: [x: 2 y: 10 height: 5]
        right_paddle: [x: width - 3 y: 10 height: 5]
        ball: [x: width / 2 y: height / 2 vx: 1 vy: 1]
        status: Running
    ]
}

FUNCTION reset_ball(width, height, vx) {
    [x: width / 2 y: height / 2 vx: vx vy: 1]
}

FUNCTION clamp(value, min, max) {
    value < min |> WHEN {
        True => min
        __ => value > max |> WHEN {
            True => max
            __ => value
        }
    }
}

FUNCTION left_delta(key) {
    key |> WHEN {
        W => -1
        S => 1
        __ => 0
    }
}

FUNCTION right_delta(key) {
    key |> WHEN {
        ArrowUp => -1
        ArrowDown => 1
        __ => 0
    }
}

FUNCTION move_paddle(paddle, delta, board_height) {
    [
        x: paddle.x
        y: clamp(value: paddle.y + delta, min: 1, max: board_height - paddle.height - 1)
        height: paddle.height
    ]
}

FUNCTION paddle_contains_y(paddle, y) {
    y >= paddle.y |> WHEN {
        True => y <= paddle.y + paddle.height
        __ => False
    }
}

FUNCTION hit_left_paddle(ball, paddle) {
    ball.x <= paddle.x + 1 |> WHEN {
        True => paddle_contains_y(paddle: paddle, y: ball.y)
        __ => False
    }
}

FUNCTION hit_right_paddle(ball, paddle) {
    ball.x >= paddle.x - 1 |> WHEN {
        True => paddle_contains_y(paddle: paddle, y: ball.y)
        __ => False
    }
}

FUNCTION next_ball_after_wall(ball, height) {
    BLOCK {
        next_vy:
            ball.y <= 1 |> WHEN {
                True => 1
                __ => ball.y >= height - 2 |> WHEN {
                    True => -1
                    __ => ball.vy
                }
            }
        [x: ball.x y: ball.y vx: ball.vx vy: next_vy]
    }
}

FUNCTION next_game(state, key) {
    state.status |> WHILE {
        Running => BLOCK {
            left_paddle:
                move_paddle(
                    paddle: state.left_paddle
                    delta: left_delta(key: key)
                    board_height: state.height
                )
            right_paddle:
                move_paddle(
                    paddle: state.right_paddle
                    delta: right_delta(key: key)
                    board_height: state.height
                )
            wall_ball:
                next_ball_after_wall(ball: state.ball, height: state.height)
            hit_left:
                hit_left_paddle(ball: wall_ball, paddle: left_paddle)
            hit_right:
                hit_right_paddle(ball: wall_ball, paddle: right_paddle)
            vx:
                hit_left |> WHEN {
                    True => 1
                    __ => hit_right |> WHEN {
                        True => -1
                        __ => wall_ball.vx
                    }
                }
            moved_ball:
                [x: wall_ball.x + vx y: wall_ball.y + wall_ball.vy vx: vx vy: wall_ball.vy]
            right_scored:
                moved_ball.x < 0
            left_scored:
                moved_ball.x > state.width - 1
            left_score:
                left_scored |> WHEN {
                    True => state.left_score + 1
                    __ => state.left_score
                }
            right_score:
                right_scored |> WHEN {
                    True => state.right_score + 1
                    __ => state.right_score
                }
            ball:
                left_scored |> WHEN {
                    True => reset_ball(width: state.width, height: state.height, vx: -1)
                    __ => right_scored |> WHEN {
                        True => reset_ball(width: state.width, height: state.height, vx: 1)
                        __ => moved_ball
                    }
                }
            status:
                left_score >= 9 |> WHEN {
                    True => LeftWon
                    __ => right_score >= 9 |> WHEN {
                        True => RightWon
                        __ => Running
                    }
                }
            [
                width: state.width
                height: state.height
                left_score: left_score
                right_score: right_score
                left_paddle: left_paddle
                right_paddle: right_paddle
                ball: ball
                status: status
            ]
        }
        __ => key |> WHEN {
            Space => initial_game(width: state.width, height: state.height)
            __ => state
        }
    }
}

FUNCTION draw_paddle(paddle) {
    Canvas/rect(
        x: paddle.x
        y: paddle.y
        width: 1
        height: paddle.height
        glyph: TEXT { █ }
    )
}

FUNCTION render_game(game) {
    BLOCK {
        status_text:
            game.status |> WHILE {
                Running => TEXT { W/S and ↑/↓ move paddles }
                LeftWon => TEXT { Left wins - press Space }
                RightWon => TEXT { Right wins - press Space }
            }
        Terminal/canvas(
            width: game.width
            height: game.height
            items: LIST {
                Canvas/text(x: 34 y: 0 text: TEXT { {game.left_score} : {game.right_score} })
                Canvas/text(x: 25 y: game.height - 1 text: status_text)
                draw_paddle(paddle: game.left_paddle)
                draw_paddle(paddle: game.right_paddle)
                Canvas/rect(x: game.ball.x y: game.ball.y width: 1 height: 1 glyph: TEXT { ● })
            }
        )
    }
}
```

Required tests:

- Initial snapshot has two paddles, one ball, `0 : 0`.
- W/S moves left paddle within bounds.
- ArrowUp/ArrowDown moves right paddle within bounds.
- Ball bounces off top/bottom walls.
- Ball bounces off paddles.
- Missing paddle gives opposite player a point and resets ball.
- First score to 9 changes status to `LeftWon` or `RightWon`.
- Space resets after game over.

### 8.5 New terminal `arkanoid` example

Create `examples/terminal/arkanoid/arkanoid.bn` and `examples/terminal/arkanoid/arkanoid.expected`.

Codex may adjust this code only to fix parser/runtime compatibility, but the final committed example must remain Boon code with equivalent semantics.

```boon
-- Terminal Arkanoid. Host APIs required: Terminal/key_down, Timer/interval, Terminal/canvas, Canvas/rect, Canvas/text.
-- Controls: ArrowLeft/ArrowRight or A/D move the paddle. Space restarts after win/loss.

screen_width: 80
screen_height: 28
frame:
    Duration[milliseconds: 50]
    |> Timer/interval()

key:
    LATEST {
        NoKey
        Terminal/key_down()
        frame |> THEN { NoKey }
    }

game:
    initial_game(width: screen_width, height: screen_height)
    |> HOLD state {
        frame |> THEN {
            next_game(state: state, key: key)
        }
    }

document:
    game
    |> render_game()

FUNCTION initial_game(width, height) {
    [
        width: width
        height: height
        paddle: [x: width / 2 - 5 y: height - 3 width: 10]
        ball: [x: width / 2 y: height - 5 vx: 1 vy: -1]
        bricks: initial_bricks()
        score: 0
        status: Running
    ]
}

FUNCTION initial_bricks() {
    List/range(from: 0, to: 4)
    |> List/map(row, new:
        List/range(from: 0, to: 9)
        |> List/map(column, new:
            make_brick(row: row, column: column)
        )
    )
    |> List/flatten()
}

FUNCTION make_brick(row, column) {
    [
        x: 6 + column * 7
        y: 3 + row * 2
        width: 5
        height: 1
        row: row
        column: column
    ]
}

FUNCTION clamp(value, min, max) {
    value < min |> WHEN {
        True => min
        __ => value > max |> WHEN {
            True => max
            __ => value
        }
    }
}

FUNCTION move_delta(key) {
    key |> WHEN {
        ArrowLeft => -3
        A => -3
        ArrowRight => 3
        D => 3
        __ => 0
    }
}

FUNCTION move_paddle(paddle, key, board_width) {
    [
        x: clamp(value: paddle.x + move_delta(key: key), min: 1, max: board_width - paddle.width - 1)
        y: paddle.y
        width: paddle.width
    ]
}

FUNCTION inside_rect(x, y, rect) {
    x >= rect.x |> WHEN {
        True => x <= rect.x + rect.width |> WHEN {
            True => y >= rect.y |> WHEN {
                True => y <= rect.y + rect.height
                __ => False
            }
            __ => False
        }
        __ => False
    }
}

FUNCTION hit_paddle(ball, paddle) {
    inside_rect(
        x: ball.x
        y: ball.y
        rect: [x: paddle.x y: paddle.y width: paddle.width height: 1]
    )
}

FUNCTION hit_brick(ball, brick) {
    inside_rect(x: ball.x, y: ball.y, rect: brick)
}

FUNCTION bounce_from_walls(ball, width) {
    BLOCK {
        vx:
            ball.x <= 1 |> WHEN {
                True => 1
                __ => ball.x >= width - 2 |> WHEN {
                    True => -1
                    __ => ball.vx
                }
            }
        vy:
            ball.y <= 1 |> WHEN {
                True => 1
                __ => ball.vy
            }
        [x: ball.x y: ball.y vx: vx vy: vy]
    }
}

FUNCTION next_game(state, key) {
    state.status |> WHILE {
        Running => BLOCK {
            paddle:
                move_paddle(paddle: state.paddle, key: key, board_width: state.width)
            wall_ball:
                bounce_from_walls(ball: state.ball, width: state.width)
            moved_ball:
                [
                    x: wall_ball.x + wall_ball.vx
                    y: wall_ball.y + wall_ball.vy
                    vx: wall_ball.vx
                    vy: wall_ball.vy
                ]
            brick_hit:
                state.bricks
                |> List/any(brick, if: hit_brick(ball: moved_ball, brick: brick))
            paddle_hit:
                hit_paddle(ball: moved_ball, paddle: paddle)
            vy:
                brick_hit |> WHEN {
                    True => moved_ball.vy * -1
                    __ => paddle_hit |> WHEN {
                        True => -1
                        __ => moved_ball.vy
                    }
                }
            ball:
                [x: moved_ball.x y: moved_ball.y vx: moved_ball.vx vy: vy]
            bricks:
                state.bricks
                |> List/retain(brick, if:
                    hit_brick(ball: moved_ball, brick: brick) |> WHEN {
                        True => False
                        __ => True
                    }
                )
            score:
                brick_hit |> WHEN {
                    True => state.score + 1
                    __ => state.score
                }
            remaining:
                bricks |> List/count()
            status:
                ball.y > state.height - 1 |> WHEN {
                    True => Lost
                    __ => remaining == 0 |> WHEN {
                        True => Won
                        __ => Running
                    }
                }
            [
                width: state.width
                height: state.height
                paddle: paddle
                ball: ball
                bricks: bricks
                score: score
                status: status
            ]
        }
        __ => key |> WHEN {
            Space => initial_game(width: state.width, height: state.height)
            __ => state
        }
    }
}

FUNCTION draw_brick(brick) {
    Canvas/rect(
        x: brick.x
        y: brick.y
        width: brick.width
        height: brick.height
        glyph: TEXT { ▉ }
    )
}

FUNCTION render_game(game) {
    BLOCK {
        brick_items:
            game.bricks
            |> List/map(brick, new: draw_brick(brick: brick))
        items:
            brick_items
            |> List/append(item: Canvas/text(x: 2 y: 0 text: TEXT { Score {game.score} }))
            |> List/append(item: Canvas/rect(x: game.paddle.x y: game.paddle.y width: game.paddle.width height: 1 glyph: TEXT { ▔ }))
            |> List/append(item: Canvas/rect(x: game.ball.x y: game.ball.y width: 1 height: 1 glyph: TEXT { ● }))
            |> List/append(item:
                game.status |> WHILE {
                    Running => Canvas/text(x: 22 y: game.height - 1 text: TEXT { A/D or ←/→ move paddle })
                    Won => Canvas/text(x: 28 y: game.height - 1 text: TEXT { You won - press Space })
                    Lost => Canvas/text(x: 27 y: game.height - 1 text: TEXT { Game over - press Space })
                }
            )
        Terminal/canvas(width: game.width, height: game.height, items: items)
    }
}
```

Required tests:

- Initial snapshot has rows of bricks, paddle, ball, and `Score 0`.
- Left/right keys move paddle within bounds.
- Ball bounces off side/top walls.
- Ball bounces off paddle.
- Ball hitting a brick removes exactly that brick and increments score.
- Removing all bricks sets status `Won`.
- Ball passing bottom sets status `Lost`.
- Space restarts after win/loss.

### 8.6 `todo_mvc` browser visual hard gate

Import current upstream `todo_mvc` exactly, including:

- `todo_mvc.bn`
- `todo_mvc.expected`
- `reference_700x700_(1400x1400).png`
- `reference_metadata.json`
- `verify_visual.sh`

Required native/headless tests before browser:

- Initial app structure parses and lowers.
- Add todo.
- Toggle todo.
- Edit todo.
- Delete todo.
- Filter All/Active/Completed.
- Clear completed.
- Persistence survives restart.
- State clearing resets.

Required terminal semantic projection before browser:

- Render title, input, todo rows, checkboxes/toggles, filters, counts, clear-completed.
- Keyboard-only interaction must cover all semantics.
- Snapshot tests must be deterministic.

Required browser final tests:

- Render through browser host using IndexedDB/OPFS state backend.
- Visual screenshot compared to upstream reference asset.
- Use metadata-driven tolerances.
- Do not accept obvious visual drift: wrong layout, wrong typography scale, missing shadows/borders, wrong filter state, wrong checkbox visuals, missing TodoMVC official look.
- Browser test may be skipped only when running in an environment with no browser, and then CI/local instructions must document how to run it.

### 8.7 `todo_mvc_physical` and physical renderer TODOs

Import current upstream `todo_mvc_physical` tree exactly.

Create `docs/PHYSICAL_TODO.md` and track these required items:

- `Model/cut(from, remove)` internal boolean subtraction.
- SDF-based rendering path.
- Automatic cavity generation from `depth`, `padding`, and element type.
- Physical lighting and shadows.
- Theme-controlled geometry/material/elevation/depth/corners/interactions/colors.
- `Scene/new` integration.
- Ensure `Model/cut()` remains internal unless future evidence says user-facing API is needed.
- Parse and lower physical examples even before full 3D rendering is implemented.

Acceptance for initial implementation:

- Physical example imports into manifest.
- It parses or has exact parser blockers recorded.
- Physical docs are copied/imported or summarized in `docs/PHYSICAL_TODO.md`.
- Missing renderer pieces are explicit TODOs with tests pending, not silent skips.

---

## 9. Phase plan

### Phase 0 — Bootstrap repository

Tasks:

- Initialize Zig project.
- Add `PLAN.md` if not already present.
- Create `WORKLOG.md`.
- Create empty directory skeleton.
- Add a tiny CLI that prints version/help.
- Add initial build/test commands.

Verification:

```bash
zig version
zig build
zig build test
zig build run -- --help
```

Acceptance:

- Commands pass.
- `WORKLOG.md` records Phase 0 complete.

---

### Phase 1 — Upstream import and corpus manifest

Tasks:

- Add a script/tool to fetch or copy a pinned upstream Boon checkout.
- Discover every `playground/frontend/src/examples` child.
- Import all `.bn`, `.expected`, reference images, metadata files, helper scripts, and docs needed by examples.
- Generate `fixtures/corpus_manifest.json`.
- Generate `fixtures/syntax_inventory.json` and `fixtures/feature_matrix.md`.
- Search for `DRAIN`, `Drain`, `drain`, `FLUSH`, `PULSES`, `TODO`, `Model/cut`, `operator`, and physical renderer TODOs.
- Create `fixtures/spec_gaps.md` for undocumented or conflicting features.

Verification:

```bash
zig build verify-corpus
```

Acceptance:

- Manifest contains every current upstream example.
- P0 examples are marked as hard gates.
- No imported example is missing `.bn` unless it is a directory with documented generated/build files.
- `DRAIN` discovery result is recorded.
- `todo_mvc` reference assets are imported.
- `todo_mvc_physical` TODOs are recorded.

---

### Phase 2 — Lexer, parser, AST, formatter

Tasks:

- Implement lexer with spans.
- Implement parser for all syntax used by P0 examples and current corpus.
- Implement AST data structures.
- Implement minimal formatter.
- Add golden parser tests from imported examples.
- Accept compact/minified upstream syntax and pretty multiline syntax.

Verification:

```bash
zig build test
zig build parse -- examples/upstream/counter/counter.bn
zig build parse -- examples/upstream/interval/interval.bn
zig build parse -- examples/upstream/cells/cells.bn
zig build parse -- examples/terminal/pong/pong.bn
zig build parse -- examples/terminal/arkanoid/arkanoid.bn
zig build verify-corpus --parse-only
```

Acceptance:

- P0 examples parse.
- Every upstream example is either parsed or has an exact parser blocker in manifest.
- Formatter is idempotent on parser-supported examples.
- `DRAIN` is reserved or implemented according to Phase 1 evidence.

---

### Phase 3 — HIR lowering and diagnostics

Tasks:

- Lower AST to HIR.
- Normalize pipes, named args, `PASS`/`PASSED`, `TEXT` interpolation, `BLOCK`, `WHEN`, `WHILE`, `THEN`, `HOLD`, `LATEST`, `LINK`, list kinds, tagged objects, optional field access.
- Add source-span diagnostics.
- Add golden HIR tests for P0 examples.

Verification:

```bash
zig build test
zig build hir -- examples/upstream/counter/counter.bn
zig build hir -- examples/upstream/interval/interval.bn
zig build hir -- examples/upstream/cells/cells.bn
zig build hir -- examples/terminal/pong/pong.bn
zig build hir -- examples/terminal/arkanoid/arkanoid.bn
```

Acceptance:

- P0 examples lower to HIR.
- Errors are readable and include spans.
- Unsupported features become explicit manifest blockers, not crashes.

---

### Phase 4 — Flow IR and deterministic runtime core

Tasks:

- Implement Flow IR nodes.
- Implement runtime value model.
- Implement actor/state graph.
- Implement event queue.
- Implement virtual time.
- Implement `LATEST`, `HOLD`, `WHEN`, `THEN`, `WHILE`, `BLOCK`, `LINK`, `SKIP`.
- Implement ownership hierarchy and non-owning links.
- Implement trace logging.

Verification:

```bash
zig build test
zig build flow -- examples/upstream/counter/counter.bn
zig build run-headless -- examples/upstream/counter/counter.bn --trace
```

Acceptance:

- Counter runs headlessly.
- Virtual events can trigger button press.
- Trace shows deterministic graph updates.

---

### Phase 5 — Minimal standard library

Tasks:

Implement the stdlib needed by P0 examples:

- `Document/new`
- `Element/stripe`
- `Element/button`
- `Element/label`
- `Element/text_input`
- `Timer/interval`
- `Duration[...]`
- `Math/sum`
- `List/*` functions used by P0 examples
- `Text/*` functions used by cells/todo
- `Terminal/key_down`
- `Terminal/canvas`
- `Canvas/rect`
- `Canvas/text`

Verification:

```bash
zig build test
zig build run-headless -- examples/upstream/counter/counter.bn --expect examples/upstream/counter/counter.expected
zig build run-headless -- examples/upstream/interval/interval.bn --virtual-time 5s
```

Acceptance:

- Counter and interval pass headless tests.
- No real sleeps.

---

### Phase 6 — Persistence and migration

Tasks:

- Implement native file-backed persistence.
- Stable IDs for stateful nodes.
- State clear command.
- State migration for unchanged `LATEST`/`HOLD` nodes.
- Manifest records persistence status per example.

Verification:

```bash
zig build test
zig build run-headless -- examples/upstream/counter/counter.bn --state-dir .zig-cache/test-state --script tests/examples/counter_sequence.json
zig build run-headless -- examples/upstream/counter/counter.bn --state-dir .zig-cache/test-state --expect-text '5+'
zig build run-headless -- examples/upstream/counter/counter.bn --state-dir .zig-cache/test-state --clear-state --expect-text '0+'
```

Acceptance:

- Counter persistence tests pass.
- State clear works.
- Trace shows persisted state reads/writes.

---

### Phase 7 — Headless P0 examples

Tasks:

- Make P0 examples pass without terminal/browser:
  - counter
  - interval
  - cells semantic tests
  - pong deterministic game tests
  - arkanoid deterministic game tests
  - todo_mvc semantic tests
- Add expected test scripts for each.
- Update manifest.

Verification:

```bash
zig build verify-examples --headless --filter p0
```

Acceptance:

- P0 headless tests pass or have exact blockers.
- No P0 example is silently skipped.

---

### Phase 8 — Terminal headless grid renderer

Tasks:

- Implement document-to-grid renderer.
- Implement canvas-to-grid renderer.
- Implement terminal event simulation.
- Add snapshot tests.
- Add terminal `.expected` files for P0 examples.

Verification:

```bash
zig build verify-examples --terminal-grid --filter p0
zig build snapshot -- examples/terminal/pong/pong.bn --frames 10
zig build snapshot -- examples/terminal/arkanoid/arkanoid.bn --frames 10
```

Acceptance:

- P0 terminal snapshots pass.
- Pong and Arkanoid render from Boon code.
- Cells renders a grid viewport.
- Counter/interval render meaningfully in terminal.

---

### Phase 9 — Interactive terminal renderer

Tasks:

- Add interactive terminal backend using `libvaxis` if compatible.
- If not compatible, implement minimal ANSI/raw-mode backend and document why.
- Wire keyboard and optional mouse events.
- Add commands:

```bash
zig build run-terminal -- examples/upstream/counter/counter.bn
zig build run-terminal -- examples/upstream/cells/cells.bn
zig build run-terminal -- examples/terminal/pong/pong.bn
zig build run-terminal -- examples/terminal/arkanoid/arkanoid.bn
```

Verification:

```bash
zig build test
zig build verify-examples --terminal-grid --filter p0
```

Manual smoke:

- Play Pong for at least one point.
- Play Arkanoid until at least one brick is removed.
- Edit a Cells cell and see formulas update.

Acceptance:

- Interactive renderer works or documented fallback works.
- Tests still use headless grid and do not require a live TTY.

---

### Phase 10 — Exhaustive upstream corpus in headless/terminal

Tasks:

- Work through every manifest example.
- Implement missing stdlib/runtime pieces.
- Add terminal projections or explicit blockers.
- Do not start browser work until this phase is acceptably green.

Verification:

```bash
zig build verify-corpus
zig build verify-examples --headless --all
zig build verify-examples --terminal-grid --all
```

Acceptance:

- Every current upstream example is DONE/PARTIAL/BLOCKED with evidence.
- P0 examples are DONE in headless and terminal-grid.
- Browser-only limitations are recorded, not hidden.

---

### Phase 11 — Browser host foundation

Tasks:

- Add browser/wasm build target if feasible.
- Implement browser host services.
- Implement IndexedDB or OPFS/structured async storage.
- Add LocalStorage importer only if useful for old playground compatibility.
- Implement DOM renderer enough for counter/interval/todo.

Verification:

```bash
zig build browser
zig build verify-examples --browser-smoke --filter counter
zig build verify-examples --browser-smoke --filter interval
```

Acceptance:

- Browser host runs simple examples.
- State persistence uses IndexedDB/OPFS, not LocalStorage as primary.

---

### Phase 12 — Browser TodoMVC visual parity

Tasks:

- Render upstream `todo_mvc` in browser.
- Use imported reference image and metadata.
- Implement necessary CSS/layout/style/element features.
- Add screenshot tool and visual comparison.
- Keep browser tests isolated and optional in non-browser environments.

Verification:

```bash
zig build verify-examples --browser-smoke --filter todo_mvc
zig build verify-visual --filter todo_mvc
```

Acceptance:

- TodoMVC semantics pass.
- TodoMVC visual comparison passes within documented tolerance.
- Any remaining visual deviations are recorded with screenshot diffs.

---

### Phase 13 — Browser corpus smoke

Tasks:

- Run browser smoke tests across corpus.
- Add feature-specific browser tests where headless/terminal cannot cover behavior.
- Keep visual tests focused on examples with reference assets.

Verification:

```bash
zig build verify-examples --browser-smoke --all
zig build verify-visual --all-with-reference-assets
```

Acceptance:

- Browser status recorded for every example.
- TodoMVC visual remains green.

---

### Phase 14 — Physical renderer research/implementation lane

Tasks:

- Parse/lower `todo_mvc_physical`.
- Implement enough semantic/theme APIs for non-3D tests.
- Design internal SDF/geometry pipeline.
- Implement or stub with explicit failures:
  - `Model/cut(from, remove)`
  - boolean subtraction
  - automatic cavity generation
  - physical lighting
  - material/elevation/depth/corner/theme propagation

Verification:

```bash
zig build parse -- examples/upstream/todo_mvc_physical/RUN.bn
zig build verify-examples --headless --filter todo_mvc_physical
```

Acceptance:

- Physical example is not ignored.
- Missing renderer work is explicit and documented.

---

### Phase 15 — Optional `Io.Evented` experiment

Only start after P0 native/headless/terminal work is stable.

Tasks:

- Add build flag or command for Evented smoke tests.
- Run timer/cancelation tests.
- Do not include networking tests because Zig 0.16 Evented networking is not implemented.
- Compare behavior with `Io.Threaded`.

Verification:

```bash
zig build test -Dio_backend=evented
zig build verify-examples --headless --filter interval -Dio_backend=evented
```

Acceptance:

- Experimental status documented.
- Failures do not block mainline unless they reveal backend-agnostic bugs.

---

### Phase 16 — Final hardening

Tasks:

- Fuzz/parser robustness if feasible.
- Improve diagnostics.
- Reduce flaky tests.
- Document commands.
- Ensure all generated files are reproducible.
- Ensure no TODO is hidden inside code without corresponding manifest/spec-gap entry.

Verification:

```bash
zig build test
zig build verify-corpus
zig build verify-examples --headless --all
zig build verify-examples --terminal-grid --all
zig build verify-examples --browser-smoke --all
zig build verify-visual --all-with-reference-assets
```

Acceptance:

- Final definition of done below is satisfied or exact blockers are documented.

---

## 10. Definition of done

The implementation is complete when:

- `zig build test` passes.
- `zig build verify-corpus` passes.
- Every current upstream playground example is in `fixtures/corpus_manifest.json`.
- P0 examples are DONE in headless tests.
- P0 examples are DONE in terminal-grid tests.
- `counter` persistence tests pass.
- `interval` virtual-time tests pass.
- `cells` formula/edit tests pass.
- `pong` and `arkanoid` are Boon source examples and pass deterministic terminal tests.
- `todo_mvc` browser visual test passes against imported reference assets, unless no browser is available and the exact local/CI command is documented.
- Browser persistence uses IndexedDB/OPFS/async structured storage as primary.
- LocalStorage is not the main persistence backend.
- `todo_mvc_physical` is imported and tracked with explicit physical renderer TODOs.
- `DRAIN` is either implemented from evidence or reserved with a spec gap.
- `LIST { ... }` dynamic vs `LIST[N] { ... }` fixed/static semantics are tested.
- `Io.Threaded` is the supported native baseline.
- `Io.Evented` is documented as optional/experimental if added.
- `WORKLOG.md` contains a clean final audit.

---

## 11. Anti-patterns to avoid

- Do not hard-code example outputs in Zig instead of executing Boon.
- Do not rewrite upstream examples just to make parsing easier.
- Do not make terminal games Zig games; they must be Boon programs.
- Do not make browser tests the main development loop.
- Do not use wall-clock sleeps in tests.
- Do not silently skip examples.
- Do not treat `LIST[8]` as the main list syntax for software examples.
- Do not use LocalStorage as the primary browser persistence store.
- Do not make Boon semantics depend on Zig async scheduling.
- Do not invent `DRAIN` semantics if no upstream/user evidence is found.
- Do not expose physical renderer internals like `Model/cut()` as user-facing API unless evidence says to.

---

## 12. Suggested GitHub repo bootstrap commands

From outside the repo:

```bash
gh repo create boon-zig --public --clone
cd boon-zig
cp /path/to/PLAN.md PLAN.md
git add PLAN.md
git commit -m "Add Boon Zig implementation plan"
git push
codex
```

Inside interactive Codex:

1. Select `gpt-5.4`.
2. Select high reasoning effort.
3. Paste the start/resume prompt from section 1.

