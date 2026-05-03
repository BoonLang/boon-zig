# Raybox-Zig 16ms Runtime Optimization Plan

This plan is the active priority under `RAYBOX_ZIG_IMPLEMENTATION_PLAN.md`.
Keep the current fixed stack from the implementation plan and continue
implementing the main plan, but do not consider the playground usable until the
runtime interaction gates here pass. The window/input/rendering layer is SDL3;
the runtime gates below remain unchanged.

Migration note: Raybox now runs inside `boon-zig` under `raybox/`. Historical
`raybox-zig` command names map to integrated `boon-zig` names:
`bench-playground-native` -> `bench-raybox-native`,
`verify-playground-native-events` -> `verify-raybox-native-events`,
`verify-examples-native` -> `verify-raybox-examples-native`,
`verify-physical-native` -> `verify-raybox-physical-native`, and
`run-playground` -> `run-raybox`.

## Goal

TodoMVC-scale interaction must feel immediate in the native playground and in
the shared runtime path used by the browser build. The target workload is 100
visible todos with duplicate titles.

Hard gates after warmup:

- A single todo checkbox toggle must complete end-to-end in `<=16ms`.
- The toggle-all checkbox/button behavior must complete end-to-end in `<=16ms`.
- End-to-end means Boon event dispatch, state update, snapshot creation,
  semantic extraction, Raybox trace projection, and CPU geometry generation.
- Runtime dispatch plus snapshot should be single-digit milliseconds.

Correctness gates:

- Todos with the same title must not share checked state.
- Toggling one todo must change exactly that todo.
- Toggle-all must check or uncheck every visible todo correctly.
- Repeatedly focusing the new-todo input must not replay Enter or duplicate old
  todo text.
- Checkbox hit testing must target the clicked row, including dense rows.
- Focused text inputs must show a blinking caret, and the blink phase must reset
  on focus and typing.

## Non-Negotiable Constraints

- Develop Raybox in this `boon-zig` checkout. Plain `zig build ...` commands
  must use the local Boon runtime host automatically.
- Do not commit or push unless the user explicitly requests it.
- Do not reintroduce a separate `raybox-zig` `boon_zig` dependency pin for
  normal integrated work.
- Do not add TodoMVC, todo-label, example-name, or business-specific shortcuts
  to production runtime code.
- Remove existing runtime shortcuts that special-case TodoMVC behavior, such as
  predicates named for TodoMVC render wrappers.
- Do not rewrite TodoMVC as Zig widgets.
- Keep upstream TodoMVC Boon structure unless profiling proves a specific Boon
  idiom is accidentally pathological. If a Boon-source change is made, document
  the evidence and preserve user-visible semantics.

## Implementation Phases

1. Add a benchmark harness.
   - Add `zig build bench-raybox-native`.
   - It must use the local `boon-zig` runtime host automatically.
   - It must run in optimized mode with `-Doptimize=ReleaseFast` when possible.
   - It must emit JSON under `zig-out/reports/` with timings for add-100,
     single toggle, toggle-all, dispatch, snapshot, semantic extraction,
     projection, geometry, and total end-to-end.
   - If native ReleaseFast linking is blocked by platform renderer warnings,
     first make a renderer-free benchmark that still covers runtime, snapshot,
     projection, and CPU geometry. Track native ReleaseFast linking as a
     separate blocker.

2. Make control identity stable.
   - Extend the `boon-zig` host/control API so interactive controls expose a
     stable control ref containing kind, link, scope identity, and current
     ordinal.
   - Carry control refs through the raybox semantic tree and render commands.
   - Dispatch checkbox, button, text input, focus, blur, hover, and key events by
     control ref instead of visible label or fragile ordinal lookup.

3. Fix duplicate list item identity generically.
   - Audit scope derivation for records/lists with equal values.
   - Ensure `List/map`, `List/retain`, append, remove, and reorder preserve
     stable item instance identity.
   - Equal todo titles must still produce distinct scoped holds and distinct
     control refs.

4. Replace full scoped fanout with a dependency index.
   - Build a generic index from event source link to matching subscriber nodes
     and initialized scoped holds.
   - On an event, evaluate only subscribers whose dependency source and scope can
     match that event.
   - Keep derived control caches versioned by scoped state dependencies so local
     state updates do not rebuild unrelated controls.
   - Reset only stale memoized values and derived caches.

5. Optimize raybox projection and hit testing.
   - Avoid O(n) label-based control lookup during dispatch.
   - Ensure checkbox hit rectangles do not overlap adjacent rows.
   - Make hit testing return the control ref stored on the render command.
   - Keep semantic extraction and CPU geometry allocation bounded and measured.

6. Add blinking caret rendering.
   - Implement blinking in the app/render clock path, not as a Boon state event.
   - Reset blink phase on focus and text input changes.
   - Keep benchmark measurements deterministic by disabling or fixing the blink
     phase in benchmark mode.

7. Audit TodoMVC Boon source.
   - Check counts, filters, inline icons, duplicate-title paths, and toggle-all
     dependencies.
   - Do not change source for speed unless measured data proves the source is
     accidentally slow independent of runtime implementation quality.

## Verification

Required commands during the loop:

```sh
rm -f zig-out/boon-runtime-state/*.json
zig build bench-raybox-native -Doptimize=ReleaseFast

rm -f zig-out/boon-runtime-state/*.json
zig build verify-raybox-native-events

zig build test-raybox
zig build verify-raybox-examples-native
zig build verify-raybox-physical-native
```

Completion requires:

- Benchmark JSON proves 100-todo single toggle `<=16ms`.
- Benchmark JSON proves 100-todo toggle-all `<=16ms`.
- Correctness verifier covers duplicate titles and per-row checked state.
- Runtime production code contains no TodoMVC-specific performance shortcuts.
- The repo remains compatible with the fixed v0 stack and the main
  implementation plan.
