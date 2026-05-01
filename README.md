# recollect

`tiye/recollect` is a structural JSON diff/patch library for MoonBit.

It computes a minimal sequence of `PatchOp` operations between two `Json` trees
and applies them to reconstruct the target — suitable for efficient network
transport in realtime sync architectures.

## Immutable data design

`recollect` is designed for **immutable-data** workflows, as used in
[Cumulo](https://github.com/Cumulo/moonbit-cumulo) and
[Respo](https://github.com/Respo/respo.mbt).

- `diff_json` / `diff_value` — **read-only**; inputs are never modified.
- `apply_patch` / `apply_patches` / `apply_to_value` — return a **new** `Json`
  tree (or typed value); unchanged subtrees are shared structurally with the
  original. The input is never mutated.

This means it is safe to hold references to both the old and new state at the
same time, which is required for Respo's render-loop equality check and for
Cumulo's server-side twig/diff logic.

```moonbit nocheck
// old_remote and new_remote are independent values — old is never touched
let new_remote = @recollect.apply_to_value(old_remote, patches)
  catch { _ => old_remote }
```

> ⚠️ Do **not** wrap your state struct in a `mut` field and mutate it in place.
> Doing so breaks structural equality (`==`) and makes the render loop skip
> updates. Always replace the whole value with the newly returned one.

## API

- `diff_json(old, new)` — compute `Array[PatchOp]` between two `Json` trees
- `diff_value(old, new)` — same, via `ToJson` serialization of typed values
- `apply_patch(root, patch)` — apply one `PatchOp`, return new `Json`
- `apply_patches(root, patches)` — apply a sequence, return new `Json`
- `apply_to_value(value, patches)` — apply patches to a typed value via `ToJson`/`FromJson`

Patch format (both enums are `pub(all)` with `ToJson`/`FromJson`):

- `PathSegment`: `Field(String)` | `Index(Int)`
- `PatchOp`: `Set` | `Remove` | `Insert` | `Delete` | `Move`

`Insert` / `Delete` / `Move` are only emitted for **keyed arrays** — arrays
where every element is a JSON object with a unique string `"id"` field.
Plain arrays fall back to positional `Set` patches.

## Import

```
import {
  "tiye/recollect" @recollect,
}
```

## Json example

```moonbit nocheck
let before : Json = {
  "todos": [{ "id": "t-1", "title": "A", "done": false }],
}

let after : Json = {
  "todos": [
    { "id": "t-1", "title": "A", "done": true },
    { "id": "t-2", "title": "B", "done": false },
  ],
}

let patches = @recollect.diff_json(before, after)
let rebuilt = @recollect.apply_patches(before, patches)
// rebuilt == after
```

## Typed value example

```moonbit nocheck
struct Todo {
  id : String
  title : String
  done : Bool
} derive(FromJson, ToJson)

struct AppState {
  todos : Array[Todo]
} derive(FromJson, ToJson)

let before = AppState::{ todos: [{ id: "t-1", title: "A", done: false }] }
let after  = AppState::{ todos: [
  { id: "t-1", title: "A", done: true },
  { id: "t-2", title: "B", done: false },
] }

let patches = @recollect.diff_value(before, after)
let rebuilt : AppState = @recollect.apply_to_value(before, patches)
  catch { _ => before }
// rebuilt == after
```}

let after : Json = {
  "todos": [
    { "id": "t-1", "title": "A", "done": true },
    { "id": "t-2", "title": "B", "done": false },
  ],
}

let patches = @recollect.diff_json(before, after)
let rebuilt = @recollect.apply_patches(before, patches)
```

## Typed value example

```moonbit
struct Todo {
  id : String
  title : String
  done : Bool
} derive(FromJson, ToJson)

struct AppState {
  todos : Array[Todo]
} derive(FromJson, ToJson)

let before = {
  todos: [{ id: "t-1", title: "A", done: false }],
}

let after = {
  todos: [
    { id: "t-1", title: "A", done: true },
    { id: "t-2", title: "B", done: false },
  ],
}

let patches = @recollect.diff_value(before, after)
let rebuilt : AppState = @recollect.apply_to_value(before, patches)
```

## Validation

Run the package test suite with:

```bash
moon test ./recollect
```

## Keyed array behavior

When both old and new arrays are arrays of objects with unique string `id` fields, `recollect` diffs them by identity instead of position. That allows move/delete/insert patches to stay local instead of rewriting neighboring items.

If elements do not expose unique string `id` values, arrays fall back to positional diffing.

## Extraction notes

This package is already arranged so it can be published on its own later:

- no imports from `app/*`, `cmd/*`, or example packages
- package-level docs live next to the implementation
- tests exercise both the JSON-first API and typed round-trips

If you later want to publish only `recollect`, the simplest path is to move the `recollect/` directory into a dedicated MoonBit module or workspace root and keep the rest of this repository as the demo/integration repo.
