# recollect

`tiye/cumulo/recollect` is the standalone structural diff/patch package extracted from the larger Cumulo demo.

It is intentionally kept as a leaf package inside this repository so it can be split into its own module later with minimal work.

It focuses on a small JSON-first API:

- `diff_json(old_json, new_json)` computes structural patch operations between two `Json` trees.
- `diff_value(old_value, new_value)` computes patches from typed MoonBit values via `ToJson`.
- `apply_patch(root, patch)` applies a single patch operation to a `Json` tree.
- `apply_patches(root, patches)` applies a patch sequence to a `Json` tree.
- `apply_to_value(value, patches)` applies patches to a typed MoonBit value via `ToJson` and `FromJson`.

The patch format is exposed through two public enums:

- `PathSegment`: `Field(String)` and `Index(Int)`
- `PatchOp`: `Set`, `Remove`, `Insert`, `Delete`, `Move`

Current package boundary:

- source: `recollect/recollect.mbt`
- tests: `recollect/recollect_test.mbt`
- only dependency: `moonbitlang/core/json`

## Import

Add the package to a `moon.pkg` import list:

```moonbit
import {
  "tiye/cumulo/recollect" @recollect,
}
```

## Json example

```moonbit
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
