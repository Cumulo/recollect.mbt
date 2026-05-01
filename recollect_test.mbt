///|
test "json patch applies structural edits" {
  let old_json : Json = {
    "page": { "$tag": "Home" },
    "todos": [
      { "id": "t-1", "title": "A", "done": false },
      { "id": "t-2", "title": "B", "done": false },
    ],
  }
  let new_json : Json = {
    "page": { "$tag": "Detail", "id": "t-2" },
    "draft": "Transport uses Json",
    "todos": [
      { "id": "t-1", "title": "A", "done": true },
      { "id": "t-2", "title": "B", "done": false },
      { "id": "t-3", "title": "C", "done": false },
    ],
  }
  let patches = diff_json(old_json, new_json)
  let patched = apply_patches(old_json, patches)
  assert_eq(patched, new_json)
}

///|
test "keyed array diff deletes removed todo instead of rewriting neighbors" {
  let old_json : Json = {
    "todos": [
      { "id": "t-1", "title": "A", "done": false },
      { "id": "t-2", "title": "B", "done": false },
    ],
  }
  let new_json : Json = {
    "todos": [{ "id": "t-2", "title": "B", "done": false }],
  }
  let patches = diff_json(old_json, new_json)
  assert_true(patches == [Delete(path=[Field("todos")], index=0)])
  let patched = apply_patches(old_json, patches)
  assert_eq(patched, new_json)
}

///|
test "keyed array diff moves todo by id with move patch" {
  let old_json : Json = {
    "todos": [
      { "id": "t-1", "title": "A", "done": false },
      { "id": "t-2", "title": "B", "done": false },
      { "id": "t-3", "title": "C", "done": false },
    ],
  }
  let new_json : Json = {
    "todos": [
      { "id": "t-3", "title": "C", "done": false },
      { "id": "t-1", "title": "A", "done": false },
      { "id": "t-2", "title": "B", "done": false },
    ],
  }
  let patches = diff_json(old_json, new_json)
  assert_true(
    patches == [Move(path=[Field("todos")], from_index=2, to_index=0)],
  )
  let patched = apply_patches(old_json, patches)
  assert_eq(patched, new_json)
}

///|
struct ValueTodo {
  id : String
  title : String
  done : Bool
} derive(Eq, Debug, FromJson, ToJson)

///|
struct ValueState {
  todos : Array[ValueTodo]
  draft : String?
} derive(Eq, Debug, FromJson, ToJson)

///|
test "typed diff_value round-trips through apply_to_value" {
  let before : ValueState = {
    draft: None,
    todos: [
      { id: "t-1", title: "A", done: false },
      { id: "t-2", title: "B", done: false },
    ],
  }
  let after : ValueState = {
    draft: Some("synced"),
    todos: [
      { id: "t-2", title: "B", done: true },
      { id: "t-3", title: "C", done: false },
    ],
  }
  let patches = diff_value(before, after)
  let rebuilt : ValueState = apply_to_value(before, patches)
  assert_true(rebuilt == after)
}

///|
test "patch ops round-trip through json encoding" {
  let patches : Array[PatchOp] = [
    Set(path=[Field("draft")], value=true.to_json()),
    Move(path=[Field("todos")], from_index=2, to_index=0),
    Delete(path=[Field("todos")], index=1),
  ]
  let encoded = patches.to_json()
  let decoded : Array[PatchOp] = @json.from_json(encoded) catch { _ => panic() }
  assert_true(decoded == patches)
}
