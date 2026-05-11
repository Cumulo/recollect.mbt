# recollect

`tiye/recollect` is a structural JSON diff/patch library for MoonBit.

It computes a compact sequence of `PatchOp` operations between two `Json` trees
and applies them to reconstruct the target state. The library is designed for
immutable-data workflows such as Cumulo and Respo, where you want to ship
structural deltas over the network and rebuild the next state locally.

## Why this package exists

`recollect` is built for state synchronization in immutable applications:

- compute diffs from an old state to a new state
- serialize patches for transport
- apply patches without mutating the previous value
- preserve structural sharing on unchanged subtrees

That makes it suitable for render loops and server/client sync models that rely
on stable equality checks and replacing the whole root value.

## Immutable data behavior

- `diff_json` / `diff_value` are read-only
- `apply_patch` / `apply_patches` / `apply_to_value` always return a new value
- unchanged branches are structurally shared with the original tree
- the input value is never mutated in place

```/dev/null/example.mbt#L1-4
let new_remote = @recollect.apply_to_value(old_remote, patches)
  catch { _ => old_remote }

// old_remote is still untouched
```

> Do not keep your app state inside a mutable wrapper and patch it in place.
> Replace the whole value with the newly returned one, otherwise structural
> equality-based update logic may stop working correctly.

## API

- `diff_json(old, new)` — compute `Array[PatchOp]` between two `Json` trees
- `diff_value(old, new)` — compute patches after serializing typed values with `ToJson`
- `apply_patch(root, patch)` — apply one `PatchOp`, return new `Json`
- `apply_patches(root, patches)` — apply a sequence of patches, return new `Json`
- `apply_to_value(value, patches)` — patch a typed value via `ToJson`/`FromJson`

Patch format:

- `PathSegment`: `Field(String)` | `Index(Int)`
- `PatchOp`: `Set` | `Remove` | `Insert` | `Delete` | `Move`

`Insert` / `Delete` / `Move` are only emitted for keyed arrays: arrays whose
items are JSON objects carrying a unique string `"id"` field. Plain arrays fall
back to positional diffing.

## Import

```/dev/null/example.json#L1-3
import {
  "tiye/recollect" @recollect,
}
```

## Json example

```/dev/null/example.mbt#L1-16
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

```/dev/null/example.mbt#L1-21
struct Todo {
  id : String
  title : String
  done : Bool
} derive(FromJson, ToJson)

struct AppState {
  todos : Array[Todo]
} derive(FromJson, ToJson)

let before = AppState::{ todos: [{ id: "t-1", title: "A", done: false }] }
let after = AppState::{ todos: [
  { id: "t-1", title: "A", done: true },
  { id: "t-2", title: "B", done: false },
] }

let patches = @recollect.diff_value(before, after)
let rebuilt : AppState = @recollect.apply_to_value(before, patches)
  catch { _ => before }
// rebuilt == after
```

## Implementation notes

The core algorithm in `recollect` works on `Json` trees.

This is intentional, but it also reflects a current limitation of MoonBit:
there is no built-in macro system or runtime reflection that lets the library
generate a generic field-level diff/patch implementation directly for arbitrary
user-defined structs.

Because of that, the typed API is currently implemented as a JSON round trip:

- `diff_value(a, b)` = `a.to_json()` + `b.to_json()` + `diff_json(...)`
- `apply_to_value(value, patches)` = `value.to_json()` + `apply_patches(...)` + `from_json()`

So the patch format is effectively a JSON-path-based structural delta.

### Trade-off

This design keeps the library generic and simple to integrate with any type that
implements `ToJson` / `FromJson`, but it also means the typed API pays extra
cost in:

- serialization
- deserialization
- intermediate `Json` allocation
- rebuilding typed values from patched `Json`

In practice, the main overhead is usually not the patch list itself, but the
struct ↔ JSON conversion around it.

If you care about throughput on large states, prefer these guidelines:

- use `diff_json` / `apply_patches` when your data is already represented as `Json`
- use the typed API when convenience and integration matter more than raw speed
- expect `apply_to_value` to be noticeably more expensive than raw JSON patching

Benchmark notes and measurements live in `bench/BENCH_REPORT.md`.

## Keyed array behavior

When both old and new arrays are arrays of objects with unique string `id`
fields, `recollect` diffs them by identity instead of position. That allows
local `Move` / `Insert` / `Delete` operations instead of rewriting neighboring
items.

If array elements do not expose unique string `id` values, the library falls
back to positional diffing.

## Validation

Run checks locally with:

```/dev/null/example.sh#L1-2
moon check
moon test
```

## Notes for extraction and publishing

This package is already organized as a standalone MoonBit module:

- package docs live next to the implementation
- tests cover both JSON-first APIs and typed round trips
- benchmark fixtures and reports are kept under `bench/`

If MoonBit later provides stronger compile-time metaprogramming support,
`recollect` can evolve toward a more direct typed diff/patch path with less
JSON conversion overhead. For now, the JSON-path-based approach is the portable
implementation that works across user-defined data types.