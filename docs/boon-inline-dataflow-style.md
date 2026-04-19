# Boon Inline Dataflow Style

This repo prefers an inline, store-first Boon style for small and medium interactive examples.

## Core Layout

Start the file with one `store` record and keep it ordered like this:

```bn
store: [
    --- constants ---
    ...

    --- links ---
    ...

    --- states ---
    ...

    --- derived ---
    ...
]
```

Use `store` for:
- constants that belong to the app model
- control links
- persistent scalar state
- derived facts that describe the current state

Do not store actual UI element nodes in `store`. The document tree should own elements.

## Reading Order

Prefer reading from root to leaves:

1. `store`
2. `document`
3. subtree functions in parent-to-child order

That means `document` should appear before `hud()`, `board_view()`, `court_row()`, and similar render helpers.

## Inline Dataflow

Prefer named derived fields and local `BLOCK` values over many tiny helper functions.

Good uses for `BLOCK`:
- naming a dense condition once
- naming temporary render pieces like `left`, `right`, or `separator`
- making a repeated subtree easier to scan

Good uses for standalone functions:
- real UI subtrees
- repeated render transformations
- logic that is reused and still clearer as a named unit

Avoid extracting helpers that only hide obvious one-step dataflow.

If a standalone function returns only `True` or `False`, prefer an `is_`-style predicate name such as `is_idle(...)`.
For store-owned derived booleans, prefer direct fact names that read well at call sites, such as `is_idle`, `point_scored_now`, or `hits_player_paddle`.

## Elements and Links

Declare the element's event shape at the element site:

```bn
Element/button(
    element: [event: [press: LINK]]
    style: []
    label: TEXT { Up }
) |> LINK { store.elements.up_button }
```

This keeps document ownership in the document tree while making the event stream available through `store.elements.*`.

Do not replace `press: LINK` with a concrete stream expression inside the element definition.

## Text Interpolation

Inside `TEXT { ... }`, interpolate only:
- names like `{count}`
- field access like `{store.status}`

If the value is an expression, compute it first with `BLOCK`, then interpolate the name.

## Pong as the Example

`examples/terminal/pong/pong.bn` is the reference example for this style in the current repo:
- one top-level `store`
- top-down render order
- inline derived facts
- local `BLOCK` names for dense logic
- document-owned button elements
